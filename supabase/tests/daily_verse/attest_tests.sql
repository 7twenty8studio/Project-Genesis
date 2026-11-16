-- Checks for 20261117000000_daily_verse_app_attest.sql (run by run_attest.sh as superuser).
\set ON_ERROR_STOP 1
create temp table results (name text, ok boolean);

-- service_role registers a key; a second registration is a no-op.
set role service_role;
select daily_verse.register_attest_key(repeat('a', 64), decode(repeat('04', 65), 'hex'), 'production');
select daily_verse.register_attest_key(repeat('a', 64), decode(repeat('05', 65), 'hex'), 'production');
reset role;
insert into results select 'register is idempotent', count(*) = 1 and bool_and(public_key = decode(repeat('04', 65), 'hex'))
  from daily_verse.attest_keys;

set role service_role;
create temp table c as select
  daily_verse.use_attest_key(repeat('a', 64), 1) as first,
  daily_verse.use_attest_key(repeat('a', 64), 1) as replay,
  daily_verse.use_attest_key(repeat('a', 64), 5) as later,
  daily_verse.use_attest_key(repeat('a', 64), 3) as backwards,
  daily_verse.use_attest_key(repeat('b', 64), 1) as unknown;
reset role;
insert into results select 'counter must move forward', first and not replay and later and not backwards and not unknown from c;
insert into results select 'counter stored', sign_count = 5 from daily_verse.attest_keys;

-- Bad values are refused by the table checks.
do $$ begin
  begin
    perform daily_verse.register_attest_key('not-a-hash', decode(repeat('04', 65), 'hex'), 'production');
    insert into results values ('bad key hash refused', false);
  exception when check_violation then insert into results values ('bad key hash refused', true); end;
  begin
    perform daily_verse.register_attest_key(repeat('c', 64), decode('04', 'hex'), 'production');
    insert into results values ('short public key refused', false);
  exception when check_violation then insert into results values ('short public key refused', true); end;
  begin
    perform daily_verse.register_attest_key(repeat('c', 64), decode(repeat('04', 65), 'hex'), 'other');
    insert into results values ('unknown environment refused', false);
  exception when check_violation then insert into results values ('unknown environment refused', true); end;
end $$;

-- Idle keys are purged on the next registration.
update daily_verse.attest_keys set last_used_at = now() - interval '181 days';
set role service_role;
select daily_verse.register_attest_key(repeat('d', 64), decode(repeat('04', 65), 'hex'), 'production');
reset role;
insert into results select 'idle keys purged', array_agg(key_hash) = array[repeat('d', 64)] from daily_verse.attest_keys;

-- anon and authenticated can't read keys or call the functions; service_role can't write the table directly.
do $$ begin
  begin
    set local role anon;
    perform 1 from daily_verse.attest_keys;
    insert into results values ('anon cannot read keys', false);
  exception when insufficient_privilege then reset role; insert into results values ('anon cannot read keys', true); end;
  begin
    set local role authenticated;
    perform daily_verse.use_attest_key(repeat('d', 64), 9);
    insert into results values ('authenticated cannot use keys', false);
  exception when insufficient_privilege then reset role; insert into results values ('authenticated cannot use keys', true); end;
  begin
    set local role service_role;
    update daily_verse.attest_keys set sign_count = 0;
    insert into results values ('service_role cannot write keys directly', false);
  exception when insufficient_privilege then reset role; insert into results values ('service_role cannot write keys directly', true); end;
end $$;

-- The migration does not open the public channel.
insert into results select 'public channel still closed', accepted_channels = array['internal'] from daily_verse.settings;

select case when ok then 'PASS' else 'FAIL' end, name from results order by ok, name;
select count(*) filter (where not ok) as failures, count(*) as checks from results;
