-- Church sermons on the web (VRS-18, checkpoint 2): what Church Studio and the
-- guest page at versely.7twenty8studio.com need beyond 20261120000000.
--
--   * Covers for readers: a reader may download a sermon's published cover,
--     and only while they may read that sermon. Storage rechecks it on every
--     request (the web's /s/<slug>/cover route sends the reader's own
--     session, or the anon key for guests), so an unpublish, a switch turned
--     off, a ban or a restriction to members applies to the very next
--     request. No signed links. Draft covers stay visible to the church's
--     leaders only.
--   * my_sermon_churches(): the churches the signed-in person can publish
--     for, for Studio's church picker.
--
-- Explicit statements, no drops; safe to run again.

-- Covers for readers ---------------------------------------------------------------

-- The name is the live published cover of a sermon the caller may read now.
create or replace function public.genesis_can_read_cover(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
    and exists (
      select 1 from public.church_sermons s
      join public.church_sermon_revisions r on r.id = s.published_revision_id
      where s.id::text = split_part(p_name, '/', 2)
        and s.group_id::text = split_part(p_name, '/', 1)
        and r.details#>>'{cover,path}' = p_name
        and public.genesis_can_read_sermon(s));
$$;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'Sermon covers: readers see') then
    create policy "Sermon covers: readers see" on storage.objects for select to anon, authenticated
      using (bucket_id = 'sermon-covers' and public.genesis_can_read_cover(name));
  end if;
end;
$$;

-- Studio ---------------------------------------------------------------------------

-- The churches the caller can publish for (owner or moderator, both switches
-- on, not banned), by name.
create or replace function public.my_sermon_churches()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', g.id,
      'name', g.name,
      'role', case when g.owner_id = auth.uid() then 'owner' else 'moderator' end,
      'listed', g.sermons_listed)
    order by lower(g.name)), '[]'::jsonb)
  from public.groups g
  join public.group_members m on m.group_id = g.id and m.user_id = auth.uid() and m.role = 'leader'
  where g.deleted_at is null and public.genesis_can_edit_sermons(g.id);
$$;

-- Grants -------------------------------------------------------------------------------

revoke all on function public.genesis_can_read_cover(text) from public;
revoke all on function public.my_sermon_churches() from public, anon;

grant execute on function public.genesis_can_read_cover(text) to anon, authenticated;
grant execute on function public.my_sermon_churches() to authenticated;
