# Building Genesis

You need a Mac with **Xcode 27.1 or later** (the iPhone Duo simulator arrived in
Xcode 27.1 beta), its **iOS simulator platform**, and **Homebrew**.

If Xcode is missing the iOS platform, the build script offers to download it.
You can also run `xcodebuild -downloadPlatform iOS` yourself. If you use the
beta, point the command line at it once: `sudo xcode-select -s /Applications/Xcode-beta.app`.

## First time

1. **Clone the repo**
   ```bash
   git clone https://github.com/7twenty8studio/Project-Genesis.git
   cd Project-Genesis
   ```

2. **Add your secrets file.** Put `Secrets.xcconfig` (sent to you separately,
   never committed) into the `Config/` folder. Without it the app still builds
   and runs, but Sentry crash reporting is off. To make one yourself, copy
   `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and fill it in.

3. **Build, test and launch with one command**
   ```bash
   ./Scripts/build.sh --open
   ```
   This installs XcodeGen if needed, generates `Genesis.xcodeproj`, builds the
   app, runs the unit tests, launches Genesis in the **iPhone Duo** simulator
   (creating one if needed) and opens the project in Xcode.
   - Another simulator: `SIMULATOR="iPhone 17 Pro" ./Scripts/build.sh`
   - Skip tests: `./Scripts/build.sh --no-tests`

4. **Running from Xcode.** Pick the **Genesis** scheme and **iPhone Duo** in the
   run-destination menu in the toolbar, then press **⌘R**.

## Automated UI tests

UI tests launch Genesis in the Simulator and use it like a person would:
onboarding, turning pages, the controls, chapter navigation, highlighting,
notes, bookmarks, search and reading settings. Each test starts from a clean
slate (a `-uiTesting` launch flag wipes settings and keeps notes in memory).

```bash
./Scripts/build.sh --ui        # iPhone Duo, iPhone Pro and iPad, in parallel
./Scripts/build.sh --ui-full   # plus passes with large text, Slate theme,
                               # scroll mode and page curl, and launch timing
```

Results are saved in `build/TestResults/*.xcresult`. Double-click one to see
each test in Xcode, with screenshots of any failure.

In Xcode, choose the **GenesisUITests** scheme and press **⌘U** to run them on
the selected simulator. The **Genesis** scheme's ⌘U runs only the fast unit tests.

The tests live in `GenesisUITests/`. They find controls by accessibility
identifiers such as `reader.chapterButton` or `selection.highlight.yellow`, so
wording changes don't break them.

## When something fails

`build.sh` writes every compiler error to **`build-errors.txt`** in the project
folder. Send that file (or paste its contents) back to Claude. If it's empty,
send `build.log` instead.

In Xcode you can also open the **Issue navigator** (⌘5), select all (⌘A),
copy (⌘C) and paste.

## Everyday use

- After pulling new code: run `xcodegen generate` (or `./Scripts/build.sh`)
  so new files are added to the project. The `.xcodeproj` is generated from
  `project.yml` and is not committed.
- Run tests in Xcode with **⌘U**.

## Running on your own iPhone

In Xcode select the **Genesis** target → **Signing & Capabilities**, choose your
team (a free personal team works for testing), then pick your device and ⌘R.
The bundle ID is `com.7twenty8studio.genesis`; change it there if Xcode reports
it's taken.

## Rebuilding the Bible databases (rarely needed)

The databases in `Genesis/Resources/Bibles` are generated and committed. To
rebuild them from source:

```bash
git clone --depth 1 https://github.com/scrollmapper/bible_databases /tmp/scrollmapper
git clone --depth 1 https://github.com/TehShrike/world-english-bible /tmp/web
python3 Tools/BibleData/build_bibles.py --scrollmapper /tmp/scrollmapper --web /tmp/web --out Genesis/Resources/Bibles
```
