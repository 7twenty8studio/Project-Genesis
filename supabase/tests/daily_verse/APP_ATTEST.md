# Daily Verse Games 1.0: public reports with App Attest

Daily Verse Games 1.0 sends "Report a puzzle issue" straight to Studio OS → Inbox →
Daily Verse (the same `daily_verse.reports` table and `dv-admin` the Internal
builds already use). Public builds must prove each request comes from our app on
a genuine Apple device, with **App Attest**, verified on the server.

Files: `supabase/functions/_shared/appAttest.ts` (verification, pure),
`dv-report/index.ts` (flow), migration `20261117000000_daily_verse_app_attest.sql`
(+ rollback), tests `_shared/appAttest.test.ts` (real Apple attestations),
`tests_app_attest.sql` (database), `app_attest/` (end-to-end over HTTP).

## What the server checks

- **Attestation** (once per key): Apple's steps 1–9. The certificate chain must lead
  to the pinned Apple App Attestation Root CA (SHA-256
  `1CB9823B…62C932`, a constant, never configurable), the nonce must match
  `SHA256(authData ‖ SHA256(challenge))`, the key id must be the SHA-256 of the key,
  the App ID must be `4XTR53RY2V.com.7twenty8studio.dailyverse`, counter 0, and the
  environment `production` (development keys only if the Vault/secret
  `DV_ATTEST_ALLOW_DEVELOPMENT` is `true`; it isn't set). Public reports need a
  production key regardless.
- **Assertion** (every report): signature with the stored key over
  `SHA256(authenticatorData ‖ SHA256(challenge + "\n" + exact body bytes))`, our App
  ID, and a counter above the stored one (stored atomically, so a replay loses).
- **Challenges**: 32 random bytes, single use, 5 minutes, stored only as a SHA-256.
- **Channel** is still decided by the server from the build number
  (`DV_INTERNAL_BUILDS`); everything else is `public`. Public stays closed
  (`settings.accepted_channels = {internal}`) until opened on purpose.

## Rate limits (all server-side)

| What | Limit |
|---|---|
| Challenges per network (/24 or /48) | 60 an hour, burst 20; 1,200 an hour overall |
| New keys per network | 10 an hour |
| Reports per attested key | 5 an hour |
| Reports per install / network / overall (unchanged) | 5 / 20 / 300 an hour; 20 a day per install |
| Same install + puzzle + category within 10 minutes (unchanged) | kept once |
| Same `reportID` (a retry) | kept once, answers 200 `duplicate` |

## What is stored

- Report: as before (the report text, category, puzzle date/type/id, language,
  app version and build, iOS version, iPhone or iPad, review state) plus
  `client_report_id` (the app's random id for that report, for retries). The
  install id and network prefix are stored only as HMACs, as before.
- `attest_keys`: HMAC of the key id, the device key's **public** key, environment,
  counter, created/last-used times. No Apple receipt, no device or person data.
  Deleted after a year unused (`purge_expired`); the app then makes a new key.
- `attest_challenges`: hashes only, deleted once used or expired.

## The app's side (contract)

All requests: `POST https://ulbpwygzwchsnvdeeife.supabase.co/functions/v1/dv-report`,
header `apikey: <publishable key>`, JSON. Build the report body **once**, keep its
exact bytes and `reportID` until it's accepted.

1. **Key** (once, then reuse): if `DCAppAttestService.shared.isSupported` is false,
   don't offer direct sending (offer Email/Share/Copy instead). Otherwise, with no
   saved key: `generateKey()` → `keyId`; `{action:"challenge", purpose:"attest"}` →
   `challenge`; `attestKey(keyId, clientDataHash: SHA256(UTF-8 challenge))`;
   `{action:"attest", keyId, attestation: base64, challenge}` → 200. Save `keyId`
   (Keychain, this device only) only after the 200.
2. **Report**: `{action:"challenge", purpose:"report"}` → `challenge`;
   `generateAssertion(keyId, clientDataHash: SHA256(UTF-8 challenge + "\n" + bodyBytes))`;
   POST `bodyBytes` exactly, with headers `x-dv-attest-key: <keyId>`,
   `x-dv-assertion: <base64>`, `x-dv-challenge: <challenge>`.
   The body is the existing report JSON plus `"reportID": "<UUID>"` (made when the
   player taps Send the first time; the same for every retry).
3. **Answers**: show success only on **201** or **200** (`duplicate: true` means an
   earlier try already got through). On anything else keep the report on screen
   with Try Again; a retry repeats step 2 with the same body and `reportID`.
   - 401 `reason: "challenge"`: get a new challenge and send again (once, automatically).
   - 401 `reason: "key"`: forget the saved key, do step 1 again, then step 2 (once).
   - 401 `reason: "invalid"` / `"required"`, 400: show the error; don't loop.
   - 429: wait `Retry-After` seconds; 503: reports are closed; 5xx / offline: Try Again.
   - `DCError.invalidKey` from `generateAssertion`: forget the key, redo step 1.
4. **Entitlement**: `com.apple.developer.devicecheck.appattest-environment` =
   `production` for Internal and Release (TestFlight and the App Store use
   production either way; this keeps Xcode-installed Release builds the same).

## Opening public reports (production, separate approval)

After the migration is applied, dv-report deployed and a production-key test
passes, one statement opens public reports:

```sql
update daily_verse.settings set accepted_channels = array['internal', 'public'], updated_at = now() where id = 1;
```

Closing them again: the same with `array['internal']`. Rollback of everything:
`supabase/rollback/20261117000000_daily_verse_app_attest_down.sql` (closes public
first; reports stay).

## Running the tests

```sh
node --experimental-strip-types --test supabase/functions/*/*.test.ts      # includes real Apple attestations
PGBIN=… supabase/tests/daily_verse/run.sh                                   # database checks, both migrations
PGBIN=… DENO=deno FN_PORT=8000 supabase/tests/daily_verse/app_attest/run.sh # end to end over HTTP
```
