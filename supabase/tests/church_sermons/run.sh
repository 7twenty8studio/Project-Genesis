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
# tested) -> tests.sql -> two sessions publishing, saving, reporting and
# sweeping covers at once -> the
# migration again (must change nothing) -> tests.sql again on fresh data.
set -euo pipefail
export LC_ALL=C LANG=C

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MIG="$ROOT/supabase/migrations"
NEW="20261120000000_church_sermons.sql"
LAST="20261121000000_church_sermon_web.sql"  # the newest church sermons migration
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
  [[ "$(basename "$f")" > "$LAST" ]] && continue
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

# One report open, then two more at the same moment: the third always hides it.
slug="$(psql -At -c "select slug from public.church_sermons where id = '$sermon'")"
psql -c "select ct.run('r1', 'public.report_church_sermon(''$slug'', ''one'')')" >/dev/null
report() {  # $1 = person
  "$PGBIN/psql" -X -q -At -d "$SUPER_URL" -c "begin; set local request.jwt.claim.sub = '$(psql -At -c "select id from ct.people where name = '$1'")'; set local role authenticated; select pg_sleep(0.2), report_church_sermon('$slug', 'together'); select pg_sleep(0.5); commit;" >/dev/null 2>&1
}
report r2 & report r3 &
wait
hidden="$(psql -At -c "select hidden_at is not null from public.church_sermons where id = '$sermon'")"
open_reports="$(psql -At -c "select count(*) from public.church_sermon_reports r join public.church_sermons s on s.id = r.sermon_id where s.id = '$sermon' and r.resolved_at is null")"
if [ "$hidden" = t ] && [ "$open_reports" = 3 ]; then echo "   PASS concurrent reports: the third hides it"; else echo "   FAIL concurrent reports: hidden=$hidden reports=$open_reports"; exit 1; fi

# The nightly sweep and an editor at the same moment: only one wins, so a
# cover is never both freed for deletion and on the draft or published copy.
group_id="$(psql -At -c "select group_id from public.church_sermons where id = '$sermon'")"
old_cover() {  # an uploaded picture, two days old, on neither copy
  local c; c="$(psql -At -c "select gen_random_uuid()")"
  psql -c "insert into storage.objects (bucket_id, name, created_at) values ('sermon-covers', '$group_id/$sermon/$c.jpg', now() - interval '2 days')" >/dev/null
  echo "$c"
}
version() { psql -At -c "select draft_version from public.church_sermons where id = '$sermon'"; }
sweep() {  # $1 = seconds to wait first, $2 = seconds to hold the transaction
  "$PGBIN/psql" -X -q -At -d "$SUPER_URL" -c "begin; set local role service_role; select pg_sleep($1); select count(*) from retire_orphan_sermon_covers(); select pg_sleep($2); commit;" >/dev/null 2>&1
}
attach() {  # $1 = cover, $2 = seconds to wait first, $3 = seconds to hold
  "$PGBIN/psql" -X -q -At -d "$SUPER_URL" -c "begin; set local request.jwt.claim.sub = '$leader'; set local role authenticated; select pg_sleep($2); select save_church_sermon('$sermon', $(version), '{\"cover\": \"$1\", \"cover_alt\": \"Hills\"}', null)->>'draft_version'; select pg_sleep($3); commit;" 2>&1 | grep -E 'invalid_details|^[0-9]+$' | head -1
}
cover_state() {  # retired (t/f) | on the draft (t/f) | published (t/f)
  psql -At -c "select exists (select 1 from public.church_sermon_retired_covers where name = '$group_id/$sermon/$1.jpg'),
                      exists (select 1 from public.church_sermons where id = '$sermon' and cover_id = '$1'),
                      exists (select 1 from public.church_sermons s join public.church_sermon_revisions r on r.id = s.published_revision_id
                              where s.id = '$sermon' and r.details#>>'{cover,id}' = '$1')"
}
# Sweep first, holding its lock: the save waits, then is refused.
c="$(old_cover)"
sweep 0 0.6 & attach "$c" 0.2 0 > "$WORK/a1" & wait
if [ "$(cover_state "$c")" = "t|f|f" ] && grep -q invalid_details "$WORK/a1"; then echo "   PASS sweep first: the cover is retired and the save is refused"
else echo "   FAIL sweep first: $(cover_state "$c") / $(cat "$WORK/a1")"; exit 1; fi
# Save first, holding its lock: the sweep waits, then leaves the cover alone.
c="$(old_cover)"
attach "$c" 0 0.6 > "$WORK/a2" & sweep 0.2 0 & wait
if [ "$(cover_state "$c")" = "f|t|f" ] && grep -qE '^[0-9]+$' "$WORK/a2"; then echo "   PASS save first: the cover stays on the draft, not retired"
else echo "   FAIL save first: $(cover_state "$c") / $(cat "$WORK/a2")"; exit 1; fi
# Publish and sweep together: the published cover is never retired.
psql -c "update storage.objects set created_at = now() - interval '2 days' where name = '$group_id/$sermon/$c.jpg'" >/dev/null
call "select pg_sleep(0.2), publish_church_sermon('$sermon', $(version))->>'revision'" > "$WORK/p3" & sweep 0.2 0.3 & wait
if [ "$(cover_state "$c")" = "f|t|t" ]; then echo "   PASS publish and sweep together: the published cover stays"
else echo "   FAIL publish and sweep: $(cover_state "$c") / $(cat "$WORK/p3")"; exit 1; fi

echo "== Migration again (must change nothing)"
"$PGBIN/pg_dump" -d "$SUPER_URL" -s -n public -n storage | grep -v restrict > "$WORK/before.sql"
as_postgres -f "$MIG/$NEW" >/dev/null 2>&1
as_postgres -f "$MIG/$LAST" >/dev/null 2>&1
"$PGBIN/pg_dump" -d "$SUPER_URL" -s -n public -n storage | grep -v restrict > "$WORK/after.sql"
if diff -q "$WORK/before.sql" "$WORK/after.sql" >/dev/null; then echo "   PASS schema identical"; else diff "$WORK/before.sql" "$WORK/after.sql" | head -20; exit 1; fi
flags="$(psql -At -c "select enabled from public.feature_flags where key = 'church_sermons'")"
[ "$flags" = t ] && echo "   PASS switch left as it was (tests turned it on)" || { echo "   FAIL switch reset"; exit 1; }

echo "== Tests on fresh data"
psql -c "update public.feature_flags set enabled = false where key = 'church_sermons'" >/dev/null
psql -f "$HERE/tests.sql" | grep -E "FAIL|PASS"
echo "All church sermon checks passed."
