# Church sermons (VRS-18)

Churches publish a sermon outline; members and guests follow along with one
link (`https://versely.7twenty8studio.com/s/<slug>`) on the web or in the app,
read each passage in their own Bible and keep private notes. Free for
everyone. Planned for Versely 1.0.5, behind the `church_sermons` switch.

Built in four checkpoints, each a pull request the owner reviews and merges
before the next one starts:

1. **Foundation and security** (PR #37, merged): database, access rules,
   the quotation rule, covers, reports, counts, the shared reference parser.
2. **Church Studio and the guest page** (PR #42, merged; `web/`,
   versely.7twenty8studio.com; web/README.md).
3. **The iPhone and iPad app**: links, sermons in church groups, Find a
   Church, the outline with passages and private notes (CLAUDE.md ›
   Church sermons).
4. **Pilot and release checks**: CHURCH_SERMONS_PILOT.md (every
   acceptance check, the test that covers it or the steps to try by hand).

Nothing here is applied to the production database, deployed or sent to
TestFlight without the owner's go-ahead for each.

## Rules the database enforces

- **A church is a group** with `groups.sermons_enabled`. While the
  `church_self_serve` switch is on (owner, 21 November 2026, for the proof
  of concept; migration 20261122000000), anyone signed in to Church Studio
  starts a church (`create_sermon_church`: a group they own, sermons on,
  unlisted, at most three a day) or turns sermons on for a group they own
  (`my_groups_for_sermons`, `set_church_sermons`, owner only). Off, only
  the dashboard sets it. Its owner and moderators (role
  `leader`) write; members read members-only sermons; anyone with the link
  reads link sermons. Banned and removed people lose access at once.
- **Every request is checked** against both switches (`church_sermons` and
  the church's own), the group switch, membership, bans and roles, inside
  security definer functions. Nobody writes the tables directly; leaders may
  select their own church's rows (Studio).
- **Draft and published copy are separate.** Saving changes only the draft
  (details, outline, cover, audience). Publishing copies all of it into an
  immutable revision in one transaction, and readers get only that. Opening
  a sermon to more people takes a publish; closing it takes effect at once
  through its own action: `restrict_church_sermon` (members only now),
  unpublish, delete, or a moderator taking it down.
- **Versions.** Saves and publishes carry the draft version the editor
  loaded: a stale one is refused (`draft_changed`), never overwritten. A
  publish retried while the sermon is still published returns the same
  revision and changes nothing; unpublish, restrict and delete move the
  version on, so a delayed retry can never open the sermon again.
- **Nothing is cut silently**: a block or detail that's missing a required
  field, has the wrong type, an unknown field or too much text is refused
  with the reason (`invalid_blocks`, `invalid_details`), and the draft stays
  as it was.
- **Quotations**: a scripture block holds the reference the pastor typed and
  verse ids (KJV numbering, both ends whole numbers, never rounded), checked against every chapter's real verse
  count (`bible_verse_counts`). Words the pastor typed stay in the draft
  only; readers never get them. A quotation labelled KJV, WEB, ASV,
  Reina-Valera 1909 or Bíblia Livre is published as that translation's code
  (`genesis_quote_translation`), and the app and web show the passage from
  their own verbatim copy; any other or missing label is a reference only
  (`quote_withheld`). A licensed translation needs its publisher's written
  grant, recorded by the owner, before it's added.
- **Members-only** sermons answer `{"status": "members_only"}` with nothing
  else to anyone who isn't a member. The web must send these with
  `Cache-Control: private, no-store` and never cache them publicly
  (checkpoint 2).
- **Unpublish, delete, hide** take effect on the next request.
- **Reports**: any signed-in reader reports once; three people hide the
  sermon until a moderator reviews it (reports on one sermon are counted one
  at a time, so simultaneous ones can't miss the threshold) (`group_sermon_reports`,
  `review_church_sermon_reports`); reports never say who reported. They also
  reach the operations dashboard.
- **Counts** (opens, passages opened, notes saved) are aggregate, written only
  by the `sermon-events` function, and only for sermons a guest can open
  (published, shown, open to the link): one per visitor per day under a key
  that changes daily, at most 60 a minute per sermon, link previews ignored.
- **Covers**: JPEG (≤ 1 MB) in the private `sermon-covers` bucket at
  `<group id>/<sermon id>/<cover id>.jpg`, a new id per picture
  (`new_church_sermon_cover`), so the published picture never changes under
  readers and a draft's picture is never seen before publishing. Leaders of
  that church upload; nobody deletes a file directly (removing a cover is
  saving `cover: null`). Studio re-encodes on the device (no metadata) and
  asks for alt text (or "decorative") before publishing. Readers get covers
  only through a request that rechecks access each time (checkpoint 2),
  never a signed URL that could outlive an unpublish. The nightly sweep
  (service role) calls `retire_orphan_sermon_covers()`, which rechecks each
  file older than a day under its sermon's row lock (the lock save and
  publish take), records the ones neither copy uses in
  `church_sermon_retired_covers` and returns them for deletion through the
  Storage API. Save and publish refuse a retired cover and a retired name
  can't be uploaded again, so a file is never both deleted and in use
  (two-session checks in run.sh).
- **Account deletion**: a volunteer's sermons stay with the church;
  `created_by` / `published_by` become null.

## Pieces

| Piece | Where |
| --- | --- |
| Migration | supabase/migrations/20261120000000_church_sermons.sql |
| Web additions: cover access, import review with the draft, Studio's church list | supabase/migrations/20261121000000_church_sermon_web.sql |
| Covers (the only way out of the bucket) | supabase/functions/sermon-cover |
| Church Studio and the guest page | web/ (Next.js; web/README.md) |
| Passages for the web (free Bibles, verse for verse) | Tools/BibleData/export_web_chapters.py |
| Access tests (local Postgres, no network) | supabase/tests/church_sermons/run.sh |
| Cover revocation on the real Storage API and Edge Runtime (Docker, local) | supabase/tests/church_sermons/real_storage/run.sh |
| Reference parser for the web (same reading as the app) | supabase/functions/_shared/references.ts, fixtures/references.json |
| Book names and verse counts | bibleBooks.json, from Tools/BibleData/export_reference_books.py |
| Counts | supabase/functions/sermon-events |
| Ops dashboard | church sermon reports in _shared/ops.ts / opsCollect.ts |

Tests:

    supabase/tests/church_sermons/run.sh       # Linux: PGBIN=/usr/lib/postgresql/16/bin
    supabase/tests/church_sermons/real_storage/run.sh   # needs Docker
    node --experimental-strip-types --test supabase/functions/*/*.test.ts
    python3 Tools/BibleData/export_reference_books.py --check
    cd web && npm test && npm run lint && npm run build
    cd web && ./e2e/run.sh                # browser checks: accessibility, members only, unpublish, Studio saving (stand-in server)
    ./Scripts/build.sh                     # app unit tests: GenesisTests/ChurchSermonTests.swift
    ./Scripts/build.sh --ui                # GenesisUITests/ChurchSermonsUITests.swift (in-memory server)
    python3 Tools/BibleData/export_web_chapters.py --rv1909 <RV1909.sqlite or spa-rv1909.usfx.xml> --out build/web-bibles --check

## The web (checkpoint 2)

- **Guest page** `/s/<slug>`: rendered for every request from
  `published_sermon`, never cached (no data cache, `force-dynamic`,
  `no-store`), so unpublishing, members only, a ban, a hidden sermon or the
  switch turned off applies to the very next request. Members-only sermons
  show nothing but a sign-in. Never indexed.
- **Covers** `/s/<slug>/cover`: checks `published_sermon` as the visitor,
  then asks the `sermon-cover` function with the visitor's own session.
  No client can read the sermon-covers bucket (no SELECT policy at all, so
  nobody can create a signed link that would outlive an unpublish or a
  ban); the function asks `sermon_cover_access` as the caller on every
  request and only then reads the file with the service role. `private,
  no-store`. Studio's draft covers (`/studio/<id>/cover`) go the same way
  ('edit' access: the church's leaders). Leaders upload with the INSERT
  policy alone. Checked against the real Storage API and Edge Runtime by
  real_storage/run.sh.
- **Passages** come from `bibles/web/v1/<CODE>/<book>-<chapter>.json`
  (KJV, ASV, WEB, RV1909, Bíblia Livre only), keyed by KJV chapter with
  each verse's own numbering, written by export_web_chapters.py from the
  app's own databases and alignment tables. Quoted words in an outline are
  never published (only the translation code for these five).
- **Unpublish and Members only** never wait on a draft save. They return
  the version they moved on from (`previous_version`); the editor takes the
  new version and saves a pending edit only when that was its own version,
  otherwise it stays in conflict and asks for a reload.
- **Church Studio** `/studio`: sign in with Apple or Google (Supabase PKCE,
  httpOnly cookie, refreshed by `proxy.ts`); the churches from
  `my_sermon_churches`; every write is a Server Action calling the
  database as the person, against the draft version they loaded.
- **Import** runs in the browser (the file is never uploaded): paste
  (Markdown-ish), Word .docx (Mammoth; hidden text taken out first) and
  text PDFs (pdf.js; a scan is refused with "paste the text or send the
  editable file"). Every import is compared with its source word for word
  (`import/completeness.ts`); words not carried over, tables, pictures,
  footnotes, hidden text, comments, unclear references and anything that
  may quote Scripture without being a Scripture item go on a review list,
  and Publish stays off until each is kept, fixed or left out. The review
  is saved with the draft (`church_sermons.draft_review`, any computer,
  any leader) and `publish_church_sermon` refuses `review_open` while an
  item is open. A duplicate keeps the review with its answers; an import
  added to the end keeps every earlier item beside the new ones. Word files are read as XML: hidden text (`w:vanish`
  however it's written, from the run, its character or paragraph style,
  the styles they're based on, or the document default) is never imported.
  A quotation with its reference goes through the Scripture rules in a
  paragraph, a quote, a list item or a heading ("John 3:16 (NIV) …",
  "“…” — John 3:16 NIV"), so a licensed translation's words are never
  published.
- **Covers** are re-encoded in the browser (≤ 2000 px, ≤ 1 MB JPEG, no
  metadata) and checked again on the server.
- Screens in English, Spanish (tú) and Brazilian Portuguese (você):
  `web/src/lib/messages.ts`, checked by `i18n.test.ts`.

## Production status (owner, 21 November 2026)

- Done: both migrations (20261120000000, 20261121000000), the
  `sermon-events` and `sermon-cover` functions, `SERMON_EVENTS_SECRET`,
  and Associated Domains on the App ID. The `church_sermons` switch is off
  and no church has `sermons_enabled`.
- Versely 1.0.5 goes to TestFlight with the switch off: smoke tests only
  (the feature stays hidden, everything else works).
- Still pending: the web app on Vercel (sign-in callback URL, the web
  Bible files), and the hosted pilot checks (CHURCH_SERMONS_PILOT.md),
  including cover revocation and counting. With no extra cost, the
  pilot's end-to-end checks run locally (web/e2e, the simulator with the
  in-memory server) until a hosted test copy is approved.

- Later on 21 November 2026 (owner: "please enable everything"): the web
  app is live on Vercel at versely.7twenty8studio.com, the 5,945 web Bible
  files are in the `bibles` bucket (web/v1), Google sign-in on the web
  works, and the `church_sermons` switch is on. Sign in with Apple on the
  web waits for a Services ID; its button shows only with
  `NEXT_PUBLIC_VERSELY_APPLE_WEB=on`. Self-serve churches (migration
  20261122000000, run in production the same day): a pastor signs in,
  names the church and lands in its first draft. Church Studio has the
  Versely Cream, Daylight and Warm Dark looks and its own language menu.

- 22 November 2026 (owner, from a recording of YouVersion's events): the
  start screen says "church or ministry", so a ministry or someone who
  speaks on their own fits too. Locations and Times (migration
  20261124000000, not yet run in production): each church's places and
  service times on every sermon page, with directions, and a "Join us"
  invitation at the end.

## When the owner approves going live

1. Run both migrations (20261120000000, then 20261121000000) in the SQL
   Editor (they leave the switch off).
2. `supabase functions deploy sermon-events --no-verify-jwt`, with the
   secret `SERMON_EVENTS_SECRET` (32+ random characters), and
   `supabase functions deploy sermon-cover --no-verify-jwt` (no secrets of
   its own; it checks every token through `sermon_cover_access`).
3. Turn on `groups.sermons_enabled` for each pilot church, then the
   `church_sermons` switch, only after the acceptance checklist passes.
4. Upload the web passages: `export_web_chapters.py … --out build/web-bibles`
   (then `--check`), and copy `build/web-bibles/web/v1` to the public
   `bibles` bucket as `web/v1`.
5. Sign-in for the web: in Supabase › Authentication › URL Configuration,
   add `https://versely.7twenty8studio.com/auth/callback` to the redirect
   URLs. Sign in with Apple on the web needs a Services ID with that
   domain and Supabase's callback as its return URL (APPLE_SETUP.md);
   Google needs nothing new.
6. Vercel: a project with root directory `web/` and the domain
   versely.7twenty8studio.com. The Universal Links file uses Team ID
   4XTR53RY2V by default (`VERSELY_APPLE_TEAM_ID` overrides it).
   `NEXT_PUBLIC_VERSELY_APP_STORE_ID` once Versely is listed.
7. Apple: Associated Domains is on for com.7twenty8studio.versely (owner,
   21 November 2026); regenerate provisioning profiles for the build that
   ships it (Xcode's automatic signing does).
