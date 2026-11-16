# Daily Verse 1.0 public reporting: production runbook

Target: **Project Genesis**, ref `ulbpwygzwchsnvdeeife` (us-east-1). Never any other
project. Each step runs only with Gamaliel's written, scoped OK for that step.

Reviewed commit: `f4684159259d1534991004e360e9c5a9303030ea` (branch
`claude/project-thread-4llmwc`, PR #24). Deploy only files byte-identical to it:

| File | SHA-256 |
|---|---|
| functions/dv-report/index.ts | ec4617a4479d1b000ef5c1daade77c1cb2b0f87a2dd899361542b9e4d4d4c53d |
| functions/_shared/dailyVerse.ts | e1637aefe1e4a461ae838af5da3f962dc93c6f93138845e4dbcf700ddb12036d |
| functions/_shared/appAttest.ts | 966579fb0cf27135dbaad2b29112476baec48a11c9114a0965ea0752edf882ff |
| functions/_shared/dailyVerseIO.ts | f78abd4d897a0d6080c73aff44f7ec1483076be995d4cd24f0e750be92bf1685 |
| migrations/20261117000000_daily_verse_app_attest.sql | 4b8f1d64e7603279f963fd8a0eb035067bcfa1c195ef80551e67ea8b53845d4f |
| rollback/20261117000000_daily_verse_app_attest_down.sql | 580b3f9d38ee3b0abe34c428fe91eb4f33ebd647629817bc0b3d44689cf83814 |

Production state checked 16 Nov 2026 (read-only): last migration
`20261115013804 studio_os_pm_github`; App Attest not applied; `daily_verse` has
admins, rate_limits, report_events, reports, settings; `accepted_channels = {internal}`;
dv-report version 3 (verify_jwt off).

## 1. Migration (only this file; never `supabase db push`)

Rehearsed locally (supabase/tests/daily_verse/run.sh): apply, 86 + 37 checks,
rollback (attest tables and client_report_id gone; schema, policies, cron, roles and
ACLs identical to before), re-apply, 37 checks. It references nothing outside the
`daily_verse` schema, so Versely's tables, policies, cron jobs and roles are untouched.

1. Snapshot Versely: `public` columns md5, policy count, cron jobs (record them).
2. Apply `20261117000000_daily_verse_app_attest.sql` as one migration.
3. Check: tables attest_challenges, attest_keys; column reports.client_report_id; the
   Versely snapshot unchanged.
Undo: run `supabase/rollback/20261117000000_daily_verse_app_attest_down.sql`.

## 2. dv-report deployment

`supabase functions deploy dv-report --no-verify-jwt --project-ref ulbpwygzwchsnvdeeife`
from a clean checkout of the reviewed commit (check the hashes above first). After:
fetch the deployed source and compare; then, with public still closed:
- unattested report with an Internal build number → 401 `required` (regression);
- `{action:"challenge", purpose:"report"}` → 200.
Undo: redeploy dv-report from `fb98d26` (version 3's source).

## 3. Public reporting

Staged: `open_public_reports.sql`, reversal `close_public_reports.sql` (one row each).
Open only when the signed Release TestFlight build is ready for the iPhone check.
Then: one English and one Spanish report from the iPhone; each appears exactly once in
Studio OS → Inbox → Daily Verse (channel Public); an offline send, then Try again, is
still one row (`client_report_id` unique). If any check fails: run the reversal,
send an attested report and confirm 503 `unavailable`.
