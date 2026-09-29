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

## 2. Apple Developer account

1. Note your **Team ID** (developer.apple.com → Account → Membership details).
2. **Certificates, Identifiers & Profiles → Identifiers → App IDs**: register
   `com.7twenty8studio.genesis` with the **App Groups** and **Sign in with Apple**
   capabilities, and `com.7twenty8studio.genesis.widgets` with **App Groups**.
3. **Identifiers → App Groups**: register `group.com.7twenty8studio.genesis` and
   add it to both App IDs.

(Xcode can do 2 and 3 for you if you let it manage signing; the IDs must match.)

## 3. Turn on entitlements in the project

```bash
cp Config/Signing.example.xcconfig Config/Signing.xcconfig
```

Edit `Config/Signing.xcconfig` and replace `YOURTEAMID` with your Team ID. Then
run `./Scripts/build.sh`. This enables the App Group (widgets read your data)
and the Sign in with Apple capability. The file is git-ignored.

## 4. Sign in with Apple in Supabase

1. In Supabase: **Authentication → Providers → Apple** → enable.
2. Under **Client IDs**, add `com.7twenty8studio.genesis` (the app's bundle ID).
   For native iOS sign-in that is all Supabase needs; the secret key fields are
   only for web sign-in.
3. Run the app on a device or simulator signed in to an Apple ID and tap
   **Sign in with Apple** on the account screen.

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

Not needed for Phase 2: reminders are local notifications. Remote push
(for example church groups in Phase 4) will need an APNs key from the developer
account; we'll add it then.
