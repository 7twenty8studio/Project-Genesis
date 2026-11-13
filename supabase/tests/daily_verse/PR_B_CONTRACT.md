# Security contract for PR B (Daily Verse Edge Functions)

PR A only provides the database: the `daily_verse` schema, functions usable by `service_role` only, RLS on, and no policies. Its guarantees hold only if the Edge Functions in PR B (`dv-report`, `dv-admin`, and the screenshot cleanup job) follow these rules. **PR B must not merge until each rule is met and covered by a test.**

1. **The server decides the channel.** `dv-report` sets `p_channel` from server-side configuration (for example, a secret held only by Internal builds' function config, or a dedicated Internal-only endpoint). It must never pass through a channel value sent by the client. A request body field such as `"channel": "internal"` must be ignored.

2. **Internal-only is a policy gate, not proof.** In v1, the `settings.accepted_channels = {internal}` gate plus the server-decided channel restricts submissions to the Internal path. It **cannot strongly prove** that a request came from an Internal TestFlight device; anyone who obtains the endpoint and the public anon key can try it, and only the validation and rate limits stop them. Strong device proof needs **App Attest / DeviceCheck** (or another trusted mechanism), which is required before public availability.

3. **The `service_role` key never reaches the app.** The app calls `dv-report` with the public anon key only. The service role key exists only as an Edge Function secret. No app build, config file, log or response may contain it.

4. **Admin identity comes only from a validated Supabase Auth session.** `dv-admin` verifies the caller's access token with Supabase Auth (`auth.getUser(token)`) and passes **that** email (lower-cased) as `p_actor_email`. It never reads an email or role from the request body, query or headers other than `Authorization`. Unauthenticated requests get 401; emails not on `daily_verse.admins` get 403. That is separate from Versely's `ops_admins`, which must not grant Daily Verse access.

5. **Screenshot rows change only after Storage succeeds.**
   - Upload: write the file to `attachments/daily-verse/reports/<id>/<n>.jpg` first, then call `attach_screenshot`. If the call fails, delete the uploaded file.
   - Cleanup: delete the files with the Storage API, then call `mark_screenshots_deleted` **only with the paths whose deletion succeeded**. Failed deletions stay listed and are retried by the next run.
   - Paths are never taken from the client. The function builds them from the report id (`attach_screenshot` does the same).

6. **Network and install identifiers.**
   - The raw IP and the raw install id never reach the database. `dv-report` sends only HMACs (keyed with a pepper held as an Edge Function secret).
   - The network HMAC is kept as the rate-limit key `net:<hmac>` in `daily_verse.rate_limits` until `purge_expired` removes it after 2 idle days. The install HMAC is stored with each report (for grouping and the daily cap) and as `install:<hmac>`.
   - The privacy disclosures (PR F) must say exactly this.

7. **Limits are enforced again at the edge.** Before touching the database, `dv-report` rejects:
   - bodies over 4 MB
   - more than two screenshots
   - non-JPEG data (checked by magic bytes, not just the extension)
   - any file over 1.5 MB

   The database checks remain as a second line.

8. **Signed URLs** for admins last 5 minutes and are created per report on request. Storage paths aren't exposed beyond that.

9. **Errors are generic.** Responses never include SQL errors, stack traces, keys or other reports' data. Rate-limited responses return 429 with `Retry-After` (from the `rate_limited` hint).

10. **Tests in PR B** must cover each rule above, including:
    - a client-sent channel is ignored
    - a body-supplied admin email is ignored
    - a non-admin gets 403 and an ops admin who isn't a Daily Verse admin gets 403
    - a failed Storage delete leaves the path in the database
    - the service key is absent from every client artifact
