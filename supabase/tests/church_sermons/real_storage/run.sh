#!/usr/bin/env bash
# Cover access against the real Supabase Storage API and the real
# sermon-cover function (VRS-18, 20261121000000), all local: Supabase's
# storage-api image (file backend) and Edge Runtime image in Docker, a
# throwaway Postgres with every Versely migration, and a small gateway
# standing in for PostgREST's one call (gateway.mjs). It never connects to a
# hosted project.
#
# What it shows (check.mjs): no client, not even the church's pastor, can
# create a signed link, list the bucket or download a cover from Storage;
# uploads work with the leaders' INSERT policy alone; the function gives a
# draft cover to leaders only and a published one only while the reader may
# read the sermon, so members only, a ban, an unpublish or the switch turned
# off stops the very next request.
#
#   PGBIN=/usr/lib/postgresql/16/bin supabase/tests/church_sermons/real_storage/run.sh
#   (needs Docker and Node; macOS: PGBIN=/opt/homebrew/opt/postgresql@17/bin)
set -euo pipefail
export LC_ALL=C LANG=C

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@17/bin}"
export PSQL="$PGBIN/psql" PGPORT_="${PGPORT_:-54332}"
STORAGE_IMAGE="${STORAGE_IMAGE:-supabase/storage-api:v1.25.7}"
EDGE_IMAGE="${EDGE_IMAGE:-public.ecr.aws/supabase/edge-runtime:v1.69.25}"
SECRET="super-secret-jwt-token-with-at-least-32-characters-long"
export WORK="$(mktemp -d /tmp/csstore.XXXXXX)"
chmod 755 "$WORK"
cleanup() {
  docker rm -f cs-storage cs-edge >/dev/null 2>&1 || true
  [ -n "${GATEWAY:-}" ] && kill "$GATEWAY" 2>/dev/null || true
  "$PGBIN/pg_ctl" -D "$WORK/data" -m immediate stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

q() { "$PSQL" -X -q -v ON_ERROR_STOP=1 -h 127.0.0.1 -p "$PGPORT_" -U "${AS:-cs_super}" -d dvtest "$@"; }

echo "== Postgres"
"$PGBIN/initdb" -D "$WORK/data" -A trust -E UTF8 --locale=C -U cs_super >/dev/null
"$PGBIN/pg_ctl" -D "$WORK/data" -o "-p $PGPORT_ -c listen_addresses=127.0.0.1 -k $WORK" -l "$WORK/pg.log" start >/dev/null
"$PGBIN/createdb" -h 127.0.0.1 -p "$PGPORT_" -U cs_super dvtest
# The usual stand-ins, without their storage part: the real Storage API makes its own.
awk '/^-- storage ---/{skip=1} /^-- pg_cron/{skip=0} !skip' "$ROOT/supabase/tests/daily_verse/supabase_stubs.sql" | q -f - >/dev/null
q >/dev/null <<'SQL'
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
create role authenticator login noinherit;
grant anon, authenticated, service_role to authenticator;
-- auth.uid() / auth.role() as Supabase defines them (the claim, or the claims JSON the Storage API sets).
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
create or replace function auth.role() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'))::text $$;
SQL

node "$HERE/jwt.mjs" '{"role":"anon"}' > "$WORK/anon.key"
node "$HERE/jwt.mjs" '{"role":"service_role"}' > "$WORK/service.key"

echo "== Supabase Storage API ($STORAGE_IMAGE)"
mkdir -p "$WORK/files" && chmod 777 "$WORK/files"
docker run -d --name cs-storage --network host -v "$WORK/files:/var/lib/storage" \
  -e ANON_KEY="$(cat "$WORK/anon.key")" -e SERVICE_KEY="$(cat "$WORK/service.key")" \
  -e AUTH_JWT_SECRET="$SECRET" -e PGRST_JWT_SECRET="$SECRET" \
  -e DATABASE_URL="postgres://cs_super@127.0.0.1:$PGPORT_/dvtest" -e DB_INSTALL_ROLES=false \
  -e STORAGE_BACKEND=file -e FILE_STORAGE_BACKEND_PATH=/var/lib/storage -e FILE_SIZE_LIMIT=52428800 \
  -e TENANT_ID=stub -e REGION=local -e GLOBAL_S3_BUCKET=stub -e SERVER_PORT=5000 -e ENABLE_IMAGE_TRANSFORMATION=false \
  "$STORAGE_IMAGE" >/dev/null
for _ in $(seq 1 60); do
  [ "$(q -Atc "select to_regclass('storage.objects') is not null" 2>/dev/null)" = t ] && curl -s -o /dev/null localhost:5000/status && break
  sleep 1
done
# As on hosted Supabase, postgres can manage the storage tables' policies.
q -c "grant usage on schema storage to anon, authenticated, service_role, postgres;
      grant all on all tables in schema storage to anon, authenticated, service_role, postgres;
      alter table storage.objects owner to postgres; alter table storage.buckets owner to postgres;" >/dev/null

echo "== Versely migrations"
n=0
for f in "$ROOT"/supabase/migrations/*.sql; do
  sed -E '/create extension if not exists (pg_cron|pg_net)/d' "$f" | AS=postgres q -f - >/dev/null 2>"$WORK/err" \
    || { echo "FAILED: $(basename "$f")"; cat "$WORK/err"; exit 1; }
  n=$((n + 1))
done
echo "   applied $n files"
{ awk '/^-- Switch off ---/{exit} {print}' "$HERE/../tests.sql"; cat "$HERE/seed_tail.sql"; } > "$WORK/seed.sql"
q -v ids="$WORK/ids.json" -f "$WORK/seed.sql" >/dev/null

echo "== Edge Runtime with sermon-cover ($EDGE_IMAGE)"
mkdir -p "$WORK/functions" && cp -r "$ROOT/supabase/functions/sermon-cover" "$WORK/functions/" && chmod -R a+rX "$WORK/functions"
docker run -d --name cs-edge --network host -v "$WORK/functions:/home/deno/functions" \
  -e SUPABASE_URL=http://127.0.0.1:54400 -e SUPABASE_ANON_KEY="$(cat "$WORK/anon.key")" -e SUPABASE_SERVICE_ROLE_KEY="$(cat "$WORK/service.key")" \
  "$EDGE_IMAGE" start --main-service /home/deno/functions/sermon-cover -p 54401 >/dev/null
node "$HERE/gateway.mjs" > "$WORK/gateway.log" 2>&1 &
GATEWAY=$!
for _ in $(seq 1 60); do curl -s -o /dev/null "localhost:54401/sermon-cover?name=x" && break; sleep 1; done

echo "== Checks"
node "$HERE/check.mjs"
