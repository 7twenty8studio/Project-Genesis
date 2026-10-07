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
- Every Bible is free. Notes, highlights, the prayer journal, reading plans
  and cloud sync (with a free account) are free with no limits, and so are
  Explore's timeline and people. `FreeLimits` holds only the 3 AI answers a
  day, enforced again on the server (supabase/functions/study-ai/lib.ts;
  Premium gets 30 new answers a day). Premium extras are
  `PremiumFeature` cases checked with `EntitlementService.allows` at each entry
  point (the tier table is in PHASE3_SETUP.md). Plans (`PremiumPlan`, `PremiumProduct`):
  Individual $7.99 / $59.99 (Family Sharing off) and Family $12.99 / $99.99
  (Family Sharing on), one subscription group; study-ai accepts all four.
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

## Morning welcome
- Premium (`.morningWelcome`): the first open each day shows
  `MorningWelcomeView` (greeting by name, today's verse verbatim from the
  current Bible, today's plan reading, the person's ambient mix easing in).
  `MorningWelcome` keeps the settings (Settings › Morning Welcome) and the
  once-a-day rule; RootView presents it and skips it when opened from a link.
  UI tests only see it with `-uiTestingWelcome`.
- Explore: the timeline, people and places are free; family trees
  (`PremiumTeaser`), the Map tab and the reader's Context panel need
  `.historicalContent`.

## Word study, journaling, reading touches
- Word study (Premium, `.wordStudy`): Resources/Study/WordStudy.sqlite, built
  by Tools/StudyData/build_wordstudy.py from STEPBible TAHOT/TAGNT/TBESG
  (CC BY 4.0), Strong's Hebrew via Open Scriptures (CC BY 4.0) and Matthew
  Henry's Concise Commentary (public domain); keep LICENSE.txt and
  `WordStudyRepository.attribution`. Hebrew/Greek shown verbatim; English
  verses always come from the Bible databases. `VerseStudyView` opens from the
  selection bar (Word Study); free accounts see two words and a teaser.
- Original Word (Premium, `.wordStudy`): long-pressing a word to select its
  verse records the word (`PressedWord`); the selection bar's row opens
  `OriginalWordView`, which ranks the verse's Hebrew/Greek forms by their
  contextual English gloss (`OriginalWordMatcher`, "Likely" vs "Closest
  match"). English Bibles only; always links to the whole verse's words.
- Handwritten pages (free): `Note.drawing` (PencilKit data, external storage),
  synced as base64 in notes.drawing (≤ 2 MB; larger stays on the device).
  Journal entries offer `JournalPrompts`.
- Reading touches: `ReaderPreferences.largeInitial` (restyles, never changes,
  the first letter; verse 1's number is dropped), `pageTurnSound`
  (`PageTurnFeedback`, a system sound so no audio session; page-turn-1…5.caf
  are five loudness levels of a Pixabay recording, built by
  Tools/Sounds/make_page_turn.py and credited in Resources/Sounds/SoundCredits.txt;
  `pageTurnVolume` picks one) and `pageTurnHaptic` (medium, `pageTurnHapticStrength`).

## Premium look and feel
- Look (`.premiumThemes`): `ReaderPreferences.initialStyle` illuminated (an
  ornament image as an NSTextAttachment before verse 1, the real letters kept
  invisible so the text stays verbatim), Premium fonts (Crimson Pro, Source
  Serif 4, Spectral; OFL, built by Tools/Fonts/make_fonts.py), Premium app
  icons (all but the standard one), and `ChapterMoments` (a gold ribbon on
  finishing a chapter or plan day; UI tests only with `-uiTestingMoments`).
  Without Premium the reader falls back to plain/New York, keeping the choice.
- Night reading stays in the normal reader (no separate night screen): the
  Night theme (free, warm dark page) and Starlight (Premium via
  `.premiumThemes`, night-blue paper with faint stars and, without Reduce
  Motion, a slow twinkle in the margins, `StarlightTwinkleView`).
  `ReaderPreferences.nightReading` ("At night, switch to", start/end hour)
  is decided by the pure `NightReading.theme(for:dayTheme:now:calendar:premium:)`;
  `ReaderSettings.effectiveTheme(for:premium:)` resolves it for RootView and
  the reader (`nightClock` is moved on at each window edge). Starlight
  without Premium falls back to Night, keeping the choice. UI tests never
  switch unless launched with `-uiTestingNight` (then it's always night).
- Widgets: only the small verse of the day and Lock Screen verse are free
  (`WidgetAccess` in Genesis/Shared); every other widget/size shows a locked
  card. Premium widgets use the reading theme (colours carried in
  `WidgetSnapshot.theme` as hex, since the extension can't use ThemePalette).
- Year in Review: free shares one card; with `.readingInsights`, up to three.

## Memorise Scripture
- Premium (`.memorise`), shown with Plans & Prayer. Games (`MemoryGame`):
  Fill the Gaps, Word Order and Speed Round use only the verse's real words
  and finish on the exact text; results feed the schedule only when the verse
  is due (never as Easy). Levels Seed → Cedar come from mastered passages;
  the practice streak is local (`MemoryProgress`, UserDefaults). `MemoryVerse` (SwiftData,
  synced as `memory_verses`) stores the passage's verse ids, translation and
  `MemorySchedule` (a gentle SM-2); never the text. Hints are the passage's
  opening words, verbatim (`MemoryHint.opening`), never altered text.
- The Memorise widget reads `WidgetSnapshot.memorise` (written with the
  entitlement); deep link `genesis://memorise`.

## Premium widgets
- `.widgets` (every widget but the small/Lock Screen verse): the Today's Reading widget (tick via `TogglePlanDayIntent`,
  which leaves `PendingPlanDays` in the App Group for the app to apply), and
  the listening Live Activity (`ListeningActivityController`, driven by
  `AudioPlayerService`; buttons are `LiveActivityIntent`s that call
  `ListeningControl`). Shared types live in Genesis/Shared/WidgetIntents.swift.
  Only the small and Lock Screen verse of the day are free (`WidgetAccess`).
- Apple Watch (verse of the day, Premium): GenesisWatch + GenesisWatchWidgets
  targets, fed by `WatchConnector` (WatchConnectivity application context,
  `WatchPayload`). Embedded in the iPhone app (a dependency of Genesis in
  project.yml), so every build needs the watchOS platform installed in Xcode;
  `./Scripts/build.sh --watch` also builds it on its own.

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
- Group roles: one owner (`groups.owner_id`), moderators (role `'leader'`,
  which the owner also has, so "leader" checks mean owner or moderator) and
  members. Only the owner chooses moderators, hands the group over
  (`transfer_group_ownership`) or deletes it; moderators remove, ban
  (`group_bans`, no rejoining) or mute (`muted_until`) members but never
  other moderators or the owner (`genesis_can_moderate`). Optional join
  approval (`requires_approval`, `group_join_requests`). Reports on group
  posts reach the group's moderators (`group_reports`, `review_group_report`);
  three hide a post or prayer until reviewed. App: `GroupPermissions`,
  `GroupModerationView`; the in-memory backend mirrors every rule.
- Group challenges (free): reading, memorise, streak and prayer
  (`group_challenges`, check-ins only through `set_challenge_checkin`,
  progress from `group_challenge_progress`; no rankings). Separate
  `GroupChallengeBackend` (`\.groupChallenges`, in memory in UI tests).
  Memorise challenges store verse ids only; the passage is shown verbatim
  from the person's Bible.
- Anything people post needs report, block and (for its author) delete:
  `.contentActions(...)`. App Store guideline 1.2.
- Switches: `groups` (on) and `community` (off until the owner moderates).
- Topic search: Resources/Study/Topics.sqlite (Nave's, CC BY 4.0 via BibleData),
  built by Tools/TopicData/build_topics.py; ids only, never verse text.
- Translation downloads: public.bible_translations + the public `bibles`
  bucket; Tools/BibleData/package_translation.py builds a file and its row.
  Public-domain (or licensed) translations only.
- Global Reading Library (the Bibles screen, `BibleDownloadsView`): Bibles by
  language, most read first, as `TranslationCardView`s, plus
  `TranslationGuideView` ("Which Bible is right for me?"). Logic in
  `ReadingLibrary`; details (`TranslationProfile`: approach, reading level,
  rights, popularity) come from bible_translations columns, falling back to
  `TranslationProfile.builtIn`. Free, like every Bible.

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
