-- Genesis: the last part of the group moderation and challenges update.
-- Supabase SQL Editor -> New query -> paste -> Run. Safe to re-run.

create or replace function public.review_group_report(p_type text, p_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_group uuid;
begin
  if p_action not in ('remove', 'keep') then raise exception 'invalid_action' using errcode = 'P0001'; end if;
  if p_type = 'group_prayer' then
    select group_id into owner_group from public.group_prayers where id = p_id;
  elsif p_type = 'group_post' then
    select group_id into owner_group from public.group_posts where id = p_id;
  elsif p_type = 'group_announcement' then
    select group_id into owner_group from public.group_announcements where id = p_id;
  else
    raise exception 'invalid_type' using errcode = 'P0001';
  end if;
  if owner_group is null or not public.genesis_is_leader(owner_group) then
    raise exception 'moderators_only' using errcode = 'P0001';
  end if;

  if p_type = 'group_prayer' then
    update public.group_prayers
    set deleted_at = case when p_action = 'remove' then now() else deleted_at end, hidden_at = null
    where id = p_id;
  elsif p_type = 'group_post' then
    update public.group_posts
    set deleted_at = case when p_action = 'remove' then now() else deleted_at end, hidden_at = null
    where id = p_id;
  elsif p_action = 'remove' then
    update public.group_announcements set deleted_at = now() where id = p_id;
  end if;
  -- Removed: the reports are closed. Kept: they're cleared, so the same
  -- people can report it again if it becomes a problem (each person can
  -- report an item once).
  if p_action = 'remove' then
    update public.content_reports set resolved_at = now()
    where content_type = p_type and content_id = p_id and resolved_at is null;
  else
    delete from public.content_reports
    where content_type = p_type and content_id = p_id and resolved_at is null;
  end if;
end;
$$;

create or replace function public.request_to_join_group(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  found_id uuid;
  found_name text;
  needs_approval boolean;
  member_name text;
  cleaned text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_feature_on('groups') then raise exception 'groups_off' using errcode = 'P0001'; end if;
  select display_name into member_name from public.profiles where user_id = auth.uid();
  if member_name is null then raise exception 'name_required' using errcode = 'P0001', hint = 'Choose a display name first.'; end if;
  select id, name, requires_approval into found_id, found_name, needs_approval
  from public.groups where invite_code = cleaned and deleted_at is null;
  if found_id is null then raise exception 'invalid_code' using errcode = 'P0001', hint = 'That invite code wasn''t found. Check it with your group leader.'; end if;
  if exists (select 1 from public.group_bans where group_id = found_id and user_id = auth.uid()) then
    raise exception 'banned' using errcode = 'P0001', hint = 'You can''t join this group.';
  end if;
  if exists (select 1 from public.group_members where group_id = found_id and user_id = auth.uid()) then
    delete from public.group_join_requests where group_id = found_id and user_id = auth.uid();
    return jsonb_build_object('group_id', found_id, 'name', found_name, 'status', 'joined');
  end if;
  if (select count(*) from public.group_members where group_id = found_id) >= 500 then
    raise exception 'group_full' using errcode = 'P0001';
  end if;

  if needs_approval then
    if exists (select 1 from public.group_join_requests where group_id = found_id and user_id = auth.uid()) then
      return jsonb_build_object('group_id', found_id, 'name', found_name, 'status', 'requested');
    end if;
    if (select count(*) from public.group_join_requests where user_id = auth.uid()) >= 20 then
      raise exception 'too_many_requests' using errcode = 'P0001';
    end if;
    insert into public.group_join_requests (group_id, user_id, display_name, group_name)
    values (found_id, auth.uid(), member_name, found_name)
    on conflict (group_id, user_id) do nothing;
    return jsonb_build_object('group_id', found_id, 'name', found_name, 'status', 'requested');
  end if;

  insert into public.group_members (group_id, user_id, role, display_name)
  values (found_id, auth.uid(), 'member', member_name)
  on conflict (group_id, user_id) do nothing;
  delete from public.group_join_requests where group_id = found_id and user_id = auth.uid();
  return jsonb_build_object('group_id', found_id, 'name', found_name, 'status', 'joined');
end;
$$;

create or replace function public.answer_join_request(p_group uuid, p_user uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_name text;
begin
  if not public.genesis_is_leader(p_group) then raise exception 'moderators_only' using errcode = 'P0001'; end if;
  delete from public.group_join_requests where group_id = p_group and user_id = p_user
  returning display_name into member_name;
  if member_name is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if p_accept then
    if exists (select 1 from public.group_bans where group_id = p_group and user_id = p_user) then
      raise exception 'banned' using errcode = 'P0001';
    end if;
    if (select count(*) from public.group_members where group_id = p_group) >= 500 then
      raise exception 'group_full' using errcode = 'P0001';
    end if;
    member_name := coalesce((select p.display_name from public.profiles p where p.user_id = p_user), member_name);
    insert into public.group_members (group_id, user_id, role, display_name)
    values (p_group, p_user, 'member', coalesce(member_name, 'Member'))
    on conflict (group_id, user_id) do nothing;
  end if;
end;
$$;

create or replace function public.set_group_approval(p_group uuid, p_required boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then raise exception 'moderators_only' using errcode = 'P0001'; end if;
  update public.groups set requires_approval = coalesce(p_required, false), updated_at = now() where id = p_group;
  -- Opening the group lets in everyone already waiting (up to the 500 cap).
  if not coalesce(p_required, false) then
    insert into public.group_members (group_id, user_id, role, display_name)
    select r.group_id, r.user_id, 'member', coalesce(p.display_name, r.display_name)
    from public.group_join_requests r
    left join public.profiles p on p.user_id = r.user_id
    where r.group_id = p_group
      and not exists (select 1 from public.group_bans b where b.group_id = r.group_id and b.user_id = r.user_id)
    order by r.created_at
    limit greatest(0, 500 - (select count(*) from public.group_members where group_id = p_group))
    on conflict (group_id, user_id) do nothing;
    delete from public.group_join_requests where group_id = p_group;
  end if;
end;
$$;

create or replace function public.leave_group(p_group uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  delete from public.group_members where group_id = p_group and user_id = auth.uid();
  if not exists (select 1 from public.group_members where group_id = p_group) then
    update public.groups set deleted_at = now(), updated_at = now() where id = p_group;
  end if;
end;
$$;

create or replace function public.remove_member(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_user = auth.uid() then raise exception 'use_leave' using errcode = 'P0001'; end if;
  if not public.genesis_can_moderate(p_group, p_user) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  delete from public.group_members where group_id = p_group and user_id = p_user;
  -- A new code, so the person can't simply rejoin with the old one.
  update public.groups set invite_code = public.genesis_new_invite_code(), updated_at = now() where id = p_group;
end;
$$;

create or replace function public.ban_member(p_group uuid, p_user uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  member_name text;
begin
  if p_user = auth.uid() then raise exception 'use_leave' using errcode = 'P0001'; end if;
  if not public.genesis_can_moderate(p_group, p_user) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if char_length(coalesce(p_reason, '')) > 300 then raise exception 'invalid_reason' using errcode = 'P0001'; end if;
  select display_name into member_name from public.group_members where group_id = p_group and user_id = p_user;
  if member_name is null then
    select display_name into member_name from public.group_join_requests where group_id = p_group and user_id = p_user;
  end if;
  if member_name is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  insert into public.group_bans (group_id, user_id, display_name, banned_by, reason)
  values (p_group, p_user, member_name, auth.uid(), coalesce(p_reason, ''))
  on conflict (group_id, user_id) do update set reason = excluded.reason, banned_by = excluded.banned_by, created_at = now();
  delete from public.group_members where group_id = p_group and user_id = p_user;
  delete from public.group_join_requests where group_id = p_group and user_id = p_user;
end;
$$;

create or replace function public.unban_member(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then raise exception 'moderators_only' using errcode = 'P0001'; end if;
  delete from public.group_bans where group_id = p_group and user_id = p_user;
end;
$$;

create or replace function public.set_challenge_checkin(p_challenge uuid, p_item integer, p_done boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.group_challenges%rowtype;
  today_index integer;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  select * into c from public.group_challenges where id = p_challenge and deleted_at is null;
  if c.id is null or not public.genesis_is_member(c.group_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  if current_date < c.starts_on - 1 then raise exception 'not_started' using errcode = 'P0001'; end if;
  if c.ended_at is not null or current_date > c.starts_on + c.days then raise exception 'challenge_ended' using errcode = 'P0001'; end if;

  today_index := current_date - c.starts_on + 1;
  if (c.kind = 'reading' and not (p_item = any (c.chapters)))
     or (c.kind = 'memorise' and p_item <> 1)
     or (c.kind in ('streak', 'prayer') and (p_item not between 1 and c.days or p_item > today_index + 1)) then
    raise exception 'invalid_item' using errcode = 'P0001';
  end if;

  if coalesce(p_done, false) then
    insert into public.group_challenge_checkins (challenge_id, group_id, user_id, item)
    values (c.id, c.group_id, auth.uid(), p_item)
    on conflict (challenge_id, user_id, item) do nothing;
  else
    delete from public.group_challenge_checkins
    where challenge_id = c.id and user_id = auth.uid() and item = p_item;
  end if;
end;
$$;

revoke all on function public.review_group_report(text, uuid, text) from public, anon;

revoke all on function public.request_to_join_group(text) from public, anon;

revoke all on function public.answer_join_request(uuid, uuid, boolean) from public, anon;

revoke all on function public.set_group_approval(uuid, boolean) from public, anon;

revoke all on function public.ban_member(uuid, uuid, text) from public, anon;

revoke all on function public.unban_member(uuid, uuid) from public, anon;

revoke all on function public.set_challenge_checkin(uuid, integer, boolean) from public, anon;

grant execute on function public.review_group_report(text, uuid, text) to authenticated;

grant execute on function public.request_to_join_group(text) to authenticated;

grant execute on function public.answer_join_request(uuid, uuid, boolean) to authenticated;

grant execute on function public.set_group_approval(uuid, boolean) to authenticated;

grant execute on function public.ban_member(uuid, uuid, text) to authenticated;

grant execute on function public.unban_member(uuid, uuid) to authenticated;

grant execute on function public.set_challenge_checkin(uuid, integer, boolean) to authenticated;
