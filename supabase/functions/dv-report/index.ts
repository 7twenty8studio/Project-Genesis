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
//   400 {error: "invalid", field?} bad input; field "description" also for spam text
//   413 {error: "too_large"}       body over 4 MB or a screenshot over 1.5 MB
//   429 {error: "rate_limited"}    with Retry-After
//   503 {error: "unavailable"}     the build's channel isn't accepted (settings)
//   500 {error: "server"}
//
// App Attest (Daily Verse 1.0; supabase/tests/daily_verse/APP_ATTEST.md):
//   {action: "challenge", purpose: "attest"|"report"}  → 200 {challenge, expiresIn}
//   {action: "attest", keyId, attestation, challenge}  → 200 {ok: true}   (key stored)
//   a report with headers x-dv-attest-key, x-dv-assertion, x-dv-challenge: the
//   assertion signs "<challenge>\n<exact body bytes>". Public builds must send
//   them; Internal builds may (older Internal builds don't). With `reportID`
//   in the body, a retry of the same report is kept once (200 duplicate).
//   401 {error: "attestation", reason: challenge|key|required|invalid}
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
  acceptedReportKeys, actionOf, alertEmail, assertionHeaders, attestFailure, channelFor, clientIP, hmacHex, isAcceptedReportKey,
  MAX_BODY_BYTES, networkPrefix, parseAttestRequest, parseReport, reportErrorToHttp, screenshotPath, type DbError, type HttpError,
  type ReportInput,
} from "../_shared/dailyVerse.ts";
import {
  AttestError, DAILY_VERSE_APP_ID, fromBase64, reportClientData, sha256, toBase64, verifyAssertion, verifyAttestation,
} from "../_shared/appAttest.ts";
import { asService, inBackground, sendDailyVerseEmail, setting, storage } from "../_shared/dailyVerseIO.ts";

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

function fail(e: HttpError): Response {
  return json(e.body, e.status, e.retryAfter ? { "Retry-After": String(e.retryAfter) } : {});
}

function dbFailure(where: string, error: unknown): Response {
  const mapped = reportErrorToHttp(error as DbError);
  // The code only: a database message can quote the values (the description).
  if (mapped.status === 500) console.error(`dv-report: ${where} failed`, (error as DbError)?.code ?? "unknown");
  return fail(mapped);
}

const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
const challengeHash = async (challenge: string) => hex(await sha256(new TextEncoder().encode(challenge)));

/** Normalised key id (standard base64 of its 32 bytes), or null. */
function keyIdBytes(keyId: string): Uint8Array | null {
  const bytes = fromBase64(keyId, 64);
  return bytes && bytes.length === 32 ? bytes : null;
}

async function issueChallenge(body: Record<string, unknown>, netHash: string): Promise<Response> {
  const purpose = body.purpose === "attest" ? "attest" : body.purpose === "report" ? "report" : null;
  if (!purpose) return json({ error: "invalid", field: "purpose" }, 400);
  const challenge = toBase64(crypto.getRandomValues(new Uint8Array(32))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const hash = await challengeHash(challenge);
  try {
    await asService((tx) => tx`select daily_verse.issue_challenge(${hash}, ${purpose}, ${netHash})`);
  } catch (error) {
    return dbFailure("challenge", error);
  }
  return json({ challenge, expiresIn: 300 }, 200);
}

async function registerKey(body: unknown, pepper: string, netHash: string): Promise<Response> {
  const parsed = parseAttestRequest(body);
  if (!parsed.ok) return json({ error: "invalid", field: parsed.field }, 400);
  const { keyId, attestation, challenge } = parsed.value;
  const keyBytes = keyIdBytes(keyId);
  const attestationBytes = fromBase64(attestation, 12_288);
  if (!keyBytes) return json({ error: "invalid", field: "keyId" }, 400);
  if (!attestationBytes) return json({ error: "invalid", field: "attestation" }, 400);
  const allowDevelopment = (await setting("DV_ATTEST_ALLOW_DEVELOPMENT")) === "true";
  try {
    const hash = await challengeHash(challenge);
    const fresh = await asService(async (tx) => (await tx`select daily_verse.consume_challenge(${hash}, 'attest') as ok`)[0].ok as boolean);
    if (!fresh) return fail(attestFailure("challenge"));
    let result;
    try {
      result = await verifyAttestation({
        attestation: attestationBytes, clientData: new TextEncoder().encode(challenge), keyId: keyBytes,
        appId: DAILY_VERSE_APP_ID, allowDevelopment,
      });
    } catch (error) {
      if (error instanceof AttestError) {
        console.warn("dv-report: attestation refused:", error.message);
        return fail(attestFailure("invalid"));
      }
      throw error;
    }
    const keyHash = await hmacHex(pepper, "attestkey:" + toBase64(keyBytes));
    await asService((tx) => tx`select daily_verse.register_attest_key(${keyHash}, ${result.publicKey}, ${result.environment}, ${netHash})`);
    return json({ ok: true }, 200);
  } catch (error) {
    return dbFailure("attest", error);
  }
}

/**
 * Checks a report's assertion. Returns the key's HMAC (for its rate limit), or
 * a Response to send instead. Uses up the challenge and moves the key's
 * counter, so the same signed request can't be accepted twice.
 */
async function checkAssertion(req: Request, raw: Uint8Array, pepper: string, channel: string): Promise<string | null | Response> {
  const headers = assertionHeaders(req.headers);
  if (headers === null) return channel === "public" ? fail(attestFailure("required")) : null;
  if (headers === "invalid") return fail(attestFailure("invalid"));
  const keyBytes = keyIdBytes(headers.keyId);
  const assertion = fromBase64(headers.assertion, 1024);
  if (!keyBytes || !assertion) return fail(attestFailure("invalid"));
  const keyHash = await hmacHex(pepper, "attestkey:" + toBase64(keyBytes));
  const hash = await challengeHash(headers.challenge);
  const fresh = await asService(async (tx) => (await tx`select daily_verse.consume_challenge(${hash}, 'report') as ok`)[0].ok as boolean);
  if (!fresh) return fail(attestFailure("challenge"));
  const [key] = await asService((tx) => tx`select public_key, environment, sign_count from daily_verse.get_attest_key(${keyHash})`);
  if (!key) return fail(attestFailure("key"));
  if (channel === "public" && key.environment !== "production") return fail(attestFailure("key"));
  let counter: number;
  try {
    ({ counter } = await verifyAssertion({
      assertion, clientData: reportClientData(headers.challenge, raw), publicKey: new Uint8Array(key.public_key),
      appId: DAILY_VERSE_APP_ID, previousCounter: Number(key.sign_count),
    }));
  } catch (error) {
    if (error instanceof AttestError) {
      console.warn("dv-report: assertion refused:", error.message);
      return fail(attestFailure("invalid"));
    }
    throw error;
  }
  const advanced = await asService(async (tx) => (await tx`select daily_verse.advance_attest_key(${keyHash}, ${counter}) as ok`)[0].ok as boolean);
  if (!advanced) return fail(attestFailure("invalid"));
  return keyHash;
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
  const action = actionOf(body);
  if (!action) return json({ error: "invalid", field: "action" }, 400);

  const pepper = (await setting("DV_HMAC_SECRET").catch(() => undefined)) ?? "";
  if (pepper.length < 32) {
    console.error("dv-report: DV_HMAC_SECRET is not set");
    return json({ error: "server" }, 500);
  }
  const netHash = await hmacHex(pepper, "net:" + networkPrefix(clientIP(req.headers)));
  if (action === "challenge") return issueChallenge(body as Record<string, unknown>, netHash);
  if (action === "attest") return registerKey(body, pepper, netHash);

  const parsed = parseReport(body);
  if (!parsed.ok) return parsed.tooLarge ? json({ error: "too_large" }, 413) : json({ error: "invalid", field: parsed.field }, 400);
  const report = parsed.value;

  let id: string;
  let fresh: boolean;
  let saved: number;
  try {
    const channel = channelFor(report.build, await setting("DV_INTERNAL_BUILDS"));
    const checked = await checkAssertion(req, raw, pepper, channel);
    if (checked instanceof Response) return checked;
    if (checked && !report.reportID) return json({ error: "invalid", field: "reportID" }, 400);
    const keyHash = checked;
    const installHash = await hmacHex(pepper, "install:" + report.installID);
    ({ id, fresh, saved } = await asService(async (tx) => {
      const [{ id }] = report.reportID
        ? await tx`select daily_verse.submit_report_once(
            ${report.reportID}, ${keyHash}, ${channel}, ${report.appVersion}, ${report.build}, ${report.osVersion},
            ${report.deviceFamily}, ${report.contentLanguage}, ${report.puzzleType}, ${report.contentId}, ${report.challengeDate},
            ${report.reviewState}, ${report.category}, ${report.description}, ${installHash}, ${netHash}
          ) as id`
        : await tx`select daily_verse.submit_report(
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
    return dbFailure("submit", error);
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
