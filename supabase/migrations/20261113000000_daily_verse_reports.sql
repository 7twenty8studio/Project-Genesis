-- Daily Verse Games: problem reports, kept apart from Versely in the same project.
--
-- Everything lives in the `daily_verse` schema, owned by its own role
-- (`daily_verse_owner`) that has no rights on any Versely table. The schema
-- is NOT in the API's exposed schemas, anon and authenticated get no access
-- to it at all, and every table has row-level security with no policies.
-- Only Daily Verse Edge Functions (service role) call the functions below,
-- and each admin action re-checks the caller against `daily_verse.admins`
-- (separate from Versely's `public.ops_admins`, which is not touched).
--
-- Screenshots (optional, at most two JPEGs of 1.5 MB per report) go in the
-- existing private `attachments` bucket under `daily-verse/reports/<id>/`,
-- written and read only by the service role. Existing storage policies only
-- allow `<auth.uid>/...` paths, so no Versely user can reach that prefix.
-- No storage policy is created or changed here.
--
-- Nothing in public, storage or auth is created, altered or dropped.
-- Rollback: supabase/rollback/20261113000000_daily_verse_reports_down.sql
-- Admin allow-list seed (manual, reviewed): supabase/seed/daily_verse_admins.sql

-- Owner role ------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'daily_verse_owner') then
    create role daily_verse_owner nologin noinherit;
  end if;
end;
$$;
-- The migration runner must be able to create objects owned by it.
grant daily_verse_owner to current_user;

create schema if not exists daily_verse authorization daily_verse_owner;

set role daily_verse_owner;

revoke all on schema daily_verse from public;
grant usage on schema daily_verse to service_role;

-- Settings ------------------------------------------------------------------------
-- One row. Which build channels may submit (Internal TestFlight only at first).
create table daily_verse.settings (
  id integer primary key default 1 check (id = 1),
  accepted_channels text[] not null default array['internal'],
  updated_at timestamptz not null default now(),
  constraint settings_channels check (accepted_channels <@ array['internal', 'public'])
);
insert into daily_verse.settings (id) values (1);

-- Admins ----------------------------------------------------------------------------
-- Who may use the Daily Verse Games tab. Rows are added by hand only
-- (supabase/seed/daily_verse_admins.sql); nothing here adds anyone.
create table daily_verse.admins (
  email text primary key,
  added_at timestamptz not null default now(),
  note text check (note is null or char_length(note) <= 200),
  constraint admins_email check (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);

-- Reports ---------------------------------------------------------------------------
create table daily_verse.reports (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  app text not null default 'daily-verse-games' check (app = 'daily-verse-games'),
  channel text not null check (channel in ('internal', 'public')),
  app_version text not null check (char_length(app_version) between 1 and 20),
  build text not null check (char_length(build) between 1 and 20),
  os_version text check (os_version is null or char_length(os_version) <= 20),
  device_family text check (device_family is null or device_family in ('phone', 'pad')),
  content_language text not null check (content_language in ('en', 'es')),
  puzzle_type text not null check (puzzle_type in
    ('verse_guess', 'word_search', 'crossword', 'trivia', 'verse_builder', 'reflection', 'other')),
  content_id text not null check (char_length(content_id) between 1 and 120 and content_id ~ '^[A-Za-z0-9._:+-]+$'),
  challenge_date date,
  review_state text check (review_state is null or review_state in ('draft', 'approved')),
  category text not null check (category in ('incorrect_answer', 'unclear_clue', 'biblical_inaccuracy', 'other')),
  description text not null check (char_length(description) between 1 and 2000),
  install_hash text not null check (install_hash ~ '^[0-9a-f]{64}$'),
  screenshot_paths text[] not null default '{}' check (cardinality(screenshot_paths) <= 2),
  -- screenshot_bytes[i] is the size of screenshot_paths[i]; they always change together.
  screenshot_bytes integer[] not null default '{}' check (cardinality(screenshot_bytes) <= 2),
  status text not null default 'new' check (status in ('new', 'in_review', 'resolved', 'dismissed')),
  admin_note text check (admin_note is null or char_length(admin_note) <= 2000),
  handled_by text,
  closed_at timestamptz,
  constraint reports_closed check ((status in ('resolved', 'dismissed')) = (closed_at is not null)),
  constraint reports_screenshot_pairs check (cardinality(screenshot_paths) = cardinality(screenshot_bytes))
);
create index reports_status_idx on daily_verse.reports (status, created_at desc);
create index reports_language_idx on daily_verse.reports (content_language, created_at desc);
create index reports_puzzle_idx on daily_verse.reports (puzzle_type, created_at desc);
create index reports_category_idx on daily_verse.reports (category, created_at desc);
create index reports_install_idx on daily_verse.reports (install_hash, created_at desc);
create index reports_retention_idx on daily_verse.reports (closed_at) where closed_at is not null;

-- Audit of every admin change ----------------------------------------------------
create table daily_verse.report_events (
  id bigint generated always as identity primary key,
  report_id uuid not null references daily_verse.reports (id) on delete cascade,
  at timestamptz not null default now(),
  actor_email text not null,
  from_status text not null,
  to_status text not null,
  note text check (note is null or char_length(note) <= 2000)
);
create index report_events_report_idx on daily_verse.report_events (report_id, at);

-- Rate limits (token buckets, same pattern as public.yvp_rate_limit) --------------
-- Keys: 'install:<HMAC of the install id>', 'net:<HMAC of the network prefix>'
-- and 'global'. These keys ARE stored here (never the raw install id or IP)
-- and are deleted by purge_expired once idle for 2 days.
create table daily_verse.rate_limits (
  key text primary key check (char_length(key) <= 100),
  tokens double precision not null,
  refilled_at timestamptz not null default now()
);

alter table daily_verse.settings enable row level security;
alter table daily_verse.admins enable row level security;
alter table daily_verse.reports enable row level security;
alter table daily_verse.report_events enable row level security;
alter table daily_verse.rate_limits enable row level security;
-- No policies: anon and authenticated have no grants on this schema either.
-- The service role (BYPASSRLS) may read for support; all writes go through
-- the functions below.
grant select on all tables in schema daily_verse to service_role;

-- Functions ---------------------------------------------------------------------------
-- All SECURITY DEFINER, owned by daily_verse_owner, with search_path ''.

-- Takes one token from `p_key`. Returns 0 when taken, otherwise seconds to wait.
create function daily_verse.take_token(p_key text, p_per_hour double precision, p_burst double precision)
returns double precision
language plpgsql
security definer
set search_path = ''
as $$
declare
  rate double precision := p_per_hour / 3600.0;
  moment timestamptz := clock_timestamp();
  row_ daily_verse.rate_limits;
  available double precision;
begin
  if p_key is null or p_per_hour <= 0 or p_burst < 1 then
    raise exception 'invalid rate limit' using errcode = '22023';
  end if;
  select * into row_ from daily_verse.rate_limits where key = p_key for update;
  if not found then
    insert into daily_verse.rate_limits (key, tokens, refilled_at) values (p_key, p_burst - 1, moment)
    on conflict (key) do nothing;
    if found then return 0; end if;
    select * into row_ from daily_verse.rate_limits where key = p_key for update;
  end if;
  available := least(p_burst, row_.tokens + extract(epoch from moment - row_.refilled_at) * rate);
  if available >= 1 then
    update daily_verse.rate_limits set tokens = available - 1, refilled_at = moment where key = p_key;
    return 0;
  end if;
  update daily_verse.rate_limits set tokens = available, refilled_at = moment where key = p_key;
  return (1 - available) / rate;
end;
$$;

-- Accepts one report from the app (called by the dv-report Edge Function after
-- it has validated the request). Returns the report id; raises
--   'rate_limited' (P0001, hint = seconds to wait), 'channel_closed', or a
--   check violation for bad fields.
-- `p_net_hash` is an HMAC of the caller's network prefix, computed by the Edge
-- Function; the raw IP never reaches the database. The HMAC is not stored with
-- the report, but it is kept as the rate-limit key 'net:<hmac>' in
-- daily_verse.rate_limits until purge_expired removes it (idle for 2 days).
create function daily_verse.submit_report(
  p_channel text, p_app_version text, p_build text, p_os_version text, p_device_family text,
  p_content_language text, p_puzzle_type text, p_content_id text, p_challenge_date date,
  p_review_state text, p_category text, p_description text, p_install_hash text, p_net_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  wait double precision;
  existing uuid;
  new_id uuid;
  body text := btrim(coalesce(p_description, ''));
  accepted text[];
begin
  select accepted_channels into accepted from daily_verse.settings where id = 1;
  if p_channel is null or not (p_channel = any (coalesce(accepted, '{}'))) then
    raise exception 'channel_closed' using errcode = 'P0001';
  end if;
  if p_net_hash is null or p_net_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid network key' using errcode = '22023';
  end if;
  -- Spam: no more than three links, and not the same character over and over.
  if (select count(*) from regexp_matches(body, 'https?://|www\.', 'gi')) > 3
     or body ~ '(.)\1{29,}' then
    raise exception 'rejected_content' using errcode = 'P0001';
  end if;

  -- Rate limits: per install, per network, and overall.
  wait := greatest(
    daily_verse.take_token('install:' || p_install_hash, 5, 5),
    daily_verse.take_token('net:' || p_net_hash, 20, 20),
    daily_verse.take_token('global', 300, 300)
  );
  if wait > 0 then
    raise exception 'rate_limited' using errcode = 'P0001', hint = ceil(wait)::text;
  end if;
  if (select count(*) from daily_verse.reports
      where install_hash = p_install_hash and created_at > now() - interval '1 day') >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001', hint = '3600';
  end if;

  -- The same report twice in ten minutes is kept once.
  select id into existing from daily_verse.reports
  where install_hash = p_install_hash and content_id = p_content_id and category = p_category
    and created_at > now() - interval '10 minutes'
  order by created_at desc limit 1;
  if existing is not null then return existing; end if;

  insert into daily_verse.reports (
    channel, app_version, build, os_version, device_family, content_language, puzzle_type,
    content_id, challenge_date, review_state, category, description, install_hash
  ) values (
    p_channel, p_app_version, p_build, nullif(p_os_version, ''), nullif(p_device_family, ''),
    p_content_language, p_puzzle_type, p_content_id, p_challenge_date, nullif(p_review_state, ''),
    p_category, body, p_install_hash
  ) returning id into new_id;
  return new_id;
end;
$$;

-- Records a screenshot the Edge Function has uploaded. The path is built here,
-- never taken from the caller: daily-verse/reports/<report id>/<1|2>.jpg
create function daily_verse.attach_screenshot(p_report_id uuid, p_index integer, p_bytes integer)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  path text;
begin
  if p_index not in (1, 2) then raise exception 'invalid screenshot index' using errcode = '22023'; end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 1572864 then
    raise exception 'screenshot too large' using errcode = '22023';
  end if;
  path := 'daily-verse/reports/' || p_report_id::text || '/' || p_index::text || '.jpg';
  update daily_verse.reports
  set screenshot_paths = array_append(screenshot_paths, path),
      screenshot_bytes = array_append(screenshot_bytes, p_bytes),
      updated_at = now()
  where id = p_report_id and not (path = any (screenshot_paths)) and cardinality(screenshot_paths) < 2
    and created_at > now() - interval '1 hour';
  if not found then raise exception 'cannot attach screenshot' using errcode = 'P0001'; end if;
  return path;
end;
$$;

create function daily_verse.is_admin(p_email text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (select 1 from daily_verse.admins where email = lower(btrim(p_email)));
$$;

-- Admin inbox. `p_actor_email` is the verified email of the signed-in caller
-- (the dv-admin function takes it from the Supabase Auth token, never from the request body).
create function daily_verse.admin_list_reports(
  p_actor_email text, p_status text default null, p_language text default null,
  p_puzzle_type text default null, p_category text default null,
  p_before timestamptz default null, p_limit integer default 50
)
returns setof daily_verse.reports
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not daily_verse.is_admin(p_actor_email) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  return query
    select * from daily_verse.reports r
    where (p_status is null or r.status = p_status)
      and (p_language is null or r.content_language = p_language)
      and (p_puzzle_type is null or r.puzzle_type = p_puzzle_type)
      and (p_category is null or r.category = p_category)
      and (p_before is null or r.created_at < p_before)
    order by r.created_at desc
    limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$$;

-- Changes a report's status and/or note, with an audit row.
create function daily_verse.admin_update_report(
  p_actor_email text, p_report_id uuid, p_status text, p_note text default null
)
returns daily_verse.reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_ daily_verse.reports;
  result daily_verse.reports;
  actor text := lower(btrim(p_actor_email));
begin
  if not daily_verse.is_admin(actor) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if p_status not in ('new', 'in_review', 'resolved', 'dismissed') then
    raise exception 'invalid status' using errcode = '22023';
  end if;
  select * into current_ from daily_verse.reports where id = p_report_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;

  update daily_verse.reports set
    status = p_status,
    admin_note = coalesce(p_note, admin_note),
    handled_by = actor,
    closed_at = case
      when p_status in ('resolved', 'dismissed') then coalesce(case when current_.status in ('resolved', 'dismissed') then current_.closed_at end, now())
      else null end,
    updated_at = now()
  where id = p_report_id
  returning * into result;

  insert into daily_verse.report_events (report_id, actor_email, from_status, to_status, note)
  values (p_report_id, actor, current_.status, p_status, p_note);
  return result;
end;
$$;

-- Retention ---------------------------------------------------------------------------
-- Screenshots are due 90 days after a report is resolved or dismissed, and in
-- any case when the report itself is due (one year after it was sent).
-- Storage objects can't be removed from SQL, so the cleanup job (Edge
-- Function, PR B) asks for this list, deletes the files through the Storage
-- API, then calls mark_screenshots_deleted.
create function daily_verse.screenshots_due_for_deletion(p_limit integer default 100)
returns table (report_id uuid, path text)
language sql
security definer
set search_path = ''
stable
as $$
  select r.id, p.path
  from daily_verse.reports r, unnest(r.screenshot_paths) as p(path)
  where cardinality(r.screenshot_paths) > 0
    and (r.closed_at < now() - interval '90 days' or r.created_at < now() - interval '1 year')
  order by r.created_at
  limit least(greatest(coalesce(p_limit, 100), 1), 1000);
$$;

-- Call only after the Storage deletion of those paths has succeeded. Each path
-- is removed together with its size; paths not on the report change nothing.
create function daily_verse.mark_screenshots_deleted(p_report_id uuid, p_paths text[])
returns void
language sql
security definer
set search_path = ''
as $$
  update daily_verse.reports r
  set screenshot_paths = array(
        select t.path from unnest(r.screenshot_paths, r.screenshot_bytes) with ordinality as t(path, bytes, i)
        where not (t.path = any (p_paths)) order by t.i),
      screenshot_bytes = array(
        select t.bytes from unnest(r.screenshot_paths, r.screenshot_bytes) with ordinality as t(path, bytes, i)
        where not (t.path = any (p_paths)) order by t.i),
      updated_at = now()
  where r.id = p_report_id and r.screenshot_paths && coalesce(p_paths, '{}');
$$;

-- Deletes reports (and their audit rows) a year after they were sent, once
-- their screenshots are gone, plus idle rate-limit rows. Run daily by pg_cron.
create function daily_verse.purge_expired()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  reports_deleted integer;
  limits_deleted integer;
begin
  delete from daily_verse.reports
  where created_at < now() - interval '1 year' and cardinality(screenshot_paths) = 0;
  get diagnostics reports_deleted = row_count;
  delete from daily_verse.rate_limits where key <> 'global' and refilled_at < now() - interval '2 days';
  get diagnostics limits_deleted = row_count;
  return jsonb_build_object('reports', reports_deleted, 'rate_limits', limits_deleted);
end;
$$;

-- Only the service role may call any of these.
revoke all on all functions in schema daily_verse from public;
grant execute on all functions in schema daily_verse to service_role;

reset role;

-- Schedule (pg_cron is already enabled for Versely's ops alerts). Daily at
-- 03:17 UTC. The screenshot cleanup job is scheduled with its Edge Function (PR B).
select cron.schedule('daily-verse-retention', '17 3 * * *', $$ select daily_verse.purge_expired(); $$);
