# Phase 3 setup: study assistant and Premium

Everything for Phase 3 is in the code. The timeline, maps, people and insights
work offline as soon as you build. These steps switch on the parts that need a
server or the App Store.

| Feature | Works now in the Simulator | Needs |
|---|---|---|
| Timeline, maps, people, insights | Yes, with Premium | Nothing (try Premium with ⌘R, below) |
| Buying Premium | With ⌘R from Xcode | Nothing for testing; App Store Connect for real purchases |
| Study assistant | After steps 1–3 | Supabase CLI, an Anthropic API key |

## 1. Create the study assistant's tables (Supabase, 1 minute)

SQL Editor → New query → paste `supabase/migrations/20260930000000_phase3_study_ai.sql`
→ Run. Safe to run again. It adds the shared answer cache, daily usage counts
and verified subscriptions, all with row-level security.

## 2. Add your Anthropic API key as a secret

Create a key at console.anthropic.com (Settings → API Keys). **Don't paste it
in chat or commit it.** Then either:

- Dashboard: Supabase → Edge Functions → Secrets → add `ANTHROPIC_API_KEY`, or
- Terminal: `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`

Tip: set a monthly spend limit in the Anthropic console (Settings → Limits).

## 3. Deploy the Edge Function

Install the Supabase CLI once, link the project, then deploy:

```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref ulbpwygzwchsnvdeeife
supabase functions deploy study-ai
```

Try it: run the app, sign in (a free account is enough), open a chapter,
long-press a verse and tap **Explain**.

## 4. Try Premium in the Simulator

Open the project in Xcode (`./Scripts/build.sh --open`), choose an iPhone
simulator and press **⌘R**. The Genesis scheme uses `Config/Genesis.storekit`,
a local test store: subscribing costs nothing and needs no Apple account.
Manage test purchases (renew, expire, refund) from Xcode → Debug → StoreKit →
Manage Transactions. (`./Scripts/build.sh` launches the app without the test
store, so purchases only work with ⌘R.)

To let test purchases unlock the study assistant's Premium tools, add the
secret `ALLOW_XCODE_STOREKIT` = `true`. **Remove it before release**: it accepts
Xcode's local test signatures.

## 5. Before release (App Store Connect)

1. Create the subscription group **Genesis Premium** with two auto-renewable
   subscriptions whose product IDs match exactly:
   - `com.7twenty8studio.genesis.premium.monthly` at $4.99
   - `com.7twenty8studio.genesis.premium.yearly` at $39.99
   Turn on Family Sharing (the PRD lists it as a Premium feature).
2. Publish a privacy policy and set `GENESIS_PRIVACY_URL` in
   `Config/Secrets.xcconfig` (e.g. `https:$(SLASH)$(SLASH)example.com/privacy`).
   App Review requires it on the Premium screen. Terms default to Apple's
   standard licence agreement; set `GENESIS_TERMS_URL` to use your own.
3. Delete the `ALLOW_XCODE_STOREKIT` secret if you added it.

## What's free and what's Premium

| Free | Premium ($4.99/month or $39.99/year) |
|---|---|
| Reading, search, every translation, cross references | Everything in Free |
| Highlights, bookmarks, reading plans | Unlimited notes and prayer journal |
| 25 notes, 25 prayer requests | Cloud backup and sync |
| Themes: Auto, Paper, Sepia, Slate, High Contrast | Themes: Cream, Parchment, Midnight, Sage |
| 3 passage explanations a day (with a free account) | Every study tool: summaries, background, discussion, children's explanations, comprehension (fair use: 50 new answers a day) |
| Streak, chapters and books on Home | Timeline, maps and journeys, people and family trees |
| | Reading insights |

## How the study assistant works (for reference)

- The app sends the passage reference and its verse text (as context) to the
  `study-ai` Edge Function with the person's sign-in token.
- The function checks the account's daily limit, returns a cached answer if
  anyone has asked before, and otherwise asks Claude Haiku 4.5.
- The model is told never to quote Scripture and to be non-denominational,
  noting where traditions differ. As a safety net, any run of six or more
  words from the passage is removed from the answer.
- The app shows the Scripture from its own database and the answer in a
  separate card labelled **AI-generated study notes · not Scripture**.
- Premium is checked on the server by verifying the App Store's signed
  transaction against Apple's root certificate. One subscription unlocks one
  account.
- Cost: roughly $0.003 per new answer. Cached answers cost nothing, and each
  device also keeps the answers it has already seen.

Server logic tests (Node 22 and openssl):

```bash
node --experimental-strip-types --test supabase/functions/study-ai/lib.test.ts
```
