# Versely operations dashboard and alerts

One private page lists everything people report, by priority:
- in-app Send Feedback;
- content reports on group posts and prayers;
- Sentry crashes and errors;
- TestFlight screenshots, comments and crashes.

It also shows usage numbers (accounts, sign-ins, sync, Premium, groups). Urgent items are emailed within five minutes, and a digest arrives every morning.

```
Website /admin (7twenty8-studio-web, src/app/admin)
   │  signed in with Supabase Auth (magic link or Google)
   ▼
ops-dashboard  ── checks public.ops_admins, then gathers:
   ├─ public.app_feedback, public.content_reports   (database)
   ├─ Sentry issues                                  (SENTRY_* secrets)
   └─ TestFlight feedback                            (ASC_* secrets)
ops-alerts     ── pg_cron every 5 min (urgent) and 13:00 UTC (digest)
   └─ Resend email                                   (RESEND_API_KEY, OPS_ALERT_EMAIL)
```

All keys are **Supabase secrets** (Dashboard → Edge Functions → Secrets).
Never put them in the website, the app, git or a chat. The page itself only
holds the project's public URL and anon key.

## What's already done

- Tables `ops_admins`, `ops_items` and `ops_state`, the function `ops_metrics()` and the schedule (migrations 20261018020000 and 20261018030000).
- Edge Functions `ops-dashboard` and `ops-alerts` are deployed.
- The owner's account is on `ops_admins`.
- The page is in the website at `src/app/admin`, so it deploys with the site at `/admin`.

## 1. Let sign-in come back to the page (2 min)

1. Supabase → **Authentication → URL Configuration → Redirect URLs**.
2. Add your site's page, for example `https://YOUR-DOMAIN/admin`.
3. Add `http://localhost:3000/admin` too, for `npm run dev`.

Keep `versely://auth-callback` (the app needs it).

Sign in with the email of your Versely account. Either way works:
- **Magic link:** only existing accounts get one.
- **Google:** with the same Gmail address.

To add someone else, add their email (lower case) as a row in `public.ops_admins` with the Table Editor.

## 2. Email alerts with Resend (5 min)

1. Create a free account at resend.com and go to **API Keys → Create** (Sending access).
2. In Supabase secrets, add:
   - `RESEND_API_KEY`: the key
   - `OPS_ALERT_EMAIL`: where alerts go (comma-separate several)
   - `OPS_DASHBOARD_URL`: `https://YOUR-DOMAIN/admin`, for the button in emails
   - `OPS_EMAIL_FROM` (optional): e.g. `Versely Alerts <alerts@YOUR-DOMAIN>` once you verify your domain in Resend. Until then the default `onboarding@resend.dev` can only send to the address you signed up to Resend with.
3. On the dashboard, use **Send test email**.

When emails go out:
- **Urgent items are emailed once, within five minutes.** Urgent means:
  - a reported Bible-text mistake;
  - a bug report that mentions a crash, lost data, payment or sign-in;
  - three or more reports on one post;
  - a Sentry crash, or an error hitting 5+ people or 50+ times;
  - any TestFlight crash.
- **Every content report (community, group posts, prayers, announcements) is emailed within five minutes too**, as "[Versely report]", so reports are reviewed promptly (App Store 1.2). Three or more on one item make it urgent.
- **Everything else goes in the daily digest at 13:00 UTC** (8:00 am Chicago in summer, 7:00 am in winter).
- **Resolved items** aren't emailed again. If one happens again, it reopens and alerts again.

## 3. Sentry (3 min)

1. Sentry → **Settings → Auth Tokens** (or **Developer Settings → Personal Tokens**) → create a token with **project:read** and **event:read** only.
2. Add these secrets:
   - `SENTRY_AUTH_TOKEN`: the token
   - `SENTRY_ORG`: the organization slug (in Sentry URLs)
   - `SENTRY_PROJECT`: the project slug of the iOS app
   - `SENTRY_API_BASE` (only for an EU account): `https://de.sentry.io`

## 4. TestFlight feedback (5 min)

1. App Store Connect → **Users and Access → Integrations → App Store Connect API**.
2. Under Team Keys, click **+**, name it "Versely Ops" and give it the **Developer** role.
3. Download the `.p8` file (you can only download it once).
4. Add these secrets:
   - `ASC_KEY_ID`: the key's ID
   - `ASC_ISSUER_ID`: the Issuer ID shown above the keys
   - `ASC_PRIVATE_KEY`: the whole text of the `.p8` file, BEGIN/END lines included
   - `ASC_APP_ID`: Versely's **Apple ID** (App Store Connect → the app → App Information, a number like 6741234567)

## Checking it

- The dashboard's chips show each source as Connected, Not set up or Error. Hover over a chip to see the error.
- From the SQL editor, run `select public.ops_call_alerts('status');`. Then run `select status_code, content from net._http_response order by id desc limit 1;` to see which sources answer and how many open items there are, without sending email.
- To see the schedules, run `select jobname, schedule from cron.job;`.

## Notes

- **Privacy:**
  - The dashboard shows feedback text and reply addresses only to people on `ops_admins`.
  - Emails leave out reply addresses and testers' emails.
  - Usage numbers are counts only.
  - Nothing new is collected from the app.
- **Triage:** Seen, Resolved, a priority you pick, and notes are kept in `ops_items`. Resolving in-app feedback also sets `app_feedback.resolved`. Content reports are reviewed in the app by group moderators; the dashboard just tracks them.
- **Code:**
  - The rules live in `supabase/functions/_shared/ops.ts`, with Node tests in `ops.test.ts`.
  - Fetching lives in `_shared/opsCollect.ts`.
