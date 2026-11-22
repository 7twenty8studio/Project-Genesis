-- Church roles: Owner, Admin, Preacher, Member (VRS-18, owner's plan of
-- 22 November 2026, "Church Studio roles: owner, admins and preachers").
--
--   * Admin is the group's moderator (role 'leader', which the owner also
--     has): every sermon, settings, people and reports, as before.
--   * Preacher (new): a member with group_members.preacher set. Writes,
--     publishes, updates, unpublishes and deletes the sermons they started
--     (church_sermons.created_by); reads the church's published sermons and
--     the reports on their own; never church settings, other people's
--     sermons, members or reports' hide/keep.
--   * Owner and Admins add or remove Preachers; only the Owner adds or removes
--     Admins (set_church_role). A Preacher may step down. Admins can hand a
--     sermon to another Preacher or Admin (change_sermon_owner).
--   * Each sermon records who last edited it (updated_by).
--
-- Explicit statements, no drops; safe to run twice.

alter table public.group_members add column if not exists preacher boolean not null default false;
alter table public.church_sermons add column if not exists updated_by uuid references auth.users (id) on delete set null;

-- Sermons whose starter's account is gone belong to the church's owner.
update public.church_sermons s set created_by = g.owner_id
from public.groups g
where g.id = s.group_id and s.created_by is null and g.owner_id is not null;
update public.church_sermons set updated_by = created_by where updated_by is null and created_by is not null;

-- Checks --------------------------------------------------------------------------

-- A Preacher of the group (a member, not an Admin, with the preacher flag).
create or replace function public.genesis_is_preacher(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = auth.uid() and m.role = 'member' and m.preacher
  ) and public.genesis_is_member(p_group);
$$;

-- May start sermons: an Owner or Admin (genesis_can_edit_sermons), or a
-- Preacher of a church with sermons on, not banned, not muted.
create or replace function public.genesis_can_write_sermons(p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.genesis_can_edit_sermons(p_group)
    or (auth.uid() is not null
        and public.genesis_church_sermons_on(p_group)
        and public.genesis_is_preacher(p_group)
        and not exists (select 1 from public.group_bans b where b.group_id = p_group and b.user_id = auth.uid())
        and not exists (select 1 from public.group_members m
                        where m.group_id = p_group and m.user_id = auth.uid() and m.muted_until is not null and m.muted_until > now()));
$$;

-- May change this sermon: an Owner or Admin of its church, or the Preacher who started it.
create or replace function public.genesis_can_edit_sermon(p_row public.church_sermons)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_row.deleted_at is null
    and (public.genesis_can_edit_sermons(p_row.group_id)
         or (p_row.created_by = auth.uid() and public.genesis_can_write_sermons(p_row.group_id)));
$$;

-- Locks the sermon for the rest of the transaction and checks the caller may
-- edit it (as in 20261120000000, now with Preachers' own sermons).
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
  if not public.genesis_can_edit_sermon(row_) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return row_;
end;
$$;

-- Who last changed the draft or its state.
create or replace function public.genesis_stamp_sermon_editor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.updated_by := coalesce(auth.uid(), new.created_by);
  elsif auth.uid() is not null and (new.draft_version is distinct from old.draft_version or new.status is distinct from old.status) then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

create or replace trigger church_sermons_stamp_editor before insert or update on public.church_sermons
  for each row execute function public.genesis_stamp_sermon_editor();

-- Writing -------------------------------------------------------------------------

-- As in 20261120000000; Preachers may start sermons too.
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
  if not public.genesis_can_write_sermons(p_group) then
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

-- Covers: anyone who may edit the sermon (as in 20261120000000 otherwise).
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
        and public.genesis_can_edit_sermon(s))
    and not exists (select 1 from public.church_sermon_retired_covers t where t.name = p_name);
$$;

-- Keep or take down a reported sermon: Owner and Admins only (a Preacher
-- sees the reports on their own sermons but doesn't judge them).
create or replace function public.review_church_sermon_reports(p_sermon uuid, p_keep boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  if not public.genesis_can_edit_sermons(row_.group_id) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
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

-- Reading -------------------------------------------------------------------------

-- Preachers read their own sermons' rows (the Studio loads drafts this way).
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'church_sermons' and policyname = 'Preachers read their own') then
    create policy "Preachers read their own" on public.church_sermons for select to authenticated
      using (deleted_at is null and created_by = auth.uid() and public.genesis_can_write_sermons(group_id));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'church_sermon_revisions' and policyname = 'Preachers read their own') then
    create policy "Preachers read their own" on public.church_sermon_revisions for select to authenticated
      using (exists (select 1 from public.church_sermons s
                     where s.id = sermon_id and s.created_by = auth.uid() and public.genesis_can_edit_sermon(s)));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'church_sermon_stats' and policyname = 'Preachers read their own') then
    create policy "Preachers read their own" on public.church_sermon_stats for select to authenticated
      using (exists (select 1 from public.church_sermons s
                     where s.id = sermon_id and s.created_by = auth.uid() and public.genesis_can_edit_sermon(s)));
  end if;
end;
$$;

-- A member's name in the church, for "Started by" and "Last edited by".
create or replace function public.genesis_member_name(p_group uuid, p_user uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.display_name from public.group_members m where m.group_id = p_group and m.user_id = p_user;
$$;

-- A church's sermons. Owner and Admins: every sermon with its state.
-- Preachers: their own sermons with their state, and everyone else's
-- published ones as published (never another person's draft). Members:
-- the published copies (as in 20261120000000). Rows for writers carry
-- "mine", "can_edit", "started_by" and "edited_by".
create or replace function public.group_sermons(p_group uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  admin_ boolean := public.genesis_can_edit_sermons(p_group);
begin
  if admin_ or public.genesis_can_write_sermons(p_group) then
    return coalesce((
      select jsonb_agg(x.row_ order by x.preached_on desc nulls first, x.created_at desc)
      from (
        select
          case when admin_ or s.created_by = auth.uid() then jsonb_build_object(
            'id', s.id, 'slug', s.slug, 'title', s.title, 'speaker', s.speaker, 'series', s.series,
            'preached_on', s.preached_on, 'audience', s.audience, 'status', s.status,
            'live_audience', s.live_audience, 'hidden', s.hidden_at is not null, 'has_cover', s.cover_id is not null,
            'published_at', s.published_at, 'draft_version', s.draft_version,
            'unpublished_changes', s.status = 'published' and r.draft_version is distinct from s.draft_version,
            'mine', s.created_by = auth.uid(), 'can_edit', true,
            'started_by', public.genesis_member_name(p_group, s.created_by),
            'edited_by', public.genesis_member_name(p_group, s.updated_by))
          else jsonb_build_object(
            'id', s.id, 'slug', s.slug, 'title', r.details->>'title', 'speaker', r.details->>'speaker',
            'series', r.details->'series', 'preached_on', r.details->'preached_on', 'audience', s.live_audience,
            'status', s.status, 'live_audience', s.live_audience, 'hidden', false,
            'has_cover', r.details->'cover' is not null and r.details->'cover' <> 'null'::jsonb,
            'published_at', s.published_at, 'draft_version', null, 'unpublished_changes', false,
            'mine', false, 'can_edit', false,
            'started_by', public.genesis_member_name(p_group, s.created_by),
            'edited_by', null)
          end as row_,
          case when admin_ or s.created_by = auth.uid() then s.preached_on else (r.details->>'preached_on')::date end as preached_on,
          s.created_at
        from public.church_sermons s left join public.church_sermon_revisions r on r.id = s.published_revision_id
        where s.group_id = p_group and s.deleted_at is null
          and (admin_ or s.created_by = auth.uid()
               or (s.status = 'published' and s.hidden_at is null and r.id is not null))
      ) x
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

-- Open reports, without saying who reported. Owner and Admins: every
-- sermon's; a Preacher: their own sermons'.
create or replace function public.group_sermon_reports(p_group uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  admin_ boolean := public.genesis_can_edit_sermons(p_group);
begin
  if not (admin_ or public.genesis_can_write_sermons(p_group)) then
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
      where s.group_id = p_group and s.deleted_at is null and (admin_ or s.created_by = auth.uid())
      group by s.id, r0.details
    ) x
  ), '[]'::jsonb);
end;
$$;

-- The churches the caller can write sermons for, with their role there:
-- 'owner', 'admin' or 'preacher' (as in 20261124000000 otherwise).
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
      'role', case when g.owner_id = auth.uid() then 'owner' when m.role = 'leader' then 'admin' else 'preacher' end,
      'listed', g.sermons_listed,
      'locations', g.sermon_locations)
    order by lower(g.name)), '[]'::jsonb)
  from public.groups g
  join public.group_members m on m.group_id = g.id and m.user_id = auth.uid() and (m.role = 'leader' or m.preacher)
  where g.deleted_at is null and public.genesis_can_write_sermons(g.id);
$$;

-- People ------------------------------------------------------------------------------

-- The church's people with their roles, for Owner and Admins: owner first,
-- then admins, preachers and members, by name. sermons = how many they started.
create or replace function public.church_people(p_group uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.genesis_is_leader(p_group) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'user_id', x.user_id, 'name', x.display_name, 'role', x.role_, 'joined_at', x.joined_at,
        'sermons', x.sermons, 'me', x.user_id = auth.uid())
      order by x.rank_, lower(x.display_name))
    from (
      select m.user_id, m.display_name, m.joined_at,
             case when g.owner_id = m.user_id then 'owner' when m.role = 'leader' then 'admin'
                  when m.preacher then 'preacher' else 'member' end as role_,
             case when g.owner_id = m.user_id then 0 when m.role = 'leader' then 1 when m.preacher then 2 else 3 end as rank_,
             (select count(*) from public.church_sermons s
              where s.group_id = p_group and s.created_by = m.user_id and s.deleted_at is null) as sermons
      from public.group_members m join public.groups g on g.id = m.group_id
      where m.group_id = p_group
    ) x
  ), '[]'::jsonb);
end;
$$;

-- Sets someone's role: 'admin', 'preacher' or 'member'. The Owner sets any
-- role for anyone but themselves; an Admin makes members Preachers and
-- Preachers members (never touches Admins); a Preacher may step down.
create or replace function public.set_church_role(p_group uuid, p_user uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target public.group_members;
  is_owner_ boolean := public.genesis_is_owner(p_group);
begin
  if p_role is null or p_role not in ('admin', 'preacher', 'member') then
    raise exception 'invalid_role' using errcode = 'P0001';
  end if;
  select * into target from public.group_members where group_id = p_group and user_id = p_user for update;
  if not found then raise exception 'not_found' using errcode = 'P0001'; end if;
  if exists (select 1 from public.groups g where g.id = p_group and g.owner_id = p_user) then
    raise exception 'owner_role_fixed' using errcode = 'P0001';
  end if;
  if is_owner_ then
    null;
  elsif public.genesis_is_leader(p_group) and target.role = 'member' and p_role in ('preacher', 'member') then
    null;
  elsif p_user = auth.uid() and target.role = 'member' and target.preacher and p_role = 'member' then
    null;
  else
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  update public.group_members set
    role = case when p_role = 'admin' then 'leader' else 'member' end,
    preacher = (p_role = 'preacher'),
    muted_until = case when p_role = 'admin' then null else muted_until end
  where group_id = p_group and user_id = p_user;
end;
$$;

-- The app's Make Moderator / Remove Moderator (owner only, as in
-- 20261011000000): an Admin is never also a Preacher, so making someone
-- an Admin, or an Admin a member again, clears the Preacher flag.
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
  update public.group_members set role = p_role, preacher = false,
    muted_until = case when p_role = 'leader' then null else muted_until end
  where group_id = p_group and user_id = p_user;
end;
$$;

-- Hands a sermon to another Preacher or Admin of its church (Owner and Admins).
create or replace function public.change_sermon_owner(p_sermon uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  if not public.genesis_can_edit_sermons(row_.group_id) then
    raise exception 'not_allowed' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.group_members m
                 where m.group_id = row_.group_id and m.user_id = p_user and (m.role = 'leader' or m.preacher)) then
    raise exception 'not_a_writer' using errcode = 'P0001';
  end if;
  update public.church_sermons set created_by = p_user where id = p_sermon;
end;
$$;

-- Grants -------------------------------------------------------------------------------

revoke all on function public.genesis_is_preacher(uuid) from public, anon;
revoke all on function public.genesis_can_write_sermons(uuid) from public, anon;
revoke all on function public.genesis_can_edit_sermon(public.church_sermons) from public, anon;
revoke all on function public.genesis_member_name(uuid, uuid) from public, anon, authenticated;
revoke all on function public.genesis_stamp_sermon_editor() from public, anon, authenticated;
revoke all on function public.genesis_editable_sermon(uuid) from public, anon, authenticated;
revoke all on function public.genesis_can_edit_cover(text) from public, anon;
revoke all on function public.create_church_sermon(uuid, text) from public, anon;
revoke all on function public.review_church_sermon_reports(uuid, boolean) from public, anon;
revoke all on function public.group_sermons(uuid) from public, anon;
revoke all on function public.group_sermon_reports(uuid) from public, anon;
revoke all on function public.my_sermon_churches() from public, anon;
revoke all on function public.church_people(uuid) from public, anon;
revoke all on function public.set_church_role(uuid, uuid, text) from public, anon;
revoke all on function public.change_sermon_owner(uuid, uuid) from public, anon;

grant execute on function public.genesis_is_preacher(uuid) to authenticated;
grant execute on function public.genesis_can_write_sermons(uuid) to authenticated;
grant execute on function public.genesis_can_edit_sermon(public.church_sermons) to authenticated;
grant execute on function public.genesis_can_edit_cover(text) to authenticated;
grant execute on function public.create_church_sermon(uuid, text) to authenticated;
grant execute on function public.review_church_sermon_reports(uuid, boolean) to authenticated;
grant execute on function public.group_sermons(uuid) to authenticated;
grant execute on function public.group_sermon_reports(uuid) to authenticated;
grant execute on function public.my_sermon_churches() to authenticated;
grant execute on function public.church_people(uuid) to authenticated;
grant execute on function public.set_church_role(uuid, uuid, text) to authenticated;
grant execute on function public.change_sermon_owner(uuid, uuid) to authenticated;
