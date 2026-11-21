#!/usr/bin/env bash
# Browser acceptance checks for the guest page and Church Studio (VRS-18)
# against a stand-in server (mock.mjs): no Supabase, no network.
#
#   cd web && npm install
#   python3 ../Tools/BibleData/export_web_chapters.py --rv1909 <RV1909.sqlite or spa-rv1909.usfx.xml> --out build/web-bibles
#   ./e2e/run.sh                      # or MOCK_BIBLES=/path/to/web-bibles ./e2e/run.sh
#
# Needs Playwright with Chromium (already in the cloud container; on a Mac:
# `npm install --no-save playwright && npx playwright install chromium`).
# Builds the site pointed at the stand-in (run `npm run build` again before
# anything else uses .next), serves it on :3100, writes screenshots to
# build/e2e-shots and exits non-zero if any check fails.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
export MOCK_BIBLES="${MOCK_BIBLES:-$PWD/build/web-bibles}"
if [ ! -d "$MOCK_BIBLES/web/v1/KJV" ]; then
  echo "No web Bibles at $MOCK_BIBLES (see the top of this file)." >&2
  exit 2
fi
NEXT_PUBLIC_VERSELY_SUPABASE_URL=http://localhost:54329 NEXT_PUBLIC_VERSELY_SITE_URL=http://localhost:3100 \
  npm run build > build/e2e-build.log 2>&1 || { tail -40 build/e2e-build.log; exit 1; }
node e2e/mock.mjs > build/e2e-mock.log 2>&1 &
MOCK_PID=$!
npx next start -p 3100 > build/e2e-next.log 2>&1 &
NEXT_PID=$!
trap 'kill $MOCK_PID $NEXT_PID 2>/dev/null; pkill -P $NEXT_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do
  curl -sf -o /dev/null http://localhost:3100/studio && curl -s -o /dev/null http://localhost:54329/mock/sermon && break
  sleep 1
done
node e2e/check.cjs
