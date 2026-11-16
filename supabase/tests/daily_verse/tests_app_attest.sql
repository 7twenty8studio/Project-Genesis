-- Tests for 20261117000000_daily_verse_app_attest.sql (challenges, attested
-- keys, retry-safe reports). Run by run.sh after tests.sql, on a database with
-- both migrations applied. Prints a summary and fails if any check fails.

set client_min_messages = warning;
drop schema if exists dvat cascade;
create schema dvat;
create table dvat.results (n serial, name text, ok boolean, detail text);

create function dvat.check(name text, cond boolean, detail text default null) returns void
language plpgsql as $$
begin
  insert into dvat.results (name, ok, detail) values (name, coalesce(cond, false), detail);
end $$;

-- Runs `sql` as `role_` and expects an error with this SQLSTATE or message fragment.
create function dvat.raises(name text, role_ text, sql text, expect text) returns void
language plpgsql as $$
declare ok boolean; detail text;
begin
  begin
    execute format('set local role %I', role_);
    execute sql;
    ok := false; detail := 'no error';
  exception when others then
    ok := (sqlstate = expect or position(expect in sqlerrm) > 0); detail := sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  insert into dvat.results (name, ok, detail) values (name, ok, detail);
end $$;

create function dvat.h(v text) returns text language sql as $$ select encode(digest(v, 'sha256'), 'hex') $$;
-- The service role and API roles may call the helper (tests switch roles around it).
grant usage on schema dvat to service_role, anon, authenticated;
grant execute on function dvat.h(text) to service_role, anon, authenticated;

-- A report through submit_report_once as the service role.
create function dvat.submit(client uuid, install text, content text, key_ text default null, chan text default 'public',
                            descr text default 'La pista 3 no coincide con el versículo.') returns uuid
language plpgsql as $$
declare id_ uuid;
  kh text := case when key_ is null then null else dvat.h(key_) end;
  ih text := dvat.h(install);
  nh text := dvat.h('net-' || install);
begin
  set local role service_role;
  id_ := daily_verse.submit_report_once(client, kh,
    chan, '1.0', '202611170100', '26.1', 'phone', 'es', 'crossword', content, date '2027-04-03', 'approved',
    'unclear_clue', descr, ih, nh);
  reset role;
  return id_;
end $$;

-- Grants: nobody but service_role ---------------------------------------------------
do $$
declare r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    perform dvat.raises(r || ' cannot issue challenges', r, $q$select daily_verse.issue_challenge(dvat.h('c'), 'report', dvat.h('n'))$q$, '42501');
    perform dvat.raises(r || ' cannot register keys', r, $q$select daily_verse.register_attest_key(dvat.h('k'), '\x00'::bytea, 'production', dvat.h('n'))$q$, '42501');
    perform dvat.raises(r || ' cannot read keys', r, $q$select * from daily_verse.attest_keys$q$, '42501');
    perform dvat.raises(r || ' cannot submit reports', r, $q$select daily_verse.submit_report_once(gen_random_uuid(), null, 'public', '1', '1', null, null, 'en', 'other', 'x', null, null, 'other', 'x', dvat.h('i'), dvat.h('n'))$q$, '42501');
  end loop;
end $$;
select dvat.check('both new tables have row-level security',
  (select bool_and(relrowsecurity) from pg_class where oid in ('daily_verse.attest_challenges'::regclass, 'daily_verse.attest_keys'::regclass)));
select dvat.check('public reports stay closed after the migration',
  (select accepted_channels = array['internal'] from daily_verse.settings));

-- Challenges ------------------------------------------------------------------------------
do $$
declare first_ boolean; second_ boolean; wrong boolean; expired boolean;
begin
  set local role service_role;
  perform daily_verse.issue_challenge(dvat.h('chal-1'), 'report', dvat.h('net-a'));
  wrong := daily_verse.consume_challenge(dvat.h('chal-1'), 'attest');
  first_ := daily_verse.consume_challenge(dvat.h('chal-1'), 'report');
  second_ := daily_verse.consume_challenge(dvat.h('chal-1'), 'report');
  perform daily_verse.issue_challenge(dvat.h('chal-old'), 'attest', dvat.h('net-a'));
  reset role;
  update daily_verse.attest_challenges set expires_at = now() - interval '1 second' where challenge_hash = dvat.h('chal-old');
  set local role service_role;
  expired := daily_verse.consume_challenge(dvat.h('chal-old'), 'attest');
  reset role;
  perform dvat.check('a challenge for another purpose is refused', not wrong);
  perform dvat.check('a challenge is accepted once', first_);
  perform dvat.check('a used challenge is refused', not second_);
  perform dvat.check('an expired challenge is refused', not expired);
  perform dvat.check('challenges are stored as hashes only',
    not exists (select 1 from daily_verse.attest_challenges where challenge_hash !~ '^[0-9a-f]{64}$'));
end $$;

do $$
declare i integer; stopped integer; limited boolean := false;
begin
  set local role service_role;
  for i in 1..25 loop
    begin
      perform daily_verse.issue_challenge(dvat.h('flood-' || i), 'report', dvat.h('net-flood'));
    exception when others then
      if sqlerrm like '%rate_limited%' then limited := true; stopped := i; exit; end if;
      raise;
    end;
  end loop;
  reset role;
  perform dvat.check('challenges are rate-limited per network (burst 20)', limited and stopped = 21, 'stopped at ' || coalesce(stopped::text, 'never'));
end $$;

-- Keys ------------------------------------------------------------------------------------
do $$
declare k record; moved boolean; replay boolean; back boolean;
begin
  set local role service_role;
  perform daily_verse.register_attest_key(dvat.h('key-1'), decode(repeat('30', 91), 'hex'), 'production', dvat.h('net-k'));
  perform daily_verse.register_attest_key(dvat.h('key-1'), decode(repeat('31', 91), 'hex'), 'development', dvat.h('net-k'));
  select * into k from daily_verse.get_attest_key(dvat.h('key-1'));
  moved := daily_verse.advance_attest_key(dvat.h('key-1'), 1);
  replay := daily_verse.advance_attest_key(dvat.h('key-1'), 1);
  back := daily_verse.advance_attest_key(dvat.h('key-1'), 0);
  reset role;
  perform dvat.check('a registered key keeps its first public key and environment',
    k.public_key = decode(repeat('30', 91), 'hex') and k.environment = 'production' and k.sign_count = 0);
  perform dvat.check('the counter moves forward', moved);
  perform dvat.check('the same counter again (a replay) is refused', not replay);
  perform dvat.check('a lower counter is refused', not back);
  perform dvat.check('an unknown key has no row',
    not exists (select 1 from daily_verse.get_attest_key(dvat.h('nobody'))));
end $$;

do $$
declare i integer; stopped integer; limited boolean := false;
begin
  set local role service_role;
  for i in 1..12 loop
    begin
      perform daily_verse.register_attest_key(dvat.h('many-' || i), decode(repeat('30', 91), 'hex'), 'production', dvat.h('net-many'));
    exception when others then
      if sqlerrm like '%rate_limited%' then limited := true; stopped := i; exit; end if;
      raise;
    end;
  end loop;
  reset role;
  perform dvat.check('new keys are rate-limited per network (10 an hour)', limited and stopped = 11, 'stopped at ' || coalesce(stopped::text, 'never'));
end $$;

-- Retry-safe reports -------------------------------------------------------------------------
update daily_verse.settings set accepted_channels = array['internal', 'public'] where id = 1;

do $$
declare a uuid; b uuid; c uuid; n integer;
  rid uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
begin
  a := dvat.submit(rid, 'install-retry', 'es-2027-04-03.crossword', 'key-r');
  b := dvat.submit(rid, 'install-retry', 'es-2027-04-03.crossword', 'key-r');
  select count(*) into n from daily_verse.reports where client_report_id = rid;
  perform dvat.check('a retry with the same report id returns the first report', a = b);
  perform dvat.check('a retry saves nothing new', n = 1);
  perform dvat.check('the report is stored on the public channel', (select channel from daily_verse.reports where id = a) = 'public');
  -- A different report id for different content is a new report.
  c := dvat.submit('aaaaaaaa-0000-4000-8000-000000000002', 'install-retry', 'es-2027-04-04.word_search', 'key-r');
  perform dvat.check('a new report id is a new report', c <> a);
end $$;

select dvat.raises('the same report id from another install is refused', 'postgres',
  $q$select dvat.submit('aaaaaaaa-0000-4000-8000-000000000001', 'someone-else', 'es-2027-04-03.crossword', 'key-x')$q$, 'invalid report id');
select dvat.raises('a missing report id is refused', 'postgres',
  $q$select dvat.submit(null, 'install-null', 'es-x', 'key-n')$q$, 'invalid report id');

do $$
declare i integer; stopped integer; limited boolean := false;
begin
  for i in 1..7 loop
    begin
      perform dvat.submit(gen_random_uuid(), 'install-keyflood-' || i, 'es-keyflood-' || i, 'key-flood');
    exception when others then
      if sqlerrm like '%rate_limited%' then limited := true; stopped := i; exit; end if;
      raise;
    end;
  end loop;
  perform dvat.check('reports are rate-limited per attested key (5 an hour), even across install ids', limited and stopped = 6, 'stopped at ' || coalesce(stopped::text, 'never'));
end $$;

do $$
declare i integer; stopped integer; limited boolean := false;
begin
  for i in 1..7 loop
    begin
      perform dvat.submit(gen_random_uuid(), 'install-flood', 'es-flood-' || i, 'key-' || i);
    exception when others then
      if sqlerrm like '%rate_limited%' then limited := true; stopped := i; exit; end if;
      raise;
    end;
  end loop;
  perform dvat.check('the existing per-install limit (5 an hour) still applies', limited and stopped = 6, 'stopped at ' || coalesce(stopped::text, 'never'));
end $$;

do $$
declare a uuid; b uuid;
begin
  -- The 10-minute rule: same install, content and category with a new report id is kept once.
  a := dvat.submit(gen_random_uuid(), 'install-ten', 'es-ten.crossword', 'key-ten-1');
  b := dvat.submit(gen_random_uuid(), 'install-ten', 'es-ten.crossword', 'key-ten-2');
  perform dvat.check('the 10-minute duplicate rule still applies', a = b);
end $$;

update daily_verse.settings set accepted_channels = array['internal'] where id = 1;
select dvat.raises('with public closed, a public report is refused', 'postgres',
  $q$select dvat.submit(gen_random_uuid(), 'install-closed', 'es-closed', 'key-closed')$q$, 'channel_closed');
do $$
declare a uuid;
begin
  a := dvat.submit(gen_random_uuid(), 'install-internal', 'es-internal', null, 'internal');
  perform dvat.check('an Internal report without a key still works', a is not null);
end $$;

-- Retention ----------------------------------------------------------------------------------
do $$
declare result jsonb;
begin
  update daily_verse.attest_keys set last_used_at = now() - interval '1 year 1 day' where key_hash = dvat.h('key-1');
  update daily_verse.attest_challenges set expires_at = now() - interval '1 minute' where challenge_hash = dvat.h('flood-1');
  set local role service_role;
  result := daily_verse.purge_expired();
  reset role;
  perform dvat.check('purge_expired removes keys idle for a year', not exists (select 1 from daily_verse.attest_keys where key_hash = dvat.h('key-1')), result::text);
  perform dvat.check('purge_expired removes expired challenges', not exists (select 1 from daily_verse.attest_challenges where challenge_hash = dvat.h('flood-1')));
  perform dvat.check('purge_expired keeps keys in use', exists (select 1 from daily_verse.attest_keys where key_hash = dvat.h('many-1')));
  perform dvat.check('purge_expired still reports reports and rate limits', result ? 'reports' and result ? 'rate_limits');
end $$;

-- Results ------------------------------------------------------------------------------------
select case when ok then 'PASS' else 'FAIL' end || '  ' || name || coalesce('  [' || detail || ']', '') as result
from dvat.results where not ok or current_setting('dvtest.verbose', true) = 'on' order by n;
select format('%s passed, %s failed, %s total (App Attest)',
  count(*) filter (where ok), count(*) filter (where not ok), count(*)) as summary from dvat.results;
do $$ begin
  if exists (select 1 from dvat.results where not ok) then raise exception 'daily_verse App Attest tests failed'; end if;
end $$;
drop schema dvat cascade;
delete from daily_verse.reports;
delete from daily_verse.rate_limits;
delete from daily_verse.attest_keys;
delete from daily_verse.attest_challenges;
