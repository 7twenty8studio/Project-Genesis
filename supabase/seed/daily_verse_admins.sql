-- ============================================================================
--  DAILY VERSE GAMES ADMIN ALLOW-LIST: MANUAL SEED, OWNER-APPROVED ONLY
-- ============================================================================
-- Run by hand, once, after the daily_verse migration has been reviewed and
-- applied. It is NOT a migration and nothing runs it automatically.
--
-- Approved by the owner on 13 Nov 2026: only this address. Never add another
-- address here (or anywhere else) without the owner's explicit, written approval.
-- This list is separate from Versely's public.ops_admins.

insert into daily_verse.admins (email, note)
values ('7twenty8studio@gmail.com', 'Owner. Approved 2026-11-13.')
on conflict (email) do nothing;
