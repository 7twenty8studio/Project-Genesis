# Daily Verse reports: local database tests

```sh
brew install postgresql@17          # once
supabase/tests/daily_verse/run.sh   # stand-ins, no Docker
# real local Supabase (Docker), see LOCAL_SUPABASE_VALIDATION.md:
supabase/tests/daily_verse/run.sh --target local-supabase
```

There's no Docker and no network involved, and nothing touches a Supabase project. The script:

1. Starts a throwaway Postgres 17 and loads `supabase_stubs.sql`. That file has stand-ins for the Supabase pieces the migrations use: the roles `anon`, `authenticated` and `service_role` (with BYPASSRLS); a non-superuser `postgres`; `auth.uid()`; `storage.objects` with RLS; and `cron`, `net` and `vault`.
2. Applies **all of Versely's migrations** as `postgres`. The `CREATE EXTENSION pg_cron/pg_net` lines are skipped because the stubs provide those.
3. Snapshots Versely: a `pg_dump` of public, storage and auth, plus all RLS policies, table and sequence grants, role memberships, and cron jobs.
4. Applies `20261113000000_daily_verse_reports.sql` as `postgres` (not a superuser), then compares the snapshot. It must be identical; the only expected addition is `postgres → daily_verse_owner` membership.
5. Runs `tests.sql` (86 checks):
   - schema, table and function isolation for anon, signed-in Versely users and the service role
   - the owner role having no rights on Versely tables
   - `SECURITY DEFINER` with `search_path=''` on every function
   - storage isolation of `attachments/daily-verse/`
   - the admin allow-list, including the reviewed seed
   - validation and spam rules
   - rate limits per install and per network, and refill (the network is kept only as the HMAC rate-limit key `net:<hmac>`, and that row is purged after 2 idle days; the raw IP never reaches the database)
   - screenshot rules (two per report, 1.5 MB each, server-built paths), and partial cleanup that keeps each remaining path with its own size
   - admin status changes and the audit trail
   - retention (only eligible screenshots and reports, audit rows cascade, idle rate-limit rows)
   - the pg_cron schedule
6. Runs the down script, checks the schema, role and cron job are gone, and checks Versely is identical to step 3.
7. Re-applies the migration and runs the 86 checks again.

The stand-ins are faithful for access control, but they aren't Supabase. **Before any production apply, the gate in [PRODUCTION_GATE.md](PRODUCTION_GATE.md) is required.** The rules the Edge Functions must follow are in [PR_B_CONTRACT.md](PR_B_CONTRACT.md).
