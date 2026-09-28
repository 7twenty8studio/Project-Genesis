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

## Building
- The Xcode project is generated: `xcodegen generate` from `project.yml`.
  Don't commit `.xcodeproj`.
- Development happens in a Linux container that cannot compile Swift. The
  owner builds with `./Scripts/build.sh` and sends back `build-errors.txt`.
  Write code carefully for Swift 6 strict concurrency (view models are
  `@MainActor @Observable`; SQLite repositories are `Sendable`).
- `Config/Secrets.xcconfig` is git-ignored (Supabase URL + anon key, Sentry DSN).

## Conventions
- MVVM, composition, one responsibility per type, small view files.
- SwiftUI first; UIKit only for the TextKit reader text and page curl.
- Verses are addressed by `VerseID` (book*1_000_000 + chapter*1_000 + verse).
- Swift Testing for unit tests of business logic.
- Muted colours only; themes live in `ReaderTheme`.
