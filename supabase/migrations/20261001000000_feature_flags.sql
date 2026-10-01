-- Project Genesis: server-side feature switches.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing and never changes a switch
-- you've already set.
--
-- The app reads this table at launch and whenever it comes to the front, so a
-- switch takes effect without an app update. Anyone can read it (it holds no
-- personal data); only you can change it, from the dashboard (Table Editor ->
-- feature_flags) or the SQL Editor.
--
--   study_assistant   the AI study assistant (Explain, chapter study tools).
--                     Off. The study-ai Edge Function also refuses requests
--                     while it's off.
--
-- Turn it on:  update public.feature_flags set enabled = true,  updated_at = now() where key = 'study_assistant';
-- Turn it off: update public.feature_flags set enabled = false, updated_at = now() where key = 'study_assistant';

create table if not exists public.feature_flags (
  key text primary key,
  enabled boolean not null default false,
  description text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.feature_flags enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'feature_flags' and policyname = 'Anyone can read') then
    create policy "Anyone can read" on public.feature_flags for select to anon, authenticated using (true);
  end if;
end;
$$;

insert into public.feature_flags (key, enabled, description)
values ('study_assistant', false, 'AI study assistant: Explain, chapter study tools and the Study panel.')
on conflict (key) do nothing;
