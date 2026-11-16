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
OUT="$WORK/out"; mkdir -p "$OUT"

# Versely = public, storage, auth (schema, policies, table ACLs), roles and cron jobs.
# Daily Verse = the daily_verse schema as it was before this migration (to check rollback).
snapshot() {
  "$PGBIN/pg_dump" -d "$SUPER_URL" -s -n public -n storage -n auth \
    | grep -vE '^(--|SET |SELECT pg_catalog|\\(un)?restrict )' > "$OUT/versely-$1.sql"
  psql -At -c "select schemaname, tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')
               from pg_policies where schemaname in ('public','storage') order by 1,2,3" >> "$OUT/versely-$1.sql"
  psql -At -c "select n.nspname || '.' || c.relname, c.relacl::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname in ('public','storage','auth') and c.relkind in ('r','v','S') order by 1" >> "$OUT/versely-$1.sql"
  psql -At -c "select rolname, rolsuper, rolinherit, rolcreaterole, rolcanlogin, rolbypassrls from pg_roles order by 1" >> "$OUT/versely-$1.sql"
  psql -At -c "select r.rolname || ' -> ' || m.rolname from pg_auth_members a join pg_roles r on r.oid = a.member
               join pg_roles m on m.oid = a.roleid order by 1" >> "$OUT/versely-$1.sql"
  psql -At -c "select jobname, schedule, command from cron.job order by 1" >> "$OUT/versely-$1.sql"
  "$PGBIN/pg_dump" -d "$SUPER_URL" -s -n daily_verse \
    | grep -vE '^(--|SET |SELECT pg_catalog|\\(un)?restrict )' > "$OUT/dailyverse-$1.sql"
  psql -At -c "select accepted_channels::text from daily_verse.settings" >> "$OUT/dailyverse-$1.sql"
}
compare() {  # $1 $2 kind label
  if diff -u "$OUT/$3-$1.sql" "$OUT/$3-$2.sql" > "$OUT/diff-$3-$1-$2.txt"; then echo "   $4: identical"
  else echo "   $4: DIFFERENT"; cat "$OUT/diff-$3-$1-$2.txt"; FAILED=1; fi
}
FAILED=0

snapshot before
echo "== App Attest migration (as postgres, not superuser)"
as_postgres -f "$MIG/$NEW" >/dev/null
snapshot after
echo "== Versely unchanged by the migration?"
compare before after versely "public, storage, auth, policies, ACLs, roles, cron"
echo "   daily_verse additions:"
diff "$OUT/dailyverse-before.sql" "$OUT/dailyverse-after.sql" | grep -E '^> CREATE (TABLE|FUNCTION)' | sed 's/^> /     /' || true
echo "== Tests (1st apply)"
psql -f "$HERE/attest_tests.sql" | tail -15
echo "== Rollback (as postgres)"
as_postgres -f "$DOWN" >/dev/null
snapshot rolledback
compare before rolledback versely "Versely after rollback"
compare before rolledback dailyverse "daily_verse after rollback (same as before the migration)"
echo "== Re-apply and test again"
as_postgres -f "$MIG/$NEW" >/dev/null
psql -f "$HERE/attest_tests.sql" | tail -3
echo "== Public activation and its reversal"
psql -At -f "$HERE/activation/open_public_reports.sql" | head -1 | grep -q '^{internal,public}' && echo "   open: {internal,public}" || { echo "   open: FAILED"; FAILED=1; }
psql -At -f "$HERE/activation/close_public_reports.sql" | head -1 | grep -q '^{internal}' && echo "   close: {internal}" || { echo "   close: FAILED"; FAILED=1; }
# With the channel closed the database refuses a public report (channel_closed); once open it accepts it.
SUBMIT="set role service_role; select daily_verse.submit_report('public','1.0','1',null,null,'en','crossword','x.crossword',null,'approved','other','test','$(printf 'a%.0s' {1..64})','$(printf 'b%.0s' {1..64})')"
CLOSED_OUT="$(psql -At -c "$SUBMIT" 2>&1 || true)"; echo "     ($CLOSED_OUT)"; if echo "$CLOSED_OUT" | grep -q channel_closed; then echo "   closed: public report refused (channel_closed)"; else echo "   closed: FAILED"; FAILED=1; fi
psql -At -f "$HERE/activation/open_public_reports.sql" >/dev/null
if psql -At -c "$SUBMIT" 2>&1 | grep -qE '^[0-9a-f-]{36}$'; then echo "   open: public report accepted"; else echo "   open: FAILED"; FAILED=1; fi
psql -At -f "$HERE/activation/close_public_reports.sql" >/dev/null
echo "SHA-256 of the migration: $(shasum -a 256 "$MIG/$NEW" | cut -d' ' -f1)"
echo "Snapshots: $OUT"
exit $FAILED
