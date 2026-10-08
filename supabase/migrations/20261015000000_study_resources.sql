-- Project Genesis: downloadable study resources (Library › Study Resources).
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing.
--
-- Study notes, commentaries, Bible dictionaries and lexicons, each one
-- SQLite file built by Tools/StudyResources/build_resources.py (which also
-- writes the insert statements; see PHASE4_SETUP.md › Study resources).
-- Files live in the public "study" storage bucket. Packs hold verse ids
-- only, never verse text.
--
-- Only public-domain or openly licensed material belongs here; keep each
-- pack's attribution, which the app shows on its details.
-- Raising `version` makes the app replace downloaded copies on Wi-Fi.
--
--   kind       notes | commentary | dictionary | lexicon
--   tradition  the author's church tradition (evangelical, presbyterian,
--              puritan, reformed_baptist, wesleyan, reformed, lutheran,
--              anglican), or null
--   premium    true: needs Genesis Premium (word study) to download and read

create table if not exists public.study_resources (
  id text primary key check (id ~ '^[a-z0-9-]{2,40}$'),
  kind text not null check (kind in ('notes', 'commentary', 'dictionary', 'lexicon')),
  name text not null,
  author text not null default '',
  summary text not null default '',
  tradition text,
  language text not null default 'en',
  year text,
  license text not null,
  attribution text not null default '',
  premium boolean not null default false,
  -- Raw-DEFLATE-compressed SQLite in the study pack format.
  file_url text not null check (file_url like 'https://%'),
  file_bytes bigint not null check (file_bytes > 0),
  database_bytes bigint not null check (database_bytes > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  version integer not null default 1 check (version >= 1),
  enabled boolean not null default false,
  sort integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.study_resources enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'study_resources' and policyname = 'Anyone can read enabled study resources') then
    create policy "Anyone can read enabled study resources" on public.study_resources for select to anon, authenticated using (enabled);
  end if;
end;
$$;

-- The public bucket the files are served from (read-only to the app; you
-- upload in the dashboard: Storage -> study -> Upload).
insert into storage.buckets (id, name, public)
values ('study', 'study', true)
on conflict (id) do nothing;
