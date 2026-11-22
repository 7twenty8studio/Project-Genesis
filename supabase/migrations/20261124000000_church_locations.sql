-- Church sermons (VRS-18): Locations and Times.
--
-- Like an event in the YouVersion Bible App, a sermon page now shows where and
-- when its church or ministry meets (owner, 21 November 2026), and ends with
-- an invitation to come ("Join us for …").
--   * groups.sermon_locations: up to 10 places, each {"name", "address",
--     "times"} (plain text; times one line per service). They belong to the
--     church, not to one sermon, so they show on every sermon at once and
--     change without publishing again.
--   * set_church_locations(group, locations): owner and moderators only,
--     while sermons are on (genesis_can_edit_sermons). Refuses anything that
--     isn't that shape ('invalid_locations'), never cuts text.
--   * published_sermon() adds "locations" (same readers as the sermon:
--     members-only sermons give nothing to others), and my_sermon_churches()
--     adds them for Church Studio.
-- Explicit statements, no drops.

alter table public.groups add column if not exists sermon_locations jsonb not null default '[]'::jsonb;

-- Cleans a list of locations: trimmed text, empty address/times as "", at
-- most 10 places. Raises 'invalid_locations' (detail says why) otherwise.
create or replace function public.genesis_clean_church_locations(p_locations jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  item jsonb;
  k text;
  name_ text;
  address_ text;
  times_ text;
  cleaned jsonb := '[]'::jsonb;
begin
  if p_locations is null or jsonb_typeof(p_locations) <> 'array' then
    raise exception 'invalid_locations' using errcode = 'P0001', detail = 'not a list';
  end if;
  if jsonb_array_length(p_locations) > 10 then
    raise exception 'invalid_locations' using errcode = 'P0001', detail = 'more than 10';
  end if;
  for item in select value from jsonb_array_elements(p_locations) loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'invalid_locations' using errcode = 'P0001', detail = 'not an object';
    end if;
    for k in select jsonb_object_keys(item) loop
      if k not in ('name', 'address', 'times') then
        raise exception 'invalid_locations' using errcode = 'P0001', detail = 'unknown field ' || k;
      end if;
      if jsonb_typeof(item->k) not in ('string', 'null') then
        raise exception 'invalid_locations' using errcode = 'P0001', detail = k;
      end if;
    end loop;
    name_ := btrim(coalesce(item->>'name', ''));
    address_ := btrim(coalesce(item->>'address', ''));
    times_ := btrim(coalesce(item->>'times', ''));
    if char_length(name_) not between 1 and 80 then
      raise exception 'invalid_locations' using errcode = 'P0001', detail = 'name';
    end if;
    if char_length(address_) > 200 then
      raise exception 'invalid_locations' using errcode = 'P0001', detail = 'address';
    end if;
    if char_length(times_) > 300 then
      raise exception 'invalid_locations' using errcode = 'P0001', detail = 'times';
    end if;
    cleaned := cleaned || jsonb_build_array(jsonb_build_object('name', name_, 'address', address_, 'times', times_));
  end loop;
  return cleaned;
end;
$$;

-- Saves a church's Locations and Times (the whole list). Owner and moderators.
create or replace function public.set_church_locations(p_group uuid, p_locations jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleaned jsonb;
begin
  if not public.genesis_can_edit_sermons(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  cleaned := public.genesis_clean_church_locations(p_locations);
  update public.groups set sermon_locations = cleaned where id = p_group;
  return cleaned;
end;
$$;

-- The churches the caller can publish for, now with their locations.
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
      'listed', g.sermons_listed,
      'locations', g.sermon_locations)
    order by lower(g.name)), '[]'::jsonb)
  from public.groups g
  join public.group_members m on m.group_id = g.id and m.user_id = auth.uid() and m.role = 'leader'
  where g.deleted_at is null and public.genesis_can_edit_sermons(g.id);
$$;

-- The sermon behind a link, for anyone (as in 20261120000000, plus the
-- church's "locations"). Returns {"status": "ok", ...} with the
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
  locations_ jsonb;
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
  select name, sermon_locations into church, locations_ from public.groups where id = row_.group_id;
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
    'locations', coalesce(locations_, '[]'::jsonb),
    'is_member', member);
end;
$$;

revoke all on function public.genesis_clean_church_locations(jsonb) from public, anon, authenticated;
revoke all on function public.set_church_locations(uuid, jsonb) from public, anon;
revoke all on function public.my_sermon_churches() from public, anon;

grant execute on function public.set_church_locations(uuid, jsonb) to authenticated;
grant execute on function public.my_sermon_churches() to authenticated;
grant execute on function public.published_sermon(text) to anon, authenticated;
