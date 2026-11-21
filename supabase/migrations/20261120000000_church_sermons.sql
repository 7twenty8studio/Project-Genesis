-- Versely: church sermons (VRS-18, Versely 1.0.4). Free for everyone.
--
-- A church publishes a sermon outline; members and guests follow along with
-- one link (https://versely.7twenty8studio.com/s/<slug>) on the web or in
-- the app, read each passage in their own Bible and keep private notes.
-- Rules and checkpoints: CHURCH_SERMONS.md.
--
-- Run once in the Supabase dashboard (SQL Editor -> New query -> paste ->
-- Run), after 20261117000000. Safe to re-run: it only creates what is
-- missing and never drops or deletes anything. Nothing is visible until both
-- switches are on: feature_flags 'church_sermons' (created off here) and the
-- church's own groups.sermons_enabled (set by the owner, pilot churches only).
--
-- Design
--   * A church is a group. Its owner and moderators (role 'leader') write;
--     its members read members-only sermons; anyone with the link reads link
--     sermons. Banned people are no longer members (group_bans).
--   * Every read and write goes through security definer functions that check
--     both switches, membership and roles on every call. Leaders may also
--     select their church's rows directly (Church Studio); nobody else can
--     select the tables, and nobody writes them directly.
--   * Draft and published copy are separate. Saving changes only the draft
--     (details, outline, cover, audience). Readers see only what was
--     published: a revision holds the outline, the details, the cover and
--     the audience as they were at publish. Opening a sermon to more people
--     takes a publish; closing it (members only, unpublish, delete) takes
--     effect at once through its own action.
--   * Saves and publishes carry the draft_version the editor loaded; a stale
--     one is refused ('draft_changed'). Unpublish, restrict and delete bump
--     the version too, so a delayed publish retry can never undo them; a
--     publish retried while the sermon is still published returns the same
--     revision and changes nothing.
--   * Scripture: a block holds the reference the pastor typed and verse ids
--     (KJV numbering) checked against the KJV's chapter and verse counts
--     (bible_verse_counts). Quoted words stay in the draft for the church,
--     but readers never get them: a quotation from KJV, WEB, ASV,
--     Reina-Valera 1909 or Biblia Livre is published as that translation's
--     code, and the app and web show the passage from their own verbatim
--     copy; any other or unknown label is published as a reference only
--     (owner, 20 Nov 2026). Malformed blocks are refused, never trimmed.
--   * Covers: JPEG (<= 1 MB) in the private sermon-covers bucket at
--     <group id>/<sermon id>/<cover id>.jpg, a new id per picture so the
--     published one never changes under readers. Served only through a
--     request that rechecks access (checkpoint 2), never a public link.
--     Nobody deletes a cover directly: removing one is saving cover: null,
--     and only the nightly sweep (retire_orphan_sermon_covers) frees files,
--     under the sermon's row lock, so it and a save or publish never both win.
--   * Reports: any signed-in reader can report a published sermon; it reaches
--     the church's moderators (and the ops dashboard). Three reports from
--     different people hide it until a moderator reviews it.
--   * Counts: aggregate only, written by the sermon-events Edge Function
--     (service role) with a daily-salted visitor hash, one per visitor per
--     day, at most 60 a minute per sermon, and only for sermons a guest can
--     open. No address, user id or text.
--   * A volunteer who deletes their account: created_by / published_by become
--     null; the church's sermons stay. They go when the group is deleted.

-- Switch -------------------------------------------------------------------------

insert into public.feature_flags (key, enabled, description)
values ('church_sermons', false, 'Church sermons (VRS-18): churches publish sermon outlines with a link and QR code. Also needs groups.sermons_enabled per church.')
on conflict (key) do nothing;

-- Per-church settings ----------------------------------------------------------------

-- Set by the owner (dashboard) for pilot churches; no function changes it.
alter table public.groups add column if not exists sermons_enabled boolean not null default false;
-- Shown in church search (Together) when the church chooses to be listed.
alter table public.groups add column if not exists sermons_listed boolean not null default false;

-- Verse counts (KJV numbering) ------------------------------------------------------------

-- How many verses each chapter has, so a verse id is checked against the
-- Bible, not a range. Numbers only. Generated from the bundled KJV by
-- Tools/BibleData/export_reference_books.py (references.test.ts checks this
-- list matches).
create table if not exists public.bible_verse_counts (
  book smallint not null check (book between 1 and 66),
  chapter smallint not null check (chapter >= 1),
  verses smallint not null check (verses >= 1),
  primary key (book, chapter)
);

alter table public.bible_verse_counts enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bible_verse_counts' and policyname = 'Anyone reads') then
    create policy "Anyone reads" on public.bible_verse_counts for select to anon, authenticated using (true);
  end if;
end;
$$;

insert into public.bible_verse_counts (book, chapter, verses)
select b.book, c.chapter, c.verses
from (values
  (1, array[31,25,24,26,32,22,24,22,29,32,32,20,18,24,21,16,27,33,38,18,34,24,20,67,34,35,46,22,35,43,55,32,20,31,29,43,36,30,23,23,57,38,34,34,28,34,31,22,33,26]),
  (2, array[22,25,22,31,23,30,25,32,35,29,10,51,22,31,27,36,16,27,25,26,36,31,33,18,40,37,21,43,46,38,18,35,23,35,35,38,29,31,43,38]),
  (3, array[17,16,17,35,19,30,38,36,24,20,47,8,59,57,33,34,16,30,37,27,24,33,44,23,55,46,34]),
  (4, array[54,34,51,49,31,27,89,26,23,36,35,16,33,45,41,50,13,32,22,29,35,41,30,25,18,65,23,31,40,16,54,42,56,29,34,13]),
  (5, array[46,37,29,49,33,25,26,20,29,22,32,32,18,29,23,22,20,22,21,20,23,30,25,22,19,19,26,68,29,20,30,52,29,12]),
  (6, array[18,24,17,24,15,27,26,35,27,43,23,24,33,15,63,10,18,28,51,9,45,34,16,33]),
  (7, array[36,23,31,24,31,40,25,35,57,18,40,15,25,20,20,31,13,31,30,48,25]),
  (8, array[22,23,18,22]),
  (9, array[28,36,21,22,12,21,17,22,27,27,15,25,23,52,35,23,58,30,24,42,15,23,29,22,44,25,12,25,11,31,13]),
  (10, array[27,32,39,12,25,23,29,18,13,19,27,31,39,33,37,23,29,33,43,26,22,51,39,25]),
  (11, array[53,46,28,34,18,38,51,66,28,29,43,33,34,31,34,34,24,46,21,43,29,53]),
  (12, array[18,25,27,44,27,33,20,29,37,36,21,21,25,29,38,20,41,37,37,21,26,20,37,20,30]),
  (13, array[54,55,24,43,26,81,40,40,44,14,47,40,14,17,29,43,27,17,19,8,30,19,32,31,31,32,34,21,30]),
  (14, array[17,18,17,22,14,42,22,18,31,19,23,16,22,15,19,14,19,34,11,37,20,12,21,27,28,23,9,27,36,27,21,33,25,33,27,23]),
  (15, array[11,70,13,24,17,22,28,36,15,44]),
  (16, array[11,20,32,23,19,19,73,18,38,39,36,47,31]),
  (17, array[22,23,15,17,14,14,10,17,32,3]),
  (18, array[22,13,26,21,27,30,21,22,35,22,20,25,28,22,35,22,16,21,29,29,34,30,17,25,6,14,23,28,25,31,40,22,33,37,16,33,24,41,30,24,34,17]),
  (19, array[6,12,8,8,12,10,17,9,20,18,7,8,6,7,5,11,15,50,14,9,13,31,6,10,22,12,14,9,11,12,24,11,22,22,28,12,40,22,13,17,13,11,5,26,17,11,9,14,20,23,19,9,6,7,23,13,11,11,17,12,8,12,11,10,13,20,7,35,36,5,24,20,28,23,10,12,20,72,13,19,16,8,18,12,13,17,7,18,52,17,16,15,5,23,11,13,12,9,9,5,8,28,22,35,45,48,43,13,31,7,10,10,9,8,18,19,2,29,176,7,8,9,4,8,5,6,5,6,8,8,3,18,3,3,21,26,9,8,24,13,10,7,12,15,21,10,20,14,9,6]),
  (20, array[33,22,35,27,23,35,27,36,18,32,31,28,25,35,33,33,28,24,29,30,31,29,35,34,28,28,27,28,27,33,31]),
  (21, array[18,26,22,16,20,12,29,17,18,20,10,14]),
  (22, array[17,17,11,16,16,13,13,14]),
  (23, array[31,22,26,6,30,13,25,22,21,34,16,6,22,32,9,14,14,7,25,6,17,25,18,23,12,21,13,29,24,33,9,20,24,17,10,22,38,22,8,31,29,25,28,28,25,13,15,22,26,11,23,15,12,17,13,12,21,14,21,22,11,12,19,12,25,24]),
  (24, array[19,37,25,31,31,30,34,22,26,25,23,17,27,22,21,21,27,23,15,18,14,30,40,10,38,24,22,17,32,24,40,44,26,22,19,32,21,28,18,16,18,22,13,30,5,28,7,47,39,46,64,34]),
  (25, array[22,22,66,22,22]),
  (26, array[28,10,27,17,17,14,27,18,11,22,25,28,23,23,8,63,24,32,14,49,32,31,49,27,17,21,36,26,21,26,18,32,33,31,15,38,28,23,29,49,26,20,27,31,25,24,23,35]),
  (27, array[21,49,30,37,31,28,28,27,27,21,45,13]),
  (28, array[11,23,5,19,15,11,16,14,17,15,12,14,16,9]),
  (29, array[20,32,21]),
  (30, array[15,16,15,13,27,14,17,14,15]),
  (31, array[21]),
  (32, array[17,10,10,11]),
  (33, array[16,13,12,13,15,16,20]),
  (34, array[15,13,19]),
  (35, array[17,20,19]),
  (36, array[18,15,20]),
  (37, array[15,23]),
  (38, array[21,13,10,14,11,15,14,23,17,12,17,14,9,21]),
  (39, array[14,17,18,6]),
  (40, array[25,23,17,25,48,34,29,34,38,42,30,50,58,36,39,28,27,35,30,34,46,46,39,51,46,75,66,20]),
  (41, array[45,28,35,41,43,56,37,38,50,52,33,44,37,72,47,20]),
  (42, array[80,52,38,44,39,49,50,56,62,42,54,59,35,35,32,31,37,43,48,47,38,71,56,53]),
  (43, array[51,25,36,54,47,71,53,59,41,42,57,50,38,31,27,33,26,40,42,31,25]),
  (44, array[26,47,26,37,42,15,60,40,43,48,30,25,52,28,41,40,34,28,41,38,40,30,35,27,27,32,44,31]),
  (45, array[32,29,31,25,21,23,25,39,33,21,36,21,14,23,33,27]),
  (46, array[31,16,23,21,13,20,40,13,27,33,34,31,13,40,58,24]),
  (47, array[24,17,18,18,21,18,16,24,15,18,33,21,14]),
  (48, array[24,21,29,31,26,18]),
  (49, array[23,22,21,32,33,24]),
  (50, array[30,30,21,23]),
  (51, array[29,23,25,18]),
  (52, array[10,20,13,18,28]),
  (53, array[12,17,18]),
  (54, array[20,15,16,16,25,21]),
  (55, array[18,26,17,22]),
  (56, array[16,15,15]),
  (57, array[25]),
  (58, array[14,18,19,16,14,20,28,13,28,39,40,29,25]),
  (59, array[27,26,18,17,20]),
  (60, array[25,25,22,19,14]),
  (61, array[21,22,18]),
  (62, array[10,29,24,21,21]),
  (63, array[13]),
  (64, array[14]),
  (65, array[25]),
  (66, array[20,29,22,11,14,17,17,13,21,11,19,17,18,20,8,21,18,24,21,15,27,21])
) as b (book, counts)
cross join lateral unnest(b.counts) with ordinality as c (verses, chapter)
on conflict (book, chapter) do nothing;

-- Tables -------------------------------------------------------------------------

-- The draft (what the Studio edits) and the live state (what readers get).
create table if not exists public.church_sermons (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9]{10}$'),
  -- Draft details.
  title text not null default '' check (char_length(title) <= 200),
  speaker text not null default '' check (char_length(speaker) <= 120),
  series text check (series is null or char_length(series) between 1 and 120),
  preached_on date,
  time_zone text check (time_zone is null or char_length(time_zone) <= 64),
  location text not null default '' check (char_length(location) <= 200),
  language text not null default 'en' check (language in ('en', 'es', 'pt', 'other')),
  audience text not null default 'link' check (audience in ('link', 'members')),
  cover_id uuid,
  cover_alt text not null default '' check (char_length(cover_alt) <= 300),
  cover_decorative boolean not null default false,
  draft_blocks jsonb not null default '[]'::jsonb check (jsonb_typeof(draft_blocks) = 'array'),
  draft_version integer not null default 0,
  -- Live state.
  status text not null default 'draft' check (status in ('draft', 'published', 'unpublished')),
  published_revision_id uuid,
  -- Who may read the published copy now: the revision's audience, or
  -- 'members' at once through restrict_church_sermon.
  live_audience text check (live_audience is null or live_audience in ('link', 'members')),
  hidden_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  published_by uuid references auth.users (id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists church_sermons_group_idx on public.church_sermons (group_id, preached_on desc);

-- What was published, never changed afterwards.
create table if not exists public.church_sermon_revisions (
  id uuid primary key default gen_random_uuid(),
  sermon_id uuid not null references public.church_sermons (id) on delete cascade,
  number integer not null check (number >= 1),
  -- title, speaker, series, preached_on, time_zone, location, language and
  -- cover ({id, path, alt, decorative} or null), as published.
  details jsonb not null check (jsonb_typeof(details) = 'object'),
  audience text not null check (audience in ('link', 'members')),
  blocks jsonb not null check (jsonb_typeof(blocks) = 'array'),
  -- The draft_version this revision was published from.
  draft_version integer not null,
  withheld_quotes integer not null default 0,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (sermon_id, number)
);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'church_sermons_published_revision_fkey') then
    alter table public.church_sermons add constraint church_sermons_published_revision_fkey
      foreign key (published_revision_id) references public.church_sermon_revisions (id);
  end if;
end;
$$;

create table if not exists public.church_sermon_reports (
  sermon_id uuid not null references public.church_sermons (id) on delete cascade,
  reporter uuid not null references auth.users (id) on delete cascade,
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  primary key (sermon_id, reporter)
);

create table if not exists public.church_sermon_stats (
  sermon_id uuid primary key references public.church_sermons (id) on delete cascade,
  opens integer not null default 0,
  passage_opens integer not null default 0,
  saves integer not null default 0,
  window_start timestamptz not null default now(),
  window_count integer not null default 0
);

-- One row per sermon, event kind and visitor for one day; the visitor value
-- is an HMAC with a key that changes daily (sermon-events), and rows older
-- than a day are removed as new ones arrive.
create table if not exists public.church_sermon_visits (
  sermon_id uuid not null references public.church_sermons (id) on delete cascade,
  kind text not null check (kind in ('open', 'passage', 'save')),
  visitor text not null check (visitor ~ '^[0-9a-f]{64}$'),
  day date not null default current_date,
  primary key (sermon_id, kind, visitor, day)
);

create index if not exists church_sermon_visits_day_idx on public.church_sermon_visits (day);

-- A person's own notes can point at the sermon they were taken in. No foreign
-- key: the notes outlive an unpublish or a deleted sermon.
alter table public.sermons add column if not exists source_sermon_id uuid;

-- Cover files the sweep has freed (or is about to delete). A retired name is
-- never attached or published again, so a file is never both deleted and in
-- use. Names hold ids only. No policies: only the functions below read it.
create table if not exists public.church_sermon_retired_covers (
  name text primary key,
  retired_at timestamptz not null default now()
);

-- Row level security ---------------------------------------------------------------

alter table public.church_sermons enable row level security;
alter table public.church_sermon_revisions enable row level security;
alter table public.church_sermon_reports enable row level security;
alter table public.church_sermon_stats enable row level security;
alter table public.church_sermon_visits enable row level security;
alter table public.church_sermon_retired_covers enable row level security;

-- Checks --------------------------------------------------------------------------

-- Both switches: the global one and the church's own (and groups on).
create or replace function public.genesis_church_sermons_on(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.genesis_feature_on('church_sermons')
    and public.genesis_feature_on('groups')
    and exists (select 1 from public.groups g where g.id = p_group and g.deleted_at is null and g.sermons_enabled);
$$;

-- An owner or moderator of a church with sermons on.
create or replace function public.genesis_can_edit_sermons(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.genesis_church_sermons_on(p_group)
    and public.genesis_is_leader(p_group)
    and not exists (select 1 from public.group_bans b where b.group_id = p_group and b.user_id = auth.uid());
$$;

-- A member (not banned) of a church with sermons on.
create or replace function public.genesis_can_read_member_sermons(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.genesis_church_sermons_on(p_group)
    and public.genesis_is_member(p_group)
    and not exists (select 1 from public.group_bans b where b.group_id = p_group and b.user_id = auth.uid());
$$;

-- The translation a quotation's label names, when its words may be shown:
-- public domain or a verified free licence (OpenLicence.verified in the
-- app). Null for anything else, including no label. Readers get this code,
-- never the pastor's typed words, and show the passage from their own copy.
create or replace function public.genesis_quote_translation(p_label text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case regexp_replace(lower(translate(coalesce(p_label, ''), 'ÁÉÍÓÚáéíóúÑñÇçÃãÕõÂâÊêÔô', 'AEIOUaeiouNnCcAaOoAaEeOo')), '[^a-z0-9]', '', 'g')
    when 'kjv' then 'KJV' when 'kingjames' then 'KJV' when 'kingjamesversion' then 'KJV'
    when 'authorizedversion' then 'KJV' when 'av' then 'KJV'
    when 'web' then 'WEB' when 'worldenglishbible' then 'WEB'
    when 'asv' then 'ASV' when 'americanstandardversion' then 'ASV'
    when 'rv1909' then 'RV1909' when 'rva1909' then 'RV1909' when 'reinavalera1909' then 'RV1909'
    when 'reinavaleraantigua' then 'RV1909'
    when 'blivre' then 'BLIVRE' when 'biblialivre' then 'BLIVRE'
  end;
$$;

-- A verse id (book*1000000 + chapter*1000 + verse) that exists in the KJV's
-- numbering.
create or replace function public.genesis_valid_verse(p_verse bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_verse is not null and exists (
    select 1 from public.bible_verse_counts c
    where c.book = p_verse / 1000000
      and c.chapter = (p_verse / 1000) % 1000
      and (p_verse % 1000) between 1 and c.verses);
$$;

-- Checks a draft's blocks and returns them unchanged in meaning. Raises
-- 'invalid_blocks' (P0001) with a detail naming the block and the problem:
-- anything missing, of the wrong type, too long or unknown is refused, never
-- trimmed or dropped.
--
-- Block: {"id": "a-z A-Z 0-9 _ -, 1-40" (required), "kind": (required)
--   heading   "text": string <= 300 (required), "level": 1|2|3 (optional, 2)
--   paragraph "text": string <= 5000 (required)
--   quote     "text": string <= 5000 (required)  (the pastor's own words)
--   list      "items": [string <= 2000], up to 100 (required), "ordered": boolean (optional)
--   scripture "ref": {"raw": 1-120 (required), "status": verified|ambiguous|unlinked (required),
--                     "start", "end": verse ids (verified only; end optional),
--                     "label": <= 60, "quote": <= 5000 (optional, null allowed)}}
-- At most 400 blocks and 200,000 characters of text.
create or replace function public.genesis_clean_sermon_blocks(p_blocks jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  b jsonb;
  r jsonb;
  kind text;
  bid text;
  out jsonb := '[]'::jsonb;
  ids text[] := '{}';
  total integer := 0;
  item jsonb;
  s bigint;
  e bigint;
  status text;
  cleaned jsonb;
  allowed text[];
  extra text;
  max_text integer;
begin
  if p_blocks is null or jsonb_typeof(p_blocks) is distinct from 'array' then
    raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'not an array';
  end if;
  if jsonb_array_length(p_blocks) > 400 then
    raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'more than 400 blocks';
  end if;
  for b in select value from jsonb_array_elements(p_blocks) loop
    if jsonb_typeof(b) is distinct from 'object' then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'a block is not an object';
    end if;
    if jsonb_typeof(b->'id') is distinct from 'string' or (b->>'id') !~ '^[A-Za-z0-9_-]{1,40}$' then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'a block has no valid id';
    end if;
    bid := b->>'id';
    if bid = any (ids) then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'duplicate block id ' || bid;
    end if;
    ids := ids || bid;
    kind := case when jsonb_typeof(b->'kind') = 'string' then b->>'kind' end;
    allowed := case kind
      when 'heading' then array['id', 'kind', 'text', 'level']
      when 'paragraph' then array['id', 'kind', 'text']
      when 'quote' then array['id', 'kind', 'text']
      when 'list' then array['id', 'kind', 'items', 'ordered']
      when 'scripture' then array['id', 'kind', 'ref']
    end;
    if allowed is null then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'kind of ' || bid;
    end if;
    select k into extra from jsonb_object_keys(b) k where k <> all (allowed) limit 1;
    if extra is not null then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'unknown field ' || extra || ' in ' || bid;
    end if;
    cleaned := jsonb_build_object('id', bid, 'kind', kind);

    if kind in ('heading', 'paragraph', 'quote') then
      max_text := case when kind = 'heading' then 300 else 5000 end;
      if jsonb_typeof(b->'text') is distinct from 'string' or char_length(b->>'text') > max_text then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'text of ' || bid;
      end if;
      total := total + char_length(b->>'text');
      cleaned := cleaned || jsonb_build_object('text', b->>'text');
      if kind = 'heading' then
        if b ? 'level' and (jsonb_typeof(b->'level') is distinct from 'number' or (b->>'level') not in ('1', '2', '3')) then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'level of ' || bid;
        end if;
        cleaned := cleaned || jsonb_build_object('level', coalesce((b->>'level')::integer, 2));
      end if;

    elsif kind = 'list' then
      if jsonb_typeof(b->'items') is distinct from 'array' or jsonb_array_length(b->'items') > 100 then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'items of ' || bid;
      end if;
      for item in select value from jsonb_array_elements(b->'items') loop
        if jsonb_typeof(item) is distinct from 'string' or char_length(item #>> '{}') > 2000 then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'an item of ' || bid;
        end if;
        total := total + char_length(item #>> '{}');
      end loop;
      if b ? 'ordered' and jsonb_typeof(b->'ordered') is distinct from 'boolean' then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'ordered of ' || bid;
      end if;
      cleaned := cleaned || jsonb_build_object('items', b->'items', 'ordered', coalesce((b->>'ordered')::boolean, false));

    else -- scripture
      r := b->'ref';
      if jsonb_typeof(r) is distinct from 'object' then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'reference of ' || bid;
      end if;
      select k into extra from jsonb_object_keys(r) k
      where k <> all (array['raw', 'start', 'end', 'status', 'label', 'quote']) limit 1;
      if extra is not null then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'unknown field ' || extra || ' in the reference of ' || bid;
      end if;
      if jsonb_typeof(r->'raw') is distinct from 'string' or char_length(btrim(r->>'raw')) not between 1 and 120 then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'typed reference of ' || bid;
      end if;
      status := case when jsonb_typeof(r->'status') = 'string' then r->>'status' end;
      if status is null or status not in ('verified', 'ambiguous', 'unlinked') then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'status of ' || bid;
      end if;
      if status = 'verified' then
        if jsonb_typeof(r->'start') is distinct from 'number'
           or (r ? 'end' and jsonb_typeof(r->'end') not in ('number', 'null')) then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'verses of ' || bid;
        end if;
        -- Both ends whole verse ids, checked before any conversion (a cast
        -- would round 43003016.6 to 43003017).
        if (r->>'start') !~ '^[0-9]{1,10}$'
           or (jsonb_typeof(r->'end') = 'number' and (r->>'end') !~ '^[0-9]{1,10}$') then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'verses of ' || bid;
        end if;
        s := (r->>'start')::bigint;
        e := coalesce((r->>'end')::bigint, s);
        if not public.genesis_valid_verse(s) or not public.genesis_valid_verse(e)
           or e < s or (e / 1000000) <> (s / 1000000) then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'verses of ' || bid;
        end if;
      else
        -- Only verified references open a passage.
        if coalesce(jsonb_typeof(r->'start'), 'null') <> 'null' or coalesce(jsonb_typeof(r->'end'), 'null') <> 'null' then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'verses on an unverified reference in ' || bid;
        end if;
        s := null; e := null;
      end if;
      if coalesce(jsonb_typeof(r->'label'), 'null') not in ('string', 'null') or char_length(r->>'label') > 60 then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'translation label of ' || bid;
      end if;
      if coalesce(jsonb_typeof(r->'quote'), 'null') not in ('string', 'null') or char_length(r->>'quote') > 5000 then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'quotation of ' || bid;
      end if;
      total := total + char_length(r->>'raw') + coalesce(char_length(r->>'quote'), 0);
      cleaned := cleaned || jsonb_build_object('ref', jsonb_build_object(
        'raw', r->>'raw', 'start', s, 'end', e, 'status', status,
        'label', nullif(btrim(coalesce(r->>'label', '')), ''),
        'quote', nullif(r->>'quote', '')));
    end if;
    out := out || jsonb_build_array(cleaned);
  end loop;
  if total > 200000 then
    raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'more than 200,000 characters';
  end if;
  return out;
end;
$$;

-- What readers get: the cleaned blocks without any quoted words. A
-- quotation from a translation that may be shown becomes "translation":
-- "KJV" (readers show that passage from their own verbatim copy, and only
-- for a verified reference); any other is a reference only, marked
-- "quote_withheld": true. The label stays (the church's own words).
create or replace function public.genesis_publishable_blocks(p_blocks jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    case when b->>'kind' = 'scripture' then
      jsonb_set(b, '{ref}', ((b->'ref') - 'quote') || jsonb_build_object(
        'translation', case when b#>>'{ref,status}' = 'verified' then public.genesis_quote_translation(b#>>'{ref,label}') end,
        'quote_withheld', b#>>'{ref,quote}' is not null
          and (b#>>'{ref,status}' <> 'verified' or public.genesis_quote_translation(b#>>'{ref,label}') is null)))
    else b end order by n), '[]'::jsonb)
  from jsonb_array_elements(public.genesis_clean_sermon_blocks(p_blocks)) with ordinality as t (b, n);
$$;

create or replace function public.genesis_new_sermon_slug()
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'abcdefghijkmnpqrstuvwxyz23456789';
  candidate text;
  bytes bytea;
begin
  loop
    bytes := extensions.gen_random_bytes(10);
    candidate := '';
    for i in 0..9 loop
      candidate := candidate || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
    end loop;
    exit when not exists (select 1 from public.church_sermons where slug = candidate);
  end loop;
  return candidate;
end;
$$;

create or replace function public.genesis_sermon_cover_path(p_group uuid, p_sermon uuid, p_cover uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_group::text || '/' || p_sermon::text || '/' || p_cover::text || '.jpg';
$$;

-- Leaders' direct reads (Church Studio) ------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'church_sermons' and policyname = 'Leaders read') then
    create policy "Leaders read" on public.church_sermons for select to authenticated
      using (deleted_at is null and public.genesis_can_edit_sermons(group_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'church_sermon_revisions' and policyname = 'Leaders read') then
    create policy "Leaders read" on public.church_sermon_revisions for select to authenticated
      using (exists (select 1 from public.church_sermons s
                     where s.id = sermon_id and s.deleted_at is null and public.genesis_can_edit_sermons(s.group_id)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'church_sermon_stats' and policyname = 'Leaders read') then
    create policy "Leaders read" on public.church_sermon_stats for select to authenticated
      using (exists (select 1 from public.church_sermons s
                     where s.id = sermon_id and s.deleted_at is null and public.genesis_can_edit_sermons(s.group_id)));
  end if;
end;
$$;

-- Writing (owner and moderators) --------------------------------------------------------

-- Locks the sermon for the rest of the transaction and checks the caller may
-- edit it.
create or replace function public.genesis_editable_sermon(p_sermon uuid)
returns public.church_sermons
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  select * into row_ from public.church_sermons where id = p_sermon and deleted_at is null for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if not public.genesis_can_edit_sermons(row_.group_id) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return row_;
end;
$$;

create or replace function public.genesis_check_version(p_row public.church_sermons, p_expected integer)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_expected is distinct from p_row.draft_version then
    raise exception 'draft_changed' using errcode = 'P0001', detail = p_row.draft_version::text;
  end if;
end;
$$;

create or replace function public.create_church_sermon(p_group uuid, p_title text default '')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  new_slug text;
begin
  if not public.genesis_can_edit_sermons(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) > 200 then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'title';
  end if;
  new_slug := public.genesis_new_sermon_slug();
  insert into public.church_sermons (group_id, slug, title, created_by)
  values (p_group, new_slug, btrim(coalesce(p_title, '')), auth.uid())
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'slug', new_slug, 'draft_version', 0);
end;
$$;

-- Saves the draft; readers see nothing of it until it's published.
-- p_expected_version must be the version the editor loaded. Details keys
-- (all optional): title, speaker, series, preached_on (YYYY-MM-DD or null),
-- time_zone, location, language, audience, cover (a cover id whose file is
-- already uploaded, or null for none), cover_alt, cover_decorative. Text
-- that's too long is refused ('invalid_details'), never cut. p_blocks null
-- keeps the outline.
create or replace function public.save_church_sermon(p_sermon uuid, p_expected_version integer, p_details jsonb, p_blocks jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  d jsonb := coalesce(p_details, '{}'::jsonb);
  blocks jsonb;
  k text;
  limits constant jsonb := '{"title": 200, "speaker": 120, "series": 120, "time_zone": 64, "location": 200, "cover_alt": 300}';
  new_cover uuid;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  perform public.genesis_check_version(row_, p_expected_version);
  if jsonb_typeof(d) is distinct from 'object' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'not an object';
  end if;
  for k in select jsonb_object_keys(d) loop
    if k not in ('title', 'speaker', 'series', 'preached_on', 'time_zone', 'location', 'language', 'audience', 'cover', 'cover_alt', 'cover_decorative') then
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'unknown field ' || k;
    end if;
    if limits ? k and (coalesce(jsonb_typeof(d->k), 'null') not in ('string', 'null')
                       or char_length(btrim(coalesce(d->>k, ''))) > (limits->>k)::integer) then
      raise exception 'invalid_details' using errcode = 'P0001', detail = k;
    end if;
  end loop;
  if d ? 'language' and coalesce(d->>'language', '') not in ('en', 'es', 'pt', 'other') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'language';
  end if;
  if d ? 'audience' and coalesce(d->>'audience', '') not in ('link', 'members') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'audience';
  end if;
  if d ? 'cover_decorative' and jsonb_typeof(d->'cover_decorative') is distinct from 'boolean' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'cover_decorative';
  end if;
  if d ? 'preached_on' and d->>'preached_on' is not null and (d->>'preached_on') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'preached_on';
  end if;
  new_cover := row_.cover_id;
  if d ? 'cover' then
    if d->>'cover' is null then
      new_cover := null;
    elsif (d->>'cover') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          or not exists (select 1 from storage.objects o where o.bucket_id = 'sermon-covers'
                         and o.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, (d->>'cover')::uuid))
          or exists (select 1 from public.church_sermon_retired_covers t
                     where t.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, (d->>'cover')::uuid)) then
      -- Checked while holding the sermon's row lock, which the sweep takes
      -- before retiring a cover of this sermon.
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'cover';
    else
      new_cover := (d->>'cover')::uuid;
    end if;
  end if;
  blocks := case when p_blocks is null then row_.draft_blocks else public.genesis_clean_sermon_blocks(p_blocks) end;
  update public.church_sermons set
    title = case when d ? 'title' then btrim(coalesce(d->>'title', '')) else title end,
    speaker = case when d ? 'speaker' then btrim(coalesce(d->>'speaker', '')) else speaker end,
    series = case when d ? 'series' then nullif(btrim(coalesce(d->>'series', '')), '') else series end,
    preached_on = case when d ? 'preached_on' then (d->>'preached_on')::date else preached_on end,
    time_zone = case when d ? 'time_zone' then nullif(btrim(coalesce(d->>'time_zone', '')), '') else time_zone end,
    location = case when d ? 'location' then btrim(coalesce(d->>'location', '')) else location end,
    language = coalesce(d->>'language', language),
    audience = coalesce(d->>'audience', audience),
    cover_id = new_cover,
    cover_alt = case when d ? 'cover_alt' then btrim(coalesce(d->>'cover_alt', '')) else cover_alt end,
    cover_decorative = case when d ? 'cover_decorative' then (d->>'cover_decorative')::boolean else cover_decorative end,
    draft_blocks = blocks,
    draft_version = draft_version + 1,
    updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('draft_version', row_.draft_version + 1);
end;
$$;

-- Publishes the draft as it was at p_expected_version, in one transaction:
-- outline, details, cover and audience together. Retried while the sermon is
-- still published at that version, it returns the same revision and changes
-- nothing. After an unpublish, restrict or delete the version has moved on,
-- so an old request is refused ('draft_changed') and only a fresh publish
-- (with the current version) opens it again.
create or replace function public.publish_church_sermon(p_sermon uuid, p_expected_version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  last_ public.church_sermon_revisions;
  blocks jsonb;
  details jsonb;
  withheld integer;
  new_id uuid;
  new_number integer;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  perform public.genesis_check_version(row_, p_expected_version);
  select * into last_ from public.church_sermon_revisions where id = row_.published_revision_id;
  if found and last_.draft_version = row_.draft_version and row_.status = 'published' then
    return jsonb_build_object('revision', last_.id, 'number', last_.number, 'withheld_quotes', last_.withheld_quotes,
                              'draft_version', row_.draft_version, 'repeated', true);
  end if;
  if btrim(row_.title) = '' then raise exception 'needs_title' using errcode = 'P0001'; end if;
  if row_.cover_id is not null then
    if not row_.cover_decorative and btrim(row_.cover_alt) = '' then
      raise exception 'needs_cover_alt' using errcode = 'P0001';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'sermon-covers'
                   and o.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id))
       or exists (select 1 from public.church_sermon_retired_covers t
                  where t.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id)) then
      raise exception 'cover_missing' using errcode = 'P0001';
    end if;
  end if;
  blocks := public.genesis_publishable_blocks(row_.draft_blocks);
  if jsonb_array_length(blocks) = 0 then raise exception 'empty_outline' using errcode = 'P0001'; end if;
  select count(*) into withheld from jsonb_array_elements(blocks) b where (b#>>'{ref,quote_withheld}') = 'true';
  details := jsonb_build_object(
    'title', row_.title, 'speaker', row_.speaker, 'series', row_.series, 'preached_on', row_.preached_on,
    'time_zone', row_.time_zone, 'location', row_.location, 'language', row_.language,
    'cover', case when row_.cover_id is not null then jsonb_build_object(
      'id', row_.cover_id,
      'path', public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id),
      'alt', case when row_.cover_decorative then '' else row_.cover_alt end,
      'decorative', row_.cover_decorative) end);
  select coalesce(max(number), 0) + 1 into new_number from public.church_sermon_revisions where sermon_id = p_sermon;
  insert into public.church_sermon_revisions (sermon_id, number, details, audience, blocks, draft_version, withheld_quotes, created_by)
  values (p_sermon, new_number, details, row_.audience, blocks, row_.draft_version, withheld, auth.uid())
  returning id into new_id;
  update public.church_sermons set
    published_revision_id = new_id, status = 'published', live_audience = row_.audience,
    published_at = now(), published_by = auth.uid(), updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('revision', new_id, 'number', new_number, 'withheld_quotes', withheld,
                            'draft_version', row_.draft_version, 'repeated', false);
end;
$$;

-- Closing actions take effect at once and move the version on (returned), so
-- no earlier publish request can undo them.

create or replace function public.unpublish_church_sermon(p_sermon uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  update public.church_sermons set
    status = case when status = 'published' then 'unpublished' else status end,
    draft_version = draft_version + 1, updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('draft_version', row_.draft_version + 1);
end;
$$;

-- Members only, now: the published copy stops being open to the link at
-- once (and the draft follows). Opening it again takes a publish.
create or replace function public.restrict_church_sermon(p_sermon uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  update public.church_sermons set
    live_audience = case when live_audience is null then null else 'members' end,
    audience = 'members', draft_version = draft_version + 1, updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('draft_version', row_.draft_version + 1);
end;
$$;

-- Soft delete; the link stops working at once.
create or replace function public.delete_church_sermon(p_sermon uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.genesis_editable_sermon(p_sermon);
  update public.church_sermons set
    deleted_at = now(), status = case when status = 'published' then 'unpublished' else status end,
    draft_version = draft_version + 1, updated_at = now()
  where id = p_sermon;
end;
$$;

-- A new draft with the same details (no date, no cover) and outline, for
-- next week.
create or replace function public.duplicate_church_sermon(p_sermon uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  new_id uuid;
  new_slug text;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  new_slug := public.genesis_new_sermon_slug();
  insert into public.church_sermons (group_id, slug, title, speaker, series, time_zone, location, language, audience, draft_blocks, created_by)
  values (row_.group_id, new_slug, row_.title, row_.speaker, row_.series, row_.time_zone, row_.location, row_.language, row_.audience, row_.draft_blocks, auth.uid())
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'slug', new_slug, 'draft_version', 0);
end;
$$;

-- A path to upload a new cover picture to (a new id each time, so the
-- published picture never changes); then save_church_sermon with
-- {"cover": id} puts it on the draft.
create or replace function public.new_church_sermon_cover(p_sermon uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  cover uuid := gen_random_uuid();
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  return jsonb_build_object('cover', cover, 'path', public.genesis_sermon_cover_path(row_.group_id, row_.id, cover));
end;
$$;

create or replace function public.set_sermons_listed(p_group uuid, p_listed boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_can_edit_sermons(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  update public.groups set sermons_listed = coalesce(p_listed, false) where id = p_group;
end;
$$;

-- Reading --------------------------------------------------------------------------

-- Published, shown and switched on (anyone's view, before the audience).
create or replace function public.genesis_sermon_live(p_row public.church_sermons)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_row.deleted_at is null
    and p_row.status = 'published'
    and p_row.published_revision_id is not null
    and p_row.live_audience is not null
    and p_row.hidden_at is null
    and public.genesis_church_sermons_on(p_row.group_id);
$$;

-- Whether the caller may read this published sermon now.
create or replace function public.genesis_can_read_sermon(p_row public.church_sermons)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.genesis_sermon_live(p_row)
    and (p_row.live_audience = 'link' or public.genesis_can_read_member_sermons(p_row.group_id));
$$;

-- The published copy's details with its slug, for lists and navigation.
create or replace function public.genesis_sermon_summary(p_row public.church_sermons)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('slug', p_row.slug, 'title', r.details->>'title', 'speaker', r.details->>'speaker',
                            'series', r.details->'series', 'preached_on', r.details->'preached_on',
                            'audience', p_row.live_audience, 'published_at', p_row.published_at)
  from public.church_sermon_revisions r where r.id = p_row.published_revision_id;
$$;

-- The sermon behind a link, for anyone. Returns {"status": "ok", ...} with the
-- published copy, {"status": "members_only"} (nothing else) or
-- {"status": "not_found"} (also for a switched-off church, an unpublished,
-- hidden or deleted sermon). The draft never shows here.
create or replace function public.published_sermon(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  rev public.church_sermon_revisions;
  church text;
  member boolean;
  series_ text;
  day_ text;
  prev_ jsonb;
  next_ jsonb;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9]{10}$' then
    return jsonb_build_object('status', 'not_found');
  end if;
  select * into row_ from public.church_sermons where slug = p_slug;
  if not found or not public.genesis_sermon_live(row_) then
    return jsonb_build_object('status', 'not_found');
  end if;
  member := public.genesis_can_read_member_sermons(row_.group_id);
  if row_.live_audience = 'members' and not member then
    return jsonb_build_object('status', 'members_only');
  end if;
  select * into rev from public.church_sermon_revisions where id = row_.published_revision_id;
  select name into church from public.groups where id = row_.group_id;
  series_ := rev.details->>'series';
  day_ := coalesce(rev.details->>'preached_on', '');
  if series_ is not null then
    select public.genesis_sermon_summary(s) into prev_
    from public.church_sermons s join public.church_sermon_revisions r on r.id = s.published_revision_id
    where s.group_id = row_.group_id and s.id <> row_.id and r.details->>'series' = series_
      and public.genesis_can_read_sermon(s)
      and (coalesce(r.details->>'preached_on', ''), s.published_at) < (day_, row_.published_at)
    order by coalesce(r.details->>'preached_on', '') desc, s.published_at desc limit 1;
    select public.genesis_sermon_summary(s) into next_
    from public.church_sermons s join public.church_sermon_revisions r on r.id = s.published_revision_id
    where s.group_id = row_.group_id and s.id <> row_.id and r.details->>'series' = series_
      and public.genesis_can_read_sermon(s)
      and (coalesce(r.details->>'preached_on', ''), s.published_at) > (day_, row_.published_at)
    order by coalesce(r.details->>'preached_on', '') asc, s.published_at asc limit 1;
  end if;
  return rev.details || jsonb_build_object(
    'status', 'ok',
    'id', row_.id,
    'slug', row_.slug,
    'group_id', row_.group_id,
    'church', church,
    'audience', row_.live_audience,
    'revision', rev.number,
    'published_at', row_.published_at,
    'blocks', rev.blocks,
    'previous', prev_,
    'next', next_,
    'is_member', member);
end;
$$;

-- A church's sermons: the published copies for members; the drafts and
-- their live state for leaders. No outlines here.
create or replace function public.group_sermons(p_group uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if public.genesis_can_edit_sermons(p_group) then
    return coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'slug', s.slug, 'title', s.title, 'speaker', s.speaker, 'series', s.series,
        'preached_on', s.preached_on, 'audience', s.audience, 'status', s.status,
        'live_audience', s.live_audience, 'hidden', s.hidden_at is not null, 'has_cover', s.cover_id is not null,
        'published_at', s.published_at, 'draft_version', s.draft_version,
        'unpublished_changes', s.status = 'published' and r.draft_version is distinct from s.draft_version)
        order by s.preached_on desc nulls first, s.created_at desc)
      from public.church_sermons s left join public.church_sermon_revisions r on r.id = s.published_revision_id
      where s.group_id = p_group and s.deleted_at is null
    ), '[]'::jsonb);
  end if;
  if not public.genesis_can_read_member_sermons(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(public.genesis_sermon_summary(s) order by (public.genesis_sermon_summary(s)->>'preached_on') desc nulls last, s.published_at desc)
    from public.church_sermons s
    where s.group_id = p_group and public.genesis_can_read_sermon(s)
  ), '[]'::jsonb);
end;
$$;

-- Churches that chose to be listed, by name (accents and case ignored), with
-- their latest sermons anyone with a link could open. No location needed.
create or replace function public.search_sermon_churches(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  q text := regexp_replace(lower(translate(btrim(coalesce(p_query, '')), 'ÁÉÍÓÚÜáéíóúüÑñÇçÃãÕõÂâÊêÔôÀÈÌÒÙàèìòùÄËÏÖäëïö', 'AEIOUUaeiouuNnCcAaOoAaEeOoAEIOUaeiouAEIOaeio')), '\s+', ' ', 'g');
begin
  if char_length(q) < 2 or char_length(q) > 60 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(c order by c->>'name')
    from (
      select jsonb_build_object(
        'group_id', g.id,
        'name', g.name,
        'sermons', coalesce((
          select jsonb_agg(x.summary order by x.summary->>'preached_on' desc nulls last, x.published_at desc)
          from (select public.genesis_sermon_summary(s2) as summary, s2.published_at
                from public.church_sermons s2
                where s2.group_id = g.id and public.genesis_sermon_live(s2) and s2.live_audience = 'link'
                order by s2.published_at desc limit 5) x
        ), '[]'::jsonb)) as c
      from public.groups g
      where g.deleted_at is null and g.sermons_listed and public.genesis_church_sermons_on(g.id)
        and position(q in regexp_replace(lower(translate(g.name, 'ÁÉÍÓÚÜáéíóúüÑñÇçÃãÕõÂâÊêÔôÀÈÌÒÙàèìòùÄËÏÖäëïö', 'AEIOUUaeiouuNnCcAaOoAaEeOoAEIOUaeiouAEIOaeio')), '\s+', ' ', 'g')) > 0
      limit 20
    ) found
  ), '[]'::jsonb);
end;
$$;

-- Reports ----------------------------------------------------------------------------

-- Any signed-in reader of a published sermon can report it, once. Three
-- reports from different people hide it until a moderator reviews it. The
-- sermon row is locked first, so reports arriving together are counted one
-- after another and the third always hides it.
create or replace function public.report_church_sermon(p_slug text, p_reason text default '')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if char_length(coalesce(p_reason, '')) > 500 then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'reason';
  end if;
  select * into row_ from public.church_sermons where slug = p_slug for update;
  if not found or not public.genesis_can_read_sermon(row_) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  insert into public.church_sermon_reports (sermon_id, reporter, reason)
  values (row_.id, auth.uid(), coalesce(p_reason, ''))
  on conflict (sermon_id, reporter) do nothing;
  if (select count(*) from public.church_sermon_reports r where r.sermon_id = row_.id and r.resolved_at is null) >= 3 then
    update public.church_sermons set hidden_at = coalesce(hidden_at, now()) where id = row_.id;
  end if;
end;
$$;

-- Open reports on a church's sermons, without saying who reported. Leaders only.
create or replace function public.group_sermon_reports(p_group uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.genesis_can_edit_sermons(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'sermon_id', x.id, 'slug', x.slug, 'title', x.title, 'hidden', x.hidden,
      'report_count', x.report_count, 'reasons', x.reasons, 'last_reported_at', x.last_reported_at)
      order by x.last_reported_at desc)
    from (
      select s.id, s.slug, coalesce(r0.details->>'title', s.title) as title, s.hidden_at is not null as hidden,
             count(*) as report_count,
             array_remove(array_agg(nullif(r.reason, '') order by r.created_at), null) as reasons,
             max(r.created_at) as last_reported_at
      from public.church_sermons s
      join public.church_sermon_reports r on r.sermon_id = s.id and r.resolved_at is null
      left join public.church_sermon_revisions r0 on r0.id = s.published_revision_id
      where s.group_id = p_group and s.deleted_at is null
      group by s.id, r0.details
    ) x
  ), '[]'::jsonb);
end;
$$;

-- Keep (show it again) or take it down (unpublish, which moves the version
-- on); either closes the reports.
create or replace function public.review_church_sermon_reports(p_sermon uuid, p_keep boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.genesis_editable_sermon(p_sermon);
  update public.church_sermon_reports set resolved_at = now() where sermon_id = p_sermon and resolved_at is null;
  if p_keep then
    update public.church_sermons set hidden_at = null where id = p_sermon;
  else
    update public.church_sermons set
      hidden_at = null, status = case when status = 'published' then 'unpublished' else status end,
      draft_version = draft_version + 1, updated_at = now()
    where id = p_sermon;
  end if;
end;
$$;

-- Counts (sermon-events Edge Function only) ------------------------------------------------

-- Returns true when the event was counted. Only sermons a guest can open now
-- are counted (published, shown, open to the link; members-only ones are
-- not counted here). p_visitor is the function's daily-keyed HMAC (64 hex);
-- nothing else about the visitor is stored.
create or replace function public.record_sermon_event(p_slug text, p_kind text, p_visitor text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  inserted integer;
  stats public.church_sermon_stats;
begin
  if p_kind is null or p_kind not in ('open', 'passage', 'save') or p_visitor is null or p_visitor !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  select * into row_ from public.church_sermons where slug = p_slug;
  if not found or not public.genesis_sermon_live(row_) or row_.live_audience <> 'link' then
    return false;
  end if;
  delete from public.church_sermon_visits where day < current_date - 1;
  insert into public.church_sermon_visits (sermon_id, kind, visitor) values (row_.id, p_kind, p_visitor)
  on conflict do nothing;
  get diagnostics inserted = row_count;
  if inserted = 0 then return false; end if;
  insert into public.church_sermon_stats (sermon_id) values (row_.id) on conflict (sermon_id) do nothing;
  select * into stats from public.church_sermon_stats where sermon_id = row_.id for update;
  if stats.window_start < date_trunc('minute', now()) then
    stats.window_start := date_trunc('minute', now());
    stats.window_count := 0;
  end if;
  if stats.window_count >= 60 then
    update public.church_sermon_stats set window_start = stats.window_start, window_count = stats.window_count where sermon_id = row_.id;
    return false;
  end if;
  update public.church_sermon_stats set
    opens = opens + case when p_kind = 'open' then 1 else 0 end,
    passage_opens = passage_opens + case when p_kind = 'passage' then 1 else 0 end,
    saves = saves + case when p_kind = 'save' then 1 else 0 end,
    window_start = stats.window_start,
    window_count = stats.window_count + 1
  where sermon_id = row_.id;
  return true;
end;
$$;

-- Covers -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sermon-covers', 'sermon-covers', false, 1048576, array['image/jpeg'])
on conflict (id) do nothing;

-- Leaders upload <group id>/<sermon id>/<cover id>.jpg for their church's
-- own sermons (a new cover id each time; files are never replaced or deleted
-- by people, and a retired name can't be uploaded again). Nobody else reads
-- them directly: readers get covers through a request that rechecks access
-- (checkpoint 2).
create or replace function public.genesis_can_edit_cover(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
    and exists (
      select 1 from public.church_sermons s
      where s.group_id::text = split_part(p_name, '/', 1)
        and s.id::text = split_part(p_name, '/', 2)
        and s.deleted_at is null
        and public.genesis_can_edit_sermons(s.group_id))
    and not exists (select 1 from public.church_sermon_retired_covers t where t.name = p_name);
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders add') then
    create policy "Sermon covers: leaders add" on storage.objects for insert to authenticated
      with check (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders see') then
    create policy "Sermon covers: leaders see" on storage.objects for select to authenticated
      using (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name));
  end if;
end;
$$;

-- The nightly sweep (service role): retires cover files neither the draft nor
-- the published copy uses (replaced, removed, unpublished, deleted sermons)
-- and returns their names for it to delete through the Storage API. Each
-- candidate is rechecked while holding its sermon's row lock, the lock save
-- and publish take, so a save attaching the cover or a publish at the same
-- moment either finishes first (the cover stays) or waits and is refused
-- (retired). Names already retired whose files remain (a delete that failed)
-- are returned again. Older than a day only, so an upload in progress is
-- never swept.
create or replace function public.retire_orphan_sermon_covers()
returns setof text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  o record;
  row_ public.church_sermons;
  live_path text;
begin
  for o in
    select ob.name, exists (select 1 from public.church_sermon_retired_covers t where t.name = ob.name) as retired
    from storage.objects ob
    where ob.bucket_id = 'sermon-covers' and ob.created_at < now() - interval '1 day'
    order by ob.name
  loop
    if not o.retired then
      row_ := null;
      if split_part(o.name, '/', 2) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        select * into row_ from public.church_sermons s where s.id = split_part(o.name, '/', 2)::uuid for update;
      end if;
      if row_.id is not null and row_.deleted_at is null then
        continue when row_.cover_id is not null
          and public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id) = o.name;
        if row_.status = 'published' then
          select r.details#>>'{cover,path}' into live_path
          from public.church_sermon_revisions r where r.id = row_.published_revision_id;
          continue when live_path is not distinct from o.name;
        end if;
      end if;
      insert into public.church_sermon_retired_covers (name) values (o.name) on conflict (name) do nothing;
    end if;
    return next o.name;
  end loop;
end;
$$;

-- Grants -------------------------------------------------------------------------------

revoke all on function public.genesis_church_sermons_on(uuid) from public, anon;
revoke all on function public.genesis_can_edit_sermons(uuid) from public, anon;
revoke all on function public.genesis_can_read_member_sermons(uuid) from public, anon;
revoke all on function public.genesis_valid_verse(bigint) from public, anon, authenticated;
revoke all on function public.genesis_clean_sermon_blocks(jsonb) from public, anon, authenticated;
revoke all on function public.genesis_publishable_blocks(jsonb) from public, anon, authenticated;
revoke all on function public.genesis_sermon_live(public.church_sermons) from public, anon, authenticated;
revoke all on function public.genesis_can_read_sermon(public.church_sermons) from public, anon, authenticated;
revoke all on function public.genesis_sermon_summary(public.church_sermons) from public, anon, authenticated;
revoke all on function public.genesis_editable_sermon(uuid) from public, anon, authenticated;
revoke all on function public.genesis_check_version(public.church_sermons, integer) from public, anon, authenticated;
revoke all on function public.genesis_new_sermon_slug() from public, anon, authenticated;
revoke all on function public.genesis_can_edit_cover(text) from public, anon;
revoke all on function public.create_church_sermon(uuid, text) from public, anon;
revoke all on function public.save_church_sermon(uuid, integer, jsonb, jsonb) from public, anon;
revoke all on function public.publish_church_sermon(uuid, integer) from public, anon;
revoke all on function public.unpublish_church_sermon(uuid) from public, anon;
revoke all on function public.restrict_church_sermon(uuid) from public, anon;
revoke all on function public.delete_church_sermon(uuid) from public, anon;
revoke all on function public.duplicate_church_sermon(uuid) from public, anon;
revoke all on function public.new_church_sermon_cover(uuid) from public, anon;
revoke all on function public.set_sermons_listed(uuid, boolean) from public, anon;
revoke all on function public.group_sermons(uuid) from public, anon;
revoke all on function public.report_church_sermon(text, text) from public, anon;
revoke all on function public.group_sermon_reports(uuid) from public, anon;
revoke all on function public.review_church_sermon_reports(uuid, boolean) from public, anon;
revoke all on function public.record_sermon_event(text, text, text) from public, anon, authenticated;
revoke all on function public.retire_orphan_sermon_covers() from public, anon, authenticated;
revoke all on table public.church_sermon_retired_covers from anon, authenticated;

grant execute on function public.genesis_church_sermons_on(uuid) to authenticated;
grant execute on function public.genesis_can_edit_sermons(uuid) to authenticated;
grant execute on function public.genesis_can_read_member_sermons(uuid) to authenticated;
grant execute on function public.genesis_can_edit_cover(text) to authenticated;
grant execute on function public.create_church_sermon(uuid, text) to authenticated;
grant execute on function public.save_church_sermon(uuid, integer, jsonb, jsonb) to authenticated;
grant execute on function public.publish_church_sermon(uuid, integer) to authenticated;
grant execute on function public.unpublish_church_sermon(uuid) to authenticated;
grant execute on function public.restrict_church_sermon(uuid) to authenticated;
grant execute on function public.delete_church_sermon(uuid) to authenticated;
grant execute on function public.duplicate_church_sermon(uuid) to authenticated;
grant execute on function public.new_church_sermon_cover(uuid) to authenticated;
grant execute on function public.set_sermons_listed(uuid, boolean) to authenticated;
grant execute on function public.group_sermons(uuid) to authenticated;
grant execute on function public.report_church_sermon(text, text) to authenticated;
grant execute on function public.group_sermon_reports(uuid) to authenticated;
grant execute on function public.review_church_sermon_reports(uuid, boolean) to authenticated;
grant execute on function public.published_sermon(text) to anon, authenticated;
grant execute on function public.search_sermon_churches(text) to anon, authenticated;
grant execute on function public.record_sermon_event(text, text, text) to service_role;
grant execute on function public.retire_orphan_sermon_covers() to service_role;

comment on table public.church_sermons is
  'Church sermons (VRS-18). Draft columns are the Studio''s; readers get only the published revision (published_sermon / group_sermons). Written through the *_church_sermon functions. Quoted words never reach readers: approved translations publish as a code, others as references only.';
comment on column public.groups.sermons_enabled is
  'Church sermons pilot switch for this church. Set by the owner only (dashboard).';
