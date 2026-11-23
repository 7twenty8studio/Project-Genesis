-- Launch giveaway (20261127000000): who may enter, draw and read. Run by
-- run.sh as a superuser on a throwaway database; each check switches role.
set client_min_messages = warning;
create schema gt;
create table gt.results (n serial, name text, ok boolean, detail text);

-- Runs `sql` as anon, or as a signed-in person with this email; returns its
-- value as text, or 'ERROR: <message>'.
create function gt.run(who text, sql text) returns text language plpgsql as $$
declare t text;
begin
  perform set_config('request.jwt.claims', case when who = 'anon' then '' else jsonb_build_object('email', who)::text end, true);
  execute format('set local role %I', case who when 'anon' then 'anon' else 'authenticated' end);
  begin
    execute 'select (' || sql || ')::text' into t;
  exception when others then t := 'ERROR: ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return t;
end $$;
create function gt.check(name text, ok boolean, detail text default null) returns void language sql as $$
  insert into gt.results (name, ok, detail) values (name, coalesce(ok, false), detail) $$;

insert into public.ops_admins (email) values ('owner@example.com') on conflict do nothing;

begin;
select gt.check('anon reads status', gt.run('anon', $q$giveaway_status('launch-2026')->>'open'$q$) = 'true');
select gt.check('first entry is 1', gt.run('anon', $q$giveaway_enter('launch-2026', ' Ana  Maria ', 'Ana@Example.com', false)$q$) = '1');
select gt.check('second entry is 2', gt.run('anon', $q$giveaway_enter('launch-2026', 'Ben', 'ben@example.com', true)$q$) = '2');
select gt.check('same email keeps its number', gt.run('anon', $q$giveaway_enter('launch-2026', 'Ana', 'ana@example.com', true)$q$) = '1');
select gt.check('news tick kept', (select wants_news from public.giveaway_entries where number = 1));
select gt.check('name tidied', (select first_name from public.giveaway_entries where number = 1) = 'Ana Maria');
select gt.check('bad email refused', gt.run('anon', $q$giveaway_enter('launch-2026', 'Cy', 'not-an-email', false)$q$) like 'ERROR: invalid_email%');
select gt.check('empty name refused', gt.run('anon', $q$giveaway_enter('launch-2026', '  ', 'cy@example.com', false)$q$) like 'ERROR: invalid_name%');
select gt.check('unknown event refused', gt.run('anon', $q$giveaway_enter('nope', 'Cy', 'cy@example.com', false)$q$) like 'ERROR: closed%');
select gt.check('anon cannot read entries', gt.run('anon', $q$(select count(*) from public.giveaway_entries)$q$) like 'ERROR:%' or gt.run('anon', $q$(select count(*) from public.giveaway_entries)$q$) = '0');
select gt.check('anon cannot see board', gt.run('anon', $q$giveaway_board('launch-2026')$q$) like 'ERROR:%');
select gt.check('anon cannot draw', gt.run('anon', $q$giveaway_draw('launch-2026', 'raffle')$q$) like 'ERROR:%');
select gt.check('stranger cannot see board', gt.run('someone@example.com', $q$giveaway_board('launch-2026')$q$) like 'ERROR: not_allowed%');
select gt.check('stranger cannot draw', gt.run('someone@example.com', $q$giveaway_draw('launch-2026', 'raffle')$q$) like 'ERROR: not_allowed%');
select gt.check('stranger cannot close', gt.run('someone@example.com', $q$giveaway_set_open('launch-2026', false)$q$) like 'ERROR: not_allowed%');
select gt.check('owner sees names, never emails', gt.run('OWNER@example.com', $q$giveaway_board('launch-2026')$q$) not like '%@%'
  and jsonb_array_length(gt.run('owner@example.com', $q$giveaway_board('launch-2026')$q$)::jsonb -> 'entries') = 2);
select gt.check('first raffle draw', gt.run('owner@example.com', $q$giveaway_draw('launch-2026', 'raffle')->>'number'$q$) in ('1', '2'));
select gt.check('second raffle draw', gt.run('owner@example.com', $q$giveaway_draw('launch-2026', 'raffle')->>'number'$q$) in ('1', '2'));
select gt.check('second raffle draw is the other', (select count(distinct number) from public.giveaway_draws where purpose = 'raffle') = 2);
select gt.check('nobody left', gt.run('owner@example.com', $q$giveaway_draw('launch-2026', 'raffle')$q$) like 'ERROR: nobody_left%');
select gt.check('volunteer pool is separate', gt.run('owner@example.com', $q$giveaway_draw('launch-2026', 'volunteer')->>'number'$q$) in ('1', '2'));
select gt.check('bad purpose refused', gt.run('owner@example.com', $q$giveaway_draw('launch-2026', 'prize')$q$) like 'ERROR: invalid_purpose%');
-- (the id is read here: the admin can't read the table, only the board)
select gt.check('no-show marked', gt.run('owner@example.com', format('giveaway_no_show(%s)', (select max(id) from public.giveaway_draws))) = 'true');
select gt.check('owner closes entries', gt.run('owner@example.com', $q$giveaway_set_open('launch-2026', false)$q$) = 'false');
select gt.check('closed refuses entries', gt.run('anon', $q$giveaway_enter('launch-2026', 'Di', 'di@example.com', false)$q$) like 'ERROR: closed%');
select gt.check('forgotten number found after closing', gt.run('anon', $q$giveaway_find('launch-2026', ' ANA@example.com ')->>'number'$q$) = '1');
select gt.check('find gives the first name only', gt.run('anon', $q$giveaway_find('launch-2026', 'ana@example.com')$q$) not like '%@%');
select gt.check('unknown email finds nothing', coalesce(gt.run('anon', $q$giveaway_find('launch-2026', 'nobody@example.com')$q$), '') in ('', 'null'));
select gt.check('anon cannot write tables', gt.run('anon', $q$(with x as (insert into public.giveaway_entries (event, number, first_name, email) values ('launch-2026', 50, 'X', 'x@example.com') returning 1) select count(*) from x)$q$) like 'ERROR:%');
-- The checks above are undone with their data, so report them first.
select case when ok then 'PASS ' else 'FAIL ' end || name || coalesce(' (' || detail || ')', '') from gt.results order by n;
do $$ begin if exists (select 1 from gt.results where not ok) then raise exception 'giveaway tests failed'; end if; end $$;
rollback;

-- Remote control (20261129000000): the timer and the clear signal, timed by the database.
select gt.check('stranger cannot drive the timer', gt.run('someone@example.com', $q$giveaway_live('launch-2026', 'timer_start')$q$) like 'ERROR: not_allowed%');
select gt.check('anon cannot drive the timer', gt.run('anon', $q$giveaway_live('launch-2026', 'clear')$q$) like 'ERROR:%');
select gt.check('board carries live state and the clock', (gt.run('owner@example.com', $q$giveaway_board('launch-2026')$q$)::jsonb ? 'live')
  and (gt.run('owner@example.com', $q$giveaway_board('launch-2026')$q$)::jsonb ->> 'now')::bigint > 1700000000000);
select gt.check('clear is stamped', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'clear') ->> 'cleared'$q$) ~ '^[0-9]{13}$');
select gt.check('start answers with the timer', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_start')$q$)::jsonb ? 'timer');
select gt.check('start: both lanes go 3 s ahead', (select (live #>> '{timer,started,0}')::bigint - floor(extract(epoch from clock_timestamp()) * 1000) between 2000 and 3100
  and live #> '{timer,started,0}' = live #> '{timer,started,1}' from public.giveaway_events where slug = 'launch-2026'));
select gt.check('clear keeps the timer', (select gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'clear') #>> '{timer,started,0}'$q$)) is not null);
select gt.check('stop during the countdown does nothing', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_stop', 0) #> '{timer,finished,0}'$q$) = 'null');
update public.giveaway_events set live = jsonb_set(live, '{timer,started}', jsonb_build_array(floor(extract(epoch from clock_timestamp()) * 1000)::bigint - 5000, floor(extract(epoch from clock_timestamp()) * 1000)::bigint - 5000)) where slug = 'launch-2026';
select gt.check('stop takes the time', (gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_stop', 1) #>> '{timer,finished,1}'$q$))::bigint between 5000 and 6000);
select gt.check('second stop keeps the first time', (select (live #>> '{timer,finished,1}')::bigint from public.giveaway_events where slug = 'launch-2026')
  = (gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_stop', 1) #>> '{timer,finished,1}'$q$))::bigint);
select gt.check('bad lane refused', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_stop', 2)$q$) like 'ERROR: invalid_lane%');
select gt.check('names are shared, trimmed to 30', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_names', null, true, array['  Ana ', repeat('x', 40)]) -> 'names'$q$)::jsonb = jsonb_build_array('Ana', repeat('x', 30)));
select gt.check('names need two', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_names', null, true, array['Ana'])$q$) like 'ERROR: invalid_names%');
select gt.check('bad action refused', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'explode')$q$) like 'ERROR: invalid_action%');
select gt.check('reset empties both lanes', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_reset') -> 'timer'$q$)::jsonb = '{"started": [null, null], "finished": [null, null]}'::jsonb);
select gt.check('one at a time starts lane 1 only', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_start', null, false) #> '{timer,started,1}'$q$) = 'null');
update public.giveaway_events set live = jsonb_set(live, '{timer,started,0}', to_jsonb(floor(extract(epoch from clock_timestamp()) * 1000)::bigint - 5000)) where slug = 'launch-2026';
select gt.check('then lane 2 on the next start', gt.run('owner@example.com', $q$giveaway_live('launch-2026', 'timer_start', null, false) #> '{timer,started,1}'$q$) <> 'null');

select case when ok then 'PASS ' else 'FAIL ' end || name || coalesce(' (' || detail || ')', '') from gt.results order by n;
do $$ begin if exists (select 1 from gt.results where not ok) then raise exception 'giveaway tests failed'; end if; end $$;
