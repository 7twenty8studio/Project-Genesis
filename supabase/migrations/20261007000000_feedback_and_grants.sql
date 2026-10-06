-- Project Genesis: in-app feedback, and Premium granted by the owner.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run: it only creates what is missing.

-- Feedback and problem reports from Settings › Send Feedback ----------------
-- Anyone can send (signed in or not); nobody can read them back through the
-- API. Read them in the dashboard (Table Editor › app_feedback).

create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid default auth.uid() references auth.users (id) on delete set null,
  category text not null check (category in ('bug', 'idea', 'question', 'scripture', 'other')),
  message text not null check (char_length(message) between 1 and 4000),
  contact_email text check (contact_email is null or char_length(contact_email) <= 320),
  app_version text check (char_length(app_version) <= 40),
  os_version text check (char_length(os_version) <= 40),
  device text check (char_length(device) <= 80),
  language text check (char_length(language) <= 10),
  context text check (char_length(context) <= 400),
  resolved boolean not null default false
);

alter table public.app_feedback enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'app_feedback' and policyname = 'Anyone can send feedback') then
    create policy "Anyone can send feedback" on public.app_feedback for insert to anon, authenticated
      with check (user_id is null or user_id = (select auth.uid()));
  end if;
end;
$$;

-- Premium granted without the App Store ---------------------------------------
-- Add a row (Table Editor › premium_grants › Insert) with the person's user id
-- from Authentication › Users. Leave expires_at empty for permanent Premium.
-- Only the owner adds rows (no insert policy); each person can read their own.

create table if not exists public.premium_grants (
  user_id uuid primary key references auth.users (id) on delete cascade,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  note text
);

alter table public.premium_grants enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'premium_grants' and policyname = 'Own grant') then
    create policy "Own grant" on public.premium_grants for select to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;
