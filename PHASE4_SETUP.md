# Phase 4 setup

Phase 4 adds the Audio Bible, church groups and the community. Everything is
free (no Premium needed).

| Feature | Works now | Needs |
|---|---|---|
| Audio Bible, device voices | Yes, every translation, offline | Nothing |
| Audio Bible, recorded narration | After step 1 | The audio SQL and one recording added |

## Audio Bible

Tap the headphones in the reader. The device voice reads verse by verse; with
**Follow Along** on (the default) the page turns and the verse being read is
marked. Listening continues with the phone locked, from the lock screen,
Control Center and headphones, with speed (0.75×–2×) and a sleep timer.

Device voices sound best with an Enhanced or Premium voice: on the iPhone,
Settings › Accessibility › Spoken Content › Voices › English, then pick it in
Genesis under Audio Settings.

### 1. Recorded narration (optional)

Recordings are listed in Supabase, so you can add, move or withdraw them
without an app update.

1. **Create the table (once):** SQL Editor → New query → paste
   `supabase/migrations/20261002000000_audio_recordings.sql` → Run.
2. **Add the World English Bible read by Basil Sands** (public domain, one file
   per chapter, from eBible.org). On your Mac, in the project folder:
   ```bash
   python3 Tools/AudioData/make_audio_manifest.py \
       --listing https://ebible.org/engwebu/mp3/ \
       --id web-basil-sands --translation WEB --title "Basil Sands" \
       --description "World English Bible, read by Basil Sands." \
       --license "Public domain" --source https://ebible.org/engwebu/mp3/ \
       --enable --out build/audio-web-basil-sands.sql
   ```
   It lists the files, matches each to its chapter and checks none are
   missing. If it reports missing or unmatched files, send me its output.
3. Open `build/audio-web-basil-sands.sql`, paste it into the SQL Editor and Run.
4. In Genesis switch to the WEB, open Audio Settings and choose
   **Recorded · Basil Sands**.

To withdraw a recording: Table Editor → `audio_recordings` → set `enabled` to
`false`. The app falls back to the device voice.

**Hosting.** The files stream straight from eBible.org, which invites copying
and mirroring. Once many people listen, copy the files to your own storage
(for example Cloudflare R2, which has free downloads) and run the script again
with `--rebase https://your-storage/web/`.

**Other translations.** No public-domain human recording with one file per
chapter turned up for the KJV or ASV (LibriVox's KJV is split into
multi-chapter files). They use the device voice; a recording can be added the
same way later.

**Small differences.** The recording is of the "WEB Updated" edition, so a
word here and there may differ from the WEB text on screen. Recorded audio
plays chapter by chapter and doesn't mark individual verses.
