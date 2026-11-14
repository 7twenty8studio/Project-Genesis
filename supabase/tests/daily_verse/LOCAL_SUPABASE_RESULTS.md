# Local real-Supabase validation: results (13 Nov 2026)

**Result: PASSED** (run 3 on image 17.6.1.075; run 4 on the production image 17.6.1.166). Every step of [LOCAL_SUPABASE_VALIDATION.md](LOCAL_SUPABASE_VALIDATION.md) passed on a disposable local Supabase stack:
- 86/86 checks, twice, with a rollback in between
- PostgREST, Storage and cron checks
- manual rollback and re-migration
- Versely schema, policies, cron jobs, roles and ACLs identical

Nothing touched the hosted project, and no local job made a network call.

| Run | Commit | Outcome |
|---|---|---|
| 1 | ab91098 (migration as of eae10bb) | **Stopped.** `grant daily_verse_owner to current_user;` crashed the server (signal 11, segmentation fault). |
| 2 | 8f79f98 (grant and revoke name `postgres`) | Migration ✅, Versely identical ✅. **Stopped** in `tests.sql`: real Storage's delete guard (below) aborted one test. |
| 3 | 4a263d5 (test fix) | ✅ Full pass on image 17.6.1.075. |
| 4 | 4a263d5 (same migration, sha256 `670f2112…bd0d`) | ✅ Full pass on **`postgres:17.6.1.166`, the image the hosted project runs** (see "Run 4" below). |

## Environment

| | |
|---|---|
| Mac | Apple Silicon (arm64), macOS 27.0 |
| Runtime | Colima 0.10.3 (`--vm-type vz --cpu 4 --memory 8 --disk 40 --dns 1.1.1.1 --dns 8.8.8.8`), Docker CLI 29.9.3 (Homebrew) |
| Supabase CLI | 2.75.0. **Not linked** to any project: `supabase/.temp` holds only `cli-latest`, with no `project-ref`. No access token, DB password or DB URL in the environment. |
| Stack | `supabase start -x realtime,studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta`. Running: db, auth, rest, storage, kong. **No edge-runtime.** |
| Postgres | `PostgreSQL 17.6 on aarch64-unknown-linux-gnu` (image `public.ecr.aws/supabase/postgres:17.6.1.075`) |
| `config.toml` | Created by `supabase init`, not committed. `major_version = 17`, **`[db.migrations] enabled = false`**, **`[db.seed] enabled = false`** |

Run 3 started from a fresh stack (`supabase stop --no-backup`, then `supabase start`): 0 public tables, no `daily_verse` schema and no `daily_verse_owner` role.

## Run 3: steps and results

| Step | Expected | Actual |
|---|---|---|
| Versely's 27 migrations as `postgres`, by hand | 27 applied, ops jobs never active | ✅ **27/27.** `20261018030000_ops_alerts_schedule.sql` ran with `psql -1` together with `cron.alter_job(…, active := false)`. Checked **before anything else ran**: ops-alerts-check `f`, ops-alerts-digest `f`, 0 active jobs calling a URL, `net._http_response` 0, `net.http_request_queue` 0. |
| `run.sh --target local-supabase`: migrate as `postgres` | Succeeds, no crash | ✅ `grant daily_verse_owner to postgres` works. Public tables present: 47. |
| Versely unchanged after migrating | identical | ✅ schema, policies, cron, roles, acl all **identical**. The only expected addition is `postgres -> daily_verse_owner`. |
| Tests, 1st apply | 86/86 | ✅ **86 passed, 0 failed, 86 total** |
| Rollback as `postgres` | Schema, role and job gone; no crash | ✅ The revoke-by-name ran cleanly. Schema, owner role and cron job all gone. |
| Versely after rollback | identical to before | ✅ schema, policies, cron, roles, acl all **identical** |
| Re-apply, tests again | 86/86 | ✅ **86 passed, 0 failed, 86 total** |

### PostgREST (step 6)

| Call | Expected | Actual |
|---|---|---|
| `GET /rest/v1/reports`, `Accept-Profile: daily_verse`, anon key | 406 | ✅ 406 |
| Same, service-role key | 406 | ✅ 406. Refused only because `daily_verse` isn't an exposed PostgREST schema. Privileged SQL connections (`postgres`, `service_role`) are **not** denied. |
| `POST /rest/v1/rpc/purge_expired`, `Content-Profile: daily_verse`, anon | 406 | ✅ 406 |
| `POST /rest/v1/rpc/is_admin` (public), anon | 404 | ✅ 404 |
| `POST /rest/v1/rpc/submit_report` (public), service role | 404 | ✅ 404 |
| Versely `POST /rest/v1/app_feedback`, anon | 201 | ✅ 201 |

### Storage under `attachments/daily-verse/` (step 7)

All requests were made as a local test user signed up on the local stack only, or with the anon key.

| Call | Expected | Actual |
|---|---|---|
| Service role uploads `daily-verse/reports/…aa/1.jpg` | 200 | ✅ 200 |
| Versely user reads it | 400/404, no bytes | ✅ 400 `{"statusCode":"404","error":"not_found","message":"Object not found"}` |
| Versely user lists `daily-verse/reports/` | `[]` | ✅ `[]` |
| Versely user uploads under `daily-verse/` | 400/403 | ✅ 400 `{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}` |
| Versely user deletes it | `[]` | ✅ `[]` (200, nothing deleted) |
| Anon reads it | 400/404 | ✅ 400 `Object not found` |
| Anon lists `daily-verse/reports/` | `[]` | ✅ `[]` |
| Anon uploads under `daily-verse/` | 400/403 | ✅ 400 `new row violates row-level security policy` |
| Anon deletes it | `[]` | ✅ `[]` (200, nothing deleted) |
| No object was created by the refused uploads | 0 | ✅ 0 |
| Versely user reads a file in their own folder | 200 | ✅ 200 |
| Daily Verse file still present (service-role list) | `1.jpg` | ✅ `['1.jpg']` |
| Bucket `attachments` | JPEG allowed, 25 MB | ✅ `{image/jpeg,audio/mp4,application/pdf,application/octet-stream}`, 26214400 |

### Cron (step 8)

```
daily-verse-retention    | 17 3 * * *   | t
ops-alerts-check         | */5 * * * *  | f
ops-alerts-digest        | 0 13 * * *   | f
yvp-chapter-cache-expire | 23 * * * *   | t
```
- `set role service_role; select daily_verse.purge_expired();` returned `{"reports": 0, "rate_limits": 0}`.
- A temporary `dv-tmp` job (`* * * * *`, `select daily_verse.purge_expired()`) ran once with status **succeeded**. It was then unscheduled, leaving 0 `dv-tmp` jobs.
- As `postgres`, `purge_expired()` also **succeeds**. The doc expected "permission denied". See difference 3 below.

### Manual rollback and re-migration (step 9)

| Step | Result |
|---|---|
| `psql -f …_down.sql` as `postgres` | ✅ No crash. Schema, role and job counts: `0 \| 0 \| 0`. |
| Delete the Storage file with the service role | ✅ The API deleted `daily-verse/reports/…aa/1.jpg`. The one remaining `daily-verse/` row is the SQL fixture `tests.sql` inserts directly (not a file); it's gone with the stack. |
| Re-apply the migration as `postgres` | ✅ Counts `1 \| 1 \| 1` |
| Versely schema (public, storage, auth) and policies vs the first snapshot | ✅ **identical** |

## Differences from the stand-in tests

1. **Role grant to `current_user`** crashes Supabase Postgres 17.6.1.075 (run 1); plain Postgres 17 accepts it. Fixed in 8f79f98 by naming `postgres` in the grant and in the rollback's revoke.
2. **Storage delete guard.** Real Storage has a statement-level `BEFORE DELETE` trigger on `storage.objects`, `protect_objects_delete` → `storage.protect_delete()`. It raises `42501 Direct deletion from storage tables is not allowed. Use the Storage API instead.` for every role unless the transaction sets `storage.allow_delete_query = 'true'`. This aborted run 2. Changes (tests only; the migration is untouched):
   - The Versely-user delete test sets the flag **transaction-locally**, so RLS alone is what's tested. It asserts 0 rows updated and **0 deleted**.
   - A new check confirms a direct `DELETE` without the flag is blocked, even as `postgres` (`42501`).
   - A new check confirms the Daily Verse object survives both delete attempts.
   - `supabase_stubs.sql` now mirrors the trigger.
   - The flag appears in no migration.
   - Total: 84 → **86** checks.
3. **`postgres` has `service_role`'s privileges on Supabase.** `postgres` is a member of `service_role`, `pg_read_all_data` and others, with inherit. So it can read `daily_verse` tables and run its functions, as it can for every `service_role`-only object in Versely.
   - This isn't caused by the migration. A transaction-local experiment (rolled back) re-granting `daily_verse_owner` `with inherit false` changed nothing.
   - The stand-ins don't model that membership.
   - The API roles (anon, authenticated) remain fully locked out, as rows 6–7 show.
4. **Storage API error shape.** Refusals come back as HTTP 400 with an inner `statusCode` of 404 or 403. The doc's "400/404" and "400/403" expectations cover this.

## Safety evidence, run 3 (end of run, before stopping)

```
cron.job:  daily-verse-retention    | active = t  (local: select daily_verse.purge_expired(); no URL)
           ops-alerts-check         | active = f
           ops-alerts-digest        | active = f
           yvp-chapter-cache-expire | active = t  (local DELETE on public.yvp_chapter_cache; no URL)
           active jobs calling a URL or ops_call_alerts: 0
cron.job_run_details: 1 run in total (dv-tmp, succeeded)
net._http_response: 0 rows    net.http_request_queue: 0 rows  → pg_net never sent a request
vault.decrypted_secrets: ops_cron_secret only (64 hex chars, generated locally by the migration; not a real secret)
```
- edge-runtime was not started.
- No `supabase link`, `--linked`, `db push`, `migration repair` or hosted `--db-url` was used.
- No admin was seeded.

## Run 4: production image `postgres:17.6.1.166` (14 Nov 2026)

The hosted project runs Postgres **17.6.1.166**, while runs 1–3 used 17.6.1.075, the image where `current_user` crashed. Run 4 repeated the full procedure on 17.6.1.166, from a fresh stack, with the same safety rules.
- **Image selection:** `supabase/.temp/postgres-version` was set to `17.6.1.166` (removed afterwards; never committed).
- **Image that ran:** `docker inspect` showed `public.ecr.aws/supabase/postgres:17.6.1.166`.
- **Version:** `select version()` → `PostgreSQL 17.6 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 15.2.0, 64-bit`.
- **Stack:** the same `-x` exclusions, so no edge-runtime. `config.toml` had migrations and seed disabled; no link and no tokens. It started empty: 0 public tables, no `daily_verse`.

| Step | Result |
|---|---|
| Versely's 27 migrations by hand, ops jobs inactive in the same transaction | ✅ 27/27. Checked first: ops-alerts-check `f`, ops-alerts-digest `f`, 0 active jobs calling a URL, `net._http_response` 0, queue 0 |
| `run.sh --target local-supabase` | ✅ Migrated as `postgres` with no crash. 47 public tables. Versely schema, policies, cron, roles and acl **identical** (+ `postgres -> daily_verse_owner`). **86/86** → rollback (schema, role and job gone; no crash) → Versely identical → re-apply → **86/86** |
| PostgREST | ✅ 406, 406, 406, 404, 404. Versely `app_feedback` 201. Same as run 3. |
| Storage (Versely user and anon) | ✅ read 400/404 · list `[]` · upload 400/403 RLS · delete `[]` · 0 objects created · own-folder read 200 · Daily Verse file kept · bucket JPEG and 25 MB. Same as run 3. |
| Cron | ✅ `daily-verse-retention 17 3 * * * t`, ops jobs `f`. `purge_expired()` as service_role returned `{"reports": 0, "rate_limits": 0}`. A temporary `dv-tmp` job ran twice, `succeeded`, and was unscheduled. |
| Manual rollback | ✅ `0\|0\|0`. Storage file deleted through the API. |
| Re-apply **in one transaction** (`psql --single-transaction`, the production method) | ✅ `1\|1\|1`. Versely schema and policies identical to the first snapshot. |
| `prod_fingerprint.sql` as `postgres`, rollback → apply | ✅ Runs on real Supabase. **0 `versely.*` rows differ.** `daily_verse.*` went from `n/a\|0\|0\|0` to `0\|1\|1\|1`. |
| Safety at the end | ✅ ops jobs `f`, 0 active jobs calling a URL, `net._http_response` 0, queue 0, vault `ops_cron_secret` only (64 characters, local), cron runs: `succeeded` only |

**Differences from run 3:** none in behaviour or results. The only differences are the image tag, and the extra single-transaction re-apply and fingerprint check.

**Hashes, unchanged:**
- migration `670f2112f5180a2391ad87e107d6613de55f7343c5282178c74c77912e0bbd0d`
- rollback `452ded13f34e3a9c22699ace312fcd0a3db3e97d3c9d9f3ec0e6da6612a0f580`

## Note on the service-role 406
PostgREST refuses `daily_verse` for every key, the service-role key included, **only because `daily_verse` isn't an exposed API schema**. That's API isolation, not database access control.
- Privileged SQL connections (`postgres`, which inherits `service_role` and `pg_read_all_data` on Supabase, and `service_role` itself) can read `daily_verse`.
- Gamaliel accepted this on 14 Nov 2026.

## Cleanup
- `supabase stop --no-backup` deleted the local database and storage volumes.
- `colima stop`; Colima and Docker remain installed.
- `supabase/config.toml` and `supabase/.gitignore` stay untracked.

To remove everything:
```sh
colima delete                      # deletes the VM and all images (~8 GB)
brew uninstall colima docker
rm -rf ~/.colima
cd ~/Desktop/7Twenty8/Project-Genesis && rm supabase/config.toml supabase/.gitignore
```
