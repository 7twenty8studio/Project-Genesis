-- Rollback for 20261117000000_daily_verse_app_attest.sql.
-- Close the public channel first, so no public report is accepted without attestation checks.
update daily_verse.settings set accepted_channels = array['internal'], updated_at = now();
set role daily_verse_owner;
drop function if exists daily_verse.use_attest_key(text, bigint);
drop function if exists daily_verse.register_attest_key(text, bytea, text);
drop table if exists daily_verse.attest_keys;
reset role;
