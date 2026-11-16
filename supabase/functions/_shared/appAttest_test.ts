// Unit tests for appAttest.ts with a stand-in CA (Apple's real chain needs a device; the
// device check is in the release notes). Run: deno test --allow-env supabase/functions/_shared/appAttest_test.ts (Deno, not node:test)
import { assert, assertEquals } from "jsr:@std/assert@1";
import { encode as cborEncode } from "npm:cbor-x@1.6.0";
import * as x509 from "npm:@peculiar/x509@1.12.3";
import {
  attestClientDataHash, checkChallenge, concat, DAILY_VERSE_APP_ID, derToRaw, makeChallenge, reportClientDataHash,
  sha256, verifyAssertion, verifyAttestation,
} from "./appAttest.ts";

x509.cryptoProvider.set(crypto);
const enc = new TextEncoder();
const EC384 = { name: "ECDSA", namedCurve: "P-384", hash: "SHA-384" } as const;
const EC256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const NOW = new Date("2026-11-17T12:00:00Z");
const FROM = new Date("2026-01-01T00:00:00Z");
const TO = new Date("2027-01-01T00:00:00Z");

function u32(n: number): Uint8Array {
  return new Uint8Array([(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]);
}
function b64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

interface Fixture {
  rootPem: string;
  keyId: string;
  devicePrivate: CryptoKey;
  attestation: Uint8Array;
  challenge: string;
}

async function fixture(opts: {
  appId?: string; counter?: number; aaguid?: Uint8Array; nonceOverride?: Uint8Array; keyIdOverride?: Uint8Array;
} = {}): Promise<Fixture> {
  const rootKeys = await crypto.subtle.generateKey(EC384, true, ["sign", "verify"]);
  const interKeys = await crypto.subtle.generateKey(EC384, true, ["sign", "verify"]);
  const device = await crypto.subtle.generateKey(EC256, true, ["sign", "verify"]);
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Test Root", notBefore: FROM, notAfter: TO, keys: rootKeys, signingAlgorithm: EC384,
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });
  const inter = await x509.X509CertificateGenerator.create({
    serialNumber: "02", subject: "CN=Test Intermediate", issuer: root.subject, notBefore: FROM, notAfter: TO,
    publicKey: interKeys.publicKey, signingKey: rootKeys.privateKey, signingAlgorithm: EC384,
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
  const raw = new Uint8Array(await crypto.subtle.exportKey("raw", device.publicKey));
  const keyIdBytes = opts.keyIdOverride ?? await sha256(raw);
  const challenge = "test-challenge";
  const authData = concat(
    await sha256(enc.encode(opts.appId ?? DAILY_VERSE_APP_ID)), new Uint8Array([0x40]), u32(opts.counter ?? 0),
    opts.aaguid ?? concat(enc.encode("appattest"), new Uint8Array(7)), new Uint8Array([0, 32]), keyIdBytes,
  );
  const nonce = opts.nonceOverride ?? await sha256(concat(authData, await attestClientDataHash(challenge)));
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03", subject: "CN=device", issuer: inter.subject, notBefore: FROM, notAfter: TO,
    publicKey: device.publicKey, signingKey: interKeys.privateKey, signingAlgorithm: EC384,
    extensions: [new x509.Extension("1.2.840.113635.100.8.2", false,
      concat(new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce).slice().buffer as ArrayBuffer)],
  });
  const attestation = cborEncode({
    fmt: "apple-appattest",
    attStmt: { x5c: [new Uint8Array(leaf.rawData), new Uint8Array(inter.rawData)], receipt: new Uint8Array([1]) },
    authData,
  });
  return { rootPem: root.toString("pem"), keyId: b64(await sha256(raw)), devicePrivate: device.privateKey, attestation, challenge };
}

/** An assertion as DCAppAttestService makes it: DER ECDSA/SHA-256 over SHA-256(authData || clientDataHash). */
async function assertion(key: CryptoKey, clientDataHash: Uint8Array, counter: number, appId = DAILY_VERSE_APP_ID) {
  const authData = concat(await sha256(enc.encode(appId)), new Uint8Array([0x40]), u32(counter));
  const nonce = await sha256(concat(authData, clientDataHash));
  const rawSig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, nonce.slice().buffer as ArrayBuffer));
  return cborEncode({ signature: rawToDer(rawSig), authenticatorData: authData });
}
function rawToDer(raw: Uint8Array): Uint8Array {
  const int = (v: Uint8Array) => {
    let i = 0;
    while (i < v.length - 1 && v[i] === 0) i++;
    v = v.subarray(i);
    if (v[0] & 0x80) v = concat(new Uint8Array([0]), v);
    return concat(new Uint8Array([2, v.length]), v);
  };
  const body = concat(int(raw.subarray(0, 32)), int(raw.subarray(32)));
  return concat(new Uint8Array([0x30, body.length]), body);
}

Deno.test("a valid attestation is accepted and returns the certified key", async () => {
  const f = await fixture();
  const r = await verifyAttestation(f.keyId, f.attestation, await attestClientDataHash(f.challenge), { roots: [f.rootPem], now: NOW });
  assert(r.ok, JSON.stringify(r));
  assertEquals(r.ok && r.environment, "production");
  assertEquals(r.ok && r.publicKey.length, 65);
});

Deno.test("attestation: wrong root, wrong challenge, app, counter, environment and key ID are refused", async () => {
  const f = await fixture();
  const cdh = await attestClientDataHash(f.challenge);
  // Apple's real root (the default) does not sign the stand-in chain.
  assertEquals(await verifyAttestation(f.keyId, f.attestation, cdh, { now: NOW }), { ok: false, reason: "chain" });
  assertEquals(await verifyAttestation(f.keyId, f.attestation, await attestClientDataHash("other"), { roots: [f.rootPem], now: NOW }),
    { ok: false, reason: "nonce" });
  assertEquals(await verifyAttestation(f.keyId, f.attestation, cdh, { roots: [f.rootPem], now: new Date("2030-01-01") }),
    { ok: false, reason: "chain" });
  const other = await fixture();
  assertEquals(await verifyAttestation(other.keyId, f.attestation, cdh, { roots: [f.rootPem], now: NOW }), { ok: false, reason: "key_id" });
  const app = await fixture({ appId: "4XTR53RY2V.com.example.other" });
  assertEquals(await verifyAttestation(app.keyId, app.attestation, cdh, { roots: [app.rootPem], now: NOW }), { ok: false, reason: "app_id" });
  const counter = await fixture({ counter: 1 });
  assertEquals(await verifyAttestation(counter.keyId, counter.attestation, cdh, { roots: [counter.rootPem], now: NOW }),
    { ok: false, reason: "counter" });
  const dev = await fixture({ aaguid: enc.encode("appattestdevelop") });
  assertEquals(await verifyAttestation(dev.keyId, dev.attestation, cdh, { roots: [dev.rootPem], now: NOW }),
    { ok: false, reason: "environment" });
  const devOk = await verifyAttestation(dev.keyId, dev.attestation, cdh, { roots: [dev.rootPem], now: NOW, allowDevelopment: true });
  assertEquals(devOk.ok && devOk.environment, "development");
  const cred = await fixture({ keyIdOverride: new Uint8Array(32) });
  assertEquals(await verifyAttestation(cred.keyId, cred.attestation, cdh, { roots: [cred.rootPem], now: NOW }),
    { ok: false, reason: "credential" });
  assertEquals(await verifyAttestation(f.keyId, new Uint8Array([1, 2, 3]), cdh, { roots: [f.rootPem], now: NOW }),
    { ok: false, reason: "format" });
});

Deno.test("assertions: valid, replayed, tampered body, other key and other app", async () => {
  const f = await fixture();
  const r = await verifyAttestation(f.keyId, f.attestation, await attestClientDataHash(f.challenge), { roots: [f.rootPem], now: NOW });
  assert(r.ok);
  const body = enc.encode(JSON.stringify({ description: "3 Down clue looks wrong." }));
  const cdh = await reportClientDataHash("c1", body);
  const a = await assertion(f.devicePrivate, cdh, 1);
  assertEquals(await verifyAssertion(a, cdh, r.publicKey, 0), { ok: true, counter: 1 });
  // Same counter again: replay.
  assertEquals(await verifyAssertion(a, cdh, r.publicKey, 1), { ok: false, reason: "counter" });
  // A different body (or challenge) under the same signature.
  const tampered = await reportClientDataHash("c1", enc.encode(JSON.stringify({ description: "changed" })));
  assertEquals(await verifyAssertion(a, tampered, r.publicKey, 0), { ok: false, reason: "signature" });
  assertEquals(await verifyAssertion(a, await reportClientDataHash("c2", body), r.publicKey, 0), { ok: false, reason: "signature" });
  // Signed by a different device key.
  const g = await fixture();
  const b = await assertion(g.devicePrivate, cdh, 2);
  assertEquals(await verifyAssertion(b, cdh, r.publicKey, 0), { ok: false, reason: "signature" });
  const c = await assertion(f.devicePrivate, cdh, 3, "4XTR53RY2V.com.example.other");
  assertEquals(await verifyAssertion(c, cdh, r.publicKey, 0), { ok: false, reason: "app_id" });
  assertEquals(await verifyAssertion(new Uint8Array([9]), cdh, r.publicKey, 0), { ok: false, reason: "format" });
});

Deno.test("challenges are signed, expire after five minutes and can't be forged", async () => {
  const secret = "s".repeat(64);
  const now = Date.parse("2026-11-17T12:00:00Z");
  const c = await makeChallenge(secret, now);
  assert(await checkChallenge(secret, c, now));
  assert(await checkChallenge(secret, c, now + 299_000));
  assert(!(await checkChallenge(secret, c, now + 301_000)));
  assert(!(await checkChallenge("t".repeat(64), c, now)));
  assert(!(await checkChallenge(secret, c.replace(/.$/, c.endsWith("0") ? "1" : "0"), now)));
  assert(!(await checkChallenge(secret, "x", now)));
  assert(!(await checkChallenge(secret, 42, now)));
});

Deno.test("DER signatures convert to raw r||s", () => {
  const raw = new Uint8Array(64).map((_, i) => (i === 0 || i === 32 ? 0x80 : i));
  assertEquals(derToRaw(rawToDer(raw)), raw);
  assertEquals(derToRaw(new Uint8Array([1, 2])), null);
});
