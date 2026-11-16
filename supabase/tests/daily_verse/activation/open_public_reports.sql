-- Opens Daily Verse reports to the public App Store / TestFlight build (1.0).
-- Run ONLY after migration 20261117000000_daily_verse_app_attest is applied and dv-attest and
-- dv-report (App Attest required) are deployed from the reviewed commit. Reverse with
-- close_public_reports.sql. Prints the setting after the change.
update daily_verse.settings set accepted_channels = array['internal', 'public'], updated_at = now() where id = 1;
select accepted_channels::text as accepted_channels, updated_at from daily_verse.settings;
