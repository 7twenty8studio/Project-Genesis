#!/bin/bash
# Builds Genesis, runs the unit tests and launches the app in the Simulator.
# Prefers the iPhone Duo simulator (Xcode 27.1 or later).
# Writes every compiler error to build-errors.txt so it can be shared easily.
#
# Usage:
#   ./Scripts/build.sh              build, unit tests, launch in the Simulator
#   ./Scripts/build.sh --open       same, then open the project in Xcode
#   ./Scripts/build.sh --no-tests   build and launch only
#   ./Scripts/build.sh --ui         also run the UI tests: iPhone Duo (folded and open),
#                                   iPhone Pro (portrait and landscape) and iPad
#   ./Scripts/build.sh --ui-full    also the open Duo in landscape, large text, dark
#                                   theme, scroll mode, page curl and launch time
#   --workers N                     UI test copies per simulator (default: chosen
#                                   from your Mac's memory; 1 = one at a time)
#   --only Phase3UITests            run only these UI tests (a class, or
#                                   Class/testMethod); repeat for more
#   --watch                         also build the Apple Watch app (needs the watchOS
#                                   platform: Xcode › Settings › Components)
#   --clean                         first free disk space: this project's build
#                                   folder, old test results, leftover test copies of
#                                   simulators and simulators Xcode can't use any more
#   SIMULATOR="iPhone 17 Pro" ./Scripts/build.sh   use a specific simulator
set -uo pipefail
cd "$(dirname "$0")/.."

OPEN_XCODE=false
RUN_TESTS=true
UI_TESTS=none
WORKERS=""
ONLY=()
CLEAN=false
WATCH=false
while [ $# -gt 0 ]; do
    case "$1" in
        --open) OPEN_XCODE=true ;;
        --no-tests) RUN_TESTS=false ;;
        --ui) UI_TESTS=standard ;;
        --ui-full) UI_TESTS=full ;;
        --workers) WORKERS=${2:-}; shift ;;
        --clean) CLEAN=true ;;
        --watch) WATCH=true ;;
        --only)
            [ "$UI_TESTS" = none ] && UI_TESTS=standard
            ONLY+=("-only-testing:GenesisUITests/${2:-}"); shift ;;
    esac
    shift
done

# How many copies of each simulator run UI tests at once. Each copy needs
# roughly 2.5 GB of memory and three simulators run side by side, so the
# default comes from the Mac's memory (leaving 8 GB for macOS and Xcode).
if [ -z "$WORKERS" ]; then
    MEMORY_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 17179869184) / 1073741824 ))
    WORKERS=$(( (MEMORY_GB - 8) * 2 / 15 ))
    [ "$WORKERS" -lt 1 ] && WORKERS=1
    [ "$WORKERS" -gt 4 ] && WORKERS=4
fi

PREFERRED="${SIMULATOR:-iPhone Duo}"
DERIVED=build/DerivedData
BUNDLE_ID=com.7twenty8studio.genesis

echo "Using $(xcodebuild -version | head -1) at $(xcode-select -p)"

# Free space, in GB, on the disk this project is on.
free_gb() { df -Pk . | awk 'NR==2 { printf "%d", $4 / 1048576 }'; }

# 0. Disk space. A full disk makes builds and UI tests fail in confusing ways
#    (simulators won't start, "No space left on device"). --clean removes only
#    things Xcode rebuilds by itself.
if [ "$CLEAN" = true ]; then
    BEFORE=$(free_gb)
    echo "Freeing disk space..."
    rm -rf build/DerivedData build/TestResults
    # Copies of simulators made for parallel UI tests, sometimes left behind.
    xcrun simctl --set testing shutdown all >/dev/null 2>&1
    xcrun simctl --set testing delete all >/dev/null 2>&1
    rm -rf "$HOME/Library/Developer/XCTestDevices"
    # Simulators for iOS versions no longer installed.
    xcrun simctl delete unavailable >/dev/null 2>&1
    echo "   Freed about $(( $(free_gb) - BEFORE )) GB ($(free_gb) GB free now)."
fi
NEEDED_GB=20
[ "$UI_TESTS" = none ] && NEEDED_GB=10
if [ "$(free_gb)" -lt "$NEEDED_GB" ]; then
    echo "❌ Only $(free_gb) GB free on this disk; Genesis needs about $NEEDED_GB GB to build and test."
    if [ "$CLEAN" = false ]; then
        echo "   Run ./Scripts/build.sh --clean first (add --ui as usual)."
    fi
    echo "   Largest Xcode folders on this Mac:"
    du -sh "$HOME/Library/Developer"/{Xcode/DerivedData,Xcode/Archives,"Xcode/iOS DeviceSupport",CoreSimulator/Devices,CoreSimulator/Caches,XCTestDevices} \
        /Library/Developer/CoreSimulator/Volumes 2>/dev/null | sort -rh | sed 's/^/     /'
    echo "   See \"Disk space\" in README.md for what's safe to remove."
    exit 1
fi

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

# The Apple Watch app builds on its own scheme (not embedded in the iPhone app yet).
if [ "$WATCH" = true ]; then
    echo "Building the Apple Watch app..."
    xcodebuild -project Genesis.xcodeproj -scheme GenesisWatch \
        -destination "generic/platform=watchOS Simulator" -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation build 2>&1 | tee -a build.log | grep -E "error:|\*\* BUILD"
    WATCH_STATUS=${PIPESTATUS[0]}
    if [ "$WATCH_STATUS" -ne 0 ]; then
        echo "The watch app didn't build (errors are in build-errors.txt). If it says watchOS isn't installed, add it in Xcode › Settings › Components."
    fi
fi

TEST_STATUS=0
if [ "$BUILD_STATUS" -eq 0 ] && [ "$RUN_TESTS" = true ]; then
    echo "Testing..."
    run_xcodebuild test-without-building
    TEST_STATUS=$?
fi

# 5. Launch the app in the Simulator.
if [ "$BUILD_STATUS" -eq 0 ]; then
    APP="$DERIVED/Build/Products/Debug-iphonesimulator/Genesis.app"
    echo "Launching Genesis on $SIM_NAME..."
    xcrun simctl boot "$SIM_ID" 2>/dev/null
    open -a "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || open -a Simulator
    xcrun simctl install "$SIM_ID" "$APP" && xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null
fi

# 6. UI tests. Each pass runs the suite on a set of simulators in one posture
#    and orientation:
#      duo = iPhone Duo, pro = iPhone Pro, ipad = iPad
#      posture = the Duo's hinge (folded or open), orientation = portrait or landscape
UI_STATUS=0
SKIPPED_PASSES=""
if [ "$BUILD_STATUS" -eq 0 ] && [ "$UI_TESTS" != none ]; then
    sim_id() { echo "$DESTINATIONS" | grep -m1 -E "$1" | cut -d'|' -f1; }
    sim_name() { echo "$DESTINATIONS" | grep -m1 -E "$1" | cut -d'|' -f3; }
    DUO_ID=$(sim_id "\|iPhone Duo$");            DUO_NAME=$(sim_name "\|iPhone Duo$")
    PRO_ID=$(sim_id "\|iPhone [0-9]+ Pro$");     PRO_NAME=$(sim_name "\|iPhone [0-9]+ Pro$")
    IPAD_ID=$(sim_id "\|iPad");                  IPAD_NAME=$(sim_name "\|iPad")

    # Name | devices | Duo posture | orientation | extra launch arguments
    PASSES=(
        "Standard|duo pro ipad|folded|portrait|"
        "Duo open|duo|open|portrait|"
        "Landscape|duo pro|folded|landscape|"
    )
    if [ "$UI_TESTS" = full ]; then
        PASSES+=(
            "Duo open landscape|duo|open|landscape|"
            "Large text|duo pro ipad|folded|portrait|-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityL"
            "Slate theme|duo pro ipad|folded|portrait|-uiTestingTheme slate"
            "Scroll mode|duo pro ipad|folded|portrait|-uiTestingReadingMode scroll"
            "Page curl|duo pro ipad|folded|portrait|-uiTestingPageTurn curl"
        )
    fi

    echo
    echo "UI tests on: ${DUO_NAME:-no iPhone Duo}, ${PRO_NAME:-no iPhone Pro}, ${IPAD_NAME:-no iPad}"
    echo "Workers per simulator: $WORKERS (change with --workers N)"
    [ ${#ONLY[@]} -gt 0 ] && echo "Only: ${ONLY[*]#-only-testing:GenesisUITests/}"
    echo "Building UI tests..."
    xcodebuild -project Genesis.xcodeproj -scheme GenesisUITests \
        -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" \
        -skipPackagePluginValidation build-for-testing 2>&1 | tee -a build.log | grep -E "error:|\*\* (BUILD|TEST)"
    UI_BUILD_STATUS=${PIPESTATUS[0]}
    UI_STATUS=$UI_BUILD_STATUS

    DUO_POSTURE=""
    set_duo_posture() {
        [ -z "$DUO_ID" ] && return 1
        [ "$DUO_POSTURE" = "$1" ] && return 0
        if ./Scripts/duo_hinge.sh "$DUO_ID" "$1"; then
            DUO_POSTURE=$1
            return 0
        fi
        DUO_POSTURE=""
        return 1
    }

    mkdir -p build/TestResults
    for pass in "${PASSES[@]}"; do
        # A failed build stops everything; failed tests don't stop later passes.
        [ "$UI_BUILD_STATUS" -ne 0 ] && break
        IFS='|' read -r NAME DEVICES POSTURE ORIENTATION ARGS <<< "$pass"

        DESTS=()
        for device in $DEVICES; do
            case "$device" in
                duo) [ -n "$DUO_ID" ] && DESTS+=("-destination" "id=$DUO_ID") ;;
                pro) [ -n "$PRO_ID" ] && DESTS+=("-destination" "id=$PRO_ID") ;;
                ipad) [ -n "$IPAD_ID" ] && DESTS+=("-destination" "id=$IPAD_ID") ;;
            esac
        done

        # Fold or unfold the Duo for this pass. A Duo-only pass that can't get
        # the right posture is skipped rather than run in the wrong one.
        EXPECT_POSTURE=""
        if [[ " $DEVICES " == *" duo "* ]] && [ -n "$DUO_ID" ]; then
            if set_duo_posture "$POSTURE"; then
                EXPECT_POSTURE=$POSTURE    # the tests check it on the Duo only
            elif [ "$DEVICES" = duo ]; then
                echo "UI pass: $NAME... skipped (couldn't set the iPhone Duo to $POSTURE)"
                SKIPPED_PASSES="$SKIPPED_PASSES $NAME,"
                continue
            fi
        fi
        if [ ${#DESTS[@]} -eq 0 ]; then
            echo "UI pass: $NAME... skipped (no matching simulator)"
            SKIPPED_PASSES="$SKIPPED_PASSES $NAME,"
            continue
        fi

        SLUG=$(echo "$NAME" | tr ' ' '-')
        RESULT="build/TestResults/UI-$SLUG.xcresult"
        rm -rf "$RESULT"
        echo "UI pass: $NAME..."
        PERF=0
        [ "$UI_TESTS" = full ] && [ "$NAME" = Standard ] && PERF=1
        # Copies of a simulator start folded, so the open-Duo pass runs on the
        # Duo itself, one test at a time.
        PARALLEL=(-parallel-testing-enabled NO)
        if [ "$WORKERS" -gt 1 ] && [ "$POSTURE" != open ]; then
            PARALLEL=(-parallel-testing-enabled YES -parallel-testing-worker-count "$WORKERS")
        fi
        TEST_RUNNER_GENESIS_UI_ARGS="$ARGS" TEST_RUNNER_GENESIS_PERF="$PERF" \
        TEST_RUNNER_GENESIS_ORIENTATION="$ORIENTATION" TEST_RUNNER_GENESIS_POSTURE="$EXPECT_POSTURE" \
        xcodebuild \
            -project Genesis.xcodeproj -scheme GenesisUITests \
            "${DESTS[@]}" -derivedDataPath "$DERIVED" \
            "${PARALLEL[@]}" ${ONLY[@]+"${ONLY[@]}"} \
            -retry-tests-on-failure -test-iterations 2 \
            -resultBundlePath "$RESULT" \
            -skipPackagePluginValidation test-without-building 2>&1 \
            | tee "build/TestResults/UI-$SLUG.log" | tee -a build.log \
            | grep -E "error:|Test Case .* failed|\*\* TEST"
        PASS_STATUS=${PIPESTATUS[0]}
        if [ "$PASS_STATUS" -ne 0 ]; then
            UI_STATUS=$PASS_STATUS
            FAILURES="build/TestResults/UI-$SLUG-failures.txt"
            python3 Scripts/ui_failures.py "$RESULT" > "$FAILURES" 2>/dev/null
            # Nothing named a failed test, so the run itself went wrong (a crash,
            # a simulator that wouldn't start). Keep what xcodebuild said.
            if ! grep -q "\[" "$FAILURES" 2>/dev/null; then
                {
                    echo "-- xcodebuild ($NAME) --"
                    grep -iE "error|fail|crash|unexpected|never began|timed out|lost connection|terminated|exited" \
                        "build/TestResults/UI-$SLUG.log" | grep -v "^ *$" | tail -n 40
                    echo "-- last lines --"
                    tail -n 30 "build/TestResults/UI-$SLUG.log"
                } >> "$FAILURES"
            fi
            if [ -s "$FAILURES" ]; then
                echo "   Failures ($NAME):"
                sed 's/^/     /' "$FAILURES"
                { echo "== UI failures: $NAME =="; cat "$FAILURES"; } >> build.log
            fi
            # Save the screenshots and screen layouts kept for failed tests, so
            # they can be sent back without opening Xcode. (Passing tests keep no
            # attachments, so this exports only what the failures left.)
            SHOTS="build/TestResults/UI-$SLUG-screenshots"
            rm -rf "$SHOTS" "$SHOTS.zip"
            if xcrun xcresulttool export attachments --path "$RESULT" --output-path "$SHOTS" >/dev/null 2>&1 \
                && [ -n "$(ls -A "$SHOTS" 2>/dev/null | grep -v '^manifest.json$')" ]; then
                # Keep the pictures and text; screen recordings and Xcode's binary
                # snapshots make the zip ten times bigger and aren't needed.
                find "$SHOTS" -type f \( -name "*.mp4" -o ! -name "*.*" \) -delete
                (cd build/TestResults && zip -qr "$(basename "$SHOTS").zip" "$(basename "$SHOTS")")
                echo "   Screenshots of each failure: $SHOTS.zip"
            else
                echo "   Screenshots of each failure: open $RESULT in Xcode."
            fi
        fi
    done

    # Leave the Duo folded, the way it starts.
    [ "$DUO_POSTURE" = open ] && set_duo_posture folded >/dev/null
fi

grep -E "error:" build.log | sort -u > build-errors.txt

echo
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "❌ Build failed ($(wc -l < build-errors.txt | tr -d ' ') error lines)."
    echo "   Send build-errors.txt (or build.log if it's empty) back to Claude."
elif [ "$TEST_STATUS" -ne 0 ]; then
    echo "⚠️  The app built and launched, but some tests failed."
    echo "   Send build.log back to Claude."
elif [ "${UI_BUILD_STATUS:-0}" -ne 0 ]; then
    echo "❌ The app built and unit tests passed, but the UI tests didn't compile."
    echo "   Send build-errors.txt back to Claude."
elif [ "$UI_STATUS" -ne 0 ]; then
    echo "⚠️  The app built and unit tests passed, but some UI tests failed."
    echo "   Send the UI-*-failures.txt and UI-*-screenshots.zip files in build/TestResults back to Claude."
else
    echo "✅ Build succeeded$([ "$RUN_TESTS" = true ] && echo " and all tests passed")$([ "$UI_TESTS" != none ] && echo ", including UI tests")."
    if [ -n "$SKIPPED_PASSES" ]; then
        echo "   Not run:${SKIPPED_PASSES%,} (see the messages above)."
    fi
    rm -f build-errors.txt
fi

if [ "$OPEN_XCODE" = true ]; then
    open Genesis.xcodeproj
fi

[ "$BUILD_STATUS" -ne 0 ] && exit "$BUILD_STATUS"
[ "$TEST_STATUS" -ne 0 ] && exit "$TEST_STATUS"
exit "$UI_STATUS"
