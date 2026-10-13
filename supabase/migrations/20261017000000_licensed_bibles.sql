-- Versely: licensed Bibles from the Digital Bible Library.
--
-- Their files go in this private bucket, never the public "bibles" one. No
-- storage policies: only the service role (the bible-file Edge Function)
-- reads it, handing the app ten-minute download links while the catalog row
-- is enabled with rights = 'licensed'. Upload in the dashboard: Storage ->
-- licensed-bibles -> Upload (LICENSED_BIBLES.md).
insert into storage.buckets (id, name, public)
values ('licensed-bibles', 'licensed-bibles', false)
on conflict (id) do nothing;

-- Bibles whose publishers charge Versely a licence fee are Premium; every
-- Bible Versely may offer free stays free (the default). bible-file checks
-- Premium before giving a link to a Premium Bible.
alter table public.bible_translations add column if not exists premium boolean not null default false;
