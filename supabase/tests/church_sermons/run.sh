#!/usr/bin/env bash
# Access and behaviour checks for church sermons (20261120000000, VRS-18) on a
# throwaway local Postgres with Supabase stand-ins. No Docker, no network; it
# never connects to a hosted project.
#
#   brew install postgresql@17          # once (Linux: PGBIN=/usr/lib/postgresql/16/bin)
#   supabase/tests/church_sermons/run.sh
#
# Steps: every Versely migration up to and including church sermons, with
# Supabase's default grants (anon and authenticated can use every new table and
# function unless a migration revokes it, so RLS and the revokes are what's
# tested) -> tests.sql -> two sessions publishing and saving at once -> the
# migration again (must change nothing) -> tests.sql again on fresh data.
set -euo pipefail
export LC_ALL=C LANG=C

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MIG="$ROOT/supabase/migrations"
NEW="20261120000000_church_sermons.sql"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
PORT="${PORT:-54330}"
WORK="$(mktemp -d /tmp/cspg.XXXXXX)"
cleanup() { "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; }
trap cleanup EXIT

"$PGBIN/initdb" -D "$WORK/data" -A trust -E UTF8 --locale=C -U cs_super >/dev/null
"$PGBIN/pg_ctl" -D "$WORK/data" -o "-k $WORK -p $PORT -c listen_addresses=''" -l "$WORK/pg.log" start >/dev/null
"$PGBIN/createdb" -h "$WORK" -p "$PORT" -U cs_super dvtest
SUPER_URL="postgresql://cs_super@/dvtest?host=$WORK&port=$PORT"
PG_URL="postgresql://postgres@/dvtest?host=$WORK&port=$PORT"
psql() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$SUPER_URL" "$@"; }
as_postgres() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$PG_URL" "$@"; }

psql -f "$ROOT/supabase/tests/daily_verse/supabase_stubs.sql" >/dev/null
# Supabase's default privileges for objects postgres creates.
psql -c "alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
         alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;" >/dev/null

echo "== Versely migrations up to church sermons (as postgres)"
n=0
for f in "$MIG"/*.sql; do
  [[ "$(basename "$f")" > "$NEW" ]] && continue
  sed -E '/create extension if not exists (pg_cron|pg_net)/d' "$f" | as_postgres -f - >/dev/null 2>"$WORK/err" \
    || { echo "FAILED: $(basename "$f")"; cat "$WORK/err"; exit 1; }
  n=$((n + 1))
done
echo "   applied $n files"

echo "== Tests"
psql -f "$HERE/tests.sql" | grep -E "FAIL|PASS"

echo "== Two sessions at once"
psql -f "$HERE/concurrency_setup.sql" >/dev/null
sermon="$(psql -At -c "select id from public.church_sermons where title = 'Concurrency'")"
leader="$(psql -At -c "select created_by from public.church_sermons where title = 'Concurrency'")"
call() {  # $1 = SQL run as the leader
  "$PGBIN/psql" -X -q -At -d "$SUPER_URL" -c "begin; set local request.jwt.claim.sub = '$leader'; set local role authenticated; $1; commit;" 2>&1 | grep -v '^$' | grep -vE '^(BEGIN|COMMIT|SET|CONTEXT:.*)$' | head -1
}
# Both publish version 1 at the same moment: one revision, the same answer twice.
call "select pg_sleep(0.2), publish_church_sermon('$sermon', 1)->>'revision'" > "$WORK/p1" &
call "select pg_sleep(0.2), publish_church_sermon('$sermon', 1)->>'revision'" > "$WORK/p2" &
wait
r1="$(cut -d'|' -f2 < "$WORK/p1")"; r2="$(cut -d'|' -f2 < "$WORK/p2")"
revs="$(psql -At -c "select count(*) from public.church_sermon_revisions where sermon_id = '$sermon'")"
if [ -n "$r1" ] && [ "$r1" = "$r2" ] && [ "$revs" = 1 ]; then echo "   PASS concurrent publish: one revision ($r1)"; else echo "   FAIL concurrent publish: '$r1' '$r2' revisions=$revs"; exit 1; fi
# Both save on top of version 1: one wins, the other is told the draft changed.
call "select pg_sleep(0.2), save_church_sermon('$sermon', 1, '{\"title\": \"A\"}', null)->>'draft_version'" > "$WORK/s1" &
call "select pg_sleep(0.2), save_church_sermon('$sermon', 1, '{\"title\": \"B\"}', null)->>'draft_version'" > "$WORK/s2" &
wait
if cat "$WORK/s1" "$WORK/s2" | grep -q 'draft_changed' && cat "$WORK/s1" "$WORK/s2" | grep -q '|2$'; then
  echo "   PASS concurrent save: one saved, one told the draft changed"
else
  echo "   FAIL concurrent save: $(cat "$WORK/s1") / $(cat "$WORK/s2")"; exit 1
fi

echo "== Migration again (must change nothing)"
"$PGBIN/pg_dump" -d "$SUPER_URL" -s -n public -n storage | grep -v restrict > "$WORK/before.sql"
as_postgres -f "$MIG/$NEW" >/dev/null 2>&1
"$PGBIN/pg_dump" -d "$SUPER_URL" -s -n public -n storage | grep -v restrict > "$WORK/after.sql"
if diff -q "$WORK/before.sql" "$WORK/after.sql" >/dev/null; then echo "   PASS schema identical"; else diff "$WORK/before.sql" "$WORK/after.sql" | head -20; exit 1; fi
flags="$(psql -At -c "select enabled from public.feature_flags where key = 'church_sermons'")"
[ "$flags" = t ] && echo "   PASS switch left as it was (tests turned it on)" || { echo "   FAIL switch reset"; exit 1; }

echo "== Tests on fresh data"
psql -c "update public.feature_flags set enabled = false where key = 'church_sermons'" >/dev/null
psql -f "$HERE/tests.sql" | grep -E "FAIL|PASS"
echo "All church sermon checks passed."
