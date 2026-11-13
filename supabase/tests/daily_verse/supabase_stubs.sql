-- Local stand-ins for the parts of a Supabase database the migrations use, so
-- they can run on a plain Postgres (no Docker). Test-only; never applied to a
-- real project. Mirrors the hosted defaults that matter for access control:
-- roles anon / authenticated / service_role (BYPASSRLS), auth.uid() from the
-- JWT claim, storage.objects with RLS and the usual grants, pg_cron's job table.

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
-- `postgres` on hosted Supabase is not a superuser; it can create roles.
create role postgres login createrole;
grant anon, authenticated, service_role to postgres;
grant create, connect on database dvtest to postgres;
grant usage, create on schema public to postgres;
grant usage on schema public to anon, authenticated, service_role;

create extension if not exists pgcrypto;
create schema extensions;
create function extensions.gen_random_bytes(n integer) returns bytea language sql as $$ select public.gen_random_bytes(n) $$;
grant usage on schema extensions to postgres, anon, authenticated, service_role;

-- auth ---------------------------------------------------------------------------
create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  created_at timestamptz not null default now(),
  last_sign_in_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  raw_app_meta_data jsonb not null default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '')
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
grant usage on schema auth to anon, authenticated, service_role, postgres;
grant select on auth.users to service_role, postgres;
grant references on auth.users to postgres;

-- storage -------------------------------------------------------------------------
create schema storage;
create table storage.buckets (
  id text primary key, name text not null, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[], created_at timestamptz default now()
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text not null,
  owner uuid,
  metadata jsonb,
  created_at timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;
alter table storage.buckets enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant usage on schema storage to anon, authenticated, service_role, postgres;
grant all on storage.objects, storage.buckets to anon, authenticated, service_role, postgres;
alter table storage.objects owner to postgres;
alter table storage.buckets owner to postgres;

-- pg_cron / pg_net / vault ------------------------------------------------------
create schema cron;
create table cron.job (
  jobid bigserial primary key, jobname text unique, schedule text not null, command text not null
);
create function cron.schedule(p_name text, p_schedule text, p_command text) returns bigint
language plpgsql as $$
declare id_ bigint;
begin
  insert into cron.job (jobname, schedule, command) values (p_name, p_schedule, p_command)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid into id_;
  return id_;
end $$;
create function cron.unschedule(p_name text) returns boolean language sql as $$
  with d as (delete from cron.job where jobname = p_name returning 1) select exists (select 1 from d)
$$;
grant usage on schema cron to postgres;
grant all on cron.job to postgres;
grant usage on sequence cron.job_jobid_seq to postgres;
grant execute on all functions in schema cron to postgres;

create schema net;
create function net.http_post(url text, headers jsonb default '{}', body jsonb default '{}',
                              timeout_milliseconds integer default 5000) returns bigint
language sql as $$ select 0::bigint $$;
grant usage on schema net to postgres;
grant execute on all functions in schema net to postgres;

create schema vault;
create table vault.secrets (id uuid primary key default gen_random_uuid(), name text unique, secret text, description text);
create view vault.decrypted_secrets as select id, name, secret as decrypted_secret, description from vault.secrets;
create function vault.create_secret(p_secret text, p_name text, p_description text default '') returns uuid
language sql as $$ insert into vault.secrets (secret, name, description) values (p_secret, p_name, p_description) returning id $$;
grant usage on schema vault to postgres;
grant all on all tables in schema vault to postgres;
grant execute on all functions in schema vault to postgres;
