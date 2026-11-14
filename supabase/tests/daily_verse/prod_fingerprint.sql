-- READ-ONLY fingerprint of everything Versely depends on, for the production
-- deployment of 20261113000000_daily_verse_reports.sql (PRODUCTION_DEPLOYMENT_PLAN.md).
--
-- Run it in the SQL editor (or psql) BEFORE the migration and AFTER it, save
-- both outputs, and compare: every row except `daily_verse.*` must be
-- identical. It only reads catalogs; it creates, changes and deletes nothing.
-- Daily Verse's own objects (schema daily_verse, role daily_verse_owner, job
-- daily-verse-retention) are excluded from the Versely rows and reported
-- separately at the end.

with
versely_tables as (
  select n.nspname, c.relname, c.relkind, c.relrowsecurity, c.relforcerowsecurity, coalesce(c.relacl::text, '') acl
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'storage', 'auth') and c.relkind in ('r', 'v', 'm', 'S', 'p')
),
versely_columns as (
  select table_schema, table_name, column_name, data_type, is_nullable, coalesce(column_default, '') def
  from information_schema.columns where table_schema in ('public', 'storage', 'auth')
),
versely_functions as (
  select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) args,
         md5(coalesce(p.prosrc, '')) src, p.prosecdef, coalesce(p.proacl::text, '') acl,
         coalesce(array_to_string(p.proconfig, ','), '') cfg
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'storage', 'auth')
),
versely_policies as (
  select schemaname, tablename, policyname, cmd, roles::text r, coalesce(qual, '') q, coalesce(with_check, '') w
  from pg_policies where schemaname in ('public', 'storage', 'auth')
),
versely_triggers as (
  select n.nspname, c.relname, t.tgname, pg_get_triggerdef(t.oid) def, t.tgenabled
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal and n.nspname in ('public', 'storage', 'auth')
),
versely_memberships as (
  select m.rolname member, r.rolname granted, a.admin_option, a.inherit_option, a.set_option
  from pg_auth_members a join pg_roles r on r.oid = a.roleid join pg_roles m on m.oid = a.member
  where r.rolname <> 'daily_verse_owner' and m.rolname <> 'daily_verse_owner'
),
versely_roles as (
  select rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolbypassrls
  from pg_roles where rolname <> 'daily_verse_owner'
),
versely_cron as (
  select jobname, schedule, command, active from cron.job where jobname not like 'daily-verse%'
),
versely_buckets as (
  select id, public, coalesce(file_size_limit, 0) lim, coalesce(allowed_mime_types::text, '') mime from storage.buckets
),
versely_schema_acl as (
  select nspname, coalesce(nspacl::text, '') acl from pg_namespace where nspname in ('public', 'storage', 'auth', 'extensions', 'cron', 'net', 'vault')
)
select 'versely.tables' as item, count(*)::text as n,
       md5(string_agg(concat_ws('|', nspname, relname, relkind, relrowsecurity, relforcerowsecurity, acl), E'\n' order by nspname, relname)) as fingerprint
from versely_tables
union all select 'versely.columns', count(*)::text, md5(string_agg(concat_ws('|', table_schema, table_name, column_name, data_type, is_nullable, def), E'\n' order by table_schema, table_name, column_name)) from versely_columns
union all select 'versely.functions', count(*)::text, md5(string_agg(concat_ws('|', nspname, proname, args, src, prosecdef, acl, cfg), E'\n' order by nspname, proname, args)) from versely_functions
union all select 'versely.policies', count(*)::text, md5(string_agg(concat_ws('|', schemaname, tablename, policyname, cmd, r, q, w), E'\n' order by schemaname, tablename, policyname)) from versely_policies
union all select 'versely.triggers', count(*)::text, md5(string_agg(concat_ws('|', nspname, relname, tgname, def, tgenabled), E'\n' order by nspname, relname, tgname)) from versely_triggers
union all select 'versely.role_memberships', count(*)::text, md5(string_agg(concat_ws('|', member, granted, admin_option, inherit_option, set_option), E'\n' order by member, granted, admin_option)) from versely_memberships
union all select 'versely.roles', count(*)::text, md5(string_agg(concat_ws('|', rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin, rolbypassrls), E'\n' order by rolname)) from versely_roles
union all select 'versely.cron_jobs', count(*)::text, md5(string_agg(concat_ws('|', jobname, schedule, command, active), E'\n' order by jobname)) from versely_cron
union all select 'versely.storage_buckets', count(*)::text, md5(string_agg(concat_ws('|', id, public, lim, mime), E'\n' order by id)) from versely_buckets
union all select 'versely.schema_acls', count(*)::text, md5(string_agg(concat_ws('|', nspname, acl), E'\n' order by nspname)) from versely_schema_acl
union all select 'versely.storage_objects_count', count(*)::text, '' from storage.objects
union all select 'versely.auth_users_count', count(*)::text, '' from auth.users
-- Daily Verse's own objects (expected 0 / 0 / 0 / n/a before; 1 / 1 / 1 / 0 after):
union all select 'daily_verse.schema', count(*)::text, '' from pg_namespace where nspname = 'daily_verse'
union all select 'daily_verse.owner_role', count(*)::text, '' from pg_roles where rolname = 'daily_verse_owner'
union all select 'daily_verse.cron_job', count(*)::text, '' from cron.job where jobname like 'daily-verse%'
union all select 'daily_verse.admins_rows',
  (case when to_regclass('daily_verse.admins') is null then 'n/a'
        else (xpath('/row/c/text()', query_to_xml('select count(*) as c from daily_verse.admins', false, true, '')))[1]::text end), ''
order by 1;
-- Note: the storage object and user counts may change between the two runs
-- because Versely users are active; every other Versely row must not change.
-- daily_verse.admins_rows stays 0 until the separately approved seed is run.
