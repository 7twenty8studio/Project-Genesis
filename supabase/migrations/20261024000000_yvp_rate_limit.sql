-- One pace for every request Versely sends to the YouVersion Platform.
--
-- The Platform allows 10,000 requests an hour per app key, but it also
-- refuses short bursts: about 575 chapter requests in 22 seconds (two
-- Bibles downloading at once, 24 October 2026) brought a five-minute block
-- ("retry-after: 300") far below the hourly figure. So yvp-bible takes a
-- token here before each request to the Platform (chapters served from
-- yvp_chapter_cache need none): a token bucket shared by every reader,
-- refilled at 2.5 a second (150 a minute, 9,000 an hour: under the hourly
-- limit even when used all hour) holding at most 20 for a small burst.
-- When the Platform still blocks us, `blocked_until` stops every request
-- until the block is over, so retries can't prolong it.
-- Only the yvp-bible function (service role) uses it.
create table if not exists public.yvp_rate_limit (
  id integer primary key default 1 check (id = 1),
  tokens double precision not null,
  refilled_at timestamptz not null default now(),
  blocked_until timestamptz
);

alter table public.yvp_rate_limit enable row level security;

-- No policies: only the service role uses it.

insert into public.yvp_rate_limit (id, tokens) values (1, 20)
on conflict (id) do nothing;

-- Takes one token. Returns 0 when taken, otherwise how many seconds to wait
-- before asking again (until a token refills, or the block ends).
create or replace function public.yvp_take_token()
returns double precision
language plpgsql
security definer
set search_path = public
as $$
declare
  rate constant double precision := 2.5;   -- tokens a second
  burst constant double precision := 20;   -- most held at once
  moment timestamptz := clock_timestamp();
  row_ public.yvp_rate_limit;
  available double precision;
begin
  select * into row_ from public.yvp_rate_limit where id = 1 for update;
  if not found then
    insert into public.yvp_rate_limit (id, tokens, refilled_at) values (1, burst - 1, moment);
    return 0;
  end if;
  if row_.blocked_until is not null and row_.blocked_until > moment then
    return extract(epoch from row_.blocked_until - moment);
  end if;
  available := least(burst, row_.tokens + extract(epoch from moment - row_.refilled_at) * rate);
  if available >= 1 then
    update public.yvp_rate_limit set tokens = available - 1, refilled_at = moment where id = 1;
    return 0;
  end if;
  update public.yvp_rate_limit set tokens = available, refilled_at = moment where id = 1;
  return (1 - available) / rate;
end;
$$;

-- The Platform asked us to wait: nothing goes to it until then.
create or replace function public.yvp_block(p_seconds integer)
returns void
language sql
security definer
set search_path = public
as $$
  update public.yvp_rate_limit
  set blocked_until = greatest(coalesce(blocked_until, now()), now() + make_interval(secs => greatest(p_seconds, 1))),
      tokens = 0,
      refilled_at = now() + make_interval(secs => greatest(p_seconds, 1))
  where id = 1;
$$;

revoke all on function public.yvp_take_token() from public, anon, authenticated;
revoke all on function public.yvp_block(integer) from public, anon, authenticated;
grant execute on function public.yvp_take_token() to service_role;
grant execute on function public.yvp_block(integer) to service_role;
