#!/usr/bin/env bash
# Records the launch-day feature demos (GenesisUITests/DemoReelUITests) on an
# iPhone 18 Pro Max simulator: about ten seconds of real use per feature (Themes and
# Pages are a few short films each, joined afterwards), with demo data and
# a 9:41 status bar. Nothing is tested and nothing leaves the Mac.
#
#   ./Scripts/record_demos.sh                 every demo
#   ./Scripts/record_demos.sh 03 08           only demos 03 and 08 (retakes)
#   SIMULATOR="iPhone 17 Pro Max" ./Scripts/record_demos.sh
#
# Output: build/Demos/<NN-name>.mp4 and build/Demos/marks/*.json (when each
# demo starts and ends, and where it taps), zipped in parts (build/Demos.zip, Demos.z01…) to send back.
set -uo pipefail
cd "$(dirname "$0")/.."

DERIVED=build/DerivedData
OUT=build/Demos
MARKS="$PWD/$OUT/marks"
mkdir -p "$OUT" "$MARKS"

DEMOS=(
  "01|testDemo01aAutumn|01a-autumn"
  "01|testDemo01bWinter|01b-winter"
  "01|testDemo01cForest|01c-forest"
  "01|testDemo01dStarlight|01d-starlight"
  "02|testDemo02Ambient|02-ambient"
  "03|testDemo03aCurl|03a-curl"
  "03|testDemo03bScroll|03b-scroll"
  "04|testDemo04Highlights|04-highlights"
  "05|testDemo05Timeline|05-timeline"
  "06|testDemo06Map|06-map"
  "07|testDemo07People|07-people"
  "08|testDemo08Original|08-original"
  "09|testDemo09Parallel|09-parallel"
  "10|testDemo10Memorize|10-memorize"
  "11|testDemo11Groups|11-groups"
  "14|testDemo14SermonOpens|14-sermon-open"
  "15|testDemo15SermonFollow|15-sermon-follow"
)
WANT=" $* "

command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen is needed: brew install xcodegen"; exit 1; }
echo "Generating Genesis.xcodeproj..."
xcodegen generate --quiet || exit 1

# The iPhone 18 Pro Max (or SIMULATOR), else the newest Pro Max or Pro.
DESTS=$(xcodebuild -project Genesis.xcodeproj -scheme GenesisUITests -showdestinations 2>/dev/null \
  | sed '/Ineligible destinations/,$d' | grep "platform:iOS Simulator" | grep -v placeholder \
  | sed -E 's/.*id:([^,]+),.*OS:([^,]+),.*name:([^}]+[^ }]).*/\1|\2|\3/' | sort -t'|' -k2 -r)
PICK=""
PICK=$(echo "$DESTS" | grep -m1 "|${SIMULATOR:-iPhone 18 Pro Max}$")
[ -z "$PICK" ] && PICK=$(echo "$DESTS" | grep -m1 -E "\|iPhone [0-9]+ Pro Max$")
[ -z "$PICK" ] && PICK=$(echo "$DESTS" | grep -m1 -E "\|iPhone [0-9]+ Pro$")
[ -z "$PICK" ] && { echo "No iPhone Pro simulator found. Add one in Xcode › Window › Devices and Simulators."; exit 1; }
SIM_ID=${PICK%%|*}
echo "Recording on: ${PICK##*|} (iOS $(echo "$PICK" | cut -d'|' -f2))"

xcrun simctl boot "$SIM_ID" 2>/dev/null
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$SIM_ID" 2>/dev/null
xcrun simctl ui "$SIM_ID" appearance light
xcrun simctl status_bar "$SIM_ID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100

echo "Building the app and the demo scripts..."
xcodebuild -project Genesis.xcodeproj -scheme GenesisUITests -destination "id=$SIM_ID" \
  -derivedDataPath "$DERIVED" -skipPackagePluginValidation build-for-testing > "$OUT/build.log" 2>&1 \
  || { grep -E "error:" "$OUT/build.log" | head -20; echo "The build failed. Send $OUT/build.log."; exit 1; }

# A full run starts clean, so no film from an older version of the demos is sent back.
if [ "$WANT" = "  " ]; then rm -f "$OUT"/*.mp4 "$MARKS"/*; find "$OUT" -maxdepth 1 -name "*.log" ! -name build.log -delete; fi

now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }
FAILED=""
for entry in "${DEMOS[@]}"; do
  IFS='|' read -r NUM TEST FILE <<< "$entry"
  if [ "$WANT" != "  " ] && [[ "$WANT" != *" $NUM "* ]]; then continue; fi
  echo "Recording $FILE..."
  rm -f "$OUT/$FILE.mp4"
  xcrun simctl io "$SIM_ID" recordVideo --codec=h264 --force "$OUT/$FILE.mp4" > /dev/null 2>&1 &
  REC=$!
  sleep 1.5
  now > "$MARKS/$FILE.recording-start"
  TEST_RUNNER_GENESIS_DEMO=1 TEST_RUNNER_GENESIS_DEMO_MARKS="$MARKS" \
  xcodebuild -project Genesis.xcodeproj -scheme GenesisUITests -destination "id=$SIM_ID" \
    -derivedDataPath "$DERIVED" -skipPackagePluginValidation \
    -only-testing:"GenesisUITests/DemoReelUITests/$TEST" test-without-building > "$OUT/$FILE.log" 2>&1 \
    || FAILED="$FAILED $FILE"
  kill -INT "$REC" 2>/dev/null
  wait "$REC" 2>/dev/null
done

xcrun simctl status_bar "$SIM_ID" clear
# Zipped in parts of at most 400 MB, since uploads stop at 480 MB.
rm -f build/Demos.zip build/Demos.z[0-9][0-9]
(cd build && zip -qr -s 400m Demos.zip Demos -x "Demos/build.log")
echo
echo "Done: $OUT. Send back every part:"
ls -1 build/Demos.z* | sed 's/^/  /'
[ -n "$FAILED" ] && echo "These had a problem (their .log files say why):$FAILED"
exit 0
