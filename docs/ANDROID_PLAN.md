# Genesis for Android: plan

This is the plan for the Android rewrite (PRD Phase 4, "Android planning").
Android is a native rewrite, not a port: the iOS app stays SwiftUI, and the
Android app is Kotlin with Jetpack Compose. Both share the Supabase backend,
the Bible databases and the study data, so most of what makes Genesis work
is reused as-is.

## Goals

- Feature parity with iOS Phases 1–4 for phones, foldables and tablets.
- The same rules: Scripture text verbatim from the bundled databases;
  public-domain translations only until a license is confirmed; AI notes
  labelled and kept apart from Scripture; muted, calm design.
- One backend. An account, highlights, notes, plans, prayers, groups and
  Premium carry across iPhone and Android.
- Android 10 (API 29) and newer, which covers about 95% of active devices.

## What's shared, what's rebuilt

| Piece | Shared as-is | Rebuilt for Android |
|---|---|---|
| Bible text (KJV, WEB, ASV SQLite) | ✓ bundled in `assets/` | Reader on Room/SQLite |
| Cross references, study data (`Study.sqlite`, CC BY-SA) | ✓ | Explore screens |
| Supabase tables, RLS, sync protocol | ✓ | Kotlin sync client |
| `study-ai` Edge Function | ✓ (plus a Google Play check, below) | Study assistant UI |
| `group-notify` Edge Function | Extended to send FCM too | Groups UI |
| Feature switches, audio catalog, What's New ids | ✓ | — |
| UI, pagination, page turns, widgets, audio | — | ✓ |

## Stack

| Concern | Choice | iOS counterpart |
|---|---|---|
| Language, UI | Kotlin 2, Jetpack Compose, Material 3 (muted custom theme) | Swift 6, SwiftUI |
| Architecture | MVVM: `ViewModel` + `StateFlow`, repositories, Hilt | `@Observable` view models |
| Local data | Room (notes, highlights, plans, prayers, tombstones); read-only SQLite for Bibles | SwiftData, SQLite |
| Network | Ktor client + kotlinx.serialization (no Supabase SDK, matching iOS) | URLSession client |
| Auth | Supabase email + Google sign-in; Sign in with Apple via Supabase's web OAuth | Sign in with Apple, email |
| Purchases | Google Play Billing 7 | StoreKit 2 |
| Reader text | Compose text with `TextMeasurer` pagination; a custom curl for page-turn | TextKit 1, UIPageViewController |
| Foldables | Jetpack WindowManager (`FoldingFeature`, window size classes) | iPhone Duo postures |
| Audio | Media3 ExoPlayer + `MediaSessionService`; `TextToSpeech` with `onRangeStart` for follow-along | AVPlayer, AVSpeechSynthesizer |
| Widgets | Jetpack Glance | WidgetKit |
| Push | Firebase Cloud Messaging | APNs |
| Crash reporting | Sentry Android (same project) | Sentry |
| Tests | JUnit 5 + Turbine for logic; Compose UI tests on emulators | Swift Testing, XCUITest |

## Module layout

```
app/                    navigation, DI, theme
core/bible/             VerseID, books, translations, repositories (shared DB files)
core/data/              Room database: user data, tombstones
core/sync/              Supabase client, auth, sync service (same cursor protocol)
core/premium/           Billing, entitlements, FreeLimits (25/25/3)
core/audio/             TTS narrator, recording player, media session
core/community/         groups and community backend (same tables and actions)
feature/reader/         pagination, page turns, selection, companion pane
feature/home|library|plans|prayer|explore|insights|search|together|study/
widget/                 Glance widgets
```

Keep the iOS names (VerseID = book×1,000,000 + chapter×1,000 + verse, the
same table and column names, the same feature-flag keys and What's New ids)
so the two apps stay easy to compare.

## Backend changes Android needs

These are small and keep iOS working unchanged:

1. **Premium on Android.** `study-ai` verifies App Store purchases today. Add a
   Google Play path: the app sends its purchase token; the function verifies
   it with the Google Play Developer API (a service-account secret) and stores
   the result in `premium_entitlements` with a `platform` column. Same limits.
2. **Push on Android.** Add a `platform` column to `push_tokens`
   (`ios`/`android`) and teach `group-notify` to send FCM HTTP v1 messages (a
   Firebase service-account secret) alongside APNs.
3. **Sign in with Apple on Android** goes through Supabase's OAuth web flow
   (needs a Services ID and return URL in the Apple developer account).
   Google sign-in is the main Android option.

## Reader on Android

The reader is the hardest part and the heart of the app, so it comes first.

- **Pagination:** lay out each chapter with `TextMeasurer` at the page size and
  split by line; cache per chapter and style, exactly like `Paginator.swift`.
  Verse ids travel as string annotations for taps, highlights and selection.
- **Page turns:** slide with `HorizontalPager`; page curl with a custom
  Canvas-based curl (there's no system one). Scroll mode with `LazyColumn`.
- **Foldables:** on a book-posture fold, show two pages side by side split at
  the hinge; on an open tablet-posture fold or tablet, text plus the companion
  panel (notes, related, study, context, search), as on the open iPhone Duo.
- **Accessibility:** TalkBack reads verses with numbers; font scale up to 200%;
  reduced motion turns curl into slide.

## Phases and rough effort (one experienced Android developer)

| Step | Scope | Weeks |
|---|---|---|
| A. Foundations | Project, theme, Bible DB access, navigation, CI, Sentry | 2 |
| B. Reader | Pagination, slide/curl/scroll, selection, highlights, notes, bookmarks, settings, foldable layouts | 5 |
| C. Phase 1 parity | Home, search (FTS), library, onboarding, cross references, widgets | 3 |
| D. Phase 2 parity | Accounts, sync (same protocol and tombstones), plans, prayer journal, reminders | 3 |
| E. Phase 3 parity | Billing + server check, explore (timeline, Maps SDK, people), insights, study assistant (behind its switch) | 4 |
| F. Phase 4 parity | Audio (TTS follow-along, recordings, media session), Together tab, FCM | 3 |
| G. Polish and release | Tablet/foldable QA, accessibility pass, Play listing, data safety form, staged rollout | 2 |
| **Total** | | **≈ 22 weeks** |

Steps B–F can overlap with a second developer (reader and data in parallel),
bringing it to about 14 weeks.

## Testing

- The same behaviour checks as iOS, as Compose UI tests: reading and turning
  pages, highlights, notes, search, plans, prayers, premium gates, audio
  follow-along, groups.
- Emulator matrix: a small phone (360 dp), a large phone, Pixel Fold (folded,
  half-open, open), a 10" tablet, landscape on each; dark theme; 200% font.
- A fake backend for UI tests, like `InMemoryCommunityBackend` and the stub
  study backend, so tests need no network or account.

## Play Store requirements to plan for

- **Data safety form:** account email, user content (notes, prayers, posts)
  synced to Supabase, crash data to Sentry; nothing sold or used for ads.
- **User-generated content policy:** the same guidelines, filter, reporting,
  blocking and moderation as iOS (already server-side).
- **Subscriptions:** Play Billing only for digital goods; restore via
  `queryPurchasesAsync`; cancellation links to Play's subscription center.
- **Target API level:** keep to the current Play requirement (API 35 in 2026).

## Decisions for the owner

1. **Who builds it:** in-house Kotlin developer, an agency, or Claude-assisted
   like the iOS app (the build-and-send-errors loop works the same way with
   Gradle).
2. **Launch scope:** full parity (≈ 22 weeks), or a reading-first release
   (steps A–D, ≈ 13 weeks) with Premium and community following.
3. **Pricing on Play:** the same $4.99 / $39.99, and whether one Premium
   subscription should unlock both platforms (needs the cross-platform
   entitlement check above; Apple and Google allow it if each store's purchase
   is honoured on its own platform).
