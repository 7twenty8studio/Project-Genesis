-- Church sermons (20261120000000): who can read and write what, the
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
  ('other_pastor'), ('r1'), ('r2'), ('r3');
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

select ct.set('stale', ct.ver('s1')::text);
select ct.run('pastor', format('public.unpublish_church_sermon(%L)', ct.v('s1')));
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
-- Readers download the published cover only while they may read the sermon,
-- rechecked by storage on every request (20261121000000).
select ct.set('c1sql', format('(select count(*) from storage.objects where bucket_id = %L and name = %L)', 'sermon-covers', (ct.v('c1')::jsonb)->>'path'));
select ct.check('a guest downloads the cover of a link sermon', (ct.run('anon', ct.v('c1sql')))::text = '"1"');
select ct.check('so does a signed-in outsider', (ct.run('outsider', ct.v('c1sql')))::text = '"1"');
select ct.run('pastor', format('public.restrict_church_sermon(%L)', ct.v('s1')));
select ct.check('restricted to members: the guest''s next request is refused', (ct.run('anon', ct.v('c1sql')))::text = '"0"');
select ct.check('restricted to members: an outsider is refused', (ct.run('outsider', ct.v('c1sql')))::text = '"0"');
select ct.check('restricted to members: a banned person is refused', (ct.run('banned', ct.v('c1sql')))::text = '"0"');
select ct.check('restricted to members: a member still downloads it', (ct.run('member', ct.v('c1sql')))::text = '"1"');
update public.groups set sermons_enabled = false where id = ct.g('grace');
select ct.check('church switch off: even a member is refused', (ct.run('member', ct.v('c1sql')))::text = '"0"');
update public.groups set sermons_enabled = true where id = ct.g('grace');
select ct.save('pastor', 's1', '{"audience": "link"}');
select ct.publish('pastor', 's1');
select ct.check('open to the link again', (ct.run('anon', ct.v('c1sql')))::text = '"1"');

-- A new picture on the draft leaves the published one alone.
select ct.set('c2', (ct.run('pastor', format('public.new_church_sermon_cover(%L)', ct.v('s1'))))::text);
select ct.dml('pastor', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', (ct.v('c2')::jsonb)->>'path'));
select ct.save('pastor', 's1', jsonb_build_object('cover', (ct.v('c2')::jsonb)->>'cover', 'cover_alt', 'Unpublished alt')::text);
select ct.check('nobody but leaders sees a cover that is only on the draft',
  (ct.run('anon', format('(select count(*) from storage.objects where name = %L)', (ct.v('c2')::jsonb)->>'path')))::text = '"0"'
  and (ct.run('member', format('(select count(*) from storage.objects where name = %L)', (ct.v('c2')::jsonb)->>'path')))::text = '"0"'
  and (ct.run('moderator', format('(select count(*) from storage.objects where name = %L)', (ct.v('c2')::jsonb)->>'path')))::text = '"1"');
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
select ct.check('a replaced cover is no longer served to readers',
  (ct.run('anon', format('(select count(*) from storage.objects where name = %L)', (ct.v('c1')::jsonb)->>'path')))::text = '"0"');
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

-- Studio's church picker (20261121000000) -----------------------------------------------

select ct.check('the pastor publishes for Grace',
  (ct.run('pastor', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'role', 'owner')));
select ct.check('a moderator publishes for Grace as a moderator',
  (ct.run('moderator', 'public.my_sermon_churches()')) @> jsonb_build_array(jsonb_build_object('id', ct.g('grace'), 'role', 'moderator')));
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
