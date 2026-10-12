# Apple setup: from Developer account to TestFlight

Everything in the code is ready. This is the order to switch it on with your
Apple Developer account. Do the steps in order; each one says where to click.
Never paste keys, `.p8` files or passwords in a chat or commit them to git.

| Step | Where | Time |
|---|---|---|
| 1. Signing: your Team ID, first build | Mac, Xcode | 10 min |
| 2. Sign in with Apple in Supabase | Supabase dashboard | 2 min |
| 3. Push notifications key | developer.apple.com, Supabase | 5 min |
| 4. Premium on the server (functions, migration) | Terminal, Supabase | 5 min |
| 5. App Store Connect: agreements, app, subscriptions | appstoreconnect.apple.com | 1 hour |
| 6. Privacy, age rating, export compliance | App Store Connect | 20 min |
| 7. TestFlight | Xcode, App Store Connect | 20 min |

## 1. Signing: your Team ID and the first build

1. Find your **Team ID**: developer.apple.com → Account → Membership details.
2. In Xcode, sign in to your Apple Account: Xcode → Settings → Accounts → +.
3. In Terminal, in the project folder:

   ```bash
   cp Config/Signing.example.xcconfig Config/Signing.xcconfig
   ```

   Open `Config/Signing.xcconfig` and replace `YOURTEAMID` with your Team ID.
   The file is git-ignored. It turns on the entitlements in
   `Config/Genesis.entitlements` (App Group, Sign in with Apple, Push
   Notifications) and `Config/GenesisWidgets.entitlements` (App Group, also
   used by the watch app and its complication).
4. `./Scripts/build.sh --open`, choose your iPhone (plugged in) or
   **Any iOS Device**, and build (⌘B).

   Xcode signs automatically. The first build registers the four bundle IDs and
   the App Group in your account:

   | Target | Bundle ID |
   |---|---|
   | iPhone/iPad app | `com.7twenty8studio.genesis` |
   | Widgets | `com.7twenty8studio.genesis.widgets` |
   | Watch app | `com.7twenty8studio.genesis.watchkitapp` |
   | Watch complication | `com.7twenty8studio.genesis.watchkitapp.widgets` |
   | App Group (all four) | `group.com.7twenty8studio.genesis` |

5. **If Xcode complains** ("Provisioning profile doesn't include the …
   capability"): select the **Genesis** project → the target named in the
   error → **Signing & Capabilities** → **Try Again**. If it still fails, turn
   the capability on by hand at developer.apple.com → Certificates,
   Identifiers & Profiles → **Identifiers** → click the bundle ID → tick
   **App Groups** (then **Configure** → choose `group.com.7twenty8studio.genesis`),
   **Sign in with Apple** and **Push Notifications** (main app only) → **Save**,
   then build again. The widgets and both watch targets need only **App Groups**.

The watch app and widgets need nothing else: they share data through the App
Group, and the watch app is embedded in the iPhone app.

### Why not iCloud / CloudKit?

Genesis syncs through Supabase on purpose, and we're not adding CloudKit:

- **One sync system.** Notes, prayers, sermons, attachments, groups and
  Premium all live in one place with one set of rules. Two systems syncing
  the same records would duplicate or overwrite each other.
- **One account everywhere.** A Genesis account works on iPhone, iPad, the
  Duo and later a website or Android, and with groups shared between people.
  CloudKit only works for one person's Apple devices.
- **Server checks.** Moderation, group roles, limits and Premium checks run on
  the server, which CloudKit can't do.

So don't turn on the iCloud capability in Xcode.

## 2. Sign in with Apple in Supabase

1. Supabase dashboard → **Authentication** → **Sign In / Providers** →
   **Apple** → turn it on.
2. **Client IDs**: `com.7twenty8studio.genesis`. That's all native sign-in on
   iPhone and iPad needs. Leave the Services ID and secret key empty; they're
   only for signing in on a website later.
3. Try it: run the app on your iPhone, Settings → Account → **Sign in with Apple**.

Good to know:

- Apple requires apps with accounts to let people delete them in the app.
  Genesis has it (Account → Delete Account, the `delete-account` function).
- People can choose **Hide My Email**; you'll then see an address like
  `abc123@privaterelay.appleid.com`. If you'll ever email users (newsletters,
  replies to feedback), register your sending address or domain first:
  developer.apple.com → Certificates, Identifiers & Profiles → **Services** →
  **Sign in with Apple for Email Communication** → Configure. Otherwise those
  emails are dropped.
- Apple also requires apps using Sign in with Apple to revoke the person's
  Apple tokens when they delete their account. Genesis does: for an Apple
  account, Delete Account first asks the person to confirm with Apple, and the
  `delete-account` function swaps that one-time code for Apple's token and
  revokes it. Nothing is stored. It needs a Sign in with Apple key:

  1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** →
     **+**. Name it "Genesis Sign in with Apple", tick **Sign in with Apple**
     → **Configure** → primary App ID **com.7twenty8studio.genesis** → Save →
     Continue → Register → **Download** the `.p8` file (only once: keep it in
     your password manager). Note the **Key ID**.
  2. Supabase dashboard → **Edge Functions** → **Secrets** → add:
     - `APPLE_SIGNIN_KEY`: the whole text of the `.p8` file, including the
       BEGIN/END lines
     - `APPLE_SIGNIN_KEY_ID`: the Key ID
     - `APPLE_TEAM_ID`: your Team ID

     Type them in the dashboard yourself; never paste them in a chat.
  3. Redeploy: `supabase functions deploy delete-account` (JWT verification
     stays on: no `--no-verify-jwt`).

  One key can have several services ticked (APNs and Sign in with Apple
  together), so you could use a single key for both; then put the same `.p8`
  and Key ID in both sets of secrets. A separate key is simpler to replace on
  its own, and Apple allows two Sign in with Apple keys per App ID. Without
  these secrets, accounts are still deleted, but Apple's tokens aren't revoked
  (the function logs a warning).

## 3. Push notifications (group announcements)

1. developer.apple.com → Certificates, Identifiers & Profiles → **Keys** → **+**.
   Name it "Genesis APNs", tick **Apple Push Notifications service (APNs)**
   (if asked, environment **Sandbox & Production**, scope **Team**) → Continue
   → Register → **Download** the `.p8` file. You can download it only once:
   keep it somewhere safe (a password manager). Note the **Key ID**.
2. Supabase dashboard → **Edge Functions** → **Secrets** → add:
   - `APNS_KEY`: the whole text of the `.p8` file (open it in TextEdit, copy
     everything including the BEGIN/END lines)
   - `APNS_KEY_ID`: the Key ID
   - `APNS_TEAM_ID`: your Team ID
3. Deploy (or redeploy) the function: `supabase functions deploy group-notify`.

Sandbox and production: Apple has a test push service (sandbox) and the live
one. The app records which one each device uses (`push_tokens.environment`):
builds run from Xcode in Debug say **sandbox**; Release builds, which is what
TestFlight and the App Store get, say **production**, and TestFlight devices
really do use the live service. If a token turns out to belong to the other
service, `group-notify` tries it there once and corrects the row. One key works
for both. (Xcode switches `aps-environment` from development to production
by itself when you upload a build.)

## 4. Premium on the server

The App Store is the source of truth for subscriptions. The server learns
about them in two ways, so Premium extras that touch the server (attachment
uploads now; more later) are enforced there too:

- **premium-sync**: the app sends its signed App Store transaction after a
  purchase or restore, on sign-in, and when the subscription changes.
- **appstore-notifications**: Apple tells the server about renewals, billing
  problems, expiry, refunds and Family Sharing changes, even if the app is
  never opened.

Both verify Apple's signature with Apple's own certificate chain, so **no App
Store Server API key or In-App Purchase key is needed**.

In Terminal, in the project folder (after `supabase link`, see PHASE3_SETUP.md):

```bash
supabase functions deploy premium-sync
supabase functions deploy appstore-notifications --no-verify-jwt
supabase functions deploy study-ai
```

`--no-verify-jwt` matters: Apple calls `appstore-notifications` without a
Genesis sign-in, and the function checks Apple's signature instead. Always
deploy it with that flag. (`study-ai` is redeployed because it now shares the
App Store code.)

Then in Supabase → SQL Editor → New query, paste and run
`supabase/migrations/20261016000000_premium_checks.sql`. It adds
`genesis_is_premium()` and makes attachment uploads require Premium (reading
and deleting your own files never does). Check everything with
`supabase/verify_setup.sql`.

## 5. App Store Connect

### 5.1 Agreements, tax and banking (do this first)

appstoreconnect.apple.com → **Business** (or Agreements, Tax, and Banking) →
accept the **Paid Apps** agreement, then fill in tax forms and a bank
account. Subscriptions don't load in the app (not even in TestFlight) until
the Paid Apps agreement is **Active**; it can take a day after you submit.

**Small Business Program**: apply at developer.apple.com/app-store/small-business-program
(Apple's commission drops from 30% to 15% while you earn under $1M a year).
Do it now; it applies from the month after approval.

### 5.2 Create the app

Apps → **+** → New App:

- Platforms: **iOS** (the watch app comes inside it)
- Name: **Genesis** (if it's taken, try "Genesis: Bible Reader"; the name on
  the Home Screen stays "Genesis")
- Primary language: **English (U.S.)**
- Bundle ID: **com.7twenty8studio.genesis**
- SKU: anything only you use, e.g. `GENESIS001`
- User access: Full access

Then App Information → **Localizable Information** → add **Spanish (Mexico)**
or **Spanish (Spain)** (the app's screens are in English and Spanish).

### 5.3 Subscriptions

App → **Monetization → Subscriptions** → Subscription Groups → **+**:

- Reference name: `Genesis Premium`
- Localization (English and Spanish): display name **Genesis Premium**

Add four auto-renewable subscriptions. The product IDs must match exactly
(they're in the app, `Config/Genesis.storekit` and the server):

| Reference name | Product ID | Duration | Price (USD) | Level | Family Sharing |
|---|---|---|---|---|---|
| Premium Family Monthly | `com.7twenty8studio.genesis.premium.family.monthly` | 1 month | $12.99 | 1 | **On** |
| Premium Family Yearly | `com.7twenty8studio.genesis.premium.family.yearly` | 1 year | $99.99 | 1 | **On** |
| Premium Monthly | `com.7twenty8studio.genesis.premium.monthly` | 1 month | $7.99 | 2 | Off |
| Premium Yearly | `com.7twenty8studio.genesis.premium.yearly` | 1 year | $59.99 | 2 | Off |

- **Family Sharing** can't be turned off once on: switch it on only for the
  two Family products.
- **Levels**: drag the Family products above the Individual ones (level 1 is
  the highest), so moving from Individual to Family is an upgrade.
- **Prices**: choose the USD price; let Apple set the other countries.
- **Introductory offer** on each product: Subscription Prices → **+** →
  Create Introductory Offer → all countries → **Free** → **1 week**.
- **Localization** for each product (display name ≤ 30 characters,
  description ≤ 45):

  | Product | English name | English description | Spanish name | Spanish description |
  |---|---|---|---|---|
  | Monthly | Premium Monthly | Every Premium feature for one person | Premium mensual | Todo Premium para una persona |
  | Yearly | Premium Yearly | Every Premium feature for one person | Premium anual | Todo Premium para una persona |
  | Family Monthly | Premium Family Monthly | Premium for you and up to 5 family members | Premium familiar mensual | Premium para ti y hasta 5 familiares |
  | Family Yearly | Premium Family Yearly | Premium for you and up to 5 family members | Premium familiar anual | Premium para ti y hasta 5 familiares |

- **Review Information** on each product: a screenshot of the Premium screen
  (the **Genesis Premium** card on Home, on an iPhone or simulator) and a note
  such as "Unlocks Premium features: themes, word study, journal attachments,
  widgets, Memorise, ambient sounds. Purchase from the Genesis Premium card on
  Home."
- The first subscriptions are reviewed together with the first app version:
  on the version page, under **In-App Purchases and Subscriptions**, add all
  four before submitting.
- App Review checks that the app description (or the EULA field) links to
  your Terms of Use; Apple's standard EULA is fine:
  `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`.

### 5.4 Server notifications

App → **App Information** → **App Store Server Notifications**:

- Production Server URL: `https://ulbpwygzwchsnvdeeife.supabase.co/functions/v1/appstore-notifications`
- Sandbox Server URL: the same address
- Version: **Version 2**

To see them arrive: make a TestFlight or sandbox purchase, then Supabase →
Edge Functions → appstore-notifications → **Logs** shows lines like
`SUBSCRIBED/INITIAL_BUY … → extend, 1 row(s)`. Sandbox subscriptions renew
fast (a month every 5 minutes, a year every hour) and stop after a few
renewals, so you'll see renewals and an expiry within the hour.

## 6. Privacy, age rating, export compliance

### Privacy policy (still needed)

You need a public privacy policy page before submitting. Then:

- App Store Connect → App Privacy → **Privacy Policy URL**, and
- `GENESIS_PRIVACY_URL` in `Config/Secrets.xcconfig` (shown on the Premium
  screen; see PHASE3_SETUP.md).

Also add a **Support URL** (App Information) with a way to contact you.

### App Privacy questionnaire

App Store Connect → **App Privacy** → Get Started. Answer **Yes, we collect
data**, then tick exactly these. For every one: **not used for tracking**.
These answers match the privacy manifest in
`Config/Privacy/Genesis/PrivacyInfo.xcprivacy`.

| Category → Data type | Linked to the person | Purposes | What it is in Genesis |
|---|---|---|---|
| Contact Info → Email Address | Yes | App Functionality | Account sign-in; optional reply address in Send Feedback |
| Contact Info → Name | Yes | App Functionality | Display name in groups and the community |
| User Content → Photos or Videos | Yes | App Functionality | Photos on prayers and sermon notes |
| User Content → Audio Data | Yes | App Functionality | Voice recordings on prayers and sermon notes |
| User Content → Customer Support | Yes | App Functionality | Send Feedback messages |
| User Content → Other User Content | Yes | App Functionality | Notes, highlights, prayers, sermons, PDFs, Pencil pages, plans, group posts |
| Sensitive Info → Sensitive Info | Yes | App Functionality | Prayers and journal entries can reveal religious beliefs |
| Identifiers → User ID | Yes | App Functionality | The account id |
| Purchases → Purchase History | Yes | App Functionality | The subscription recorded for the account |
| Diagnostics → Crash Data | **No** | App Functionality, Analytics | Sentry crash reports (no user id) |
| Diagnostics → Other Diagnostic Data | Yes | App Functionality, Analytics | Error reports; app/iOS version and device sent with feedback |

Everything else: **not collected** (location, contacts, health, financial
info, browsing or search history, usage data / product interaction,
advertising data, other identifiers, performance data). Genesis has no
analytics or advertising SDK, and Sentry's performance tracing is off. Xcode's
privacy report (Organizer → the archive → Generate Privacy Report) also shows
Sentry's own manifest, which lists Performance Data in general terms; Genesis
doesn't send any, so "not collected" is right.

The widgets and the watch app have their own manifests (they collect nothing).

### Age rating

App Information → **Age Rating** → Edit. Answer honestly; Apple works out the
rating. Genesis has **user-generated content** (church groups, and the
community when you switch it on) and **messaging between users** inside
groups. Say so: the app already has what Apple requires for that (guideline
1.2): reporting, blocking, deleting your own posts, a word filter, moderators
and rate limits (see PHASE4_SETUP.md). No violence, no gambling, no unrestricted
web browsing.

### Export compliance

Genesis uses only standard HTTPS. `ITSAppUsesNonExemptEncryption` is already
**NO** in the app's Info.plist (project.yml), so App Store Connect won't ask
on each upload.

## 7. TestFlight

1. In Xcode, scheme **Genesis**, destination **Any iOS Device (arm64)** →
   **Product → Archive**. (Bump `CURRENT_PROJECT_VERSION` in project.yml for
   each new upload, then `xcodegen generate`.)
2. The Organizer opens → **Distribute App** → **App Store Connect** →
   **Upload**. Wait for the email that the build has processed (10–30 min).
3. App Store Connect → **TestFlight** → Internal Testing → **+** → add
   yourself and up to 100 people from your team → choose the build.
4. Testers install **TestFlight** from the App Store and accept the invite.

Buying Premium while testing:

- **TestFlight**: purchases are free, use the tester's own Apple Account, and
  renew fast (see 5.4). Nothing to set up beyond 5.1–5.3.
- **Your own builds from Xcode with ⌘R**: use the local test store in
  `Config/Genesis.storekit` (PHASE3_SETUP.md, step 4). To let those test
  purchases count on the server too, add the Supabase secret
  `ALLOW_XCODE_STOREKIT` = `true` **only while testing locally**, and **delete
  it before release**: it accepts Xcode's self-signed test purchases.
- **A sandbox tester** (App Store Connect → Users and Access → **Sandbox** →
  Test Accounts → +) is for builds installed from Xcode without the local
  store (`./Scripts/build.sh` on a device). On the iPhone: Settings → App
  Store → **Sandbox Account** → sign in with it.

## Checklist before submitting

- [ ] Paid Apps agreement active; Small Business Program applied for
- [ ] Four subscriptions with English and Spanish names, intro offer, review screenshot
- [ ] Server notifications URL (Production and Sandbox, Version 2)
- [ ] `premium-sync`, `appstore-notifications` (`--no-verify-jwt`), `study-ai`, `group-notify`, `delete-account` deployed
- [ ] Migration `20261016000000_premium_checks.sql` run
- [ ] APNs secrets set
- [ ] Privacy policy and support URLs; App Privacy answers as above
- [ ] `ALLOW_XCODE_STOREKIT` secret deleted
- [ ] Sign in with Apple key secrets set (`APPLE_SIGNIN_KEY`, `APPLE_SIGNIN_KEY_ID`, `APPLE_TEAM_ID`) and `delete-account` redeployed
