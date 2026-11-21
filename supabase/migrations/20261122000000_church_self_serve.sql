-- Church sermons (VRS-18): churches start on their own in Church Studio.
--
-- Until now sermons were turned on for each pilot church by hand
-- (groups.sermons_enabled in the dashboard), so a pastor who signed in to
-- Church Studio met a dead end. With the `church_self_serve` switch on
-- (owner, 21 November 2026: on for the proof of concept):
--   * create_sermon_church(name, your_name) makes a church group owned by the
--     signed-in person, with sermons on. It's an ordinary Versely group:
--     members join with its invite code in the app.
--   * my_groups_for_sermons() lists the groups the person owns whose sermons
--     are off, and set_church_sermons(group, on) lets that owner turn them on
--     (or off) from Church Studio.
-- Everything else stays as it was: both switches (church_sermons, groups)
-- still gate every read and write, a church stays unlisted in search until
-- its owner lists it, and reports reach its moderators and the ops dashboard.
-- Turning church_self_serve off stops new churches; existing ones keep going.
-- Explicit statements, no drops.

insert into public.feature_flags (key, enabled, description)
values ('church_self_serve', true, 'Church sermons (VRS-18): anyone signed in can start a church in Church Studio, or turn sermons on for a group they own. Off: only the dashboard turns sermons on.')
on conflict (key) do nothing;

-- Self-serve is open: church sermons, groups and self-serve all on.
create or replace function public.genesis_church_self_serve_on()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.genesis_feature_on('church_sermons')
    and public.genesis_feature_on('groups')
    and public.genesis_feature_on('church_self_serve');
$$;

-- Starts a church: a group owned by the caller with sermons on. `p_your_name`
-- is the caller's display name in Versely, needed only when they have none yet
-- (someone who has never used Groups in the app). Returns {"id", "name"}.
create or replace function public.create_sermon_church(p_name text, p_your_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  cleaned_name text := btrim(coalesce(p_name, ''));
  member_name text;
  new_id uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_church_self_serve_on() then raise exception 'not_allowed' using errcode = 'P0001'; end if;

  select display_name into member_name from public.profiles where user_id = auth.uid();
  if member_name is null then
    member_name := btrim(coalesce(p_your_name, ''));
    if char_length(member_name) not between 1 and 40 then raise exception 'name_required' using errcode = 'P0001'; end if;
    if public.genesis_is_objectionable(member_name) then raise exception 'objectionable_content' using errcode = 'P0001'; end if;
    insert into public.profiles (user_id, display_name) values (auth.uid(), member_name)
    on conflict (user_id) do update set display_name = excluded.display_name, updated_at = now();
  end if;

  perform public.genesis_check_group(cleaned_name, '', null, null, null, null);
  -- A church a day at most three times, and the app's 20 groups in all.
  if (select count(*) from public.groups where created_by = auth.uid() and created_at > now() - interval '1 day') >= 3 then
    raise exception 'too_many_churches' using errcode = 'P0001';
  end if;
  if (select count(*) from public.groups where created_by = auth.uid() and deleted_at is null) >= 20 then
    raise exception 'too_many_groups' using errcode = 'P0001';
  end if;

  insert into public.groups (name, description, invite_code, created_by, owner_id, sermons_enabled)
  values (cleaned_name, '', public.genesis_new_invite_code(), auth.uid(), auth.uid(), true)
  returning id into new_id;
  insert into public.group_members (group_id, user_id, role, display_name)
  values (new_id, auth.uid(), 'leader', member_name);

  return jsonb_build_object('id', new_id, 'name', cleaned_name);
end;
$$;

-- The caller's own groups whose sermons are off, for Church Studio's
-- "Turn on sermons" list. Empty while self-serve is off.
create or replace function public.my_groups_for_sermons()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name) order by lower(g.name)), '[]'::jsonb)
  from public.groups g
  where g.owner_id = auth.uid()
    and g.deleted_at is null
    and not g.sermons_enabled
    and public.genesis_church_self_serve_on();
$$;

-- The owner (only the owner) turns sermons on or off for their group.
-- Turning them off hides the church's sermons everywhere; nothing is deleted.
create or replace function public.set_church_sermons(p_group uuid, p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_church_self_serve_on()
     or not exists (select 1 from public.groups where id = p_group and owner_id = auth.uid() and deleted_at is null) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  update public.groups set sermons_enabled = coalesce(p_on, false) where id = p_group;
end;
$$;

revoke all on function public.genesis_church_self_serve_on() from public, anon, authenticated;
revoke all on function public.create_sermon_church(text, text) from public, anon;
revoke all on function public.my_groups_for_sermons() from public, anon;
revoke all on function public.set_church_sermons(uuid, boolean) from public, anon;

grant execute on function public.create_sermon_church(text, text) to authenticated;
grant execute on function public.my_groups_for_sermons() to authenticated;
grant execute on function public.set_church_sermons(uuid, boolean) to authenticated;
