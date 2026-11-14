# Production deployment plan: PR A (Daily Verse reports schema)

**Status: plan only. Nothing in this document has been run against production.** Each step marked 🔒 needs Gamaliel's explicit authorization at the time it is done.

## Final checklist: Saturday 14 Nov 2026, 10:00 Central (16:00 UTC)

**Migration to apply:** `supabase/migrations/20261113000000_daily_verse_reports.sql`
- **sha256 `670f2112f5180a2391ad87e107d6613de55f7343c5282178c74c77912e0bbd0d`**, the same file reviewed at 4a263d5 and still unchanged at 82b4d15 and later.
- Rollback `452ded13f34e3a9c22699ace312fcd0a3db3e97d3c9d9f3ec0e6da6612a0f580`. Seed (not part of this window) `dd5ebb3cccee35f17eb85cdd6e9b96468e17cf40622fcda9edb2034b7764f0c4`.

**Already done:**
- [x] Real local Supabase validation on the production image 17.6.1.166: run 4 in `LOCAL_SUPABASE_RESULTS.md`.
- [x] Window agreed: Sat 14 Nov 2026, 10:00 CT / 16:00 UTC. It avoids the 13:00 UTC digest and 03:17 UTC.
- [x] Physical backups confirmed by Gamaliel. Latest seen on 13 Nov: **13 Nov 2026 07:57:31 UTC (01:57:31 CT)**, physical, with a Restore option.

**Window day, in order.** Stop at the first unexpected result; nothing changes in production until step 9.

| # | Step | Who | Expected | Section |
|---|---|---|---|---|
| 1 | **Re-verify the backup.** Dashboard → Database → Backups. | Gamaliel | A physical backup dated **14 Nov 2026, about 07:57 UTC** (the daily one, about 8 h before the window), status completed, with Restore available. **If the newest is still 13 Nov 07:57 UTC (about 32 h old), stop and decide.** | §1 |
| 2 | Record that backup's timestamp in the PR, and re-read the recovery procedure (§8), including its Storage limits. | Gamaliel / Claude | Recorded | §1, §8 |
| 3 | A schema-only `pg_dump` and a Storage inventory, saved outside the repo | Gamaliel connects; Claude runs them (A1) | Files written | §1 |
| 4 | Migration and rollback hashes on `main` after the merge | Claude | `670f2112…bd0d` / `452ded13…0f580` | §3.1 |
| 5 | Migration history checks | Claude (A1) | 23 rows (or explained), no `20261113000000`, columns recorded | §3.2 |
| 6 | Compatibility checks, image still 17.6.1.166, `daily_verse` not exposed | Claude (A1) | As listed | §3.3 |
| 7 | Versely fingerprint, BEFORE | Claude (A1) | Saved; `daily_verse.*` = `n/a\|0\|0\|0` | §3.4 |
| 8 | **Go / no-go**, reported to Gamaliel | Claude → Gamaliel | Every row above as expected | — |
| 9 | **Explicit authorization to apply (A3)**, then the one-transaction apply | Gamaliel | `psql` exits 0 | §4 |
| 10 | Post-checks: history, fingerprint diff, lockdown, API 406, Versely smoke test | Claude + Gamaliel (phone) | 0 Versely rows differ; `daily_verse.*` = `0\|1\|1\|1` | §5 |
| 11 | Record the results in the PR. Watch for 24 h; confirm the 03:17 UTC run on 15 Nov | Claude / Gamaliel | `succeeded` | §5.6–5.7 |

**Separate approvals that are not part of this window:** A2 (merge PR #20, needed before step 4), A4 (rollback, only on a trigger), A5 (admin seed) and PR B.

---

| | |
|---|---|
| Project | Existing Project Genesis Supabase project `ulbpwygzwchsnvdeeife` (Postgres 17.6.1.166). No new project, branch or bucket. |
| Migration | `supabase/migrations/20261113000000_daily_verse_reports.sql`, sha256 `670f2112f5180a2391ad87e107d6613de55f7343c5282178c74c77912e0bbd0d`. Unchanged since review at 4a263d5. |
| Rollback | `supabase/rollback/20261113000000_daily_verse_reports_down.sql`, sha256 `452ded13f34e3a9c22699ace312fcd0a3db3e97d3c9d9f3ec0e6da6612a0f580` |
| Admin seed (separate) | `supabase/seed/daily_verse_admins.sql`, sha256 `dd5ebb3cccee35f17eb85cdd6e9b96468e17cf40622fcda9edb2034b7764f0c4` |
| Read-only Versely fingerprint | `supabase/tests/daily_verse/prod_fingerprint.sql` |
| Validation evidence | `LOCAL_SUPABASE_RESULTS.md`. Real local Supabase on **the production image `postgres:17.6.1.166`** (run 4) and on 17.6.1.075 (run 3). Each run: 86/86 twice, PostgREST, Storage, cron, rollback, a one-transaction re-apply, Versely identical. |
| Out of scope | PR B (Edge Functions, secrets, screenshot-cleanup job), the admin dashboard tab, any app change, exposed-schema or bucket settings |

**What the migration does in production.** It only *adds* objects:
- the `daily_verse` schema, its tables and functions
- the `daily_verse_owner` role, granted to `postgres`
- one pg_cron job, `daily-verse-retention` (03:17 UTC; local SQL only, no network call)

It creates, alters or drops nothing in `public`, `storage` or `auth`, and takes no lock on any Versely table. It runs in a few seconds. With PR B not deployed, nothing writes to the new tables, so a rollback loses no data.

## Why not `supabase db push`

The hosted migration history (`supabase_migrations.schema_migrations`) doesn't match the repo:
- The hosted history has 23 entries with dashboard-style versions, for example `20261007170307_attachments`.
- The repo has 27 files under other versions.

So `db push` would try to re-run Versely's migrations. **Never use `supabase db push`, `supabase migration repair` or `supabase link` for this deployment.**

Production applies **only** this one file:
- as `postgres`
- in **one transaction** (`psql --single-transaction`), validated locally on 17.6.1.166
- with one history row added in the same transaction

The hosted history's existing rows are not touched.

## Who runs what

- **Gamaliel runs every step that needs production credentials.** He copies the connection string from Dashboard → **Connect** (direct connection or session pooler, user `postgres`) and types the password when `psql` asks for it. Claude never types a password or token.
- **On this Mac, Claude can run only the read-only checks**, and only once Gamaliel has entered the password himself and has authorized that specific step.
- **The Supabase connector's `apply_migration` isn't used.** It would record its own version number. The connector's read-only SQL may be used for the checks in steps 1 and 3 if Gamaliel prefers.

```sh
# Once, in Gamaliel's terminal (the password is NOT part of the string; psql prompts for it):
export PROD="postgresql://postgres.ulbpwygzwchsnvdeeife@<pooler-host>:5432/postgres?sslmode=require"   # from Dashboard → Connect
PSQL=/opt/homebrew/opt/postgresql@17/bin/psql
```

---

## Checklist

### 1. Recoverable backup or restore point (window day, before anything else) 🔒 read-only
1. Dashboard → **Database → Backups**:
   - The project has **scheduled daily physical backups** with a Restore option (confirmed by Gamaliel). The latest seen on 13 Nov is **13 Nov 2026 07:57:31 UTC**.
   - On the window day, confirm a newer backup: **14 Nov 2026, about 07:57 UTC**, completed, with Restore available. Record its exact timestamp in the PR.
   - **If no backup from 14 Nov is listed, stop and decide before continuing** (wait for it, or accept the 13 Nov backup knowingly).
   - Note whether Point-in-Time Recovery is enabled. As of 13 Nov, only daily physical backups were seen.
2. **Supabase database backups don't include Storage file contents.** They do include the `storage.objects` metadata rows, because those live in the database. See §8 for what that means for a restore.
   - PR A writes **no** Storage files, and `attachments/daily-verse/` stays empty until PR B. So no Storage data is at risk from this migration.
3. **Take local copies on this Mac**, stored **outside the repository** and never committed:
   ```sh
   D=~/Desktop/7Twenty8/prod-backups/2026-11-14 && mkdir -p "$D" && chmod 700 "$D"
   /opt/homebrew/opt/postgresql@17/bin/pg_dump "$PROD" --schema-only -n public -n storage -n auth -f "$D/schema-before.sql"
   # Storage inventory (metadata only, no file contents): for reconciling files with metadata if a restore is ever needed (§8)
   $PSQL "$PROD" -X -At -c "\copy (select bucket_id, name, coalesce(metadata->>'size',''), created_at, updated_at from storage.objects order by 1,2) to '$D/storage-inventory-before.csv' csv header"
   $PSQL "$PROD" -X -At -c "select bucket_id, count(*), coalesce(sum((metadata->>'size')::bigint),0) from storage.objects group by 1 order by 1" > "$D/storage-summary-before.txt"
   ```
   - The inventory lists object paths, which start with user IDs. Keep it private and delete it once the window has passed without incident.
   - A data dump would contain users' personal data. Take one only if Gamaliel wants it, and store it encrypted.
4. **Record in the PR:** the backup timestamp, whether PITR is enabled, and the dump and inventory file names and sizes. The PR gets names and sizes only, never the contents.

### 2. Deployment window
- **Agreed:** Saturday 14 Nov 2026, **10:00 Central (16:00 UTC)**. Book 30 minutes: the apply takes seconds, and the rest is checks and watching.
- **Clear of the scheduled jobs:**
  - the ops digest (13:00 UTC)
  - the new retention job (03:17 UTC)
  - the daily backup (~07:57 UTC)

  `ops-alerts-check` runs every 5 minutes; it doesn't conflict, and its next run is part of the smoke test.
- **No freeze is needed.** Versely stays online. Don't ship a Versely release or any other database change in the same window.

### 3. History and compatibility checks (immediately before applying) 🔒 read-only
1. **The file being applied is the reviewed one:**
   ```sh
   cd ~/Desktop/7Twenty8/Project-Genesis && git fetch origin && git checkout main && git pull --ff-only   # after A2 (merge)
   shasum -a 256 supabase/migrations/20261113000000_daily_verse_reports.sql supabase/rollback/20261113000000_daily_verse_reports_down.sql
   # must print 670f2112…bd0d and 452ded13…0f580
   ```
2. **History** (read-only):
   ```sql
   select count(*) from supabase_migrations.schema_migrations;                                   -- 23 (as seen 14 Nov)
   select version, name from supabase_migrations.schema_migrations order by version desc limit 5;  -- note the newest
   select count(*) from supabase_migrations.schema_migrations where version = '20261113000000';  -- 0
   select column_name, data_type, is_nullable from information_schema.columns
    where table_schema = 'supabase_migrations' and table_name = 'schema_migrations' order by ordinal_position;
   ```
   - **Record** the column list. The history insert in step 4 uses `version`, `name` and `statements`, and must match these columns. If other columns are NOT NULL without a default, stop and adjust the insert under review.
   - **Stop** if a `20261113000000` row already exists, or if the count differs from what was last seen without explanation.
3. **Compatibility** (read-only):
   ```sql
   select version();                                                          -- PostgreSQL 17.6
   select extname, extversion from pg_extension where extname in ('pg_cron','pg_net','pgcrypto') order by 1;  -- pg_cron present
   select count(*) from pg_namespace where nspname = 'daily_verse';          -- 0
   select count(*) from pg_roles where rolname = 'daily_verse_owner';        -- 0
   select rolcreaterole from pg_roles where rolname = 'postgres';            -- t
   select jobname, schedule, active from cron.job order by 1;                -- Versely's jobs only; nothing named daily-verse%
   select id, allowed_mime_types, file_size_limit from storage.buckets where id = 'attachments';   -- includes image/jpeg
   ```
   - Also check Dashboard → **API settings → Exposed schemas**. It must not include `daily_verse`, and it stays as it is.
   - Get the Postgres image version from Dashboard → Settings → Infrastructure. **Stop** if it's no longer 17.6.1.166: re-validate locally on the new image first.
4. **Versely fingerprint, BEFORE:**
   ```sh
   $PSQL "$PROD" -X -At -v ON_ERROR_STOP=1 -f supabase/tests/daily_verse/prod_fingerprint.sql > ~/Desktop/7Twenty8/prod-backups/$(date +%F)/fingerprint-before.txt
   ```
   The `daily_verse.*` rows must read `n/a | 0 | 0 | 0`.

**Go / no-go:** the backup from step 1 is in place and 3.1–3.4 are as expected. Otherwise **stop and report**: nothing has been changed yet.

### 4. Apply 🔒 (separate authorization, in the window)
1. **Merge PR #20 to `main` (A2).** What's applied is then exactly what's on `main`; re-check the hashes (3.1). PR B is not merged.
2. **Apply in one transaction**, with the history row recorded in that same transaction:
   ```sh
   cd ~/Desktop/7Twenty8/Project-Genesis
   { cat supabase/migrations/20261113000000_daily_verse_reports.sql
     printf '\ninsert into supabase_migrations.schema_migrations (version, name, statements)\n'
     printf "values ('20261113000000', 'daily_verse_reports', array[\$dvmig\$%s\$dvmig\$]);\n" "$(cat supabase/migrations/20261113000000_daily_verse_reports.sql)"
   } > /tmp/dv-apply.sql
   shasum -a 256 /tmp/dv-apply.sql            # record it in the PR
   $PSQL "$PROD" -X --single-transaction -v ON_ERROR_STOP=1 -f /tmp/dv-apply.sql
   ```
   - `statements` holds the file's text, with the final newline trimmed by `$(cat …)`. It's for the record only. The authoritative check is the file's SHA-256, recorded in the PR.
   - **Tested on stand-ins:** the apply file, the history row, the rollback transaction, and the all-or-nothing behaviour (a deliberately broken copy left `0|0|0|0`).
   - `--single-transaction` plus `ON_ERROR_STOP` makes it **all or nothing**. If any statement fails, Postgres rolls everything back, history row included, and production is left exactly as it was.
   - **Don't** run it from the SQL editor: it doesn't guarantee one transaction for a multi-statement script.
   - The single-transaction apply was tested on the production image locally (`LOCAL_SUPABASE_RESULTS.md`, run 4).
3. **If `psql` reports an error:** copy it exactly and stop. Then confirm nothing was left behind (step 6A.4 should print `0|0|0` and no history row). Report it; don't retry without review.

### 5. Post-migration checks (immediately after) 🔒 read-only
1. **History:**
   ```sql
   select version, name from supabase_migrations.schema_migrations where version = '20261113000000';   -- one row
   select count(*) from supabase_migrations.schema_migrations;                                          -- previous count + 1
   ```
2. **Versely unaffected:**
   ```sh
   $PSQL "$PROD" -X -At -v ON_ERROR_STOP=1 -f supabase/tests/daily_verse/prod_fingerprint.sql > ~/Desktop/7Twenty8/prod-backups/$(date +%F)/fingerprint-after.txt
   diff <(grep '^versely\.' fingerprint-before.txt | grep -v _count) <(grep '^versely\.' fingerprint-after.txt | grep -v _count)   # no output
   ```
   - Every `versely.*` row must be **identical**, except `storage_objects_count` and `auth_users_count`, which live traffic can change.
   - The `daily_verse.*` rows must read `0 | 1 | 1 | 1`: admins 0 (no seed), then cron job, role and schema.
   - Optionally, `pg_dump --schema-only` again and `diff` it against `schema-before.sql`. There should be no difference outside `daily_verse`.
3. **Daily Verse is locked down** (read-only):
   ```sql
   select has_schema_privilege('anon','daily_verse','usage'), has_schema_privilege('authenticated','daily_verse','usage');   -- f, f
   select c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'daily_verse' and c.relkind = 'r' order by 1;                          -- every table: t
   select count(*) from pg_policies where schemaname = 'daily_verse';                         -- 0
   select p.proname, p.proacl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'daily_verse' order by 1;            -- only daily_verse_owner and service_role
   select jobname, schedule, active from cron.job order by 1;    -- Versely's as before + daily-verse-retention 17 3 * * * t
   select count(*) from daily_verse.admins;                      -- 0
   ```
4. **API isolation**, using the public anon key from the app config:
   ```sh
   curl -s -o /dev/null -w "%{http_code}\n" "https://ulbpwygzwchsnvdeeife.supabase.co/rest/v1/reports" \
     -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" -H "Accept-Profile: daily_verse"     # 406
   ```
   - That 406 comes from `daily_verse` not being an **exposed PostgREST schema**: the API, even with the service-role key, can't reach it. Privileged **SQL** connections (`postgres`, `service_role`) are not denied, which is accepted (Gamaliel, 14 Nov).
   - **Don't run `tests.sql` or `run.sh` in production.** They insert test users and storage rows.
5. **Versely smoke test** on a real device, with Gamaliel's own account:
   - sign in
   - open notes and a Bible chapter
   - view an existing attachment
   - the 7twenty8 `/admin` ops dashboard loads
   - after the next `*/5` run, `select j.jobname, d.status from cron.job_run_details d join cron.job j using (jobid) order by d.start_time desc limit 3;` shows `succeeded` for `ops-alerts-check`
6. **Watch** for 24 hours: the ops dashboard and email alerts, plus Dashboard → Logs (Postgres, API) for new errors. After the next 03:17 UTC, confirm that `daily-verse-retention` reports `succeeded`.
7. **Record in the PR:**
   - the time applied
   - the `dv-apply.sql` hash
   - the outputs of 5.1–5.5
   - the fingerprint rows: counts and hashes only, with no user data

### 6. Rollback or forward fix
**When to act:**
- **Roll back** if the post-checks show any change in a `versely.*` fingerprint row, a Versely smoke test fails, or new Versely errors appear that relate to the window.
- **Fix forward** for defects inside the Daily Verse objects.
- **If the apply itself fails**, the single transaction has already undone everything, so no rollback is needed. Just verify with 6A.4.

**A. Rollback with the down script** 🔒 (preferred while PR B isn't deployed and no reports exist):
1. Confirm nothing has written data:
   - `select count(*) from daily_verse.reports;` returns 0
   - no `dv-*` Edge Function exists
   - `attachments/daily-verse/` is empty in Storage
2. Run the down script and the history-row delete in **one transaction**:
   ```sh
   { cat supabase/rollback/20261113000000_daily_verse_reports_down.sql
     echo "delete from supabase_migrations.schema_migrations where version = '20261113000000';"
   } | $PSQL "$PROD" -X --single-transaction -v ON_ERROR_STOP=1 -f -
   ```
   The down script was tested on 17.6.1.166 and is idempotent. Never use `migration repair`.
3. After PR B is live, also follow `ROLLBACK.md` steps 1–3: stop the functions, export the reports, then delete `attachments/daily-verse/` through the Storage API.
4. Verify:
   ```sql
   select (select count(*) from pg_namespace where nspname='daily_verse'), (select count(*) from pg_roles where rolname='daily_verse_owner'),
          (select count(*) from cron.job where jobname like 'daily-verse%'),
          (select count(*) from supabase_migrations.schema_migrations where version = '20261113000000');     -- 0|0|0|0
   ```
   Then re-run `prod_fingerprint.sql`: every `versely.*` row must equal the BEFORE file.

**B. Forward fix:**
- Write a new migration with a later version, validate it with `run.sh --target local-supabase` on the production image, and apply it with this same checklist (one file, one transaction, one history row).
- **Never edit** `20261113000000_daily_verse_reports.sql` once it's applied.

**C. Restore from backup** 🔒 (last resort; a separate decision): see **§8 Recovery procedure**. Use it only if Versely data itself were damaged. The migration doesn't touch Versely data, so for any problem limited to `daily_verse`, use A (down script) or B (forward fix).

### 7. Admin seed: separate approval 🔒 (not part of the window)
- The seed adds only `7twenty8studio@gmail.com` to `daily_verse.admins`. No other address, now or later, without written approval.
- **Recommended timing:** together with PR B's authorization. Nothing reads the allow-list until `dv-admin` exists.
- When authorized:
  1. Check the seed's hash (`dd5ebb3c…f0c4`).
  2. Run `$PSQL "$PROD" -X --single-transaction -v ON_ERROR_STOP=1 -f supabase/seed/daily_verse_admins.sql`.
  3. Verify with `select email, note, created_at from daily_verse.admins;`. Expect exactly one row.
  4. Record it in the PR.

---

### 8. Recovery procedure (restore from the physical backup) 🔒 separate decision
**Use this only if Versely's own data or schema were damaged.** That is not expected: the migration only adds `daily_verse` objects, and it's all-or-nothing. For anything else, use §6A or §6B.

**What a restore does:**
- Returns the **whole database** to the backup's timestamp. For the 14 Nov backup that's about 07:57 UTC, roughly 8 h before the window. Every database write after that point is lost, from all users: sign-ups (`auth.users`), synced notes, prayers, sermons, groups, feedback, ops items and Bible-cache rows. It can't be undone.
- **Takes the project offline** while it runs, for minutes to hours depending on size. Versely's API, sign-in, sync and the ops dashboard are unavailable meanwhile.
- **Doesn't restore Storage file contents.** Files in Storage buckets stay exactly as they are at restore time. Only the `storage.objects` metadata rows rewind, which creates two mismatches:
  - **Files uploaded after the backup** (for example Versely attachments on the morning of the window) still exist in Storage but have no metadata row. The app and API can't see them; they're orphans.
  - **Files deleted after the backup** get their metadata rows back, but the content is gone. Downloads fail (404 or error).
- Doesn't touch Edge Functions, their secrets, Auth settings or API settings (exposed schemas). Those aren't in the database backup and stay as they are.

**Procedure:**
1. **Decide.** Gamaliel authorizes the restore explicitly, after weighing the data loss above against the damage.
2. **Optional, to keep recent data:** before restoring, export whatever must be kept and can be re-entered, for example `copy (…) to stdout` of the affected tables. Personal data must be stored encrypted and outside the repo.
3. **Keep the current Storage state for reconciliation:** run the Storage inventory query from §1.3 again, as `storage-inventory-pre-restore.csv`.
4. **Restore.** Dashboard → Database → Backups → choose the backup (normally the 14 Nov ~07:57 UTC one, the newest before the window) → **Restore**, and confirm. Wait for the project to report healthy.
5. **Verify the database:**
   - `select version();`
   - `prod_fingerprint.sql`: the `versely.*` rows should match `fingerprint-before.txt`. The two `_count` rows may differ, since the backup predates the window.
   - `daily_verse.*` rows read `n/a|0|0|0`, because the backup predates the migration.
   - `select count(*) from supabase_migrations.schema_migrations where version = '20261113000000';` returns 0.
   - `select jobname, active from cron.job order by 1;` shows Versely's jobs as before, with ops alerts active.
6. **Reconcile Storage.** Compare `storage-inventory-pre-restore.csv` with the restored `storage.objects`:
   - Objects present before the restore but missing now are orphans; they need re-registering or re-uploading by the owning user.
   - Restored rows whose files were deleted after the backup should be removed through the Storage API.

   PR A adds nothing here; `attachments/daily-verse/` is empty.
7. **Smoke-test Versely** as in §5.5, and watch the ops dashboard.
8. **Record** in the PR: what was restored, the backup timestamp, the data-loss window, and the Storage reconciliation outcome.
9. Re-apply the migration later, from this checklist, only with a new authorization.

## Authorizations requested (each one a separate yes)

| # | Action | Changes production? |
|---|---|---|
| A1 | Steps 1 and 3: Gamaliel connects; read-only backup, history, compatibility and fingerprint checks | No (reads only) |
| A2 | Step 4.1: merge PR #20 to `main` | No (repository only) |
| A3 | Steps 4.2 and 5: the one-transaction apply of `20261113000000_daily_verse_reports.sql` plus its history row, in the chosen window, then the read-only post-checks | **Yes**: adds the `daily_verse` schema, the role, the cron job and 1 history row |
| A4 | Step 6A: the rollback transaction, only if a rollback trigger occurs | Yes |
| A5 | Step 7: the admin seed (`7twenty8studio@gmail.com` only) | Yes: one row |

PR B (Edge Functions and secrets) stays paused and isn't covered by any of these.
