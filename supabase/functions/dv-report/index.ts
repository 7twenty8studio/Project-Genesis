// dv-report: receives a Daily Verse Games problem report from the app.
//
// POST /functions/v1/dv-report with the project's PUBLISHABLE key in the `apikey`
// header only (no Authorization header), JSON body as in
// supabase/tests/daily_verse/PR_B_CONTRACT.md and the app's ReportSubmission
// (daily-verse PR #36):
//   201 {id, screenshots, submitted}           new report; screenshots = how many were
//                                              saved, submitted = how many were sent.
//                                              screenshots < submitted means the text
//                                              was saved but some pictures weren't, and
//                                              the app says so (it never re-sends).
//   200 {id, duplicate: true, screenshots}     the same report within 10 minutes (kept
//                                              once); screenshots = what the first one saved
//   401 {error: "unauthorized"}    no apikey, or not one of the project's publishable keys
//   401 {error: "attestation_required"} no App Attest headers, or an unknown key (the app
//                                  registers its key with dv-attest, then retries)
//   401 {error: "challenge_expired"} the challenge is missing, forged or over 5 minutes old
//   403 {error: "attestation_invalid"} the assertion doesn't verify or was replayed
//   400 {error: "invalid", field?} bad input; field "description" also for spam text
//   413 {error: "too_large"}       body over 4 MB or a screenshot over 1.5 MB
//   429 {error: "rate_limited"}    with Retry-After
//   503 {error: "unavailable"}     the build's channel isn't accepted (settings)
//   500 {error: "server"}
//
// App Attest (PR_B_CONTRACT.md rule 2, required for every channel once public reports
// open): headers x-dv-attest-key (the App Attest key ID), x-dv-attest-challenge (from
// dv-attest) and x-dv-assertion (base64), an assertion over
// SHA-256(challenge + "\n" + the exact body bytes). Checked before anything is stored.
//
// The channel comes from DV_INTERNAL_BUILDS (server config: a function secret or
// the Vault entry dv_internal_builds), never the body. The
// install ID and network prefix reach the database only as HMACs (DV_HMAC_SECRET).
// Screenshots go to the existing private `attachments` bucket under
// daily-verse/reports/<id>/<n>.jpg: uploaded first, then recorded with
// attach_screenshot (the upload is removed if that fails).
//
// Deploy (only with approval): supabase functions deploy dv-report --no-verify-jwt
//   The platform's verify_jwt check only understands JWTs, and publishable keys
//   aren't JWTs (Supabase: "Migrating to publishable and secret API keys"), so
//   this function checks the apikey itself, first, against SUPABASE_PUBLISHABLE_KEYS
//   (acceptedReportKeys). Fails closed: with no keys configured nothing is accepted.
import {
  acceptedReportKeys, alertEmail, channelFor, clientIP, hmacHex, isAcceptedReportKey, MAX_BODY_BYTES, networkPrefix, parseReport,
  reportErrorToHttp, screenshotPath, type DbError, type ReportInput,
} from "../_shared/dailyVerse.ts";
import { asService, inBackground, sendDailyVerseEmail, setting, storage } from "../_shared/dailyVerseIO.ts";
import { checkChallenge, fromBase64, reportClientDataHash, verifyAssertion } from "../_shared/appAttest.ts";

type AttestCheck = { ok: true } | { ok: false; status: number; error: string };

/** Checks the report's App Attest assertion against the stored key and moves its counter on. */
async function checkAttestation(headers: Headers, body: Uint8Array, pepper: string): Promise<AttestCheck> {
  const keyId = headers.get("x-dv-attest-key") ?? "";
  const challenge = headers.get("x-dv-attest-challenge") ?? "";
  const assertion = fromBase64(headers.get("x-dv-assertion"), 4096);
  if (!/^[A-Za-z0-9+/]{43}=$/.test(keyId) || !challenge || !assertion) {
    return { ok: false, status: 401, error: "attestation_required" };
  }
  if (!(await checkChallenge(pepper, challenge))) return { ok: false, status: 401, error: "challenge_expired" };
  const keyHash = await hmacHex(pepper, "attest:" + keyId);
  const rows = await asService((tx) =>
    tx`select public_key, sign_count from daily_verse.attest_keys where key_hash = ${keyHash}`);
  if (rows.length === 0) return { ok: false, status: 401, error: "attestation_required" };
  const publicKey = new Uint8Array(rows[0].public_key as Uint8Array);
  const result = await verifyAssertion(assertion, await reportClientDataHash(challenge, body), publicKey, Number(rows[0].sign_count));
  if (!result.ok) {
    console.warn("dv-report: assertion refused", result.reason);
    return { ok: false, status: 403, error: "attestation_invalid" };
  }
  const [{ used }] = await asService((tx) => tx`select daily_verse.use_attest_key(${keyHash}, ${result.counter}) as used`);
  return used ? { ok: true } : { ok: false, status: 403, error: "attestation_invalid" };
}

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
  if (!Deno.env.get("RESEND_API_KEY") || !(await setting("DV_ALERT_EMAIL"))) return;
  // At most 12 alert emails an hour, whatever the report volume.
  const wait = await asService(async (tx) => (await tx`select daily_verse.take_token('alert:email', 12, 12) as wait`)[0].wait);
  if (Number(wait) > 0) return;
  const { subject, html } = alertEmail({
    id, category: report.category, puzzleType: report.puzzleType, contentLanguage: report.contentLanguage,
    contentId: report.contentId, challengeDate: report.challengeDate, reviewState: report.reviewState,
    appVersion: report.appVersion, build: report.build, description: report.description, screenshots,
  }, await setting("DV_ADMIN_URL"));
  await sendDailyVerseEmail(subject, html);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "invalid" }, 405);

  const accepted = acceptedReportKeys(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"), Deno.env.get("DV_REPORT_KEYS"));
  if (accepted.length === 0) console.error("dv-report: no publishable key configured; refusing every request");
  if (!isAcceptedReportKey(req.headers.get("apikey"), accepted)) return json({ error: "unauthorized" }, 401);

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

  const pepper = (await setting("DV_HMAC_SECRET").catch(() => undefined)) ?? "";
  if (pepper.length < 32) {
    console.error("dv-report: DV_HMAC_SECRET is not set");
    return json({ error: "server" }, 500);
  }

  try {
    const attest = await checkAttestation(req.headers, raw, pepper);
    if (!attest.ok) return json({ error: attest.error }, attest.status);
  } catch (error) {
    console.error("dv-report: attestation check failed", (error as DbError)?.code ?? "unknown");
    return json({ error: "server" }, 500);
  }

  let id: string;
  let fresh: boolean;
  let saved: number;
  try {
    const channel = channelFor(report.build, await setting("DV_INTERNAL_BUILDS"));
    const installHash = await hmacHex(pepper, "install:" + report.installID);
    const netHash = await hmacHex(pepper, "net:" + networkPrefix(clientIP(req.headers)));
    ({ id, fresh, saved } = await asService(async (tx) => {
      const [{ id }] = await tx`select daily_verse.submit_report(
        ${channel}, ${report.appVersion}, ${report.build}, ${report.osVersion}, ${report.deviceFamily},
        ${report.contentLanguage}, ${report.puzzleType}, ${report.contentId}, ${report.challengeDate},
        ${report.reviewState}, ${report.category}, ${report.description}, ${installHash}, ${netHash}
      ) as id`;
      // A new row was created in this transaction (created_at = now()); otherwise it's a duplicate.
      const [{ fresh, saved }] = await tx`select created_at = now() as fresh, cardinality(screenshot_paths) as saved
        from daily_verse.reports where id = ${id}`;
      return { id: id as string, fresh: fresh as boolean, saved: Number(saved) };
    }));
  } catch (error) {
    const mapped = reportErrorToHttp(error as DbError);
    // The code only: a database message can quote the values (the description).
    if (mapped.status === 500) console.error("dv-report: submit failed", (error as DbError)?.code ?? "unknown");
    return json(mapped.body, mapped.status, mapped.retryAfter ? { "Retry-After": String(mapped.retryAfter) } : {});
  }

  if (!fresh) return json({ id, duplicate: true, screenshots: saved }, 200);

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
      console.error("dv-report: attach failed; removing the upload", (error as DbError)?.code ?? "unknown");
      await storage.remove([path]);
      break;
    }
  }

  inBackground(notify(id, report, attached));
  return json({ id, screenshots: attached, submitted: report.screenshots.length }, 201);
});
