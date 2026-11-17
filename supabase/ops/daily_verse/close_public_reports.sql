-- STAGED REVERSAL. Restores Internal-only Daily Verse reporting if the iPhone
-- check fails (or any time public reporting must stop). Touches one row.
begin;
update daily_verse.settings set accepted_channels = array['internal'], updated_at = now() where id = 1;
select accepted_channels from daily_verse.settings where id = 1;  -- expect {internal}
commit;
-- Then confirm the public channel is closed: an attested Release report must get
-- 503 {"error":"unavailable"} (the app shows "Reports aren't being accepted right now").
