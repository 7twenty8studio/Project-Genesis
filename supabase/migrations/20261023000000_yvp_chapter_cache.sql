-- A shared cache of YouVersion Platform chapter responses, kept exactly as
-- long as the Platform's Cache-Control header allows (RFC 9111/7234; today
-- "public, max-age=3600"). Heather McMahan (YouVersion) confirmed that
-- following the header is how caching complies (LICENSED_BIBLES.md › 5).
-- yvp-bible serves every reader from here while a chapter is fresh, so a
-- popular chapter reaches the Platform once an hour instead of once per
-- reader. A response marked private, no-store or no-cache is never stored.
-- Only the yvp-bible function (service role) reads or writes it.
create table if not exists public.yvp_chapter_cache (
  bible integer not null,                 -- the Platform's Bible id (yvp_id)
  passage text not null,                  -- "JHN.3"
  content text not null,                  -- the response's chapter HTML, verbatim
  reference text not null default '',
  fetched_at timestamptz not null default now(),
  max_age integer not null check (max_age > 0),   -- seconds, from Cache-Control
  age_at_fetch integer not null default 0 check (age_at_fetch >= 0),  -- the Age header
  primary key (bible, passage)
);

alter table public.yvp_chapter_cache enable row level security;

-- No policies: only the service role (the yvp-bible function) uses it.

-- Expired responses are removed every hour, so nothing outlives its
-- freshness by more than an hour.
select cron.schedule(
  'yvp-chapter-cache-expire',
  '23 * * * *',
  $$ delete from public.yvp_chapter_cache
     where fetched_at + make_interval(secs => max_age - age_at_fetch) < now(); $$
);
