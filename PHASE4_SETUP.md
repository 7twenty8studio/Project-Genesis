# Phase 4 setup

Phase 4 adds the Audio Bible, church groups and the community. Everything is
free (no Premium needed).

| Feature | Works now | Needs |
|---|---|---|
| Audio Bible, device voices | Yes, every translation, offline | Nothing |
| Audio Bible, recorded narration | After step 1 | The audio SQL and one recording added |
| Church groups | After step 2 | The groups SQL (one paste) |
| Prayer wall and reflections | After step 2 + switch | The same SQL, then turn `community` on |
| Announcement notifications | After step 3 | Apple Developer account, an APNs key |
| Topic search, feature choices, Duo panels, lock-screen prayer widget | Yes | Nothing |
| Downloading more Bibles (Berean Standard Bible) | After step 4 | The Bibles SQL and one upload |

The new **Together** tab appears once the groups SQL has run. Groups and the
community need people to sign in (free).

## Audio Bible

Tap the headphones in the reader. The device voice reads verse by verse; with
**Follow Along** on (the default) the page turns and the verse being read is
marked. Listening continues with the phone locked, from the lock screen,
Control Center and headphones, with speed (0.75×–2×) and a sleep timer.

Device voices sound best with a Premium voice (Zoe, Ava, Evan, Nathan and
others): on the iPhone, Settings › Accessibility › Spoken Content › Voices ›
English, download one (about 100–200 MB). Genesis's Automatic setting then
uses it; a particular voice can be chosen under Audio Settings. The older
robotic voices (Eddy, Flo, Reed, Grandma and the like) aren't offered.
Simulators usually have only the basic voices, so judge the sound on a phone.

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

## 2. Church groups and the community

**Run the SQL (once):** SQL Editor → New query → paste
`supabase/migrations/20261003000000_groups_community.sql` → Run. Safe to run
again.

That creates everything with row-level security on every table, and two
switches in `feature_flags`:

- `groups`: **on**. People can start groups, join with an invite code, read a
  plan together, share prayer requests, discuss each day's reading and post
  announcements (leaders).
- `community`: **off**. The public prayer wall and reflections. Turn it on
  (Table Editor → `feature_flags` → `enabled`) when you're ready to look at
  reports regularly; see below.

Groups are private to their members. Leaders can edit the group, make a new
invite code, make others leaders, remove members and delete any post in their
group.

### Keeping the community safe (App Store guideline 1.2)

Apple requires apps with user posts to have a content filter, reporting,
blocking and someone acting on reports. Genesis has all four:

- **Guidelines:** people agree to the community guidelines before their first
  post.
- **Filter:** posts, names and group content are checked against the
  `blocked_terms` table (a starter list is included; add words in Table Editor,
  lowercase, one per row). Posting is limited to 20 an hour per person.
- **Report and block:** every post and comment has a … menu with Report and
  Block. Reported posts disappear for the reporter; **three reports hide a post
  for everyone** until you review it. Blocked people's posts disappear for the
  person who blocked them.
- **Your review list:** Table Editor → `moderation_queue` shows open reports
  with the content and author. Then, in the SQL Editor:
  ```sql
  -- Dealt with (keeps it hidden if it was hidden):
  update public.content_reports set resolved_at = now() where content_id = '<id>';
  -- It was fine, show it again:
  update public.community_posts set hidden_at = null where id = '<id>';
  -- Stop someone posting in the community:
  insert into public.community_bans (user_id, reason) values ('<author>', 'reason');
  ```
  Apple expects reports to be acted on within 24 hours. Check daily while the
  community is on.
- **Contact:** App Review also wants a way to reach you. Put a support email on
  the App Store listing and your website.

### 3. Notifications for announcements

When a leader posts an announcement, members get a push notification (they
can turn it off per group). This needs your Apple Developer account:

1. Apple Developer → Certificates, Identifiers & Profiles → **Keys** → add a key
   with **Apple Push Notifications service (APNs)**. Download the `.p8` file
   (only once) and note the **Key ID** and your **Team ID**.
2. In Xcode, the app needs the Push Notifications capability. It's already in
   `Config/Genesis.entitlements`; it switches on with your
   `Config/Signing.xcconfig` (see PHASE2_SETUP.md).
3. Add three Supabase secrets (Edge Functions → Secrets). **Don't paste them in
   chat.**
   - `APNS_KEY`: the whole text of the `.p8` file
   - `APNS_KEY_ID`: the Key ID
   - `APNS_TEAM_ID`: your Team ID
4. Deploy the function: `supabase functions deploy group-notify`

Builds run from Xcode use Apple's test (sandbox) push service; TestFlight and
App Store builds use the live one. Without the secrets, announcements still
post; nobody is notified.

## Testing it

- `./Scripts/build.sh --ui` runs the groups and community tests against a
  built-in test server (no network, no account).
- Server rules: the SQL was tested on Postgres for outsiders, faked names,
  leader-only actions, the word filter, rate limits, reports hiding posts,
  blocking and bans.
- `node --experimental-strip-types --test supabase/functions/group-notify/lib.test.ts`
  checks the notification signing and payload.

## 4. More Bibles to download (Berean Standard Bible)

The KJV, WEB and ASV come with the app. More translations are downloaded from
Home › Bibles on This Device › Get More, Home › Settings (gear) › Bibles, or
the reader's translation menu › More Bibles. Downloads work offline for good, and when you
publish a corrected edition the app updates them automatically on Wi-Fi.

1. **Create the table and storage (once):** SQL Editor → paste
   `supabase/migrations/20261004000000_bible_translations.sql` → Run. It also
   creates a public storage bucket called `bibles`.
2. **Upload the file:** Storage → `bibles` → Upload →
   `BSB-1.sqlite.deflate` (sent to you; or build it yourself with
   `Tools/BibleData/package_translation.py`, see the top of that file).
3. **List it:** SQL Editor → paste `BSB-1.sql` → Run.

The Berean Standard Bible has been public domain since April 30, 2023. Its
translators ask only that the Berean name isn't used for altered text; Genesis
shows it word for word. Licensed translations (NIV, ESV, NLT, CSB, NKJV) can be
listed the same way once you have a license that allows offline use.

## Feature choices

New people choose what they'd like at the end of setup ("Make Genesis yours"),
or tap Keep It Simple for just the reader, notes, highlights and search. Anyone
can change this in Home › Settings (gear) › Features. Your Supabase switches
still decide what exists; people only choose among what's switched on.

People who set Genesis up before this screen existed keep everything. Groups
and the community start hidden for new people; the What's New note for a
feature someone has hidden offers a Turn On button.
