-- Rollback for 20261114000000_daily_verse_retention_schedule.sql.
-- Removes only what that migration added: the cron job, the two functions and
-- the two Vault entries. Daily Verse data and Versely are not touched.

set client_min_messages = warning;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-verse-screenshot-cleanup') then
    perform cron.unschedule('daily-verse-screenshot-cleanup');
  end if;
end;
$$;

drop function if exists daily_verse.call_retention();
drop function if exists daily_verse.retention_secret_matches(text);

delete from vault.secrets where name in ('dv_retention_secret', 'dv_retention_url');
