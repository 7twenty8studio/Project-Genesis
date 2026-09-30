-- Project Genesis: Phase 3 study assistant (study-ai Edge Function).
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing and never drops or deletes
-- anything.
--
-- These tables are written only by the study-ai Edge Function (service role).
-- Row-level security is on for all three: people can read their own usage and
-- Premium status, and nobody can read or write the shared answer cache
-- directly. They aren't synced, so they don't carry the sync columns.

-- Shared answers, one per passage and study action. Never contains verse text.
create table if not exists public.ai_cache (
  key text primary key,
  action text not null,
  start_verse integer not null,
  end_verse integer not null,
  content text not null,
  model text not null,
  created_at timestamptz not null default now()
);

-- Answers per person per day, for the free and fair-use limits.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0,
  primary key (user_id, day)
);

-- Verified App Store subscriptions. One subscription unlocks one account.
create table if not exists public.premium_entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  original_transaction_id text not null unique,
  product_id text not null,
  environment text not null,
  expires_at timestamptz not null,
  updated_at timestamptz not null default now()
);

alter table public.ai_cache enable row level security;
alter table public.ai_usage enable row level security;
alter table public.premium_entitlements enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'ai_usage' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.ai_usage for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'premium_entitlements' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.premium_entitlements for select to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

-- Adds one to today's count and returns the new total, in one step so
-- simultaneous requests can't both slip under the limit.
create or replace function public.increment_ai_usage(p_user uuid, p_day date)
returns integer
language sql
security definer
set search_path = ''
as $$
  insert into public.ai_usage (user_id, day, count)
  values (p_user, p_day, 1)
  on conflict (user_id, day) do update set count = public.ai_usage.count + 1
  returning count;
$$;

-- Only the Edge Function (service role) may call it.
revoke all on function public.increment_ai_usage(uuid, date) from public;
revoke all on function public.increment_ai_usage(uuid, date) from anon;
revoke all on function public.increment_ai_usage(uuid, date) from authenticated;
grant execute on function public.increment_ai_usage(uuid, date) to service_role;
