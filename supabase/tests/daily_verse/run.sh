#!/usr/bin/env bash
# Checks for the Daily Verse reports migration: migrate -> security tests ->
# rollback -> migrate -> tests, comparing Versely's schema, policies, grants,
# roles and cron jobs before and after.
#
#   Default (no Docker, no network): a throwaway Postgres 17 with Supabase
#   stand-ins, all Versely migrations applied first.
#     brew install postgresql@17      # once
#     supabase/tests/daily_verse/run.sh
#
#   Real local Supabase (Docker; see LOCAL_SUPABASE_VALIDATION.md). The stack must
#   have been reset to the last Versely migration first:
#     supabase db reset --local --no-seed --version 20261024000000
#     supabase/tests/daily_verse/run.sh --target local-supabase
#   Only 127.0.0.1 / localhost databases are accepted in this mode.
set -euo pipefail
export LC_ALL=C LANG=C   # Postgres refuses to start under some macOS locales

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MIG="$ROOT/supabase/migrations"
NEW="20261113000000_daily_verse_reports.sql"
DOWN="$ROOT/supabase/rollback/20261113000000_daily_verse_reports_down.sql"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
TARGET="stubs"
if [ "${1:-}" = "--target" ]; then TARGET="${2:-}"; fi

case "$TARGET" in
stubs)
  PORT="${PORT:-54329}"
  # Short path: Postgres socket paths are limited to ~100 characters.
  WORK="$(mktemp -d /tmp/dvpg.XXXXXX)"
  OUT="${OUT:-$WORK/out}"; mkdir -p "$OUT"
  cleanup() { "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true; }
  trap cleanup EXIT
  "$PGBIN/initdb" -D "$WORK/data" -A trust -U "$(whoami)" >/dev/null
  "$PGBIN/pg_ctl" -D "$WORK/data" -o "-k $WORK -p $PORT -c listen_addresses=''" -l "$WORK/pg.log" start >/dev/null
  "$PGBIN/createdb" -h "$WORK" -p "$PORT" dvtest
  SUPER_URL="postgresql:///dvtest?host=$WORK&port=$PORT"
  PG_URL="postgresql://postgres@/dvtest?host=$WORK&port=$PORT"
  ;;
local-supabase)
  # Defaults of `supabase start`. supabase_admin is the local superuser (for the
  # tests' role switching); migrations run as postgres, like the hosted project.
  PG_URL="${PG_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
  SUPER_URL="${SUPER_URL:-postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres}"
  for url in "$PG_URL" "$SUPER_URL"; do
    case "$url" in
      *@127.0.0.1:*|*@localhost:*) ;;
      *) echo "Refusing: $url is not a local database. This script never runs against a hosted project." >&2; exit 2 ;;
    esac
  done
  OUT="${OUT:-$(mktemp -d /tmp/dvsb.XXXXXX)}"; mkdir -p "$OUT"
  ;;
*) echo "usage: run.sh [--target stubs|local-supabase]" >&2; exit 2 ;;
esac

psql() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$SUPER_URL" "$@"; }
as_postgres() { "$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$PG_URL" "$@"; }

if [ "$TARGET" = stubs ]; then
  psql -f "$HERE/supabase_stubs.sql" >/dev/null
  echo "== Versely migrations (as postgres)"
  for f in "$MIG"/*.sql; do
    [ "$(basename "$f")" = "$NEW" ] && continue
    # pg_cron / pg_net are stand-ins here (supabase_stubs.sql); their CREATE EXTENSION lines are skipped.
    sed -E '/create extension if not exists (pg_cron|pg_net)/d' "$f" | as_postgres -f - >/dev/null
  done
  echo "   applied $(ls "$MIG"/*.sql | grep -vc "$NEW") files"
else
  echo "== Real local Supabase at ${PG_URL##*@}"
  if ! psql -At -c "select 1" >/dev/null 2>&1; then
    echo "No local Supabase reachable at ${PG_URL##*@}: run 'supabase start' first." >&2; exit 2
  fi
  if [ "$(psql -At -c "select count(*) from pg_namespace where nspname = 'daily_verse'")" != 0 ]; then
    echo "daily_verse already exists: run 'supabase db reset --local --no-seed --version 20261024000000' first." >&2; exit 2
  fi
  echo "   Versely migrations applied by supabase db reset: $(psql -At -c "select count(*) from supabase_migrations.schema_migrations")"
fi

snapshot() {  # $1 = label
  "$PGBIN/pg_dump" -d "$SUPER_URL" -s -n public -n storage -n auth \
    | grep -vE '^(--|SET |SELECT pg_catalog|\\(un)?restrict )' > "$OUT/schema-$1.sql"
  psql -At -c "select schemaname, tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')
               from pg_policies where schemaname in ('public','storage') order by 1,2,3" > "$OUT/policies-$1.txt"
  psql -At -c "select jobname, schedule, command from cron.job where jobname not like 'daily-verse%' order by 1" > "$OUT/cron-$1.txt"
  psql -At -c "select r.rolname, coalesce(string_agg(m.rolname, ',' order by m.rolname), '')
               from pg_roles r left join pg_auth_members a on a.member = r.oid left join pg_roles m on m.oid = a.roleid and m.rolname <> 'daily_verse_owner'
               where r.rolname !~ '^pg_' and r.rolname <> 'daily_verse_owner' group by 1 order by 1" > "$OUT/roles-$1.txt"
  psql -At -c "select n.nspname || '.' || c.relname, c.relacl::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname in ('public','storage') and c.relkind in ('r','v','S') order by 1" > "$OUT/acl-$1.txt"
}

same() {  # $1 $2 labels
  local ok=0
  for k in schema policies cron roles acl; do
    local ext=txt; [ "$k" = schema ] && ext=sql
    if diff -u "$OUT/$k-$1.$ext" "$OUT/$k-$2.$ext" > "$OUT/diff-$k-$1-$2.txt"; then
      echo "   $k: identical"
    else
      echo "   $k: DIFFERENT (see $OUT/diff-$k-$1-$2.txt)"; ok=1
    fi
  done
  return $ok
}

snapshot before

echo "== Daily Verse migration (as postgres, not superuser)"
as_postgres -f "$MIG/$NEW" >/dev/null
snapshot after1
echo "== Versely unchanged after migrating?"
same before after1
echo "   expected addition: postgres is a member of daily_verse_owner (to own the new schema):"
psql -At -c "select '     ' || r.rolname || ' -> daily_verse_owner' from pg_auth_members a join pg_roles r on r.oid = a.member
             join pg_roles o on o.oid = a.roleid where o.rolname = 'daily_verse_owner'" | sort -u

echo "== Tests (1st apply)"
psql -f "$HERE/tests.sql" | tee "$OUT/tests-1.txt" | tail -3

echo "== Rollback (as postgres)"
as_postgres -f "$DOWN" >/dev/null
psql -At -c "select count(*) from pg_namespace where nspname = 'daily_verse'" | grep -qx 0 && echo "   schema gone"
psql -At -c "select count(*) from pg_roles where rolname = 'daily_verse_owner'" | grep -qx 0 && echo "   owner role gone"
psql -At -c "select count(*) from cron.job where jobname like 'daily-verse%'" | grep -qx 0 && echo "   cron job gone"
snapshot rolledback
echo "== Versely identical to before after rollback?"
same before rolledback

echo "== Re-apply and test again"
as_postgres -f "$MIG/$NEW" >/dev/null
psql -f "$HERE/tests.sql" | tee "$OUT/tests-2.txt" | tail -3

echo "Snapshots and logs: $OUT"
