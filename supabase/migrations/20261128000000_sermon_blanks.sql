-- Fill-in-the-blank handouts (owner's plan, 22 November 2026, "Fill-in-the-blank
-- sermon handouts").
--
--   * A blank is written in the pastor's own words in the draft (headings,
--     paragraphs and list items; never Scripture or a quotation):
--     "[[Thanking]]", "[[Thanking|T]]" (with a hint), "[[...]]" (open: the
--     member's own words, never checked), "[[]]" (still waiting for its
--     answer: Publish refuses). The same rules as web/src/lib/blanks.ts.
--   * Publishing numbers them through the outline, writes "[[1]]", "[[2]]"…
--     in the published blocks and keeps the key apart in the revision's
--     `blanks` ([{n, answer, hint}], answer null for an open blank).
--   * church_sermons.answers: 'reveal' (after the pastor reveals them, the
--     default), 'now' or 'never'; copied to each revision when published.
--     A reveal names one revision (answers_revealed_revision_id), so a new
--     revision always starts hidden.
--   * published_sermon gives readers each blank's number, hint and whether
--     it's open, plus `answers` ('hidden', 'revealed' or 'never'). The
--     answer itself only once revealed for that revision: never in any
--     reader response before.
--   * sermons.handouts: a member's own saved work on church handouts (the
--     revision they filled in, their answers, and the key only if they had
--     it), synced with their sermon notes. Private like every sermons row.
--
-- Explicit statements, no drops; safe to run twice.

alter table public.church_sermons add column if not exists answers text not null default 'reveal';
alter table public.church_sermons add column if not exists answers_revealed_revision_id uuid;
alter table public.church_sermon_revisions add column if not exists blanks jsonb not null default '[]'::jsonb;
alter table public.church_sermon_revisions add column if not exists answers text not null default 'reveal';
alter table public.sermons add column if not exists handouts jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'church_sermons_answers_check') then
    alter table public.church_sermons add constraint church_sermons_answers_check
      check (answers in ('reveal', 'now', 'never'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'church_sermons_answers_revealed_revision_fkey') then
    alter table public.church_sermons add constraint church_sermons_answers_revealed_revision_fkey
      foreign key (answers_revealed_revision_id) references public.church_sermon_revisions (id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'church_sermon_revisions_answers_check') then
    alter table public.church_sermon_revisions add constraint church_sermon_revisions_answers_check
      check (answers in ('reveal', 'now', 'never'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'church_sermon_revisions_blanks_check') then
    alter table public.church_sermon_revisions add constraint church_sermon_revisions_blanks_check
      check (jsonb_typeof(blanks) = 'array');
  end if;
  if not exists (select 1 from pg_constraint where conname = 'sermons_handouts_shape') then
    alter table public.sermons add constraint sermons_handouts_shape
      check (handouts is null or (jsonb_typeof(handouts) = 'array' and jsonb_array_length(handouts) <= 10
                                  and octet_length(handouts::text) <= 1000000));
  end if;
end;
$$;

-- Blanks ---------------------------------------------------------------------------

-- One piece of the pastor's text with its blanks numbered from
-- jsonb_array_length(p_blanks) + 1: {"text": with "[[n]]" markers, "blanks":
-- p_blanks plus the new ones}. Refuses a blank still waiting for its answer,
-- or one too long.
create or replace function public.genesis_blank_text(p_text text, p_blanks jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  rest text := coalesce(p_text, '');
  out_ text := '';
  blanks jsonb := coalesce(p_blanks, '[]'::jsonb);
  i integer;
  j integer;
  inner_ text;
  bar integer;
  answer_ text;
  hint_ text;
begin
  loop
    i := strpos(rest, '[[');
    exit when i = 0;
    j := strpos(substr(rest, i + 2), ']]');
    exit when j = 0;
    inner_ := substr(rest, i + 2, j - 1);
    if inner_ ~ '[][\n\r]' then
      -- Not a blank: keep the first bracket as words and look again after it.
      out_ := out_ || substr(rest, 1, i);
      rest := substr(rest, i + 1);
      continue;
    end if;
    bar := strpos(inner_, '|');
    answer_ := regexp_replace(case when bar = 0 then inner_ else substr(inner_, 1, bar - 1) end, '^\s+|\s+$', '', 'g');
    hint_ := case when bar = 0 then null
                  else nullif(regexp_replace(substr(inner_, bar + 1), '^\s+|\s+$', '', 'g'), '') end;
    if answer_ in ('...', '…') then
      answer_ := null;
    elsif answer_ = '' then
      raise exception 'blank_needs_answer' using errcode = 'P0001';
    end if;
    if char_length(answer_) > 100 or char_length(hint_) > 60 then
      raise exception 'blank_too_long' using errcode = 'P0001';
    end if;
    blanks := blanks || jsonb_build_array(jsonb_build_object(
      'n', jsonb_array_length(blanks) + 1, 'answer', answer_, 'hint', hint_));
    out_ := out_ || substr(rest, 1, i - 1) || '[[' || jsonb_array_length(blanks) || ']]';
    rest := substr(rest, i + 2 + j + 1);
  end loop;
  return jsonb_build_object('text', out_ || rest, 'blanks', blanks);
end;
$$;

-- Published blocks with their blanks numbered in order, and the key apart:
-- {"blocks": [...], "blanks": [{n, answer, hint}]}. Blanks only in
-- headings, paragraphs and list items; a quotation holding one is refused
-- (blanks are never put in Scripture or quoted words), and so are more than
-- 100.
create or replace function public.genesis_sermon_blanks(p_blocks jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  b jsonb;
  r jsonb;
  item jsonb;
  items jsonb;
  out_ jsonb := '[]'::jsonb;
  blanks jsonb := '[]'::jsonb;
begin
  for b in select value from jsonb_array_elements(coalesce(p_blocks, '[]'::jsonb)) loop
    if b->>'kind' in ('heading', 'paragraph') then
      r := public.genesis_blank_text(b->>'text', blanks);
      blanks := r->'blanks';
      b := jsonb_set(b, '{text}', r->'text');
    elsif b->>'kind' = 'list' then
      items := '[]'::jsonb;
      for item in select value from jsonb_array_elements(b->'items') loop
        r := public.genesis_blank_text(item #>> '{}', blanks);
        blanks := r->'blanks';
        items := items || jsonb_build_array(r->'text');
      end loop;
      b := jsonb_set(b, '{items}', items);
    elsif b->>'kind' = 'quote' then
      if jsonb_array_length(public.genesis_blank_text(b->>'text', '[]'::jsonb)->'blanks') > 0 then
        raise exception 'blank_in_quotation' using errcode = 'P0001';
      end if;
    end if;
    out_ := out_ || jsonb_build_array(b);
  end loop;
  if jsonb_array_length(blanks) > 100 then
    raise exception 'too_many_blanks' using errcode = 'P0001';
  end if;
  return jsonb_build_object('blocks', out_, 'blanks', blanks);
end;
$$;

-- What readers get of a revision's blanks: number, hint and whether it's
-- open; the answer only when revealed.
create or replace function public.genesis_reader_blanks(p_blanks jsonb, p_revealed boolean)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object('n', (x->>'n')::integer, 'open', x->'answer' is null or jsonb_typeof(x->'answer') = 'null', 'hint', x->'hint')
    || case when p_revealed then jsonb_build_object('answer', x->'answer') else '{}'::jsonb end
    order by (x->>'n')::integer), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_blanks, '[]'::jsonb)) x;
$$;

-- Writing (as in 20261121000000, plus the Answers setting and blanks) -------------------

create or replace function public.save_church_sermon(p_sermon uuid, p_expected_version integer, p_details jsonb, p_blocks jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  d jsonb := coalesce(p_details, '{}'::jsonb);
  blocks jsonb;
  k text;
  limits constant jsonb := '{"title": 200, "speaker": 120, "series": 120, "time_zone": 64, "location": 200, "cover_alt": 300}';
  new_cover uuid;
  review_ jsonb;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  perform public.genesis_check_version(row_, p_expected_version);
  if jsonb_typeof(d) is distinct from 'object' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'not an object';
  end if;
  for k in select jsonb_object_keys(d) loop
    if k not in ('title', 'speaker', 'series', 'preached_on', 'time_zone', 'location', 'language', 'audience', 'cover', 'cover_alt', 'cover_decorative', 'review', 'answers') then
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'unknown field ' || k;
    end if;
    if limits ? k and (coalesce(jsonb_typeof(d->k), 'null') not in ('string', 'null')
                       or char_length(btrim(coalesce(d->>k, ''))) > (limits->>k)::integer) then
      raise exception 'invalid_details' using errcode = 'P0001', detail = k;
    end if;
  end loop;
  if d ? 'language' and coalesce(d->>'language', '') not in ('en', 'es', 'pt', 'other') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'language';
  end if;
  if d ? 'audience' and coalesce(d->>'audience', '') not in ('link', 'members') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'audience';
  end if;
  if d ? 'answers' and coalesce(d->>'answers', '') not in ('reveal', 'now', 'never') then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'answers';
  end if;
  if d ? 'cover_decorative' and jsonb_typeof(d->'cover_decorative') is distinct from 'boolean' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'cover_decorative';
  end if;
  if d ? 'preached_on' and d->>'preached_on' is not null and (d->>'preached_on') !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'invalid_details' using errcode = 'P0001', detail = 'preached_on';
  end if;
  new_cover := row_.cover_id;
  if d ? 'cover' then
    if d->>'cover' is null then
      new_cover := null;
    elsif (d->>'cover') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          or not exists (select 1 from storage.objects o where o.bucket_id = 'sermon-covers'
                         and o.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, (d->>'cover')::uuid))
          or exists (select 1 from public.church_sermon_retired_covers t
                     where t.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, (d->>'cover')::uuid)) then
      -- Checked while holding the sermon's row lock, which the sweep takes
      -- before retiring a cover of this sermon.
      raise exception 'invalid_details' using errcode = 'P0001', detail = 'cover';
    else
      new_cover := (d->>'cover')::uuid;
    end if;
  end if;
  blocks := case when p_blocks is null then row_.draft_blocks else public.genesis_clean_sermon_blocks(p_blocks) end;
  review_ := case when d ? 'review' then public.genesis_clean_sermon_review(d->'review') else row_.draft_review end;
  update public.church_sermons set
    title = case when d ? 'title' then btrim(coalesce(d->>'title', '')) else title end,
    speaker = case when d ? 'speaker' then btrim(coalesce(d->>'speaker', '')) else speaker end,
    series = case when d ? 'series' then nullif(btrim(coalesce(d->>'series', '')), '') else series end,
    preached_on = case when d ? 'preached_on' then (d->>'preached_on')::date else preached_on end,
    time_zone = case when d ? 'time_zone' then nullif(btrim(coalesce(d->>'time_zone', '')), '') else time_zone end,
    location = case when d ? 'location' then btrim(coalesce(d->>'location', '')) else location end,
    language = coalesce(d->>'language', language),
    audience = coalesce(d->>'audience', audience),
    answers = coalesce(d->>'answers', answers),
    cover_id = new_cover,
    cover_alt = case when d ? 'cover_alt' then btrim(coalesce(d->>'cover_alt', '')) else cover_alt end,
    cover_decorative = case when d ? 'cover_decorative' then (d->>'cover_decorative')::boolean else cover_decorative end,
    draft_blocks = blocks,
    draft_review = review_,
    draft_version = draft_version + 1,
    updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('draft_version', row_.draft_version + 1);
end;
$$;


create or replace function public.publish_church_sermon(p_sermon uuid, p_expected_version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  last_ public.church_sermon_revisions;
  blocks jsonb;
  numbered jsonb;
  details jsonb;
  withheld integer;
  new_id uuid;
  new_number integer;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  perform public.genesis_check_version(row_, p_expected_version);
  select * into last_ from public.church_sermon_revisions where id = row_.published_revision_id;
  if found and last_.draft_version = row_.draft_version and row_.status = 'published' then
    return jsonb_build_object('revision', last_.id, 'number', last_.number, 'withheld_quotes', last_.withheld_quotes,
                              'draft_version', row_.draft_version, 'repeated', true);
  end if;
  if btrim(row_.title) = '' then raise exception 'needs_title' using errcode = 'P0001'; end if;
  if public.genesis_review_open(row_.draft_review, row_.draft_blocks) > 0 then
    raise exception 'review_open' using errcode = 'P0001';
  end if;
  if row_.cover_id is not null then
    if not row_.cover_decorative and btrim(row_.cover_alt) = '' then
      raise exception 'needs_cover_alt' using errcode = 'P0001';
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'sermon-covers'
                   and o.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id))
       or exists (select 1 from public.church_sermon_retired_covers t
                  where t.name = public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id)) then
      raise exception 'cover_missing' using errcode = 'P0001';
    end if;
  end if;
  blocks := public.genesis_publishable_blocks(row_.draft_blocks);
  if jsonb_array_length(blocks) = 0 then raise exception 'empty_outline' using errcode = 'P0001'; end if;
  -- Blanks numbered in order, their answers kept apart (never in the blocks).
  numbered := public.genesis_sermon_blanks(blocks);
  blocks := numbered->'blocks';
  select count(*) into withheld from jsonb_array_elements(blocks) b where (b#>>'{ref,quote_withheld}') = 'true';
  details := jsonb_build_object(
    'title', row_.title, 'speaker', row_.speaker, 'series', row_.series, 'preached_on', row_.preached_on,
    'time_zone', row_.time_zone, 'location', row_.location, 'language', row_.language,
    'cover', case when row_.cover_id is not null then jsonb_build_object(
      'id', row_.cover_id,
      'path', public.genesis_sermon_cover_path(row_.group_id, row_.id, row_.cover_id),
      'alt', case when row_.cover_decorative then '' else row_.cover_alt end,
      'decorative', row_.cover_decorative) end);
  select coalesce(max(number), 0) + 1 into new_number from public.church_sermon_revisions where sermon_id = p_sermon;
  insert into public.church_sermon_revisions (sermon_id, number, details, audience, blocks, draft_version, withheld_quotes, created_by, blanks, answers)
  values (p_sermon, new_number, details, row_.audience, blocks, row_.draft_version, withheld, auth.uid(), numbered->'blanks', row_.answers)
  returning id into new_id;
  update public.church_sermons set
    published_revision_id = new_id, status = 'published', live_audience = row_.audience,
    published_at = now(), published_by = auth.uid(), updated_at = now()
  where id = p_sermon;
  return jsonb_build_object('revision', new_id, 'number', new_number, 'withheld_quotes', withheld,
                            'draft_version', row_.draft_version, 'repeated', false,
                            'blanks', jsonb_array_length(numbered->'blanks'));
end;
$$;


-- Reveal Answers (or hide them again) for the revision readers have now.
-- Owners, admins and the preacher who started it; only in "After I reveal
-- them" mode. A later publish makes a new revision, hidden again.
create or replace function public.reveal_church_sermon_answers(p_sermon uuid, p_reveal boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  rev public.church_sermon_revisions;
begin
  row_ := public.genesis_editable_sermon(p_sermon);
  select * into rev from public.church_sermon_revisions where id = row_.published_revision_id;
  if not found or row_.status <> 'published' then
    raise exception 'not_published' using errcode = 'P0001';
  end if;
  if rev.answers <> 'reveal' then
    raise exception 'answers_not_manual' using errcode = 'P0001';
  end if;
  update public.church_sermons
  set answers_revealed_revision_id = case when coalesce(p_reveal, true) then rev.id end
  where id = p_sermon;
  return jsonb_build_object('revealed', coalesce(p_reveal, true), 'revision', rev.number);
end;
$$;

-- Reading (as in 20261124000000, plus `answers` and `blanks`) --------------------------

create or replace function public.published_sermon(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  row_ public.church_sermons;
  rev public.church_sermon_revisions;
  church text;
  member boolean;
  series_ text;
  day_ text;
  prev_ jsonb;
  next_ jsonb;
  locations_ jsonb;
  revealed boolean;
begin
  if p_slug is null or p_slug !~ '^[a-z0-9]{10}$' then
    return jsonb_build_object('status', 'not_found');
  end if;
  select * into row_ from public.church_sermons where slug = p_slug;
  if not found or not public.genesis_sermon_live(row_) then
    return jsonb_build_object('status', 'not_found');
  end if;
  member := public.genesis_can_read_member_sermons(row_.group_id);
  if row_.live_audience = 'members' and not member then
    return jsonb_build_object('status', 'members_only');
  end if;
  select * into rev from public.church_sermon_revisions where id = row_.published_revision_id;
  select name, sermon_locations into church, locations_ from public.groups where id = row_.group_id;
  series_ := rev.details->>'series';
  day_ := coalesce(rev.details->>'preached_on', '');
  if series_ is not null then
    select public.genesis_sermon_summary(s) into prev_
    from public.church_sermons s join public.church_sermon_revisions r on r.id = s.published_revision_id
    where s.group_id = row_.group_id and s.id <> row_.id and r.details->>'series' = series_
      and public.genesis_can_read_sermon(s)
      and (coalesce(r.details->>'preached_on', ''), s.published_at) < (day_, row_.published_at)
    order by coalesce(r.details->>'preached_on', '') desc, s.published_at desc limit 1;
    select public.genesis_sermon_summary(s) into next_
    from public.church_sermons s join public.church_sermon_revisions r on r.id = s.published_revision_id
    where s.group_id = row_.group_id and s.id <> row_.id and r.details->>'series' = series_
      and public.genesis_can_read_sermon(s)
      and (coalesce(r.details->>'preached_on', ''), s.published_at) > (day_, row_.published_at)
    order by coalesce(r.details->>'preached_on', '') asc, s.published_at asc limit 1;
  end if;
  -- The key goes out only for this revision, once revealed (or right away).
  revealed := rev.answers = 'now' or (rev.answers = 'reveal' and row_.answers_revealed_revision_id = rev.id);
  return rev.details || jsonb_build_object(
    'status', 'ok',
    'id', row_.id,
    'slug', row_.slug,
    'group_id', row_.group_id,
    'church', church,
    'audience', row_.live_audience,
    'revision', rev.number,
    'published_at', row_.published_at,
    'blocks', rev.blocks,
    'previous', prev_,
    'next', next_,
    'locations', coalesce(locations_, '[]'::jsonb),
    'is_member', member,
    'answers', case when rev.answers = 'never' then 'never' when revealed then 'revealed' else 'hidden' end,
    'blanks', public.genesis_reader_blanks(rev.blanks, revealed));
end;
$$;

-- Grants -------------------------------------------------------------------------------

revoke all on function public.genesis_blank_text(text, jsonb) from public, anon, authenticated;
revoke all on function public.genesis_sermon_blanks(jsonb) from public, anon, authenticated;
revoke all on function public.genesis_reader_blanks(jsonb, boolean) from public, anon, authenticated;
revoke all on function public.save_church_sermon(uuid, integer, jsonb, jsonb) from public, anon;
revoke all on function public.publish_church_sermon(uuid, integer) from public, anon;
revoke all on function public.reveal_church_sermon_answers(uuid, boolean) from public, anon;

grant execute on function public.save_church_sermon(uuid, integer, jsonb, jsonb) to authenticated;
grant execute on function public.publish_church_sermon(uuid, integer) to authenticated;
grant execute on function public.reveal_church_sermon_answers(uuid, boolean) to authenticated;
grant execute on function public.published_sermon(text) to anon, authenticated;
