# Required gate before any production apply

> Step-by-step for this Mac (Docker or Colima plus `supabase start`): [LOCAL_SUPABASE_VALIDATION.md](LOCAL_SUPABASE_VALIDATION.md). There is no non-production Supabase environment, and none is to be created.

The local suite (`run.sh`) runs on plain Postgres with Supabase stand-ins. It proves the logic and the isolation rules, **but not hosted Supabase permissions**. Before the migration is applied to the production project, all of the following must pass on a **disposable real Supabase**:

- `supabase start` (Docker) on a developer machine, **or**
- a non-production Supabase branch or project, **only with Gamaliel's explicit approval** (and never a second permanent project).

| # | Check | How |
|---|---|---|
| 1 | Migrations | `supabase db reset` (local) applies all Versely migrations, then `20261113000000_daily_verse_reports.sql`, as the hosted `postgres` role. |
| 2 | Hosted permissions | Confirm the migration succeeds **without superuser**. In particular: `CREATE ROLE daily_verse_owner`, `GRANT daily_verse_owner TO postgres` (named explicitly; `current_user` crashed Supabase Postgres 17.6.1.075 locally), `SET ROLE daily_verse_owner`, creating objects as that role, `cron.schedule(...)`, and `revoke … from public` on the new functions. |
| 3 | Privileges and RLS | Run `tests.sql` sections 1–4 and 6 against the real database: `psql "$DB_URL" -f supabase/tests/daily_verse/tests.sql` after loading the seed. Confirm 0 failures. Also call PostgREST with the anon key and a signed-in Versely user token: `/rest/v1/reports` with `Accept-Profile: daily_verse` must fail (schema not exposed), and RPCs to `daily_verse.*` must fail. |
| 4 | Storage | With the real Storage API, as a signed-in Versely user: listing, downloading, uploading and deleting under `attachments/daily-verse/` must all be refused, and the user's own `<uid>/…` access must still work. As service role: upload and delete under `daily-verse/` work. Check `allowed_mime_types` (JPEG) and the size limit behave as expected. |
| 5 | Cron | `select * from cron.job` shows `daily-verse-retention` once and Versely's jobs unchanged. Run `select daily_verse.purge_expired();` by hand and check `cron.job_run_details` after the first scheduled run. |
| 6 | Rollback | Run `supabase/rollback/…_down.sql`, then check the schema, role and job are gone. Re-apply and re-run checks 3–5. |
| 7 | Versely unaffected | Compare a schema-only dump of `public`, `storage` and `auth` (`supabase db dump --schema public,storage,auth`), `pg_policies`, table grants, role memberships and Versely's cron jobs, before the migration vs. after it vs. after rollback. They must be identical apart from `postgres → daily_verse_owner`. Smoke-test the Versely app (sign-in, attachments, feedback) and the ops dashboard. |

Record the results (date, environment, outputs) in the PR, then ask Gamaliel for a **separate, explicit authorization** to apply to production. Nothing in CI applies it.

**Production applies ONLY `20261113000000_daily_verse_reports.sql`.** It goes in as one recorded migration, in one transaction, after checking its SHA-256 (`670f2112f5180a2391ad87e107d6613de55f7343c5282178c74c77912e0bbd0d`).
- **Never use `supabase db push` or `supabase migration repair`.** The hosted migration history doesn't match the repo: it has dashboard-style versions, and several repo files aren't recorded. So `db push` would try to re-run Versely's migrations.
- See [PRODUCTION_DEPLOYMENT_PLAN.md](PRODUCTION_DEPLOYMENT_PLAN.md).
- The admin seed is a separate, later approval.
