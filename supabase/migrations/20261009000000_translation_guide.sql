-- Genesis: the Global Reading Library's details for each downloadable Bible.
-- Run once in the SQL Editor after 20261005000000_translation_language.sql.
-- Safe to run again.
--
-- The Bibles screen groups translations by language and shows, for each one,
-- how it's translated, how it reads, whether it's public domain, and how
-- widely it's read (most read first). Empty values fall back to what the app
-- knows about the translation, so these can be filled in at any time.
--
--   approach       word_for_word | balanced | thought_for_thought
--   reading_level  traditional (older wording) | formal | everyday
--   rights         public_domain | licensed
--   popularity     1 = most read in its language, then 2, 3...
--
-- Whether recorded narration exists comes from public.audio_recordings.

alter table public.bible_translations add column if not exists approach text check (approach in ('word_for_word', 'balanced', 'thought_for_thought'));
alter table public.bible_translations add column if not exists reading_level text check (reading_level in ('traditional', 'formal', 'everyday'));
alter table public.bible_translations add column if not exists rights text check (rights in ('public_domain', 'licensed'));
alter table public.bible_translations add column if not exists popularity integer check (popularity >= 1);

comment on column public.bible_translations.approach is
  'How it is translated: word_for_word, balanced or thought_for_thought.';
comment on column public.bible_translations.reading_level is
  'How it reads: traditional (older wording), formal or everyday.';
comment on column public.bible_translations.rights is
  'public_domain or licensed.';
comment on column public.bible_translations.popularity is
  'Order within its language, 1 = most read.';

-- The translations offered today.
update public.bible_translations
set approach = 'balanced', reading_level = 'everyday', rights = 'public_domain', popularity = 2
where id = 'BSB' and approach is null;

update public.bible_translations
set approach = 'word_for_word', reading_level = 'traditional', rights = 'public_domain', popularity = 1
where id = 'RV1909' and approach is null;
