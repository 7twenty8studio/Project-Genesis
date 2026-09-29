-- Project Genesis: Phase 2 cloud sync schema.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run (everything is "if not exists" / "or replace").
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

-- Indexes, triggers and row-level security for every synced table ----------

do $$
declare
  t text;
begin
  foreach t in array array['bookmarks', 'highlight_collections', 'highlights', 'notes', 'reading_plans', 'prayers']
  loop
    execute format('create index if not exists %I on public.%I (user_id, server_updated_at)', t || '_sync_idx', t);

    execute format('drop trigger if exists genesis_touch on public.%I', t);
    execute format(
      'create trigger genesis_touch before insert or update on public.%I
         for each row execute function public.genesis_touch_server_updated_at()', t);

    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists "Owner can read" on public.%I', t);
    execute format('create policy "Owner can read" on public.%I for select to authenticated using (user_id = auth.uid())', t);

    execute format('drop policy if exists "Owner can insert" on public.%I', t);
    execute format('create policy "Owner can insert" on public.%I for insert to authenticated with check (user_id = auth.uid())', t);

    execute format('drop policy if exists "Owner can update" on public.%I', t);
    execute format('create policy "Owner can update" on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', t);

    execute format('drop policy if exists "Owner can delete" on public.%I', t);
    execute format('create policy "Owner can delete" on public.%I for delete to authenticated using (user_id = auth.uid())', t);
  end loop;
end;
$$;
