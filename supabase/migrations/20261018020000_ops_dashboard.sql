-- Versely: the operations dashboard (feedback, reports, crashes, TestFlight
-- feedback and usage in one place) and email alerts by priority.
--
-- Nothing here is readable by the app: every table has row-level security
-- with no policies, so only the ops-dashboard and ops-alerts Edge Functions
-- (service role) use them, after checking the caller.

-- Who may open the dashboard: the owner adds rows (by sign-in email).
create table if not exists public.ops_admins (
  email text primary key,
  created_at timestamptz not null default now()
);
alter table public.ops_admins enable row level security;

-- Triage state for every reported item, whatever its source
-- (feedback, report, sentry, testflight), and when it was emailed.
create table if not exists public.ops_items (
  source text not null,
  external_id text not null,
  status text not null default 'new',
  priority text,
  note text,
  alerted_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (source, external_id),
  constraint ops_items_status check (status in ('new', 'seen', 'resolved')),
  constraint ops_items_priority check (priority is null or priority in ('urgent', 'high', 'normal', 'low'))
);
alter table public.ops_items enable row level security;

-- Small state for the alert job (last digest, last check).
create table if not exists public.ops_state (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.ops_state enable row level security;

-- Usage numbers for the dashboard: counts only, no personal data.
create or replace function public.ops_metrics()
returns jsonb
language sql
security definer
set search_path = ''
stable
as $$
  select jsonb_build_object(
    'accounts', (select count(*) from auth.users),
    'new_accounts_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'new_accounts_30d', (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'signed_in_7d', (select count(*) from auth.users where last_sign_in_at > now() - interval '7 days'),
    'signed_in_30d', (select count(*) from auth.users where last_sign_in_at > now() - interval '30 days'),
    'premium', (
      select count(distinct u) from (
        select e.user_id as u from public.premium_entitlements e where e.expires_at is null or e.expires_at > now()
        union
        select g.user_id from public.premium_grants g where g.expires_at is null or g.expires_at > now()
      ) p
    ),
    'groups', (select count(*) from public.groups where deleted_at is null),
    'group_members', (select count(*) from public.group_members),
    'feedback_7d', (select count(*) from public.app_feedback where created_at > now() - interval '7 days'),
    'reports_open', (select count(*) from public.content_reports where resolved_at is null),
    'syncing_7d', (
      select count(distinct user_id) from (
        select user_id from public.notes where server_updated_at > now() - interval '7 days'
        union select user_id from public.highlights where server_updated_at > now() - interval '7 days'
        union select user_id from public.reading_plans where server_updated_at > now() - interval '7 days'
        union select user_id from public.prayers where server_updated_at > now() - interval '7 days'
      ) s
    ),
    'signups_by_day', (
      select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'count', c) order by d), '[]'::jsonb)
      from (
        select date_trunc('day', created_at) d, count(*) c
        from auth.users where created_at > now() - interval '30 days'
        group by 1
      ) x
    )
  );
$$;

revoke all on function public.ops_metrics() from public, anon, authenticated;
grant execute on function public.ops_metrics() to service_role;

-- The scheduled alert job proves itself with a random secret kept in the
-- Vault (made here, never written anywhere else).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'ops_cron_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'ops_cron_secret', 'ops-alerts schedule');
  end if;
end;
$$;

create or replace function public.ops_cron_secret_matches(p_secret text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select coalesce(
    (select decrypted_secret = p_secret from vault.decrypted_secrets where name = 'ops_cron_secret' limit 1),
    false
  );
$$;

revoke all on function public.ops_cron_secret_matches(text) from public, anon, authenticated;
grant execute on function public.ops_cron_secret_matches(text) to service_role;
