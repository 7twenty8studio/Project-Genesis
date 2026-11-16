# Public Daily Verse reports (1.0): production runbook

Target: **Project Genesis**, Supabase project `ulbpwygzwchsnvdeeife` (us-east-1, Postgres 17.6.1.166). Checked on 16 Nov 2026 23:5x UTC: `ACTIVE_HEALTHY`. Hosted migration history ends at `20261115013804 studio_os_pm_github`. `daily_verse_reports` (`20261113000000`) and `daily_verse_retention_schedule` (`20261114000000`) are applied. The App Attest migration is not.

Reviewed commit: **`9dffce6`** on `claude/dv-public-reports-app-attest`. Everything deployed is taken from that commit (`git show 9dffce6:<path>`), never from a working tree. Only Gamaliel's explicit go-ahead starts each production step.

| File at 9dffce6 | SHA-256 |
|---|---|
| supabase/migrations/20261117000000_daily_verse_app_attest.sql | 09c506274099653165e95025dfa463247a3466a9cee101d21a132fa9d7a23c52 |
| supabase/rollback/20261117000000_daily_verse_app_attest_down.sql | 2dbfc1240fc5dd7fc7cd2a1e37d6193814105c1a3467b6fe8cb52a6e5570b406 |
| supabase/functions/dv-report/index.ts | 380089c493e54c04f146704d6f065256d6b81ee1c0fbdd4b633879dc55ee02ae |
| supabase/functions/dv-attest/index.ts | 251ef0d66a90e2b55690b01e04919df9c674123f87819fb55b8da33e716c2d20 |
| supabase/functions/_shared/dailyVerse.ts | e863951f361e90a8a0354e6bc004ca9ef990dab132c43e81cac55d5fa8342240 |
| supabase/functions/_shared/dailyVerseIO.ts | f78abd4d897a0d6080c73aff44f7ec1483076be995d4cd24f0e750be92bf1685 |
| supabase/functions/_shared/appAttest.ts | 9d60db76e3074d6fe92ffe229ca2b993eadd3d1059e663e168f2ad5da20f5411 |
| supabase/tests/daily_verse/activation/open_public_reports.sql | c036b7a47b4e902d51fec82a942390e6f49272c23e0fb66d3a8449864b508bb1 |
| supabase/tests/daily_verse/activation/close_public_reports.sql | 11de42ee6f73d68f363ae3c5d9bf173d12d55bc54cde2b7bdf9228bbe7338233 |

## Pre-checks (done, read-only, 16 Nov 2026)

- `daily_verse.settings.accepted_channels` = `{internal}`; `daily_verse.attest_keys` absent; 1 report; Vault has `dv_hmac_secret`, no `dv_internal_report_key` (so the internal-key exception is off).
- Versely fingerprint (`prod_fingerprint.sql`), before:

| item | n | md5 |
|---|---|---|
| versely.tables | 85 | 9508389ce0722c5fce637ec3456dfcd1 |
| versely.columns | 755 | 4a8d6967ab5d0de6c9ccacf6058559a5 |
| versely.functions | 87 | 84ac851a8b4b901aab19dacbdfc81f40 |
| versely.policies | 86 | eaf67319bc6e9f4b557ff240635131ae |
| versely.triggers | 32 | fa2ba6ccfc43e49b71a58dd1554264d5 |
| versely.role_memberships | 28 | f5fca2c962257235fb10cbfec384cd9f |
| versely.roles | 33 | 2de56fac7bf34b03eaae917ee30513bc |
| versely.cron_jobs | 3 | 50b73f5aaa32c657b72b1446ace9754e |
| versely.storage_buckets | 4 | f4d17289e23cc48e0105ad21b63df1c2 |
| versely.schema_acls | 7 | 317824157e258f7442d952506ddd8730 |
| (counts) storage objects 18, auth users 9; daily_verse schema 1, owner role 1, daily-verse cron jobs 2 | | |

## Rehearsal (done)

`supabase/tests/daily_verse/run_attest.sh` on throwaway Postgres 17 with the Supabase stand-ins: Versely migrations → `20261113000000` → **only** `20261117000000` (as `postgres`, not superuser).
- Versely (public, storage, auth schema; policies; table ACLs; roles; memberships; cron): **identical** after the apply and after the rollback.
- `daily_verse` after the rollback: **identical** to before the migration.
- `attest_tests.sql`: **11/11** on the first apply and again after re-applying.
- Activation: open → `{internal,public}`, close → `{internal}`. With the channel closed, a public `submit_report` is refused with `channel_closed`; with it open, the same report is accepted.

## Step 1: migration (needs go-ahead)

1. Apply `20261117000000_daily_verse_app_attest.sql` from 9dffce6 (SHA above) as one recorded migration (`apply_migration`, name `daily_verse_app_attest`). Never `db push`.
2. Re-run `prod_fingerprint.sql`: every `versely.*` row must equal the table above (counts of storage objects and users may move with real use).
3. `activation/check_channels.sql`: `attest_keys` and `use_attest_key` present, channels still `{internal}`.
4. Rollback if needed: `rollback/20261117000000_daily_verse_app_attest_down.sql` (it also closes the public channel first).

## Step 2: functions (needs go-ahead; after step 1)

- `dv-attest` (new, verify_jwt **off**: it checks the publishable key itself) and `dv-report` (verify_jwt **off**, as now), each with `index.ts` plus `_shared/dailyVerse.ts`, `_shared/dailyVerseIO.ts` and `_shared/appAttest.ts`, all from 9dffce6.
- After deploy: read each function back and compare file hashes with the table above. Record the new `ezbr_sha256` and version here.
- Smoke checks (nothing is stored):
  - dv-report with no App Attest headers → 401 `attestation_required`
  - with an internal build number and no attestation → 401 `attestation_required` (regression)
  - with `x-dv-internal-key: wrong` → 401 `unauthorized`
  - dv-attest `{"action":"challenge"}` → 200 with a challenge
  - dv-attest register with a junk attestation → 403 `attestation_invalid`
- Effect: old builds without App Attest can no longer send reports (they fall back to sharing a note).
- Back out: redeploy the previous dv-report (version 3, `ezbr_sha256` 41271bbb…8e88) and delete dv-attest.

## Step 3: public activation (needs go-ahead; after step 2 and once the signed Release TestFlight build is ready)

1. `activation/open_public_reports.sql` → `{internal,public}`.
2. iPhone check from the TestFlight build, in English and Spanish, including a retry. Then in Studio OS → Inbox → Daily Verse, each report appears **exactly once** (`check_channels.sql` lists the latest reports; a retried send returns `duplicate: true` with the same id).
3. If anything fails: `activation/close_public_reports.sql` → `{internal}`, then confirm a public request is refused (503 `unavailable`, nothing stored).

## Results

(Filled in as each step runs.)
