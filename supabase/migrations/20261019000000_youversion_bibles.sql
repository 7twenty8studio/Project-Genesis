-- Versely: Bibles from the YouVersion Platform (YVP).
--
-- Each row is a Bible our Platform app key may use (check with the
-- yvp-catalog function). The app lists enabled rows in the Bibles library
-- and builds the Bible on the device, book by book, through the yvp-bible
-- Edge Function; nothing of the text is stored on the server.
--
-- Terms agreed with YouVersion in writing (LICENSED_BIBLES.md › 5):
-- always free to read (there is no premium column on purpose), never shown
-- in a paid feature, stored on the device unless the publisher limits
-- caching, refreshed when online. Turning a row off stops new downloads and
-- removes the Bible from devices the next time the app loads the catalog.
--
-- `version`: raise it to make devices download the Bible again (on Wi-Fi),
-- for example after a publisher's correction.

create table if not exists public.youversion_bibles (
  -- The app's id for it, shown as its abbreviation; keeps the publisher's
  -- casing (NIrV).
  id text primary key check (id ~ '^[A-Za-z0-9]{2,8}$'),
  -- The Bible's id on the YouVersion Platform (GET /v1/bibles/{id}).
  yvp_id integer not null unique check (yvp_id > 0),
  name text not null,
  year text not null default '',
  -- The copyright statement exactly as the Platform gives it; shown under
  -- every chapter.
  license text not null,
  summary text not null default '',
  language text not null default 'en' check (language ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
  approach text check (approach in ('word_for_word', 'balanced', 'thought_for_thought')),
  reading_level text check (reading_level in ('traditional', 'formal', 'everyday')),
  popularity integer check (popularity >= 1),
  version integer not null default 1 check (version >= 1),
  enabled boolean not null default false,
  sort integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.youversion_bibles enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'youversion_bibles' and policyname = 'Anyone can read enabled YouVersion Bibles') then
    create policy "Anyone can read enabled YouVersion Bibles" on public.youversion_bibles for select to anon, authenticated using (enabled);
  end if;
end;
$$;

-- The first six, chosen by the owner (20 October 2026). Copyright
-- statements as the Platform returned them that day.
insert into public.youversion_bibles (id, yvp_id, name, year, license, summary, language, approach, reading_level, popularity, enabled, sort)
values
  ('NIV', 111, 'New International Version', '2011',
   E'The Holy Bible, New International Version® NIV®\nCopyright © 1973, 1978, 1984, 2011 by Biblica, Inc.®\nUsed by Permission of Biblica, Inc.® All rights reserved worldwide.',
   'Accurate and readable, the most read modern English Bible.',
   'en', 'balanced', 'everyday', 1, true, 30),
  ('NASB', 2692, 'New American Standard Bible', '2020',
   E'NEW AMERICAN STANDARD BIBLE® NASB®\nCopyright © 1960, 1971, 1977,1995, 2020 by The Lockman Foundation\nA Corporation Not for Profit\nLa Habra, CA\nAll Rights Reserved\nwww.lockman.org',
   'A precise, word-for-word translation trusted for close study.',
   'en', 'word_for_word', 'formal', 2, true, 31),
  ('NIrV', 110, 'New International Reader’s Version', '2014',
   E'Holy Bible, New International Reader’s Version®, NIrV®\nCopyright © 1995, 1996, 1998, 2014 by Biblica, Inc.®\nUsed by permission. All rights reserved worldwide.',
   'The NIV in simpler words and shorter sentences, for children and new readers.',
   'en', 'thought_for_thought', 'everyday', 5, true, 32),
  ('NVI', 128, 'Nueva Versión Internacional', '2025',
   'Santa Biblia, Nueva Versión Internacional® NVI® | © 1999, 2015, 2022 por Biblica, Inc. | Usado con permiso. Reservados todos los derechos en todo el mundo.',
   'Una traducción moderna, clara y fiel, de las más leídas en español.',
   'es', 'balanced', 'everyday', 1, true, 33),
  ('NBLA', 103, 'Nueva Biblia de las Américas', '2005',
   '1986, 1995, 1997, 2005 by The Lockman Foundation',
   'Precisa y fiel al original, en un español claro y actual.',
   'es', 'word_for_word', 'formal', 2, true, 34),
  ('LBLA', 89, 'La Biblia de las Américas', '1997',
   '1986, 1995, 1997 by The Lockman Foundation',
   'Una traducción literal y precisa, muy apreciada para el estudio.',
   'es', 'word_for_word', 'formal', 3, true, 35)
on conflict (id) do nothing;
