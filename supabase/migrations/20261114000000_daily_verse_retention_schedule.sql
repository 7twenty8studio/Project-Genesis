-- Daily Verse Games: nightly screenshot cleanup schedule (PR B).
-- NOT APPLIED to production: applying it needs its own review and approval.
--
-- Storage files can only be deleted through the Storage API, so the cleanup
-- runs in the dv-retention Edge Function. This schedules it with pg_cron +
-- pg_net, the same pattern as Versely's ops-alerts, with its OWN secret and
-- functions (Versely's ops_cron_secret, ops_call_alerts and their jobs are not
-- touched).
--
-- Safe by default: the job calls nothing until the function URL is stored in
-- the Vault as 'dv_retention_url' (a deployment step, after dv-retention is
-- deployed). So applying this migration on a local stack, or before deploy,
-- never calls production.
--
-- Rollback: supabase/rollback/20261114000000_daily_verse_retention_schedule_down.sql

-- The random secret pg_cron sends; dv-retention checks it via retention_secret_matches.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'dv_retention_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'dv_retention_secret', 'Daily Verse retention schedule');
  end if;
end;
$$;

-- Owned by postgres (which can read the Vault), not daily_verse_owner, which
-- has no Vault access and keeps none.
create or replace function daily_verse.retention_secret_matches(p_secret text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select coalesce(
    (select decrypted_secret = p_secret from vault.decrypted_secrets where name = 'dv_retention_secret' limit 1),
    false
  );
$$;

revoke all on function daily_verse.retention_secret_matches(text) from public, anon, authenticated;
grant execute on function daily_verse.retention_secret_matches(text) to service_role;

-- Called by the cron job. Returns the pg_net request id, or null while no URL is set.
create or replace function daily_verse.call_retention()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  url text := (select decrypted_secret from vault.decrypted_secrets where name = 'dv_retention_url' limit 1);
begin
  -- Only Project Genesis's own function (or the local stack's internal gateway,
  -- which isn't reachable from outside), so a mistyped URL can never send the
  -- retention secret to another host.
  if url is null or url !~ '^(https://ulbpwygzwchsnvdeeife\.supabase\.co|http://kong:8000)/functions/v1/dv-retention$' then
    return null;
  end if;
  return net.http_post(
    url := url,
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-dv-retention-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'dv_retention_secret' limit 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function daily_verse.call_retention() from public, anon, authenticated;
grant execute on function daily_verse.call_retention() to service_role;

-- 03:47 UTC daily, after PR A's daily-verse-retention purge (03:17) and away
-- from Versely's ops jobs. There's no one-day lag for reports whose screenshots
-- are cleared here: dv-retention calls purge_expired itself right after the
-- deletions, so a year-old report goes the same night its files do.
select cron.schedule('daily-verse-screenshot-cleanup', '47 3 * * *', $$ select daily_verse.call_retention(); $$);
