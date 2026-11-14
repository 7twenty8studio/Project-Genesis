-- Security and behaviour tests for the daily_verse schema. Run by run.sh (as a
-- superuser on a throwaway local database); each check switches to the role
-- under test. Prints PASS/FAIL per check and fails if any check fails.

set client_min_messages = warning;
drop schema if exists dvtest cascade;
create schema dvtest;
create table dvtest.results (n serial, name text, ok boolean, detail text);
grant usage on schema dvtest to postgres;
grant insert on dvtest.results to postgres;
grant usage on sequence dvtest.results_n_seq to postgres;

-- Runs `sql` as `role_` (with JWT subject `sub`, if given) and expects it to be refused.
create function dvtest.denied(name text, role_ text, sql text, sub uuid default null) returns void
language plpgsql as $$
declare ok boolean; detail text;
begin
  begin
    perform set_config('request.jwt.claim.sub', coalesce(sub::text, ''), true);
    execute format('set local role %I', role_);
    execute sql;
    ok := false; detail := 'was allowed';
  exception when insufficient_privilege then ok := true; detail := sqlerrm;
  end;
  reset role;
  insert into dvtest.results (name, ok, detail) values (name, ok, detail);
end $$;

-- Runs `sql` as `role_` and expects the given SQLSTATE (or message fragment).
create function dvtest.raises(name text, role_ text, sql text, expect text) returns void
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
  insert into dvtest.results (name, ok, detail) values (name, ok, detail);
end $$;

create function dvtest.check(name text, cond boolean, detail text default null) returns void
language plpgsql as $$
begin
  insert into dvtest.results (name, ok, detail) values (name, coalesce(cond, false), detail);
end $$;

-- A valid report through the service role. Returns the id.
create function dvtest.submit(install text, content text, net text default null, cat text default 'unclear_clue',
                              descr text default 'La pista no coincide con el versículo.', chan text default 'internal')
returns uuid language plpgsql as $$
declare id_ uuid;
begin
  set local role service_role;
  id_ := daily_verse.submit_report(chan, '1.0', '42', '18.1', 'phone', 'es', 'crossword', content,
                                   date '2026-12-25', 'draft', cat, descr,
                                   encode(digest(install, 'sha256'), 'hex'),
                                   encode(digest(coalesce(net, 'net-' || install), 'sha256'), 'hex'));
  reset role;
  return id_;
end $$;

-- Fixtures ----------------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'versely.user@example.com'),
  ('22222222-2222-2222-2222-222222222222', '7twenty8studio@gmail.com')
on conflict (id) do nothing;
insert into storage.objects (bucket_id, name) values
  ('attachments', '11111111-1111-1111-1111-111111111111/note.jpg'),
  ('attachments', 'daily-verse/reports/00000000-0000-0000-0000-000000000001/1.jpg')
on conflict (bucket_id, name) do nothing;

\set versely '''11111111-1111-1111-1111-111111111111'''

-- 1. Schema-level isolation --------------------------------------------------------
select dvtest.check('anon has no USAGE on schema daily_verse', not has_schema_privilege('anon', 'daily_verse', 'usage'));
select dvtest.check('authenticated has no USAGE on schema daily_verse', not has_schema_privilege('authenticated', 'daily_verse', 'usage'));
select dvtest.check('service_role has USAGE on schema daily_verse', has_schema_privilege('service_role', 'daily_verse', 'usage'));
select dvtest.check('every daily_verse table has RLS on',
  (select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'daily_verse' and c.relkind = 'r'));
select dvtest.check('no RLS policies exist on daily_verse tables',
  (select count(*) = 0 from pg_policies where schemaname = 'daily_verse'));
select dvtest.check('every daily_verse object is owned by daily_verse_owner',
  (select bool_and(pg_get_userbyid(c.relowner) = 'daily_verse_owner') from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'daily_verse')
  and (select bool_and(pg_get_userbyid(p.proowner) = 'daily_verse_owner') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'daily_verse'));

-- 2. Owner role has nothing outside its schema ---------------------------------------
select dvtest.check('daily_verse_owner cannot log in, is not superuser, has no BYPASSRLS',
  (select not rolcanlogin and not rolsuper and not rolbypassrls and not rolcreaterole from pg_roles where rolname = 'daily_verse_owner'));
select dvtest.check('daily_verse_owner is a member of no other role',
  (select count(*) = 0 from pg_auth_members a join pg_roles r on r.oid = a.member where r.rolname = 'daily_verse_owner'));
select dvtest.check('daily_verse_owner has no privilege on any public/storage/auth/vault table',
  (select count(*) = 0 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'storage', 'auth', 'vault') and c.relkind in ('r', 'v', 'm')
     and (has_table_privilege('daily_verse_owner', c.oid, 'select') or has_table_privilege('daily_verse_owner', c.oid, 'insert')
          or has_table_privilege('daily_verse_owner', c.oid, 'update') or has_table_privilege('daily_verse_owner', c.oid, 'delete'))));
select dvtest.check('daily_verse_owner owns nothing outside daily_verse',
  (select count(*) = 0 from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where pg_get_userbyid(c.relowner) = 'daily_verse_owner' and n.nspname not in ('daily_verse', 'pg_toast')));

-- 3. Functions: SECURITY DEFINER, empty search_path, service role only ---------------
select dvtest.check('all daily_verse functions are SECURITY DEFINER with search_path=""',
  (select bool_and(p.prosecdef and p.proconfig @> array['search_path=""']) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'daily_verse'));
select dvtest.check('anon and authenticated cannot EXECUTE any daily_verse function',
  (select bool_and(not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute'))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'daily_verse'));
select dvtest.check('PUBLIC has no EXECUTE on daily_verse functions',
  (select bool_and(coalesce(not (p.proacl::text like '%=X/%' and p.proacl::text ~ '(^|[{,])=X'), true))
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'daily_verse'));
select dvtest.check('service_role can EXECUTE every daily_verse function',
  (select bool_and(has_function_privilege('service_role', p.oid, 'execute')) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'daily_verse'));

-- 4. anon / signed-in Versely user are refused everywhere ----------------------------
select dvtest.denied('anon cannot read reports', 'anon', 'select * from daily_verse.reports');
select dvtest.denied('anon cannot insert reports', 'anon',
  $$insert into daily_verse.reports (channel, app_version, build, content_language, puzzle_type, content_id, category, description, install_hash)
    values ('internal','1','1','es','crossword','x','other','x', repeat('a',64))$$);
select dvtest.denied('anon cannot call submit_report', 'anon',
  $$select daily_verse.submit_report('internal','1','1',null,null,'es','crossword','x',null,null,'other','x',repeat('a',64),repeat('b',64))$$);
select dvtest.denied('anon cannot call take_token', 'anon', $$select daily_verse.take_token('x', 10, 10)$$);
select dvtest.denied('anon cannot read admins', 'anon', 'select * from daily_verse.admins');
select dvtest.denied('Versely user cannot read reports', 'authenticated', 'select * from daily_verse.reports', :versely);
select dvtest.denied('Versely user cannot read admins', 'authenticated', 'select * from daily_verse.admins', :versely);
select dvtest.denied('Versely user cannot read audit events', 'authenticated', 'select * from daily_verse.report_events', :versely);
select dvtest.denied('Versely user cannot read rate limits', 'authenticated', 'select * from daily_verse.rate_limits', :versely);
select dvtest.denied('Versely user cannot change settings', 'authenticated', $$update daily_verse.settings set accepted_channels = '{public}'$$, :versely);
select dvtest.denied('Versely user cannot add an admin', 'authenticated', $$insert into daily_verse.admins (email) values ('x@example.com')$$, :versely);
select dvtest.denied('Versely user cannot call admin_list_reports', 'authenticated',
  $$select * from daily_verse.admin_list_reports('7twenty8studio@gmail.com')$$, :versely);
select dvtest.denied('Versely user cannot call admin_update_report', 'authenticated',
  $$select daily_verse.admin_update_report('7twenty8studio@gmail.com', gen_random_uuid(), 'dismissed')$$, :versely);
select dvtest.denied('Versely user cannot call is_admin', 'authenticated', $$select daily_verse.is_admin('7twenty8studio@gmail.com')$$, :versely);
select dvtest.denied('Versely user cannot call purge_expired', 'authenticated', $$select daily_verse.purge_expired()$$, :versely);
select dvtest.denied('Versely user cannot list screenshots due', 'authenticated', $$select * from daily_verse.screenshots_due_for_deletion()$$, :versely);
select dvtest.denied('service_role cannot write reports directly (functions only)', 'service_role',
  $$update daily_verse.reports set status = 'dismissed'$$);
select dvtest.denied('service_role cannot add admins directly', 'service_role',
  $$insert into daily_verse.admins (email) values ('someone@example.com')$$);

-- 5. Storage: a Versely user can't reach daily-verse/ objects --------------------------
create temp table _seen (name text);
grant insert on _seen to authenticated;
do $$ begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  set local role authenticated;
  insert into _seen select name from storage.objects where bucket_id = 'attachments';
  reset role;
end $$;
select dvtest.check('Versely policies are active (user sees own attachment)',
  (select count(*) = 1 from _seen where name like '11111111-%'));
select dvtest.check('Versely user sees no daily-verse/ objects',
  (select count(*) = 0 from _seen where name like 'daily-verse/%'));
drop table _seen;
select dvtest.denied('Versely user cannot upload under daily-verse/', 'authenticated',
  $$insert into storage.objects (bucket_id, name) values ('attachments', 'daily-verse/reports/00000000-0000-0000-0000-000000000002/1.jpg')$$, :versely);
-- Real Supabase Storage blocks every direct DELETE on storage.objects with a
-- statement trigger (storage.protect_delete) unless storage.allow_delete_query
-- is 'true'. The flag is set transaction-locally here, for this test only, so
-- that RLS alone is what stops the Versely user. It never appears in a migration.
do $$
declare changed integer; deleted integer;
begin
  perform set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
  perform set_config('storage.allow_delete_query', 'true', true);
  set local role authenticated;
  update storage.objects set name = name where bucket_id = 'attachments' and name like 'daily-verse/%';
  get diagnostics changed = row_count;
  delete from storage.objects where bucket_id = 'attachments' and name like 'daily-verse/%';
  get diagnostics deleted = row_count;
  reset role;
  perform set_config('storage.allow_delete_query', 'false', true);
  perform dvtest.check('Versely user cannot update or delete daily-verse/ objects (RLS: 0 updated, 0 deleted)',
    changed = 0 and deleted = 0
    and (select count(*) = 1 from storage.objects where name like 'daily-verse/%'));
end $$;
select dvtest.raises('direct DELETE on storage.objects without the flag is blocked (protect_delete, 42501)', 'postgres',
  $$delete from storage.objects where bucket_id = 'attachments' and name like 'daily-verse/%'$$,
  'Direct deletion from storage tables is not allowed');
select dvtest.check('daily-verse/ object still present after both delete attempts',
  (select count(*) = 1 from storage.objects where name like 'daily-verse/%'));
do $$
declare seen integer;
begin
  set local role anon;
  select count(*) into seen from storage.objects;
  reset role;
  perform dvtest.check('anon sees no storage objects at all', seen = 0);
end $$;
select dvtest.check('no storage policy mentions daily-verse (none were added)',
  (select count(*) = 0 from pg_policies where schemaname = 'storage' and (coalesce(qual,'') || coalesce(with_check,'')) ilike '%daily%'));

-- 6. Admin allow-list -------------------------------------------------------------
select dvtest.check('allow-list starts empty (no address added by the migration)', (select count(*) = 0 from daily_verse.admins));
select dvtest.raises('non-admin is rejected by admin_list_reports', 'service_role',
  $$select * from daily_verse.admin_list_reports('7twenty8studio@gmail.com')$$, '42501');
-- Apply the reviewed seed exactly as the owner would (manual step).
\ir ../../seed/daily_verse_admins.sql
select dvtest.check('seed adds exactly one admin, the approved address',
  (select array_agg(email) = array['7twenty8studio@gmail.com'] from daily_verse.admins));
select dvtest.raises('admins table rejects upper-case emails', 'postgres',
  $$insert into daily_verse.admins (email) values ('Someone@Example.com')$$, '23514');
select dvtest.raises('another address is still rejected', 'service_role',
  $$select * from daily_verse.admin_list_reports('versely.user@example.com')$$, '42501');
select dvtest.raises('Versely ops admin is not a Daily Verse admin', 'service_role',
  $$select * from daily_verse.admin_list_reports('ops.admin@example.com')$$, '42501');
do $$ begin
  set local role service_role;
  perform daily_verse.admin_list_reports(' 7Twenty8Studio@Gmail.com ');
  reset role;
  perform dvtest.check('approved admin may list (email compared case-insensitively)', true);
exception when others then
  reset role;
  perform dvtest.check('approved admin may list (email compared case-insensitively)', false, sqlerrm);
end $$;

-- 7. Submissions and validation -----------------------------------------------------
do $$
declare id_ uuid; r daily_verse.reports;
begin
  id_ := dvtest.submit('install-a', 'es-2026-12-25.crossword');
  select * into r from daily_verse.reports where id = id_;
  perform dvtest.check('valid internal report is stored with the app tag',
    r.app = 'daily-verse-games' and r.channel = 'internal' and r.status = 'new' and r.content_language = 'es');
  perform dvtest.check('report stores only the hashed install id', r.install_hash ~ '^[0-9a-f]{64}$');
  perform dvtest.check('duplicate within 10 minutes returns the same report',
    dvtest.submit('install-a', 'es-2026-12-25.crossword') = id_
    and (select count(*) = 1 from daily_verse.reports where content_id = 'es-2026-12-25.crossword'));
end $$;
select dvtest.raises('public builds are refused (Internal only)', 'postgres',
  $$select dvtest.submit('install-b', 'es-x', chan => 'public')$$, 'channel_closed');
select dvtest.raises('unknown category rejected', 'postgres', $$select dvtest.submit('install-b', 'es-x', cat => 'rude')$$, '23514');
select dvtest.raises('description over 2000 characters rejected', 'postgres',
  $$select dvtest.submit('install-b', 'es-y', descr => repeat('palabra ', 300))$$, '23514');
select dvtest.raises('empty description rejected', 'postgres', $$select dvtest.submit('install-b', 'es-z', descr => '   ')$$, '23514');
select dvtest.raises('content id with spaces rejected', 'postgres', $$select dvtest.submit('install-b', 'bad id')$$, '23514');
select dvtest.raises('more than three links rejected as spam', 'postgres',
  $$select dvtest.submit('install-b', 'es-s1', descr => 'http://a http://b http://c http://d')$$, 'rejected_content');
select dvtest.raises('repeated-character spam rejected', 'postgres',
  $$select dvtest.submit('install-b', 'es-s2', descr => repeat('!', 40))$$, 'rejected_content');
select dvtest.raises('bad install hash rejected', 'service_role',
  $$select daily_verse.submit_report('internal','1','1',null,null,'es','crossword','x',null,null,'other','x','nothex',repeat('b',64))$$, '23514');

-- 8. Rate limits -------------------------------------------------------------------
do $$
declare i integer; blocked boolean := false; hint_ text;
begin
  for i in 1..5 loop perform dvtest.submit('install-rate', 'es-rate-' || i); end loop;
  begin
    perform dvtest.submit('install-rate', 'es-rate-6');
  exception when others then blocked := (sqlerrm = 'rate_limited'); get stacked diagnostics hint_ = pg_exception_hint;
  end;
  perform dvtest.check('6th report from one install within the hour is rate-limited', blocked, hint_);
  perform dvtest.check('rate limit tells the caller how long to wait', coalesce(hint_::integer, 0) > 0, hint_);
  -- An hour later the bucket has refilled.
  update daily_verse.rate_limits set refilled_at = refilled_at - interval '1 hour'
  where key = 'install:' || encode(digest('install-rate', 'sha256'), 'hex');
  perform dvtest.submit('install-rate', 'es-rate-7');
  perform dvtest.check('install bucket refills over time', true);
exception when others then
  perform dvtest.check('install bucket refills over time', false, sqlerrm);
end $$;
do $$
declare i integer; blocked boolean := false;
begin
  for i in 1..20 loop perform dvtest.submit('install-net-' || i, 'es-net', net => 'shared-network'); end loop;
  begin
    perform dvtest.submit('install-net-21', 'es-net', net => 'shared-network');
  exception when others then blocked := (sqlerrm = 'rate_limited');
  end;
  perform dvtest.check('21st report from one network within the hour is rate-limited', blocked);
end $$;
do $$
declare first_ double precision; second_ double precision;
begin
  set local role service_role;
  first_ := daily_verse.take_token('test:unit', 3600, 1);
  second_ := daily_verse.take_token('test:unit', 3600, 1);
  reset role;
  perform dvtest.check('take_token: first call takes, second waits about a second', first_ = 0 and second_ > 0 and second_ <= 1.01,
                    first_ || ' / ' || second_);
end $$;

-- 9. Screenshots --------------------------------------------------------------------
do $$
declare id_ uuid; p1 text; p2 text; blocked boolean;
begin
  id_ := dvtest.submit('install-shots', 'es-shots');
  set local role service_role;
  p1 := daily_verse.attach_screenshot(id_, 1, 1572864);
  p2 := daily_verse.attach_screenshot(id_, 2, 200000);
  reset role;
  perform dvtest.check('screenshot paths are built server-side under daily-verse/reports/<id>/',
    p1 = 'daily-verse/reports/' || id_ || '/1.jpg' and p2 = 'daily-verse/reports/' || id_ || '/2.jpg');
  begin
    set local role service_role;
    perform daily_verse.attach_screenshot(id_, 1, 1000);
    blocked := false;
  exception when others then blocked := true;
  end;
  reset role;
  perform dvtest.check('a third screenshot (or a repeat) is refused', blocked);
end $$;
select dvtest.raises('screenshot over 1.5 MB refused', 'postgres',
  $$select daily_verse.attach_screenshot((select id from daily_verse.reports limit 1), 1, 1572865)$$, 'too large');
select dvtest.raises('screenshot index 3 refused', 'postgres',
  $$select daily_verse.attach_screenshot((select id from daily_verse.reports limit 1), 3, 1000)$$, 'invalid screenshot index');

-- 10. Admin updates and audit -----------------------------------------------------
do $$
declare id_ uuid; r daily_verse.reports;
begin
  id_ := dvtest.submit('install-admin', 'es-admin');
  set local role service_role;
  r := daily_verse.admin_update_report('7twenty8studio@gmail.com', id_, 'in_review', 'Revisando');
  r := daily_verse.admin_update_report('7twenty8studio@gmail.com', id_, 'resolved', null);
  reset role;
  perform dvtest.check('resolving sets closed_at and keeps the note', r.status = 'resolved' and r.closed_at is not null and r.admin_note = 'Revisando');
  perform dvtest.check('every status change is audited',
    (select array_agg(from_status || '>' || to_status order by id) = array['new>in_review', 'in_review>resolved']
     from daily_verse.report_events where report_id = id_));
  set local role service_role;
  r := daily_verse.admin_update_report('7twenty8studio@gmail.com', id_, 'in_review', null);
  reset role;
  perform dvtest.check('reopening clears closed_at', r.closed_at is null);
end $$;
select dvtest.raises('non-admin cannot change a status', 'service_role',
  $$select daily_verse.admin_update_report('versely.user@example.com', (select id from daily_verse.reports limit 1), 'dismissed')$$, '42501');
select dvtest.raises('invalid status refused', 'service_role',
  $$select daily_verse.admin_update_report('7twenty8studio@gmail.com', (select id from daily_verse.reports limit 1), 'deleted')$$, 'invalid status');

-- 11. Retention -----------------------------------------------------------------------
do $$
declare
  a uuid; b uuid; c uuid; d uuid; e uuid; f uuid; due uuid[]; result jsonb;
begin
  a := dvtest.submit('ret-a', 'es-ret-a'); b := dvtest.submit('ret-b', 'es-ret-b'); c := dvtest.submit('ret-c', 'es-ret-c');
  d := dvtest.submit('ret-d', 'es-ret-d'); e := dvtest.submit('ret-e', 'es-ret-e'); f := dvtest.submit('ret-f', 'es-ret-f');
  set local role service_role;
  perform daily_verse.attach_screenshot(a, 1, 1000); perform daily_verse.attach_screenshot(b, 1, 1000);
  perform daily_verse.attach_screenshot(c, 1, 1000); perform daily_verse.attach_screenshot(d, 1, 1000);
  reset role;
  -- a: resolved 91 days ago; b: dismissed 89 days ago; c: open, 10 days old;
  -- d: open, 366 days old with a screenshot; e: 366 days old, no screenshot; f: 364 days old.
  update daily_verse.reports set status = 'resolved', closed_at = now() - interval '91 days', created_at = now() - interval '100 days' where id = a;
  update daily_verse.reports set status = 'dismissed', closed_at = now() - interval '89 days', created_at = now() - interval '100 days' where id = b;
  update daily_verse.reports set created_at = now() - interval '10 days' where id = c;
  update daily_verse.reports set created_at = now() - interval '366 days' where id = d;
  update daily_verse.reports set created_at = now() - interval '366 days' where id = e;
  update daily_verse.reports set created_at = now() - interval '364 days' where id = f;
  insert into daily_verse.report_events (report_id, actor_email, from_status, to_status) values (e, 'x@example.com', 'new', 'dismissed');

  set local role service_role;
  select array_agg(report_id order by report_id) into due from daily_verse.screenshots_due_for_deletion();
  reset role;
  perform dvtest.check('screenshots due: closed >90 days and older than a year only',
    due @> array[a, d] and not (due && array[b, c, e, f]), due::text);

  set local role service_role;
  result := daily_verse.purge_expired();
  reset role;
  perform dvtest.check('purge deletes only year-old reports without screenshots',
    not exists (select 1 from daily_verse.reports where id = e)
    and (select count(*) = 5 from daily_verse.reports where id in (a, b, c, d, f)), result::text);
  perform dvtest.check('purge also deletes the audit rows of purged reports',
    not exists (select 1 from daily_verse.report_events where report_id = e));

  set local role service_role;
  perform daily_verse.mark_screenshots_deleted(d, (select screenshot_paths from daily_verse.reports where id = d));
  perform daily_verse.mark_screenshots_deleted(a, (select screenshot_paths from daily_verse.reports where id = a));
  result := daily_verse.purge_expired();
  reset role;
  perform dvtest.check('after its screenshots are removed, the year-old report is purged',
    not exists (select 1 from daily_verse.reports where id = d));
  perform dvtest.check('resolved report keeps its text after screenshots are removed (until a year)',
    exists (select 1 from daily_verse.reports where id = a and cardinality(screenshot_paths) = 0));
end $$;
do $$
declare result jsonb;
begin
  insert into daily_verse.rate_limits (key, tokens, refilled_at) values ('install:old', 0, now() - interval '3 days')
  on conflict (key) do update set refilled_at = excluded.refilled_at;
  update daily_verse.rate_limits set refilled_at = now() - interval '3 days' where key = 'global';
  set local role service_role;
  result := daily_verse.purge_expired();
  reset role;
  perform dvtest.check('idle rate-limit rows are purged, the global bucket is kept',
    not exists (select 1 from daily_verse.rate_limits where key = 'install:old')
    and exists (select 1 from daily_verse.rate_limits where key = 'global'), result::text);
end $$;
-- 11b. Screenshot cleanup keeps paths and sizes paired ----------------------------
do $$
declare id_ uuid; r daily_verse.reports; before_ timestamptz;
begin
  id_ := dvtest.submit('install-pairs', 'es-pairs');
  set local role service_role;
  perform daily_verse.attach_screenshot(id_, 1, 111111);
  perform daily_verse.attach_screenshot(id_, 2, 222222);
  reset role;
  select updated_at into before_ from daily_verse.reports where id = id_;

  set local role service_role;
  perform daily_verse.mark_screenshots_deleted(id_, array['daily-verse/reports/' || id_ || '/9.jpg', 'somewhere/else.jpg']);
  reset role;
  select * into r from daily_verse.reports where id = id_;
  perform dvtest.check('unknown paths change nothing (paths, sizes, updated_at)',
    cardinality(r.screenshot_paths) = 2 and r.screenshot_bytes = array[111111, 222222] and r.updated_at = before_);

  set local role service_role;
  perform daily_verse.mark_screenshots_deleted(id_, array['daily-verse/reports/' || id_ || '/1.jpg']);
  reset role;
  select * into r from daily_verse.reports where id = id_;
  perform dvtest.check('deleting one of two screenshots keeps the other with its own size',
    r.screenshot_paths = array['daily-verse/reports/' || id_ || '/2.jpg'] and r.screenshot_bytes = array[222222],
    r.screenshot_paths::text || ' ' || r.screenshot_bytes::text);

  set local role service_role;
  perform daily_verse.attach_screenshot(id_, 1, 333333);
  perform daily_verse.mark_screenshots_deleted(id_, array['daily-verse/reports/' || id_ || '/1.jpg', 'daily-verse/reports/' || id_ || '/2.jpg']);
  reset role;
  select * into r from daily_verse.reports where id = id_;
  perform dvtest.check('deleting both clears both paths and sizes',
    r.screenshot_paths = '{}' and r.screenshot_bytes = '{}');
end $$;
select dvtest.raises('paths and sizes can never get out of step', 'postgres',
  $$update daily_verse.reports set screenshot_bytes = '{}' where cardinality(screenshot_paths) > 0$$, '23514');

-- 11c. Network keys are kept only as HMAC rate-limit keys, and purged when idle --
do $$
declare result jsonb; net_key text := 'net:' || encode(digest('net-idle', 'sha256'), 'hex');
begin
  perform dvtest.submit('install-idle', 'es-idle', net => 'net-idle');
  perform dvtest.check('the network HMAC is kept as a rate-limit key (not the raw value)',
    exists (select 1 from daily_verse.rate_limits where key = net_key)
    and not exists (select 1 from daily_verse.rate_limits where key like '%net-idle%'));
  perform dvtest.check('reports do not store the network key',
    not exists (select 1 from information_schema.columns where table_schema = 'daily_verse' and table_name = 'reports' and column_name ilike '%net%'));
  update daily_verse.rate_limits set refilled_at = now() - interval '2 days 1 minute' where key = net_key;
  set local role service_role;
  result := daily_verse.purge_expired();
  reset role;
  perform dvtest.check('an idle net: row is purged by purge_expired', not exists (select 1 from daily_verse.rate_limits where key = net_key), result::text);
end $$;

select dvtest.check('retention is scheduled daily with pg_cron',
  (select count(*) = 1 from cron.job where jobname = 'daily-verse-retention' and command like '%daily_verse.purge_expired()%'));

-- Results ----------------------------------------------------------------------------
select case when ok then 'PASS' else 'FAIL' end || '  ' || name || coalesce('  [' || detail || ']', '') as result
from dvtest.results where not ok or current_setting('dvtest.verbose', true) = 'on' order by n;
select format('%s passed, %s failed, %s total',
  count(*) filter (where ok), count(*) filter (where not ok), count(*)) as summary from dvtest.results;
do $$ begin
  if exists (select 1 from dvtest.results where not ok) then raise exception 'daily_verse tests failed'; end if;
end $$;
drop schema dvtest cascade;
