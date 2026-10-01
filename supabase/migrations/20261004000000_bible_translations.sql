-- Project Genesis: downloadable Bible translations.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing.
--
-- Translations beyond the three bundled ones (KJV, WEB, ASV) are listed here
-- and downloaded in the app (Home -> Get More, or the reader's translation
-- menu -> More Bibles). Files live in the public
-- "bibles" storage bucket. Tools/BibleData/package_translation.py builds a
-- file and the insert statement for it; see PHASE4_SETUP.md.
--
-- Only public-domain or licensed-for-offline translations belong here.
-- Raising `version` makes the app replace downloaded copies automatically.
-- A row for a bundled translation (e.g. KJV, version 2) updates that one too.

create table if not exists public.bible_translations (
  id text primary key check (id ~ '^[A-Z0-9]{2,8}$'),
  name text not null,
  year text not null default '',
  license text not null,
  summary text not null default '',
  -- Raw-DEFLATE-compressed SQLite in the app's Bible format.
  file_url text not null check (file_url like 'https://%'),
  file_bytes bigint not null check (file_bytes > 0),
  database_bytes bigint not null check (database_bytes > 0),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  version integer not null default 1 check (version >= 1),
  enabled boolean not null default false,
  sort integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.bible_translations enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bible_translations' and policyname = 'Anyone can read enabled translations') then
    create policy "Anyone can read enabled translations" on public.bible_translations for select to anon, authenticated using (enabled);
  end if;
end;
$$;

-- The public bucket the files are served from (read-only to the app; you
-- upload in the dashboard: Storage -> bibles -> Upload).
insert into storage.buckets (id, name, public)
values ('bibles', 'bibles', true)
on conflict (id) do nothing;
