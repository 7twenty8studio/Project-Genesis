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

## Architecture

```
Genesis/
  App/              App entry, root view, tab navigation, router
  Core/
    Bible/          VerseID, book catalogue, SQLite repositories, library
    Search/         Reference parser, FTS5 query builder, search
    Settings/       Reader preferences, themes, fonts
    Storage/        Minimal read-only SQLite wrapper
    UserData/       SwiftData models (highlights, notes, bookmarks) + StudyStore
    Services/       Config, Sentry crash reporting, reading progress, daily verse
  Features/         Reader, Home, Search, Library, Study, Onboarding (SwiftUI)
  DesignSystem/     Shared components
  Resources/        Bible databases, fonts, assets
GenesisTests/       Swift Testing unit tests
Tools/BibleData/    Script that builds the Bible databases
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
