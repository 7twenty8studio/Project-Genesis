-- Read-only: current channels, App Attest objects present, and the latest reports (no content).
select accepted_channels::text as accepted_channels, updated_at from daily_verse.settings;
select to_regclass('daily_verse.attest_keys') is not null as attest_keys_table,
       to_regprocedure('daily_verse.use_attest_key(text,bigint)') is not null as use_attest_key_fn;
select id, created_at, channel, build, content_language, puzzle_type, content_id, category, status
from daily_verse.reports order by created_at desc limit 10;
