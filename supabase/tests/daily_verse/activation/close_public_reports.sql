-- Restores Internal-only reports (undoes open_public_reports.sql). dv-report then answers
-- public reports with 503 "unavailable" and stores nothing. Prints the setting after the change.
update daily_verse.settings set accepted_channels = array['internal'], updated_at = now() where id = 1;
select accepted_channels::text as accepted_channels, updated_at from daily_verse.settings;
