-- Project Genesis: group owners and moderators, moderation tools, and group
-- challenges.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run.
--
-- Roles: every group has one owner (groups.owner_id). Moderators are members
-- whose role is 'leader' (the owner is one too). So the existing checks,
-- policies and group-notify keep working, and 'leader' means "moderator or
-- owner" everywhere.
--
--   Owner:      everything a moderator can do, plus choosing moderators,
--               handing the group to someone else, and deleting the group.
--   Moderator:  edit the group and its invite code, approve join requests,
--               post announcements, start and end challenges, review reports,
--               remove posts, and remove, ban or mute members (not other
--               moderators or the owner).
--   Member:     read, post, pray, take part, report, leave.
--
-- Moderation: bans (no rejoining with any code), mutes (can't post for a
-- while), join requests (optional per group), and reports that the group's
-- owner and moderators review. Three open reports hide a group post or prayer
-- from everyone but its author and the moderators until it's reviewed.
--
-- Challenges: reading (chapters to finish together), memorise (a passage),
-- streak (read every day) and prayer (pray every day), 1 to 90 days.
-- Check-ins go through set_challenge_checkin, which checks every rule.

-- Owners ---------------------------------------------------------------------

alter table public.groups add column if not exists owner_id uuid references auth.users (id) on delete set null;
alter table public.groups add column if not exists requires_approval boolean not null default false;

-- The creator if still a moderator, else the longest-standing moderator, else
-- the longest-standing member.
update public.groups g
set owner_id = (
  select m.user_id from public.group_members m
  where m.group_id = g.id
  order by (m.user_id = g.created_by and m.role = 'leader') desc, (m.role = 'leader') desc, m.joined_at
  limit 1
)
where g.owner_id is null and g.deleted_at is null;

-- The owner is always a moderator too.
update public.group_members m
set role = 'leader'
from public.groups g
where g.id = m.group_id and g.owner_id = m.user_id and m.role <> 'leader';

-- Mutes ----------------------------------------------------------------------

alter table public.group_members add column if not exists muted_until timestamptz;

-- Hidden after three reports -------------------------------------------------

alter table public.group_prayers add column if not exists hidden_at timestamptz;
alter table public.group_posts add column if not exists hidden_at timestamptz;

-- Which group a report is about, so the group's moderators can review it.
alter table public.content_reports add column if not exists group_id uuid references public.groups (id) on delete cascade;
create index if not exists content_reports_group_idx on public.content_reports (group_id) where resolved_at is null;

-- Bans and join requests -------------------------------------------------------

create table if not exists public.group_bans (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null default '',
  banned_by uuid references auth.users (id) on delete set null,
  reason text not null default '' check (char_length(reason) <= 300),
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.group_join_requests (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- The group's name, so the person waiting can see what they asked to join
-- (they can't read the group itself until they're in).
alter table public.group_join_requests add column if not exists group_name text not null default '';

create index if not exists group_join_requests_user_idx on public.group_join_requests (user_id);

-- Challenges -------------------------------------------------------------------

create table if not exists public.group_challenges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  created_by uuid references auth.users (id) on delete set null,
  kind text not null check (kind in ('reading', 'memorise', 'streak', 'prayer')),
  title text not null check (char_length(btrim(title)) between 1 and 80),
  details text not null default '' check (char_length(details) <= 500),
  starts_on date not null,
  days integer not null check (days between 1 and 90),
  -- Reading: the chapters to finish (ChapterID: book * 1000 + chapter).
  chapters integer[],
  -- Memorise: the passage (VerseID: book * 1000000 + chapter * 1000 + verse)
  -- and the translation it's learned in. Ids only, never verse text.
  verse_start integer,
  verse_end integer,
  translation_id text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Ended early by a moderator: kept (with everyone's progress) as finished.
alter table public.group_challenges add column if not exists ended_at timestamptz;

create index if not exists group_challenges_group_idx on public.group_challenges (group_id) where deleted_at is null;

-- One row per thing done: a chapter (reading), a day (streak, prayer) or 1
-- (memorise: "I've learned it").
create table if not exists public.group_challenge_checkins (
  challenge_id uuid not null references public.group_challenges (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  item integer not null,
  created_at timestamptz not null default now(),
  primary key (challenge_id, user_id, item)
);

create index if not exists group_challenge_checkins_group_idx on public.group_challenge_checkins (group_id);

alter table public.group_bans enable row level security;
alter table public.group_join_requests enable row level security;
alter table public.group_challenges enable row level security;
alter table public.group_challenge_checkins enable row level security;

-- Helpers ----------------------------------------------------------------------

create or replace function public.genesis_is_owner(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.groups g
    where g.id = p_group and g.owner_id = auth.uid() and g.deleted_at is null
  ) and public.genesis_is_member(p_group);
$$;

-- A member who isn't muted.
create or replace function public.genesis_can_post_group(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.genesis_is_member(p_group) and not exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = auth.uid() and m.muted_until is not null and m.muted_until > now()
  );
$$;

-- Moderators act on members; only the owner acts on moderators; nobody acts
-- on the owner or themselves.
create or replace function public.genesis_can_moderate(p_group uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user <> auth.uid()
    and public.genesis_is_leader(p_group)
    and not exists (select 1 from public.groups g where g.id = p_group and g.owner_id = p_user)
    and (
      public.genesis_is_owner(p_group)
      or not exists (select 1 from public.group_members m where m.group_id = p_group and m.user_id = p_user and m.role = 'leader')
    );
$$;

-- Policies -----------------------------------------------------------------------

-- Muted members can't add prayers or posts.
alter policy "Members add" on public.group_prayers
  with check (user_id = (select auth.uid()) and public.genesis_can_post_group(group_id) and prayed_count = 0 and answered_at is null and deleted_at is null and hidden_at is null);
alter policy "Members add" on public.group_posts
  with check (user_id = (select auth.uid()) and public.genesis_can_post_group(group_id) and deleted_at is null and hidden_at is null);

-- Hidden posts stay visible to their author and the group's moderators.
alter policy "Members read" on public.group_prayers
  using (public.genesis_is_member(group_id) and deleted_at is null
    and (hidden_at is null or user_id = (select auth.uid()) or public.genesis_is_leader(group_id)));
alter policy "Members read" on public.group_posts
  using (public.genesis_is_member(group_id) and deleted_at is null
    and (hidden_at is null or user_id = (select auth.uid()) or public.genesis_is_leader(group_id)));

do $$
begin
  -- Bans: the group's moderators see the list.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_bans' and policyname = 'Moderators read') then
    create policy "Moderators read" on public.group_bans for select to authenticated using (public.genesis_is_leader(group_id));
  end if;

  -- Join requests: your own, or your group's if you moderate it. You can
  -- withdraw your own; everything else goes through the functions below.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_join_requests' and policyname = 'Own or moderated read') then
    create policy "Own or moderated read" on public.group_join_requests for select to authenticated
      using (user_id = (select auth.uid()) or public.genesis_is_leader(group_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_join_requests' and policyname = 'Withdraw own') then
    create policy "Withdraw own" on public.group_join_requests for delete to authenticated using (user_id = (select auth.uid()));
  end if;

  -- Challenges and check-ins: members read; changes go through functions.
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_challenges' and policyname = 'Members read') then
    create policy "Members read" on public.group_challenges for select to authenticated
      using (public.genesis_is_member(group_id) and deleted_at is null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_challenge_checkins' and policyname = 'Members read') then
    create policy "Members read" on public.group_challenge_checkins for select to authenticated
      using (public.genesis_is_member(group_id));
  end if;
end;
$$;

-- Reports ------------------------------------------------------------------------

-- Group posts can only be reported by the group's members (the stamp trigger
-- below fills in group_id before this check runs), so outsiders can't hide them.
alter policy "Report content" on public.content_reports
  with check (reporter = (select auth.uid()) and (
    (content_type in ('community_post', 'community_comment') and group_id is null)
    or (group_id is not null and public.genesis_is_member(group_id))
  ));

-- Server times, open reports, and the group the content belongs to.
create or replace function public.genesis_stamp_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'content_reports' then
    new.created_at := now();
    new.resolved_at := null;
    new.group_id := case new.content_type
      when 'group_prayer' then (select group_id from public.group_prayers where id = new.content_id)
      when 'group_post' then (select group_id from public.group_posts where id = new.content_id)
      when 'group_announcement' then (select group_id from public.group_announcements where id = new.content_id)
      else null
    end;
  elsif tg_table_name = 'group_progress' then
    new.completed_at := now();
  end if;
  return new;
end;
$$;

-- Three reports from different people hide community content, group posts
-- and group prayers until reviewed.
create or replace function public.genesis_after_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reports integer;
begin
  select count(distinct reporter) into reports from public.content_reports
  where content_type = new.content_type and content_id = new.content_id and resolved_at is null;
  if reports >= 3 then
    if new.content_type = 'community_post' then
      update public.community_posts set hidden_at = coalesce(hidden_at, now()) where id = new.content_id;
    elsif new.content_type = 'community_comment' then
      update public.community_comments set hidden_at = coalesce(hidden_at, now()) where id = new.content_id;
    elsif new.content_type = 'group_prayer' then
      update public.group_prayers set hidden_at = coalesce(hidden_at, now()) where id = new.content_id;
    elsif new.content_type = 'group_post' then
      update public.group_posts set hidden_at = coalesce(hidden_at, now()) where id = new.content_id;
    end if;
  end if;
  return null;
end;
$$;

-- Open reports in a group, one row per reported item, without saying who
-- reported it. Moderators only.
create or replace function public.group_reports(p_group uuid)
returns table (
  content_type text,
  content_id uuid,
  author_id uuid,
  author_name text,
  body text,
  report_count integer,
  reasons text[],
  last_reported_at timestamptz,
  hidden boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then raise exception 'moderators_only' using errcode = 'P0001'; end if;
  return query
    select r.content_type, r.content_id,
      coalesce(gp.user_id, gpo.user_id, ga.user_id),
      coalesce(gp.display_name, gpo.display_name, ga.display_name),
      coalesce(gp.body, gpo.body, ga.title || E'\n' || ga.body),
      count(distinct r.reporter)::integer,
      coalesce(array_agg(r.reason) filter (where r.reason <> ''), '{}'),
      max(r.created_at),
      coalesce(gp.hidden_at, gpo.hidden_at) is not null
    from public.content_reports r
    left join public.group_prayers gp on r.content_type = 'group_prayer' and gp.id = r.content_id
    left join public.group_posts gpo on r.content_type = 'group_post' and gpo.id = r.content_id
    left join public.group_announcements ga on r.content_type = 'group_announcement' and ga.id = r.content_id
    where r.group_id = p_group and r.resolved_at is null
      and coalesce(gp.deleted_at, gpo.deleted_at, ga.deleted_at) is null
      and coalesce(gp.id, gpo.id, ga.id) is not null
    group by r.content_type, r.content_id, gp.user_id, gpo.user_id, ga.user_id,
      gp.display_name, gpo.display_name, ga.display_name, gp.body, gpo.body, ga.title, ga.body,
      gp.hidden_at, gpo.hidden_at
    order by max(r.created_at) desc;
end;
$$;

-- Review a report: 'remove' takes the item down, 'keep' shows it again.
-- Either way its open reports are closed.
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

-- Groups: create, join, leave ------------------------------------------------------

-- As before, with the creator as owner.
create or replace function public.create_group(
  p_name text,
  p_description text,
  p_plan_id text,
  p_plan_title text,
  p_plan_books integer[],
  p_plan_days integer,
  p_plan_start date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  member_name text;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_feature_on('groups') then raise exception 'groups_off' using errcode = 'P0001'; end if;
  select display_name into member_name from public.profiles where user_id = auth.uid();
  if member_name is null then raise exception 'name_required' using errcode = 'P0001', hint = 'Choose a display name first.'; end if;
  perform public.genesis_check_group(p_name, p_description, p_plan_id, p_plan_title, p_plan_books, p_plan_days);
  if (select count(*) from public.groups where created_by = auth.uid() and deleted_at is null) >= 20 then
    raise exception 'too_many_groups' using errcode = 'P0001';
  end if;

  insert into public.groups (name, description, invite_code, plan_id, plan_title, plan_books, plan_days, plan_start, created_by, owner_id)
  values (btrim(p_name), coalesce(p_description, ''), public.genesis_new_invite_code(), p_plan_id, p_plan_title, p_plan_books, p_plan_days, p_plan_start, auth.uid(), auth.uid())
  returning id into new_id;

  insert into public.group_members (group_id, user_id, role, display_name)
  values (new_id, auth.uid(), 'leader', member_name);
  return new_id;
end;
$$;

-- Join with a code: straight in, or a request when the group approves members.
-- Returns {"group_id", "name", "status": "joined" | "requested"}.
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

-- The older join, kept for earlier app versions: refuses banned people and
-- groups that approve members.
create or replace function public.join_group(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  result := public.request_to_join_group(p_code);
  if result ->> 'status' <> 'joined' then
    raise exception 'approval_required' using errcode = 'P0001', hint = 'This group approves new members. Update Genesis to ask to join.';
  end if;
  return (result ->> 'group_id')::uuid;
end;
$$;

-- Moderators let someone in or turn them down.
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

-- Whenever the owner goes (leaving, or deleting their account), the
-- longest-standing moderator (else member) becomes the owner; when the last
-- person goes, the group closes.
create or replace function public.genesis_after_member_left()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  next_owner uuid;
begin
  -- Nobody left (for instance the last member deleted their account): close it.
  if not exists (select 1 from public.group_members where group_id = old.group_id) then
    update public.groups set deleted_at = coalesce(deleted_at, now()), updated_at = now() where id = old.group_id;
    return null;
  end if;
  if exists (select 1 from public.groups where id = old.group_id and deleted_at is null and (owner_id is null or owner_id = old.user_id)) then
    select m.user_id into next_owner from public.group_members m
    where m.group_id = old.group_id order by (m.role = 'leader') desc, m.joined_at limit 1;
    if next_owner is not null then
      update public.group_members set role = 'leader', muted_until = null where group_id = old.group_id and user_id = next_owner;
      update public.groups set owner_id = next_owner, updated_at = now() where id = old.group_id;
    end if;
  end if;
  return null;
end;
$$;

create or replace trigger group_members_after_leave after delete on public.group_members
  for each row execute function public.genesis_after_member_left();

-- Leaving: the trigger above passes on ownership; the last person out closes
-- the group.
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

-- Removing content: authors remove their own; moderators remove other
-- people's in their group, but only the owner removes a moderator's, and
-- nobody removes the owner's except the owner.
create or replace function public.remove_content(p_type text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  author uuid;
  owner_group uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if p_type = 'group_prayer' then
    select user_id, group_id into author, owner_group from public.group_prayers where id = p_id;
  elsif p_type = 'group_post' then
    select user_id, group_id into author, owner_group from public.group_posts where id = p_id;
  elsif p_type = 'group_announcement' then
    select user_id, group_id into author, owner_group from public.group_announcements where id = p_id;
  elsif p_type = 'community_post' then
    select user_id into author from public.community_posts where id = p_id;
  elsif p_type = 'community_comment' then
    select user_id into author from public.community_comments where id = p_id;
  else
    raise exception 'invalid_type' using errcode = 'P0001';
  end if;
  if author is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  if author <> auth.uid() and (owner_group is null or not public.genesis_can_moderate(owner_group, author)) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;

  if p_type = 'group_prayer' then
    update public.group_prayers set deleted_at = now() where id = p_id;
  elsif p_type = 'group_post' then
    update public.group_posts set deleted_at = now() where id = p_id;
  elsif p_type = 'group_announcement' then
    update public.group_announcements set deleted_at = now() where id = p_id;
  elsif p_type = 'community_post' then
    update public.community_posts set deleted_at = now() where id = p_id;
  else
    update public.community_comments set deleted_at = now() where id = p_id;
  end if;
end;
$$;

-- Owner only ---------------------------------------------------------------------

create or replace function public.transfer_group_ownership(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_owner(p_group) then raise exception 'owner_only' using errcode = 'P0001'; end if;
  if p_user = auth.uid() then return; end if;
  if not exists (select 1 from public.group_members where group_id = p_group and user_id = p_user) then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;
  -- The new owner is a moderator; the old one stays a moderator.
  update public.group_members set role = 'leader', muted_until = null where group_id = p_group and user_id = p_user;
  update public.groups set owner_id = p_user, updated_at = now() where id = p_group;
end;
$$;

-- Moderator ('leader') or member. Only the owner chooses moderators, and the
-- owner's own role can't change.
create or replace function public.set_member_role(p_group uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_owner(p_group) then raise exception 'owner_only' using errcode = 'P0001'; end if;
  if p_role not in ('leader', 'member') then raise exception 'invalid_role' using errcode = 'P0001'; end if;
  if p_user = auth.uid() then raise exception 'owner_role_fixed' using errcode = 'P0001', hint = 'Hand the group to someone else first.'; end if;
  update public.group_members set role = p_role, muted_until = case when p_role = 'leader' then null else muted_until end
  where group_id = p_group and user_id = p_user;
end;
$$;

create or replace function public.delete_group(p_group uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_owner(p_group) then raise exception 'owner_only' using errcode = 'P0001'; end if;
  update public.groups set deleted_at = now(), updated_at = now() where id = p_group;
end;
$$;

-- Moderators: remove, ban, mute ---------------------------------------------------

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

-- Remove someone and keep them out, whatever code they have.
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

-- Mute for 1 hour to 30 days; 0 hours lifts the mute.
create or replace function public.mute_member(p_group uuid, p_user uuid, p_hours integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.genesis_can_moderate(p_group, p_user) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if p_hours is null or p_hours not between 0 and 720 then raise exception 'invalid_duration' using errcode = 'P0001'; end if;
  update public.group_members
  set muted_until = case when p_hours = 0 then null else now() + make_interval(hours => p_hours) end
  where group_id = p_group and user_id = p_user;
end;
$$;

-- Challenges -----------------------------------------------------------------------

create or replace function public.create_group_challenge(
  p_group uuid,
  p_kind text,
  p_title text,
  p_details text,
  p_starts_on date,
  p_days integer,
  p_chapters integer[],
  p_verse_start integer,
  p_verse_end integer,
  p_translation text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
begin
  if not public.genesis_is_leader(p_group) then raise exception 'moderators_only' using errcode = 'P0001'; end if;
  if p_kind is null or p_kind not in ('reading', 'memorise', 'streak', 'prayer') then
    raise exception 'invalid_challenge' using errcode = 'P0001';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 80 or char_length(coalesce(p_details, '')) > 500
     or p_days is null or p_days not between 1 and 90
     or p_starts_on is null or p_starts_on not between current_date - 1 and current_date + 60 then
    raise exception 'invalid_challenge' using errcode = 'P0001';
  end if;
  if public.genesis_is_objectionable(p_title) or public.genesis_is_objectionable(p_details) then
    raise exception 'objectionable_content' using errcode = 'P0001', hint = 'Please rephrase. Some words aren''t allowed in Genesis.';
  end if;
  if p_kind = 'reading' and (
       p_chapters is null or cardinality(p_chapters) not between 1 and 1189
       or exists (select 1 from unnest(p_chapters) c where c is null or c / 1000 not between 1 and 66 or c % 1000 not between 1 and 150)) then
    raise exception 'invalid_challenge' using errcode = 'P0001';
  end if;
  if p_kind = 'memorise' and (
       p_verse_start is null or p_verse_end is null or p_verse_end < p_verse_start
       or p_verse_start / 1000000 not between 1 and 66 or p_verse_start / 1000000 <> p_verse_end / 1000000
       or p_verse_end - p_verse_start > 2000
       or char_length(coalesce(p_translation, '')) not between 1 and 20) then
    raise exception 'invalid_challenge' using errcode = 'P0001';
  end if;
  if (select count(*) from public.group_challenges
      where group_id = p_group and deleted_at is null and ended_at is null and starts_on + days > current_date) >= 5 then
    raise exception 'too_many_challenges' using errcode = 'P0001', hint = 'A group can run up to five challenges at once.';
  end if;

  insert into public.group_challenges (group_id, created_by, kind, title, details, starts_on, days, chapters, verse_start, verse_end, translation_id)
  values (
    p_group, auth.uid(), p_kind, btrim(p_title), coalesce(p_details, ''), p_starts_on, p_days,
    case when p_kind = 'reading' then (select array_agg(distinct c order by c) from unnest(p_chapters) c) end,
    case when p_kind = 'memorise' then p_verse_start end,
    case when p_kind = 'memorise' then p_verse_end end,
    case when p_kind = 'memorise' then p_translation end
  )
  returning id into new_id;
  return new_id;
end;
$$;

-- End a challenge early. It stays, with everyone's progress, as finished.
create or replace function public.end_group_challenge(p_challenge uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_group uuid;
begin
  select group_id into owner_group from public.group_challenges where id = p_challenge and deleted_at is null;
  if owner_group is null or not public.genesis_is_leader(owner_group) then
    raise exception 'moderators_only' using errcode = 'P0001';
  end if;
  update public.group_challenges set ended_at = coalesce(ended_at, now()) where id = p_challenge;
end;
$$;

-- Tick or untick something done. Days can't be ticked ahead (a day's slack
-- for time zones), and nothing changes once a challenge has ended.
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

-- Everyone's progress in a challenge: how many done, and for day-by-day
-- challenges which days (for streaks). Your own chapters come back too.
create or replace function public.group_challenge_progress(p_challenge uuid)
returns table (user_id uuid, display_name text, done integer, items integer[])
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c public.group_challenges%rowtype;
begin
  select * into c from public.group_challenges where id = p_challenge and deleted_at is null;
  if c.id is null or not public.genesis_is_member(c.group_id) then raise exception 'not_found' using errcode = 'P0001'; end if;
  return query
    select m.user_id, m.display_name, count(k.item)::integer,
      case when c.kind <> 'reading' or m.user_id = auth.uid()
        then coalesce(array_agg(k.item order by k.item) filter (where k.item is not null), '{}')
        else null end
    from public.group_members m
    left join public.group_challenge_checkins k on k.challenge_id = c.id and k.user_id = m.user_id
    where m.group_id = c.group_id
    group by m.user_id, m.display_name;
end;
$$;

-- Permissions ----------------------------------------------------------------------

revoke all on function public.genesis_after_member_left() from public, anon, authenticated;
revoke all on function public.genesis_is_owner(uuid) from public, anon;
revoke all on function public.genesis_can_post_group(uuid) from public, anon;
revoke all on function public.genesis_can_moderate(uuid, uuid) from public, anon;
grant execute on function public.genesis_is_owner(uuid) to authenticated;
grant execute on function public.genesis_can_post_group(uuid) to authenticated;
grant execute on function public.genesis_can_moderate(uuid, uuid) to authenticated;

revoke all on function public.group_reports(uuid) from public, anon;
revoke all on function public.review_group_report(text, uuid, text) from public, anon;
revoke all on function public.request_to_join_group(text) from public, anon;
revoke all on function public.answer_join_request(uuid, uuid, boolean) from public, anon;
revoke all on function public.set_group_approval(uuid, boolean) from public, anon;
revoke all on function public.transfer_group_ownership(uuid, uuid) from public, anon;
revoke all on function public.ban_member(uuid, uuid, text) from public, anon;
revoke all on function public.unban_member(uuid, uuid) from public, anon;
revoke all on function public.mute_member(uuid, uuid, integer) from public, anon;
revoke all on function public.create_group_challenge(uuid, text, text, text, date, integer, integer[], integer, integer, text) from public, anon;
revoke all on function public.end_group_challenge(uuid) from public, anon;
revoke all on function public.set_challenge_checkin(uuid, integer, boolean) from public, anon;
revoke all on function public.group_challenge_progress(uuid) from public, anon;
grant execute on function public.group_reports(uuid) to authenticated;
grant execute on function public.review_group_report(text, uuid, text) to authenticated;
grant execute on function public.request_to_join_group(text) to authenticated;
grant execute on function public.answer_join_request(uuid, uuid, boolean) to authenticated;
grant execute on function public.set_group_approval(uuid, boolean) to authenticated;
grant execute on function public.transfer_group_ownership(uuid, uuid) to authenticated;
grant execute on function public.ban_member(uuid, uuid, text) to authenticated;
grant execute on function public.unban_member(uuid, uuid) to authenticated;
grant execute on function public.mute_member(uuid, uuid, integer) to authenticated;
grant execute on function public.create_group_challenge(uuid, text, text, text, date, integer, integer[], integer, integer, text) to authenticated;
grant execute on function public.end_group_challenge(uuid) to authenticated;
grant execute on function public.set_challenge_checkin(uuid, integer, boolean) to authenticated;
grant execute on function public.group_challenge_progress(uuid) to authenticated;
