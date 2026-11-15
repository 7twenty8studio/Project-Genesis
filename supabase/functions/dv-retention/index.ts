// dv-retention: the nightly Daily Verse screenshot cleanup.
//
// POST /functions/v1/dv-retention with header x-dv-retention-secret. Called by
// pg_cron through daily_verse.call_retention() (migration
// 20261114000000_daily_verse_retention_schedule.sql), which sends the Vault's
// dv_retention_secret; daily_verse.retention_secret_matches checks it. Deletes
// screenshots due under the retention rules (90 days after a report is resolved
// or dismissed, or a year after it was sent), then purges expired reports and
// idle rate limits.
//   200 {deleted, failed, reportsPurged, rateLimitsPurged}
//   403 {error: "forbidden"}   wrong or missing secret (or the schedule migration isn't applied)
//
// Deploy (only with approval): supabase functions deploy dv-retention --no-verify-jwt
//   --no-verify-jwt because pg_cron has no user session; the caller is proven by
//   the Vault secret instead, the same pattern as Versely's ops-alerts with its
//   own, separate secret.
import type { DbError } from "../_shared/dailyVerse.ts";
import { asService } from "../_shared/dailyVerseIO.ts";
import { runCleanup } from "./cleanup.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

async function callerAllowed(secret: string | null): Promise<boolean> {
  if (!secret || secret.length < 32 || secret.length > 200) return false;
  try {
    return await asService(async (tx) => (await tx`select daily_verse.retention_secret_matches(${secret}) as ok`)[0].ok === true);
  } catch {
    return false; // e.g. the schedule migration isn't applied yet
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "invalid" }, 405);
  if (!(await callerAllowed(req.headers.get("x-dv-retention-secret")))) return json({ error: "forbidden" }, 403);
  try {
    return json(await runCleanup());
  } catch (error) {
    console.error("dv-retention failed", (error as DbError)?.code ?? (error as Error)?.name ?? "unknown");
    return json({ error: "internal" }, 500);
  }
});
