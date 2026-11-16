// Apple App Attest checks for Daily Verse Games reports (PR_B_CONTRACT.md rule 2).
//
// Flow (see dv-attest and dv-report):
//   1. The app asks dv-attest for a challenge (stateless, HMAC-signed, valid 5 minutes).
//   2. Once per install it creates an App Attest key and sends Apple's attestation for
//      SHA-256(challenge). verifyAttestation checks the certificate chain up to Apple's
//      App Attestation Root CA, the nonce, the app ID, the counter (0), the environment and
//      that the key ID matches the certified public key. The public key is then stored.
//   3. Each report carries an assertion over SHA-256(challenge + "\n" + exact body bytes).
//      verifyAssertion checks the signature with the stored key, the app ID and that the
//      counter moved forward (the database refuses a counter that didn't: no replays).
//
// Pure functions (no I/O) so they can be unit-tested with a stand-in root certificate.
import { decode as cborDecode } from "npm:cbor-x@1.6.0";
import * as x509 from "npm:@peculiar/x509@1.12.3";

x509.cryptoProvider.set(crypto);

/** Apple App Attestation Root CA (https://www.apple.com/certificateauthority/), valid to 2045.
 *  SHA-256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32 */
export const APPLE_APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

/** Team ID + bundle ID of Daily Verse Games. */
export const DAILY_VERSE_APP_ID = "4XTR53RY2V.com.7twenty8studio.dailyverse";

const NONCE_OID = "1.2.840.113635.100.8.2";
const enc = new TextEncoder();
const AAGUID_PRODUCTION = concat(enc.encode("appattest"), new Uint8Array(7));
const AAGUID_DEVELOPMENT = enc.encode("appattestdevelop");

export type AttestEnvironment = "production" | "development";
export type AttestResult =
  | { ok: true; publicKey: Uint8Array; environment: AttestEnvironment }
  | { ok: false; reason: string };
export type AssertResult = { ok: true; counter: number } | { ok: false; reason: string };

export interface AttestOptions {
  appId?: string;
  /** PEM roots to trust. Production code uses Apple's only; tests pass a stand-in. */
  roots?: string[];
  allowDevelopment?: boolean;
  now?: Date;
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

/** A standalone ArrayBuffer copy (WebCrypto and x509 typings want ArrayBuffer, not ArrayBufferLike). */
function buf(data: Uint8Array): ArrayBuffer {
  return data.slice().buffer as ArrayBuffer;
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", buf(data)));
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function fromBase64(value: unknown, maxBytes: number): Uint8Array | null {
  if (typeof value !== "string" || value.length === 0 || value.length > Math.ceil(maxBytes / 3) * 4 + 4) return null;
  try {
    const bin = atob(value.replace(/-/g, "+").replace(/_/g, "/"));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.length > 0 && out.length <= maxBytes ? out : null;
  } catch {
    return null;
  }
}

function u32(bytes: Uint8Array, at: number): number {
  return ((bytes[at] << 24) >>> 0) + (bytes[at + 1] << 16) + (bytes[at + 2] << 8) + bytes[at + 3];
}

/** ECDSA DER signature → the raw r||s form WebCrypto expects (P-256: 64 bytes). */
export function derToRaw(der: Uint8Array, size = 32): Uint8Array | null {
  let i = 0;
  if (der[i++] !== 0x30) return null;
  let len = der[i++];
  if (len & 0x80) i += len & 0x7f;
  const out = new Uint8Array(size * 2);
  for (let part = 0; part < 2; part++) {
    if (der[i++] !== 0x02) return null;
    len = der[i++];
    let v = der.subarray(i, i + len);
    i += len;
    while (v.length > size && v[0] === 0) v = v.subarray(1);
    if (v.length > size) return null;
    out.set(v, part * size + (size - v.length));
  }
  return out;
}

function cbor(bytes: Uint8Array): Record<string, unknown> | null {
  try {
    const value = cborDecode(bytes);
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function asBytes(value: unknown): Uint8Array | null {
  return value instanceof Uint8Array ? value : null;
}

/**
 * Verifies an App Attest attestation object for `keyId` (base64, as the app received it from
 * DCAppAttestService.generateKey) over `clientDataHash`.
 */
export async function verifyAttestation(
  keyId: string, attestation: Uint8Array, clientDataHash: Uint8Array, options: AttestOptions = {},
): Promise<AttestResult> {
  const fail = (reason: string): AttestResult => ({ ok: false, reason });
  const keyIdBytes = fromBase64(keyId, 32);
  if (!keyIdBytes || keyIdBytes.length !== 32) return fail("key_id");
  const obj = cbor(attestation);
  if (!obj || obj.fmt !== "apple-appattest") return fail("format");
  const stmt = obj.attStmt as Record<string, unknown> | undefined;
  const authData = asBytes(obj.authData);
  const x5c = Array.isArray(stmt?.x5c) ? (stmt!.x5c as unknown[]).map(asBytes) : [];
  if (!authData || x5c.length !== 2 || x5c.some((c) => !c)) return fail("format");

  // 1. Certificate chain: leaf ← intermediate ← trusted root (never one from the request).
  const now = options.now ?? new Date();
  let leaf: x509.X509Certificate, intermediate: x509.X509Certificate;
  try {
    leaf = new x509.X509Certificate(buf(x5c[0]!));
    intermediate = new x509.X509Certificate(buf(x5c[1]!));
  } catch {
    return fail("certificate");
  }
  const roots = (options.roots ?? [APPLE_APP_ATTEST_ROOT_PEM]).map((pem) => new x509.X509Certificate(pem));
  let chained = false;
  for (const root of roots) {
    if (await intermediate.verify({ publicKey: root.publicKey, date: now }).catch(() => false)
        && root.notBefore <= now && now <= root.notAfter) {
      chained = true;
      break;
    }
  }
  if (!chained) return fail("chain");
  if (!(await leaf.verify({ publicKey: intermediate.publicKey, date: now }).catch(() => false))) return fail("chain");

  // 2. Nonce: SHA-256(authData || clientDataHash), in the leaf's 1.2.840.113635.100.8.2 extension.
  const nonce = await sha256(concat(authData, clientDataHash));
  const ext = leaf.getExtension(NONCE_OID);
  if (!ext) return fail("nonce");
  const extValue = new Uint8Array(ext.value);
  const expected = concat(new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce);
  if (!equal(extValue, expected)) return fail("nonce");

  // 3. The key ID is SHA-256 of the certified public key (uncompressed point).
  let publicKey: Uint8Array;
  try {
    const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" } as EcKeyImportParams, ["verify"]);
    publicKey = new Uint8Array(await crypto.subtle.exportKey("raw", key));
  } catch {
    return fail("public_key");
  }
  if (publicKey.length !== 65 || !equal(await sha256(publicKey), keyIdBytes)) return fail("key_id");

  // 4. Authenticator data: app ID hash, counter 0, environment, credential ID = key ID.
  if (authData.length < 55) return fail("auth_data");
  const appId = options.appId ?? DAILY_VERSE_APP_ID;
  if (!equal(authData.subarray(0, 32), await sha256(enc.encode(appId)))) return fail("app_id");
  if (u32(authData, 33) !== 0) return fail("counter");
  const aaguid = authData.subarray(37, 53);
  let environment: AttestEnvironment;
  if (equal(aaguid, AAGUID_PRODUCTION)) environment = "production";
  else if (equal(aaguid, AAGUID_DEVELOPMENT) && options.allowDevelopment) environment = "development";
  else return fail("environment");
  const credLen = (authData[53] << 8) + authData[54];
  if (credLen !== 32 || authData.length < 55 + credLen || !equal(authData.subarray(55, 55 + credLen), keyIdBytes)) {
    return fail("credential");
  }
  return { ok: true, publicKey, environment };
}

/**
 * Verifies an App Attest assertion over `clientDataHash` with a stored public key.
 * `storedCounter` is the last counter seen; the new one must be larger (the database
 * re-checks this atomically in use_attest_key).
 */
export async function verifyAssertion(
  assertion: Uint8Array, clientDataHash: Uint8Array, publicKey: Uint8Array, storedCounter: number,
  options: { appId?: string } = {},
): Promise<AssertResult> {
  const fail = (reason: string): AssertResult => ({ ok: false, reason });
  const obj = cbor(assertion);
  const signature = asBytes(obj?.signature);
  const authData = asBytes(obj?.authenticatorData);
  if (!signature || !authData || authData.length < 37) return fail("format");
  if (!equal(authData.subarray(0, 32), await sha256(enc.encode(options.appId ?? DAILY_VERSE_APP_ID)))) return fail("app_id");
  const counter = u32(authData, 33);
  if (counter <= storedCounter) return fail("counter");
  const raw = derToRaw(signature);
  if (!raw) return fail("signature");
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey("raw", buf(publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  } catch {
    return fail("public_key");
  }
  // The device signs nonce = SHA-256(authenticatorData || clientDataHash) with ECDSA/SHA-256.
  const nonce = await sha256(concat(authData, clientDataHash));
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, buf(raw), buf(nonce));
  return ok ? { ok: true, counter } : fail("signature");
}

/** clientDataHash for a report: SHA-256(challenge + "\n" + exact request body bytes). */
export async function reportClientDataHash(challenge: string, body: Uint8Array): Promise<Uint8Array> {
  return sha256(concat(enc.encode(challenge + "\n"), body));
}

/** clientDataHash for registering a key: SHA-256(challenge). */
export async function attestClientDataHash(challenge: string): Promise<Uint8Array> {
  return sha256(enc.encode(challenge));
}

// Challenges --------------------------------------------------------------------------
// Stateless: "<unix seconds>.<32 hex random>.<HMAC>", HMAC-SHA-256 with the server pepper.
// Valid for CHALLENGE_SECONDS. Replays are stopped by the key counter, not by the challenge.
export const CHALLENGE_SECONDS = 300;
const CHALLENGE = /^(\d{10})\.([0-9a-f]{32})\.([0-9a-f]{64})$/;

async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(message)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

export async function makeChallenge(secret: string, now = Date.now()): Promise<string> {
  const ts = Math.floor(now / 1000).toString();
  const rand = Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) => b.toString(16).padStart(2, "0")).join("");
  return `${ts}.${rand}.${await hmac(secret, "dv-challenge:" + ts + "." + rand)}`;
}

export async function checkChallenge(secret: string, challenge: unknown, now = Date.now()): Promise<boolean> {
  if (typeof challenge !== "string") return false;
  const m = CHALLENGE.exec(challenge);
  if (!m) return false;
  const age = Math.floor(now / 1000) - Number(m[1]);
  if (age < -30 || age > CHALLENGE_SECONDS) return false;
  return equal(enc.encode(m[3]), enc.encode(await hmac(secret, "dv-challenge:" + m[1] + "." + m[2])));
}
