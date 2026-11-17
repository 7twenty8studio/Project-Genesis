-- STAGED, NOT RUN. Opens Daily Verse public reporting (Gamaliel's step 3).
-- Run only after migration 20261117000000 is applied, dv-report is deployed from
-- the reviewed commit, and the signed Release TestFlight build is ready for the
-- iPhone check. Project: Project Genesis (ulbpwygzwchsnvdeeife). Touches one row.
begin;
update daily_verse.settings set accepted_channels = array['internal', 'public'], updated_at = now() where id = 1;
select accepted_channels from daily_verse.settings where id = 1;  -- expect {internal,public}
commit;
