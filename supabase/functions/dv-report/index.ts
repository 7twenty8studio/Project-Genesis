// dv-report: receives a Daily Verse Games problem report from the app.
//
// POST /functions/v1/dv-report with the PUBLIC anon key (apikey + Bearer), JSON
// body as in supabase/tests/daily_verse/PR_B_CONTRACT.md and the app's
// ReportSubmission (daily-verse PR #36):
//   201 {id, screenshots}          new report (screenshots = how many were attached)
//   200 {id, duplicate: true}      the same report within 10 minutes (kept once)
//   400 {error: "invalid", field?} bad input; field "description" also for spam text
//   413 {error: "too_large"}       body over 4 MB or a screenshot over 1.5 MB
//   429 {error: "rate_limited"}    with Retry-After
//   503 {error: "unavailable"}     the build's channel isn't accepted (settings)
//   500 {error: "server"}
//
// The channel comes from DV_INTERNAL_BUILDS (server config), never the body. The
// install ID and network prefix reach the database only as HMACs (DV_HMAC_SECRET).
// Screenshots go to the existing private `attachments` bucket under
// daily-verse/reports/<id>/<n>.jpg: uploaded first, then recorded with
// attach_screenshot (the upload is removed if that fails).
//
// Deploy (only with approval): supabase functions deploy dv-report
//   JWT verification stays ON: the app sends the anon key.
import {
  alertEmail, channelFor, clientIP, hmacHex, MAX_BODY_BYTES, networkPrefix, parseReport,
  reportErrorToHttp, screenshotPath, type DbError, type ReportInput,
} from "../_shared/dailyVerse.ts";
import { asService, inBackground, sendDailyVerseEmail, storage } from "../_shared/dailyVerseIO.ts";

function json(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...extra },
  });
}

/**
 * Reads at most `limit` bytes; null if the body is larger. An oversized body is
 * still read (and discarded) up to DRAIN_BYTES, so the client gets a clean 413
 * instead of a reset connection; beyond that the stream is cancelled.
 */
const DRAIN_BYTES = 8 * 1024 * 1024;
async function readLimited(req: Request, limit: number): Promise<Uint8Array | null> {
  if (!req.body) return new Uint8Array();
  const declared = Number(req.headers.get("content-length") ?? "0");
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  let tooLarge = declared > limit;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > limit) tooLarge = true;
    if (tooLarge) {
      if (size > DRAIN_BYTES) {
        await reader.cancel();
        break;
      }
      continue;
    }
    chunks.push(value);
  }
  if (tooLarge) return null;
  const all = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    all.set(chunk, offset);
    offset += chunk.length;
  }
  return all;
}

async function notify(id: string, report: ReportInput, screenshots: number): Promise<void> {
  if (!Deno.env.get("RESEND_API_KEY") || !Deno.env.get("DV_ALERT_EMAIL")) return;
  // At most 12 alert emails an hour, whatever the report volume.
  const wait = await asService(async (tx) => (await tx`select daily_verse.take_token('alert:email', 12, 12) as wait`)[0].wait);
  if (Number(wait) > 0) return;
  const { subject, html } = alertEmail({
    id, category: report.category, puzzleType: report.puzzleType, contentLanguage: report.contentLanguage,
    contentId: report.contentId, challengeDate: report.challengeDate, reviewState: report.reviewState,
    appVersion: report.appVersion, build: report.build, description: report.description, screenshots,
  }, Deno.env.get("DV_ADMIN_URL"));
  await sendDailyVerseEmail(subject, html);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "invalid" }, 405);

  const raw = await readLimited(req, MAX_BODY_BYTES);
  if (raw === null) return json({ error: "too_large" }, 413);
  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return json({ error: "invalid", field: "body" }, 400);
  }
  const parsed = parseReport(body);
  if (!parsed.ok) return parsed.tooLarge ? json({ error: "too_large" }, 413) : json({ error: "invalid", field: parsed.field }, 400);
  const report = parsed.value;

  const pepper = Deno.env.get("DV_HMAC_SECRET") ?? "";
  if (pepper.length < 32) {
    console.error("dv-report: DV_HMAC_SECRET is not set");
    return json({ error: "server" }, 500);
  }

  let id: string;
  let fresh: boolean;
  try {
    const channel = channelFor(report.build, Deno.env.get("DV_INTERNAL_BUILDS"));
    const installHash = await hmacHex(pepper, "install:" + report.installID);
    const netHash = await hmacHex(pepper, "net:" + networkPrefix(clientIP(req.headers)));
    ({ id, fresh } = await asService(async (tx) => {
      const [{ id }] = await tx`select daily_verse.submit_report(
        ${channel}, ${report.appVersion}, ${report.build}, ${report.osVersion}, ${report.deviceFamily},
        ${report.contentLanguage}, ${report.puzzleType}, ${report.contentId}, ${report.challengeDate},
        ${report.reviewState}, ${report.category}, ${report.description}, ${installHash}, ${netHash}
      ) as id`;
      // A new row was created in this transaction (created_at = now()); otherwise it's a duplicate.
      const [{ fresh }] = await tx`select created_at = now() as fresh from daily_verse.reports where id = ${id}`;
      return { id: id as string, fresh: fresh as boolean };
    }));
  } catch (error) {
    const mapped = reportErrorToHttp(error as DbError);
    if (mapped.status === 500) console.error("dv-report: submit failed", (error as DbError)?.code, (error as DbError)?.message);
    return json(mapped.body, mapped.status, mapped.retryAfter ? { "Retry-After": String(mapped.retryAfter) } : {});
  }

  if (!fresh) return json({ id, duplicate: true }, 200);

  // Storage first, then the database (contract rule 5).
  let attached = 0;
  for (const [i, bytes] of report.screenshots.entries()) {
    const path = screenshotPath(id, i + 1);
    const { error: uploadError } = await storage.upload(path, bytes, { contentType: "image/jpeg", upsert: false });
    if (uploadError) {
      console.error("dv-report: screenshot upload failed", uploadError.message);
      break;
    }
    try {
      await asService((tx) => tx`select daily_verse.attach_screenshot(${id}, ${i + 1}, ${bytes.length})`);
      attached++;
    } catch (error) {
      console.error("dv-report: attach failed; removing the upload", (error as DbError)?.message);
      await storage.remove([path]);
      break;
    }
  }

  inBackground(notify(id, report, attached));
  return json({ id, screenshots: attached }, 201);
});
