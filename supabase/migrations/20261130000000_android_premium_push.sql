-- Versely for Android: Google Play subscriptions and Android push tokens.
--
-- 1. public.premium_entitlements gains `store`. App Store rows keep their
--    key (the original transaction id, or "<original>:family:<user>");
--    Google Play rows are keyed "play:<purchase token>", written only by the
--    play-sync and play-notifications functions after Google's Play
--    Developer API confirms the subscription. genesis_is_premium() reads
--    every row the same way, so nothing else changes.
-- 2. public.android_push_tokens: Firebase Cloud Messaging tokens, which
--    aren't hex like APNs tokens (push_tokens' check), so they get their own
--    table with the same rules: each person reads and writes only their own.
--    group-notify sends to both.
--
-- Explicit statements only; RLS enabled in a plain alter table line.

alter table public.premium_entitlements
  add column if not exists store text not null default 'app_store'
  check (store in ('app_store', 'google_play'));

comment on column public.premium_entitlements.store is
  'Where the subscription was bought: app_store (key = original transaction id) or google_play (key = "play:<purchase token>").';

create table if not exists public.android_push_tokens (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  token text not null check (char_length(token) between 32 and 4096 and token ~ '^[A-Za-z0-9:_-]+$'),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table public.android_push_tokens enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'android_push_tokens' and policyname = 'Own tokens read') then
    create policy "Own tokens read" on public.android_push_tokens for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'android_push_tokens' and policyname = 'Own tokens add') then
    create policy "Own tokens add" on public.android_push_tokens for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'android_push_tokens' and policyname = 'Own tokens update') then
    create policy "Own tokens update" on public.android_push_tokens for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'android_push_tokens' and policyname = 'Own tokens remove') then
    create policy "Own tokens remove" on public.android_push_tokens for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

grant select, insert, update, delete on public.android_push_tokens to authenticated;
