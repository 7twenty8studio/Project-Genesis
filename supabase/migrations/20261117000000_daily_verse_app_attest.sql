-- Daily Verse Games: App Attest keys for public problem reports (1.0).
--
-- Before the public App Store build may submit reports, every report must be
-- signed by a key that Apple's App Attest service has certified as belonging
-- to the genuine Daily Verse Games app on a real Apple device (PR_B_CONTRACT.md
-- rule 2). The dv-attest Edge Function verifies the attestation once per
-- install and stores the key here; dv-report then checks an assertion (a
-- signature over a fresh server challenge and the exact report body) and the
-- key's counter before anything reaches daily_verse.submit_report.
--
-- Stored per key: an HMAC of Apple's key identifier (DV_HMAC_SECRET pepper,
-- like the install and network hashes), the key's public key, its signature
-- counter and timestamps. No device name, Apple ID, IP address or report
-- content is stored here. Keys unused for 180 days are purged.
--
-- This migration does NOT open the public channel. That is a separate,
-- deliberate step once dv-report with attestation is deployed:
--   update daily_verse.settings set accepted_channels = array['internal', 'public'], updated_at = now();
-- Rollback: supabase/rollback/20261117000000_daily_verse_app_attest_down.sql

set role daily_verse_owner;

create table daily_verse.attest_keys (
  key_hash text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  public_key bytea not null check (octet_length(public_key) = 65),
  environment text not null check (environment in ('production', 'development')),
  sign_count bigint not null default 0 check (sign_count >= 0),
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now()
);
alter table daily_verse.attest_keys enable row level security;
-- No policies. The service role may read it (dv-report looks keys up); writes go
-- through the functions below only.
grant select on daily_verse.attest_keys to service_role;

-- Stores a key whose attestation dv-attest has verified. Registering the same
-- key again is a no-op (an app may retry after a lost response). Also purges
-- keys idle for 180 days, so the table needs no separate schedule.
create function daily_verse.register_attest_key(p_key_hash text, p_public_key bytea, p_environment text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from daily_verse.attest_keys where last_used_at < now() - interval '180 days';
  insert into daily_verse.attest_keys (key_hash, public_key, environment)
  values (p_key_hash, p_public_key, p_environment)
  on conflict (key_hash) do nothing;
end;
$$;

-- Records a verified assertion. Returns false when the counter does not move
-- forward (a replayed assertion) or the key is unknown, true otherwise.
create function daily_verse.use_attest_key(p_key_hash text, p_counter bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated integer;
begin
  update daily_verse.attest_keys
  set sign_count = p_counter, last_used_at = now()
  where key_hash = p_key_hash and sign_count < p_counter;
  get diagnostics updated = row_count;
  return updated = 1;
end;
$$;

revoke all on function daily_verse.register_attest_key(text, bytea, text) from public;
revoke all on function daily_verse.use_attest_key(text, bigint) from public;
grant execute on function daily_verse.register_attest_key(text, bytea, text) to service_role;
grant execute on function daily_verse.use_attest_key(text, bigint) to service_role;

reset role;
