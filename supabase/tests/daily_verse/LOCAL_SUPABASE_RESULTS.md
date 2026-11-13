# Local real-Supabase validation: results (13 Nov 2026)

**Result: STOPPED at the migration step.**
- The Daily Verse migration crashes the database server on real Supabase Postgres 17.6.
- PR #20 is **not ready** for final approval until that is fixed and the full procedure passes.
- Nothing touched the hosted project. No local job made any network call.

## Environment

| | |
|---|---|
| Mac | Apple Silicon (arm64), macOS 27.0 |
| Runtime | Colima 0.10.3 (`--vm-type vz --cpu 4 --memory 8 --disk 40 --dns 1.1.1.1 --dns 8.8.8.8`), Docker CLI 29.9.3 / engine 29.5.2 (Homebrew) |
| Supabase CLI | 2.75.0, **not linked** to any project (no `supabase/.temp/project-ref`); no access token or DB URL in the shell |
| Stack | `supabase start -x realtime,studio,imgproxy,edge-runtime,logflare,vector,supavisor,mailpit,postgres-meta` (no edge-runtime) |
| Postgres | `PostgreSQL 17.6 on aarch64-unknown-linux-gnu` (image `public.ecr.aws/supabase/postgres:17.6.1.075`) |
| Images pulled | ~8 GB (postgres 5.5 GB, storage-api 1.0 GB, realtime 0.66 GB, postgrest 0.59 GB, kong 0.21 GB, gotrue 0.07 GB) |
| `config.toml` | Created by `supabase init` (not committed). `major_version = 17`; **`[db.migrations] enabled = false`** and **`[db.seed] enabled = false`** (see the safety notes) |

## Steps and results

| Step | Expected | Actual |
|---|---|---|
| Install Colima + Docker | `docker info` works | ✅ After restarting Colima with `--dns 1.1.1.1 --dns 8.8.8.8`; the default VM DNS timed out while pulling images. |
| `supabase start` | Stack up | ✅ PostgreSQL 17.6, empty database. **Note:** with the default config, `supabase start` applies every migration on first boot, including Versely's ops-alerts cron jobs. That's why automatic migrations were disabled and applied by hand (next row). |
| Apply Versely's 27 migrations as `postgres` | 27 applied | ✅ **27/27** by `psql`, one file at a time. `20261018030000_ops_alerts_schedule.sql` ran in **one transaction** together with `select cron.alter_job(jobid, active := false) …` for every job calling `ops_call_alerts` or http, so those jobs were never active. (On real Supabase, `postgres` can't `UPDATE cron.job` directly; `cron.alter_job` is the supported way.) |
| Apply `20261113000000_daily_verse_reports.sql` as `postgres` | Migration succeeds | ❌ **Server crash.** Statement `grant daily_verse_owner to current_user;` (line 30): the database log shows `server process (PID 354) was terminated by signal 11: Segmentation fault`, then `all server processes terminated; reinitializing`. The preceding `CREATE ROLE daily_verse_owner` succeeded. |
| 84 checks ×2, rollback, Versely diff | 84/84, identical | **Not run**: stopped at the failing step, as instructed. |
| PostgREST, Storage, cron checks | see LOCAL_SUPABASE_VALIDATION.md | **Not run** |

### Diagnostic (read-only intent, local stack only)
`grant daily_verse_owner to postgres;` (the role named explicitly instead of `current_user`), run as `postgres`, **succeeded with no crash** (`GRANT ROLE`). Membership was then `set=true inherit=true`, alongside the automatic admin-only membership from `CREATE ROLE`.
- **Likely cause:** a Supabase extension hook that intercepts role grants (supautils / pgaudit) mishandles the `CURRENT_USER` role specification. It doesn't appear on plain Postgres 17 (the stand-in suite passes 84/84).
- **Proposed fix, for review, not applied:**
  - In the migration, replace `grant daily_verse_owner to current_user;` with `grant daily_verse_owner to postgres;`. Hosted migrations run as `postgres`.
  - In the rollback, replace `revoke daily_verse_owner from current_user` with `revoke daily_verse_owner from postgres`, since it likely hits the same code path.
  - Then re-run this whole procedure.

## Safety evidence (no local job could reach production)

At the end of the run, before stopping:
```
cron.job:  ops-alerts-check | active = f
           ops-alerts-digest | active = f
           yvp-chapter-cache-expire | active = t   (local DELETE on public.yvp_chapter_cache only; no URL)
net._http_response: 0 rows     net.http_request_queue: 0 rows   → pg_net never sent a request
vault.decrypted_secrets: ops_cron_secret (64 hex chars, generated locally by the migration with gen_random_bytes; not a real secret)
```
- edge-runtime was not started.
- No `supabase link`, `--linked`, `db push`, `migration repair` or hosted `--db-url` was used.
- No admin was seeded anywhere.

## Cleanup done
- `supabase stop --no-backup` deleted the local database and storage volumes.
- `colima stop`; Colima and Docker stay installed.
- `supabase/config.toml` and `supabase/.gitignore` are left untracked and uncommitted.

To remove everything:
```sh
colima delete                      # deletes the VM and all images (~8 GB)
brew uninstall colima docker       # removes the tools
rm -rf ~/.colima                   # leftover settings, if any
cd ~/Desktop/7Twenty8/Project-Genesis && rm supabase/config.toml supabase/.gitignore
```
