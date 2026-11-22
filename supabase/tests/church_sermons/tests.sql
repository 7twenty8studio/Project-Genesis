-- Church sermons (20261120000000 and later): who can read and write what, the
-- quotation rule, switches, reports, counts and covers. Run by run.sh as a
-- superuser on a throwaway database; each call switches to the role under
-- test (anon, or authenticated as a named person). Prints a FAIL line for any
-- failed check and raises at the end if there was one. Safe to run twice: it
-- makes its own people and churches each time.

set client_min_messages = warning;
drop schema if exists ct cascade;
create schema ct;
create table ct.results (n serial, name text, ok boolean, detail text);
create table ct.people (name text primary key, id uuid not null default gen_random_uuid());
create table ct.churches (name text primary key, id uuid not null default gen_random_uuid());
create table ct.vars (name text primary key, value text);

create function ct.p(n text) returns uuid language sql as $$ select id from ct.people where name = n $$;
create function ct.g(n text) returns uuid language sql as $$ select id from ct.churches where name = n $$;
create function ct.v(n text) returns text language sql as $$ select value from ct.vars where name = n $$;
create function ct.set(n text, val text) returns void language sql as $$
  insert into ct.vars values (n, val) on conflict (name) do update set value = excluded.value $$;

-- Runs `sql` (an expression) as `who` ('anon', 'service', or a person's name)
-- and returns its value as jsonb, or {"error": message} if it raised.
create function ct.run(who text, sql text) returns jsonb language plpgsql as $$
declare t text; r jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(ct.p(who)::text, ''), true);
  execute format('set local role %I', case who when 'anon' then 'anon' when 'service' then 'service_role' else 'authenticated' end);
  begin
    execute 'select ' || sql into t;
    r := case when t ~ '^\s*[\[{]' then t::jsonb else to_jsonb(t) end;
  exception when others then r := jsonb_build_object('error', sqlerrm);
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return r;
end $$;

create function ct.len(j jsonb) returns integer language sql as $$
  select case when jsonb_typeof(j) = 'array' then jsonb_array_length(j) else -1 end $$;

-- Runs a statement as `who`; returns the number of rows it touched, or {"error": ...}.
create function ct.dml(who text, sql text) returns jsonb language plpgsql as $$
declare n integer; r jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(ct.p(who)::text, ''), true);
  execute format('set local role %I', case who when 'anon' then 'anon' when 'service' then 'service_role' else 'authenticated' end);
  begin
    execute sql;
    get diagnostics n = row_count;
    r := to_jsonb(n);
  exception when others then r := jsonb_build_object('error', sqlerrm);
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return r;
end $$;

-- Expects the statement run as `who` to raise an error containing `expect`.
create function ct.refused_dml(name text, who text, sql text, expect text) returns void language plpgsql as $$
declare r jsonb := ct.dml(who, sql);
begin perform ct.check(name, position(expect in coalesce(r->>'error', '')) > 0, r); end $$;

create function ct.check(name text, cond boolean, detail jsonb default null) returns void language plpgsql as $$
begin insert into ct.results (name, ok, detail) values (name, coalesce(cond, false), detail::text); end $$;

-- Expects `sql` run as `who` to raise an error containing `expect`.
create function ct.refused(name text, who text, sql text, expect text) returns void language plpgsql as $$
declare r jsonb := ct.run(who, sql);
begin perform ct.check(name, position(expect in coalesce(r->>'error', '')) > 0, r); end $$;

-- Expects published_sermon(slug) as `who` to answer `status`.
create function ct.sees(name text, who text, slug_var text, status text) returns jsonb language plpgsql as $$
declare r jsonb := ct.run(who, format('public.published_sermon(%L)', ct.v(slug_var)));
begin perform ct.check(name, r->>'status' = status, r); return r; end $$;

-- People and churches ------------------------------------------------------------------

insert into ct.people (name) values ('pastor'), ('moderator'), ('member'), ('banned'), ('former'), ('outsider'),
  ('other_pastor'), ('r1'), ('r2'), ('r3'), ('starter'), ('named'),
  ('preacher'), ('preacher2'), ('admin1'), ('admin2');
insert into auth.users (id, email) select id, name || '@example.test' from ct.people;
insert into ct.churches (name) values ('grace'), ('hope'), ('quiet');

insert into public.groups (id, name, invite_code, created_by, owner_id, sermons_enabled)
select ct.g('grace'), 'Grace Fellowship ' || left(ct.g('grace')::text, 6), left(md5(random()::text), 12), ct.p('pastor'), ct.p('pastor'), true;
insert into public.groups (id, name, invite_code, created_by, owner_id, sermons_enabled)
select ct.g('hope'), 'Hope Church ' || left(ct.g('hope')::text, 6), left(md5(random()::text), 12), ct.p('other_pastor'), ct.p('other_pastor'), true;
-- Sermons not turned on for this church.
insert into public.groups (id, name, invite_code, created_by, owner_id, sermons_enabled)
select ct.g('quiet'), 'Quiet Chapel ' || left(ct.g('quiet')::text, 6), left(md5(random()::text), 12), ct.p('pastor'), ct.p('pastor'), false;

insert into public.group_members (group_id, user_id, role, display_name) values
  (ct.g('grace'), ct.p('pastor'), 'leader', 'Pastor'),
  (ct.g('grace'), ct.p('moderator'), 'leader', 'Moderator'),
  (ct.g('grace'), ct.p('member'), 'member', 'Member'),
  (ct.g('grace'), ct.p('former'), 'leader', 'Former'),
  (ct.g('grace'), ct.p('r1'), 'member', 'R1'),
  (ct.g('grace'), ct.p('r2'), 'member', 'R2'),
  (ct.g('hope'), ct.p('other_pastor'), 'leader', 'Other'),
  (ct.g('quiet'), ct.p('pastor'), 'leader', 'Pastor');
-- Banned: a ban row and no membership (as ban_group_member leaves it).
insert into public.group_bans (group_id, user_id, display_name) values (ct.g('grace'), ct.p('banned'), 'Banned');

-- Switch off ---------------------------------------------------------------------------

update public.feature_flags set enabled = false where key = 'church_sermons';
select ct.refused('switch off: pastor cannot create', 'pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Hi'), 'not_allowed');
update public.feature_flags set enabled = true where key = 'church_sermons';

-- Creating -----------------------------------------------------------------------------

select ct.set('s1', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'The Good Shepherd')))->>'id');
select ct.check('pastor creates a sermon', ct.v('s1') is not null);
select ct.set('slug1', (select slug from public.church_sermons where id = ct.v('s1')::uuid));
select ct.check('slug is ten safe characters', ct.v('slug1') ~ '^[a-z0-9]{10}$', to_jsonb(ct.v('slug1')));
select ct.check('moderator creates a sermon',
  (ct.run('moderator', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Draft')))->>'id' is not null);
select ct.refused('member cannot create', 'member', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'x'), 'not_allowed');
select ct.refused('outsider cannot create', 'outsider', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'x'), 'not_allowed');
select ct.refused('guest cannot create', 'anon', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'x'), 'permission denied');
select ct.refused('church without sermons on: leader cannot create', 'pastor', format('public.create_church_sermon(%L, %L)', ct.g('quiet'), 'x'), 'not_allowed');
select ct.refused('leader of another church cannot create here', 'other_pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'x'), 'not_allowed');

-- The draft version the Studio would have loaded.
create function ct.ver(sermon_var text) returns integer language sql as $$
  select draft_version from public.church_sermons where id = ct.v(sermon_var)::uuid $$;
-- save_church_sermon / publish_church_sermon at the current version.
create function ct.save(who text, sermon_var text, details text, blocks text default null) returns jsonb language sql as $$
  select ct.run(who, format('public.save_church_sermon(%L, %s, %L, %L)', ct.v(sermon_var), ct.ver(sermon_var), details, blocks)) $$;
create function ct.publish(who text, sermon_var text) returns jsonb language sql as $$
  select ct.run(who, format('public.publish_church_sermon(%L, %s)', ct.v(sermon_var), ct.ver(sermon_var))) $$;
-- Expects saving `blocks` to be refused as invalid_blocks.
create function ct.bad_blocks(name text, blocks text) returns void language sql as $$
  select ct.refused(name, 'pastor', format('public.save_church_sermon(%L, %s, null, %L)', ct.v('s1'), ct.ver('s1'), blocks), 'invalid_blocks') $$;

-- Saving -------------------------------------------------------------------------------

select ct.set('blocks', $j$[
  {"id": "h1", "kind": "heading", "text": "The Lord is my shepherd", "level": 1},
  {"id": "p1", "kind": "paragraph", "text": "We are known by name."},
  {"id": "k1", "kind": "scripture", "ref": {"raw": "John 10:11", "start": 43010011, "end": 43010011, "status": "verified", "label": "KJV", "quote": "Words the church typed under a KJV label"}},
  {"id": "n1", "kind": "scripture", "ref": {"raw": "John 10:14", "start": 43010014, "end": 43010014, "status": "verified", "label": "NIV", "quote": "Licensed words the church typed"}},
  {"id": "u1", "kind": "scripture", "ref": {"raw": "John 10:27", "start": 43010027, "status": "verified", "quote": "Words with no translation named"}},
  {"id": "a1", "kind": "scripture", "ref": {"raw": "Jn 10", "status": "ambiguous", "label": "KJV", "quote": "Unverified words"}},
  {"id": "r1", "kind": "scripture", "ref": {"raw": "Salmo 23", "start": 19023001, "end": 19023006, "status": "verified", "label": "Reina-Valera 1909"}},
  {"id": "l1", "kind": "list", "items": ["He knows", "He leads"], "ordered": true},
  {"id": "q1", "kind": "quote", "text": "A pastor's own words."}
]$j$);

select ct.check('pastor saves version 0 -> 1',
  ct.save('pastor', 's1', '{"speaker": "Pastor Ana", "series": "Psalms of Trust", "preached_on": "2026-11-22", "time_zone": "America/Chicago"}', ct.v('blocks'))->>'draft_version' = '1');
select ct.refused('stale save is refused, nothing overwritten', 'pastor',
  format('public.save_church_sermon(%L, 0, %L, null)', ct.v('s1'), '{"title": "Overwritten"}'), 'draft_changed');
select ct.check('title unchanged after the stale save', (select title from public.church_sermons where id = ct.v('s1')::uuid) = 'The Good Shepherd');
select ct.refused('too long a title is refused, never cut', 'pastor',
  format('public.save_church_sermon(%L, 1, %L, null)', ct.v('s1'), jsonb_build_object('title', repeat('t', 201))), 'invalid_details');
select ct.refused('unknown detail refused', 'pastor', format('public.save_church_sermon(%L, 1, %L, null)', ct.v('s1'), '{"slug": "x"}'), 'invalid_details');
select ct.refused('a cover that was never uploaded is refused', 'pastor',
  format('public.save_church_sermon(%L, 1, %L, null)', ct.v('s1'), jsonb_build_object('cover', gen_random_uuid())), 'invalid_details');

-- Malformed blocks: refused with the reason, never trimmed or stored as null.
select ct.bad_blocks('not an array', '{"id": "x"}');
select ct.bad_blocks('block without an id', '[{"kind": "paragraph", "text": "x"}]');
select ct.bad_blocks('id of the wrong type', '[{"id": 7, "kind": "paragraph", "text": "x"}]');
select ct.bad_blocks('block without a kind', '[{"id": "x", "text": "x"}]');
select ct.bad_blocks('unknown kind', '[{"id": "x", "kind": "script"}]');
select ct.bad_blocks('paragraph without text', '[{"id": "x", "kind": "paragraph"}]');
select ct.bad_blocks('paragraph with null text', '[{"id": "x", "kind": "paragraph", "text": null}]');
select ct.bad_blocks('heading without text', '[{"id": "x", "kind": "heading", "level": 2}]');
select ct.bad_blocks('heading level 7', '[{"id": "x", "kind": "heading", "text": "x", "level": 7}]');
select ct.bad_blocks('quote without text', '[{"id": "x", "kind": "quote"}]');
select ct.bad_blocks('list without items', '[{"id": "x", "kind": "list"}]');
select ct.bad_blocks('list with a null item', '[{"id": "x", "kind": "list", "items": ["a", null]}]');
select ct.bad_blocks('list ordered not a boolean', '[{"id": "x", "kind": "list", "items": [], "ordered": "yes"}]');
select ct.bad_blocks('scripture without a reference', '[{"id": "x", "kind": "scripture"}]');
select ct.bad_blocks('scripture with a null reference', '[{"id": "x", "kind": "scripture", "ref": null}]');
select ct.bad_blocks('reference without typed text', '[{"id": "x", "kind": "scripture", "ref": {"status": "unlinked"}}]');
select ct.bad_blocks('reference without status', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x"}}]');
select ct.bad_blocks('verified reference without verses', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "status": "verified"}}]');
select ct.bad_blocks('verses on an ambiguous reference', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "status": "ambiguous", "start": 43003016}}]');
select ct.bad_blocks('John 3:99 does not exist', '[{"id": "x", "kind": "scripture", "ref": {"raw": "John 3:99", "start": 43003099, "status": "verified"}}]');
select ct.bad_blocks('Psalm 151 does not exist', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 19151001, "status": "verified"}}]');
select ct.bad_blocks('verse 0 does not exist', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003000, "status": "verified"}}]');
select ct.bad_blocks('a fractional verse id', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016.5, "status": "verified"}}]');
select ct.bad_blocks('a fractional end verse (never rounded to 43003017)', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": 43003016.6, "status": "verified"}}]');
select ct.bad_blocks('a whole number written as a decimal', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": 43003017.0, "status": "verified"}}]');
select ct.bad_blocks('a negative verse id', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": -43003016, "status": "verified"}}]');
select ct.bad_blocks('a negative end verse', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": -1, "status": "verified"}}]');
select ct.bad_blocks('a huge verse id', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": 430030160000000000000, "status": "verified"}}]');
select ct.bad_blocks('an end verse past the chapter', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": 43003037, "status": "verified"}}]');
select ct.bad_blocks('an end verse as text', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": "43003017", "status": "verified"}}]');
select ct.bad_blocks('range across books', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43010011, "end": 44001001, "status": "verified"}}]');
select ct.bad_blocks('range backwards', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43003016, "end": 43003010, "status": "verified"}}]');
select ct.bad_blocks('quotation of the wrong type', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "status": "unlinked", "quote": 5}}]');
select ct.bad_blocks('unknown field in a block', '[{"id": "x", "kind": "paragraph", "text": "x", "html": "<b>"}]');
select ct.bad_blocks('unknown field in a reference', '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "status": "unlinked", "text": "x"}}]');
select ct.bad_blocks('duplicate block ids', '[{"id": "x", "kind": "paragraph", "text": ""}, {"id": "x", "kind": "paragraph", "text": ""}]');
select ct.bad_blocks('too long a paragraph', jsonb_build_array(jsonb_build_object('id', 'x', 'kind', 'paragraph', 'text', repeat('a', 5001)))::text);
select ct.check('a range to the last verse of a chapter is accepted',
  public.genesis_valid_verse(43021025) and not public.genesis_valid_verse(43021026) and public.genesis_valid_verse(19119176));
select ct.check('draft unchanged after the refused saves', ct.ver('s1') = 1);
select ct.refused('member cannot save', 'member', format('public.save_church_sermon(%L, 1, null, null)', ct.v('s1')), 'not_allowed');
select ct.refused('other church leader cannot save', 'other_pastor', format('public.save_church_sermon(%L, 1, null, null)', ct.v('s1')), 'not_allowed');

-- Direct table access --------------------------------------------------------------------

select ct.check('guest sees no rows', (ct.run('anon', '(select count(*) from public.church_sermons)'))::text = '"0"');
select ct.check('member sees no rows directly', (ct.run('member', '(select count(*) from public.church_sermons)'))::text = '"0"');
select ct.check('pastor reads the church''s rows', (ct.run('pastor', '(select count(*) from public.church_sermons)'))::text = '"2"');
select ct.check('other church leader sees none of them', (ct.run('other_pastor', '(select count(*) from public.church_sermons)'))::text = '"0"');
select ct.refused_dml('pastor cannot insert directly', 'pastor',
  format('insert into public.church_sermons (group_id, slug) values (%L, %L)', ct.g('grace'), 'abcdefghjk'), 'row-level security');
select ct.check('pastor cannot update directly',
  ct.dml('pastor', format('update public.church_sermons set title = %L where id = %L', 'Hacked', ct.v('s1'))) = '0');
select ct.check('nobody reads reports or visits directly',
  (ct.run('pastor', '(select count(*) from public.church_sermon_reports) + (select count(*) from public.church_sermon_visits)'))::text = '"0"');
select ct.check('verse counts are readable by anyone', (ct.run('anon', '(select count(*) from public.bible_verse_counts)'))::text = '"1189"');
select ct.check('nobody writes verse counts', ct.dml('pastor', 'update public.bible_verse_counts set verses = 1') = '0');

-- Publishing -----------------------------------------------------------------------------

select ct.sees('a draft is not public', 'anon', 'slug1', 'not_found');
select ct.refused('publish with a stale version refused', 'pastor', format('public.publish_church_sermon(%L, 0)', ct.v('s1')), 'draft_changed');
select ct.set('pub1', ct.publish('pastor', 's1')::text);
select ct.check('publish counts the NIV, unlabelled and unverified quotations as withheld', (ct.v('pub1')::jsonb)->>'withheld_quotes' = '3', ct.v('pub1')::jsonb);
select ct.check('retried publish returns the same revision',
  ct.publish('pastor', 's1')->>'revision' = (ct.v('pub1')::jsonb)->>'revision');
select ct.check('one revision only', (select count(*) from public.church_sermon_revisions where sermon_id = ct.v('s1')::uuid) = 1);
select ct.refused('member cannot publish', 'member', format('public.publish_church_sermon(%L, 1)', ct.v('s1')), 'not_allowed');

select ct.set('view', (ct.sees('guest opens the link', 'anon', 'slug1', 'ok'))::text);
select ct.check('no quoted words ever reach readers',
  position('typed' in ct.v('view')) = 0 and position('Unverified words' in ct.v('view')) = 0
  and position('no translation named' in ct.v('view')) = 0
  and not exists (select 1 from jsonb_array_elements((ct.v('view')::jsonb)->'blocks') b where b->'ref' ? 'quote'));
select ct.check('a KJV quotation is published as the KJV''s code, for readers to show from their own copy',
  (ct.v('view')::jsonb)->'blocks' @> '[{"id": "k1", "ref": {"translation": "KJV", "quote_withheld": false, "start": 43010011}}]');
select ct.check('a reference labelled RV1909 names it', (ct.v('view')::jsonb)->'blocks' @> '[{"id": "r1", "ref": {"translation": "RV1909"}}]');
select ct.check('an NIV quotation is a reference only',
  (ct.v('view')::jsonb)->'blocks' @> '[{"id": "n1", "ref": {"translation": null, "quote_withheld": true, "start": 43010014, "raw": "John 10:14"}}]');
select ct.check('an unverified reference names no translation and opens nothing',
  (ct.v('view')::jsonb)->'blocks' @> '[{"id": "a1", "ref": {"start": null, "end": null, "translation": null, "quote_withheld": true}}]');
select ct.check('the view names the speaker, never who published',
  (ct.v('view')::jsonb)->>'speaker' = 'Pastor Ana' and not ((ct.v('view')::jsonb) ? 'published_by') and not ((ct.v('view')::jsonb) ? 'created_by'));
select ct.check('the draft keeps the church''s words for them', position('Licensed words' in (select draft_blocks::text from public.church_sermons where id = ct.v('s1')::uuid)) > 0);
select ct.check('a guessed slug finds nothing', (ct.run('anon', 'public.published_sermon(''zzzzzzzzzz'')'))->>'status' = 'not_found');
select ct.check('a malformed slug finds nothing', (ct.run('anon', 'public.published_sermon(''../x'')'))->>'status' = 'not_found');

-- Draft saves never reach readers ----------------------------------------------------------------

select ct.save('pastor', 's1', '{"title": "Draft-only title", "speaker": "Someone Else"}', '[{"id": "d", "kind": "paragraph", "text": "Draft-only words"}]');
select ct.set('view', (ct.sees('after a draft save: still readable', 'anon', 'slug1', 'ok'))::text);
select ct.check('readers still get the published title, speaker and outline',
  (ct.v('view')::jsonb)->>'title' = 'The Good Shepherd' and (ct.v('view')::jsonb)->>'speaker' = 'Pastor Ana'
  and position('Draft-only' in ct.v('view')) = 0);
select ct.check('leaders see that there are unpublished changes',
  (ct.run('pastor', format('public.group_sermons(%L)', ct.g('grace'))))->0 ? 'unpublished_changes');
select ct.save('pastor', 's1', '{"title": "The Good Shepherd", "speaker": "Pastor Ana"}', ct.v('blocks'));

-- Members only, and a draft that would open it ------------------------------------------------------

select ct.save('pastor', 's1', '{"audience": "members"}');
select ct.sees('setting the draft to members only does not change readers yet', 'anon', 'slug1', 'ok');
select ct.check('restricting is its own action, at once',
  (ct.run('pastor', format('public.restrict_church_sermon(%L)', ct.v('s1'))))->>'draft_version' = ct.ver('s1')::text);
select ct.set('mo', (ct.sees('guest: members only, at once', 'anon', 'slug1', 'members_only'))::text);
select ct.check('members-only answer says nothing about the sermon', (ct.v('mo')::jsonb) = '{"status": "members_only"}'::jsonb, ct.v('mo')::jsonb);
select ct.save('pastor', 's1', '{"audience": "link", "title": "Opened in the draft"}');
select ct.sees('a draft save back to "anyone with the link" does not open it', 'anon', 'slug1', 'members_only');
select ct.sees('outsider: members only', 'outsider', 'slug1', 'members_only');
select ct.sees('banned person: members only', 'banned', 'slug1', 'members_only');
select ct.set('view', (ct.sees('member reads it', 'member', 'slug1', 'ok'))::text);
select ct.check('members still read the published title', (ct.v('view')::jsonb)->>'title' = 'The Good Shepherd');
select ct.sees('other church leader: members only', 'other_pastor', 'slug1', 'members_only');
delete from public.group_members where group_id = ct.g('grace') and user_id = ct.p('former');
select ct.sees('removed leader: members only', 'former', 'slug1', 'members_only');
select ct.refused('removed leader cannot edit', 'former', format('public.save_church_sermon(%L, %s, null, null)', ct.v('s1'), ct.ver('s1')), 'not_allowed');
select ct.check('removed leader no longer reads drafts', (ct.run('former', '(select count(*) from public.church_sermons)'))::text = '"0"');
insert into public.group_bans (group_id, user_id, display_name) values (ct.g('grace'), ct.p('r2'), 'R2');
select ct.sees('member banned while still listed: members only', 'r2', 'slug1', 'members_only');
delete from public.group_bans where group_id = ct.g('grace') and user_id = ct.p('r2');
select ct.refused('members-only list refused for outsiders', 'outsider', format('public.group_sermons(%L)', ct.g('grace')), 'not_allowed');
select ct.check('members list shows published sermons only, as published',
  ct.len(ct.run('member', format('public.group_sermons(%L)', ct.g('grace')))) = 1
  and ct.run('member', format('public.group_sermons(%L)', ct.g('grace')))->0->>'title' = 'The Good Shepherd');
select ct.check('leaders list shows drafts too', ct.len(ct.run('pastor', format('public.group_sermons(%L)', ct.g('grace')))) = 2);
select ct.save('pastor', 's1', '{"title": "The Good Shepherd"}');
select ct.check('publishing opens it to the link again', ct.publish('pastor', 's1')->>'number' = '2');
select ct.sees('open to the link after publishing', 'anon', 'slug1', 'ok');

-- Switches -------------------------------------------------------------------------------

update public.groups set sermons_enabled = false where id = ct.g('grace');
select ct.sees('church switch off: link stops at once', 'anon', 'slug1', 'not_found');
select ct.sees('church switch off: members too', 'member', 'slug1', 'not_found');
select ct.refused('church switch off: leader cannot publish', 'pastor', format('public.publish_church_sermon(%L, %s)', ct.v('s1'), ct.ver('s1')), 'not_allowed');
update public.groups set sermons_enabled = true where id = ct.g('grace');
update public.feature_flags set enabled = false where key = 'church_sermons';
select ct.sees('global switch off: link stops', 'anon', 'slug1', 'not_found');
update public.feature_flags set enabled = true where key = 'church_sermons';
update public.feature_flags set enabled = false where key = 'groups';
select ct.sees('groups switch off: link stops', 'anon', 'slug1', 'not_found');
update public.feature_flags set enabled = true where key = 'groups';
select ct.sees('switches back on: readable', 'anon', 'slug1', 'ok');

-- Unpublish, and a delayed retry ------------------------------------------------------------------

select ct.set('closed', ct.run('pastor', format('public.restrict_church_sermon(%L)', ct.v('s1')))::text);
select ct.check('members only says which version it moved on from',
  (ct.v('closed')::jsonb->>'previous_version')::integer + 1 = (ct.v('closed')::jsonb->>'draft_version')::integer
  and (ct.v('closed')::jsonb->>'draft_version')::integer = ct.ver('s1'), ct.v('closed')::jsonb);
select ct.save('pastor', 's1', '{"audience": "link"}');
select ct.publish('pastor', 's1');
select ct.set('stale', ct.ver('s1')::text);
select ct.set('closed', ct.run('pastor', format('public.unpublish_church_sermon(%L)', ct.v('s1')))::text);
select ct.check('unpublish says which version it moved on from',
  (ct.v('closed')::jsonb->>'previous_version')::integer = ct.v('stale')::integer
  and (ct.v('closed')::jsonb->>'draft_version')::integer = ct.ver('s1'), ct.v('closed')::jsonb);
select ct.sees('unpublish stops the link at once', 'anon', 'slug1', 'not_found');
select ct.refused('the original publish request, retried late, is refused', 'pastor',
  format('public.publish_church_sermon(%L, %s)', ct.v('s1'), ct.v('stale')), 'draft_changed');
select ct.sees('and the link stays closed', 'anon', 'slug1', 'not_found');
select ct.check('only a fresh publish opens it again', ct.publish('pastor', 's1')->>'repeated' = 'false');
select ct.sees('published again', 'anon', 'slug1', 'ok');

-- Series navigation ----------------------------------------------------------------------------

select ct.set('s2', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Green Pastures')))->>'id');
select ct.save('pastor', 's2', '{"series": "Psalms of Trust", "preached_on": "2026-11-29", "audience": "members"}', '[{"id": "p", "kind": "paragraph", "text": "Rest."}]');
select ct.publish('pastor', 's2');
select ct.check('guests are not told of a members-only next sermon', (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'next' = 'null'::jsonb);
select ct.check('members see the next sermon in the series',
  (ct.run('member', format('public.published_sermon(%L)', ct.v('slug1'))))->'next'->>'title' = 'Green Pastures');

-- Locations and Times (20261124000000, 20261125000000) ------------------------------------------------------

select ct.check('a church starts with no locations', (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'locations' = '[]'::jsonb);
select ct.set('loc', (ct.run('pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'),
  '[{"name": "  Main Campus ", "address": "1 Hill Rd, Austin, TX", "times": "Sundays 9:00 and 11:00 AM\nWednesdays 7:00 PM"}, {"name": "Online"}]')))::text);
select ct.check('the pastor saves locations, trimmed, empty fields as ""',
  ct.v('loc')::jsonb = '[{"name": "Main Campus", "address": "1 Hill Rd, Austin, TX", "times": "Sundays 9:00 and 11:00 AM\nWednesdays 7:00 PM", "street": "", "city": "", "region": "", "postal_code": "", "country": "", "gatherings": []}, {"name": "Online", "address": "", "times": "", "street": "", "city": "", "region": "", "postal_code": "", "country": "", "gatherings": []}]'::jsonb, ct.v('loc')::jsonb);
select ct.check('guests see them on a link sermon',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'locations' = ct.v('loc')::jsonb);
select ct.check('Church Studio has them',
  (ct.run('moderator', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'locations', ct.v('loc')::jsonb)));
select ct.check('a moderator can change them',
  ct.len(ct.run('moderator', format('public.set_church_locations(%L, %L)', ct.g('grace'), ct.v('loc')))) = 2);
select ct.refused('a member cannot', 'member', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[]'), 'not_allowed');
select ct.refused('another church''s pastor cannot', 'other_pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[]'), 'not_allowed');
select ct.refused('a guest cannot', 'anon', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[]'), 'permission denied');
select ct.refused('a place needs a name', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "  ", "times": "Sundays"}]'), 'invalid_locations');
select ct.refused('unknown fields are refused', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "phone": "1"}]'), 'invalid_locations');
select ct.refused('long times are refused, never cut', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), jsonb_build_array(jsonb_build_object('name', 'A', 'times', repeat('x', 301)))), 'invalid_locations');
select ct.refused('at most 10 places', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), (select jsonb_agg(jsonb_build_object('name', 'P' || i)) from generate_series(1, 11) i)), 'invalid_locations');
select ct.refused('not a list', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '{"name": "A"}'), 'invalid_locations');
-- In parts, with times picked from lists (20261125000000).
select ct.set('loc2', (ct.run('pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'),
  '[{"name": "Main Campus", "street": " 2827 Saint Martin Dr. ", "city": "Lancaster", "region": "TX", "postal_code": "75146", "country": "United States", "address": "old", "gatherings": [{"day": "sun", "time": "09:00"}, {"date": "2026-12-24", "time": "18:30", "note": " Candlelight "}]}, {"name": "Online", "city": "Lancaster", "postal_code": "75146"}]')))::text);
select ct.check('the address on one line is worked out from its parts',
  (ct.v('loc2')::jsonb)->0->>'address' = '2827 Saint Martin Dr., Lancaster, TX 75146, United States'
  and (ct.v('loc2')::jsonb)->1->>'address' = 'Lancaster, 75146', ct.v('loc2')::jsonb);
select ct.check('the parts are kept, trimmed',
  (ct.v('loc2')::jsonb)->0 @> '{"street": "2827 Saint Martin Dr.", "city": "Lancaster", "region": "TX", "postal_code": "75146", "country": "United States"}', ct.v('loc2')::jsonb);
select ct.check('gatherings are kept: a weekly day or a date, a time and a note',
  (ct.v('loc2')::jsonb)->0->'gatherings' = '[{"day": "sun", "time": "09:00", "note": ""}, {"date": "2026-12-24", "time": "18:30", "note": "Candlelight"}]'::jsonb, ct.v('loc2')::jsonb);
select ct.check('guests see the parts and gatherings',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'locations' = ct.v('loc2')::jsonb);
select ct.refused('a gathering needs a day or a date', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "gatherings": [{"time": "09:00"}]}]'), 'invalid_locations');
select ct.refused('not both', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "gatherings": [{"day": "sun", "date": "2026-12-24", "time": "09:00"}]}]'), 'invalid_locations');
select ct.refused('only the seven days', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "gatherings": [{"day": "sunday", "time": "09:00"}]}]'), 'invalid_locations');
select ct.refused('a real date', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "gatherings": [{"date": "2026-02-30", "time": "09:00"}]}]'), 'invalid_locations');
select ct.refused('a clock time', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "gatherings": [{"day": "sun", "time": "9am"}]}]'), 'invalid_locations');
select ct.refused('no other fields on a gathering', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[{"name": "A", "gatherings": [{"day": "sun", "time": "09:00", "zone": "UTC"}]}]'), 'invalid_locations');
select ct.refused('long notes are refused', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), jsonb_build_array(jsonb_build_object('name', 'A', 'gatherings', jsonb_build_array(jsonb_build_object('day', 'sun', 'time', '09:00', 'note', repeat('x', 61)))))), 'invalid_locations');
select ct.refused('at most 20 gatherings', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), jsonb_build_array(jsonb_build_object('name', 'A', 'gatherings', (select jsonb_agg(jsonb_build_object('day', 'sun', 'time', '09:00')) from generate_series(1, 21))))), 'invalid_locations');
select ct.refused('long ZIP codes are refused', 'pastor', format('public.set_church_locations(%L, %L)', ct.g('grace'), jsonb_build_array(jsonb_build_object('name', 'A', 'postal_code', repeat('9', 21)))), 'invalid_locations');
select ct.set('loc', ct.v('loc2'));
select ct.check('refusals leave them as they were',
  (select sermon_locations from public.groups where id = ct.g('grace')) = ct.v('loc')::jsonb);
select ct.check('a members-only sermon tells guests nothing about them',
  not (ct.run('anon', format('public.published_sermon(%L)', (select slug from public.church_sermons where id = ct.v('s2')::uuid)))) ? 'locations');
select ct.check('members see them there',
  (ct.run('member', format('public.published_sermon(%L)', (select slug from public.church_sermons where id = ct.v('s2')::uuid))))->'locations' = ct.v('loc')::jsonb);

-- Covers ---------------------------------------------------------------------------------

select ct.set('c1', (ct.run('pastor', format('public.new_church_sermon_cover(%L)', ct.v('s1'))))::text);
select ct.check('cover path is <group>/<sermon>/<cover>.jpg',
  (ct.v('c1')::jsonb)->>'path' = ct.g('grace')::text || '/' || ct.v('s1') || '/' || ((ct.v('c1')::jsonb)->>'cover') || '.jpg', ct.v('c1')::jsonb);
select ct.refused('members cannot ask for a cover path', 'member', format('public.new_church_sermon_cover(%L)', ct.v('s1')), 'not_allowed');
select ct.check('pastor uploads the cover',
  ct.dml('pastor', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', (ct.v('c1')::jsonb)->>'path')) = '1');
select ct.refused_dml('other church leader cannot upload there', 'other_pastor',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.g('grace')::text || '/' || ct.v('s1') || '/' || gen_random_uuid() || '.jpg'), 'row-level security');
select ct.refused_dml('member cannot upload', 'member',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.g('grace')::text || '/' || ct.v('s2') || '/' || gen_random_uuid() || '.jpg'), 'row-level security');
select ct.refused_dml('no other file names', 'pastor',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.g('grace')::text || '/' || ct.v('s1') || '.jpg'), 'row-level security');
select ct.check('guests cannot see a cover before it is published',
  (ct.run('anon', format('(select count(*) from storage.objects where bucket_id = %L and name like %L)', 'sermon-covers', ct.g('grace')::text || '/%')))::text = '"0"');
select ct.check('bucket is private, JPEG only, 1 MB', exists (select 1 from storage.buckets where id = 'sermon-covers'
  and not public and file_size_limit = 1048576 and allowed_mime_types = array['image/jpeg']));
select ct.check('the cover goes on the draft', ct.save('pastor', 's1', jsonb_build_object('cover', (ct.v('c1')::jsonb)->>'cover')::text) ? 'draft_version');
select ct.check('readers do not see a cover that is only on the draft',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'cover' = 'null'::jsonb);
select ct.refused('publishing a cover without alt text is refused', 'pastor', format('public.publish_church_sermon(%L, %s)', ct.v('s1'), ct.ver('s1')), 'needs_cover_alt');
select ct.check('still no cover for readers after the refused publish',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'cover' = 'null'::jsonb);
select ct.save('pastor', 's1', '{"cover_alt": "A shepherd at dusk"}');
select ct.publish('pastor', 's1');
select ct.check('published with its alt text',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'cover' @> jsonb_build_object('path', (ct.v('c1')::jsonb)->>'path', 'alt', 'A shepherd at dusk'));
-- No client reads the bucket (so nobody can sign a link to a cover that
-- outlives an unpublish); the sermon-cover function asks
-- sermon_cover_access() as the caller on every request (20261121000000).
select ct.set('c1sql', format('(select count(*) from storage.objects where bucket_id = %L and name = %L)', 'sermon-covers', (ct.v('c1')::jsonb)->>'path'));
select ct.set('c1access', format('public.sermon_cover_access(%L)', (ct.v('c1')::jsonb)->>'path'));
select ct.check('no client can read a cover from storage, not even its pastor',
  (ct.run('anon', ct.v('c1sql')))::text = '"0"' and (ct.run('outsider', ct.v('c1sql')))::text = '"0"'
  and (ct.run('member', ct.v('c1sql')))::text = '"0"' and (ct.run('moderator', ct.v('c1sql')))::text = '"0"'
  and (ct.run('pastor', ct.v('c1sql')))::text = '"0"');
select ct.check('no SELECT policy on sermon covers lets anyone in',
  not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and cmd in ('SELECT', 'ALL')
              and (qual like '%sermon-covers%' or qual like '%cover%') and qual <> 'false'));
select ct.check('a guest may read the cover of a link sermon', ct.run('anon', ct.v('c1access')) = '"read"'::jsonb);
select ct.check('so may a signed-in outsider', ct.run('outsider', ct.v('c1access')) = '"read"'::jsonb);
select ct.check('its leaders may edit it', ct.run('pastor', ct.v('c1access')) = '"edit"'::jsonb and ct.run('moderator', ct.v('c1access')) = '"edit"'::jsonb);
select ct.check('another church''s pastor only reads it like any guest', ct.run('other_pastor', ct.v('c1access')) = '"read"'::jsonb);
select ct.check('a made-up name is nobody''s', coalesce(ct.run('anon', format('public.sermon_cover_access(%L)', ct.g('grace')::text || '/../x.jpg')), 'null'::jsonb) = 'null'::jsonb);
select ct.run('pastor', format('public.restrict_church_sermon(%L)', ct.v('s1')));
select ct.check('restricted to members: the guest''s next request is refused', coalesce(ct.run('anon', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
select ct.check('restricted to members: an outsider is refused', coalesce(ct.run('outsider', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
select ct.check('restricted to members: a banned person is refused', coalesce(ct.run('banned', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
select ct.check('restricted to members: a member still reads it', ct.run('member', ct.v('c1access')) = '"read"'::jsonb);
update public.groups set sermons_enabled = false where id = ct.g('grace');
select ct.check('church switch off: even a member is refused', coalesce(ct.run('member', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
update public.groups set sermons_enabled = true where id = ct.g('grace');
select ct.save('pastor', 's1', '{"audience": "link"}');
select ct.publish('pastor', 's1');
select ct.check('open to the link again', ct.run('anon', ct.v('c1access')) = '"read"'::jsonb);
select ct.run('pastor', format('public.unpublish_church_sermon(%L)', ct.v('s1')));
select ct.check('unpublished: the guest''s next request is refused', coalesce(ct.run('anon', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
select ct.check('unpublished: a member''s too', coalesce(ct.run('member', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
select ct.publish('pastor', 's1');
select ct.check('published again: readable again', ct.run('anon', ct.v('c1access')) = '"read"'::jsonb);
select ct.refused('only the access check is callable, not its parts', 'anon',
  format('public.genesis_can_read_cover(%L)', (ct.v('c1')::jsonb)->>'path'), 'permission denied');

-- A new picture on the draft leaves the published one alone.
select ct.set('c2', (ct.run('pastor', format('public.new_church_sermon_cover(%L)', ct.v('s1'))))::text);
select ct.dml('pastor', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', (ct.v('c2')::jsonb)->>'path'));
select ct.save('pastor', 's1', jsonb_build_object('cover', (ct.v('c2')::jsonb)->>'cover', 'cover_alt', 'Unpublished alt')::text);
select ct.set('c2access', format('public.sermon_cover_access(%L)', (ct.v('c2')::jsonb)->>'path'));
select ct.check('nobody but leaders gets a cover that is only on the draft',
  coalesce(ct.run('anon', ct.v('c2access')), 'null'::jsonb) = 'null'::jsonb and coalesce(ct.run('member', ct.v('c2access')), 'null'::jsonb) = 'null'::jsonb
  and ct.run('moderator', ct.v('c2access')) = '"edit"'::jsonb);
select ct.check('readers keep the published cover until the next publish',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))#>>'{cover,path}' = (ct.v('c1')::jsonb)->>'path');
select ct.check('leaders cannot delete a cover file, published or not',
  ct.dml('pastor', format('delete from storage.objects where name in (%L, %L)', (ct.v('c1')::jsonb)->>'path', (ct.v('c2')::jsonb)->>'path')) = '0')
from (select set_config('storage.allow_delete_query', 'true', true)) allow_;
update storage.objects set created_at = now() - interval '2 days' where bucket_id = 'sermon-covers';
select ct.check('covers in use (draft and published) are never retired',
  (select count(*) from public.retire_orphan_sermon_covers() n where n in ((ct.v('c1')::jsonb)->>'path', (ct.v('c2')::jsonb)->>'path')) = 0
  and not exists (select 1 from public.church_sermon_retired_covers where name in ((ct.v('c1')::jsonb)->>'path', (ct.v('c2')::jsonb)->>'path')));
select ct.publish('pastor', 's1');
select ct.check('after the next publish the old picture is retired',
  exists (select 1 from public.retire_orphan_sermon_covers() n where n = (ct.v('c1')::jsonb)->>'path'));
select ct.check('a replaced cover is no longer served to readers', coalesce(ct.run('anon', ct.v('c1access')), 'null'::jsonb) = 'null'::jsonb);
select ct.check('and recorded as retired',
  exists (select 1 from public.church_sermon_retired_covers where name = (ct.v('c1')::jsonb)->>'path'));
select ct.check('a retired file not yet deleted is returned again',
  exists (select 1 from public.retire_orphan_sermon_covers() n where n = (ct.v('c1')::jsonb)->>'path'));
select ct.refused('a retired cover cannot go back on the draft', 'pastor',
  format('public.save_church_sermon(%L, %s, %L, null)', ct.v('s1'), ct.ver('s1'), jsonb_build_object('cover', (ct.v('c1')::jsonb)->>'cover')), 'invalid_details');
-- The sweep deletes the file through the Storage API.
begin;
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where name = (ct.v('c1')::jsonb)->>'path';
commit;
select ct.refused_dml('and its name cannot be uploaded again', 'pastor',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', (ct.v('c1')::jsonb)->>'path'), 'row-level security');
select ct.refused('only the service role runs the sweep', 'pastor', '(select count(*) from public.retire_orphan_sermon_covers())', 'permission denied');
select ct.refused('nobody reads the retired list directly', 'pastor', '(select count(*) from public.church_sermon_retired_covers)', 'permission denied');

-- Import review with the draft (20261121000000) ---------------------------------------------

select ct.set('rv', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Imported')))->>'id');
select ct.save('pastor', 'rv', '{}', '[{"id": "p1", "kind": "paragraph", "text": "Rest."}, {"id": "q1", "kind": "quote", "text": "John 3:16 NIV For God so loved"}, {"id": "r1", "kind": "scripture", "ref": {"raw": "Jn 3", "status": "ambiguous", "label": null, "quote": null}}]');
select ct.set('review', '{"items": [{"key": "missing:4", "kind": "missing", "words": ["amen"], "before": [], "after": []},
  {"key": "note:comments", "kind": "note", "note": {"kind": "comments", "count": 0}},
  {"key": "quotation:q1", "kind": "quotation", "blockId": "q1"},
  {"key": "reference:r1", "kind": "reference", "blockId": "r1", "raw": "Jn 3"}], "decisions": {}}');
select ct.set('rvsave', ct.save('pastor', 'rv', jsonb_build_object('review', ct.v('review')::jsonb)::text)::text);
select ct.check('the review is saved with the draft',
  ct.v('rvsave')::jsonb ? 'draft_version'
  and (select draft_review->'items'->0->>'key' from public.church_sermons where id = ct.v('rv')::uuid) = 'missing:4', ct.v('rvsave')::jsonb);
select ct.check('three items are open (a note that found nothing needs no answer)',
  public.genesis_review_open((select draft_review from public.church_sermons where id = ct.v('rv')::uuid),
                             (select draft_blocks from public.church_sermons where id = ct.v('rv')::uuid)) = 3);
select ct.refused('publishing waits for the review', 'pastor', format('public.publish_church_sermon(%L, %s)', ct.v('rv'), ct.ver('rv')), 'review_open');
select ct.check('nothing was published', (select published_revision_id is null from public.church_sermons where id = ct.v('rv')::uuid));
select ct.save('pastor', 'rv', jsonb_build_object('review', jsonb_set(ct.v('review')::jsonb, '{decisions}', '{"missing:4": "dismissed"}'))::text);
select ct.refused('one answer is not enough', 'pastor', format('public.publish_church_sermon(%L, %s)', ct.v('rv'), ct.ver('rv')), 'review_open');
select ct.save('pastor', 'rv', '{}', '[{"id": "p1", "kind": "paragraph", "text": "Rest."}, {"id": "q1", "kind": "scripture", "ref": {"raw": "John 3:16", "status": "verified", "start": 43003016, "end": 43003016, "label": "NIV", "quote": "For God so loved"}}, {"id": "r1", "kind": "scripture", "ref": {"raw": "John 3", "status": "verified", "start": 43003001, "end": 43003036, "label": null, "quote": null}}]');
select ct.check('a quotation made a Scripture block and a fixed reference need no answer',
  public.genesis_review_open((select draft_review from public.church_sermons where id = ct.v('rv')::uuid),
                             (select draft_blocks from public.church_sermons where id = ct.v('rv')::uuid)) = 0);
select ct.check('then it publishes, with the NIV words withheld', (ct.publish('pastor', 'rv')->>'withheld_quotes')::integer = 1);
select ct.check('the review never reaches readers',
  not (ct.run('member', format('public.published_sermon(%L)', (select slug from public.church_sermons where id = ct.v('rv')::uuid)))) ? 'review');
-- A duplicate keeps the review: an open item stays open on the copy.
select ct.set('rv2', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Review copy')))->>'id');
select ct.save('pastor', 'rv2', jsonb_build_object('review', ct.v('review')::jsonb)::text, '[{"id": "p1", "kind": "paragraph", "text": "Rest."}, {"id": "q1", "kind": "quote", "text": "John 3:16 NIV For God so loved"}]');
select ct.refused('the original waits for its review', 'pastor', format('public.publish_church_sermon(%L, %s)', ct.v('rv2'), ct.ver('rv2')), 'review_open');
select ct.set('rv3', (ct.run('pastor', format('public.duplicate_church_sermon(%L)', ct.v('rv2'))))->>'id');
select ct.check('the duplicate carries the review and its answers',
  (select draft_review from public.church_sermons where id = ct.v('rv3')::uuid) = (select draft_review from public.church_sermons where id = ct.v('rv2')::uuid));
select ct.refused('so the duplicate cannot publish past it either', 'pastor', format('public.publish_church_sermon(%L, %s)', ct.v('rv3'), ct.ver('rv3')), 'review_open');

select ct.check('a quotation left out of a Scripture block needs an answer',
  public.genesis_review_open('{"items": [{"key": "quotation:q", "kind": "quotation", "blockId": "q"}], "decisions": {}}',
                             '[{"id": "q", "kind": "list", "items": ["John 3:16 NIV For God"], "ordered": false}]') = 1
  and public.genesis_review_open('{"items": [{"key": "quotation:q", "kind": "quotation", "blockId": "q"}], "decisions": {"quotation:q": "kept"}}',
                             '[{"id": "q", "kind": "list", "items": ["John 3:16 NIV For God"], "ordered": false}]') = 0);
select ct.check('a note that found something needs an answer',
  public.genesis_review_open('{"items": [{"key": "note:images", "kind": "note", "note": {"kind": "images", "count": 2}}], "decisions": {}}', '[]') = 1);
select ct.refused('an unknown decision is refused', 'pastor',
  format('public.save_church_sermon(%L, %s, %L, null)', ct.v('rv'), ct.ver('rv'), '{"review": {"items": [], "decisions": {"x": "maybe"}}}'), 'invalid_details');
select ct.refused('an unknown item kind is refused', 'pastor',
  format('public.save_church_sermon(%L, %s, %L, null)', ct.v('rv'), ct.ver('rv'), '{"review": {"items": [{"key": "x", "kind": "other"}], "decisions": {}}}'), 'invalid_details');
select ct.refused('a reference item names its block', 'pastor',
  format('public.save_church_sermon(%L, %s, %L, null)', ct.v('rv'), ct.ver('rv'), '{"review": {"items": [{"key": "x", "kind": "reference"}], "decisions": {}}}'), 'invalid_details');
select ct.refused('a huge review is refused', 'pastor',
  format('public.save_church_sermon(%L, %s, %L, null)', ct.v('rv'), ct.ver('rv'),
    jsonb_build_object('review', jsonb_build_object('items', jsonb_build_array(jsonb_build_object('key', 'm', 'kind', 'missing', 'words', repeat('a', 300000))), 'decisions', '{}'::jsonb))), 'invalid_details');
select ct.set('rvsave', ct.save('pastor', 'rv', '{"review": null}')::text);
select ct.check('closing the review clears it', ct.v('rvsave')::jsonb ? 'draft_version'
  and (select draft_review is null from public.church_sermons where id = ct.v('rv')::uuid), ct.v('rvsave')::jsonb);
select ct.check('members cannot read a draft''s review',
  coalesce(ct.run('member', format('(select draft_review from public.church_sermons where id = %L)', ct.v('rv'))), 'null'::jsonb) = 'null'::jsonb);

-- Studio's church picker (20261121000000) -----------------------------------------------

select ct.check('the pastor publishes for Grace',
  (ct.run('pastor', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'role', 'owner')));
select ct.check('a moderator publishes for Grace as a moderator',
  (ct.run('moderator', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'role', 'admin')));
select ct.check('a member has no churches to publish for', ct.run('member', 'public.my_sermon_churches()') = '[]'::jsonb);
select ct.check('a banned person has none', ct.run('banned', 'public.my_sermon_churches()') = '[]'::jsonb);
select ct.check('another church''s pastor never sees Grace',
  not (ct.run('other_pastor', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'))));
select ct.check('a church with sermons off is not offered',
  not (ct.run('pastor', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('quiet'))));
select ct.refused('guests cannot ask', 'anon', 'public.my_sermon_churches()', 'permission denied');

-- Reports --------------------------------------------------------------------------------

select ct.refused('guests cannot report', 'anon', format('public.report_church_sermon(%L, %L)', ct.v('slug1'), 'spam'), 'permission denied');
select ct.run('r1', format('public.report_church_sermon(%L, %L)', ct.v('slug1'), 'Off topic'));
select ct.run('r1', format('public.report_church_sermon(%L, %L)', ct.v('slug1'), 'again'));
select ct.run('r2', format('public.report_church_sermon(%L, %L)', ct.v('slug1'), ''));
select ct.sees('two reports (one person twice counts once): still shown', 'anon', 'slug1', 'ok');
select ct.run('r3', format('public.report_church_sermon(%L, %L)', ct.v('slug1'), 'Spam'));
select ct.sees('three people report: hidden until reviewed', 'anon', 'slug1', 'not_found');
select ct.set('reports', (ct.run('moderator', format('public.group_sermon_reports(%L)', ct.g('grace'))))::text);
select ct.check('moderators see the count and reasons', (ct.v('reports')::jsonb)->0->>'report_count' = '3', ct.v('reports')::jsonb);
select ct.check('reports never say who reported',
  position(ct.p('r1')::text in ct.v('reports')) = 0 and position(ct.p('r3')::text in ct.v('reports')) = 0);
select ct.refused('members cannot read reports', 'member', format('public.group_sermon_reports(%L)', ct.g('grace')), 'not_allowed');
select ct.refused('too long a reason is refused', 'member', format('public.report_church_sermon(%L, %L)', ct.v('slug1'), repeat('r', 501)), 'invalid_details');

-- Counts ---------------------------------------------------------------------------------

select ct.set('visitor', encode(digest('visitor-1', 'sha256'), 'hex'));
select ct.check('a hidden sermon is never counted', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor'))) = '"false"');
select ct.run('moderator', format('public.review_church_sermon_reports(%L, true)', ct.v('s1')));
select ct.sees('kept after review: shown again', 'anon', 'slug1', 'ok');
select ct.check('reports closed', ct.len(ct.run('pastor', format('public.group_sermon_reports(%L)', ct.g('grace')))) = 0);
select ct.refused('readers cannot write counts', 'member', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor')), 'permission denied');
select ct.refused('guests cannot write counts', 'anon', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor')), 'permission denied');
select ct.check('first open counted', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor'))) = '"true"');
select ct.check('same visitor again today not counted', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor'))) = '"false"');
select ct.check('a raw address is refused', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', '203.0.113.9')) = '"false"');
select ct.check('a members-only sermon is never counted by the guest counter',
  ct.run('service', format('public.record_sermon_event(%L, %L, %L)', (select slug from public.church_sermons where id = ct.v('s2')::uuid), 'open', ct.v('visitor'))) = '"false"');
select ct.check('a draft is never counted', ct.run('service', format('public.record_sermon_event(%L, %L, %L)',
  (select slug from public.church_sermons where title = 'Draft' and group_id = ct.g('grace')), 'open', ct.v('visitor'))) = '"false"');
do $$
begin
  for i in 2..70 loop
    perform ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', encode(digest('visitor-' || i, 'sha256'), 'hex')));
  end loop;
end $$;
select ct.check('at most 60 counted a minute', (select opens from public.church_sermon_stats where sermon_id = ct.v('s1')::uuid) = 60,
  (select to_jsonb(s) from public.church_sermon_stats s where sermon_id = ct.v('s1')::uuid));
select ct.check('leaders read the totals', (ct.run('pastor', format('(select opens from public.church_sermon_stats where sermon_id = %L)', ct.v('s1'))))::text = '"60"');
select ct.check('members do not', (ct.run('member', '(select count(*) from public.church_sermon_stats)'))::text = '"0"');

-- Church search --------------------------------------------------------------------------

select ct.check('unlisted churches are not found', ct.len(ct.run('anon', format('public.search_sermon_churches(%L)', 'grace fellowship ' || left(ct.g('grace')::text, 6)))) = 0);
select ct.refused('members cannot list the church', 'member', format('public.set_sermons_listed(%L, true)', ct.g('grace')), 'not_allowed');
select ct.run('pastor', format('public.set_sermons_listed(%L, true)', ct.g('grace')));
select ct.set('found', (ct.run('anon', format('public.search_sermon_churches(%L)', 'GRACE  fellowship ' || left(ct.g('grace')::text, 6))))::text);
select ct.check('listed church found by name, any case', ct.len(ct.v('found')::jsonb) = 1, ct.v('found')::jsonb);
select ct.check('search shows link sermons as published, never members-only ones or drafts',
  position('Good Shepherd' in ct.v('found')) > 0 and position('Green Pastures' in ct.v('found')) = 0
  and position('Draft' in ct.v('found')) = 0);
select ct.check('too short a search returns nothing', ct.len(ct.run('anon', 'public.search_sermon_churches(''g'')')) = 0);
-- Spanish and Portuguese names: any case, accents optional either way.
update public.groups set name = 'Iglesia Gracia y Paz ' || left(ct.g('hope')::text, 6) where id = ct.g('hope');
select ct.run('other_pastor', format('public.set_sermons_listed(%L, true)', ct.g('hope')));
select ct.check('a Spanish name is found in any case', ct.len(ct.run('anon', format('public.search_sermon_churches(%L)', 'IGLESIA gracia y paz ' || left(ct.g('hope')::text, 6)))) = 1);
update public.groups set name = 'Igreja da Graça à Beira-Rio ' || left(ct.g('hope')::text, 6) where id = ct.g('hope');
select ct.check('a Portuguese name is found without its accents', ct.len(ct.run('anon', format('public.search_sermon_churches(%L)', 'igreja da graca a beira-rio ' || left(ct.g('hope')::text, 6)))) = 1);
select ct.check('and with them', ct.len(ct.run('anon', format('public.search_sermon_churches(%L)', 'Igreja da Graça À Beira-Rio ' || left(ct.g('hope')::text, 6)))) = 1);
select ct.run('other_pastor', format('public.set_sermons_listed(%L, false)', ct.g('hope')));
select ct.check('an unlisted church is never found, in any language', ct.len(ct.run('anon', format('public.search_sermon_churches(%L)', 'igreja da graca ' || left(ct.g('hope')::text, 6)))) = 0);
update public.groups set name = 'Hope Church ' || left(ct.g('hope')::text, 6) where id = ct.g('hope');

-- Duplicate, delete, account deletion ---------------------------------------------------------

select ct.set('dup', (ct.run('moderator', format('public.duplicate_church_sermon(%L)', ct.v('s1'))))->>'id');
select ct.check('duplicate is a new draft with the outline, no date and no cover',
  exists (select 1 from public.church_sermons d where d.id = ct.v('dup')::uuid and d.status = 'draft' and d.preached_on is null
          and d.cover_id is null and d.slug <> ct.v('slug1')
          and d.draft_blocks = (select draft_blocks from public.church_sermons where id = ct.v('s1')::uuid)));
select ct.set('s2slug', (select slug from public.church_sermons where id = ct.v('s2')::uuid));
select ct.set('s2ver', ct.ver('s2')::text);
select ct.run('pastor', format('public.delete_church_sermon(%L)', ct.v('s2')));
select ct.sees('deleted sermon is gone for members', 'member', 's2slug', 'not_found');
select ct.refused('deleted sermon cannot be published again by an old request', 'pastor',
  format('public.publish_church_sermon(%L, %s)', ct.v('s2'), ct.v('s2ver')), 'not_found');
delete from auth.users where id = ct.p('moderator');
select ct.check('a volunteer deletes their account: sermons stay, their name goes',
  exists (select 1 from public.church_sermons where id = ct.v('dup')::uuid and created_by is null));

-- Quotation rule -------------------------------------------------------------------------

select ct.check('shown from trusted copies: KJV, WEB, ASV, RV1909, Biblia Livre',
  public.genesis_quote_translation('KJV') = 'KJV' and public.genesis_quote_translation('King James Version') = 'KJV'
  and public.genesis_quote_translation('web') = 'WEB' and public.genesis_quote_translation('ASV') = 'ASV'
  and public.genesis_quote_translation('RV1909') = 'RV1909' and public.genesis_quote_translation('Reina-Valera 1909') = 'RV1909'
  and public.genesis_quote_translation('Bíblia Livre') = 'BLIVRE' and public.genesis_quote_translation('BLIVRE') = 'BLIVRE');
select ct.check('reference only: NIV, ESV, NKJV, NVI, RVR1960, none',
  public.genesis_quote_translation('NIV') is null and public.genesis_quote_translation('ESV') is null
  and public.genesis_quote_translation('NKJV') is null and public.genesis_quote_translation('NVI') is null
  and public.genesis_quote_translation('RVR1960') is null and public.genesis_quote_translation(null) is null
  and public.genesis_quote_translation('') is null);

-- Self-serve churches (20261122000000) -----------------------------------------------------

select ct.refused('a guest cannot start a church', 'anon', 'public.create_sermon_church(''Guest Church'', ''Guest'')', 'permission denied');
select ct.refused('someone with no name in Versely is asked for one', 'starter', 'public.create_sermon_church(''New Life'', null)', 'name_required');
select ct.set('started', (ct.run('starter', 'public.create_sermon_church(''  New Life Church  '', ''Sam'')'))->>'id');
select ct.check('anyone signed in starts a church', ct.v('started') is not null);
select ct.check('it is theirs, sermons on, unlisted, with them as its leader',
  exists (select 1 from public.groups g join public.group_members m on m.group_id = g.id
          where g.id = ct.v('started')::uuid and g.name = 'New Life Church' and g.owner_id = ct.p('starter')
            and g.sermons_enabled and not g.sermons_listed and m.user_id = ct.p('starter') and m.role = 'leader' and m.display_name = 'Sam'));
select ct.check('their name is saved for the app', exists (select 1 from public.profiles where user_id = ct.p('starter') and display_name = 'Sam'));
select ct.check('Church Studio offers the new church at once',
  (ct.run('starter', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.v('started'), 'role', 'owner')));
select ct.check('they can write a sermon in it',
  (ct.run('starter', format('public.create_church_sermon(%L, %L)', ct.v('started'), 'First')))->>'id' is not null);
select ct.check('a saved name is kept, whatever the form says',
  (ct.run('starter', 'public.create_sermon_church(''Second Church'', ''Someone Else'')'))->>'id' is not null
  and exists (select 1 from public.profiles where user_id = ct.p('starter') and display_name = 'Sam'));
select ct.refused('an empty church name is refused', 'named', 'public.create_sermon_church(''   '', ''Named'')', 'invalid_group');
select ct.check('third church in a day', (ct.run('starter', 'public.create_sermon_church(''Third Church'', null)'))->>'id' is not null);
select ct.refused('a fourth church in a day is refused', 'starter', 'public.create_sermon_church(''Fourth Church'', null)', 'too_many_churches');

select ct.check('the owner sees their group with sermons off',
  (ct.run('pastor', 'public.my_groups_for_sermons()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('quiet'))));
select ct.check('a moderator does not see groups they don''t own',
  not (ct.run('moderator', 'public.my_groups_for_sermons()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('quiet'))));
select ct.refused('a moderator cannot turn sermons on or off', 'moderator', format('public.set_church_sermons(%L, false)', ct.g('grace')), 'not_allowed');
select ct.refused('another church''s pastor cannot either', 'other_pastor', format('public.set_church_sermons(%L, true)', ct.g('quiet')), 'not_allowed');
select ct.refused('nor a guest', 'anon', format('public.set_church_sermons(%L, true)', ct.g('quiet')), 'permission denied');
select ct.run('pastor', format('public.set_church_sermons(%L, true)', ct.g('quiet')));
select ct.check('the owner turns sermons on for their group',
  (select sermons_enabled from public.groups where id = ct.g('quiet'))
  and (ct.run('pastor', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('quiet'))));
select ct.run('pastor', format('public.set_church_sermons(%L, false)', ct.g('quiet')));
select ct.check('and off again', not (select sermons_enabled from public.groups where id = ct.g('quiet')));

update public.feature_flags set enabled = false where key = 'church_self_serve';
select ct.refused('self-serve off: no new churches', 'named', 'public.create_sermon_church(''Closed'', ''Named'')', 'not_allowed');
select ct.refused('self-serve off: no switching', 'pastor', format('public.set_church_sermons(%L, true)', ct.g('quiet')), 'not_allowed');
select ct.check('self-serve off: nothing listed', ct.run('pastor', 'public.my_groups_for_sermons()') = '[]'::jsonb);
select ct.check('self-serve off: churches already started keep going',
  (ct.run('starter', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.v('started'))));
update public.feature_flags set enabled = true where key = 'church_self_serve';
update public.feature_flags set enabled = false where key = 'church_sermons';
select ct.refused('church sermons off: no new churches', 'named', 'public.create_sermon_church(''Closed'', ''Named'')', 'not_allowed');
update public.feature_flags set enabled = true where key = 'church_sermons';

-- Roles: Owner, Admin, Preacher, Member (20261126000000) -----------------------------

insert into public.group_members (group_id, user_id, role, display_name) values
  (ct.g('grace'), ct.p('preacher'), 'member', 'Preacher One'),
  (ct.g('grace'), ct.p('preacher2'), 'member', 'Preacher Two'),
  (ct.g('grace'), ct.p('admin2'), 'member', 'Admin Two'),
  (ct.g('grace'), ct.p('admin1'), 'leader', 'Admin One');

-- Who may set roles.
select ct.refused('a member cannot make a preacher', 'member', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'preacher'), 'not_allowed');
select ct.refused('an outsider cannot make a preacher', 'outsider', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'preacher'), 'not_allowed');
select ct.refused('guests cannot set roles', 'anon', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'preacher'), 'permission denied');
select ct.refused('no unknown roles', 'pastor', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'bishop'), 'invalid_role');
select ct.refused('nobody changes the owner''s role', 'pastor', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('pastor'), 'member'), 'owner_role_fixed');
select ct.refused('someone not in the church gets no role', 'pastor', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('outsider'), 'preacher'), 'not_found');
select ct.set('r', ct.run('admin1', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'preacher'))::text);
select ct.check('an admin makes a member a preacher',
  not (ct.v('r')::jsonb ? 'error')
  and (select preacher and role = 'member' from public.group_members where group_id = ct.g('grace') and user_id = ct.p('preacher')), ct.v('r')::jsonb);
select ct.check('the owner makes a member a preacher',
  not (ct.run('pastor', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher2'), 'preacher')) ? 'error'));
select ct.refused('an admin cannot make an admin', 'admin1', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('admin2'), 'admin'), 'not_allowed');
select ct.set('r', ct.run('pastor', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('admin2'), 'admin'))::text);
select ct.check('the owner makes an admin',
  not (ct.v('r')::jsonb ? 'error')
  and (select role = 'leader' and not preacher from public.group_members where group_id = ct.g('grace') and user_id = ct.p('admin2')), ct.v('r')::jsonb);
select ct.refused('an admin cannot demote another admin', 'admin1', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('admin2'), 'member'), 'not_allowed');
select ct.refused('a preacher cannot make preachers', 'preacher', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('member'), 'preacher'), 'not_allowed');
select ct.refused('a preacher cannot promote themselves', 'preacher', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'admin'), 'not_allowed');

-- What the church looks like to each.
select ct.check('a preacher has the church, as preacher',
  (ct.run('preacher', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'role', 'preacher')));
select ct.check('an admin made by the owner has it, as admin',
  (ct.run('admin2', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'role', 'admin')));
select ct.set('people', (ct.run('admin1', format('public.church_people(%L)', ct.g('grace'))))::text);
select ct.check('admins see the people with their roles, owner first',
  ct.v('people')::jsonb->0->>'role' = 'owner'
  and ct.v('people')::jsonb @> jsonb_build_array(jsonb_build_object('name', 'Preacher One', 'role', 'preacher'),
                                                 jsonb_build_object('name', 'Admin Two', 'role', 'admin'),
                                                 jsonb_build_object('name', 'Member', 'role', 'member')), ct.v('people')::jsonb);
select ct.refused('preachers don''t see the people list', 'preacher', format('public.church_people(%L)', ct.g('grace')), 'not_allowed');
select ct.refused('members don''t see the people list', 'member', format('public.church_people(%L)', ct.g('grace')), 'not_allowed');

-- Preachers write their own sermons.
select ct.set('ps', (ct.run('preacher', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Preacher''s sermon')))->>'id');
select ct.check('a preacher starts a sermon', ct.v('ps') is not null);
select ct.check('a preacher saves their own',
  (ct.save('preacher', 'ps', '{"speaker": "Preacher One"}', '[{"id": "p", "kind": "paragraph", "text": "Grace."}]'))->>'draft_version' is not null);
select ct.check('the last editor is recorded',
  (select updated_by = ct.p('preacher') and created_by = ct.p('preacher') from public.church_sermons where id = ct.v('ps')::uuid));
select ct.check('a preacher publishes their own', (ct.publish('preacher', 'ps'))->>'revision' is not null, ct.publish('preacher', 'ps'));
select ct.set('ps_slug', (select slug from public.church_sermons where id = ct.v('ps')::uuid));
select ct.check('a preacher loads their own draft row',
  (ct.dml('preacher', format('select 1 from public.church_sermons where id = %L', ct.v('ps'))))::text = '1');
select ct.check('a preacher may change their own sermon''s cover',
  ct.run('preacher', format('public.genesis_can_edit_cover(%L)', ct.g('grace') || '/' || ct.v('ps') || '/' || gen_random_uuid() || '.jpg')) = '"true"'::jsonb);
select ct.check('a preacher unpublishes and restricts their own',
  not (ct.run('preacher', format('public.restrict_church_sermon(%L)', ct.v('ps'))) ? 'error'));

-- ...and nobody else's.
select ct.refused('a preacher cannot save the pastor''s sermon', 'preacher', format('public.save_church_sermon(%L, %s, %L, null)', ct.v('s1'), ct.ver('s1'), '{"title": "Mine now"}'), 'not_allowed');
select ct.refused('a preacher cannot publish the pastor''s sermon', 'preacher', format('public.publish_church_sermon(%L, %s)', ct.v('s1'), ct.ver('s1')), 'not_allowed');
select ct.refused('a preacher cannot delete the pastor''s sermon', 'preacher', format('public.delete_church_sermon(%L)', ct.v('s1')), 'not_allowed');
select ct.refused('a preacher cannot unpublish the pastor''s sermon', 'preacher', format('public.unpublish_church_sermon(%L)', ct.v('s1')), 'not_allowed');
select ct.refused('a preacher cannot duplicate the pastor''s sermon', 'preacher', format('public.duplicate_church_sermon(%L)', ct.v('s1')), 'not_allowed');
select ct.refused('another preacher cannot save it', 'preacher2', format('public.save_church_sermon(%L, %s, %L, null)', ct.v('ps'), ct.ver('ps'), '{"title": "x"}'), 'not_allowed');
select ct.check('a preacher cannot read another person''s draft row',
  (ct.dml('preacher2', format('select 1 from public.church_sermons where id = %L', ct.v('ps'))))::text = '0');
select ct.check('a preacher cannot change another person''s cover',
  ct.run('preacher2', format('public.genesis_can_edit_cover(%L)', ct.g('grace') || '/' || ct.v('ps') || '/' || gen_random_uuid() || '.jpg')) = '"false"'::jsonb);
select ct.refused('a preacher cannot change locations', 'preacher', format('public.set_church_locations(%L, %L)', ct.g('grace'), '[]'), 'not_allowed');
select ct.refused('a preacher cannot list the church', 'preacher', format('public.set_sermons_listed(%L, true)', ct.g('grace')), 'not_allowed');
select ct.refused('a preacher cannot make a new invite code', 'preacher', format('public.new_invite_code(%L)', ct.g('grace')), 'leaders_only');
select ct.refused('a preacher cannot turn sermons off', 'preacher', format('public.set_church_sermons(%L, false)', ct.g('grace')), 'not_allowed');

-- Lists: own sermons with their state, others' as published, never others' drafts.
select ct.set('plist', (ct.run('preacher2', format('public.group_sermons(%L)', ct.g('grace'))))::text);
select ct.check('another preacher sees no one else''s drafts',
  not exists (select 1 from jsonb_array_elements(ct.v('plist')::jsonb) e where e->>'status' <> 'published'), ct.v('plist')::jsonb);
select ct.set('plist1', (ct.run('preacher', format('public.group_sermons(%L)', ct.g('grace'))))::text);
select ct.check('a preacher sees their own sermon as theirs, with who edited it',
  ct.v('plist1')::jsonb @> jsonb_build_array(jsonb_build_object('id', ct.v('ps'), 'mine', true, 'can_edit', true, 'started_by', 'Preacher One', 'edited_by', 'Preacher One')),
  ct.v('plist1')::jsonb);
select ct.check('a preacher sees others'' published sermons read-only',
  exists (select 1 from jsonb_array_elements(ct.v('plist1')::jsonb) e where e->>'mine' = 'false' and e->>'can_edit' = 'false')
  and not exists (select 1 from jsonb_array_elements(ct.v('plist1')::jsonb) e where e->>'mine' = 'false' and e->>'status' <> 'published'),
  ct.v('plist1')::jsonb);
select ct.check('admins see the preacher''s sermon with who started it',
  (ct.run('admin1', format('public.group_sermons(%L)', ct.g('grace')))) @> jsonb_build_array(jsonb_build_object('id', ct.v('ps'), 'started_by', 'Preacher One', 'can_edit', true)));

-- Reports: a preacher sees their own sermons' reports and can't judge them.
select ct.run('r1', format('public.report_church_sermon(%L, %L)', ct.v('ps_slug'), 'Typo'));
select ct.set('preports', (ct.run('preacher', format('public.group_sermon_reports(%L)', ct.g('grace'))))::text);
select ct.check('the preacher sees reports on their sermon only',
  ct.len(ct.v('preports')::jsonb) = 1 and ct.v('preports')::jsonb->0->>'sermon_id' = ct.v('ps'), ct.v('preports')::jsonb);
select ct.refused('a preacher cannot keep or take down a reported sermon', 'preacher', format('public.review_church_sermon_reports(%L, true)', ct.v('ps')), 'not_allowed');
select ct.check('an admin can',
  not (ct.run('admin1', format('public.review_church_sermon_reports(%L, true)', ct.v('ps'))) ? 'error'));

-- Admins step in: edit any sermon, hand it to someone else.
select ct.set('r', ct.save('admin1', 'ps', '{"title": "Edited by an admin"}')::text);
select ct.check('an admin edits a preacher''s sermon',
  ct.v('r')::jsonb->>'draft_version' is not null
  and (select updated_by = ct.p('admin1') from public.church_sermons where id = ct.v('ps')::uuid), ct.v('r')::jsonb);
select ct.refused('a sermon goes only to a preacher or admin', 'admin1', format('public.change_sermon_owner(%L, %L)', ct.v('ps'), ct.p('member')), 'not_a_writer');
select ct.refused('a preacher cannot hand a sermon over', 'preacher', format('public.change_sermon_owner(%L, %L)', ct.v('ps'), ct.p('preacher2')), 'not_allowed');
select ct.check('an admin hands it to another preacher',
  not (ct.run('admin1', format('public.change_sermon_owner(%L, %L)', ct.v('ps'), ct.p('preacher2'))) ? 'error')
  and (ct.save('preacher2', 'ps', '{"title": "Mine now"}'))->>'draft_version' is not null);
select ct.refused('the first preacher no longer edits it', 'preacher', format('public.save_church_sermon(%L, %s, %L, null)', ct.v('ps'), ct.ver('ps'), '{"title": "x"}'), 'not_allowed');

-- A muted preacher waits; one who steps down or is removed stops; the sermons stay.
update public.group_members set muted_until = now() + interval '1 hour' where group_id = ct.g('grace') and user_id = ct.p('preacher2');
select ct.refused('a muted preacher cannot write', 'preacher2', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'x'), 'not_allowed');
update public.group_members set muted_until = null where group_id = ct.g('grace') and user_id = ct.p('preacher2');
select ct.check('a preacher steps down',
  not (ct.run('preacher2', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher2'), 'member')) ? 'error'));
select ct.refused('then cannot write', 'preacher2', format('public.save_church_sermon(%L, %s, %L, null)', ct.v('ps'), ct.ver('ps'), '{"title": "x"}'), 'not_allowed');
select ct.check('the sermon stays with the church', (select deleted_at is null from public.church_sermons where id = ct.v('ps')::uuid));
select ct.check('an admin removes a preacher',
  not (ct.run('admin1', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'member')) ? 'error')
  and ct.run('preacher', 'public.my_sermon_churches()') = '[]'::jsonb);
select ct.check('making an admin a member again doesn''t bring back an old preacher role',
  not (ct.run('pastor', format('public.set_church_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'preacher')) ? 'error')
  and not (ct.run('pastor', format('public.set_member_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'leader')) ? 'error')
  and not (ct.run('pastor', format('public.set_member_role(%L, %L, %L)', ct.g('grace'), ct.p('preacher'), 'member')) ? 'error')
  and ct.run('preacher', 'public.my_sermon_churches()') = '[]'::jsonb);
select ct.check('members still read only published copies',
  ct.len(ct.run('member', format('public.group_sermons(%L)', ct.g('grace')))) > 0
  and not exists (select 1 from jsonb_array_elements(ct.run('member', format('public.group_sermons(%L)', ct.g('grace')))) e where e ? 'status'));

-- Result -------------------------------------------------------------------------------

select 'FAIL ' || name || coalesce(': ' || detail, '') as failed from ct.results where not ok order by n;
do $$
declare failed integer := (select count(*) from ct.results where not ok);
        total integer := (select count(*) from ct.results);
begin
  if failed > 0 then raise exception '% of % checks failed', failed, total; end if;
  raise notice 'all % checks passed', total;
end $$;
select 'PASS ' || count(*) || ' checks' from ct.results;
