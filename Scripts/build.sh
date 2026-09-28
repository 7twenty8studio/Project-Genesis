#!/bin/bash
# Generates the Xcode project, builds Genesis and runs the tests on a simulator.
# Writes every compiler error to build-errors.txt so it can be shared easily.
#
# Usage:  ./Scripts/build.sh          build and test
#         ./Scripts/build.sh --open   also open the project in Xcode afterwards
set -uo pipefail
cd "$(dirname "$0")/.."

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
    echo "Note: Config/Secrets.xcconfig not found. The app will build, but crash reporting stays off."
fi

echo "Generating Genesis.xcodeproj..."
xcodegen generate --quiet || exit 1

SIMULATOR=$(xcrun simctl list devices available | grep -m1 -oE "iPhone [0-9]+ Pro( Max)? \(" | sed 's/ ($//')
if [ -z "$SIMULATOR" ]; then
    SIMULATOR=$(xcrun simctl list devices available | grep -m1 -oE "iPhone [^()]+ \(" | sed 's/ ($//')
fi
if [ -z "$SIMULATOR" ]; then
    echo "No iPhone simulator found. Open Xcode > Settings > Components and install an iOS simulator."
    exit 1
fi
echo "Building and testing on: $SIMULATOR"

xcodebuild \
    -project Genesis.xcodeproj \
    -scheme Genesis \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -skipPackagePluginValidation \
    test 2>&1 | tee build.log | grep -E "error:|warning: .*Genesis/|Test (Suite|Case).*(passed|failed)|✔|✘|\*\* (BUILD|TEST)"

STATUS=${PIPESTATUS[0]}
grep -E "error:" build.log | sort -u > build-errors.txt

echo
if [ "$STATUS" -eq 0 ]; then
    echo "✅ Build and tests succeeded."
    rm -f build-errors.txt
else
    COUNT=$(wc -l < build-errors.txt | tr -d ' ')
    echo "❌ Build or tests failed ($COUNT error lines)."
    echo "   Send build-errors.txt (or build.log if it's empty) back to Claude."
fi

if [ "${1:-}" = "--open" ]; then
    open Genesis.xcodeproj
fi
exit "$STATUS"
