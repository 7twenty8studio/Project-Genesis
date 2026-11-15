# Daily Verse reporting: hosted validation on Project Genesis (14–15 Nov 2026)

Gamaliel authorized controlled hosted testing on 14 Nov 2026 (22:30Z) and the remaining checks on 15 Nov (04:14Z).
- Project: the existing Project Genesis Supabase project (`ulbpwygzwchsnvdeeife`, Postgres 17.6.1.166). No new project, bucket or other infrastructure was created.
- Not done: the nightly schedule migration was not applied, nothing was merged, and nothing was published.

## What was set up

| | |
|---|---|
| Functions | `dv-report` (verify_jwt **off**; checks the publishable key itself), `dv-admin` (verify_jwt **on**), `dv-retention` (verify_jwt **off**; Vault secret). Deployed from commit **9146e98**. Each is now at version 3 with the same `ezbr_sha256` as its first deploy: 41271bbb…8e88, 0a68e1b1…0eb8 and 82cbe97b…7ecb5. The dv-retention source was read back and matches the repo. |
| Settings (Vault, read by `setting()`) | `dv_hmac_secret`: generated in the database, 64 hex, never shown. `dv_internal_builds` = `202611142300` (the hosted test build). `dv_alert_email` = `7twenty8studio@gmail.com`. `dv_allowed_origins` = `http://localhost:3000,https://www.7twenty8studio.com,https://7twenty8studio.com`. **Not set:** `dv_email_from`, `dv_admin_url`. No `DV_*` function secrets. |
| Admin allow-list | `daily_verse.admins` holds only `7twenty8studio@gmail.com` (the approved seed). |
| Schedule | `daily-verse-screenshot-cleanup` is **not** installed (migration 20261114000000 unapplied). PR A's `daily-verse-retention` purge job is active. |

## Results

| # | Check | Result |
|---|---|---|
| 1 | **Keys** (dv-report) | ✅ Publishable key in `apikey` → 201. Refused with 401: no key, a wrong `sb_publishable_` key (the platform gateway refuses it first: "Invalid API key"), the legacy anon JWT, and the key sent only as Bearer. Refused calls saved nothing (0 → 1 report). |
| 2 | **IP header** | ✅ (behavioural). A request with no `x-forwarded-for` and three with client-sent values (203.0.113.1, 198.51.100.77, 192.0.2.200) all landed in **one** `net:<hmac>` bucket (tokens 20 → 16). So the last `x-forwarded-for` entry is the gateway's and a client can't move itself to another bucket. No header-reflection code was deployed. |
| 3 | **Screenshots** | ✅ Two JPEGs → 201 `{screenshots: 2, submitted: 2}`. Paths `daily-verse/reports/<id>/1.jpg`, `2.jpg`; sizes match exactly. A duplicate → 200 `{duplicate: true, screenshots: 2}`. Signed URLs from dv-admin are `https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object/sign/attachments/daily-verse/reports/<id>/<n>.jpg` with token `exp − iat = 300`, and serve `image/jpeg` with JPEG magic bytes at the stored size. Refused: the same URL without the token (400), the public URL (400), the object without auth (400 NoSuchBucket), anon via `/authenticated/` (400 NoSuchKey), and anon list (`[]`). **After expiry:** a URL issued at 04:28:27Z (expiresAt 04:33:27Z) gave 200 at 04:28:33Z and **400 `InvalidJWT: "exp" claim timestamp check failed`** at 04:33:38Z. |
| 3b | **Errors** (dv-report) | ✅ Unlisted build → 503 `unavailable`. Unknown puzzleType → 400 `{field: "puzzleType"}`. Spam → 400 `{field: "description"}`. PNG → 400 `{field: "screenshots"}`. 1.5 MB + 10 → 413. The 6th report from one install → 429 with `Retry-After: 720`. Every response is `Cache-Control: no-store`. |
| 4 | **Admin access** (dv-admin) | ✅ The seeded admin (signed in at www.7twenty8studio.com): `me` → 200 `{email: "7twenty8studio@gmail.com", admin: true}`; all responses `no-store`. 401: no Authorization (platform), the anon JWT (ours), and the publishable key only. CORS: the allowed origins get `Access-Control-Allow-Origin`; `https://evil.example` gets none; the hosted gateway adds no CORS of its own. **Separate Versely ops account (not on daily_verse.admins): PENDING** — waiting for Gamaliel to sign in with it; expected 403 `{error: "forbidden", email}` from dv-admin while Versely Operations keeps working for it. |
| 4b | **List and details** | ✅ All 11 reports with exactly the contract's 21 keys. No 64-hex hash and no storage path anywhere in the response. Language filter OK. Cursor paging: limit 3, then `before` gives the next 3 with no overlap. The app report `867562f7…` shows with `screenshotCount: 2`. |
| 4c | **Status updates** | ✅ On test report `37157e18…` (hosted-test-0a5a5dc6): new → in_review (with a note), then → resolved (with a note) gave 200 each. `handledBy` = `7twenty8studio@gmail.com` even though the request body named `someone@else.test`. `closedAt` is set, and the change persists in a fresh list. A bad status → 400 `{field: "status"}`; an unknown id → 404. |
| 5 | **Email** | ✅ Ten alerts arrived at `7twenty8studio@gmail.com` (one per new test report, within the 12/h cap), plus one from the app test. Sender: `Daily Verse Games <onboarding@resend.dev>` (the fallback, because `dv_email_from` is unset). Subject prefix `[Daily Verse]`; `URGENT` for biblical inaccuracy in approved content. Text only, with **no images and no links** (no `dv_admin_url`). No `dv background task failed` in function_logs. Afterwards the `alert:email` bucket was set to 0; it refills by itself at 12/h. |
| 6 | **App → server → admin** | ✅ Debug build of daily-verse #36 (cf41c41, build 202611142300, `REPORTS_URL` = hosted dv-report, publishable key; command-line overrides only, nothing committed). On the iPhone 17 simulator: Today → Play → Verse Guess → "Report a problem" → "Unclear question or clue" → form → description → 2 photos via PhotosPicker → Send. The app showed "Thanks! Your report was sent to the editors." with reference `867562f7-74ed-458c-9d64-42ff81c21593`. The row: internal, 0.1.0 / 202611142300, iOS 27.2, phone, en, verse_guess, 2026-11-14-joy.verseGuess, approved, unclear_clue, 2 screenshots (70,548 and 109,576 bytes). The admin API lists it and serves both pictures (check 3). |
| 6b | **Studio OS inbox** (`/admin/work`, read-only) | ✅ "Issues & Reports" lists Versely and Daily Verse Games live: 10 Daily Verse reports open (11 minus the one resolved above), with statuses matching dv-admin. Task **DVG-2** opens report `c05c1bb4…` (hosted-test-50e2bd88: Trivia, biblical accuracy, In review, handled by 7twenty8studio@gmail.com, 2 screenshots). `pm-api` stores only report references and reads content through dv-admin. |
| 7 | **Versely unchanged** | ✅ The `prod_fingerprint.sql` Versely rows (tables 85, columns 753, functions 87, policies 86, triggers 32, role memberships 24, roles 31, cron jobs 3, buckets 4, schema ACLs 7) are identical before and after. `storage_objects_count` 16 → 20, from the 4 Daily Verse test screenshots. `auth_users` 7 → 7: no users were created. Versely functions keep their `ezbr_sha256`. Versely Operations at `/admin` loads for the admin with all sources connected and email alerts on. |
| — | **dv-retention** | ✅ 403 with no secret and with a random secret. That's expected while the schedule migration isn't applied (no `retention_secret_matches`). GET → 405. |

## Test data: cleanup list (nothing deleted yet; Gamaliel decides)

All of the following are test data. Each was created by these hosted tests between 22:54 and 22:59 UTC on 14 Nov from build `202611142300`, which exists only in my local test builds and in `dv_internal_builds`. The ten automated ones have content ids `hosted-test-*` and the description "Hosted test report (automated, will be deleted)."

| Report id | Created (UTC) | Category / puzzle | Status | Screenshot objects | Linked Studio OS task |
|---|---|---|---|---|---|
| 99db3ff7-e4a7-4415-bcda-6c93d756cfb7 | 22:54:19 | unclear_clue / crossword | new | — | — |
| 7bff9be5-5594-4060-8cd9-79b24ef1e708 | 22:54:31 | unclear_clue / crossword | new | — | — |
| 41c48ee6-f44e-439f-8873-4b17addefaa4 | 22:54:31 | unclear_clue / crossword | new | — | — |
| 4969c41c-1980-4777-b974-aee1bd613f2c | 22:54:31 | unclear_clue / crossword | new | — | — |
| c05c1bb4-a196-4d5e-bbde-4144dc580c81 | 22:54:40 | biblical_inaccuracy / trivia | in_review | `daily-verse/reports/c05c1bb4-…/1.jpg` (101,862 B), `…/2.jpg` (69,098 B) | **DVG-2** "Review biblical accuracy in Trivia for 2026-11-14 (EN)" (Gamaliel keeps the task) |
| 70ecd774-2a37-4b6d-a07f-6586f5120f6a | 22:54:44 | unclear_clue / crossword | new | — | — |
| 955ce92f-ec99-49ea-9c9a-33ae2e5e168b | 22:54:44 | unclear_clue / crossword | new | — | — |
| 212aa241-569b-4523-98a7-69535705e57d | 22:54:44 | unclear_clue / crossword | new | — | — |
| ffacfe54-adbb-40fb-b6bb-72fa0de1be0c | 22:54:44 | unclear_clue / crossword | new | — | — |
| 37157e18-3029-4957-92b7-3b7083315cfc | 22:54:45 | unclear_clue / crossword | resolved (by check 4c) | — | — |
| 867562f7-74ed-458c-9d64-42ff81c21593 | 22:58:46 | unclear_clue / verse_guess (`2026-11-14-joy.verseGuess`) | new | `daily-verse/reports/867562f7-…/1.jpg` (70,548 B), `…/2.jpg` (109,576 B) | — |

The last one was sent by the iPhone simulator app test. Its description says "Hosted end-to-end test from the iPhone simulator…".

Also test-only:
- `daily_verse.report_events`: 3 rows. Two are from check 4c on `37157e18…`. One is c05c1bb4 new → in_review at 02:25Z by 7twenty8studio@gmail.com, which was made through Studio OS, not by these tests.
- `daily_verse.rate_limits`: 11 rows (`global`, `net`, 7 `install`, `alert:email`, `admin:<email>`). All exist only because of the tests. They are purged automatically after 2 idle days, except `global`.

**Unsure / keep:** Studio OS task **DVG-1** "test" has no report link. It wasn't created by these tests, so it's not on the list. **DVG-2** is kept by Gamaliel's decision. If c05c1bb4 is deleted, DVG-2's link points to a report that no longer exists.

**How to remove them later (when approved):** for each report with screenshots, delete the objects through the Storage API first (or mark the report closed more than 90 days ago and use dv-admin "runCleanup"). Then delete the rows by id in SQL.
