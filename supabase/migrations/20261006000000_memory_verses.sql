-- Project Genesis: Memorise Scripture (Premium), synced like prayers.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing.
--
-- Each row is a passage someone is learning by heart and its review
-- schedule. Verse ids only; the words come from the Bible on the device.

create table if not exists public.memory_verses (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  start_verse integer not null check (start_verse > 1000000),
  end_verse integer not null check (end_verse >= start_verse),
  translation_id text not null check (translation_id ~ '^[A-Z0-9]{2,8}$'),
  ease double precision not null default 2.5 check (ease between 1 and 5),
  interval_days double precision not null default 0 check (interval_days >= 0),
  repetitions integer not null default 0 check (repetitions >= 0),
  due_at timestamptz not null,
  last_reviewed_at timestamptz,
  review_count integer not null default 0 check (review_count >= 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

alter table public.memory_verses enable row level security;

create index if not exists memory_verses_sync_idx on public.memory_verses (user_id, server_updated_at);
create or replace trigger genesis_touch before insert or update on public.memory_verses
  for each row execute function public.genesis_touch_server_updated_at();

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_verses' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.memory_verses for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_verses' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.memory_verses for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_verses' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.memory_verses for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'memory_verses' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.memory_verses for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;
