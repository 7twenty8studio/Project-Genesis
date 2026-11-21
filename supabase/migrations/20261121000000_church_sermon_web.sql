-- Church sermons on the web (VRS-18, checkpoint 2): what Church Studio and the
-- guest page at versely.7twenty8studio.com need beyond 20261120000000.
--
--   * Covers: no client can read the sermon-covers bucket. Storage would let
--     anyone with a SELECT policy create a signed link, and a signed link
--     keeps working after an unpublish, a ban or a restriction, so there is
--     no SELECT policy for anon or authenticated at all (the leaders' one
--     from 20261120000000 is switched off below). Covers are served only by
--     the sermon-cover Edge Function: it asks sermon_cover_access() as the
--     caller on every request and only then downloads the file with the
--     service role. Leaders keep their INSERT policy, which uploads need
--     (an upload without upsert needs INSERT only).
--   * Import review: church_sermons.draft_review keeps the leader's answers
--     to the import review with the draft (and its version), and
--     publish_church_sermon refuses while an item is open.
--   * my_sermon_churches(): the churches the signed-in person can publish
--     for, for Studio's church picker.
--
-- Explicit statements, no drops; safe to run again.

-- Covers for readers ---------------------------------------------------------------

-- The name is the live published cover of a sermon the caller may read now.
create or replace function public.genesis_can_read_cover(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
    and exists (
      select 1 from public.church_sermons s
      join public.church_sermon_revisions r on r.id = s.published_revision_id
      where s.id::text = split_part(p_name, '/', 2)
        and s.group_id::text = split_part(p_name, '/', 1)
        and r.details#>>'{cover,path}' = p_name
        and public.genesis_can_read_sermon(s));
$$;

-- What the caller may do with a cover now: 'edit' (a leader of its church,
-- any cover of the sermon), 'read' (the live published cover of a sermon the
-- caller may read), or null. The sermon-cover function asks this as the
-- caller before every download.
create or replace function public.sermon_cover_access(p_name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_name is null then null
    when public.genesis_can_edit_cover(p_name) then 'edit'
    when public.genesis_can_read_cover(p_name) then 'read'
  end;
$$;

-- No client reads the bucket directly (no signed links): switch off any
-- SELECT policy on sermon covers. Altered, not dropped.
do $$
begin
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: leaders see') then
    alter policy "Sermon covers: leaders see" on storage.objects using (false);
  end if;
  if exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: readers see') then
    alter policy "Sermon covers: readers see" on storage.objects using (false);
  end if;
end;
$$;

-- Import review with the draft ------------------------------------------------------

-- The leader's import review ({"items": [...], "decisions": {key: answer}}),
-- saved with the draft so it follows the sermon to any computer or leader
-- and Publish can be refused on the server while an item is open.
alter table public.church_sermons add column if not exists draft_review jsonb;

-- A review as Studio sends it, checked: an object with "items" (at most 500,
-- each with a key and a known kind; references and quotations name their
-- block) and "decisions" (kept, fixed or dismissed); 256 kB at most. Null
-- (no review) stays null.
create or replace function public.genesis_clean_sermon_review(p_review jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  item jsonb;
  k text;
begin
  if p_review is null or jsonb_typeof(p_review) = 'null' then return null; end if;
  if jsonb_typeof(p_review) <> 'object'
     or jsonb_typeof(p_review->'items') is distinct from 'array'
     or jsonb_typeof(coalesce(p_review->'decisions', '{}'::jsonb)) <> 'object'
     or jsonb_array_length(p_review->'items') > 500
     or octet_length(p_review::text) > 262144 then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'review';
  end if;
  for k in select jsonb_object_keys(p_review) loop
    if k not in ('items', 'decisions') then
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'review';
    end if;
  end loop;
  for item in select value from jsonb_array_elements(p_review->'items') loop
    if jsonb_typeof(item) <> 'object'
       or jsonb_typeof(item->'key') is distinct from 'string'
       or char_length(item->>'key') not between 1 and 200
       or coalesce(item->>'kind', '') not in ('missing', 'note', 'reference', 'quotation')
       or (item->>'kind' in ('reference', 'quotation')
           and (jsonb_typeof(item->'blockId') is distinct from 'string' or char_length(item->>'blockId') not between 1 and 64)) then
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'review item';
    end if;
  end loop;
  for k in select jsonb_object_keys(coalesce(p_review->'decisions', '{}'::jsonb)) loop
    if coalesce(p_review->'decisions'->>k, '') not in ('kept', 'fixed', 'dismissed') then
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'review decision';
    end if;
  end loop;
  return jsonb_build_object('items', p_review->'items', 'decisions', coalesce(p_review->'decisions', '{}'::jsonb));
end;
$$;

-- How many review items still need an answer before publishing: none for an
-- informational note that found nothing, a reference whose block is no
-- longer ambiguous (or is gone), or a quotation whose block is now a
-- Scripture block (or is gone). The same rule as Studio's reviewDone and
-- stillOpen (web/src/lib/import/review.ts).
create or replace function public.genesis_review_open(p_review jsonb, p_blocks jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer
  from jsonb_array_elements(case when jsonb_typeof(p_review->'items') = 'array' then p_review->'items' else '[]'::jsonb end) i
  where coalesce(p_review->'decisions'->>(i->>'key'), '') not in ('kept', 'fixed', 'dismissed')
    and not (i->>'kind' = 'note' and coalesce(i#>>'{note,count}', '0') = '0')
    and not (i->>'kind' = 'reference' and not exists (
      select 1 from jsonb_array_elements(p_blocks) b
      where b->>'id' = i->>'blockId' and b->>'kind' = 'scripture' and b#>>'{ref,status}' = 'ambiguous'))
    and not (i->>'kind' = 'quotation' and not exists (
      select 1 from jsonb_array_elements(p_blocks) b
      where b->>'id' = i->>'blockId' and b->>'kind' <> 'scripture'));
$$;

-- save_church_sermon as in 20261120000000, plus the "review" detail.
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
  review_ jsonb;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  perform public.genesis_check_version(row_, p_expected_version);
  if jsonb_typeof(d) is distinct from 'object' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'not an object';
  end if;
  for k in select jsonb_object_keys(d) loop
    if k not in ('title', 'speaker', 'series', 'preached_on', 'time_zone', 'location', 'language', 'audience', 'cover', 'cover_alt', 'cover_decorative', 'review') then
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
  review_ := case when d ? 'review' then public.genesis_clean_sermon_review(d->'review') else row_.draft_review end;
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
    draft_review = review_,
    draft_version = draft_version + 1,
    updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('draft_version', row_.draft_version + 1);
end;
$$;

-- publish_church_sermon as in 20261120000000, plus review_open.
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
  if public.genesis_review_open(row_.draft_review, row_.draft_blocks) > 0 then
    raise exception 'review_open' using errcode = 'P0001';
  end if;
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

-- Unpublish and Members only also say which draft version they moved on
-- from, so an editor can tell whether its own copy was still the latest
-- (previous_version = the version it loaded or last saved) before adopting
-- the new version; otherwise the draft changed elsewhere and the editor must
-- not save its older copy on top. As in 20261120000000 otherwise.
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
  return jsonb_build_object('draft_version', row_.draft_version + 1, 'previous_version', row_.draft_version);
end;
$$;

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
  return jsonb_build_object('draft_version', row_.draft_version + 1, 'previous_version', row_.draft_version);
end;
$$;

-- A duplicate keeps the import review (with its answers): an item still
-- open on the original is still open on the copy, so the copy can't be
-- published past it. As in 20261120000000 otherwise.
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
  insert into public.church_sermons (group_id, slug, title, speaker, series, time_zone, location, language, audience, draft_blocks, draft_review, created_by)
  values (row_.group_id, new_slug, row_.title, row_.speaker, row_.series, row_.time_zone, row_.location, row_.language, row_.audience, row_.draft_blocks, row_.draft_review, auth.uid())
  returning id into new_id;
  return jsonb_build_object('id', new_id, 'slug', new_slug, 'draft_version', 0);
end;
$$;

-- Studio ---------------------------------------------------------------------------

-- The churches the caller can publish for (owner or moderator, both switches
-- on, not banned), by name.
create or replace function public.my_sermon_churches()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', g.id,
      'name', g.name,
      'role', case when g.owner_id = auth.uid() then 'owner' else 'moderator' end,
      'listed', g.sermons_listed)
    order by lower(g.name)), '[]'::jsonb)
  from public.groups g
  join public.group_members m on m.group_id = g.id and m.user_id = auth.uid() and m.role = 'leader'
  where g.deleted_at is null and public.genesis_can_edit_sermons(g.id);
$$;

-- Grants -------------------------------------------------------------------------------

revoke all on function public.genesis_can_read_cover(text) from public, anon, authenticated;
revoke all on function public.sermon_cover_access(text) from public;
revoke all on function public.my_sermon_churches() from public, anon;
revoke all on function public.genesis_clean_sermon_review(jsonb) from public, anon, authenticated;
revoke all on function public.genesis_review_open(jsonb, jsonb) from public, anon, authenticated;

grant execute on function public.sermon_cover_access(text) to anon, authenticated;
grant execute on function public.my_sermon_churches() to authenticated;
