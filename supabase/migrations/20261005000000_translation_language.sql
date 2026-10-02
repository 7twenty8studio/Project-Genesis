-- Genesis: the language of each downloadable Bible (Spanish screens, Spanish Bibles).
-- Run once in the SQL Editor after 20261004000000_bible_translations.sql.
-- Safe to run again.
--
-- The app reads this to choose a narrating voice that speaks the Bible's
-- language and to offer Bibles in the person's language first. Rows without
-- it are English.

alter table public.bible_translations
  add column if not exists language text not null default 'en'
  check (language ~ '^[a-z]{2,3}(-[A-Z]{2})?$');

comment on column public.bible_translations.language is
  'Language of the text, e.g. en or es.';
