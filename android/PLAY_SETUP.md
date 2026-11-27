# Google Play: Premium and push setup

Versely for Android sells Premium through Google Play Billing and gets group
announcements and nudges through Firebase Cloud Messaging. The code is in
place and stays switched off until the steps below are done. Without them,
the Premium screen says Premium isn't available yet and no push token is
sent.

## 1. Database (once)

Run `supabase/migrations/20261130000000_android_premium_push.sql`. It adds
`premium_entitlements.store` ('app_store' or 'google_play') and the
`android_push_tokens` table (RLS on, each person sees only their own rows).
Run it before deploying the functions below.

## 2. The subscription in the Play Console

1. Monetize › Products › Subscriptions › Create subscription, with the
   product id `com.7twenty8studio.versely.premium` (the same id as iOS;
   `PlayBilling.PREMIUM_PRODUCT`, `PLAY_PRODUCT_IDS` in
   supabase/functions/_shared/play.ts).
2. Two auto-renewing base plans with the ids `monthly` ($7.99) and
   `yearly` ($59.99).
3. Optional: a free-trial offer on each base plan (for example 7 days, new
   customers only). The Premium screen shows it when the Google account can
   still have it.
4. Google Play has no Family Sharing for subscriptions, so Android offers the
   Individual plan only. The server would also accept a
   `com.7twenty8studio.versely.premium.family` product if one is made later.

## 3. Checking purchases on the server

1. In Google Cloud (the project linked to the Play Console), create a
   service account and a JSON key for it.
2. In the Play Console › Users and permissions, invite the service
   account's email with "View financial data" and "Manage orders and
   subscriptions".
3. Add Supabase Edge Function secrets:
   - `GOOGLE_PLAY_SERVICE_ACCOUNT`: the whole JSON key.
   - `GOOGLE_PLAY_PACKAGE`: only if the app id isn't
     `com.seventwenty8studio.versely`.
   - `PLAY_RTDN_SECRET`: a random string of 24 or more characters.
4. Deploy `premium-sync` (as before) and `play-notifications` with
   `--no-verify-jwt`.

## 4. Real-time developer notifications

1. In Google Cloud › Pub/Sub, create a topic (for example `versely-play`)
   and give `google-play-developer-notifications@system.gserviceaccount.com`
   the Publisher role on it.
2. Add a push subscription to the topic, with this endpoint:
   `https://<project>.supabase.co/functions/v1/play-notifications?secret=<PLAY_RTDN_SECRET>`
3. In the Play Console › Monetization setup, enter the topic name and send a
   test notification. It answers 200.

Renewals, cancellations, refunds and expiries then reach
`premium_entitlements` without the app being opened.

## 5. Push (Firebase Cloud Messaging)

1. Create a Firebase project and add an Android app with the app id.
2. Put its values in `android/local.properties` (no google-services.json is
   needed):
   ```
   versely.firebaseAppId=1:...:android:...
   versely.firebaseApiKey=...
   versely.firebaseProjectId=...
   versely.firebaseSenderId=...
   ```
3. Firebase › Project settings › Service accounts › Generate new private
   key. Save the JSON as the Edge Function secret `FIREBASE_SERVICE_ACCOUNT`.
4. Deploy `group-notify` again. It now sends to iPhones (APNs) and Android
   phones (FCM). Dead Android tokens are removed when FCM reports them.

## Testing

- Add testers as licence testers (Play Console › Settings › License
  testing). Their purchases renew quickly and are never charged.
- The app must be installed from a Play testing track (internal testing is
  enough) for Billing to answer. A build run from Android Studio shows
  "Premium isn't available yet".
