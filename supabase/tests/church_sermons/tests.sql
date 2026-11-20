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

-- Saving -------------------------------------------------------------------------------

select ct.set('blocks', $j$[
  {"id": "h1", "kind": "heading", "text": "The Lord is my shepherd", "level": 1},
  {"id": "p1", "kind": "paragraph", "text": "We are known by name."},
  {"id": "k1", "kind": "scripture", "ref": {"raw": "John 10:11", "start": 43010011, "end": 43010011, "status": "verified", "label": "KJV", "quote": "I am the good shepherd: the good shepherd giveth his life for the sheep."}},
  {"id": "n1", "kind": "scripture", "ref": {"raw": "John 10:14", "start": 43010014, "end": 43010014, "status": "verified", "label": "NIV", "quote": "Licensed words the church typed"}},
  {"id": "u1", "kind": "scripture", "ref": {"raw": "John 10:27", "start": 43010027, "status": "verified", "quote": "Words with no translation named"}},
  {"id": "a1", "kind": "scripture", "ref": {"raw": "Jn 10", "start": 43010001, "end": 43010042, "status": "ambiguous"}},
  {"id": "r1", "kind": "scripture", "ref": {"raw": "Reina-Valera 1909", "start": 19023001, "end": 19023006, "status": "verified", "label": "Reina-Valera 1909", "quote": "Jehová es mi pastor; nada me faltará."}},
  {"id": "l1", "kind": "list", "items": ["He knows", "He leads"], "ordered": true, "extra": "dropped"},
  {"id": "q1", "kind": "quote", "text": "A pastor's own words."}
]$j$);

select ct.check('pastor saves version 0 -> 1',
  (ct.run('pastor', format('public.save_church_sermon(%L, 0, %L, %L)', ct.v('s1'),
    '{"speaker": "Pastor Ana", "series": "Psalms of Trust", "preached_on": "2026-11-22", "time_zone": "America/Chicago"}', ct.v('blocks'))))->>'draft_version' = '1');
select ct.refused('stale save is refused, nothing overwritten', 'pastor',
  format('public.save_church_sermon(%L, 0, %L, null)', ct.v('s1'), '{"title": "Overwritten"}'), 'draft_changed');
select ct.check('title unchanged after the stale save', (select title from public.church_sermons where id = ct.v('s1')::uuid) = 'The Good Shepherd');
select ct.refused('unknown block kind refused', 'pastor',
  format('public.save_church_sermon(%L, 1, null, %L)', ct.v('s1'), '[{"id": "x", "kind": "script"}]'), 'invalid_blocks');
select ct.refused('verified range across books refused', 'pastor',
  format('public.save_church_sermon(%L, 1, null, %L)', ct.v('s1'), '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 43010011, "end": 44001001, "status": "verified"}}]'), 'invalid_blocks');
select ct.refused('impossible verse id refused', 'pastor',
  format('public.save_church_sermon(%L, 1, null, %L)', ct.v('s1'), '[{"id": "x", "kind": "scripture", "ref": {"raw": "x", "start": 99001001, "status": "verified"}}]'), 'invalid_blocks');
select ct.refused('duplicate block ids refused', 'pastor',
  format('public.save_church_sermon(%L, 1, null, %L)', ct.v('s1'), '[{"id": "x", "kind": "paragraph", "text": ""}, {"id": "x", "kind": "paragraph", "text": ""}]'), 'invalid_blocks');
select ct.refused('a draft can never be silently cut: too long a paragraph is refused', 'pastor',
  format('public.save_church_sermon(%L, 1, null, %L)', ct.v('s1'), jsonb_build_array(jsonb_build_object('id', 'x', 'kind', 'paragraph', 'text', repeat('a', 5001)))), 'invalid_blocks');
select ct.check('draft unchanged after refused saves', (select draft_version from public.church_sermons where id = ct.v('s1')::uuid) = 1);
select ct.refused('member cannot save', 'member', format('public.save_church_sermon(%L, 1, null, null)', ct.v('s1')), 'not_allowed');
select ct.refused('other church leader cannot save', 'other_pastor', format('public.save_church_sermon(%L, 1, null, null)', ct.v('s1')), 'not_allowed');
select ct.check('extra keys are not stored',
  not ((select draft_blocks from public.church_sermons where id = ct.v('s1')::uuid) @> '[{"extra": "dropped"}]'));

-- Direct table access --------------------------------------------------------------------

select ct.check('guest sees no rows', (ct.run('anon', '(select count(*) from public.church_sermons)'))::text = '"0"');
select ct.check('member sees no rows directly', (ct.run('member', '(select count(*) from public.church_sermons)'))::text = '"0"');
select ct.check('pastor reads the church''s rows', (ct.run('pastor', '(select count(*) from public.church_sermons)'))::text = '"2"');
select ct.check('other church leader sees none of them', (ct.run('other_pastor', '(select count(*) from public.church_sermons)'))::text = '"0"');
select ct.refused_dml('pastor cannot insert directly', 'pastor',
  format('insert into public.church_sermons (group_id, slug) values (%L, %L)', ct.g('grace'), 'abcdefghjk'), 'row-level security');
select ct.check('pastor cannot update directly',
  ct.dml('pastor', format('update public.church_sermons set title = %L where id = %L', 'Hacked', ct.v('s1'))) = '0');
select ct.check('nobody reads reports, stats or visits directly',
  (ct.run('pastor', '(select count(*) from public.church_sermon_reports) + (select count(*) from public.church_sermon_visits)'))::text = '"0"');

-- Publishing -----------------------------------------------------------------------------

select ct.sees('draft is not public', 'anon', 'slug1', 'not_found');
select ct.refused('publish with a stale version refused', 'pastor', format('public.publish_church_sermon(%L, 0)', ct.v('s1')), 'draft_changed');
select ct.set('pub1', (ct.run('pastor', format('public.publish_church_sermon(%L, 1)', ct.v('s1'))))::text);
select ct.check('publish withholds the NIV and the unlabelled quotation', (ct.v('pub1')::jsonb)->>'withheld_quotes' = '2', ct.v('pub1')::jsonb);
select ct.check('retried publish returns the same revision',
  (ct.run('pastor', format('public.publish_church_sermon(%L, 1)', ct.v('s1'))))->>'revision' = (ct.v('pub1')::jsonb)->>'revision');
select ct.check('one revision only', (select count(*) from public.church_sermon_revisions where sermon_id = ct.v('s1')::uuid) = 1);
select ct.refused('member cannot publish', 'member', format('public.publish_church_sermon(%L, 1)', ct.v('s1')), 'not_allowed');

select ct.set('view', (ct.sees('guest opens the link', 'anon', 'slug1', 'ok'))::text);
select ct.check('KJV quotation published as written',
  (ct.v('view')::jsonb)->'blocks' @> '[{"id": "k1", "ref": {"quote": "I am the good shepherd: the good shepherd giveth his life for the sheep."}}]');
select ct.check('RV1909 quotation published', (ct.v('view')::jsonb)->'blocks' @> '[{"id": "r1", "ref": {"quote": "Jehová es mi pastor; nada me faltará."}}]');
select ct.check('NIV words never reach readers',
  (ct.v('view')::jsonb)->'blocks' @> '[{"id": "n1", "ref": {"quote": null, "quote_withheld": true, "start": 43010014}}]'
  and position('Licensed words' in ct.v('view')) = 0);
select ct.check('unlabelled words never reach readers', position('no translation named' in ct.v('view')) = 0);
select ct.check('the reference stays when words are withheld', (ct.v('view')::jsonb)->'blocks' @> '[{"id": "n1", "ref": {"raw": "John 10:14"}}]');
select ct.check('an ambiguous reference opens nothing', (ct.v('view')::jsonb)->'blocks' @> '[{"id": "a1", "ref": {"start": null, "end": null, "status": "ambiguous"}}]');
select ct.check('the view names the church and speaker, never who published',
  (ct.v('view')::jsonb)->>'speaker' = 'Pastor Ana' and not ((ct.v('view')::jsonb) ? 'published_by') and not ((ct.v('view')::jsonb) ? 'created_by'));
select ct.check('the draft keeps the church''s words for them to see', position('Licensed words' in (select draft_blocks::text from public.church_sermons where id = ct.v('s1')::uuid)) > 0);
select ct.check('a guessed slug finds nothing', (ct.run('anon', 'public.published_sermon(''zzzzzzzzzz'')'))->>'status' = 'not_found');
select ct.check('a malformed slug finds nothing', (ct.run('anon', 'public.published_sermon(''../x'')'))->>'status' = 'not_found');

-- Members only ---------------------------------------------------------------------------

select ct.check('switch to members only',
  (ct.run('pastor', format('public.save_church_sermon(%L, 1, %L, null)', ct.v('s1'), '{"audience": "members"}')))->>'draft_version' = '2');
select ct.set('mo', (ct.sees('guest: members only, at once', 'anon', 'slug1', 'members_only'))::text);
select ct.check('members-only answer says nothing about the sermon', (ct.v('mo')::jsonb) = '{"status": "members_only"}'::jsonb, ct.v('mo')::jsonb);
select ct.sees('outsider: members only', 'outsider', 'slug1', 'members_only');
select ct.sees('banned person: members only', 'banned', 'slug1', 'members_only');
select ct.sees('member reads it', 'member', 'slug1', 'ok');
select ct.sees('other church leader: members only', 'other_pastor', 'slug1', 'members_only');
-- The former leader leaves (or is removed).
delete from public.group_members where group_id = ct.g('grace') and user_id = ct.p('former');
select ct.sees('removed leader: members only', 'former', 'slug1', 'members_only');
select ct.refused('removed leader cannot edit', 'former', format('public.save_church_sermon(%L, 2, null, null)', ct.v('s1')), 'not_allowed');
select ct.check('removed leader no longer reads drafts', (ct.run('former', '(select count(*) from public.church_sermons)'))::text = '"0"');
-- A member is banned after joining.
insert into public.group_bans (group_id, user_id, display_name) values (ct.g('grace'), ct.p('r2'), 'R2');
select ct.sees('member banned while still listed: members only', 'r2', 'slug1', 'members_only');
delete from public.group_bans where group_id = ct.g('grace') and user_id = ct.p('r2');

select ct.refused('members-only list refused for outsiders', 'outsider', format('public.group_sermons(%L)', ct.g('grace')), 'not_allowed');
select ct.check('members list shows published sermons only', ct.len(ct.run('member', format('public.group_sermons(%L)', ct.g('grace')))) = 1);
select ct.check('leaders list shows drafts too', ct.len(ct.run('pastor', format('public.group_sermons(%L)', ct.g('grace')))) = 2);
select ct.check('back to anyone with the link',
  (ct.run('pastor', format('public.save_church_sermon(%L, 2, %L, null)', ct.v('s1'), '{"audience": "link"}')))->>'draft_version' = '3');

-- Switches -------------------------------------------------------------------------------

update public.groups set sermons_enabled = false where id = ct.g('grace');
select ct.sees('church switch off: link stops at once', 'anon', 'slug1', 'not_found');
select ct.sees('church switch off: members too', 'member', 'slug1', 'not_found');
select ct.refused('church switch off: leader cannot publish', 'pastor', format('public.publish_church_sermon(%L, 3)', ct.v('s1')), 'not_allowed');
update public.groups set sermons_enabled = true where id = ct.g('grace');
update public.feature_flags set enabled = false where key = 'church_sermons';
select ct.sees('global switch off: link stops', 'anon', 'slug1', 'not_found');
update public.feature_flags set enabled = true where key = 'church_sermons';
update public.feature_flags set enabled = false where key = 'groups';
select ct.sees('groups switch off: link stops', 'anon', 'slug1', 'not_found');
update public.feature_flags set enabled = true where key = 'groups';
select ct.sees('switches back on: readable', 'anon', 'slug1', 'ok');

-- Unpublish and publish again ----------------------------------------------------------------

select ct.run('pastor', format('public.unpublish_church_sermon(%L)', ct.v('s1')));
select ct.sees('unpublish stops the link at once', 'anon', 'slug1', 'not_found');
select ct.check('publishing again makes revision 2 (the draft changed)',
  (ct.run('pastor', format('public.publish_church_sermon(%L, 3)', ct.v('s1'))))->>'number' = '2');
select ct.sees('published again', 'anon', 'slug1', 'ok');

-- Series navigation ----------------------------------------------------------------------------

select ct.set('s2', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Green Pastures')))->>'id');
select ct.run('pastor', format('public.save_church_sermon(%L, 0, %L, %L)', ct.v('s2'),
  '{"series": "Psalms of Trust", "preached_on": "2026-11-29", "audience": "members"}', '[{"id": "p", "kind": "paragraph", "text": "Rest."}]'));
select ct.run('pastor', format('public.publish_church_sermon(%L, 1)', ct.v('s2')));
select ct.check('guests are not told of a members-only next sermon', (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'next' = 'null'::jsonb);
select ct.check('members see the next sermon in the series',
  (ct.run('member', format('public.published_sermon(%L)', ct.v('slug1'))))->'next'->>'title' = 'Green Pastures');

-- Covers ---------------------------------------------------------------------------------

select ct.set('cover', (ct.run('pastor', format('public.set_church_sermon_cover(%L, true)', ct.v('s1'))))#>>'{}');
select ct.check('cover path is <group>/<sermon>.jpg', ct.v('cover') = ct.g('grace')::text || '/' || ct.v('s1') || '.jpg', to_jsonb(ct.v('cover')));
select ct.refused('publishing a cover without alt text is refused', 'pastor', format('public.publish_church_sermon(%L, 3)', ct.v('s1')), 'needs_cover_alt');
select ct.check('pastor uploads the cover',
  ct.dml('pastor', format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.v('cover'))) = '1');
select ct.refused_dml('other church leader cannot upload there', 'other_pastor',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.g('grace')::text || '/' || gen_random_uuid() || '.jpg'), 'row-level security');
select ct.refused_dml('member cannot upload', 'member',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.g('grace')::text || '/' || ct.v('s2') || '.jpg'), 'row-level security');
select ct.refused_dml('no other file names', 'pastor',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'sermon-covers', ct.g('grace')::text || '/' || ct.v('s1') || '.png'), 'row-level security');
select ct.check('guests cannot list covers', (ct.run('anon', '(select count(*) from storage.objects where bucket_id = ''sermon-covers'')'))::text = '"0"');
select ct.check('bucket is private, JPEG only, 1 MB', exists (select 1 from storage.buckets where id = 'sermon-covers'
  and not public and file_size_limit = 1048576 and allowed_mime_types = array['image/jpeg']));
select ct.run('pastor', format('public.save_church_sermon(%L, 3, %L, null)', ct.v('s1'), '{"cover_alt": "A shepherd at dusk"}'));
select ct.check('with alt text it publishes', (ct.run('pastor', format('public.publish_church_sermon(%L, 4)', ct.v('s1'))))->>'number' = '3');
select ct.check('readers get the path and alt text',
  (ct.run('anon', format('public.published_sermon(%L)', ct.v('slug1'))))->'cover' @> jsonb_build_object('path', ct.v('cover'), 'alt', 'A shepherd at dusk'));
update storage.objects set created_at = now() - interval '2 days' where name = ct.v('cover');
select ct.check('a cover in use is not an orphan', not exists (select 1 from public.orphan_sermon_covers() n where n = ct.v('cover')));
select ct.refused('only the service role lists orphans', 'pastor', '(select count(*) from public.orphan_sermon_covers())', 'permission denied');

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
select ct.run('moderator', format('public.review_church_sermon_reports(%L, true)', ct.v('s1')));
select ct.sees('kept after review: shown again', 'anon', 'slug1', 'ok');
select ct.check('reports closed', ct.len(ct.run('pastor', format('public.group_sermon_reports(%L)', ct.g('grace')))) = 0);

-- Counts ---------------------------------------------------------------------------------

select ct.set('visitor', encode(digest('visitor-1', 'sha256'), 'hex'));
select ct.refused('readers cannot write counts', 'member', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor')), 'permission denied');
select ct.refused('guests cannot write counts', 'anon', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor')), 'permission denied');
select ct.check('first open counted', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor'))) = '"true"');
select ct.check('same visitor again today not counted', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', ct.v('visitor'))) = '"false"');
select ct.check('a raw address is refused', ct.run('service', format('public.record_sermon_event(%L, %L, %L)', ct.v('slug1'), 'open', '203.0.113.9')) = '"false"');
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
select ct.check('search shows link sermons, never members-only ones',
  position('Good Shepherd' in ct.v('found')) > 0 and position('Green Pastures' in ct.v('found')) = 0);
select ct.check('too short a search returns nothing', ct.len(ct.run('anon', 'public.search_sermon_churches(''g'')')) = 0);

-- Duplicate, delete, account deletion ---------------------------------------------------------

select ct.set('dup', (ct.run('moderator', format('public.duplicate_church_sermon(%L)', ct.v('s1'))))->>'id');
select ct.check('duplicate is a new draft with the outline and no date',
  exists (select 1 from public.church_sermons d where d.id = ct.v('dup')::uuid and d.status = 'draft' and d.preached_on is null
          and d.slug <> ct.v('slug1') and d.draft_blocks = (select draft_blocks from public.church_sermons where id = ct.v('s1')::uuid)));
select ct.run('pastor', format('public.delete_church_sermon(%L)', ct.v('s2')));
select ct.check('deleted sermon is gone for members', (ct.run('member', format('public.published_sermon(%L)',
  (select slug from public.church_sermons where id = ct.v('s2')::uuid))))->>'status' = 'not_found');
select ct.refused('deleted sermon cannot be edited', 'pastor', format('public.save_church_sermon(%L, 1, null, null)', ct.v('s2')), 'not_found');
delete from auth.users where id = ct.p('moderator');
select ct.check('a volunteer deletes their account: sermons stay, their name goes',
  exists (select 1 from public.church_sermons where id = ct.v('dup')::uuid and created_by is null));

-- Quotation rule -------------------------------------------------------------------------

select ct.check('publishable: KJV, WEB, ASV, RV1909, Biblia Livre',
  public.genesis_quote_publishable('KJV') and public.genesis_quote_publishable('King James Version')
  and public.genesis_quote_publishable('web') and public.genesis_quote_publishable('ASV')
  and public.genesis_quote_publishable('RV1909') and public.genesis_quote_publishable('Reina-Valera 1909')
  and public.genesis_quote_publishable('Bíblia Livre') and public.genesis_quote_publishable('BLIVRE'));
select ct.check('reference only: NIV, ESV, NKJV, NVI, RVR1960, none',
  not public.genesis_quote_publishable('NIV') and not public.genesis_quote_publishable('ESV')
  and not public.genesis_quote_publishable('NKJV') and not public.genesis_quote_publishable('NVI')
  and not public.genesis_quote_publishable('RVR1960') and not public.genesis_quote_publishable(null)
  and not public.genesis_quote_publishable(''));

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
