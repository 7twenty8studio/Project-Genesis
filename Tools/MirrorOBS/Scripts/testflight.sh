#!/bin/bash
# Archives Mirror OBS (Release) and uploads it to App Store Connect for
# TestFlight, in one step. Uses the Apple Account signed in to Xcode
# (Xcode › Settings › Accounts), so no passwords or keys are needed here.
#
# Usage (from Tools/MirrorOBS):
#   ./Scripts/testflight.sh              archive and upload
#   ./Scripts/testflight.sh --no-upload  archive and export only (to check signing)
#
# The build number is the date and time (e.g. 202611241705), so every upload
# is newer than the last. The version testers see is MARKETING_VERSION in
# project.yml (1.0.0).
set -uo pipefail
cd "$(dirname "$0")/.."

UPLOAD=true
[ "${1:-}" = "--no-upload" ] && UPLOAD=false

OUT=build/TestFlight
ARCHIVE="$OUT/MirrorOBS.xcarchive"
LOG="$OUT/testflight.log"
BUILD_NUMBER=$(date +%Y%m%d%H%M)
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
TEAM=$(awk '/DEVELOPMENT_TEAM:/ { print $2; exit }' project.yml)
mkdir -p "$OUT"
: > "$LOG"

fail() {
    echo ""
    echo "❌ $1"
    [ -n "${2:-}" ] && echo "   $2"
    echo "   Full log: $LOG"
    grep -E "error:|Error Domain|No profiles|requires a provisioning|No Accounts" "$LOG" | sort -u | head -15 > build-errors.txt
    [ -s build-errors.txt ] && { echo ""; echo "First errors (also in build-errors.txt):"; cat build-errors.txt; }
    exit 1
}

echo "Mirror OBS $VERSION ($BUILD_NUMBER) for TestFlight, team $TEAM"
echo "Using $(xcodebuild -version | head -1)"

echo "1. Generating the project..."
command -v xcodegen >/dev/null || fail "XcodeGen isn't installed." "brew install xcodegen"
xcodegen generate >> "$LOG" 2>&1 || fail "xcodegen failed."

echo "2. Archiving (a few minutes)..."
rm -rf "$ARCHIVE"
xcodebuild archive -project MirrorOBS.xcodeproj -scheme MirrorOBS -configuration Release \
    -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" >> "$LOG" 2>&1 \
    || fail "Archiving failed." "Signing problems usually mean Xcode › Settings › Accounts isn't signed in to the team, or an App ID or the App Group is missing (README, App Store Connect checklist)."
echo "   Archived: $ARCHIVE"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>$([ "$UPLOAD" = true ] && echo upload || echo export)</string>
    <key>teamID</key>
    <string>$TEAM</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>testFlightInternalTestingOnly</key>
    <false/>
</dict>
</plist>
PLIST

if [ "$UPLOAD" = true ]; then echo "3. Uploading to App Store Connect..."; else echo "3. Exporting (not uploading)..."; fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/Export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates >> "$LOG" 2>&1 \
    || fail "The upload failed." "Check that the app exists in App Store Connect with bundle id com.7twenty8studio.mirrorobs (README, step 2)."

echo ""
if [ "$UPLOAD" = true ]; then
    echo "✅ Uploaded Mirror OBS $VERSION ($BUILD_NUMBER)."
    echo "   Apple emails you when it has processed (10–30 min). Then:"
    echo "   App Store Connect → Mirror OBS → TestFlight → choose the build for your testers."
else
    echo "✅ Exported to $OUT/Export (not uploaded)."
fi
