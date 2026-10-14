-- Versely: gentle nudges between group members ("read with me today?").
--
-- A nudge is a fixed, friendly message: no text of the sender's own, so
-- there's nothing to moderate. The database decides who may nudge whom:
-- both in the same open group, groups switched on, the sender not muted,
-- neither blocking the other, the receiver accepting nudges, at most one
-- nudge to the same person every 20 hours and 10 a day in all. The app then
-- asks group-notify to push it ({ nudgeID }).

create table if not exists public.group_nudges (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  from_user uuid not null references auth.users (id) on delete cascade,
  to_user uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  notified_at timestamptz
);

create index if not exists group_nudges_sender_idx on public.group_nudges (from_user, created_at);

alter table public.group_nudges enable row level security;

-- Only through send_group_nudge (security definer); senders can read their own.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'group_nudges' and policyname = 'Senders read their nudges') then
    create policy "Senders read their nudges" on public.group_nudges for select to authenticated using (from_user = auth.uid());
  end if;
end;
$$;

-- Whether others may nudge this person (Settings › Notifications › Nudges).
alter table public.profiles add column if not exists accepts_nudges boolean not null default true;

create or replace function public.send_group_nudge(p_group uuid, p_to uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  new_id uuid;
begin
  if me is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_feature_on('groups') then raise exception 'groups_off' using errcode = 'P0001'; end if;
  if p_to is null or p_to = me then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.groups g where g.id = p_group and g.deleted_at is null) then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group and m.user_id = me and (m.muted_until is null or m.muted_until <= now())
  ) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.group_members m where m.group_id = p_group and m.user_id = p_to) then
    raise exception 'not_a_member' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.user_blocks b
    where (b.blocker = p_to and b.blocked = me) or (b.blocker = me and b.blocked = p_to)
  ) then raise exception 'not_allowed' using errcode = 'P0001'; end if;
  if not coalesce((select p.accepts_nudges from public.profiles p where p.user_id = p_to), true) then
    raise exception 'nudges_off' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.group_nudges n
    where n.from_user = me and n.to_user = p_to and n.created_at > now() - interval '20 hours'
  ) then raise exception 'already_nudged' using errcode = 'P0001'; end if;
  if (select count(*) from public.group_nudges n where n.from_user = me and n.created_at > now() - interval '24 hours') >= 10 then
    raise exception 'nudge_limit' using errcode = 'P0001';
  end if;

  insert into public.group_nudges (group_id, from_user, to_user)
  values (p_group, me, p_to)
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.set_accepts_nudges(p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  update public.profiles set accepts_nudges = coalesce(p_on, true), updated_at = now() where user_id = auth.uid();
end;
$$;

revoke all on function public.send_group_nudge(uuid, uuid) from public, anon;
revoke all on function public.set_accepts_nudges(boolean) from public, anon;
grant execute on function public.send_group_nudge(uuid, uuid) to authenticated;
grant execute on function public.set_accepts_nudges(boolean) to authenticated;
