# Versely for Android

The Android app (code name Genesis, people see Versely): native Kotlin and
Jetpack Compose, sharing the Supabase backend, the bundled Bible databases and
the data tools with the iOS app. The plan and its phases:
[docs/ANDROID_PLAN.md](../docs/ANDROID_PLAN.md).

## Build

Needs JDK 21 and the Android SDK (platform 37.2). Builds and tests also run in
Claude's cloud container, so no build errors need sending back.

```sh
cd android
echo "sdk.dir=$HOME/Library/Android/sdk" > local.properties   # once, on a Mac
./gradlew :core:domain:test     # pure rules, against the shared fixtures
./gradlew :app:assembleDebug    # app/build/outputs/apk/debug/app-debug.apk
```

## Modules

| Module | What it holds |
| --- | --- |
| `app` | Activity, screens, navigation |
| `core:domain` | Pure Kotlin rules, no Android: books, verse ids, the reference parser, themes |
| `core:bible` | Read-only access to the bundled Bibles (the iOS files, shared) |
| `core:design` | Versely's colours and type for Compose |

## Shared with iOS and the web

- **Bibles:** `Genesis/Resources/Bibles/*.sqlite` are the app's assets, not copies.
- **Book names and verse counts:** `supabase/functions/_shared/bibleBooks.json`
  (generated from `BibleBook.swift` and the KJV by
  `Tools/BibleData/export_reference_books.py`).
- **Reference parsing cases:** `supabase/functions/_shared/fixtures/references.json`;
  `ReferenceParserTest` runs the same cases as iOS and the web.
- **Strings:** `Tools/Localization/android_strings.json` names each resource
  and its English; `python3 Tools/Localization/build_android_strings.py`
  writes English, Spanish and Brazilian Portuguese from `es.json` and `pt.json`.
  Don't edit `res/values*/strings.xml` by hand.

## Rules that carry over

Everything in the repository's CLAUDE.md applies: Scripture verbatim from the
databases, AI labelled and kept apart, YouVersion text never in paid tools,
church sermons and core features free, the same names as iOS.
