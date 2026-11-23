#!/usr/bin/env bash
# Checks for the launch giveaway (20261127000000, remote control 20261129000000) on a throwaway local
# Postgres with Supabase stand-ins. No Docker, no network.
#
#   brew install postgresql@17          # once (Linux: PGBIN=/usr/lib/postgresql/16/bin)
#   supabase/tests/giveaway/run.sh
set -euo pipefail
export LC_ALL=C LANG=C
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MIG="$ROOT/supabase/migrations"
LAST="20261129000000_giveaway_remote.sql"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
PORT="${PORT:-54331}"
WORK="$(mktemp -d /tmp/gwpg.XXXXXX)"
cleanup() { "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

"$PGBIN/initdb" -D "$WORK/data" -A trust -E UTF8 --locale=C -U gw_super >/dev/null
"$PGBIN/pg_ctl" -D "$WORK/data" -o "-k $WORK -p $PORT -c listen_addresses=''" -l "$WORK/pg.log" start >/dev/null
"$PGBIN/createdb" -h "$WORK" -p "$PORT" -U gw_super dvtest
SUPER_URL="postgresql://gw_super@/dvtest?host=$WORK&port=$PORT"
PG_URL="postgresql://postgres@/dvtest?host=$WORK&port=$PORT"
psql() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$SUPER_URL" "$@"; }
as_postgres() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$PG_URL" "$@"; }

psql -f "$ROOT/supabase/tests/daily_verse/supabase_stubs.sql" >/dev/null
psql -c "alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
         alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;" >/dev/null

echo "== Versely migrations up to the giveaway (as postgres)"
for f in "$MIG"/*.sql; do
  [[ "$(basename "$f")" > "$LAST" ]] && continue
  sed -E '/create extension if not exists (pg_cron|pg_net)/d' "$f" | as_postgres -f - >/dev/null 2>"$WORK/err" \
    || { echo "FAILED: $(basename "$f")"; cat "$WORK/err"; exit 1; }
done
echo "== Tests"
psql -At -f "$HERE/tests.sql"
echo "== Migration again (must apply cleanly)"
as_postgres -f "$MIG/$LAST" >/dev/null
echo "== Two entries at once get different numbers"
enter() { "$PGBIN/psql" -X -q -At -d "$SUPER_URL" -c "set role anon; select giveaway_enter('launch-2026', '$1', '$1@example.com', false)"; }
enter p1 > "$WORK/e1" & enter p2 > "$WORK/e2" & enter p3 > "$WORK/e3" & wait
nums="$(sort -n "$WORK"/e? | tr '\n' ' ')"
if [ "$nums" = "1 2 3 " ]; then echo "PASS concurrent entries: $nums"; else echo "FAIL concurrent entries: $nums"; exit 1; fi
