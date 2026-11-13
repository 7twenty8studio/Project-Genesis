# Rolling back the Daily Verse Games reports migration

Migration: `supabase/migrations/20261113000000_daily_verse_reports.sql`
Down script: `supabase/rollback/20261113000000_daily_verse_reports_down.sql`

The migration only adds the following, so rolling back only removes them:

- the `daily_verse` schema (with its tables and functions)
- the `daily_verse_owner` role
- the `daily-verse-retention` pg_cron job

Nothing in `public`, `storage` or `auth` is created or changed, so Versely is unaffected either way. The local test (`supabase/tests/daily_verse/run.sh`) checks that public, storage, auth, policies, grants, roles and Versely's cron jobs are identical before the migration and after the rollback.

## When to roll back

- The migration was applied and must be withdrawn before Daily Verse reporting goes live.
- A defect is found in the schema and a corrected migration will replace it. Prefer a forward fix if any real reports exist.

## Procedure (production needs the owner's explicit approval)

1. **Stop new writes.** Make sure the `dv-report` / `dv-admin` Edge Functions (PR B) are not deployed, or undeploy them first: `supabase functions delete dv-report dv-admin`. Unschedule the screenshot cleanup job if PR B added one.

2. **Keep a copy, if any reports matter.** In the SQL editor:
   ```sql
   copy (select * from daily_verse.reports) to stdout with csv header;        -- or export from the Table Editor
   copy (select * from daily_verse.report_events) to stdout with csv header;
   ```
   Note the admin allow-list (`select * from daily_verse.admins;`) so it can be re-seeded.

3. **Remove screenshot files.** SQL can't delete Storage objects, so use the Storage API or the dashboard. Delete everything under `attachments/daily-verse/`. Touch nothing else in that bucket: every other path there belongs to a Versely user.
   ```sh
   # list first, check, then remove (supabase CLI ≥ 2.x, linked project)
   supabase storage ls ss:///attachments/daily-verse/ --recursive
   supabase storage rm ss:///attachments/daily-verse/ --recursive
   ```

4. **Run the down script** as `postgres` (SQL editor, or `psql "$DB_URL" -f supabase/rollback/20261113000000_daily_verse_reports_down.sql`). It unschedules the cron job, drops the `daily_verse` schema with CASCADE, and drops the `daily_verse_owner` role.

5. **Mark the migration as reverted** so `supabase db push` doesn't consider it applied:
   ```sh
   supabase migration repair --status reverted 20261113000000
   ```

6. **Verify:**
   ```sql
   select count(*) from pg_namespace where nspname = 'daily_verse';        -- 0
   select count(*) from pg_roles where rolname = 'daily_verse_owner';      -- 0
   select jobname from cron.job order by 1;   -- only Versely's jobs (ops-alerts-check, ops-alerts-digest, yvp cache)
   ```

## Re-applying later

Run the migration again; it is self-contained. Then re-run the reviewed admin seed (`supabase/seed/daily_verse_admins.sql`), and only with the owner's approval.

## Tested locally

`supabase/tests/daily_verse/run.sh` runs migrate → 86 tests → rollback → compares Versely's schema → migrate again → 86 tests, on a throwaway Postgres 17 with Supabase stand-ins or (`--target local-supabase`) on a real local Supabase stack, where it passed on 13 Nov 2026 (`supabase/tests/daily_verse/LOCAL_SUPABASE_RESULTS.md`). No hosted staging project or branch exists. The rollback is part of the required gate in `supabase/tests/daily_verse/PRODUCTION_GATE.md` before any production apply.
