#!/bin/bash
# Archives Versely (Release) and uploads it to App Store Connect for
# TestFlight, in one step. Uses the Apple Account signed in to Xcode
# (Xcode › Settings › Accounts), so no passwords or keys are needed here.
#
# Usage:
#   ./Scripts/testflight.sh              checks, unit tests, archive, upload
#   ./Scripts/testflight.sh --no-tests   skip the unit tests
#   ./Scripts/testflight.sh --no-upload  archive and export only (to check signing)
#
# The build number is the date and time (e.g. 202610141205), so every upload
# is newer than the last without editing project.yml. The version shown to
# testers is MARKETING_VERSION in project.yml.
set -uo pipefail
cd "$(dirname "$0")/.."

RUN_TESTS=true
UPLOAD=true
while [ $# -gt 0 ]; do
    case "$1" in
        --no-tests) RUN_TESTS=false ;;
        --no-upload) UPLOAD=false ;;
    esac
    shift
done

OUT=build/TestFlight
ARCHIVE="$OUT/Versely.xcarchive"
LOG="$OUT/testflight.log"
BUILD_NUMBER=$(date +%Y%m%d%H%M)
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)
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

echo "Versely $VERSION ($BUILD_NUMBER) for TestFlight"
echo "Using $(xcodebuild -version | head -1)"

# 1. Things a TestFlight build needs that a Simulator build doesn't.
echo "1. Checking setup..."
[ -f Config/Signing.xcconfig ] || fail "Config/Signing.xcconfig is missing." "Copy Config/Signing.example.xcconfig and add your Team ID (APPLE_SETUP.md, step 1)."
TEAM=$(awk -F'= *' '/^DEVELOPMENT_TEAM/ { gsub(/[ \t]/, "", $2); print $2 }' Config/Signing.xcconfig)
{ [ -z "$TEAM" ] || [ "$TEAM" = "YOURTEAMID" ]; } && fail "No Team ID in Config/Signing.xcconfig." "Set DEVELOPMENT_TEAM (developer.apple.com → Account → Membership details)."
[ -f Config/Secrets.xcconfig ] || fail "Config/Secrets.xcconfig is missing." "Without it the TestFlight build has no sync, sign-in or crash reports. Copy Config/Secrets.example.xcconfig and fill it in."
for key in SUPABASE_URL SUPABASE_ANON_KEY; do
    value=$(awk -F'= *' -v k="$key" '$1 ~ "^"k"[ \t]*$" { print $2 }' Config/Secrets.xcconfig | tr -d ' \t')
    [ -n "$value" ] || fail "$key is empty in Config/Secrets.xcconfig." "Testers couldn't sign in or sync."
done
command -v xcodegen >/dev/null || fail "XcodeGen isn't installed." "brew install xcodegen"
if ! xcodebuild -showsdks 2>/dev/null | grep -q watchos; then
    fail "The watchOS platform isn't installed." "The Apple Watch app is part of every build: Xcode › Settings › Components › watchOS."
fi
echo "   Team $TEAM, secrets and signing found."

# 2. Project.
echo "2. Generating the project..."
xcodegen generate >> "$LOG" 2>&1 || fail "xcodegen failed."

# 3. Unit tests (the fast ones; UI tests stay with ./Scripts/build.sh --ui).
if [ "$RUN_TESTS" = true ]; then
    echo "3. Running unit tests..."
    SIM_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for runtime, ds in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in ds]
pick = next((d for d in devices if d["name"].startswith("iPhone Duo")), None) or next((d for d in devices if d["name"].startswith("iPhone")), None)
print(pick["udid"] if pick else "")')
    [ -n "$SIM_ID" ] || fail "No iPhone simulator found for the unit tests." "Run with --no-tests, or install one in Xcode."
    xcodebuild test -project Genesis.xcodeproj -scheme Genesis -destination "id=$SIM_ID" \
        -derivedDataPath build/DerivedData -quiet >> "$LOG" 2>&1 \
        || fail "Unit tests failed, so nothing was uploaded." "Fix them (./Scripts/build.sh shows details) or run with --no-tests."
    echo "   Unit tests passed."
else
    echo "3. Skipping unit tests."
fi

# 4. Archive (Release, real devices). Automatic signing creates or updates
#    the distribution certificate and profiles for the app, widgets and watch.
echo "4. Archiving (a few minutes)..."
rm -rf "$ARCHIVE"
xcodebuild archive -project Genesis.xcodeproj -scheme Genesis -configuration Release \
    -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" >> "$LOG" 2>&1 \
    || fail "Archiving failed." "Signing problems usually mean Xcode › Settings › Accounts isn't signed in to the team, or an App ID is missing a capability (APPLE_SETUP.md, step 1)."
echo "   Archived: $ARCHIVE"

# 5. Upload (or export only).
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

if [ "$UPLOAD" = true ]; then
    echo "5. Uploading to App Store Connect..."
else
    echo "5. Exporting (not uploading)..."
fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/Export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates >> "$LOG" 2>&1 \
    || fail "The upload failed." "Check that the app exists in App Store Connect with bundle id com.7twenty8studio.versely (APPLE_SETUP.md, step 5)."

echo ""
if [ "$UPLOAD" = true ]; then
    echo "✅ Uploaded Versely $VERSION ($BUILD_NUMBER)."
    echo "   Apple emails you when it has processed (10–30 min). Then:"
    echo "   App Store Connect → Versely → TestFlight → choose the build for your testers."
else
    echo "✅ Exported to $OUT/Export (not uploaded)."
fi
