#!/bin/bash
# Builds Genesis, runs the unit tests and launches the app in the Simulator.
# Prefers the iPhone Duo simulator (Xcode 27.1 or later).
# Writes every compiler error to build-errors.txt so it can be shared easily.
#
# Usage:
#   ./Scripts/build.sh              build, test, launch in the Simulator
#   ./Scripts/build.sh --open       same, then open the project in Xcode
#   ./Scripts/build.sh --no-tests   build and launch only
#   SIMULATOR="iPhone 17 Pro" ./Scripts/build.sh   use a specific simulator
set -uo pipefail
cd "$(dirname "$0")/.."

OPEN_XCODE=false
RUN_TESTS=true
for arg in "$@"; do
    case "$arg" in
        --open) OPEN_XCODE=true ;;
        --no-tests) RUN_TESTS=false ;;
    esac
done

PREFERRED="${SIMULATOR:-iPhone Duo}"
DERIVED=build/DerivedData
BUNDLE_ID=com.7twenty8studio.genesis

echo "Using $(xcodebuild -version | head -1) at $(xcode-select -p)"

# 1. XcodeGen generates the project from project.yml.
if ! command -v xcodegen >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "Installing XcodeGen with Homebrew..."
        brew install xcodegen || exit 1
    else
        echo "XcodeGen is required. Install Homebrew (https://brew.sh), then run: brew install xcodegen"
        exit 1
    fi
fi
if [ ! -f Config/Secrets.xcconfig ]; then
    echo "Note: Config/Secrets.xcconfig not found. The app builds, but crash reporting stays off."
fi
echo "Generating Genesis.xcodeproj..."
xcodegen generate --quiet || exit 1

# 2. Find iOS simulators this Xcode can actually build for.
eligible_simulators() {
    # Lines look like: { platform:iOS Simulator, arch:arm64, id:ABC, OS:27.2, name:iPhone Duo }
    xcodebuild -project Genesis.xcodeproj -scheme Genesis -showdestinations 2>/dev/null \
        | sed '/Ineligible destinations/,$d' \
        | grep "platform:iOS Simulator" \
        | grep -v "placeholder" \
        | sed -E 's/.*id:([^,]+),.*OS:([^,]+),.*name:([^}]+[^ }]).*/\1|\2|\3/' \
        | sort -t'|' -k2 -r
}

DESTINATIONS=$(eligible_simulators)

if [ -z "$DESTINATIONS" ]; then
    echo
    echo "This Xcode has no iOS simulator platform installed, so there's nothing to build for."
    echo "It's a one-time download of several GB (same as Xcode > Settings > Components > iOS)."
    read -r -p "Download it now? [y/N] " answer
    if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        xcodebuild -downloadPlatform iOS || exit 1
        DESTINATIONS=$(eligible_simulators)
    else
        echo "Run this when ready, then re-run the script:  xcodebuild -downloadPlatform iOS"
        exit 1
    fi
fi

# 3. If the iPhone Duo device type exists but no Duo simulator has been made, create one.
if [ "$PREFERRED" = "iPhone Duo" ] && ! echo "$DESTINATIONS" | grep -q "|iPhone Duo$"; then
    DUO_TYPE=$(xcrun simctl list devicetypes | grep -m1 "^iPhone Duo (" | sed -E 's/.*\((.*)\)/\1/')
    RUNTIME=$(xcrun simctl list runtimes available | grep -E "^iOS 27\.[1-9]" | tail -1 | grep -oE "com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+")
    if [ -n "$DUO_TYPE" ] && [ -n "$RUNTIME" ]; then
        echo "Creating an iPhone Duo simulator..."
        xcrun simctl create "iPhone Duo" "$DUO_TYPE" "$RUNTIME" >/dev/null && DESTINATIONS=$(eligible_simulators)
    else
        echo "No iPhone Duo simulator available. It needs Xcode 27.1 or later with the iOS 27.1+ simulator."
    fi
fi

PICK=$(echo "$DESTINATIONS" | grep -m1 "|$PREFERRED$")
[ -z "$PICK" ] && PICK=$(echo "$DESTINATIONS" | grep -m1 -E "\|iPhone [0-9]+ Pro$")
[ -z "$PICK" ] && PICK=$(echo "$DESTINATIONS" | grep -m1 "|iPhone")
[ -z "$PICK" ] && PICK=$(echo "$DESTINATIONS" | head -1)

SIM_ID=${PICK%%|*}
SIM_NAME=${PICK##*|}
SIM_OS=$(echo "$PICK" | cut -d'|' -f2)
echo "Simulator: $SIM_NAME (iOS $SIM_OS)"

# 4. Build, then test.
run_xcodebuild() {
    xcodebuild \
        -project Genesis.xcodeproj \
        -scheme Genesis \
        -destination "id=$SIM_ID" \
        -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation \
        "$@" 2>&1 | tee -a build.log | grep -E "error:|Test (Suite|Case).*(passed|failed)|✔|✘|\*\* (BUILD|TEST)"
    return "${PIPESTATUS[0]}"
}

rm -f build.log
echo "Building..."
run_xcodebuild build-for-testing
BUILD_STATUS=$?

TEST_STATUS=0
if [ "$BUILD_STATUS" -eq 0 ] && [ "$RUN_TESTS" = true ]; then
    echo "Testing..."
    run_xcodebuild test-without-building
    TEST_STATUS=$?
fi

grep -E "error:" build.log | sort -u > build-errors.txt

# 5. Launch the app in the Simulator.
if [ "$BUILD_STATUS" -eq 0 ]; then
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/Genesis.app"
    echo "Launching Genesis on $SIM_NAME..."
    xcrun simctl boot "$SIM_ID" 2>/dev/null
    open -a Simulator
    xcrun simctl install "$SIM_ID" "$APP" && xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null
fi

echo
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "❌ Build failed ($(wc -l < build-errors.txt | tr -d ' ') error lines)."
    echo "   Send build-errors.txt (or build.log if it's empty) back to Claude."
elif [ "$TEST_STATUS" -ne 0 ]; then
    echo "⚠️  The app built and launched, but some tests failed."
    echo "   Send build.log back to Claude."
else
    echo "✅ Build succeeded$([ "$RUN_TESTS" = true ] && echo " and all tests passed")."
    rm -f build-errors.txt
fi

if [ "$OPEN_XCODE" = true ]; then
    open Genesis.xcodeproj
fi

[ "$BUILD_STATUS" -eq 0 ] && exit "$TEST_STATUS" || exit "$BUILD_STATUS"
