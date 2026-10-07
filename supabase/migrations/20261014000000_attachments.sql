-- Project Genesis: attachments on prayers and sermon notes (Premium): photos,
-- voice recordings, imported PDFs and Apple Pencil pages.
--
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run,
-- after 20261013000000_sermons.sql. Safe to re-run: it only creates what is
-- missing. Run it before shipping the app version with attachments: sync
-- pulls public.attachments.
--
-- Two parts:
-- 1. public.attachments: each attachment's details, synced like sermons
--    (user_id, updated_at = client edit time, deleted_at = soft delete,
--    server_updated_at = pull cursor). Rows go when the account is deleted.
-- 2. The private storage bucket `attachments` holding the files, at
--    "<user id>/<attachment id>.<ext>". Each person can read and write only
--    their own folder. The delete-account Edge Function empties the folder
--    before the account is deleted.
--
-- Premium on the server: attachments are a Premium feature in the app, but
-- the bucket doesn't check Premium. App Store subscriptions are verified only
-- inside the study-ai Edge Function (public.premium_entitlements is filled
-- when it runs, and the study assistant is switched off), so a policy that
-- required Premium would refuse real subscribers. Uploads are still limited
-- to the person's own folder, 25 MB a file and these four file types.

-- 1. Attachment details ---------------------------------------------------------

create table if not exists public.attachments (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  owner_kind text not null check (owner_kind in ('prayer', 'sermon')),
  owner_id uuid not null,
  kind text not null check (kind in ('photo', 'audio', 'pdf', 'drawing')),
  storage_path text not null check (char_length(storage_path) <= 200),
  bytes bigint not null default 0 check (bytes >= 0 and bytes <= 26214400),
  duration_seconds double precision check (duration_seconds is null or (duration_seconds >= 0 and duration_seconds <= 7300)),
  page_count integer check (page_count is null or page_count >= 0),
  caption text not null default '' check (char_length(caption) <= 500),
  sort_order integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now()
);

alter table public.attachments enable row level security;

create index if not exists attachments_sync_idx on public.attachments (user_id, server_updated_at);
create index if not exists attachments_owner_idx on public.attachments (user_id, owner_kind, owner_id);
create or replace trigger genesis_touch before insert or update on public.attachments
  for each row execute function public.genesis_touch_server_updated_at();

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attachments' and policyname = 'Owner can read') then
    create policy "Owner can read" on public.attachments for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attachments' and policyname = 'Owner can insert') then
    create policy "Owner can insert" on public.attachments for insert to authenticated with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attachments' and policyname = 'Owner can update') then
    create policy "Owner can update" on public.attachments for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'attachments' and policyname = 'Owner can delete') then
    create policy "Owner can delete" on public.attachments for delete to authenticated using (user_id = (select auth.uid()));
  end if;
end;
$$;

comment on table public.attachments is
  'Photos, voice recordings, PDFs and Pencil pages on prayers and sermons (Premium). The file is in the private attachments bucket at storage_path.';

comment on column public.attachments.storage_path is
  '"<user id>/<attachment id>.<ext>" in the attachments storage bucket.';

-- 2. The private bucket -----------------------------------------------------------
-- 25 MB a file. Photos are JPEG, recordings AAC in .m4a (audio/mp4), PDFs,
-- and PencilKit drawings as application/octet-stream. Row-level security on
-- storage.objects is managed by Supabase (always on); the policies below
-- apply only to this bucket.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 26214400, array['image/jpeg', 'audio/mp4', 'application/pdf', 'application/octet-stream'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Attachments: owner can read') then
    create policy "Attachments: owner can read" on storage.objects for select to authenticated
      using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Attachments: owner can upload') then
    create policy "Attachments: owner can upload" on storage.objects for insert to authenticated
      with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Attachments: owner can replace') then
    create policy "Attachments: owner can replace" on storage.objects for update to authenticated
      using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text)
      with check (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Attachments: owner can delete') then
    create policy "Attachments: owner can delete" on storage.objects for delete to authenticated
      using (bucket_id = 'attachments' and (storage.foldername(name))[1] = (select auth.uid())::text);
  end if;
end;
$$;
