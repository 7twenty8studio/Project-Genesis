-- For run.sh's two-session checks (after tests.sql): a sermon at draft version 1.
select ct.set('cc', (ct.run('pastor', format('public.create_church_sermon(%L, %L)', ct.g('grace'), 'Concurrency')))->>'id');
select ct.run('pastor', format('public.save_church_sermon(%L, 0, null, %L)', ct.v('cc'), '[{"id": "p", "kind": "paragraph", "text": "Together."}]'));
