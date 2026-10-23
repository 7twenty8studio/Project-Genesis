-- YouVersion Platform Bibles: what the publishers' agreements ask of us
-- (LICENSED_BIBLES.md › 5; Biblica: NIV, NIrV, NVI; Lockman: NASB, NBLA,
-- LBLA).
--
-- 1. A link to the publisher wherever its text is shown: the copyright line
--    under every chapter opens publisher_url (Biblica: a one-step link with
--    "Biblica" in it, which the notice has; Lockman: its home page).
-- 2. Lockman's own notices for a whole Bible, word for word from its
--    agreement (the Platform's metadata for NBLA and LBLA is only a fragment).
--    Biblica's stay as the Platform's metadata gives them, as its agreement
--    asks.
-- 3. Footnotes are now included (Biblica requires every one): the shared
--    chapter cache (stored without notes) is emptied. Devices rebuild
--    Bibles made before notes on their own (YouVersionBibleBuilder.format),
--    so no version bump: older app builds would rebuild for nothing.
-- 4. Lockman asks each February for the number of copies distributed the
--    year before: an anonymous count of finished downloads per Bible and
--    year, recorded by the app through record_youversion_download().

alter table public.youversion_bibles add column if not exists publisher_url text;

update public.youversion_bibles set publisher_url = 'https://www.biblica.com' where id in ('NIV', 'NIrV', 'NVI');
update public.youversion_bibles set publisher_url = 'https://www.lockman.org' where id in ('NASB', 'NBLA', 'LBLA');

update public.youversion_bibles set license = E'New American Standard Bible – NASB 2020\nCopyright © 1960, 1971, 1977, 1995, 2020 by The Lockman Foundation, La Habra, Calif. Used by permission. All rights reserved. For Permission to Quote Information visit www.Lockman.org' where id = 'NASB';
update public.youversion_bibles set license = E'Nueva Biblia de las Américas - NBLA\nCopyright © 2005 by The Lockman Foundation\nLa Habra, California. Used by permission. All rights reserved. Derechos Reservados - All Rights Reserved www.NuevaBiblia.com (Español) www.Lockman.org (English)' where id = 'NBLA';
update public.youversion_bibles set license = E'La Biblia de las Américas - LBLA\nCopyright © 1986, 1995, 1997 by The Lockman Foundation\nLa Habra, California. Used by permission. All rights reserved. Derechos Reservados - All Rights Reserved www.NuevaBiblia.com (Español) www.Lockman.org (English)' where id = 'LBLA';

update public.youversion_bibles set updated_at = now();

delete from public.yvp_chapter_cache;

create table if not exists public.youversion_download_counts (
  bible text not null references public.youversion_bibles (id),
  year integer not null,
  downloads integer not null default 0 check (downloads >= 0),
  primary key (bible, year)
);

alter table public.youversion_download_counts enable row level security;

-- No policies: read in the dashboard (service role); written only below.

create or replace function public.record_youversion_download(p_bible text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.youversion_bibles where id = p_bible) then
    return;
  end if;
  insert into public.youversion_download_counts (bible, year, downloads)
  values (p_bible, extract(year from now())::integer, 1)
  on conflict (bible, year) do update set downloads = public.youversion_download_counts.downloads + 1;
end;
$$;

revoke all on function public.record_youversion_download(text) from public;
grant execute on function public.record_youversion_download(text) to anon, authenticated;
