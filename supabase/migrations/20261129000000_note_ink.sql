-- Handwritten pages in one format for iPhone, iPad and Android (Versely Ink,
-- docs/HANDWRITING_FORMAT.md). notes.drawing stays PencilKit's own data for
-- iOS; notes.ink is the shared JSON page, at most 2 MB like drawing.
alter table public.notes add column if not exists ink text;

alter table public.notes add constraint notes_ink_size
  check (ink is null or octet_length(ink) <= 2097152);

comment on column public.notes.ink is
  'Versely Ink handwritten page (JSON, docs/HANDWRITING_FORMAT.md), written by iOS and Android.';
