-- YouVersion Bibles on church sermon pages on the web (VRS-18).
--
-- The guest page's passages came only from the five free Bibles. The owner
-- chose (21 November 2026) to offer the YouVersion Bibles there too, through
-- the yvp-web-passage Edge Function and the web app's own Platform key
-- (secret YVP_WEB_APP_KEY), with every footnote, the publisher's link and at
-- most two chapters at once, as in the app.
--   * `web_youversion` switch: the whole feature (on).
--   * youversion_bibles.web_allowed: each Bible on its own, so one publisher
--     can be taken off the web at once without touching the app (on for every
--     Bible offered today, owner's decision).
--   * youversion_web_bibles(): the Bibles the guest page may list.
-- Explicit statements, no drops.

insert into public.feature_flags (key, enabled, description)
values ('web_youversion', true, 'Church sermon pages on the web (VRS-18): passages can open in YouVersion Bibles whose row has web_allowed, through yvp-web-passage. Off: only the five free Bibles.')
on conflict (key) do nothing;

alter table public.youversion_bibles add column if not exists web_allowed boolean not null default false;

update public.youversion_bibles set web_allowed = true where enabled;

-- The YouVersion Bibles a sermon page may offer, in the catalog's order. Empty
-- while the switch is off. Names and languages only: the text comes from
-- yvp-web-passage.
create or replace function public.youversion_web_bibles()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'language', b.language) order by b.sort, b.id), '[]'::jsonb)
  from public.youversion_bibles b
  where b.enabled and b.web_allowed and public.genesis_feature_on('web_youversion');
$$;

revoke all on function public.youversion_web_bibles() from public;
grant execute on function public.youversion_web_bibles() to anon, authenticated;
