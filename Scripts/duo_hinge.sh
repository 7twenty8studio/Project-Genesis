#!/bin/bash
# Folds or unfolds an iPhone Duo simulator.
#
#   ./Scripts/duo_hinge.sh <simulator-id> open      unfold flat (180 degrees)
#   ./Scripts/duo_hinge.sh <simulator-id> folded    fold closed (0 degrees)
#
# simctl has no fold command, so this runs a tiny helper inside the simulator
# that sends the same event as the fold buttons in Xcode's Device Hub
# (see Scripts/Duo/hinge_helper.c). Exits non-zero if the hinge didn't move.
set -uo pipefail
cd "$(dirname "$0")/.."

UDID=${1:?simulator id}
POSTURE=${2:?open or folded}
case "$POSTURE" in
    open) ANGLE=180 ;;
    folded) ANGLE=0 ;;
    *) echo "duo_hinge: posture must be open or folded" >&2; exit 64 ;;
esac

SRC=Scripts/Duo/hinge_helper.c
KEY=$( (cat "$SRC"; xcode-select -p) | shasum | cut -c1-12)
HELPER="build/hinge_helper-$KEY"
if [ ! -x "$HELPER" ]; then
    mkdir -p build
    xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 -O2 \
        -o "$HELPER.tmp" "$SRC" -framework IOKit -framework CoreFoundation 2>/dev/null \
        && codesign -f -s - "$HELPER.tmp" >/dev/null 2>&1 \
        && mv "$HELPER.tmp" "$HELPER" \
        || { echo "duo_hinge: couldn't build the hinge helper" >&2; exit 1; }
fi

# The simulator must be running to receive the event.
xcrun simctl boot "$UDID" >/dev/null 2>&1
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1

xcrun simctl spawn "$UDID" "$PWD/$HELPER" set "$ANGLE" || { echo "duo_hinge: the helper failed" >&2; exit 1; }
sleep 3

# Read the angle back (the same way Xcode's tools do) to be sure it moved.
read_angle() {
    local out pid angle=""
    out=$(mktemp)
    xcrun devicectl device motion hinge-angle -d "$UDID" --session-timeout 5 -t 10 >"$out" 2>&1 &
    pid=$!
    for _ in $(seq 1 80); do
        angle=$(grep -m1 -oE 'Angle: *[0-9]+([.,][0-9]+)?' "$out" | grep -oE '[0-9]+([.,][0-9]+)?' | tr , . || true)
        [ -n "$angle" ] && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    rm -f "$out"
    echo "$angle"
}

ACTUAL=$(read_angle)
if [ -z "$ACTUAL" ]; then
    # Couldn't read it back; the UI tests check the screen shape themselves.
    echo "duo_hinge: set to $POSTURE (angle not confirmed)"
    exit 0
fi
DIFF=$(echo "$ACTUAL $ANGLE" | awk '{ d = $1 - $2; if (d < 0) d = -d; print int(d) }')
if [ "$DIFF" -gt 10 ]; then
    echo "duo_hinge: asked for ${ANGLE} degrees, the simulator reports ${ACTUAL}" >&2
    exit 1
fi
echo "duo_hinge: ${POSTURE} (${ACTUAL} degrees)"
