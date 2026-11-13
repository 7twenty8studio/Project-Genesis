-- Rollback for 20261113000000_daily_verse_reports.sql
--
-- DESTRUCTIVE: removes every Daily Verse report, audit row, admin row and
-- rate-limit row. Export first if anything must be kept (see ROLLBACK.md).
-- Touches nothing outside the daily_verse schema except its own cron job and
-- its own role. Screenshot files under attachments/daily-verse/ are NOT
-- removed by SQL; delete them through the Storage API (ROLLBACK.md, step 3).

set client_min_messages = warning;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-verse-retention') then
    perform cron.unschedule('daily-verse-retention');
  end if;
end;
$$;

drop schema if exists daily_verse cascade;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'daily_verse_owner') then
    execute 'revoke daily_verse_owner from ' || quote_ident(current_user);
    drop role daily_verse_owner;
  end if;
end;
$$;
