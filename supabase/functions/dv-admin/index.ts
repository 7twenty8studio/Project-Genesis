// dv-admin: the Daily Verse Games tab of the 7twenty8 admin site.
//
// POST /functions/v1/dv-admin with the signed-in admin's access token
// (Authorization: Bearer <user JWT>, plus apikey). The admin is the email in that
// VERIFIED token (Supabase Auth getUser), checked against daily_verse.admins only.
// Versely's ops_admins grants nothing here, and nothing in the body, query or
// other headers can name the admin (PR_B_CONTRACT.md rule 4).
//   {action: "me"}                                   → {email, admin: true}
//   {action: "list", status?, language?, puzzleType?, category?, before?, limit?}
//                                                    → {reports, nextBefore}
//   {action: "update", id, status, note?}            → {report}
//   {action: "screenshots", id}                      → {screenshots: [{index, url, expiresAt}]}  (5-minute links)
//   {action: "runCleanup"}                           → {deleted, failed, reportsPurged, rateLimitsPurged}
// Errors: 401 unauthorized · 403 {error: "forbidden", email} · 400 {error: "invalid", field}
//         · 404 not_found · 429 rate_limited (Retry-After) · 500 internal. Every
//         response is Cache-Control: no-store. Shapes: tests/dv-admin.fixtures.json.
//
// CORS: only the origins in DV_ALLOWED_ORIGINS (function secret or Vault dv_allowed_origins; if unset, Versely's
// OPS_ALLOWED_ORIGINS, read-only); never "*".
//
// Deploy (only with approval): supabase functions deploy dv-admin
//   (JWT verification on: the caller must be signed in).
import {
  adminErrorToHttp, corsHeaders, isDailyVersePath, nextBefore, parseAdminAction, SIGNED_URL_SECONDS,
  toAdminReport, type DbError, type ReportRow,
} from "../_shared/dailyVerse.ts";
import { asService, setting, storage, verifiedEmail } from "../_shared/dailyVerseIO.ts";
import { runCleanup } from "../dv-retention/cleanup.ts";

Deno.serve(async (req) => {
  const origins = (await setting("DV_ALLOWED_ORIGINS").catch(() => undefined)) ?? Deno.env.get("OPS_ALLOWED_ORIGINS");
  const cors = corsHeaders(req.headers.get("Origin"), origins);
  const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json", "cache-control": "no-store", ...extra } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: { ...cors, "cache-control": "no-store" } });
  if (req.method !== "POST") return json({ error: "invalid", field: "method" }, 405);

  let email: string | null = null;
  try {
    email = await verifiedEmail(req.headers.get("Authorization"));
    if (!email) return json({ error: "unauthorized" }, 401);
    const actor = email;

    const allowed = await asService(async (tx) => (await tx`select daily_verse.is_admin(${actor}) as ok`)[0].ok === true);
    if (!allowed) return json({ error: "forbidden", email: actor }, 403);

    // A generous per-admin ceiling, and a tight one for the cleanup run.
    const limited = async (key: string, perHour: number, burst: number) =>
      Number(await asService(async (tx) => (await tx`select daily_verse.take_token(${key}, ${perHour}, ${burst}) as wait`)[0].wait));
    const general = await limited("admin:" + actor, 1200, 120);
    if (general > 0) return json({ error: "rate_limited" }, 429, { "Retry-After": String(Math.ceil(general)) });

    const parsed = parseAdminAction(await req.json().catch(() => null));
    if (!parsed.ok) return json({ error: "invalid", field: parsed.field }, 400);
    const a = parsed.value;

    switch (a.action) {
      case "me":
        return json({ email: actor, admin: true });

      case "list": {
        const rows = await asService(async (tx) => await tx`
          select * from daily_verse.admin_list_reports(${actor}, ${a.status}, ${a.language}, ${a.puzzleType},
                                                       ${a.category}, ${a.before}::timestamptz, ${a.limit})`) as unknown as ReportRow[];
        const reports = rows.map(toAdminReport);
        return json({ reports, nextBefore: nextBefore(reports, a.limit) });
      }

      case "update": {
        const [row] = await asService(async (tx) =>
          await tx`select * from daily_verse.admin_update_report(${actor}, ${a.id}::uuid, ${a.status}, ${a.note})`) as unknown as ReportRow[];
        return json({ report: toAdminReport(row) });
      }

      case "screenshots": {
        const [row] = await asService(async (tx) =>
          await tx`select screenshot_paths from daily_verse.reports where id = ${a.id}::uuid`) as unknown as { screenshot_paths: string[] }[];
        if (!row) return json({ error: "not_found" }, 404);
        const screenshots = [];
        for (const [index, path] of row.screenshot_paths.entries()) {
          if (!isDailyVersePath(path)) continue;
          const { data, error } = await storage.createSignedUrl(path, SIGNED_URL_SECONDS);
          if (error || !data?.signedUrl) continue; // e.g. the file is already gone
          screenshots.push({ index, url: data.signedUrl, expiresAt: new Date(Date.now() + SIGNED_URL_SECONDS * 1000).toISOString() });
        }
        return json({ screenshots });
      }

      case "runCleanup": {
        const wait = await limited("admin:cleanup", 6, 2);
        if (wait > 0) return json({ error: "rate_limited" }, 429, { "Retry-After": String(Math.ceil(wait)) });
        return json(await runCleanup());
      }
    }
  } catch (error) {
    const mapped = adminErrorToHttp(error as DbError, email ?? "");
    // The code only: a database message can quote values (an admin note, a description).
    if (mapped.status === 500) console.error("dv-admin failed", (error as DbError)?.code ?? "unknown");
    return json(mapped.body, mapped.status);
  }
});
