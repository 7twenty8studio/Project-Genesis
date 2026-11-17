#!/usr/bin/env bash
# End-to-end App Attest test for dv-report: a throwaway local Postgres with the
# Supabase stand-ins and all migrations, dv-report served by Deno with a test
# root (testRoot.ts via an import map), then e2e.test.ts over HTTP. Nothing
# here can reach a hosted project: the database and function are on 127.0.0.1.
#   PGBIN=/usr/lib/postgresql/16/bin DENO=deno supabase/tests/daily_verse/app_attest/run.sh
# (Run as a non-root user: initdb refuses root.)
set -euo pipefail
export LC_ALL=C LANG=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
DENO="${DENO:-deno}"
PORT="${PORT:-54331}"; FN_PORT="${FN_PORT:-8000}"   # Deno.serve listens on 8000
WORK="$(mktemp -d /tmp/dvat.XXXXXX)"
# initdb refuses root: as root, the database server runs as PG_OS_USER (default dvrunner).
PGUSER_OS="$(whoami)"; pgrun() { "$@"; }
if [ "$(id -u)" = 0 ]; then PGUSER_OS="${PG_OS_USER:-dvrunner}"; chown "$PGUSER_OS" "$WORK"; pgrun() { runuser -u "$PGUSER_OS" -- "$@"; }; fi
cleanup() { [ -n "${FN_PID:-}" ] && kill "$FN_PID" 2>/dev/null || true; pgrun "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

pgrun "$PGBIN/initdb" -D "$WORK/data" -A trust -U "$PGUSER_OS" >/dev/null
pgrun "$PGBIN/pg_ctl" -D "$WORK/data" -o "-k $WORK -p $PORT -c listen_addresses=127.0.0.1" -l "$WORK/pg.log" start >/dev/null
"$PGBIN/createdb" -h 127.0.0.1 -p "$PORT" -U "$PGUSER_OS" dvtest
SUPER="postgresql://$PGUSER_OS@127.0.0.1:$PORT/dvtest"
AS_PG="postgresql://postgres@127.0.0.1:$PORT/dvtest"
"$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$SUPER" -f "$ROOT/supabase/tests/daily_verse/supabase_stubs.sql" >/dev/null
for f in "$ROOT"/supabase/migrations/*.sql; do
  case "$(basename "$f")" in 20261114000000_*) continue ;; esac   # the retention schedule needs pg_net; not part of this test
  sed -E '/create extension if not exists (pg_cron|pg_net)/d' "$f" | "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$AS_PG" -f - >/dev/null 2>&1
done
echo "== migrations applied"

# The test CA is made once and shared with the server through a file.
CA_DIR="$WORK/ca"; mkdir -p "$CA_DIR"
cp "$ROOT/supabase/functions/_shared/appAttest.ts" "$HERE/appAttest.real.ts"
cat > "$WORK/import_map.json" <<JSON
{ "imports": { "file://$ROOT/supabase/functions/_shared/appAttest.ts": "file://$HERE/testRoot.ts" } }
JSON
cat > "$WORK/makeca.mts" <<JS
import { writeFileSync } from "node:fs";
import { FakeCA } from "$HERE/fakeDevice.ts";
const ca = new FakeCA();
writeFileSync("$CA_DIR/state.json", JSON.stringify({ dir: ca.dir, root: ca.rootFile }));
JS
node --experimental-strip-types "$WORK/makeca.mts"
CA_STATE="$(cat "$CA_DIR/state.json")"
ROOT_PEM="$(node -e "console.log(JSON.parse(process.argv[1]).root)" "$CA_STATE")"

SUPABASE_DB_URL="$AS_PG" SUPABASE_URL="http://127.0.0.1:9" SUPABASE_SERVICE_ROLE_KEY="test" SUPABASE_ANON_KEY="test" \
DV_REPORT_KEYS="sb_publishable_localtestkey1234" DV_HMAC_SECRET="$(openssl rand -hex 32)" \
DV_INTERNAL_BUILDS="202611141200" DV_ATTEST_ALLOW_DEVELOPMENT="false" DV_TEST_ATTEST_ROOT_PEM_FILE="$ROOT_PEM" \
PORT="$FN_PORT" "$DENO" run -A --import-map "$WORK/import_map.json" "$ROOT/supabase/functions/dv-report/index.ts" \
  > "$WORK/fn.log" 2>&1 &
FN_PID=$!
for i in $(seq 1 60); do curl -s -o /dev/null "http://127.0.0.1:$FN_PORT" && break; sleep 0.5; done

DV_E2E_URL="http://127.0.0.1:$FN_PORT" DV_E2E_APIKEY="sb_publishable_localtestkey1234" DV_E2E_DB="$SUPER" \
DV_E2E_CA="$CA_STATE" PSQL="$PGBIN/psql" \
  node --experimental-strip-types --test "$HERE/e2e.test.ts" 2>&1 | tee "$WORK/test.log" | grep -E "^# (pass|fail)|^not ok|^ok" || true
rm -f "$HERE/appAttest.real.ts"
grep -q "^# fail 0" "$WORK/test.log" || { echo "FAILED; function log: $WORK/fn.log"; tail -30 "$WORK/fn.log"; trap - EXIT; cleanup; exit 1; }
echo "Logs: $WORK"
