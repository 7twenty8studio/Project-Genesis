-- Versely launch day (Saturday 28 November 2026): the free giveaway.
--
-- People enter from their phone (a QR on the lobby signs and the countdown)
-- or the lobby iPad at versely.7twenty8studio.com/launch, and get a number.
-- The host page (/launch/host) draws numbers live on the projector: the
-- volunteers for the two games and the final golden ticket (one free year of
-- Versely Premium). Entry is free: no purchase, download or review needed.
--
-- Nobody reads these tables directly (RLS on, no policies). Entering goes
-- through giveaway_enter; the draw, the list and opening/closing entries
-- through functions that only accept Versely's ops admins (public.ops_admins,
-- the owner's sign-in email), checked in genesis_is_ops_admin().

create table if not exists public.giveaway_events (
  slug text primary key,
  name text not null,
  is_open boolean not null default false,
  created_at timestamptz not null default now(),
  constraint giveaway_events_slug check (slug ~ '^[a-z0-9-]{3,40}$')
);
alter table public.giveaway_events enable row level security;

create table if not exists public.giveaway_entries (
  event text not null references public.giveaway_events (slug),
  number integer not null,
  first_name text not null,
  email text not null,
  wants_news boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (event, number),
  constraint giveaway_entries_email_once unique (event, email),
  constraint giveaway_entries_number check (number between 1 and 9999),
  constraint giveaway_entries_name check (char_length(first_name) between 1 and 40),
  constraint giveaway_entries_email check (email = lower(email) and char_length(email) between 3 and 254 and position('@' in email) > 1)
);
alter table public.giveaway_entries enable row level security;

-- Every number drawn, in order. A drawn person who isn't in the room is
-- marked no_show and someone else is drawn; nobody is drawn twice for the
-- same purpose.
create table if not exists public.giveaway_draws (
  id bigint generated always as identity primary key,
  event text not null references public.giveaway_events (slug),
  number integer not null,
  purpose text not null,
  no_show boolean not null default false,
  drawn_at timestamptz not null default now(),
  constraint giveaway_draws_purpose check (purpose in ('volunteer', 'raffle')),
  foreign key (event, number) references public.giveaway_entries (event, number)
);
alter table public.giveaway_draws enable row level security;

create index if not exists giveaway_draws_event on public.giveaway_draws (event, purpose);

insert into public.giveaway_events (slug, name, is_open)
values ('launch-2026', 'Versely launch day', true)
on conflict (slug) do nothing;

-- Whether the signed-in person is one of Versely's ops admins (the owner).
create or replace function public.genesis_is_ops_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ops_admins
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
      and coalesce(auth.jwt() ->> 'email', '') <> ''
  );
$$;
revoke all on function public.genesis_is_ops_admin() from public, anon;
grant execute on function public.genesis_is_ops_admin() to authenticated;

-- The entry page's header: the event's name and whether it takes entries.
create or replace function public.giveaway_status(p_event text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('name', e.name, 'open', e.is_open)
  from public.giveaway_events e
  where e.slug = p_event;
$$;
revoke all on function public.giveaway_status(text) from public;
grant execute on function public.giveaway_status(text) to anon, authenticated;

-- Enters someone and returns their number. The same email gets the number it
-- already has (one entry each), and ticking "news" later keeps it ticked.
create or replace function public.giveaway_enter(p_event text, p_first_name text, p_email text, p_wants_news boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(regexp_replace(coalesce(p_first_name, ''), '\s+', ' ', 'g'));
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_number integer;
begin
  if not exists (select 1 from public.giveaway_events where slug = p_event and is_open) then
    raise exception 'closed';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then
    raise exception 'invalid_name';
  end if;
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid_email';
  end if;

  -- One at a time per event, so numbers count up with no gaps or repeats.
  perform pg_advisory_xact_lock(hashtext('giveaway:' || p_event));

  select number into v_number from public.giveaway_entries where event = p_event and email = v_email;
  if found then
    if coalesce(p_wants_news, false) then
      update public.giveaway_entries set wants_news = true where event = p_event and number = v_number;
    end if;
    return v_number;
  end if;

  select coalesce(max(number), 0) + 1 into v_number from public.giveaway_entries where event = p_event;
  if v_number > 2000 then
    raise exception 'full';
  end if;
  insert into public.giveaway_entries (event, number, first_name, email, wants_news)
  values (p_event, v_number, v_name, v_email, coalesce(p_wants_news, false));
  return v_number;
end;
$$;
revoke all on function public.giveaway_enter(text, text, text, boolean) from public;
grant execute on function public.giveaway_enter(text, text, text, boolean) to anon, authenticated;

-- "I forgot my number": the same email gives back its number and first name,
-- even after entries close. Nothing else about the entry is returned.
create or replace function public.giveaway_find(p_event text, p_email text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('number', number, 'name', first_name)
  from public.giveaway_entries
  where event = p_event and email = lower(btrim(coalesce(p_email, '')));
$$;
revoke all on function public.giveaway_find(text, text) from public;
grant execute on function public.giveaway_find(text, text) to anon, authenticated;

-- The host page: every number with its first name (never the email) and
-- every draw so far.
create or replace function public.giveaway_board(p_event text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_event public.giveaway_events;
begin
  if not public.genesis_is_ops_admin() then
    raise exception 'not_allowed';
  end if;
  select * into v_event from public.giveaway_events where slug = p_event;
  if not found then
    raise exception 'not_found';
  end if;
  return jsonb_build_object(
    'name', v_event.name,
    'open', v_event.is_open,
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object('number', number, 'name', first_name) order by number)
      from public.giveaway_entries where event = p_event), '[]'::jsonb),
    'draws', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'number', d.number, 'name', g.first_name, 'purpose', d.purpose, 'no_show', d.no_show) order by d.id)
      from public.giveaway_draws d
      join public.giveaway_entries g on g.event = d.event and g.number = d.number
      where d.event = p_event), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.giveaway_board(text) from public, anon;
grant execute on function public.giveaway_board(text) to authenticated;

create or replace function public.giveaway_set_open(p_event text, p_open boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.genesis_is_ops_admin() then
    raise exception 'not_allowed';
  end if;
  update public.giveaway_events set is_open = coalesce(p_open, false) where slug = p_event;
  if not found then
    raise exception 'not_found';
  end if;
  return coalesce(p_open, false);
end;
$$;
revoke all on function public.giveaway_set_open(text, boolean) from public, anon;
grant execute on function public.giveaway_set_open(text, boolean) to authenticated;

-- Draws one number at random (the database picks, not the browser) from the
-- entries not yet drawn for this purpose, and records it.
create or replace function public.giveaway_draw(p_event text, p_purpose text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number integer;
  v_name text;
  v_id bigint;
begin
  if not public.genesis_is_ops_admin() then
    raise exception 'not_allowed';
  end if;
  if p_purpose is null or p_purpose not in ('volunteer', 'raffle') then
    raise exception 'invalid_purpose';
  end if;
  perform pg_advisory_xact_lock(hashtext('giveaway:' || p_event));

  select g.number, g.first_name into v_number, v_name
  from public.giveaway_entries g
  where g.event = p_event
    and not exists (
      select 1 from public.giveaway_draws d
      where d.event = g.event and d.number = g.number and d.purpose = p_purpose)
  order by random()
  limit 1;
  if not found then
    raise exception 'nobody_left';
  end if;

  insert into public.giveaway_draws (event, number, purpose) values (p_event, v_number, p_purpose)
  returning id into v_id;
  return jsonb_build_object('id', v_id, 'number', v_number, 'name', v_name, 'purpose', p_purpose);
end;
$$;
revoke all on function public.giveaway_draw(text, text) from public, anon;
grant execute on function public.giveaway_draw(text, text) to authenticated;

-- "Not here": marks a draw as a no-show (the number stays out of that purpose's pool).
create or replace function public.giveaway_no_show(p_draw bigint)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.genesis_is_ops_admin() then
    raise exception 'not_allowed';
  end if;
  update public.giveaway_draws set no_show = true where id = p_draw;
  return found;
end;
$$;
revoke all on function public.giveaway_no_show(bigint) from public, anon;
grant execute on function public.giveaway_no_show(bigint) to authenticated;
