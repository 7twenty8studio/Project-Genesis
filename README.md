# Genesis

The most elegant and immersive way to experience Scripture on Apple devices.
A calm, Kindle-inspired Bible reader for iPhone, iPhone Duo and iPad. Fully
offline, native SwiftUI.

See [BUILDING.md](BUILDING.md) to build and run.

## Phase 1 (this release)

- **Reader**: page mode (slide or page-curl) and scroll mode; tap to show or
  hide controls; tap the page edges or swipe to turn; pages flow across
  chapters and books. Left-handed mode.
- **Offline Bibles**: KJV, WEB and ASV bundled (public domain), plus 340,000
  cross references from OpenBible.info.
- **Search**: references ("jn 3:16", "1 Cor 13:4-7"), book names, words and
  exact phrases, with SQLite FTS5. Typical query: 1–2 ms.
- **Themes and typography**: Paper, Cream, Sepia, Parchment, Slate, High
  Contrast or Auto. New York, SF Pro, Georgia, Baskerville, Atkinson
  Hyperlegible. Adjustable size, line spacing, paragraph spacing, margins,
  brightness, verse numbers, paragraph or verse-by-verse layout. Dynamic Type.
- **Study**: long-press a verse to select; highlight in six named colours,
  organise highlights into collections, bookmark, copy, share, write notes
  (note, prayer, study, journal) on verses, chapters or themes, and see
  cross references.
- **Wide screens**: on iPad and an open iPhone Duo a study panel (notes,
  related passages, search) sits beside the text.
- **Home**: continue reading, verse of the day, recent highlights and notes,
  Bibles on this device.

## Phase 2 (built; switch on with [PHASE2_SETUP.md](PHASE2_SETUP.md))

- **Accounts**: email, Sign in with Apple, or guest (fully offline).
- **Cloud sync** with Supabase: highlights, collections, notes, bookmarks,
  reading plans and prayers. Offline first, newest edit wins, deletions sync,
  row-level security per user.
- **Reading plans**: Bible in a Year, Chronological, New Testament in 90 Days,
  Gospels in 30 Days, Psalms in 30 Days, and custom plans from any books.
- **Prayer journal**: private requests by category, answered prayers with
  notes, daily or one-off reminders.
- **Home**: today's reading, prayer journal, streak and progress.
- **Widgets**: verse of the day, continue reading, reading progress (large),
  lock screen streak, verse and continue reading. Tapping opens the app in place.

## Phase 3 (built; switch on with [PHASE3_SETUP.md](PHASE3_SETUP.md))

- **Study assistant**: explain a passage, summarize a chapter, historical
  background, discussion questions, an explanation for children, reading
  comprehension. Claude Haiku 4.5 through a Supabase Edge Function; answers are
  cached and shared. Non-denominational, never quotes Scripture, always shown
  apart from the text and labelled as AI-generated. **Switched off for now**
  (`GENESIS_AI_ENABLED` in Config/Genesis.xcconfig).
- **Timeline**: twelve eras from Creation to Revelation with 450 events; tap an
  event for its people, places and chapters.
- **Maps**: 1,250 located places on Apple Maps, Paul's journeys and a
  traditional Exodus route.
- **People**: 3,000+ people with biographies, family trees, timelines, books,
  verses and places.
- **Insights**: streaks, reading time, chapters, books, highlights, favourite
  books and topics.
- **Premium** with StoreKit 2: $4.99/month or $39.99/year, per the PRD's
  Premium Features list.
- **Wide screens**: the study panel adds Study (AI notes beside the text) and
  Context (people, places and events in the chapter).

## Architecture

```
Genesis/
  App/              App entry, root view, tab navigation, router
  Core/
    Bible/          VerseID, book catalogue, SQLite repositories, library
    Search/         Reference parser, FTS5 query builder, search
    Settings/       Reader preferences, themes, fonts
    Storage/        Minimal read-only SQLite wrapper
    UserData/       SwiftData models (highlights, notes, bookmarks, plans, prayers) + StudyStore
    Cloud/          Supabase client, auth, sync engine
    AI/             Study assistant client
    Premium/        StoreKit 2 entitlements and free limits
    Study/          People, places, events and routes (Study.sqlite)
    Plans/          Reading plan schedules
    Services/       Config, Sentry, reading progress/streaks, reminders, widget snapshot
  Shared/           Code shared with the widget extension
  Features/         Reader, Home, Search, Library, Study, Explore, Insights,
                    Premium, Plans, Prayer, Account, Onboarding (SwiftUI)
  DesignSystem/     Shared components
  Resources/        Bible databases, fonts, assets
GenesisWidgets/     WidgetKit extension
GenesisTests/       Swift Testing unit tests
GenesisUITests/     XCUITest UI automation
supabase/           Database schema (SQL migrations) and the study-ai Edge Function
Tools/BibleData/    Script that builds the Bible databases
Tools/StudyData/    Script that builds Study.sqlite
```

- **MVVM** with `@Observable` view models; dependencies passed through the
  SwiftUI environment.
- **Scripture is never altered.** Verse text is stored verbatim and rendered
  from the local database. Only whitespace is normalised at build time.
  Paragraph and poetry layout for KJV/ASV is borrowed from the WEB as
  formatting only.
- **Verses are addressed translation-independently** (`book*1_000_000 +
  chapter*1_000 + verse`), so highlights and notes follow you across
  translations.
- The reader draws text with **TextKit 1** (`ReaderTextView`), the same
  engine `Paginator` measures with, so pages are exact. This is the one
  place UIKit is used, for page layout and page-curl.
- Personal data lives in **SwiftData** with UUIDs and timestamps, ready for
  Phase 2 Supabase sync.

## Attribution

- Cross references: [OpenBible.info](https://www.openbible.info/labs/cross-references/), CC-BY.
- Bible text sources: [scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases) (KJV, ASV)
  and [TehShrike/world-english-bible](https://github.com/TehShrike/world-english-bible) (WEB). All translations are public domain;
  "World English Bible" is a trademark of eBible.org.
- Atkinson Hyperlegible: Braille Institute, SIL Open Font License.
- People, places and events: [Theographic Bible Metadata](https://github.com/robertrouse/theographic-bible-metadata)
  by Robert Rouse, CC BY-SA 4.0; place coordinates from
  [OpenBible.info](https://github.com/openbibleinfo/Bible-Geocoding-Data), CC BY 4.0;
  descriptions from Easton's Bible Dictionary (1897, public domain). The
  derived `Study.sqlite` is CC BY-SA 4.0 (see `Genesis/Resources/Study/LICENSE.txt`).
- iPhone Duo hinge helper for UI tests adapted from
  [hinge](https://github.com/artemnovichkov/hinge) by Artem Novichkov, MIT.
