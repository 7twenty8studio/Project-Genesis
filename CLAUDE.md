# Project Genesis: notes for Claude

A premium, offline-first Bible reader for iPhone, iPhone Duo and iPad
(SwiftUI, iOS 26+, Swift 6). Product requirements live in the PRD the owner
shares; README.md has the architecture.

## Rules that never bend
- Never alter Scripture text. Verse text comes verbatim from the bundled
  SQLite databases. AI features (Phase 3) must never return verse text; the
  app renders verses from the database and visibly labels AI content.
- Phase 1 ships public-domain translations only (KJV, WEB, ASV). Licensed
  translations wait until the owner confirms a license.
- AI content must be non-denominational and presented as distinct from Scripture.
  The study-ai Edge Function (Claude Haiku 4.5) is told never to quote and
  removes 6+ word runs from the passage; the app labels answers "AI-generated
  study notes · not Scripture" in a separate card. Keep both safeguards.
- Study.sqlite (people/places/events) is CC BY-SA 4.0: keep the attribution
  and LICENSE.txt with it. It holds verse ids only, never verse text.

## Building
- The Xcode project is generated: `xcodegen generate` from `project.yml`.
  Don't commit `.xcodeproj`.
- Development happens in a Linux container that cannot compile Swift. The
  owner builds with `./Scripts/build.sh` and sends back `build-errors.txt`.
  Write code carefully for Swift 6 strict concurrency (view models are
  `@MainActor @Observable`; SQLite repositories are `Sendable`).
- `Config/Secrets.xcconfig` is git-ignored (Supabase URL + anon key, Sentry DSN).
- `Config/Signing.xcconfig` (git-ignored) sets the team and turns on entitlements
  (App Group, Sign in with Apple). Without it builds have no entitlements.
- UI tests: `./Scripts/build.sh --ui` / `--ui-full`; failures are extracted from
  .xcresult into build/TestResults/*-failures.txt.

## Sync
- Supabase schema lives in `supabase/migrations`; every table has user_id,
  updated_at (client edit time, last writer wins), deleted_at (soft delete) and
  server_updated_at (trigger-stamped pull cursor). Keep RLS on every table.
- Local deletions must go through StudyStore so a Tombstone is recorded.
- New synced models need: a Remote* row in SyncRows.swift, pull/apply and push
  in SyncService, a table + RLS in a new migration.

## Premium and AI
- Free limits live in `FreeLimits` (25 notes, 25 prayers, 3 AI a day) and are
  checked with `EntitlementService` at each entry point; the server enforces
  AI limits again (supabase/functions/study-ai/lib.ts).
- The study assistant is behind a server-side switch (public.feature_flags row
  `study_assistant`, read by `FeatureFlagService`; off for now). Check
  `StudyAssistant.isEnabled` before showing any AI entry point; study-ai also
  refuses while it's off. UI tests turn it on with `-uiTestingAI`.
- UI tests are free unless launched with `-uiTestingPremium`; the study
  assistant uses `StubStudyBackend` in UI tests (no network, no cost).
- Server logic tests: `node --experimental-strip-types --test supabase/functions/study-ai/lib.test.ts`.
- Supabase SQL: explicit statements, no drops, RLS enabled in plain
  `alter table` lines (the dashboard's checker flags anything else).

## Premium sources, feedback and accounts
- `EntitlementService.isPremium` = App Store subscription, or a grant in
  public.premium_grants (the owner adds rows; `refreshGrant` on launch,
  foreground and sign-in; study-ai honours grants too), or in DEBUG builds
  only Settings › Developer › Test as Premium. UI tests' override wins.
- Free trial: an introductory offer in App Store Connect (and in
  Config/Genesis.storekit); the paywall shows it when the account is eligible.
- Settings › Send Feedback writes public.app_feedback (insert-only RLS; read
  in the dashboard). Account › Delete Account calls the `delete-account` Edge
  Function (App Store 5.1.1(v)); every table cascades from auth.users.

## Memorise Scripture
- Premium (`.memorise`), shown with Plans & Prayer. `MemoryVerse` (SwiftData,
  synced as `memory_verses`) stores the passage's verse ids, translation and
  `MemorySchedule` (a gentle SM-2); never the text. Hints are the passage's
  opening words, verbatim (`MemoryHint.opening`), never altered text.
- The Memorise widget reads `WidgetSnapshot.memorise` (written with the
  entitlement); deep link `genesis://memorise`.

## Premium widgets
- `.widgets`: the Today's Reading widget (tick via `TogglePlanDayIntent`,
  which leaves `PendingPlanDays` in the App Group for the app to apply), and
  the listening Live Activity (`ListeningActivityController`, driven by
  `AudioPlayerService`; buttons are `LiveActivityIntent`s that call
  `ListeningControl`). Shared types live in Genesis/Shared/WidgetIntents.swift.
  The widgets that were free before stay free.
- Apple Watch (verse of the day, Premium): GenesisWatch + GenesisWatchWidgets
  targets, fed by `WatchConnector` (WatchConnectivity application context,
  `WatchPayload`). Built with `./Scripts/build.sh --watch`; not embedded in
  the iPhone app until the owner is ready (add `- target: GenesisWatch` to
  Genesis's dependencies), so everyday builds don't need watchOS.

## Phase 4: audio, groups, community
- Audio: `AudioPlayerService` (device voices via `SpeechNarrator`, recordings
  via `RecordingPlayer`, catalog in public.audio_recordings). UI tests use the
  silent `StubNarrator`. Recorded narration must be public domain.
- Ambient sounds (Premium, `.ambientSounds`): `AmbientSoundService` mixes the
  bundled loops (`ambient-*.m4a`, built by Tools/Ambient/make_ambient.py;
  sources and licences in Resources/Ambient/AmbientCredits.txt) through
  `EngineAmbientOutput`; UI tests use `SilentAmbientOutput`. Narration and
  ambient share the session through `AudioSession.begin/end`; don't call
  AVAudioSession directly.
- What's playing shows on every tab but the reader as a tab-bar accessory
  (`NowPlayingAccessory`, iOS 26.1+) that opens `NowPlayingSheet` with full
  controls for both; the reader keeps its own listening and ambient bars.
- Groups and community: `CommunityBackend` (Supabase, `InMemoryCommunityBackend`
  in UI tests). The database enforces membership, leader-only actions, author
  names, the word filter and rate limits; keep it that way rather than trusting
  the app. The community feed comes from `community_feed()` so anonymous
  authors stay anonymous; `user_id` on community_posts isn't readable.
- Group plan progress: `group_progress_summary(p_group)` (members only) feeds
  each member's bar; any day can be marked read and has its own discussion
  (Every Day of the Plan). The Group Progress widget (Premium) reads
  `GroupWidgetSnapshot` (App Group file written by `GroupDetailModel`).
- Anything people post needs report, block and (for its author) delete:
  `.contentActions(...)`. App Store guideline 1.2.
- Switches: `groups` (on) and `community` (off until the owner moderates).
- Topic search: Resources/Study/Topics.sqlite (Nave's, CC BY 4.0 via BibleData),
  built by Tools/TopicData/build_topics.py; ids only, never verse text.
- Translation downloads: public.bible_translations + the public `bibles`
  bucket; Tools/BibleData/package_translation.py builds a file and its row.
  Public-domain (or licensed) translations only.

## Feature choices
- People choose optional features at setup ("Make Genesis yours") and in
  Settings › Features: `FeaturePreferences` (listen, plansAndPrayer, explore,
  studyAssistant, together). Reading, notes, highlights and search are always
  on. A feature shows only if its server switch allows it *and* the person
  wants it: use `features.shows(_:flags:)` / `isOn(_:)` at every entry point
  of a new optional feature, and give it a case in `OptionalFeature`.
- Hiding never deletes data. One-time tips use TipKit (`GenesisTips`),
  hidden in UI tests.

## What's New
- Every new user-facing feature gets a one-time announcement in
  `WhatsNewCatalog.all` (Genesis/Core/WhatsNew/WhatsNew.swift) with a new,
  never-reused id. Features behind a Supabase switch set `flag` so the note
  appears when the switch turns on. UI tests only see it with `-uiTestingWhatsNew`.

## Languages
- Screens are in English and Spanish (String Catalogs:
  Genesis/Resources/Localizable.xcstrings and GenesisWidgets/Localizable.xcstrings).
  Don't edit the catalogs by hand: write new text in English in code (a Text/
  Button literal, or `String(localized:)` for any String that's displayed), add
  its Spanish to Tools/Localization/es.json, then run
  `python3 Tools/Localization/build_catalogs.py` (it fails on missing Spanish
  or mismatched %@/%lld). One sentence per string; no English fragments glued
  together. On the Mac, `./Scripts/localization_check.sh` lists anything Xcode
  sees without Spanish.
- People choose the language in the iPhone's Settings (Settings › Language in
  Genesis opens it). `AppLanguage.code` is "en" or "es".
- `BibleBook.name` follows the app's language (`englishName` is fixed);
  the reference parser accepts English and Spanish names, accents optional.
  Next to Scripture (reader title and controls, running head, book picker,
  selection, audio, verse images, shares) names follow the Bible's language:
  `ChapterID/PassageReference.description(in: translation.language)`.
- Each Translation has a `language`; narration picks a voice in it. The study
  assistant answers in the app's language (`language` in the request; the
  cache key gets a suffix for non-English).
- Spanish Bible: Reina-Valera 1909 (public domain), downloadable, built from
  open-bibles' USFX with Spanish verse numbering. Scripture is never
  translated or edited; data from Study.sqlite and Topics.sqlite stays English.

## Navigation
- iPhone (compact width) shows at most five tabs: Home, Read, Library,
  Explore, Together. Search is a button there (Home, Library) opening
  `SearchSheet`, as in the Bible app; iPad and the open Duo keep the Search
  tab. Don't add tabs without moving something out.
- The reader's side panel (notes, plans, prayer) shows only when the text
  keeps 440 pt beside it (iPad; the open Duo held sideways). Reader controls
  fall back to tighter buttons, then a "More" menu, rather than squeezing.
- Don't put `.accessibilityIdentifier` on a container whose children have
  their own identifiers (SwiftUI passes it down and replaces theirs).

## Conventions
- MVVM, composition, one responsibility per type, small view files.
- SwiftUI first; UIKit only for the TextKit reader text and page curl.
- Verses are addressed by `VerseID` (book*1_000_000 + chapter*1_000 + verse).
- Swift Testing for unit tests of business logic.
- Muted colours only; themes live in `ReaderTheme`. Every List/Form wraps its
  content in `ThemedRows { }` so rows take the theme's surface colour
  (otherwise they stay system white), plus `.themedScreen()` on the list.
