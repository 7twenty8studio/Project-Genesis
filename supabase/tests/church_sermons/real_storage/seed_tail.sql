-- After the people and churches from tests.sql: switches on, one sermon by
-- the pastor with a cover name to upload. Writes the ids for check.mjs.
update public.feature_flags set enabled = true where key in ('church_sermons', 'groups');
select ct.set('s1', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'The Good Shepherd')))->>'id');
select ct.run('pastor', format('public.save_church_sermon(%L, 0, %L, %L)', ct.v('s1'), '{"cover_alt": "Hills"}', '[{"id": "p1", "kind": "paragraph", "text": "Rest."}]'));
select ct.set('c1', (ct.run('pastor', format('public.new_church_sermon_cover(%L)', ct.v('s1'))))::text);
\pset tuples_only on
\o :ids
select jsonb_build_object('sermon', ct.v('s1'), 'cover', ct.v('c1')::jsonb, 'people', (select jsonb_object_agg(name, id) from ct.people), 'grace', ct.g('grace'));
\o
