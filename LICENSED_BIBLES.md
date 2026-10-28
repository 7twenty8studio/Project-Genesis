# Licensed Bibles (Digital Bible Library)

**Free stays free.** A Bible whose licence costs Versely nothing is free for
every reader. Only a Bible whose publisher charges Versely a fee needs
Premium (publish it with `--premium`).

Versely is a distributor in the Digital Bible Library (DBL). Membership lets
Versely *request* Bibles. Each publisher then approves (or declines) its own
Bible, with its own licence terms. A Bible goes live in Versely only after
its publisher has approved it for Versely and the terms below are known.

## 1. Which Bibles to request

These are the most read in each language. Search for each one in the DBL.
If a Bible isn't listed there, its publisher licenses it directly: ask them
through the contact shown.

### English

| Bible | Publisher | Where to ask |
|---|---|---|
| New International Version (NIV) | Biblica | Biblica's Permission Request Form (biblica.com/permission-request-form), plus an email to rightspermissions@biblica.com. Biblica declined our DBL request (October 2026) and asked for this route. A full Bible needs proof of a registered legal entity, and Biblica generally waits for a finished, launched app |
| New Living Translation (NLT) | Tyndale House | DBL if listed, else tyndale.com/permissions |
| English Standard Version (ESV) | Crossway | Crossway directly: crossway.org/permissions/digital |
| New King James Version (NKJV) | HarperCollins Christian Publishing (Thomas Nelson) | Directly (permissions at harpercollinschristian.com) |
| Christian Standard Bible (CSB) | Holman Bible Publishers (Lifeway) | Directly (csbible.com) |
| New American Standard Bible (NASB 2020) and Amplified (AMP) | The Lockman Foundation | Directly (lockman.org) |
| Good News Translation (GNT) and Contemporary English Version (CEV) | American Bible Society | DBL (a United Bible Societies member) |
| New International Reader's Version (NIrV) | Biblica | As for the NIV |

### Spanish

| Bible | Publisher | Where to ask |
|---|---|---|
| Reina-Valera 1960 (RVR1960) | Sociedades Bíblicas Unidas / American Bible Society | DBL |
| Nueva Versión Internacional (NVI) | Biblica | As for the NIV |
| Nueva Traducción Viviente (NTV) | Tyndale House | DBL if listed, else Tyndale directly |
| Dios Habla Hoy (DHH), Traducción en Lenguaje Actual (TLA), Reina Valera Contemporánea (RVC) | Sociedades Bíblicas Unidas | DBL |
| La Biblia de las Américas (LBLA) and Nueva Biblia de las Américas (NBLA) | The Lockman Foundation | Directly (lockman.org) |

A good first round is the NIV, the NLT, the RVR1960, the NVI and the NTV:
together they cover most readers in both languages.

The "Where to ask" column is a guide. The DBL itself is the authority on
which entries it carries.

## 2. Ask every publisher these questions

Write the answers down for each Bible. The app is built to satisfy the usual
terms, but each licence decides.

1. **Offline storage.** Versely stores the whole Bible on the phone so it
   works without the internet. Is that allowed? Does the publisher require
   encryption on the device?
2. **Copyright notice.** What exact wording is required? Versely shows it
   under every chapter, on the Bible's card in the library, and in the
   parallel view.
3. **Fees and Premium.** Is there a licence fee? If the licence is free, the
   Bible is free for every reader. If there's a fee, Versely offers the
   Bible to Premium subscribers. Ask whether the publisher allows that, and
   whether the fee is per user, per download or flat.
4. **Where verses appear.** Can its verses appear outside the reader? That
   includes widgets, Apple Watch, notifications, the morning welcome, shared
   verse images and text, PDF exports, the Memorize games and group
   challenges.
5. **AI.** Versely never sends a licensed Bible's text to its AI service. It
   uses a public-domain Bible in the same language instead. Confirm that's
   enough.
6. **Reporting and fees.** Are there usage reports (for example downloads
   per month) or fees?
7. **Term and ending.** How long does the licence last? How quickly must
   copies leave devices when it ends? (Turning the row off removes them the
   next time the app opens online.)
8. **Countries, audio and parallel display.** Is the licence limited to some
   countries? Is audio included? Can the Bible be shown side by side with
   another one?

If a publisher refuses something the app already does (say, widgets), tell
Claude and it'll add a per-Bible switch for it.

## 3. Publishing an approved Bible

1. In the DBL, download the Bible's **text** bundle (the zip with
   `metadata.xml` and USX files).
2. On the Mac, in the project folder, run:

   ```
   python3 Tools/BibleData/import_dbl.py --bundle ~/Downloads/<bundle>.zip --id NIV --year 2011 \
     --summary "Accurate and readable, the most read modern English Bible." \
     --approach balanced --reading-level everyday --popularity 2 \
     --url https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object/licensed-bibles/NIV-1.sqlite.deflate \
     --out build/bibles
   ```

   - `--id` is 2–8 capitals or digits, for example NIV, NLT, RVR1960, NVI
     or NTV.
   - Add `--copyright "…"` if the licence requires wording that differs from
     `metadata.xml`.
   - Add `--premium` **only** if Versely pays a licence fee for this Bible.
     Without it, the Bible is free for everyone.
3. **Read the report.** It shows:
   - the copyright line that will be shown
   - joined verses, such as "16–17" (common in the GNT, CEV and TLA)
   - verse numbers that differ from the KJV
   - anything set aside

   Send it to Claude if anything looks off.
4. In Supabase, open Storage › **licensed-bibles** (private; never the public
   `bibles` bucket) and upload `build/bibles/<ID>-1.sqlite.deflate`.
5. In the SQL Editor, run `build/bibles/<ID>-1.sql`. The Bible then appears
   under Library › Bibles.
6. Ask Claude for any follow-ups:
   - **Original Hebrew and Greek parallel view:** a versification map and an
     `OriginalSource.greek(for:)` line.
   - **What's New:** an announcement.
   - **Other:** anything the licence requires.

**To publish a corrected edition:** run the importer with `--version 2`,
upload the new file, and run the new SQL. Downloaded copies update on Wi‑Fi.

**To withdraw a Bible:**

```
update public.bible_translations set enabled = false where id = 'NIV';
```

New downloads stop at once. Copies on devices are removed the next time the
app loads the catalog.

## 4. What the app already does for licensed Bibles

- **Notices.** The publisher's copyright statement is shown under every
  chapter, in the parallel view and on the Bible's card.
- **Files.** Files are kept in a private bucket. The app gets a ten-minute
  link from the `bible-file` Edge Function, and only while the Bible's row
  is enabled with `rights = 'licensed'`. Downloaded files are left out of
  iCloud backups.
- **Withdrawn Bibles.** These are removed from devices. A reader using one
  moves to another Bible in the same language.
- **Joined verses.** Verses a translation joins ("16–17") show as one verse.
  A reference to verse 17 still finds the words.
- **AI.** The study assistant never receives the Bible's text.
- **Premium Bibles** (`--premium`, for paid licences only):
  - Every Bible picker shows them with a lock.
  - Without Premium, tapping one opens the Premium screen instead of
    downloading or reading.
  - The server gives the download link only to a Premium subscriber.
  - If a subscription ends, the reader moves to a free Bible in the same
    language. The download stays on the device for when they come back.
- **Scripture text.** It is kept verbatim. Footnotes, cross references and
  introductions are left out. Words the publisher marks as the divine name
  are written as LORD, as plain-text editions print them.

## 5. YouVersion Platform (YVP)

A second source of licensed Bibles, besides the DBL. Built in October
2026: the NIV, NASB, NIrV, NVI, NBLA and LBLA are offered (rows in
public.youversion_bibles).

**To add a YouVersion Bible:** check our key can use it (run the
`yvp-catalog` function, see its header), check its publisher's caching
terms, then insert a row in public.youversion_bibles: `id` (what readers
see, 2–8 letters or digits), `yvp_id`, name, year, `license` (the
copyright statement exactly as the Platform's /v1/bibles/{id} gives it),
summary in the Bible's language, language, approach, reading_level,
popularity, sort, `enabled = true`. It appears in the Bibles library the
next time the app loads the catalog. **To withdraw one:** set `enabled =
false`; devices remove it. **To push a publisher's correction:** raise
`version`; devices rebuild it on Wi-Fi (they also do so monthly).

These are the terms YouVersion agreed with us in writing (email thread
"Developer questions before integrating YouVersion Platform – Versely
(7Twenty8 Studio)", Heather McMahan, Director, Platform Partner Strategy,
19–20 October 2026; the owner keeps the PDF).

- **Registration.** The Platform's app form offers only "Non-commercial"
  and asks us to confirm "free of charge in all respects" and "no
  materials behind paywalls". We asked Heather about this, since Versely
  has an optional subscription. On 20 October 2026 she wrote: "Yes, you
  can register. We will be making updates to our website soon and this is
  one of the areas that will get updated. For now, please proceed with
  the sign-up." That written consent rests on the conditions below; keep
  every one of them.
- **Always free.** The app and access to Scripture stay free. A YVP Bible
  is never behind Premium anywhere a person reads it: no `--premium`, no
  lock, whatever the translation costs elsewhere.
- **No YVP text in paid features.** Premium tools must not use a YVP
  Bible's text. Heather named the Memorize games; we apply it to every
  `PremiumFeature` that shows verse text. With a YVP Bible chosen, these
  use the public-domain Bible in the same language (the KJV in English,
  the RV1909 in Spanish, installed along with a Spanish YVP Bible), the
  way the study assistant does (`BibleLibrary.premiumToolsTranslation`):
  - Memorize (games, hints, new cards, the Memorise widget)
  - the Apple Watch's verse of the day (a Premium extra)
  - Widgets are the exception (owner's decision, 28 October 2026): every
    widget but Memorize is free, and every widget, in any look or option
    (backgrounds, keepsakes, the reading theme, categories, From Your
    Reading), shows the Bible being read, YVP included. We asked Heather
    on 19 October about "the memorization practice and some of the extra
    widgets"; she answered that the memorization game must not use YVP
    Bibles and "otherwise, the use case is fine since reading scripture is
    separate from what is requiring subscription". Premium widget looks
    are like Premium themes in the reader, which show YVP text too.
  - the morning welcome's verse
  - word study (`VerseStudyView`) and lexicon entries' verses
  - passages in journal PDF exports
  - the Original (Hebrew & Greek) parallel isn't offered for YVP Bibles
    (no versification map)

  Free features (the reader, search, plans, notes, highlights,
  notifications, sharing, groups) use the YVP Bible as usual.
- **No listening.** Our first email told YouVersion its Bibles aren't read
  aloud by a device voice unless a licence allows it, so the player says
  listening isn't available for them.
- **Tell readers before they choose.** The Bible's card says listening
  isn't available and Premium tools use the public-domain Bible with it, a
  one-time note says so the first time it's read, and What's New
  announces it.
- **Offline is allowed.** A YVP Bible may be stored on the device, whole or
  chapter by chapter, with no YouVersion limit, unless that publisher's own
  agreement sets a caching limit: check each Bible's licence. Refresh from
  the server whenever the device is online, in case the publisher updates
  the text, and remove Bibles that are no longer licensed.
- **Not a competing product.** Versely may offer Bible reading, plans,
  devotional content and other Scripture features. It must not use
  YouVersion's IP to copy or substitute for a YouVersion product or the
  Platform, or use YouVersion's technology, materials or branding beyond
  the required attribution.
- **From the Platform Terms of Use** (the developer agreement):
  - Because Versely charges for a subscription, it must "conspicuously and
    explicitly advise Users that the YouVersion Bible App is provided at no
    cost". No wording is prescribed. Plan: a line on the Premium screen
    and in Settings › About ("The YouVersion Bible App is free to download
    and use."), in plain text with no logo.
  - The app key is confidential: it stays a Supabase secret
    (`YVP_APP_KEY`), used only by an Edge Function, never in the app,
    git or a chat.
  - Keep any usage reporting built into YouVersion's tools switched on.
  - No YouVersion marks or logo, and nothing that suggests endorsement or
    partnership, beyond what a tool's own terms allow.
  - AI: YVP content must not feed open-ended AI chat or AI training. The
    study assistant already reads only a public-domain Bible; keep it so.
  - Either side may end the agreement with 30 days' notice; YouVersion
    may suspend at once. When it ends, YVP Bibles leave the catalog and
    the devices.
  - YouVersion shares our developer details with each publisher whose
    Bible we request, so the publisher can check eligibility.
- **Bibles our app key can use** (checked 20 October 2026 with the
  `yvp-catalog` function; run it again to refresh):
  - English: NIV 2011 (id 111), NIrV 2014 (110), NIV Anglicized (113),
    NASB 2020 (2692), NASB 1995 (100), Amplified (1588), Berean Standard
    Bible (3034), Literal Standard Version (2660), plus public-domain
    texts (ASV, WEB, Geneva, CPDV and others).
  - Spanish: NVI 2025 (128), NVI 2015 (2664), another NVI listed as "Spanish NVI" (1637), La
    Biblia de las Américas (89), Nueva Biblia de las Américas (103),
    Versión Biblia Libre (3291), Reina-Valera Antigua (147).
  - Not on the Platform: RVR1960, DHH, RVC, TLA, ESV, NLT, NTV, CSB. Those
    still go to their publishers directly (section 1).
  - Biblica's own permissions page offers its Bibles through YouVersion
    for apps "with no AI or machine learning features". The study
    assistant is off and never sees licensed text; ask Biblica before
    turning it on while the NIV, NIrV or NVI are offered.
- **Rate limit:** 200 requests an hour (rolling) while in development;
  about 10,000 an hour once the app was marked live in the Platform
  portal (20 October 2026). A whole Bible is about 1,250 requests, so
  that's roughly eight Bible downloads an hour across all readers. Before
  launch, ask for more or for a single server copy (below).
- **What we saw first (20 October 2026):** the Platform limits requests per
  app key, shared by every reader. A burst of about a thousand chapter
  requests at once got HTTP 429 with `Retry-After: 300` (five minutes).
  A whole Bible is about 1,250 requests, so the app builds one two books
  at a time (four chapters each) and tells people to try again in a few
  minutes if the limit is hit. Ask YouVersion for the real limit before
  launch, and whether we may keep one copy of each Bible on our server
  for devices to download (one build per Bible instead of one per
  reader).
- **Caching (Heather McMahan, 23 October 2026):** every API response
  carries a `Cache-Control` header, and caching that follows it per the
  HTTP standard (RFC 7234 › 5.2.2, now RFC 9111) complies; there's no
  separate YVP caching rule. Today every response we've seen (chapters,
  Bible details, book lists) says `public, max-age=3600`, with no ETag or
  Last-Modified, and no must-revalidate. So:
  - our server may keep a chapter for everyone for an hour
    (`public`): `public.yvp_chapter_cache`, used by `yvp-bible`, reads
    the header on every response and never stores one marked private,
    no-store or no-cache; expired rows are deleted hourly (pg_cron
    `yvp-chapter-cache-expire`);
  - a device may show its stored copy while it can't reach the server
    (no must-revalidate); online, a chapter older than its max-age is
    fetched again when it's opened (`BibleLibrary.refreshIfStale`,
    `YouVersionFreshness`) and the stored Bible updated if it changed.
  - Heather (23 October 2026, afternoon): whether a Bible may be stored on
    the device, and for how long, is set by each publisher's agreement,
    not by YouVersion; she pointed us to the publishers' agreements.
  - The hour is YouVersion's choice, not ours: only they can lengthen it.
  - The API has no ranges: one chapter per request (whole books and
    chapter ranges return 404). Pagination applies only to listings
    and search, so it doesn't reduce chapter requests.
- **Publishers' agreements (received 23 October 2026).** Biblica's
  Content License Agreement (NIV, NIrV, NVI) is **confidential**: keep its
  text out of the repository, the website and anything public; only what
  we must do is noted here. Lockman's Free Distribution Permission
  Agreement covers the NASB, NBLA and LBLA (also the AMP and NASB 1995,
  which we don't offer). What they ask, and where the app does it:
  - **Offline:** both allow the text to be downloaded in a mobile app
    (Biblica: downloadable for mobile apps, never as files handed to the
    user; Lockman: live or downloaded to the device). Built and kept on the
    device as before.
  - **Every footnote, accessible (Biblica):** yvp-bible requests
    `include_notes=true` and keeps each note apart from the verse with its
    position (lib.ts `placeMarks`; the verse text is exactly the same as
    without notes, tested); the app stores them in a `footnotes` table and
    shows a small letter marker that opens the note (`FootnoteSheet`).
    Cross references are not footnotes and stay out.
  - **Encryption / no easy copying (Biblica: industry-standard encryption,
    see biblica.com/digital-ip-protection-requirements; Lockman: taking a
    large part out of the app must be difficult or impractical):** each
    YouVersion Bible is built in memory and stored sealed with AES-256-GCM
    under a key made on the device and kept in its Keychain (this device
    only), opened into memory to read, left out of backups
    (`BibleProtection`); unfinished downloads' books are sealed too.
    Bibles built before are sealed in place at launch and rebuilt with
    footnotes on Wi-Fi (`YouVersionBibleBuilder.format` 2). Check the
    Biblica page above for anything more it asks.
  - **A link to the publisher wherever the text is shown:** the copyright
    notice under every chapter opens `publisher_url` (biblica.com, whose
    name is in the notice; lockman.org, Lockman's home page).
  - **Notices:** Biblica's as the Platform's metadata gives them (with the
    ® marks); Lockman's whole-Bible notices word for word from its
    agreement (migration 20261023010000).
  - **Free, no third-party advertising, no AI:** the Bibles are free to
    everyone and never in Premium; Versely has no advertising; licensed
    text never reaches the study assistant (which is off).
  - **Lockman's yearly report:** by the end of each February, the number
    of copies distributed the year before: `public.youversion_download_counts`
    (anonymous, one per finished download, by Bible and year; rebuilds and
    refreshes aren't counted). `select * from public.youversion_download_counts order by year, bible;`
  - **Biblica's display limit:** no more than two chapters (or 25 verses)
    shown to a person at once: the reader shows one chapter (two in the
    parallel view).
  - **Updates and termination:** publisher corrections arrive through the
    chapter refresh; if an agreement ends, turning the row off removes the
    Bible from devices, and Biblica asks for files to be destroyed within
    72 hours with a signed notice.
- **Owner's decision (23 October 2026):** NIV, NIrV and NVI stay offered,
  on the strength of Heather McMahan's written OK for our use (free
  Bibles, never in Premium, never used by AI). Biblica's public
  permissions page (biblica.com/permissions) says its express licence via
  the Platform is for "truly non-commercial" apps without subscriptions or
  AI features, and other uses need written permission; ask Biblica to
  confirm in writing, and keep Heather's email with these records.
- **Questions sent to the publishers (open):**
  - Biblica defines its rights as distribution free of subscriptions:
    confirm in writing that Versely's optional Premium (which never
    includes their Bibles) is acceptable. Lockman's "no general membership
    fees" raises the same question.
  - Both agreements speak of the YouVersion SDK (Biblica also allows the
    API "where applicable"); confirm that our use of the API through our
    server, with its one-hour shared cache, is acceptable.
  - Biblica asks for a prospectus and approval before any "new, revised or
    enhanced" edition: ask what counts, so ordinary updates don't each
    need sign-off.
- **Still to confirm:** quotas and rate limits (not in the Terms; ask
  Platform Support or check the developer docs).
