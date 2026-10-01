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

## Phase 4: audio, groups, community
- Audio: `AudioPlayerService` (device voices via `SpeechNarrator`, recordings
  via `RecordingPlayer`, catalog in public.audio_recordings). UI tests use the
  silent `StubNarrator`. Recorded narration must be public domain.
- Groups and community: `CommunityBackend` (Supabase, `InMemoryCommunityBackend`
  in UI tests). The database enforces membership, leader-only actions, author
  names, the word filter and rate limits; keep it that way rather than trusting
  the app. The community feed comes from `community_feed()` so anonymous
  authors stay anonymous; `user_id` on community_posts isn't readable.
- Anything people post needs report, block and (for its author) delete:
  `.contentActions(...)`. App Store guideline 1.2.
- Switches: `groups` (on) and `community` (off until the owner moderates).

## What's New
- Every new user-facing feature gets a one-time announcement in
  `WhatsNewCatalog.all` (Genesis/Core/WhatsNew/WhatsNew.swift) with a new,
  never-reused id. Features behind a Supabase switch set `flag` so the note
  appears when the switch turns on. UI tests only see it with `-uiTestingWhatsNew`.

## Conventions
- MVVM, composition, one responsibility per type, small view files.
- SwiftUI first; UIKit only for the TextKit reader text and page curl.
- Verses are addressed by `VerseID` (book*1_000_000 + chapter*1_000 + verse).
- Swift Testing for unit tests of business logic.
- Muted colours only; themes live in `ReaderTheme`.
