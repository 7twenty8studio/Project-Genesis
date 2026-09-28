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
   run-destination menu in the toolbar, then press **⌘R**. In the Simulator,
   use the Duo's fold control to switch between closed and open.

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
