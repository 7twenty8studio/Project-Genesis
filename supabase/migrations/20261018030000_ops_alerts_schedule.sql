-- Versely: runs ops-alerts on a schedule (pg_cron + pg_net).
-- Every five minutes: email anything urgent that just arrived.
-- Every morning at 13:00 UTC (8:00 in Chicago in summer, 7:00 in winter):
-- the daily digest. The request carries the Vault's ops_cron_secret, which
-- ops-alerts checks; nothing else can make it send mail.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Admin emails are compared in lower case.
alter table public.ops_admins add constraint ops_admins_lowercase check (email = lower(email));

create or replace function public.ops_call_alerts(p_kind text)
returns bigint
language sql
security definer
set search_path = ''
as $$
  select net.http_post(
    url := 'https://ulbpwygzwchsnvdeeife.supabase.co/functions/v1/ops-alerts',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-ops-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'ops_cron_secret' limit 1)
    ),
    body := jsonb_build_object('kind', p_kind),
    timeout_milliseconds := 30000
  );
$$;

revoke all on function public.ops_call_alerts(text) from public, anon, authenticated;
grant execute on function public.ops_call_alerts(text) to service_role;

select cron.schedule('ops-alerts-check', '*/5 * * * *', $$ select public.ops_call_alerts('check'); $$);
select cron.schedule('ops-alerts-digest', '0 13 * * *', $$ select public.ops_call_alerts('digest'); $$);
