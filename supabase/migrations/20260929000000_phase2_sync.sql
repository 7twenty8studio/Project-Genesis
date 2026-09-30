-- Project Genesis: Phase 2 cloud sync schema.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing and never drops or
-- deletes anything.
--
-- Design
--   * Every row belongs to one user (user_id = auth.uid()) and row-level
--     security makes other users' rows invisible and unwritable.
--   * id is generated on the device (UUID), so records created offline keep
--     their identity when they sync.
--   * updated_at is the device's edit time and decides conflicts
--     (last writer wins). deleted_at marks deletions so other devices learn
--     about them.
--   * server_updated_at is stamped by the database on every write. Devices
--     pull "everything changed since my last cursor" using it, which avoids
--     trusting device clocks for paging.
--   * Verse references are integers: book*1000000 + chapter*1000 + verse,
--     the same VerseID the app uses. Scripture text is never stored here.

create or replace function public.genesis_touch_server_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

-- Bookmarks ---------------------------------------------------------------

create table if not exists public.bookmarks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  verse integer not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Highlight collections ---------------------------------------------------

create table if not exists public.highlight_collections (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Highlights --------------------------------------------------------------

create table if not exists public.highlights (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  verse integer not null,
  color text not null check (color in ('yellow', 'blue', 'green', 'purple', 'pink', 'orange')),
  collection_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Notes -------------------------------------------------------------------

create table if not exists public.notes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '',
  body text not null default '',
  kind text not null check (kind in ('text', 'prayer', 'study', 'journal')),
  anchor_type text not null check (anchor_type in ('verses', 'chapter', 'book', 'theme', 'none')),
  start_verse integer,
  end_verse integer,
  book integer,
  chapter integer,
  theme text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Reading plans (one row per plan the person has started) -----------------

create table if not exists public.reading_plans (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  plan_id text not null,
  title text not null,
  start_date date not null,
  completed_days integer[] not null default '{}',
  custom_books integer[],
  custom_days integer,
  is_active boolean not null default true,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Prayer journal (private to the person) ----------------------------------

create table if not exists public.prayers (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null default '',
  body text not null default '',
  category text not null check (category in ('family', 'church', 'work', 'personal', 'health', 'friends')),
  is_answered boolean not null default false,
  answered_at timestamptz,
  answer_note text,
  reminder_at timestamptz,
  reminder_repeats_daily boolean not null default false,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

-- Row-level security: each person can only see and change their own rows.

alter table public.bookmarks enable row level security;
alter table public.highlight_collections enable row level security;
alter table public.highlights enable row level security;
alter table public.notes enable row level security;
alter table public.reading_plans enable row level security;
alter table public.prayers enable row level security;

-- Indexes and the server_updated_at trigger.

create index if not exists bookmarks_sync_idx on public.bookmarks (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.bookmarks
  for each row execute function public.genesis_touch_server_updated_at();
create index if not exists highlight_collections_sync_idx on public.highlight_collections (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.highlight_collections
  for each row execute function public.genesis_touch_server_updated_at();
create index if not exists highlights_sync_idx on public.highlights (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.highlights
  for each row execute function public.genesis_touch_server_updated_at();
create index if not exists notes_sync_idx on public.notes (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.notes
  for each row execute function public.genesis_touch_server_updated_at();
create index if not exists reading_plans_sync_idx on public.reading_plans (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.reading_plans
  for each row execute function public.genesis_touch_server_updated_at();
create index if not exists prayers_sync_idx on public.prayers (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.prayers
  for each row execute function public.genesis_touch_server_updated_at();

-- Policies (created only if missing).

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bookmarks' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.bookmarks for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bookmarks' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.bookmarks for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bookmarks' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.bookmarks for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bookmarks' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.bookmarks for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlight_collections' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.highlight_collections for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlight_collections' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.highlight_collections for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlight_collections' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.highlight_collections for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlight_collections' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.highlight_collections for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlights' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.highlights for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlights' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.highlights for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlights' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.highlights for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'highlights' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.highlights for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notes' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.notes for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notes' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.notes for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notes' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.notes for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notes' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.notes for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'reading_plans' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.reading_plans for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'reading_plans' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.reading_plans for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'reading_plans' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.reading_plans for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'reading_plans' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.reading_plans for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'prayers' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.prayers for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'prayers' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.prayers for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'prayers' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.prayers for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'prayers' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.prayers for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;
