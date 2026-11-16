-- Rollback for 20261117000000_daily_verse_app_attest.sql.
-- Removes only what that migration added and restores purge_expired as it
-- was. Reports stay (their client_report_id column is dropped). Public
-- reports are closed first, since nothing would verify them any more.
-- Versely is not touched.

set client_min_messages = warning;
set role daily_verse_owner;

update daily_verse.settings set accepted_channels = array['internal'], updated_at = now() where id = 1;

drop function if exists daily_verse.submit_report_once(uuid, text, text, text, text, text, text, text, text, text, date, text, text, text, text, text);
drop function if exists daily_verse.advance_attest_key(text, bigint);
drop function if exists daily_verse.get_attest_key(text);
drop function if exists daily_verse.register_attest_key(text, bytea, text, text);
drop function if exists daily_verse.consume_challenge(text, text);
drop function if exists daily_verse.issue_challenge(text, text, text);
drop table if exists daily_verse.attest_keys;
drop table if exists daily_verse.attest_challenges;
drop index if exists daily_verse.reports_client_report_idx;
alter table daily_verse.reports drop column if exists client_report_id;
delete from daily_verse.rate_limits where key like 'chal:%' or key like 'attest:%' or key like 'key:%';

create or replace function daily_verse.purge_expired()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reports_deleted integer;
  limits_deleted integer;
begin
  delete from daily_verse.reports
  where created_at < now() - interval '1 year' and cardinality(screenshot_paths) = 0;
  get diagnostics reports_deleted = row_count;
  delete from daily_verse.rate_limits where key <> 'global' and refilled_at < now() - interval '2 days';
  get diagnostics limits_deleted = row_count;
  return jsonb_build_object('reports', reports_deleted, 'rate_limits', limits_deleted);
end;
$$;
revoke all on function daily_verse.purge_expired() from public;
grant execute on function daily_verse.purge_expired() to service_role;

reset role;
