-- Project Genesis: Premium known to the database, and attachment uploads
-- (a Premium feature) checked against it.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run,
-- after 20261014000000_attachments.sql. Safe to re-run.
--
-- Before running it, deploy the premium-sync and appstore-notifications Edge
-- Functions (APPLE_SETUP.md). public.premium_entitlements is filled by:
-- - premium-sync: the app sends its App Store subscription after a purchase or
--   restore, on sign-in, and when the subscription changes;
-- - appstore-notifications: Apple tells the server about renewals, expiry,
--   grace periods, refunds and Family Sharing changes;
-- - study-ai, as before.
-- Since 20261015 attachment files go to each person's iCloud, so the app
-- no longer uploads to this bucket; the upload policy below is legacy (kept
-- because this file is already applied). Only the comments changed since.
--
-- Reading and deleting files is NOT limited to Premium: people keep their own
-- files if Premium lapses (and account deletion still empties the folder).

-- 1. Is the person asking Premium? ------------------------------------------
-- An App Store subscription on file (with three days' grace for a renewal
-- that hasn't been reported yet), or an active grant from the owner.

create or replace function public.genesis_is_premium()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1
      from public.premium_entitlements e
      where e.user_id = (select auth.uid())
        and e.expires_at > now() - interval '3 days'
    )
    or exists (
      select 1
      from public.premium_grants g
      where g.user_id = (select auth.uid())
        and (g.expires_at is null or g.expires_at > now())
    );
$$;

revoke all on function public.genesis_is_premium() from public;
revoke all on function public.genesis_is_premium() from anon;
grant execute on function public.genesis_is_premium() to authenticated;
grant execute on function public.genesis_is_premium() to service_role;

-- 2. Uploads to the attachments bucket need Premium -------------------------
-- Same folder rule as before ("<user id>/..."), plus Premium. Uploads use
-- upsert, so both the insert and the update policy check it.

alter policy "Attachments: owner can upload" on storage.objects
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.genesis_is_premium()
  );

alter policy "Attachments: owner can replace" on storage.objects
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.genesis_is_premium()
  );
