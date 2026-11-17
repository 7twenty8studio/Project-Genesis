// Daily Verse Games: server-side App Attest verification for dv-report.
//
// Pure code over WebCrypto (no Deno, Supabase or npm imports), so Node can test
// it with real Apple attestations (appAttest.test.ts). It implements Apple's
// "Validating apps that connect to your server":
//   attestation  — once per app install key: proves the key lives in the Secure
//                  Enclave of a genuine Apple device, inside OUR app (App ID).
//   assertion    — on every report: proves the request was signed by that key,
//                  over this exact request body and a fresh server challenge.
// The certificate chain is checked against the pinned Apple App Attestation
// Root CA below; nothing in the request decides which root is trusted.

/** Apple App Attestation Root CA (P-384, valid 2020-03-18 to 2045-03-15).
 *  SHA-256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32
 *  (https://www.apple.com/certificateauthority/private/). The test checks the fingerprint. */
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

/** Daily Verse Games' App ID: <Team ID>.<bundle ID>. Both the ad-free and the ad target use this bundle ID. */
export const DAILY_VERSE_APP_ID = "4XTR53RY2V.com.7twenty8studio.dailyverse";

export type AttestEnvironment = "production" | "development";
export class AttestError extends Error {}

const enc = new TextEncoder();
const AAGUID_DEVELOP = enc.encode("appattestdevelop");
const AAGUID_PRODUCTION = Uint8Array.from([...enc.encode("appattest"), 0, 0, 0, 0, 0, 0, 0]);
const NONCE_OID = "1.2.840.113635.100.8.2";

// ---------------------------------------------------------------- small helpers
/** WebCrypto wants ArrayBuffer-backed views; every array here is one (never shared memory). */
const buf = (b: Uint8Array): BufferSource => b as unknown as BufferSource;
function fail(reason: string): never {
  throw new AttestError(reason);
}

export function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", buf(bytes)));
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

/** Standard or URL-safe base64, strictly; null if it isn't. */
export function fromBase64(text: unknown, maxBytes = 16_384): Uint8Array | null {
  if (typeof text !== "string" || text.length === 0 || text.length > Math.ceil(maxBytes / 3) * 4 + 4) return null;
  const clean = text.replace(/-/g, "+").replace(/_/g, "/");
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(clean) || clean.length % 4 === 1) return null;
  try {
    const binary = atob(clean.padEnd(Math.ceil(clean.length / 4) * 4, "="));
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

function pemToDer(pem: string): Uint8Array {
  return fromBase64(pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, ""), 65_536) ?? fail("bad pem");
}

// ---------------------------------------------------------------- CBOR (decode only)
// Enough for App Attest objects: unsigned/negative ints, byte and text strings,
// arrays and maps, definite lengths only. Anything else is refused.
type Cbor = number | string | Uint8Array | Cbor[] | Map<Cbor, Cbor> | boolean | null;

export function decodeCbor(bytes: Uint8Array): Cbor {
  let pos = 0;
  let depth = 0;
  const need = (n: number) => {
    if (pos + n > bytes.length) fail("cbor: truncated");
  };
  const length = (info: number): number => {
    if (info < 24) return info;
    const size = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : 0;
    if (!size) fail("cbor: unsupported length");
    need(size);
    let n = 0;
    for (let i = 0; i < size; i++) n = n * 256 + bytes[pos++];
    return n;
  };
  const item = (): Cbor => {
    if (++depth > 16) fail("cbor: too deep");
    need(1);
    const head = bytes[pos++];
    const major = head >> 5;
    const info = head & 0x1f;
    let value: Cbor;
    switch (major) {
      case 0: value = length(info); break;
      case 1: value = -1 - length(info); break;
      case 2: case 3: {
        const n = length(info);
        need(n);
        const slice = bytes.slice(pos, pos + n);
        pos += n;
        value = major === 2 ? slice : new TextDecoder("utf-8", { fatal: true }).decode(slice);
        break;
      }
      case 4: {
        const n = length(info);
        if (n > 64) fail("cbor: array too long");
        const list: Cbor[] = [];
        for (let i = 0; i < n; i++) list.push(item());
        value = list;
        break;
      }
      case 5: {
        const n = length(info);
        if (n > 64) fail("cbor: map too long");
        const map = new Map<Cbor, Cbor>();
        for (let i = 0; i < n; i++) {
          const k = item();
          map.set(k, item());
        }
        value = map;
        break;
      }
      case 7:
        if (info === 20) value = false;
        else if (info === 21) value = true;
        else if (info === 22) value = null;
        else fail("cbor: unsupported simple value");
        break;
      default:
        fail("cbor: unsupported type");
    }
    depth--;
    return value;
  };
  const result = item();
  if (pos !== bytes.length) fail("cbor: trailing bytes");
  return result;
}

function field(map: Cbor, key: string): Cbor | undefined {
  return map instanceof Map ? map.get(key) : undefined;
}
function bytesField(map: Cbor, key: string): Uint8Array {
  const v = field(map, key);
  return v instanceof Uint8Array ? v : fail(`missing ${key}`);
}

// ---------------------------------------------------------------- DER / X.509
interface Der { tag: number; start: number; contentStart: number; end: number; bytes: Uint8Array }

function readDer(bytes: Uint8Array, start: number, limit = bytes.length): Der {
  if (start + 2 > limit) fail("der: truncated");
  const tag = bytes[start];
  if ((tag & 0x1f) === 0x1f) fail("der: long tags unsupported");
  let pos = start + 1;
  let len = bytes[pos++];
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 3 || pos + n > limit) fail("der: bad length");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + bytes[pos++];
  }
  const end = pos + len;
  if (end > limit) fail("der: truncated");
  return { tag, start, contentStart: pos, end, bytes };
}

function children(node: Der): Der[] {
  const out: Der[] = [];
  let pos = node.contentStart;
  while (pos < node.end) {
    const child = readDer(node.bytes, pos, node.end);
    out.push(child);
    pos = child.end;
  }
  return out;
}

const whole = (n: Der) => n.bytes.slice(n.start, n.end);
const content = (n: Der) => n.bytes.slice(n.contentStart, n.end);

function oid(n: Der): string {
  if (n.tag !== 0x06) fail("der: expected OID");
  const b = content(n);
  const parts = [Math.floor(b[0] / 40), b[0] % 40];
  let value = 0;
  for (let i = 1; i < b.length; i++) {
    value = value * 128 + (b[i] & 0x7f);
    if (!(b[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function time(n: Der): number {
  const text = new TextDecoder().decode(content(n));
  const m = n.tag === 0x17
    ? /^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text)
    : n.tag === 0x18 ? /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(text) : null;
  if (!m) fail("der: bad time");
  let year = Number(m[1]);
  if (n.tag === 0x17) year += year < 50 ? 2000 : 1900;
  return Date.UTC(year, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
}

interface Certificate {
  tbs: Uint8Array;
  signatureAlg: string;
  signature: Uint8Array; // DER ECDSA-Sig-Value
  issuer: Uint8Array;
  subject: Uint8Array;
  notBefore: number;
  notAfter: number;
  spki: Uint8Array; // whole SubjectPublicKeyInfo
  curve: string;
  publicPoint: Uint8Array; // uncompressed EC point
  extensions: Map<string, Uint8Array>; // OID → extnValue contents
}

const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const SIG_HASH: Record<string, string> = { "1.2.840.10045.4.3.2": "SHA-256", "1.2.840.10045.4.3.3": "SHA-384" };

export function parseCertificate(der: Uint8Array): Certificate {
  const cert = readDer(der, 0);
  if (cert.tag !== 0x30 || cert.end !== der.length) fail("x509: bad certificate");
  const [tbsNode, algNode, sigNode] = children(cert);
  if (!tbsNode || !algNode || !sigNode || sigNode.tag !== 0x03) fail("x509: bad certificate");
  const tbs = children(tbsNode);
  let i = tbs[0]?.tag === 0xa0 ? 1 : 0; // [0] version
  i++; // serial
  i++; // signature algorithm (inner)
  const issuer = tbs[i++];
  const validity = children(tbs[i++]);
  const subject = tbs[i++];
  const spkiNode = tbs[i++];
  if (!issuer || !subject || !spkiNode || validity.length !== 2) fail("x509: bad tbs");
  const extensions = new Map<string, Uint8Array>();
  for (const node of tbs.slice(i)) {
    if (node.tag !== 0xa3) continue;
    for (const ext of children(children(node)[0])) {
      const parts = children(ext);
      const value = parts[parts.length - 1];
      if (value.tag !== 0x04) fail("x509: bad extension");
      extensions.set(oid(parts[0]), content(value));
    }
  }
  const [spkiAlg, spkiKey] = children(spkiNode);
  const [keyType, curveNode] = children(spkiAlg);
  if (oid(keyType) !== "1.2.840.10045.2.1" || !curveNode) fail("x509: not an EC key");
  const keyBits = content(spkiKey);
  const sigBits = content(sigNode);
  if (keyBits[0] !== 0 || sigBits[0] !== 0) fail("x509: bad bit string");
  return {
    tbs: whole(tbsNode),
    signatureAlg: oid(children(algNode)[0]),
    signature: sigBits.slice(1),
    issuer: whole(issuer),
    subject: whole(subject),
    notBefore: time(validity[0]),
    notAfter: time(validity[1]),
    spki: whole(spkiNode),
    curve: oid(curveNode),
    publicPoint: keyBits.slice(1),
    extensions,
  };
}

/** DER ECDSA-Sig-Value → raw r‖s (what WebCrypto verifies). */
export function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const seq = readDer(der, 0);
  if (seq.tag !== 0x30 || seq.end !== der.length) fail("bad signature");
  const parts = children(seq);
  if (parts.length !== 2 || parts.some((p) => p.tag !== 0x02)) fail("bad signature");
  const out = new Uint8Array(size * 2);
  parts.forEach((p, idx) => {
    let v = content(p);
    while (v.length > 1 && v[0] === 0) v = v.slice(1);
    if (v.length > size) fail("bad signature");
    out.set(v, idx * size + (size - v.length));
  });
  return out;
}

async function importEcKey(spki: Uint8Array, curveOid: string): Promise<{ key: CryptoKey; size: number }> {
  const curve = CURVES[curveOid] ?? fail("unsupported curve");
  const key = await crypto.subtle.importKey("spki", buf(spki), { name: "ECDSA", namedCurve: curve.name }, false, ["verify"]);
  return { key, size: curve.size };
}

async function verifiedBy(child: Certificate, parent: Certificate, options: { forcePure?: boolean } = {}): Promise<boolean> {
  if (!equalBytes(child.issuer, parent.subject)) return false;
  const hash = SIG_HASH[child.signatureAlg];
  if (!hash) return false;
  const mixed = parent.curve === P384_OID && hash === "SHA-256";
  if (mixed && options.forcePure) return verifyP384Sha256(parent.publicPoint, child.signature, child.tbs);
  const { key, size } = await importEcKey(parent.spki, parent.curve);
  try {
    return await crypto.subtle.verify({ name: "ECDSA", hash }, key, buf(derSignatureToRaw(child.signature, size)), buf(child.tbs));
  } catch (error) {
    // Apple's intermediate is a P-384 key that signs the credential certificate with
    // ecdsa-with-SHA256. Supabase's Edge Runtime (Deno 2.1) only pairs P-384 with SHA-384
    // and throws NotSupportedError, so that one combination is checked in pure code.
    if (mixed && (error as { name?: string })?.name === "NotSupportedError") {
      return verifyP384Sha256(parent.publicPoint, child.signature, child.tbs);
    }
    throw error;
  }
}

/** For tests: checks a certificate's signature by its issuer, optionally without WebCrypto. */
export function certificateSignedBy(child: Certificate, parent: Certificate, forcePure = false): Promise<boolean> {
  return verifiedBy(child, parent, { forcePure });
}

// ---------------------------------------------------------------- ECDSA P-384 / SHA-256 (pure)
// Signature checking only (public data, so no constant-time concerns). Curve: NIST P-384 (SEC 2).
const P384_OID = "1.3.132.0.34";
const P = 2n ** 384n - 2n ** 128n - 2n ** 96n + 2n ** 32n - 1n;
const N = 0xffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973n;
const B = 0xb3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aefn;
const G: Point = {
  x: 0xaa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7n,
  y: 0x3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5fn,
};
type Point = { x: bigint; y: bigint } | null; // null = point at infinity

const mod = (a: bigint, m: bigint) => ((a % m) + m) % m;
function inv(a: bigint, m: bigint): bigint {
  let [r0, r1, t0, t1] = [mod(a, m), m, 1n, 0n];
  while (r1 !== 0n) {
    const q = r0 / r1;
    [r0, r1] = [r1, r0 - q * r1];
    [t0, t1] = [t1, t0 - q * t1];
  }
  if (r0 !== 1n) fail("not invertible");
  return mod(t0, m);
}
function add(p1: Point, p2: Point): Point {
  if (!p1) return p2;
  if (!p2) return p1;
  if (p1.x === p2.x && mod(p1.y + p2.y, P) === 0n) return null;
  const l = p1.x === p2.x
    ? mod((3n * p1.x * p1.x - 3n) * inv(2n * p1.y, P), P) // a = -3
    : mod((p2.y - p1.y) * inv(p2.x - p1.x, P), P);
  const x = mod(l * l - p1.x - p2.x, P);
  return { x, y: mod(l * (p1.x - x) - p1.y, P) };
}
function mul(k: bigint, pt: Point): Point {
  let out: Point = null;
  for (let addend = pt; k > 0n; k >>= 1n, addend = add(addend, addend)) if (k & 1n) out = add(out, addend);
  return out;
}
const toInt = (bytes: Uint8Array) => bytes.reduce((acc, b) => (acc << 8n) | BigInt(b), 0n);

/** ECDSA over P-384 with a SHA-256 digest; `point` is the uncompressed key (04 ‖ x ‖ y). */
export async function verifyP384Sha256(point: Uint8Array, derSignature: Uint8Array, message: Uint8Array): Promise<boolean> {
  if (point.length !== 97 || point[0] !== 4) return false;
  const q = { x: toInt(point.slice(1, 49)), y: toInt(point.slice(49)) };
  if (q.x >= P || q.y >= P || mod(q.y * q.y - (q.x * q.x * q.x - 3n * q.x + B), P) !== 0n) return false;
  let raw: Uint8Array;
  try {
    raw = derSignatureToRaw(derSignature, 48);
  } catch {
    return false;
  }
  const r = toInt(raw.slice(0, 48));
  const s = toInt(raw.slice(48));
  if (r <= 0n || r >= N || s <= 0n || s >= N) return false;
  const e = toInt(await sha256(message)); // 256 bits < 384: no truncation
  const w = inv(s, N);
  const x = add(mul(mod(e * w, N), G), mul(mod(r * w, N), q));
  return x !== null && mod(x.x, N) === r;
}

// ---------------------------------------------------------------- authenticator data
interface AuthData { rpIdHash: Uint8Array; counter: number; aaguid?: Uint8Array; credentialId?: Uint8Array }

function parseAuthData(bytes: Uint8Array, attested: boolean): AuthData {
  if (bytes.length < 37) fail("authData too short");
  const counter = ((bytes[33] << 24) >>> 0) + (bytes[34] << 16) + (bytes[35] << 8) + bytes[36];
  const out: AuthData = { rpIdHash: bytes.slice(0, 32), counter };
  if (attested) {
    if (bytes.length < 55) fail("authData too short");
    out.aaguid = bytes.slice(37, 53);
    const n = (bytes[53] << 8) + bytes[54];
    if (bytes.length < 55 + n) fail("authData too short");
    out.credentialId = bytes.slice(55, 55 + n);
  }
  return out;
}

// ---------------------------------------------------------------- public API
export interface AttestationResult {
  /** SubjectPublicKeyInfo DER of the device key: stored, used to verify every assertion. */
  publicKey: Uint8Array;
  environment: AttestEnvironment;
  receipt: Uint8Array;
}

/**
 * Verifies an App Attest attestation object (steps 1–9 of Apple's guide).
 * `clientData` is the exact bytes the app hashed for attestKey's clientDataHash
 * (dv-report: the UTF-8 challenge string). `keyId` is the key identifier's raw
 * bytes (the app sends it base64). `now` is a parameter so tests can use real,
 * since-expired attestations.
 */
export async function verifyAttestation(params: {
  attestation: Uint8Array; clientData: Uint8Array; keyId: Uint8Array; appId: string;
  allowDevelopment: boolean; now?: number; rootPem?: string;
}): Promise<AttestationResult> {
  const now = params.now ?? Date.now();
  const object = decodeCbor(params.attestation);
  if (field(object, "fmt") !== "apple-appattest") fail("not an App Attest object");
  const attStmt = field(object, "attStmt");
  const x5c = field(attStmt as Cbor, "x5c");
  if (!Array.isArray(x5c) || x5c.length !== 2 || !x5c.every((c) => c instanceof Uint8Array)) fail("bad x5c");
  const receipt = bytesField(attStmt as Cbor, "receipt");
  const authDataBytes = bytesField(object, "authData");

  // 1. credCert ← intermediate ← pinned Apple root, all within their validity.
  const root = parseCertificate(pemToDer(params.rootPem ?? APPLE_APP_ATTEST_ROOT_PEM));
  const [leaf, intermediate] = (x5c as Uint8Array[]).map(parseCertificate);
  for (const c of [leaf, intermediate, root]) if (now < c.notBefore || now > c.notAfter) fail("certificate expired or not yet valid");
  if (!(await verifiedBy(intermediate, root))) fail("intermediate not issued by the Apple App Attestation Root CA");
  if (!(await verifiedBy(leaf, intermediate))) fail("credential certificate not issued by the intermediate");

  // 2–4. nonce = SHA256(authData ‖ SHA256(clientData)) must equal the credCert extension.
  const nonce = await sha256(concatBytes(authDataBytes, await sha256(params.clientData)));
  const ext = leaf.extensions.get(NONCE_OID) ?? fail("nonce extension missing");
  const seq = readDer(ext, 0);
  const tagged = children(seq)[0] ?? fail("bad nonce extension");
  const octets = children(tagged)[0] ?? fail("bad nonce extension");
  if (octets.tag !== 0x04 || !equalBytes(content(octets), nonce)) fail("nonce mismatch");

  // 5. keyId = SHA256(public key point).
  if (leaf.curve !== "1.2.840.10045.3.1.7") fail("credential key is not P-256");
  if (!equalBytes(await sha256(leaf.publicPoint), params.keyId)) fail("keyId mismatch");

  // 6–9. App ID, counter 0, environment, credential ID.
  const auth = parseAuthData(authDataBytes, true);
  if (!equalBytes(auth.rpIdHash, await sha256(enc.encode(params.appId)))) fail("App ID mismatch");
  if (auth.counter !== 0) fail("counter not 0");
  let environment: AttestEnvironment;
  if (equalBytes(auth.aaguid!, AAGUID_PRODUCTION)) environment = "production";
  else if (equalBytes(auth.aaguid!, AAGUID_DEVELOP)) environment = "development";
  else fail("unknown aaguid");
  if (environment === "development" && !params.allowDevelopment) fail("development environment not accepted");
  if (!equalBytes(auth.credentialId!, params.keyId)) fail("credentialId mismatch");

  return { publicKey: leaf.spki, environment, receipt };
}

/**
 * Verifies an App Attest assertion (steps 1–5): the signature over
 * SHA256(authenticatorData ‖ SHA256(clientData)) with the stored key, our App
 * ID, and a counter above the stored one. Returns the new counter, which the
 * caller must store atomically (only if still greater) to stop replays.
 * Step 6 (the challenge) is the caller's: it is inside clientData.
 */
export async function verifyAssertion(params: {
  assertion: Uint8Array; clientData: Uint8Array; publicKey: Uint8Array; appId: string; previousCounter: number;
}): Promise<{ counter: number }> {
  const object = decodeCbor(params.assertion);
  const signature = bytesField(object, "signature");
  const authenticatorData = bytesField(object, "authenticatorData");
  const nonce = await sha256(concatBytes(authenticatorData, await sha256(params.clientData)));
  const key = await crypto.subtle.importKey("spki", buf(params.publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, buf(derSignatureToRaw(signature, 32)), buf(nonce));
  if (!ok) fail("bad signature");
  const auth = parseAuthData(authenticatorData, false);
  if (!equalBytes(auth.rpIdHash, await sha256(enc.encode(params.appId)))) fail("App ID mismatch");
  if (auth.counter <= params.previousCounter) fail("counter not increasing");
  return { counter: auth.counter };
}

/**
 * What the app signs for a report: the UTF-8 challenge, a newline, then the
 * exact request body bytes. Binding the body means a captured assertion can't
 * be reused for different report text; binding the challenge means it can't be
 * replayed at all (challenges are single-use, 5 minutes).
 */
export function reportClientData(challenge: string, body: Uint8Array): Uint8Array {
  return concatBytes(enc.encode(challenge + "\n"), body);
}
