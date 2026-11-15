# PR B: Daily Verse reporting functions — deployment notes (NOT DEPLOYED)

**Status: code and local tests only.** Nothing has been deployed, no production migration has been applied, and no admin has been seeded. Each step below needs Gamaliel's separate approval. It belongs in a consolidated release checklist, alongside PR #36 (app), PR #37 (privacy) and studio-web #2 (admin tab).

## What PR B adds (new files only)

| Path | What |
|---|---|
| `supabase/functions/_shared/dailyVerse.ts` | Pure rules: validation, channel, HMAC, paths, error mapping, admin shapes, CORS, retention planning, alert email. Node-tested in `dailyVerse.test.ts`. |
| `supabase/functions/_shared/dailyVerseIO.ts` | Postgres via `SUPABASE_DB_URL`, with `set local role service_role` per transaction. Also Storage (service role), the verified email via `auth.getUser`, and Resend. |
| `supabase/functions/dv-report/` | The app's report intake (publishable key in `apikey`, checked in code). |
| `supabase/functions/dv-admin/` | The admin site's API (user JWT; the `daily_verse.admins` allow-list). `contract.test.ts` and `dv-admin.fixtures.json` are copied from studio-web 96478ac. |
| `supabase/functions/dv-retention/` | The screenshot cleanup (Vault secret). `cleanup.ts` is shared with dv-admin's `runCleanup`. |
| `supabase/migrations/20261114000000_daily_verse_retention_schedule.sql` | The nightly schedule. **Not applied anywhere but local.** |
| `supabase/rollback/20261114000000_daily_verse_retention_schedule_down.sql` | Its rollback. |
| `supabase/tests/daily_verse/functions/` | Local integration tests, a mock Resend, and a README. |

The only change to an existing file is in `supabase/tests/daily_verse/run.sh`, PR A's harness. Its Versely-migrations loop now stops at PR A's migration, because the new later migration depends on PR A.

No existing Versely function, shared module, migration, policy or bucket is changed. Versely's `ops-alerts`, `ops-dashboard`, `_shared/ops*.ts` and `ops_*` objects are untouched. The function test suite is 118/118: Versely's 92 (unchanged from `main`) plus 26 new tests.

## Contract rules → where they're enforced and tested

| Rule (PR_B_CONTRACT.md) | Enforced in | Tested by |
|---|---|---|
| 1. The server decides the channel | `channelFor(build, DV_INTERNAL_BUILDS)`; the body's `channel` is never read | unit: "channel comes from server config"; integration: client `channel` ignored, unlisted build → 503 |
| 2. Internal-only is a policy gate | documented in `dv-report` and here; App Attest / DeviceCheck before public release | — |
| 3. The service key never reaches the app | the service key is used only in `dailyVerseIO.ts` (function secret); the app uses the publishable key only (PR #36) | integration: no response body or header (all calls in the run) contains the service key or the JWT secret; the app repo has no service key (checked by grep, see the PR) |
| 4. Admin comes only from a verified session | `verifiedEmail()` → `auth.getUser`; `daily_verse.is_admin` | integration: 401 for none / anon / forged / expired / deleted user; 403 for an ops-only user even with the email in the body or a header |
| 5. Storage first, database after | dv-report uploads then calls `attach_screenshot` (removing the upload if that fails); `confirmedDeleted()` | integration: attach failure → upload removed; Storage down → 201 with nothing attached; cleanup with Storage down → path stays listed, next run deletes it |
| 6. HMACs only | `hmacHex(DV_HMAC_SECRET, …)`; the last `x-forwarded-for` hop | integration: no raw install ID or IP in the DB; keys are `install:<hmac>`, `net:<hmac>`; a spoofed header doesn't dodge the network limit |
| 7. Edge limits | 4 MB stream cap; ≤2 screenshots; JPEG magic bytes; ≤1.5 MB | unit and integration: 413 (body and screenshot; exactly 1.5 MB accepted), PNG and truncated JPEG → 400 |
| 8. 5-minute signed URLs | `createSignedUrl(path, 300)`, one report at a time | integration: the token's `exp − iat = 300`, and the bytes match |
| 9. Generic errors | `reportErrorToHttp`, `adminErrorToHttp` | unit: no SQL detail leaks; 429 + Retry-After |

## Secrets and settings (production; set only at deploy, with approval)

| Name | Used by | Value |
|---|---|---|
| `DV_HMAC_SECRET` | dv-report | `openssl rand -hex 32`. Never rotate casually: install grouping depends on it. |
| `DV_INTERNAL_BUILDS` | dv-report | Comma-separated Internal TestFlight build numbers; update with each Internal upload. |
| `DV_ALERT_EMAIL` | dv-report | Recipient(s) for Daily Verse alerts, separate from Versely's `OPS_ALERT_EMAIL`. |
| `DV_EMAIL_FROM` | dv-report | Optional sender, e.g. `Daily Verse Games <alerts@…>` on the verified Resend domain. |
| `DV_ADMIN_URL` | dv-report | Optional link to the admin tab in the alert email. |
| `DV_ALLOWED_ORIGINS` | dv-admin | The studio site origin(s). If unset, `OPS_ALLOWED_ORIGINS` is read; `*` is never honoured. |
| `RESEND_API_KEY` | dv-report | **Existing** secret, reused read-only. |
| `SUPABASE_DB_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | all | Provided by Supabase. |
| Vault `dv_retention_secret` | dv-retention, cron | Created by the schedule migration (random). |
| Vault `dv_retention_url` | cron | `https://ulbpwygzwchsnvdeeife.supabase.co/functions/v1/dv-retention`. Set **after** dv-retention is deployed; until then the job does nothing. |
| `DV_RESEND_URL` | tests only | **Leave unset in production.** |

### Where the settings live
Each `DV_*` setting is read from the Edge Function secret of that name if set; otherwise from the **Vault** entry of the same name in lower case (`dv_hmac_secret`, `dv_internal_builds`, `dv_alert_email`, `dv_email_from`, `dv_admin_url`, `dv_allowed_origins`). Vault entries can be created from SQL (`select vault.create_secret(...)`), so the HMAC pepper can be generated inside the database (`encode(extensions.gen_random_bytes(32), 'hex')`) and never shown to anyone. Values are cached for 60 s. If `DV_EMAIL_FROM` is unset, alerts use Versely's verified sender address (`OPS_EMAIL_FROM`, read only) under the name "Daily Verse Games".

## JWT verification choices

| Function | `verify_jwt` | Why |
|---|---|---|
| dv-report | **off** (`--no-verify-jwt`) | The app sends the project's **publishable key** (`sb_publishable_…`) in the `apikey` header only, no `Authorization`. The platform's `verify_jwt` check only understands JWTs, and publishable keys aren't JWTs (Supabase, "Migrating to publishable and secret API keys": *Edge Functions don't verify the apikey header for the new keys; use verify_jwt = false and authorize in code*). So dv-report checks the key itself, first: `acceptedReportKeys` reads `SUPABASE_PUBLISHABLE_KEYS` (set by the platform) and accepts only `sb_publishable_` values, constant-time; no key configured means every call gets 401. Legacy anon JWTs, secret keys and service-role keys are refused. (The legacy anon key stops working at the end of 2026, so the app never uses it.) |
| dv-admin | **on** (default) | The caller must be signed in. The function also verifies the user with `auth.getUser` and checks `daily_verse.admins`. |
| dv-retention | **off** (`--no-verify-jwt`) | pg_cron has no user session. The caller is proven by the Vault secret, checked by `daily_verse.retention_secret_matches` (the same pattern as Versely's ops-alerts, but its own secret). |

## Production release steps (TODO; each needs approval)

1. Review and approve PR B (draft) together with #36, #37 and web #2.
2. Set the secrets above (`supabase secrets set …`) without touching existing ones. `RESEND_API_KEY` stays as is.
3. Deploy:
   ```sh
   supabase functions deploy dv-report --no-verify-jwt
   supabase functions deploy dv-admin
   supabase functions deploy dv-retention --no-verify-jwt
   ```
4. Apply `20261114000000_daily_verse_retention_schedule.sql`.
   - Use the PR A method: **one file, `psql --single-transaction`, plus one history row; never `db push`**.
   - Check its SHA-256 and run the Versely fingerprint before and after (`prod_fingerprint.sql`).
5. Store the URL: `select vault.create_secret('https://ulbpwygzwchsnvdeeife.supabase.co/functions/v1/dv-retention', 'dv_retention_url', 'Daily Verse retention');`
   - Then check: `select daily_verse.call_retention();` → `net._http_response` status 200.
6. The admin seed (`supabase/seed/daily_verse_admins.sql`) is a separate approval.
7. Smoke test:
   - a test report from an Internal build → the admin tab shows it, and the alert email arrives
   - Versely's ops dashboard is unchanged

**Rollback:**
1. Undeploy the three functions.
2. Run `20261114000000_daily_verse_retention_schedule_down.sql` and delete its history row. Do this **before** any PR A rollback, because PR A's down script doesn't remove this job.

## Not verified locally (needs the hosted project or a device)

- **The gateway's anon-key check on dv-report.** The CLI's local gateway can't verify the local auth server's ES256 tokens, so the local tests ran with `--no-verify-jwt` (see `functions/README.md`).
- **The admin site viewing screenshots.** Locally, signed URLs use the internal `http://kong:8000` host, which studio-web correctly rejects. Hosted, they're `https://<ref>.supabase.co/storage/v1/object/sign/…`, which matches its check.
- **The real client IP header on the hosted gateway.** We use the last `x-forwarded-for` entry. Confirm it's the client's address after deploy (the network bucket only, not a security boundary).
- **A real Resend send** (the tests use a mock), and App Attest / DeviceCheck (required before public release).
- **Alert emails are best effort.** `notify()` runs after the response, at most 12 an hour; a Resend failure is only logged (`dv background task failed`). The admin tab is the record: a report is never lost because its email wasn't sent.
- **The app end to end.** A Debug build needs an https `REPORTS_URL`. The integration tests instead send requests with the same JSON keys and value formats that the app's `ReportSubmission` encodes (PR #36).

## Screenshot results the app sees

`201 {id, screenshots, submitted}`: the text is always saved first; `screenshots` is how many pictures were saved and `submitted` how many were sent. If Storage fails, or the second picture fails, the report stays with what was saved (never re-sent automatically, so there are no duplicates or half-uploads). The app (#36) compares the two and shows "Your report was sent, but N screenshot(s) couldn't be uploaded" with the report reference. A duplicate within 10 minutes answers `200 {id, duplicate: true, screenshots}` with what the first one saved.

## Hosted validation (approved Nov 14 2026, before the release checklist)

Run on Project Genesis with the three functions deployed and only `7twenty8studio@gmail.com` seeded; the schedule migration stays unapplied (dv-retention answers 403 until then, which is part of the check). Results go in `HOSTED_RESULTS.md`.

1. **Keys:** 201 with the publishable key in `apikey`; 401 with none, a wrong one, the legacy anon JWT, the key only as Bearer; nothing saved for refused calls.
2. **IP header:** which `x-forwarded-for` / `x-real-ip` values the hosted gateway passes, and whether a client-sent `x-forwarded-for` changes the last entry. If the gateway's address can't be told from a client's, the network bucket stays a coarse brake and the docs say so.
3. **Screenshots:** two pictures → `{screenshots: 2, submitted: 2}`; dv-admin's signed URLs are `https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object/sign/attachments/daily-verse/reports/<id>/<n>.jpg`, expire after 300 s, serve the JPEG, and the plain object URL without a token is refused (private bucket).
4. **Admin access:** the seeded admin gets 200; anon and a signed-in non-admin get 401/403; Versely's ops-dashboard keeps answering as before; CORS only for `DV_ALLOWED_ORIGINS`.
5. **Email:** one real alert to `DV_ALERT_EMAIL` through Resend from `DV_EMAIL_FROM`.
6. **App → server → admin:** the app's own `SupabaseReportClient` sends a report with screenshots to the hosted dv-report; it shows in the admin tab with its pictures.
7. **Versely unchanged:** the existing functions, cron jobs and fingerprint (`prod_fingerprint.sql`) are the same before and after.

**Cleaning up after the tests:** test reports and their screenshots are removed (dv-admin's delete path, or the Storage API then SQL by id); any temporary non-admin test user is deleted.
