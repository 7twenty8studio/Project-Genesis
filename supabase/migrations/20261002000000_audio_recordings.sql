-- Project Genesis: recorded Bible narration (Phase 4 Audio Bible).
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing.
--
-- Each row is one recorded narration of a translation. The app lists the
-- enabled rows as "Recorded" choices next to the device voice, and plays each
-- chapter from chapter_urls. Anyone can read the list (no personal data); only
-- you can change it, from the dashboard.
--
-- Add a recording with Tools/AudioData/make_audio_manifest.py, which writes
-- the insert statement for you (see PHASE4_SETUP.md). To withdraw one, set
-- enabled = false.

create table if not exists public.audio_recordings (
  id text primary key,
  -- Translation id in the app: KJV, WEB or ASV.
  translation text not null,
  -- Usually the narrator's name.
  title text not null,
  description text not null default '',
  -- Shown with the recording, e.g. 'Public domain'.
  license text not null,
  source_url text,
  -- {"<book>.<chapter>": "https://.../file.mp3"}, e.g. {"43.3": "..."} for John 3.
  chapter_urls jsonb not null default '{}'::jsonb,
  enabled boolean not null default false,
  sort integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.audio_recordings enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'audio_recordings' and policyname = 'Anyone can read enabled recordings') then
    create policy "Anyone can read enabled recordings" on public.audio_recordings for select to anon, authenticated using (enabled);
  end if;
end;
$$;
