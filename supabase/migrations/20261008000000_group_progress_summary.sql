-- Project Genesis: everyone's progress through a group's reading plan.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run.
--
-- Members see each other's progress bars (days read, latest day) without
-- downloading every row of group_progress. Members only.

create or replace function public.group_progress_summary(p_group uuid)
returns table (user_id uuid, days_done integer, last_day integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  if not public.genesis_is_member(p_group) then raise exception 'not_a_member' using errcode = 'P0001'; end if;
  return query
    select m.user_id, count(p.day)::integer, coalesce(max(p.day), 0)::integer
    from public.group_members m
    left join public.group_progress p on p.group_id = m.group_id and p.user_id = m.user_id
    where m.group_id = p_group
    group by m.user_id;
end;
$$;

revoke all on function public.group_progress_summary(uuid) from public, anon;
grant execute on function public.group_progress_summary(uuid) to authenticated;
