-- Church sermons (VRS-18): Locations and Times, easier to fill in.
--
-- The owner asked (21 November 2026) for the address in parts, each on its
-- own line, and for times picked from lists instead of typed. A place in
-- groups.sermon_locations now also holds:
--   * street, city, region (state or province), postal_code, country: plain
--     text. When any is given, "address" is worked out from them on one line
--     (for directions and for anything that reads only "address").
--   * gatherings: up to 20, each {"day": "sun".."sat"} (every week) or
--     {"date": "YYYY-MM-DD"} (once), with "time" ("HH:MM", the church's own
--     clock) and an optional "note" (up to 60 characters). Readers show
--     them in their own language.
-- "address" and "times" typed as text before this keep working.
-- Only genesis_clean_church_locations changes. Explicit statements, no drops.

create or replace function public.genesis_clean_church_locations(p_locations jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  item jsonb;
  g jsonb;
  k text;
  f text;
  limits constant jsonb := '{"name": 80, "street": 120, "city": 80, "region": 80, "postal_code": 20, "country": 80, "address": 200, "times": 300}';
  v jsonb;
  gatherings jsonb;
  day_ text;
  date_ text;
  time_ text;
  note_ text;
  address_ text;
  cleaned jsonb := '[]'::jsonb;
begin
  if p_locations is null or jsonb_typeof(p_locations) <> 'array' then
    raise exception 'invalid_locations' using errcode = 'P0001', detail = 'not a list';
  end if;
  if jsonb_array_length(p_locations) > 10 then
    raise exception 'invalid_locations' using errcode = 'P0001', detail = 'more than 10';
  end if;
  for item in select value from jsonb_array_elements(p_locations) loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'invalid_locations' using errcode = 'P0001', detail = 'not an object';
    end if;
    for k in select jsonb_object_keys(item) loop
      if k = 'gatherings' then
        if jsonb_typeof(item->k) not in ('array', 'null') then
          raise exception 'invalid_locations' using errcode = 'P0001', detail = k;
        end if;
      elsif not limits ? k then
        raise exception 'invalid_locations' using errcode = 'P0001', detail = 'unknown field ' || k;
      elsif jsonb_typeof(item->k) not in ('string', 'null') then
        raise exception 'invalid_locations' using errcode = 'P0001', detail = k;
      end if;
    end loop;

    v := '{}'::jsonb;
    for f in select jsonb_object_keys(limits) loop
      if char_length(btrim(coalesce(item->>f, ''))) > (limits->>f)::integer then
        raise exception 'invalid_locations' using errcode = 'P0001', detail = f;
      end if;
      v := v || jsonb_build_object(f, btrim(coalesce(item->>f, '')));
    end loop;
    if char_length(v->>'name') < 1 then
      raise exception 'invalid_locations' using errcode = 'P0001', detail = 'name';
    end if;
    if concat(v->>'street', v->>'city', v->>'region', v->>'postal_code', v->>'country') <> '' then
      address_ := concat_ws(', ',
        nullif(v->>'street', ''),
        nullif(concat_ws(', ', nullif(v->>'city', ''), nullif(concat_ws(' ', nullif(v->>'region', ''), nullif(v->>'postal_code', '')), '')), ''),
        nullif(v->>'country', ''));
      v := v || jsonb_build_object('address', address_);
    end if;

    gatherings := '[]'::jsonb;
    if jsonb_typeof(item->'gatherings') = 'array' then
      if jsonb_array_length(item->'gatherings') > 20 then
        raise exception 'invalid_locations' using errcode = 'P0001', detail = 'more than 20 times';
      end if;
      for g in select value from jsonb_array_elements(item->'gatherings') loop
        if jsonb_typeof(g) <> 'object' then
          raise exception 'invalid_locations' using errcode = 'P0001', detail = 'time not an object';
        end if;
        for k in select jsonb_object_keys(g) loop
          if k not in ('day', 'date', 'time', 'note') then
            raise exception 'invalid_locations' using errcode = 'P0001', detail = 'unknown field ' || k;
          end if;
          if jsonb_typeof(g->k) not in ('string', 'null') then
            raise exception 'invalid_locations' using errcode = 'P0001', detail = k;
          end if;
        end loop;
        day_ := nullif(btrim(coalesce(g->>'day', '')), '');
        date_ := nullif(btrim(coalesce(g->>'date', '')), '');
        time_ := btrim(coalesce(g->>'time', ''));
        note_ := btrim(coalesce(g->>'note', ''));
        if (day_ is null) = (date_ is null) then
          raise exception 'invalid_locations' using errcode = 'P0001', detail = 'a day or a date';
        end if;
        if day_ is not null and day_ not in ('sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat') then
          raise exception 'invalid_locations' using errcode = 'P0001', detail = 'day';
        end if;
        if date_ is not null then
          if date_ !~ '^\d{4}-\d{2}-\d{2}$' then
            raise exception 'invalid_locations' using errcode = 'P0001', detail = 'date';
          end if;
          begin
            if to_char(date_::date, 'YYYY-MM-DD') <> date_ then
              raise exception 'invalid_locations' using errcode = 'P0001', detail = 'date';
            end if;
          exception when datetime_field_overflow or invalid_datetime_format then
            raise exception 'invalid_locations' using errcode = 'P0001', detail = 'date';
          end;
        end if;
        if time_ !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
          raise exception 'invalid_locations' using errcode = 'P0001', detail = 'time';
        end if;
        if char_length(note_) > 60 then
          raise exception 'invalid_locations' using errcode = 'P0001', detail = 'note';
        end if;
        gatherings := gatherings || jsonb_build_array(
          case when day_ is not null then jsonb_build_object('day', day_) else jsonb_build_object('date', date_) end
          || jsonb_build_object('time', time_, 'note', note_));
      end loop;
    end if;
    cleaned := cleaned || jsonb_build_array(v || jsonb_build_object('gatherings', gatherings));
  end loop;
  return cleaned;
end;
$$;

revoke all on function public.genesis_clean_church_locations(jsonb) from public, anon, authenticated;
