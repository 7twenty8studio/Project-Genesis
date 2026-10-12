# Phase 2 setup: accounts, sync and widgets

Everything for Phase 2 is already in the code. These one-time steps switch the
cloud features on. Until they're done the app still runs fully, as a guest.

| Feature | Works now in the Simulator | Needs |
|---|---|---|
| Reading plans, prayer journal, streaks | Yes | Nothing |
| Prayer reminders (local notifications) | Yes | Nothing |
| Email sign-in and cloud sync | After step 1 | Supabase schema |
| Widgets showing your real data | After step 3 | Apple Developer account (App Group) |
| Sign in with Apple | After steps 2–4 | Apple Developer account |

## 1. Create the database tables (Supabase, 2 minutes)

1. Open your project at supabase.com → **SQL Editor** → **New query**.
2. Paste the contents of `supabase/migrations/20260929000000_phase2_sync.sql` and press **Run**.
   It's safe to run again later.
3. **Authentication → Providers → Email**: leave it on. "Confirm email" is on by
   default, so new accounts must click the link in their email before signing in
   (the app tells them). Turn it off while testing if you prefer.
4. **Authentication → URL Configuration**: set the Site URL to anything you own
   for now (e.g. your website). It's used in confirmation and password-reset emails.

Test it: run the app, tap the person icon on Home, create an account, add a
highlight, then check **Table Editor → highlights** in Supabase.

The tables use row-level security: each person can only ever see and change
their own rows. The anon key in the app can't read anyone's data.

## 2–4. Apple Developer account, entitlements and Sign in with Apple

Now in [APPLE_SETUP.md](APPLE_SETUP.md), steps 1 and 2 (Team ID in
`Config/Signing.xcconfig`, the bundle IDs and App Group, Sign in with Apple
in Supabase).

## How sync works (for reference)

- Everything is saved on the device first and works offline.
- Signing in merges guest data into the account. Signing into a *different*
  account on the same device first removes the previous account's data from the
  device (never from the cloud).
- Each record carries a UUID and the time it was last edited; when two devices
  edit the same record, the most recent edit wins. Deletions sync too.
- Sync runs at launch, when the app returns to the foreground, a few seconds
  after any change, and from **Account → Sync Now**.
- Prayer reminders are scheduled on each device and show only the prayer's
  title, never its text.

## Push notifications

Not needed for Phase 2: reminders are local notifications. Remote push for
church groups needs an APNs key: [APPLE_SETUP.md](APPLE_SETUP.md), step 3.
