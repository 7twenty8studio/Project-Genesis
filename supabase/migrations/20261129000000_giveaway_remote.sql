-- Launch day: run the draws and the race timer from any signed-in device
-- (the host's iPad) while the projector's OBS scenes follow along.
--
-- Draws already live in giveaway_draws, so a scene picks up a new one by
-- reading the board. What the database didn't hold was the timer and the
-- "clear the screen" signal: they go in giveaway_events.live, written only
-- through giveaway_live with the database's clock, so every screen agrees
-- on the start and on each player's time.
--
-- live = {
--   "cleared": <epoch ms of the last clear, or absent>,
--   "timer": { "started": [ms|null, ms|null],   -- each lane's go (epoch ms)
--              "finished": [ms|null, ms|null] }, -- each lane's time (ms)
--   "names": [text, text]                        -- the two players (30 characters each)
-- }

alter table public.giveaway_events add column if not exists live jsonb not null default '{}'::jsonb;

-- The host page: as before, plus the shared live state and the database's
-- clock (epoch ms) so a screen can line its own clock up with it.
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
      where d.event = p_event), '[]'::jsonb),
    'live', v_event.live,
    'now', floor(extract(epoch from clock_timestamp()) * 1000)::bigint
  );
end;
$$;
revoke all on function public.giveaway_board(text) from public, anon;
grant execute on function public.giveaway_board(text) to authenticated;

-- One step of the shared state, timed by the database:
--   clear        the draw screens go back to waiting
--   timer_start  3-2-1 then go: both lanes not yet started (p_together), or the next one
--   timer_stop   stops lane p_lane (0 or 1) once it's running
--   timer_reset  both lanes back to zero
--   timer_names  the players' names (p_names, two of them)
-- Returns the new live state with the database's clock as "now".
create or replace function public.giveaway_live(p_event text, p_action text, p_lane integer default null, p_together boolean default true, p_names text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_live jsonb;
  v_now bigint := floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
  v_started jsonb;
  v_finished jsonb;
  v_lane integer;
  v_go bigint;
begin
  if not public.genesis_is_ops_admin() then
    raise exception 'not_allowed';
  end if;
  select live into v_live from public.giveaway_events where slug = p_event for update;
  if not found then
    raise exception 'not_found';
  end if;
  v_started := coalesce(v_live #> '{timer,started}', '[null, null]'::jsonb);
  v_finished := coalesce(v_live #> '{timer,finished}', '[null, null]'::jsonb);

  if p_action = 'clear' then
    v_live := v_live || jsonb_build_object('cleared', v_now);
  elsif p_action = 'timer_names' then
    if p_names is null or cardinality(p_names) <> 2 then
      raise exception 'invalid_names';
    end if;
    v_live := v_live || jsonb_build_object('names', jsonb_build_array(
      left(btrim(coalesce(p_names[1], '')), 30), left(btrim(coalesce(p_names[2], '')), 30)));
  elsif p_action = 'timer_start' then
    -- Ignored while a countdown is still running.
    if not exists (
      select 1 from jsonb_array_elements(v_started) s
      where jsonb_typeof(s) = 'number' and (s #>> '{}')::bigint > v_now) then
      v_go := v_now + 3000;
      for v_lane in 0..1 loop
        if jsonb_typeof(v_started -> v_lane) = 'null' and jsonb_typeof(v_finished -> v_lane) = 'null' then
          v_started := jsonb_set(v_started, array[v_lane::text], to_jsonb(v_go));
          exit when not coalesce(p_together, true);
        end if;
      end loop;
    end if;
  elsif p_action = 'timer_stop' then
    if p_lane is null or p_lane not in (0, 1) then
      raise exception 'invalid_lane';
    end if;
    if jsonb_typeof(v_started -> p_lane) = 'number'
       and (v_started ->> p_lane)::bigint <= v_now
       and jsonb_typeof(v_finished -> p_lane) = 'null' then
      v_finished := jsonb_set(v_finished, array[p_lane::text], to_jsonb(v_now - (v_started ->> p_lane)::bigint));
    end if;
  elsif p_action = 'timer_reset' then
    v_started := '[null, null]'::jsonb;
    v_finished := '[null, null]'::jsonb;
  else
    raise exception 'invalid_action';
  end if;

  if p_action not in ('clear', 'timer_names') then
    v_live := v_live || jsonb_build_object('timer', jsonb_build_object('started', v_started, 'finished', v_finished));
  end if;
  update public.giveaway_events set live = v_live where slug = p_event;
  return v_live || jsonb_build_object('now', v_now);
end;
$$;
revoke all on function public.giveaway_live(text, text, integer, boolean, text[]) from public, anon;
grant execute on function public.giveaway_live(text, text, integer, boolean, text[]) to authenticated;
