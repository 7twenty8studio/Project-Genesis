-- Project Genesis: the Sermon Companion's notes (free for everyone), synced
-- like prayers.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run,
-- after 20261012000000_prayer_journal.sql. Safe to re-run: it only creates
-- what is missing. Run it before shipping the app version with Sermon Notes:
-- sync pulls public.sermons.
--
-- Each row is one sermon's notes: title, preacher, church, when it was
-- preached, an optional series, the notes as Markdown text, the passages as
-- verse ids only ([{"start_verse": 43003016, "end_verse": 43003017}, ...];
-- the app shows the words from the person's Bible, never stored here) and
-- a favourite flag. Rows go when the account is deleted (on delete cascade).

create table if not exists public.sermons (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '' check (char_length(title) <= 200),
  preacher text not null default '' check (char_length(preacher) <= 120),
  church text not null default '' check (char_length(church) <= 120),
  preached_at timestamptz not null,
  series text check (series is null or char_length(series) <= 120),
  body text not null default '' check (char_length(body) <= 100000),
  passages jsonb not null default '[]'::jsonb constraint sermons_passages_shape check (jsonb_typeof(passages) = 'array' and jsonb_array_length(passages) <= 100),
  is_favourite boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

alter table public.sermons enable row level security;

create index if not exists sermons_sync_idx on public.sermons (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.sermons
  for each row execute function public.genesis_touch_server_updated_at();

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'sermons' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.sermons for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'sermons' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.sermons for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'sermons' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.sermons for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'sermons' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.sermons for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

comment on table public.sermons is
  'Sermon notes (Sermon Companion). Notes are Markdown; passages are verse ids only, never verse text.';

comment on column public.sermons.passages is
  'Attached passages as [{"start_verse": int, "end_verse": int}] verse ids (book*1000000 + chapter*1000 + verse); never verse text.';
