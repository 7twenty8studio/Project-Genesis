-- Versely: Settings › Notifications › Group Announcements off, kept on the
-- server, so a device that still takes nudges doesn't get announcements.
-- group-notify skips members whose profile says no.

alter table public.profiles add column if not exists accepts_announcements boolean not null default true;

create or replace function public.set_accepts_announcements(p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in' using errcode = 'P0001'; end if;
  update public.profiles set accepts_announcements = coalesce(p_on, true), updated_at = now() where user_id = auth.uid();
end;
$$;

revoke all on function public.set_accepts_announcements(boolean) from public, anon;
grant execute on function public.set_accepts_announcements(boolean) to authenticated;
