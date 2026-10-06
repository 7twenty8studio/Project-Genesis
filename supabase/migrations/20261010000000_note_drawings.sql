-- Project Genesis: handwritten pages on notes (PencilKit), free for everyone.
-- Run once in the SQL Editor after 20260929000000_phase2_sync.sql.
-- Safe to run again: the column (and its size check) is only added if missing.
--
-- `drawing` holds PencilKit's drawing data as base64 text, the way the app's
-- JSON encodes binary data. The check keeps each drawing at 2 MB of base64 or
-- less; the app never sends a larger one (that drawing stays on its device and
-- the rest of the note still syncs). Row-level security on public.notes is
-- unchanged: owners read and write only their own rows.

alter table public.notes add column if not exists drawing text constraint notes_drawing_size check (drawing is null or octet_length(drawing) <= 2097152);

comment on column public.notes.drawing is
  'Handwritten page: base64 of PKDrawing.dataRepresentation(), at most 2 MB of base64; null for none.';
