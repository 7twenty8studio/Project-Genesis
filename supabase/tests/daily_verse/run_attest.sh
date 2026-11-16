#!/usr/bin/env bash
# Checks for 20261117000000_daily_verse_app_attest.sql on a throwaway Postgres 17 with
# Supabase stand-ins (as run.sh): Versely migrations -> Daily Verse reports -> App Attest
# migration -> attest_tests.sql -> rollback -> re-apply -> tests again. No Docker, no network.
set -euo pipefail
export LC_ALL=C LANG=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MIG="$ROOT/supabase/migrations"
BASE="20261113000000_daily_verse_reports.sql"
NEW="20261117000000_daily_verse_app_attest.sql"
DOWN="$ROOT/supabase/rollback/20261117000000_daily_verse_app_attest_down.sql"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
PORT="${PORT:-54330}"
WORK="$(mktemp -d /tmp/dvat.XXXXXX)"
cleanup() { "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$PGBIN/initdb" -D "$WORK/data" -A trust -U "$(whoami)" >/dev/null
"$PGBIN/pg_ctl" -D "$WORK/data" -o "-k $WORK -p $PORT -c listen_addresses=''" -l "$WORK/pg.log" start >/dev/null
"$PGBIN/createdb" -h "$WORK" -p "$PORT" dvtest
SUPER_URL="postgresql:///dvtest?host=$WORK&port=$PORT"
PG_URL="postgresql://postgres@/dvtest?host=$WORK&port=$PORT"
psql() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$SUPER_URL" "$@"; }
as_postgres() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$PG_URL" "$@"; }

psql -f "$HERE/supabase_stubs.sql" >/dev/null
for f in "$MIG"/*.sql; do
  [[ "$(basename "$f")" < "$BASE" ]] || continue
  sed -E '/create extension if not exists (pg_cron|pg_net)/d' "$f" | as_postgres -f - >/dev/null
done
as_postgres -f "$MIG/$BASE" >/dev/null
echo "== App Attest migration (as postgres)"
as_postgres -f "$MIG/$NEW" >/dev/null
echo "== Tests (1st apply)"
psql -f "$HERE/attest_tests.sql" | tail -14
echo "== Rollback"
as_postgres -f "$DOWN" >/dev/null
psql -At -c "select count(*) from pg_tables where schemaname = 'daily_verse' and tablename = 'attest_keys'" | grep -qx 0 && echo "   attest_keys gone"
psql -At -c "select count(*) from pg_tables where schemaname = 'daily_verse' and tablename = 'reports'" | grep -qx 1 && echo "   reports kept"
echo "== Re-apply and test again"
as_postgres -f "$MIG/$NEW" >/dev/null
psql -f "$HERE/attest_tests.sql" | tail -1
