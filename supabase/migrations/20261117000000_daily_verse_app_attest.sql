-- Daily Verse Games 1.0: public in-app reports, protected by App Attest.
--
-- Adds, inside the daily_verse schema only:
--   * attest_challenges — single-use server challenges (5 minutes), stored as
--     SHA-256 hashes, so a challenge can't be replayed or forged;
--   * attest_keys       — one App Attest key per app install, after dv-report
--     has verified its attestation against Apple's root. Stored by HMAC of the
--     key id (never the raw id), with its public key, environment and the
--     signature counter (rises with every report; stops replays);
--   * reports.client_report_id — the app's own id for a report, so a retry
--     after a failure or a lost reply is kept once, never twice;
--   * functions for those, all SECURITY DEFINER, owned by daily_verse_owner,
--     callable only by service_role (the dv-report Edge Function);
--   * purge_expired also deletes used/expired challenges and keys idle a year.
--
-- It does NOT open public reports: settings.accepted_channels stays {internal}.
-- Opening them is a separate, approved one-line change (PUBLIC_REPORTS.md).
-- Nothing in public, storage or auth is created, altered or dropped; Versely
-- is unchanged. Rollback: supabase/rollback/20261117000000_daily_verse_app_attest_down.sql

set role daily_verse_owner;

-- Challenges -------------------------------------------------------------------
create table daily_verse.attest_challenges (
  challenge_hash text primary key check (challenge_hash ~ '^[0-9a-f]{64}$'),
  purpose text not null check (purpose in ('attest', 'report')),
  expires_at timestamptz not null
);
create index attest_challenges_expiry_idx on daily_verse.attest_challenges (expires_at);

-- Keys ---------------------------------------------------------------------------
create table daily_verse.attest_keys (
  key_hash text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  public_key bytea not null check (octet_length(public_key) between 60 and 200),
  environment text not null check (environment in ('production', 'development')),
  sign_count bigint not null default 0 check (sign_count >= 0),
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now()
);
create index attest_keys_idle_idx on daily_verse.attest_keys (last_used_at);

-- Retries --------------------------------------------------------------------------
alter table daily_verse.reports add column client_report_id uuid;
create unique index reports_client_report_idx on daily_verse.reports (client_report_id) where client_report_id is not null;

alter table daily_verse.attest_challenges enable row level security;
alter table daily_verse.attest_keys enable row level security;
-- No policies, as for the other daily_verse tables; writes only through the functions below.
grant select on daily_verse.attest_challenges to service_role;
grant select on daily_verse.attest_keys to service_role;

-- Issues a challenge (its SHA-256, computed by dv-report). Rate-limited per
-- network (60 an hour, burst 20) and overall (1,200 an hour).
create function daily_verse.issue_challenge(p_challenge_hash text, p_purpose text, p_net_hash text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  wait double precision;
begin
  if p_net_hash is null or p_net_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid network key' using errcode = '22023';
  end if;
  wait := greatest(
    daily_verse.take_token('chal:' || p_net_hash, 60, 20),
    daily_verse.take_token('chal:global', 1200, 300)
  );
  if wait > 0 then
    raise exception 'rate_limited' using errcode = 'P0001', hint = ceil(wait)::text;
  end if;
  insert into daily_verse.attest_challenges (challenge_hash, purpose, expires_at)
  values (p_challenge_hash, p_purpose, now() + interval '5 minutes');
end;
$$;

-- Uses up a challenge: true once, if it exists, has this purpose and hasn't expired.
create function daily_verse.consume_challenge(p_challenge_hash text, p_purpose text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  found_ text;
begin
  delete from daily_verse.attest_challenges
  where challenge_hash = p_challenge_hash and purpose = p_purpose and expires_at > now()
  returning challenge_hash into found_;
  return found_ is not null;
end;
$$;

-- Stores a key whose attestation dv-report has verified. Rate-limited per
-- network (10 an hour). A key id seen before keeps its first row: an
-- attestation only ever happens once per key, with counter 0.
create function daily_verse.register_attest_key(p_key_hash text, p_public_key bytea, p_environment text, p_net_hash text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  wait double precision;
begin
  if p_net_hash is null or p_net_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid network key' using errcode = '22023';
  end if;
  wait := daily_verse.take_token('attest:' || p_net_hash, 10, 10);
  if wait > 0 then
    raise exception 'rate_limited' using errcode = 'P0001', hint = ceil(wait)::text;
  end if;
  insert into daily_verse.attest_keys (key_hash, public_key, environment)
  values (p_key_hash, p_public_key, p_environment)
  on conflict (key_hash) do nothing;
end;
$$;

-- A stored key, or no row.
create function daily_verse.get_attest_key(p_key_hash text)
returns table (public_key bytea, environment text, sign_count bigint)
language sql
security definer
set search_path = ''
stable
as $$
  select k.public_key, k.environment, k.sign_count from daily_verse.attest_keys k where k.key_hash = p_key_hash;
$$;

-- Moves the key's counter forward; false if it isn't above the stored one
-- (a replayed or out-of-order assertion), so only one request per counter wins.
create function daily_verse.advance_attest_key(p_key_hash text, p_sign_count bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update daily_verse.attest_keys set sign_count = p_sign_count, last_used_at = now()
  where key_hash = p_key_hash and sign_count < p_sign_count;
  return found;
end;
$$;

-- Accepts a report with the app's own id. The same client_report_id again
-- (a retry) returns the first report's id and saves nothing new, if it came
-- from the same install; from another install it's refused. Otherwise it's
-- submit_report (channel gate, spam rules, rate limits, 10-minute
-- duplicate rule) plus one more rate limit per attested key (5 an hour).
create function daily_verse.submit_report_once(
  p_client_report_id uuid, p_key_hash text,
  p_channel text, p_app_version text, p_build text, p_os_version text, p_device_family text,
  p_content_language text, p_puzzle_type text, p_content_id text, p_challenge_date date,
  p_review_state text, p_category text, p_description text, p_install_hash text, p_net_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing uuid;
  existing_install text;
  new_id uuid;
  wait double precision;
begin
  if p_client_report_id is null then
    raise exception 'invalid report id' using errcode = '22023';
  end if;
  select id, install_hash into existing, existing_install from daily_verse.reports where client_report_id = p_client_report_id;
  if existing is not null then
    if existing_install = p_install_hash then return existing; end if;
    raise exception 'invalid report id' using errcode = '22023';
  end if;

  if p_key_hash is not null then
    wait := daily_verse.take_token('key:' || p_key_hash, 5, 5);
    if wait > 0 then
      raise exception 'rate_limited' using errcode = 'P0001', hint = ceil(wait)::text;
    end if;
  end if;

  begin
    new_id := daily_verse.submit_report(
      p_channel, p_app_version, p_build, p_os_version, p_device_family, p_content_language, p_puzzle_type,
      p_content_id, p_challenge_date, p_review_state, p_category, p_description, p_install_hash, p_net_hash
    );
    -- A report kept by the 10-minute rule may already carry another retry id; it keeps that one.
    update daily_verse.reports set client_report_id = p_client_report_id
    where id = new_id and client_report_id is null;
  exception when unique_violation then
    -- Two copies of the same retry at once: the other one won.
    select id into existing from daily_verse.reports where client_report_id = p_client_report_id;
    return existing;
  end;
  return new_id;
end;
$$;

-- Retention: as before, plus challenges past their 5 minutes and keys unused
-- for a year (the app simply attests a new key next time).
create or replace function daily_verse.purge_expired()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reports_deleted integer;
  limits_deleted integer;
  challenges_deleted integer;
  keys_deleted integer;
begin
  delete from daily_verse.reports
  where created_at < now() - interval '1 year' and cardinality(screenshot_paths) = 0;
  get diagnostics reports_deleted = row_count;
  delete from daily_verse.rate_limits where key not in ('global', 'chal:global') and refilled_at < now() - interval '2 days';
  get diagnostics limits_deleted = row_count;
  delete from daily_verse.attest_challenges where expires_at < now();
  get diagnostics challenges_deleted = row_count;
  delete from daily_verse.attest_keys where last_used_at < now() - interval '1 year';
  get diagnostics keys_deleted = row_count;
  return jsonb_build_object('reports', reports_deleted, 'rate_limits', limits_deleted,
                            'challenges', challenges_deleted, 'attest_keys', keys_deleted);
end;
$$;

revoke all on function daily_verse.issue_challenge(text, text, text) from public;
revoke all on function daily_verse.consume_challenge(text, text) from public;
revoke all on function daily_verse.register_attest_key(text, bytea, text, text) from public;
revoke all on function daily_verse.get_attest_key(text) from public;
revoke all on function daily_verse.advance_attest_key(text, bigint) from public;
revoke all on function daily_verse.submit_report_once(uuid, text, text, text, text, text, text, text, text, text, date, text, text, text, text, text) from public;
revoke all on function daily_verse.purge_expired() from public;
grant execute on function daily_verse.issue_challenge(text, text, text) to service_role;
grant execute on function daily_verse.consume_challenge(text, text) to service_role;
grant execute on function daily_verse.register_attest_key(text, bytea, text, text) to service_role;
grant execute on function daily_verse.get_attest_key(text) to service_role;
grant execute on function daily_verse.advance_attest_key(text, bigint) to service_role;
grant execute on function daily_verse.submit_report_once(uuid, text, text, text, text, text, text, text, text, text, date, text, text, text, text, text) to service_role;
grant execute on function daily_verse.purge_expired() to service_role;

reset role;
