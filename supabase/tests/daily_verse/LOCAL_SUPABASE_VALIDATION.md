# Validating PR A on a real local Supabase (Docker)

> **First run, 13 Nov 2026:** see [LOCAL_SUPABASE_RESULTS.md](LOCAL_SUPABASE_RESULTS.md). It stopped at a server crash in the migration (`grant … to current_user`). It also found three corrections to the steps below:
> 1. `supabase start` applies **all** migrations on first boot (default config). Set `[db.migrations] enabled = false` and `[db.seed] enabled = false` in `config.toml` before starting, then apply Versely's migrations by hand with `psql`. Apply `20261018030000_ops_alerts_schedule.sql` with `psql -1` plus `select cron.alter_job(jobid, active := false) from cron.job where command ilike '%ops_call_alerts%' or command ilike '%http%';` in the same transaction, so the ops-alerts jobs are never active.
> 2. `postgres` can't `UPDATE cron.job` on real Supabase; use `cron.alter_job`.
> 3. Colima may need `--dns 1.1.1.1 --dns 8.8.8.8` to pull images. The images total ~8 GB.

This carries out the gate in [PRODUCTION_GATE.md](PRODUCTION_GATE.md) on **this Mac**, with a disposable Supabase stack in Docker.
- There is no non-production Supabase environment for Versely.
- No Supabase project or branch is to be created.

**Nothing here has been run yet.** Installing Docker (or Colima) and running `supabase start` both need Gamaliel's approval first.

## Safety rules (read first)

- **Never** use `--linked`, `--db-url` with a hosted address, `supabase link`, `supabase db push` or `supabase migration repair` in this procedure. Every command below targets the local stack only. The default for `supabase db reset` is `--local`, and the commands say `--local` explicitly anyway.
- `run.sh --target local-supabase` refuses any database that isn't on `127.0.0.1` or `localhost`.
- The admin seed is applied **only** to the local stack (the tests do it). Never seed the hosted project.
- Versely's `ops-alerts-check` / `ops-alerts-digest` cron jobs call the **production** `ops-alerts` URL. On the local stack they would carry a random local secret, which production rejects. Step 4 disables them straight after the reset anyway, so nothing local talks to production.

## 1. What this Mac has (checked read-only, 13 Nov 2026)

| | |
|---|---|
| Chip / macOS | Apple Silicon (arm64), macOS 27.0 |
| Free disk | ~45 GB on the Data volume |
| Docker / Colima / OrbStack | **Not installed** |
| Supabase CLI | 2.75.0 (Homebrew; 3.1.0 available) |
| `supabase/config.toml` | **Doesn't exist** in Project-Genesis (created in step 3) |
| Postgres client | `postgresql@17` (Homebrew), used by `run.sh` |

## 2. Install a container runtime (pick one, with approval)

**A. Docker Desktop (simplest).**
- Free for personal use and small businesses (under 250 employees and under $10M revenue).
- Download "Docker Desktop for Mac with Apple silicon" from docker.com, open the `.dmg`, drag it to Applications, start it, and accept its terms.
- In Settings → Resources, give it **4 CPUs, 8 GB memory and at least 40 GB of disk**.
- Check it's running: `docker info` prints the server information.

**B. Colima (no GUI, open source).**
```sh
brew install colima docker
colima start --arch aarch64 --vm-type vz --cpu 4 --memory 8 --disk 40
docker info
```

Optional: `brew upgrade supabase` to update the CLI (2.75.0 → 3.x). The steps below work with 2.75.

## 3. One-time local project setup (not committed)

```sh
cd ~/Desktop/7Twenty8/Project-Genesis
git checkout claude/daily-verse-reports-db      # PR A branch
supabase init                                    # creates supabase/config.toml (+ .gitignore entries); answer "N" to the IDE prompts
```

Then edit `supabase/config.toml`:
- `[db] major_version` must match the **hosted** project. Check it in the Supabase dashboard: Project Settings → Infrastructure → Postgres version. Expected **17**; set `major_version = 17`.
- Leave all other defaults. Don't commit `config.toml` as part of this validation unless Gamaliel wants it in the repo.

## 4. Start the stack and reset to Versely's last migration

```sh
# Only the services the checks need (database, auth, REST, storage, gateway):
supabase start -x realtime,studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta
```
- First run downloads the images. Expect roughly **2–4 GB** with these exclusions (5–7 GB for the full set). Not measured on this Mac yet.
- After that, `supabase start` works **offline**; the update check just fails quietly.
- Output: the API URL `http://127.0.0.1:54321`, the DB URL `postgresql://postgres:postgres@127.0.0.1:54322/postgres`, and the anon and service_role keys.

```sh
# Apply only Versely's 27 migrations (stop before Daily Verse), no seed:
supabase db reset --local --no-seed --version 20261024000000

# Immediately disable the cron jobs that call the production ops-alerts URL:
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c \
  "update cron.job set active = false where jobname in ('ops-alerts-check', 'ops-alerts-digest');"
```
Expected:
- `reset` finishes with "Finished supabase db reset".
- `select count(*) from supabase_migrations.schema_migrations;` → **27**.
- The `update` reports `UPDATE 2`.

## 5. Migration, 84 checks, rollback, re-migration and the Versely diff

```sh
OUT=/tmp/dv-local-supabase supabase/tests/daily_verse/run.sh --target local-supabase
```
This applies `20261113000000_daily_verse_reports.sql` **as `postgres` (not a superuser on Supabase)**. That is the hosted-permissions test for `CREATE ROLE`, `GRANT … TO current_user`, `SET ROLE` and `cron.schedule`. It then runs the 84 checks as `supabase_admin`, rolls back, compares, re-applies and runs the checks again.

Expected output:
```
   schema: identical / policies: identical / cron: identical / roles: identical / acl: identical
   expected addition: postgres -> daily_verse_owner
 84 passed, 0 failed, 84 total
   schema gone / owner role gone / cron job gone
   (all five) identical
 84 passed, 0 failed, 84 total
```
- **If the migration itself fails** (for example, permission denied to create a role), stop. That is a real finding about hosted permissions. Record the exact error.
- **If a check fails or errors only on real Supabase** (for example, real `auth.users` or `storage.objects` triggers behaving differently from the stand-ins), record it as-is. Don't change the migration to make it pass without review.

The run leaves the Daily Verse migration applied, ready for steps 6–8.

## 6. API (PostgREST) checks

```sh
eval "$(supabase status -o env)"   # exports API_URL, ANON_KEY, SERVICE_ROLE_KEY, ...

# The schema isn't exposed: every call fails, even with the service key.
curl -s -o /dev/null -w "%{http_code}\n" "$API_URL/rest/v1/reports" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H "Accept-Profile: daily_verse"            # expect 406
curl -s -o /dev/null -w "%{http_code}\n" "$API_URL/rest/v1/reports" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Accept-Profile: daily_verse"  # expect 406
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$API_URL/rest/v1/rpc/purge_expired" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H "Content-Profile: daily_verse"           # expect 406
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$API_URL/rest/v1/rpc/is_admin" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H "content-type: application/json" -d '{"p_email":"x"}'  # expect 404 (not in public)
# Versely's own API still works:
curl -s -o /dev/null -w "%{http_code}\n" -X POST "$API_URL/rest/v1/app_feedback" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H "content-type: application/json" \
  -d '{"category":"other","message":"local validation"}'                                               # expect 201
```

## 7. Storage checks under `attachments/daily-verse/`

```sh
printf '\xff\xd8\xff\xe0local-test\xff\xd9' > /tmp/dv.jpg
P="daily-verse/reports/00000000-0000-0000-0000-0000000000aa/1.jpg"

# Service role (what the Edge Functions will use) can write it:
curl -s -w "\n%{http_code}\n" -X POST "$API_URL/storage/v1/object/attachments/$P" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "content-type: image/jpeg" --data-binary @/tmp/dv.jpg   # expect 200

# A signed-in Versely user (local test account, local stack only):
USER_JSON=$(curl -s "$API_URL/auth/v1/signup" -H "apikey: $ANON_KEY" -H "content-type: application/json" \
  -d '{"email":"versely.local@example.com","password":"local-only-test-pw-1"}')
USER_TOKEN=$(echo "$USER_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])')
USER_ID=$(echo "$USER_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["user"]["id"])')

curl -s -w "\n%{http_code}\n" "$API_URL/storage/v1/object/authenticated/attachments/$P" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $USER_TOKEN"                    # expect 400/404 "Object not found", never the bytes
curl -s -X POST "$API_URL/storage/v1/object/list/attachments" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $USER_TOKEN" \
  -H "content-type: application/json" -d '{"prefix":"daily-verse/reports/","limit":100}'   # expect []
curl -s -w "\n%{http_code}\n" -X POST "$API_URL/storage/v1/object/attachments/daily-verse/reports/00000000-0000-0000-0000-0000000000bb/1.jpg" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $USER_TOKEN" -H "content-type: image/jpeg" --data-binary @/tmp/dv.jpg   # expect 400/403 (row-level security)
curl -s -X DELETE "$API_URL/storage/v1/object/attachments" -H "apikey: $ANON_KEY" -H "Authorization: Bearer $USER_TOKEN" \
  -H "content-type: application/json" -d "{\"prefixes\":[\"$P\"]}"                 # expect [] (nothing deleted)

# Anonymous (anon key only): the same three reads/writes are refused.
curl -s -w "\n%{http_code}\n" "$API_URL/storage/v1/object/authenticated/attachments/$P" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"                     # expect 400/404

# The Versely user's own folder still works (owner read):
curl -s -X POST "$API_URL/storage/v1/object/attachments/$USER_ID/own.jpg" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "content-type: image/jpeg" --data-binary @/tmp/dv.jpg >/dev/null
curl -s -o /dev/null -w "%{http_code}\n" "$API_URL/storage/v1/object/authenticated/attachments/$USER_ID/own.jpg" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $USER_TOKEN"                   # expect 200

# The Daily Verse file is still there (service role list):
curl -s -X POST "$API_URL/storage/v1/object/list/attachments" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "content-type: application/json" -d '{"prefix":"daily-verse/reports/00000000-0000-0000-0000-0000000000aa/"}'  # expect [ {"name":"1.jpg",...} ]
```
Also note the bucket settings: `select allowed_mime_types, file_size_limit from storage.buckets where id = 'attachments';` should show JPEG among the types and a 25 MB limit.

## 8. Cron checks

```sql
-- psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
select jobname, schedule, active from cron.job order by 1;
--   daily-verse-retention | 17 3 * * * | t   (once)
--   ops-alerts-*          | …          | f   (disabled in step 4)
--   yvp-chapter-cache-expire | 23 * * * * | t
select daily_verse.purge_expired();   -- as postgres: permission denied (service role only), which is expected
set role service_role; select daily_verse.purge_expired(); reset role;   -- {"reports": 0, "rate_limits": …}
```
pg_cron in the local stack runs the job at 03:17 UTC. To see a real run sooner (optional), temporarily schedule `select cron.schedule('dv-tmp', '* * * * *', 'select daily_verse.purge_expired()');` as postgres. Check `select status, return_message from cron.job_run_details order by start_time desc limit 3;` → `succeeded`, then `select cron.unschedule('dv-tmp');`.

## 9. Rollback and re-migration by hand (in addition to run.sh)

```sh
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/rollback/20261113000000_daily_verse_reports_down.sql
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -At -c \
  "select (select count(*) from pg_namespace where nspname='daily_verse'), (select count(*) from pg_roles where rolname='daily_verse_owner'), (select count(*) from cron.job where jobname like 'daily-verse%');"
# expect 0|0|0
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/migrations/20261113000000_daily_verse_reports.sql   # re-applies cleanly
```
The local file `attachments/daily-verse/...` from step 7 remains; delete it with the service role (`DELETE /storage/v1/object/attachments` with that prefix), as ROLLBACK.md step 3 describes.

## 10. Record the results

Paste into PR #20:
- date, CLI version, Docker or Colima version, Postgres version (`select version();`)
- the `run.sh` output
- the HTTP codes from steps 6–7
- the cron listing
- any deviation, with its exact error

Gamaliel then decides separately whether to authorize the production apply.

## 11. Stop and clean up

```sh
supabase stop --no-backup        # stops the containers and deletes the local database and storage volumes
rm -rf /tmp/dv-local-supabase /tmp/dv.jpg
git status                       # supabase/config.toml and .gitignore changes from `supabase init`: keep or `git checkout -- . && rm supabase/config.toml`
# Optional, to reclaim disk:
docker image prune -a            # Docker Desktop / Colima: removes the downloaded Supabase images
colima stop && colima delete     # Colima only
```
Nothing above touches the hosted project.
