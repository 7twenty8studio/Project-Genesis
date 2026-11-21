# Church sermons: acceptance checks and pilot (VRS-18, checkpoint 4)

Each acceptance check in the plan is listed here once. For each one, it says
what proves it:

- **Automated**: a test in this repository that runs without the network.
- **By hand**: steps to try on real devices against a test copy of the
  database. Nothing in this file touches production.

Every check must pass before `church_sermons` is turned on for anyone
(CHURCH_SERMONS.md › When the owner approves going live).

## 1. Run every automated check

On the Mac, from a fresh copy of `main`:

    cd ~/Desktop/7Twenty8/Project-Genesis
    git fetch origin
    git checkout main
    git pull origin main
    xcodegen generate
    ./Scripts/build.sh --ui                                   # app unit tests and UI tests
    node --experimental-strip-types --test supabase/functions/*/*.test.ts
    python3 Tools/BibleData/export_reference_books.py --check
    supabase/tests/church_sermons/run.sh                      # needs: brew install postgresql@17
    supabase/tests/church_sermons/real_storage/run.sh         # needs Docker running
    cd web && npm install && npm test && npm run lint && npm run build && cd ..

The browser checks need the web Bibles and Playwright:

    python3 Tools/BibleData/export_web_chapters.py --rv1909 <RV1909.sqlite or spa-rv1909.usfx.xml> --out web/build/web-bibles
    cd web && npm install --no-save playwright && npx playwright install chromium && ./e2e/run.sh && cd ..

The browser checks rebuild `.next` pointed at a stand-in server. Run
`npm run build` again before using that build for anything else.

## 2. Check by check

| # | Check | Automated | By hand |
| --- | --- | --- | --- |
| 1 | A bilingual DOCX and a Portuguese text PDF import with every word kept, ambiguous references flagged, no auto-publish; a scanned PDF asks for the text or the editable file | web/src/lib/import/docx.test.ts ("a bilingual Word sermon…"), pdf.test.ts ("a Portuguese text PDF…", "a scanned PDF…"), lines.test.ts (review list), e2e (Publish waits for the review) | Import three real documents from the pilot church (step 3) |
| 2 | Speaker notes and comments in a DOCX are left out, and the review says so | docx.test.ts ("hidden text, footnotes and comments are reported…") | — |
| 3 | A guest scans the QR code and reads the outline on the web with no account; the same link opens the app when it's installed | e2e (the guest page with no session) | Step 4 |
| 4 | A members-only link shows a non-member no title, text or block, through the page, the function and any cache | tests.sql ("guest: members only"), e2e (no title in the page, `private, no-cache, no-store`), ChurchSermonTests (in-memory rules), ChurchSermonsUITests (the link says only "For church members") | Step 5 |
| 5 | "Juan 3:16" in a Spanish outline opens John 3:16 in an English Bible, and Back returns to the same place. The same for Portuguese, a hand-linked reference, an ambiguous one, an invalid one, a Bible without the passage, and the Reina-Valera's different numbering | fixtures/references.json (references.test.ts and the Swift tests), scripture.test.ts (Numbers 12:16 → RV 13:1), ChurchSermonTests (RV1909 Acts 19:41 → 19:40), ChurchSermonsUITests (the passage sheet closes back onto the outline) | Step 6 |
| 6 | A member's note from a sermon reopens after the church edits the outline, still opens after an unpublish, and no other member or leader can read it | ChurchSermonTests (notes keep details and passages, never the outline), sermons RLS (own rows only) | Step 7 |
| 7 | Two leaders publishing at once produce one revision; a retried publish changes nothing | run.sh "two sessions" step, tests.sql ("retried publish returns the same revision") | — |
| 8 | A moderator removed from the group can no longer edit or publish; another church's leaders can't see its drafts | tests.sql ("removed leader cannot edit", "no longer reads drafts", other_pastor checks) | — |
| 9 | Report and block work on a published sermon in the app (guideline 1.2), and a report reaches the moderators and the ops dashboard | tests.sql (Reports), ops.test.ts ("church sermon reports group per sermon…"), ChurchSermonTests (three reports hide it) | Step 8 |
| 10 | Large text, VoiceOver, keyboard and zoom on the web, dark mode, a small iPhone and iPad all work | e2e: axe (WCAG 2.1 AA) in English, Spanish and Portuguese, light and dark, 320 px, 200% text, the keyboard tab order and focus rings | Step 9 |
| 11 | Every new string exists in English, Spanish and Portuguese | build_catalogs.py, web i18n.test.ts | — |
| 12 | An NIV or unknown-translation quotation publishes as a reference only, even when the function is called directly; a KJV or RV1909 quotation publishes as written | tests.sql (Quotation rule), studio.test.ts, e2e (the NIV words never reach the guest page) | — |
| 13 | With the global switch or the church's switch off, the server refuses every read and write | tests.sql (Switches), ChurchSermonScreen's "not available yet" | — |
| 14 | A banned member signed in on the web sees "members only" and nothing else; members-only responses carry private, no-store | tests.sql (banned), real_storage/check.mjs, e2e (headers) | — |
| 15 | An unpublished link sermon is gone on the very next request | tests.sql ("unpublish stops the link at once"), e2e (404 on the next page load) | — |
| 16 | Storage refuses a cover over 1 MB or not JPEG; a replaced or removed cover's file is gone; a photo's location never reaches storage | tests.sql ("bucket is private, JPEG only, 1 MB", the cover sweep), real_storage/run.sh, studio.test.ts (re-encoded ≤ 2000 px; a re-encoded canvas carries no EXIF) | Step 10 |
| 17 | Repeated opens from one visitor count once a day, and a burst stops at the per-sermon cap | tests.sql (Counts: "same visitor again today not counted", "at most 60 counted a minute") | — |
| 18 | Church search finds a listed church by name in all three languages and never shows an unlisted one; Previous and Next follow the series; Copy copies the section exactly | tests.sql (Church search, including Spanish and Portuguese names with or without accents), outline.test.ts (Copy), ChurchSermonsUITests (search, Next) | — |
| 19 | (pilot question) The real mix of documents: how often PDFs are scans | — | Step 3 |
| 20 | (pilot question) Whether rebuilding sermons by hand is really why churches don't publish today | — | Step 11 |
| 21 | Universal Links: `/.well-known/apple-app-site-association` names 4XTR53RY2V.com.7twenty8studio.versely for /s/* | web/src/config.ts default, ChurchSermonTests (links) | Step 4 |

## 3–11. By hand, on a test copy of the database

You need a test copy of the database with both church sermon migrations
run and the switches on. Production stays untouched and its switch stays
off. The test copy can be a Supabase branch, or a second project. You need:

- An iPhone (a small one if you have it) and an iPad, each with a TestFlight
  or Xcode build whose `Config/Secrets.xcconfig` points at the test copy.
- The web app on a Vercel preview, with `NEXT_PUBLIC_VERSELY_SUPABASE_URL`
  and `NEXT_PUBLIC_VERSELY_SUPABASE_ANON_KEY` set to the test copy.
- Four accounts: **Pastor** (owner of the pilot church group), **Moderator**,
  **Member**, and **Visitor** (no group). Also a second church with its own
  **Other Pastor**.

On the test copy, in the SQL editor:

    update public.feature_flags set enabled = true where key = 'church_sermons';
    update public.groups set sermons_enabled = true where id = '<pilot church group id>';

3. **Real documents.** As Pastor, import the church's last three sermons in
   Church Studio, in whatever form they exist (Word, PDF, Pages exported as
   PDF, pasted text). Note each one's type. Check the review list against
   the source. Publish only after every item is answered. Write down any
   word the comparison missed.
4. **QR code and Universal Links.** Open Share and scan the QR code with
   the Visitor's phone, first without Versely installed (the web page opens
   with no sign-in), then with it installed (Versely opens on the sermon).
   Also tap the link in Messages and in Mail.
5. **Members only.** Switch one sermon to Members only. Open its link as
   Visitor on the phone, in Safari signed out, and in Safari signed in as
   Visitor: each shows only "for church members".
6. **References.** Publish an outline in Spanish with "Juan 3:16" and in
   Portuguese with "João 3:16", one reference you link by hand in the
   review, one ambiguous one ("Juan 3:99", which the review flags), one
   that isn't a reference at all ("gracia y paz") and Hechos 19:41. On the
   phone in the KJV, then in the Reina-Valera: each opens the right verse
   (Acts 19:41 is the Reina-Valera's 19:40), the others stay as typed, and
   Done returns to the same place in the outline.
7. **Private notes.** As Member, tap Take Notes on a sermon and type a
   line. As Pastor, edit the outline and publish again, then unpublish it.
   As Member, open the notes from Sermon Notes: still there. As Moderator
   and as another member, check the notes are nowhere to be seen.
8. **Report and hide.** As Member, report a sermon from its menu. As
   Pastor, see it in Church Studio's reports. As the owner, see it on the
   ops dashboard at /admin. As Member, choose Hide Sermons from the church:
   they disappear from the group page, and a link to one offers Show Again.
9. **Accessibility on devices.** On the iPhone and the iPad: VoiceOver
   reads the outline in order, the cover's description is read (or nothing,
   if it's marked decorative), and passages are buttons. Larger Text at the
   largest size, dark mode and the Night theme all work. On the web, try
   Safari zoom at 200% and the keyboard alone.
10. **Covers.** Upload a phone photo with location turned on. Download the
    published cover from the guest page and check it has no location (Mac
    Preview › Tools › Show Inspector › GPS shows nothing). Replace the
    cover, then confirm the old cover's address no longer loads.
11. **Pilot question.** Ask the pilot church how they share sermon notes
    today and why they don't put them online. Write down the answer.

When every row passes, write the date and anything that failed into
CHURCH_SERMONS.md, then ask for the go-ahead to run the production
migration, deploy the web app and the two functions, and build 1.0.5 for
TestFlight.
