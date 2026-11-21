# Church sermons (VRS-18)

Churches publish a sermon outline; members and guests follow along with one
link (`https://versely.7twenty8studio.com/s/<slug>`) on the web or in the app,
read each passage in their own Bible and keep private notes. Free for
everyone. Planned for Versely 1.0.4, behind the `church_sermons` switch.

Built in four checkpoints, each a pull request the owner reviews and merges
before the next one starts:

1. **Foundation and security** (this one): database, access rules, the
   quotation rule, covers, reports, counts, the shared reference parser.
2. Church Studio and the guest page (`web/`, versely.7twenty8studio.com).
3. The iPhone and iPad app.
4. Pilot and release checks.

Nothing here is applied to the production database, deployed or sent to
TestFlight without the owner's go-ahead for each.

## Rules the database enforces

- **A church is a group** with `groups.sermons_enabled` (set by the owner in
  the dashboard for pilot churches). Its owner and moderators (role
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
| Access tests (local Postgres, no network) | supabase/tests/church_sermons/run.sh |
| Reference parser for the web (same reading as the app) | supabase/functions/_shared/references.ts, fixtures/references.json |
| Book names and verse counts | bibleBooks.json, from Tools/BibleData/export_reference_books.py |
| Counts | supabase/functions/sermon-events |
| Ops dashboard | church sermon reports in _shared/ops.ts / opsCollect.ts |

Tests:

    supabase/tests/church_sermons/run.sh       # Linux: PGBIN=/usr/lib/postgresql/16/bin
    node --experimental-strip-types --test supabase/functions/*/*.test.ts
    python3 Tools/BibleData/export_reference_books.py --check

## When the owner approves going live (not yet)

1. Run the migration in the SQL Editor (it leaves the switch off).
2. `supabase functions deploy sermon-events --no-verify-jwt`, with the
   secret `SERMON_EVENTS_SECRET` (32+ random characters).
3. Turn on `groups.sermons_enabled` for each pilot church, then the
   `church_sermons` switch, only after the acceptance checklist passes.
