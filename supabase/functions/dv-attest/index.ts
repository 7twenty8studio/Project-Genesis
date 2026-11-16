// dv-attest: App Attest setup for Daily Verse Games reports (PR_B_CONTRACT.md rule 2).
//
// POST /functions/v1/dv-attest with the project's PUBLISHABLE key in `apikey` (as dv-report).
//   {"action": "challenge"}
//     200 {challenge}                 a signed, 5-minute challenge (nothing is stored)
//   {"action": "register", "keyId": <base64>, "attestation": <base64>, "challenge": <string>}
//     201 {ok: true}                  Apple's attestation for SHA-256(challenge) is valid; the
//                                     key is stored (again: no-op) for dv-report assertions
//     400 {error: "invalid", field}   malformed input
//     401 {error: "challenge_expired"} challenge missing, forged or older than 5 minutes
//     403 {error: "attestation_invalid"} the attestation doesn't verify
//     429 {error: "rate_limited"}     with Retry-After
//   401 {error: "unauthorized"} without an accepted publishable key; 500 {error: "server"}.
//
// Stored: HMAC(DV_HMAC_SECRET, "attest:" + keyId), the public key, the counter and timestamps
// (daily_verse.attest_keys). The network prefix is used only as an HMAC'd rate-limit key.
// Deploy (only with approval): supabase functions deploy dv-attest --no-verify-jwt
import { acceptedReportKeys, clientIP, hmacHex, isAcceptedReportKey, networkPrefix } from "../_shared/dailyVerse.ts";
import { attestClientDataHash, checkChallenge, fromBase64, makeChallenge, verifyAttestation } from "../_shared/appAttest.ts";
import { asService, setting } from "../_shared/dailyVerseIO.ts";

const MAX_BODY = 64 * 1024;

function json(body: unknown, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...extra },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "invalid" }, 405);
  const accepted = acceptedReportKeys(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"), Deno.env.get("DV_REPORT_KEYS"));
  if (!isAcceptedReportKey(req.headers.get("apikey"), accepted)) return json({ error: "unauthorized" }, 401);

  const text = await req.text();
  if (text.length > MAX_BODY) return json({ error: "too_large" }, 413);
  let body: Record<string, unknown>;
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    body = parsed;
  } catch {
    return json({ error: "invalid", field: "body" }, 400);
  }

  const pepper = (await setting("DV_HMAC_SECRET").catch(() => undefined)) ?? "";
  if (pepper.length < 32) {
    console.error("dv-attest: DV_HMAC_SECRET is not set");
    return json({ error: "server" }, 500);
  }

  if (body.action === "challenge") return json({ challenge: await makeChallenge(pepper) }, 200);
  if (body.action !== "register") return json({ error: "invalid", field: "action" }, 400);

  const keyId = typeof body.keyId === "string" ? body.keyId : "";
  if (!/^[A-Za-z0-9+/]{43}=$/.test(keyId)) return json({ error: "invalid", field: "keyId" }, 400);
  const attestation = fromBase64(body.attestation, 16 * 1024);
  if (!attestation) return json({ error: "invalid", field: "attestation" }, 400);
  if (!(await checkChallenge(pepper, body.challenge))) return json({ error: "challenge_expired" }, 401);

  try {
    // Verifying an attestation costs more than a report: at most 10 an hour per network.
    const netHash = await hmacHex(pepper, "net:" + networkPrefix(clientIP(req.headers)));
    const wait = Number(await asService(async (tx) =>
      (await tx`select daily_verse.take_token(${"attest:" + netHash}, 10, 10) as wait`)[0].wait));
    if (wait > 0) return json({ error: "rate_limited" }, 429, { "Retry-After": String(Math.ceil(wait)) });

    const result = await verifyAttestation(keyId, attestation, await attestClientDataHash(body.challenge as string));
    if (!result.ok) {
      console.warn("dv-attest: attestation refused", result.reason);
      return json({ error: "attestation_invalid" }, 403);
    }
    const keyHash = await hmacHex(pepper, "attest:" + keyId);
    await asService((tx) => tx`select daily_verse.register_attest_key(${keyHash}, ${result.publicKey}, ${result.environment})`);
    return json({ ok: true }, 201);
  } catch (error) {
    console.error("dv-attest: failed", (error as { code?: string })?.code ?? "unknown");
    return json({ error: "server" }, 500);
  }
});
