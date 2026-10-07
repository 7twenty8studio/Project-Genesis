-- Project Genesis: the prayer journal's passages and "I prayed" (free for everyone).
-- Run once in the SQL Editor after 20260929000000_phase2_sync.sql.
-- Safe to run again: each column (and its check) is only added if missing.
--
-- `passages` holds the Bible passages a prayer is attached to, as verse ids
-- only ([{"start_verse": 43003016, "end_verse": 43003017}, ...]); the app
-- shows the words from the person's Bible, never stored here. Older app
-- versions leave the column untouched when they save a prayer.
-- `last_prayed_at` is the last time the person marked the prayer as prayed
-- (it feeds their prayer streak).
-- Row-level security on public.prayers is unchanged: owners read and write
-- only their own rows.

alter table public.prayers add column if not exists passages jsonb not null default '[]'::jsonb constraint prayers_passages_shape check (jsonb_typeof(passages) = 'array' and jsonb_array_length(passages) <= 100);

alter table public.prayers add column if not exists last_prayed_at timestamptz;

alter table public.prayers enable row level security;

comment on column public.prayers.passages is
  'Attached passages as [{"start_verse": int, "end_verse": int}] verse ids (book*1000000 + chapter*1000 + verse); never verse text.';

comment on column public.prayers.last_prayed_at is
  'When the person last marked this prayer as prayed (client time).';
