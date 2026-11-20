-- Versely: church sermons (VRS-18, Versely 1.0.4). Free for everyone.
--
-- A church publishes a sermon outline; members and guests follow along with
-- one link (https://versely.7twenty8studio.com/s/<slug>) on the web or in
-- the app, read each passage in their own Bible and keep private notes.
-- Plan and decisions: "VRS-18: Church Sermons plan" (20 Nov 2026).
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
--   * The draft lives on the sermon (draft_blocks + draft_version for
--     optimistic saves). Publishing copies a cleaned draft into an immutable
--     revision in one transaction; a retried publish returns the same one.
--   * Scripture: blocks hold the pastor's words as written and verse ids
--     (KJV numbering), never text fetched from a Bible. A quotation is
--     published only when its translation is public domain or freely
--     reusable (KJV, WEB, ASV, Reina-Valera 1909, Biblia Livre); any other or
--     unknown label is published as a reference only (owner, 20 Nov 2026).
--     Publishing licensed words needs that publisher's written grant first.
--   * Covers: one JPEG per sermon (<= 1 MB) in the private sermon-covers
--     bucket at <group id>/<sermon id>.jpg, served by short-lived signed
--     links under the sermon's audience. Re-encoded on the device, so no
--     metadata.
--   * Reports: any signed-in reader can report a published sermon; it reaches
--     the church's moderators (and the ops dashboard). Three reports from
--     different people hide it until a moderator reviews it.
--   * Counts: aggregate only, written by the sermon-events Edge Function
--     (service role) with a daily-salted visitor hash, one per visitor per
--     day, at most 60 a minute per sermon. No address, user id or text.
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

-- Tables -------------------------------------------------------------------------

create table if not exists public.church_sermons (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9]{10}$'),
  title text not null default '' check (char_length(title) <= 200),
  speaker text not null default '' check (char_length(speaker) <= 120),
  series text check (series is null or char_length(series) between 1 and 120),
  preached_on date,
  time_zone text check (time_zone is null or char_length(time_zone) <= 64),
  location text not null default '' check (char_length(location) <= 200),
  language text not null default 'en' check (language in ('en', 'es', 'pt', 'other')),
  audience text not null default 'link' check (audience in ('link', 'members')),
  status text not null default 'draft' check (status in ('draft', 'published', 'unpublished')),
  draft_blocks jsonb not null default '[]'::jsonb check (jsonb_typeof(draft_blocks) = 'array'),
  draft_version integer not null default 0,
  published_revision_id uuid,
  has_cover boolean not null default false,
  cover_alt text not null default '' check (char_length(cover_alt) <= 300),
  cover_decorative boolean not null default false,
  hidden_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  published_by uuid references auth.users (id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists church_sermons_group_idx on public.church_sermons (group_id, preached_on desc);

create table if not exists public.church_sermon_revisions (
  id uuid primary key default gen_random_uuid(),
  sermon_id uuid not null references public.church_sermons (id) on delete cascade,
  number integer not null check (number >= 1),
  blocks jsonb not null check (jsonb_typeof(blocks) = 'array'),
  -- The draft_version this revision was published from (a retried publish of
  -- the same version returns this revision).
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
-- is an HMAC with a salt that changes daily (sermon-events), and rows older
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

-- Row level security ---------------------------------------------------------------

alter table public.church_sermons enable row level security;
alter table public.church_sermon_revisions enable row level security;
alter table public.church_sermon_reports enable row level security;
alter table public.church_sermon_stats enable row level security;
alter table public.church_sermon_visits enable row level security;

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

-- Translations whose quoted words may be published: public domain or a
-- verified free licence (OpenLicence.verified in the app). Anything else,
-- including no label, is published as a reference only.
create or replace function public.genesis_quote_publishable(p_label text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    regexp_replace(lower(translate(p_label, 'ÁÉÍÓÚáéíóúÑñÇçÃãÕõÂâÊêÔô', 'AEIOUaeiouNnCcAaOoAaEeOo')), '[^a-z0-9]', '', 'g')
    in ('kjv', 'kingjames', 'kingjamesversion', 'authorizedversion', 'av',
        'web', 'worldenglishbible',
        'asv', 'americanstandardversion',
        'rv1909', 'rva1909', 'reinavalera1909', 'reinavaleraantigua',
        'blivre', 'biblialivre'),
    false);
$$;

-- A valid verse id (book*1000000 + chapter*1000 + verse).
create or replace function public.genesis_valid_verse(p_verse bigint)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_verse is not null
    and (p_verse / 1000000) between 1 and 66
    and ((p_verse / 1000) % 1000) between 1 and 150
    and (p_verse % 1000) between 1 and 176;
$$;

-- Checks a draft's blocks and returns them with only the allowed keys.
-- Raises 'invalid_blocks' (P0001) with a detail naming the problem.
--
-- Block: {"id": "a-z A-Z 0-9 _ -, 1-40", "kind": heading|paragraph|list|quote|scripture,
--         "text": string <= 5000 (heading, paragraph, quote; heading <= 300),
--         "items": [string <= 2000] up to 100 and "ordered": bool (list),
--         "level": 1|2|3 (heading),
--         "ref": {"raw": 1-120, "start": verse id|null, "end": verse id|null,
--                 "status": verified|ambiguous|unlinked, "label": <= 60|null,
--                 "quote": <= 5000|null} (scripture)}
-- At most 400 blocks and 200,000 characters of text.
create or replace function public.genesis_clean_sermon_blocks(p_blocks jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  b jsonb;
  r jsonb;
  kind text;
  out jsonb := '[]'::jsonb;
  ids text[] := '{}';
  total integer := 0;
  item jsonb;
  items jsonb;
  s bigint;
  e bigint;
  status text;
  cleaned jsonb;
begin
  if p_blocks is null or jsonb_typeof(p_blocks) <> 'array' then
    raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'not an array';
  end if;
  if jsonb_array_length(p_blocks) > 400 then
    raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'too many blocks';
  end if;
  for b in select value from jsonb_array_elements(p_blocks) loop
    if jsonb_typeof(b) <> 'object' or jsonb_typeof(b->'id') <> 'string' or (b->>'id') !~ '^[A-Za-z0-9_-]{1,40}$' then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'block id';
    end if;
    if (b->>'id') = any (ids) then
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'duplicate block id ' || (b->>'id');
    end if;
    ids := ids || (b->>'id');
    kind := b->>'kind';
    cleaned := jsonb_build_object('id', b->>'id', 'kind', kind);
    if kind in ('heading', 'paragraph', 'quote') then
      if jsonb_typeof(b->'text') <> 'string' or char_length(b->>'text') > (case when kind = 'heading' then 300 else 5000 end) then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'text of ' || (b->>'id');
      end if;
      total := total + char_length(b->>'text');
      cleaned := cleaned || jsonb_build_object('text', b->>'text');
      if kind = 'heading' then
        cleaned := cleaned || jsonb_build_object('level',
          case when (b->>'level') in ('1', '2', '3') then (b->>'level')::integer else 2 end);
      end if;
    elsif kind = 'list' then
      items := b->'items';
      if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) > 100 then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'items of ' || (b->>'id');
      end if;
      for item in select value from jsonb_array_elements(items) loop
        if jsonb_typeof(item) <> 'string' or char_length(item #>> '{}') > 2000 then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'item of ' || (b->>'id');
        end if;
        total := total + char_length(item #>> '{}');
      end loop;
      cleaned := cleaned || jsonb_build_object('items', items, 'ordered', coalesce((b->>'ordered')::boolean, false));
    elsif kind = 'scripture' then
      r := b->'ref';
      if jsonb_typeof(r) <> 'object' or jsonb_typeof(r->'raw') <> 'string'
         or char_length(btrim(r->>'raw')) not between 1 and 120 then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'reference of ' || (b->>'id');
      end if;
      status := coalesce(r->>'status', 'unlinked');
      if status not in ('verified', 'ambiguous', 'unlinked') then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'status of ' || (b->>'id');
      end if;
      s := case when jsonb_typeof(r->'start') = 'number' then (r->>'start')::bigint end;
      e := case when jsonb_typeof(r->'end') = 'number' then (r->>'end')::bigint end;
      if status = 'verified' then
        if not public.genesis_valid_verse(s) or not public.genesis_valid_verse(coalesce(e, s))
           or coalesce(e, s) < s or (coalesce(e, s) / 1000000) <> (s / 1000000) then
          raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'verses of ' || (b->>'id');
        end if;
      else
        s := null; e := null;
      end if;
      if r->'label' is not null and jsonb_typeof(r->'label') <> 'null'
         and (jsonb_typeof(r->'label') <> 'string' or char_length(r->>'label') > 60) then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'label of ' || (b->>'id');
      end if;
      if r->'quote' is not null and jsonb_typeof(r->'quote') <> 'null'
         and (jsonb_typeof(r->'quote') <> 'string' or char_length(r->>'quote') > 5000) then
        raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'quote of ' || (b->>'id');
      end if;
      total := total + char_length(r->>'raw') + coalesce(char_length(r->>'quote'), 0);
      cleaned := cleaned || jsonb_build_object('ref', jsonb_build_object(
        'raw', r->>'raw',
        'start', s,
        'end', case when s is null then null else coalesce(e, s) end,
        'status', status,
        'label', nullif(btrim(coalesce(r->>'label', '')), ''),
        'quote', nullif(r->>'quote', '')));
    else
      raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'kind of ' || (b->>'id');
    end if;
    out := out || jsonb_build_array(cleaned);
  end loop;
  if total > 200000 then
    raise exception 'invalid_blocks' using errcode = 'P0001', detail = 'too much text';
  end if;
  return out;
end;
$$;

-- What readers get: cleaned blocks, with a quotation's words removed unless
-- its translation may be published ("quote_withheld": true marks where).
create or replace function public.genesis_publishable_blocks(p_blocks jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    case
      when b->>'kind' = 'scripture' and b#>>'{ref,quote}' is not null
           and not public.genesis_quote_publishable(b#>>'{ref,label}')
      then jsonb_set(b, '{ref}', ((b->'ref') - 'quote') || '{"quote": null, "quote_withheld": true}'::jsonb)
      else b
    end order by n), '[]'::jsonb)
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
  new_slug := public.genesis_new_sermon_slug();
  insert into public.church_sermons (group_id, slug, title, created_by)
  values (p_group, new_slug, left(btrim(coalesce(p_title, '')), 200), auth.uid())
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'slug', new_slug, 'draft_version', 0);
end;
$$;

-- Saves the draft and details. p_expected_version must be the version the
-- editor loaded; a stale one raises 'draft_changed' so nobody's edits are
-- overwritten silently. Details keys (all optional): title, speaker, series,
-- preached_on (YYYY-MM-DD or null), time_zone, location, language, audience,
-- cover_alt, cover_decorative. Changing the audience of a published sermon
-- takes effect at once (the Studio confirms first).
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
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  if p_expected_version is distinct from row_.draft_version then
    raise exception 'draft_changed' using errcode = 'P0001', detail = row_.draft_version::text;
  end if;
  blocks := case when p_blocks is null then row_.draft_blocks else public.genesis_clean_sermon_blocks(p_blocks) end;
  if d ? 'language' and (d->>'language') not in ('en', 'es', 'pt', 'other') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'language';
  end if;
  if d ? 'audience' and (d->>'audience') not in ('link', 'members') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'audience';
  end if;
  update public.church_sermons set
    title = case when d ? 'title' then left(btrim(coalesce(d->>'title', '')), 200) else title end,
    speaker = case when d ? 'speaker' then left(btrim(coalesce(d->>'speaker', '')), 120) else speaker end,
    series = case when d ? 'series' then nullif(left(btrim(coalesce(d->>'series', '')), 120), '') else series end,
    preached_on = case when d ? 'preached_on' then (d->>'preached_on')::date else preached_on end,
    time_zone = case when d ? 'time_zone' then nullif(left(btrim(coalesce(d->>'time_zone', '')), 64), '') else time_zone end,
    location = case when d ? 'location' then left(btrim(coalesce(d->>'location', '')), 200) else location end,
    language = coalesce(d->>'language', language),
    audience = coalesce(d->>'audience', audience),
    cover_alt = case when d ? 'cover_alt' then left(btrim(coalesce(d->>'cover_alt', '')), 300) else cover_alt end,
    cover_decorative = case when d ? 'cover_decorative' then coalesce((d->>'cover_decorative')::boolean, false) else cover_decorative end,
    draft_blocks = blocks,
    draft_version = draft_version + 1,
    updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('draft_version', row_.draft_version + 1);
end;
$$;

-- Publishes the draft as it was at p_expected_version, in one transaction.
-- Retrying with the same version returns the revision it already made.
-- Quotations from translations that may not be published are withheld here,
-- whatever the editor sent.
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
  withheld integer;
  new_id uuid;
  new_number integer;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  if p_expected_version is distinct from row_.draft_version then
    raise exception 'draft_changed' using errcode = 'P0001', detail = row_.draft_version::text;
  end if;
  if btrim(row_.title) = '' then raise exception 'needs_title' using errcode = 'P0001'; end if;
  if row_.has_cover and not row_.cover_decorative and btrim(row_.cover_alt) = '' then
    raise exception 'needs_cover_alt' using errcode = 'P0001';
  end if;
  select * into last_ from public.church_sermon_revisions where id = row_.published_revision_id;
  if found and last_.draft_version = row_.draft_version then
    if row_.status <> 'published' then
      update public.church_sermons set status = 'published', published_at = now(), published_by = auth.uid() where id = p_sermon;
    end if;
    return jsonb_build_object('revision', last_.id, 'number', last_.number, 'withheld_quotes', last_.withheld_quotes, 'repeated', true);
  end if;
  blocks := public.genesis_publishable_blocks(row_.draft_blocks);
  if jsonb_array_length(blocks) = 0 then raise exception 'empty_outline' using errcode = 'P0001'; end if;
  select count(*) into withheld from jsonb_array_elements(blocks) b where (b#>>'{ref,quote_withheld}') = 'true';
  select coalesce(max(number), 0) + 1 into new_number from public.church_sermon_revisions where sermon_id = p_sermon;
  insert into public.church_sermon_revisions (sermon_id, number, blocks, draft_version, withheld_quotes, created_by)
  values (p_sermon, new_number, blocks, row_.draft_version, withheld, auth.uid())
  returning id into new_id;
  update public.church_sermons set
    published_revision_id = new_id, status = 'published', published_at = now(), published_by = auth.uid(), updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('revision', new_id, 'number', new_number, 'withheld_quotes', withheld, 'repeated', false);
end;
$$;

create or replace function public.unpublish_church_sermon(p_sermon uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.genesis_editable_sermon(p_sermon);
  update public.church_sermons set status = 'unpublished', updated_at = now()
  where id = p_sermon and status = 'published';
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
  update public.church_sermons set deleted_at = now(), status = 'unpublished', updated_at = now() where id = p_sermon;
end;
$$;

-- A new draft with the same details (no date) and outline, for next week.
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

-- Records whether the sermon has a cover; the file itself goes to
-- sermon-covers/<group id>/<sermon id>.jpg through the Storage API (the
-- policies below), and is removed there when has_cover becomes false.
create or replace function public.set_church_sermon_cover(p_sermon uuid, p_has_cover boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  update public.church_sermons set has_cover = coalesce(p_has_cover, false), updated_at = now() where id = p_sermon;
  return row_.group_id::text || '/' || row_.id::text || '.jpg';
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

-- Whether the caller may read this published sermon now.
create or replace function public.genesis_can_read_sermon(p_row public.church_sermons)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_row.deleted_at is null
    and p_row.status = 'published'
    and p_row.published_revision_id is not null
    and p_row.hidden_at is null
    and public.genesis_church_sermons_on(p_row.group_id)
    and (p_row.audience = 'link' or public.genesis_can_read_member_sermons(p_row.group_id));
$$;

-- The sermon behind a link, for anyone. Returns {"status": "ok", ...} with the
-- published outline, {"status": "members_only"} (never a title or a block)
-- or {"status": "not_found"} (also for a switched-off church, an unpublished,
-- hidden or deleted sermon).
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
  prev_ jsonb;
  next_ jsonb;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9]{10}$' then
    return jsonb_build_object('status', 'not_found');
  end if;
  select * into row_ from public.church_sermons where slug = p_slug;
  if not found or row_.deleted_at is not null or row_.status <> 'published' or row_.hidden_at is not null
     or row_.published_revision_id is null or not public.genesis_church_sermons_on(row_.group_id) then
    return jsonb_build_object('status', 'not_found');
  end if;
  member := public.genesis_can_read_member_sermons(row_.group_id);
  if row_.audience = 'members' and not member then
    return jsonb_build_object('status', 'members_only');
  end if;
  select * into rev from public.church_sermon_revisions where id = row_.published_revision_id;
  select name into church from public.groups where id = row_.group_id;
  if row_.series is not null then
    select jsonb_build_object('slug', s.slug, 'title', s.title) into prev_
    from public.church_sermons s
    where s.group_id = row_.group_id and s.series = row_.series and s.id <> row_.id
      and public.genesis_can_read_sermon(s)
      and (s.preached_on, s.published_at) < (row_.preached_on, row_.published_at)
    order by s.preached_on desc nulls last, s.published_at desc limit 1;
    select jsonb_build_object('slug', s.slug, 'title', s.title) into next_
    from public.church_sermons s
    where s.group_id = row_.group_id and s.series = row_.series and s.id <> row_.id
      and public.genesis_can_read_sermon(s)
      and (s.preached_on, s.published_at) > (row_.preached_on, row_.published_at)
    order by s.preached_on asc nulls last, s.published_at asc limit 1;
  end if;
  return jsonb_build_object(
    'status', 'ok',
    'id', row_.id,
    'slug', row_.slug,
    'group_id', row_.group_id,
    'church', church,
    'title', row_.title,
    'speaker', row_.speaker,
    'series', row_.series,
    'preached_on', row_.preached_on,
    'time_zone', row_.time_zone,
    'location', row_.location,
    'language', row_.language,
    'audience', row_.audience,
    'cover', case when row_.has_cover then jsonb_build_object(
      'path', row_.group_id::text || '/' || row_.id::text || '.jpg',
      'alt', case when row_.cover_decorative then '' else row_.cover_alt end,
      'decorative', row_.cover_decorative) end,
    'revision', rev.number,
    'published_at', row_.published_at,
    'blocks', rev.blocks,
    'previous', prev_,
    'next', next_,
    'is_member', member);
end;
$$;

-- A church's sermons: published ones for members, drafts too for leaders.
-- No outlines here (published_sermon gives one).
create or replace function public.group_sermons(p_group uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  leader boolean := public.genesis_can_edit_sermons(p_group);
begin
  if not leader and not public.genesis_can_read_member_sermons(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id, 'slug', s.slug, 'title', s.title, 'speaker', s.speaker, 'series', s.series,
      'preached_on', s.preached_on, 'audience', s.audience, 'status', s.status,
      'hidden', s.hidden_at is not null, 'has_cover', s.has_cover, 'published_at', s.published_at,
      'draft_version', case when leader then s.draft_version end)
      order by s.preached_on desc nulls first, s.created_at desc)
    from public.church_sermons s
    where s.group_id = p_group and s.deleted_at is null
      and (leader or public.genesis_can_read_sermon(s))
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
  q text := regexp_replace(lower(translate(btrim(coalesce(p_query, '')), 'ÁÉÍÓÚÜáéíóúüÑñÇçÃãÕõÂâÊêÔô', 'AEIOUUaeiouuNnCcAaOoAaEeOo')), '\s+', ' ', 'g');
begin
  if char_length(q) < 2 or char_length(q) > 60 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(c order by c->>'name')
    from (
      select jsonb_build_object(
        'group_id', g.id,
        'name', g.name,
        'sermons', coalesce((
          select jsonb_agg(jsonb_build_object('slug', s.slug, 'title', s.title, 'preached_on', s.preached_on)
                           order by s.preached_on desc nulls last, s.published_at desc)
          from (select * from public.church_sermons s2
                where s2.group_id = g.id and s2.audience = 'link' and public.genesis_can_read_sermon(s2)
                order by s2.preached_on desc nulls last, s2.published_at desc limit 5) s
        ), '[]'::jsonb)) as c
      from public.groups g
      where g.deleted_at is null and g.sermons_listed and public.genesis_church_sermons_on(g.id)
        and position(q in regexp_replace(lower(translate(g.name, 'ÁÉÍÓÚÜáéíóúüÑñÇçÃãÕõÂâÊêÔô', 'AEIOUUaeiouuNnCcAaOoAaEeOo')), '\s+', ' ', 'g')) > 0
      limit 20
    ) found
  ), '[]'::jsonb);
end;
$$;

-- Reports ----------------------------------------------------------------------------

-- Any signed-in reader of a published sermon can report it, once. Three
-- reports from different people hide it until a moderator reviews it.
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
  select * into row_ from public.church_sermons where slug = p_slug;
  if not found or not public.genesis_can_read_sermon(row_) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  insert into public.church_sermon_reports (sermon_id, reporter, reason)
  values (row_.id, auth.uid(), left(coalesce(p_reason, ''), 500))
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
      select s.id, s.slug, s.title, s.hidden_at is not null as hidden, count(*) as report_count,
             array_remove(array_agg(nullif(r.reason, '') order by r.created_at), null) as reasons,
             max(r.created_at) as last_reported_at
      from public.church_sermons s
      join public.church_sermon_reports r on r.sermon_id = s.id and r.resolved_at is null
      where s.group_id = p_group and s.deleted_at is null
      group by s.id
    ) x
  ), '[]'::jsonb);
end;
$$;

-- Keep (show it again) or take it down (unpublish); either closes the reports.
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
    update public.church_sermons set hidden_at = null, status = 'unpublished', updated_at = now()
    where id = p_sermon and status = 'published';
  end if;
end;
$$;

-- Counts (sermon-events Edge Function only) ------------------------------------------------

-- Returns true when the event was counted. p_visitor is the function's
-- daily-salted HMAC (64 hex); nothing else about the visitor is stored.
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
  if p_kind not in ('open', 'passage', 'save') or p_visitor is null or p_visitor !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  select * into row_ from public.church_sermons where slug = p_slug;
  if not found or row_.deleted_at is not null or row_.status <> 'published'
     or not public.genesis_church_sermons_on(row_.group_id) then
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

-- Leaders upload, replace and remove <group id>/<sermon id>.jpg for their
-- church's own sermons. Nobody reads directly: readers get signed links.
create or replace function public.genesis_can_edit_cover(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
    and exists (
      select 1 from public.church_sermons s
      where s.group_id::text = split_part(p_name, '/', 1)
        and s.id::text || '.jpg' = split_part(p_name, '/', 2)
        and s.deleted_at is null
        and public.genesis_can_edit_sermons(s.group_id));
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders add') then
    create policy "Sermon covers: leaders add" on storage.objects for insert to authenticated
      with check (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders replace') then
    create policy "Sermon covers: leaders replace" on storage.objects for update to authenticated
      using (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name))
      with check (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders remove') then
    create policy "Sermon covers: leaders remove" on storage.objects for delete to authenticated
      using (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name));
  end if;
  -- Upserts read the existing object first.
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders see') then
    create policy "Sermon covers: leaders see" on storage.objects for select to authenticated
      using (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name));
  end if;
end;
$$;

-- Cover files with no sermon that has a cover (deleted, removed or never
-- saved), for the nightly sweep (service role). Older than a day only, so an
-- upload in progress is never swept.
create or replace function public.orphan_sermon_covers()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select o.name from storage.objects o
  where o.bucket_id = 'sermon-covers'
    and o.created_at < now() - interval '1 day'
    and not exists (
      select 1 from public.church_sermons s
      where s.group_id::text = split_part(o.name, '/', 1)
        and s.id::text || '.jpg' = split_part(o.name, '/', 2)
        and s.has_cover and s.deleted_at is null);
$$;

-- Grants -------------------------------------------------------------------------------

revoke all on function public.genesis_church_sermons_on(uuid) from public, anon;
revoke all on function public.genesis_can_edit_sermons(uuid) from public, anon;
revoke all on function public.genesis_can_read_member_sermons(uuid) from public, anon;
revoke all on function public.genesis_can_read_sermon(public.church_sermons) from public, anon, authenticated;
revoke all on function public.genesis_editable_sermon(uuid) from public, anon, authenticated;
revoke all on function public.genesis_new_sermon_slug() from public, anon, authenticated;
revoke all on function public.genesis_can_edit_cover(text) from public, anon;
revoke all on function public.create_church_sermon(uuid, text) from public, anon;
revoke all on function public.save_church_sermon(uuid, integer, jsonb, jsonb) from public, anon;
revoke all on function public.publish_church_sermon(uuid, integer) from public, anon;
revoke all on function public.unpublish_church_sermon(uuid) from public, anon;
revoke all on function public.delete_church_sermon(uuid) from public, anon;
revoke all on function public.duplicate_church_sermon(uuid) from public, anon;
revoke all on function public.set_church_sermon_cover(uuid, boolean) from public, anon;
revoke all on function public.set_sermons_listed(uuid, boolean) from public, anon;
revoke all on function public.group_sermons(uuid) from public, anon;
revoke all on function public.report_church_sermon(text, text) from public, anon;
revoke all on function public.group_sermon_reports(uuid) from public, anon;
revoke all on function public.review_church_sermon_reports(uuid, boolean) from public, anon;
revoke all on function public.record_sermon_event(text, text, text) from public, anon, authenticated;
revoke all on function public.orphan_sermon_covers() from public, anon, authenticated;

grant execute on function public.genesis_church_sermons_on(uuid) to authenticated;
grant execute on function public.genesis_can_edit_sermons(uuid) to authenticated;
grant execute on function public.genesis_can_read_member_sermons(uuid) to authenticated;
grant execute on function public.genesis_can_edit_cover(text) to authenticated;
grant execute on function public.create_church_sermon(uuid, text) to authenticated;
grant execute on function public.save_church_sermon(uuid, integer, jsonb, jsonb) to authenticated;
grant execute on function public.publish_church_sermon(uuid, integer) to authenticated;
grant execute on function public.unpublish_church_sermon(uuid) to authenticated;
grant execute on function public.delete_church_sermon(uuid) to authenticated;
grant execute on function public.duplicate_church_sermon(uuid) to authenticated;
grant execute on function public.set_church_sermon_cover(uuid, boolean) to authenticated;
grant execute on function public.set_sermons_listed(uuid, boolean) to authenticated;
grant execute on function public.group_sermons(uuid) to authenticated;
grant execute on function public.report_church_sermon(text, text) to authenticated;
grant execute on function public.group_sermon_reports(uuid) to authenticated;
grant execute on function public.review_church_sermon_reports(uuid, boolean) to authenticated;
grant execute on function public.published_sermon(text) to anon, authenticated;
grant execute on function public.search_sermon_churches(text) to anon, authenticated;
grant execute on function public.record_sermon_event(text, text, text) to service_role;
grant execute on function public.orphan_sermon_covers() to service_role;

comment on table public.church_sermons is
  'Church sermons (VRS-18). Read through published_sermon / group_sermons; written through the *_church_sermon functions. Blocks hold the church''s own words and verse ids; quotations from translations that may not be published are withheld on publish.';
comment on column public.groups.sermons_enabled is
  'Church sermons pilot switch for this church. Set by the owner only (dashboard).';
