# Daily Verse functions: local integration tests

`integration.test.ts` runs dv-report, dv-admin and dv-retention end to end against
a **local** Supabase stack. It refuses any API URL other than `http://127.0.0.1` or
`http://localhost`. Never point it at the hosted project: it creates test users, adds
them to `daily_verse.admins` and `public.ops_admins`, and stops and restarts the
local Storage container.

## Setup

Use the same safety setup as `../LOCAL_SUPABASE_VALIDATION.md`:
- no `supabase link`, and no access token or DB URL in the shell
- `[db.migrations]` and `[db.seed]` disabled in the uncommitted `config.toml`
- Versely's migrations applied by hand, with the ops-alerts cron jobs inactive

1. Start the stack.
   ```sh
   echo -n 17.6.1.166 > supabase/.temp/postgres-version   # the production image (local override, not committed)
   supabase start -x realtime,studio,imgproxy,logflare,vector,supavisor,mailpit,postgres-meta
   ```
2. Apply the migrations, all as `postgres`:
   - Versely's 27, with the ops cron jobs inactive (see `../LOCAL_SUPABASE_VALIDATION.md`)
   - `20261113000000_daily_verse_reports.sql`
   - `20261114000000_daily_verse_retention_schedule.sql`
3. Start the mock Resend, which records each email to `/tmp/dvb/emails.jsonl` and sends nothing:
   ```sh
   node supabase/tests/daily_verse/functions/mock-resend.mjs &
   ```
4. Write a test env file, outside the repo:
   ```sh
   DV_HMAC_SECRET=<openssl rand -hex 32>
   DV_REPORT_KEYS=<PUBLISHABLE_KEY from `supabase status -o env`>   # the hosted platform sets SUPABASE_PUBLISHABLE_KEYS instead
   DV_INTERNAL_BUILDS=202611141200,202611150900
   RESEND_API_KEY=re_local_test_not_real
   DV_ALERT_EMAIL=dv-alerts@example.test
   DV_RESEND_URL=http://host.docker.internal:54399/emails
   DV_ALLOWED_ORIGINS=http://localhost:3000
   OPS_ALLOWED_ORIGINS=http://localhost:3000
   ```
5. Serve the functions with that env file:
   ```sh
   supabase functions serve --no-verify-jwt --env-file <that file>
   ```
6. Run the tests:
   ```sh
   eval "$(supabase status -o env)"; export API_URL ANON_KEY PUBLISHABLE_KEY SECRET_KEY SERVICE_ROLE_KEY JWT_SECRET
   node --experimental-strip-types --test --test-concurrency=1 supabase/tests/daily_verse/functions/integration.test.ts
   ```

## Local-only differences

- **`--no-verify-jwt`:** with CLI 2.75 the local auth server signs user tokens with ES256, but the local functions gateway only verifies HS256, so it rejects every user token as "Invalid JWT".
  - The functions don't depend on the gateway: dv-admin verifies each caller with `auth.getUser`, and dv-retention checks its Vault secret.
  - On the hosted project dv-admin keeps JWT verification on. dv-report is deployed with `--no-verify-jwt` there too and checks the publishable key itself, so the local run tests the same check.
- **CORS:** the local Kong adds `Access-Control-Allow-Origin: *` to every function response. The CORS test asks the edge runtime directly, inside the Docker network.
- **Signed URLs:** locally they use the internal `http://kong:8000` host. The test rewrites the host before fetching. On the hosted project they're `https://<ref>.supabase.co/storage/v1/object/sign/…`.
