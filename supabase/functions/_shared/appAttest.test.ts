// Tests for appAttest.ts. Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/*/*.test.ts
//
// fixtures/app-attest-*.json are real App Attest attestations made on an
// iPhone for another app (V8H6LQ9448.io.uebelacker.AppAttestExample), from
// github.com/uebelack/node-app-attest (MIT). The assertion below is from the
// same project. Their certificates expired in December 2024, so the tests pass
// a `now` inside their validity.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  APPLE_APP_ATTEST_ROOT_PEM, AttestError, concatBytes, decodeCbor, ecdsaVerifyDigest, fromBase64, reportClientData, sha256, toBase64,
  verifyAssertion, verifyAttestation,
} from "./appAttest.ts";

const EXAMPLE_APP = "V8H6LQ9448.io.uebelacker.AppAttestExample";
const VALID_AT = Date.UTC(2024, 5, 1);
const fixture = (env: string) =>
  JSON.parse(readFileSync(new URL(`./fixtures/app-attest-${env}.json`, import.meta.url), "utf8")) as
    { attestation: string; challenge: string; keyId: string };

function inputs(env: "production" | "development") {
  const f = fixture(env);
  return {
    attestation: fromBase64(f.attestation)!,
    clientData: fromBase64(f.challenge)!, // the app hashed the challenge's bytes
    keyId: fromBase64(f.keyId)!,
    appId: EXAMPLE_APP,
    allowDevelopment: false,
    now: VALID_AT,
  };
}

async function rejects(promise: Promise<unknown>, reason: RegExp) {
  await assert.rejects(promise, (e: unknown) => e instanceof AttestError && reason.test(e.message));
}

test("the pinned root is Apple's App Attestation Root CA (by SHA-256 fingerprint)", async () => {
  const der = fromBase64(APPLE_APP_ATTEST_ROOT_PEM.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, ""), 65_536)!;
  const hex = Array.from(await sha256(der), (b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
  assert.equal(hex, "1CB9823BA28BA6AD2D33A006941DE2AE4F513EF1D4E831B9F7E0FA7B6242C932");
});

test("a real production attestation verifies", async () => {
  const result = await verifyAttestation(inputs("production"));
  assert.equal(result.environment, "production");
  assert.ok(result.receipt.length > 100);
  assert.equal(result.publicKey[0], 0x30); // SPKI DER
});

test("a development attestation is refused unless allowed", async () => {
  await rejects(verifyAttestation(inputs("development")), /development/);
  const result = await verifyAttestation({ ...inputs("development"), allowDevelopment: true });
  assert.equal(result.environment, "development");
});

test("attestation: another app's App ID is refused", async () => {
  await rejects(verifyAttestation({ ...inputs("production"), appId: "4XTR53RY2V.com.7twenty8studio.dailyverse" }), /App ID/);
});

test("attestation: a different challenge is refused", async () => {
  await rejects(verifyAttestation({ ...inputs("production"), clientData: new TextEncoder().encode("another") }), /nonce/);
});

test("attestation: a different key id is refused", async () => {
  const keyId = inputs("production").keyId.slice();
  keyId[0] ^= 1;
  await rejects(verifyAttestation({ ...inputs("production"), keyId }), /keyId/);
});

test("attestation: expired certificates are refused", async () => {
  await rejects(verifyAttestation({ ...inputs("production"), now: Date.UTC(2026, 10, 16) }), /expired/);
});

test("attestation: a chain that doesn't lead to the pinned root is refused", async () => {
  // A self-signed P-384 root that is not Apple's.
  const other = `-----BEGIN CERTIFICATE-----
MIIBrjCCATSgAwIBAgIUMGdUjJHmGFXLyqbIn9ffOMZ7SJQwCgYIKoZIzj0EAwIw
DjEMMAoGA1UEAwwDMTIzMB4XDTI0MDIwNTIxMzQwNFoXDTM0MDIwMjIxMzQwNFow
DjEMMAoGA1UEAwwDMTIzMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEPcy+aBrD4yUv
yh2fio3AZTQyIVUF4UllUcpWu8bBFHjCDN4W2TsIBrcyueFQYor2cGnFJ00gAT0u
c2L81EMgFU6xqmKzRbnJrJB8vB9qY2UWk3FJJPP6gf2abzpsMwVjo1MwUTAdBgNV
HQ4EFgQUqYyT9rPWmVIgODa5vTCoNNGcWHYwHwYDVR0jBBgwFoAUqYyT9rPWmVIg
ODa5vTCoNNGcWHYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNoADBlAjEA
yT6UP8AXVS++9I3+40EHEnK1rQFj102VLPoNBPxl9uaRxCOklIyh5zQIv1l3UKjE
AjAf6viaXK8SqjdzZbR5DcrSfISX8lQq9TD/7ZapZWI4sY0d+xnHu9jUIQLGyrd9
FaM=
-----END CERTIFICATE-----`;
  await rejects(verifyAttestation({ ...inputs("production"), rootPem: other }), /Root CA/);
});

test("attestation: a tampered authData is refused", async () => {
  const bad = inputs("production");
  const object = decodeCbor(bad.attestation) as Map<string, unknown>;
  assert.ok(object.get("authData") instanceof Uint8Array);
  // Flip one byte inside the CBOR-encoded authData (its counter field).
  const auth = object.get("authData") as Uint8Array;
  const at = indexOf(bad.attestation, auth);
  const tampered = bad.attestation.slice();
  tampered[at + 36] ^= 1;
  await rejects(verifyAttestation({ ...bad, attestation: tampered }), /nonce|counter/);
});

test("attestation: garbage is refused, never crashes", async () => {
  for (const bytes of [new Uint8Array(), Uint8Array.from([0xa1]), new TextEncoder().encode("hello"), Uint8Array.from([0x9f, 0xff])]) {
    await assert.rejects(verifyAttestation({ ...inputs("production"), attestation: bytes }), AttestError);
  }
});

// ---- assertions
const ASSERTION = fromBase64(
  "omlzaWduYXR1cmVYRzBFAiBB8BGAwkmFCg1M5J0mOYEun0SUN1/lse79/7ypG9WiMQIhAIHvqj7eg59B1PMFX1CN4GMGlsgfFtdL30pHCf7G/dNRcWF1dGhlbnRpY2F0b3JEYXRhWCXKPdw7T3iujcFZbHVrHX0mDSMrNms5PzEbrFbQPRA6rEAAAAAB",
)!;
const ASSERTION_KEY = fromBase64(
  "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEg69t2YzgcPTLUx8Zgu+rbcikeaEL8Ppb+HG0QTIulz8YUB9tgv1pDRruWk87nZC3our56pzIWaqXEbaWyamdzA==",
)!;
const PAYLOAD = new TextEncoder().encode('{"subject":"Lorem ipsum","message":"Lorem ipsum dolor sit amet, consectetur adipiscing elit."}');
const assertionInput = () => ({ assertion: ASSERTION, clientData: PAYLOAD, publicKey: ASSERTION_KEY, appId: EXAMPLE_APP, previousCounter: 0 });

test("a real assertion verifies and returns its counter", async () => {
  assert.deepEqual(await verifyAssertion(assertionInput()), { counter: 1 });
});

test("assertion: replay (counter not above the stored one) is refused", async () => {
  await rejects(verifyAssertion({ ...assertionInput(), previousCounter: 1 }), /counter/);
});

test("assertion: a changed body is refused", async () => {
  await rejects(verifyAssertion({ ...assertionInput(), clientData: concatBytes(PAYLOAD, Uint8Array.from([32])) }), /signature/);
});

test("assertion: another app's App ID is refused", async () => {
  await rejects(verifyAssertion({ ...assertionInput(), appId: "4XTR53RY2V.com.7twenty8studio.dailyverse" }), /App ID/);
});

test("assertion: another key is refused", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  await rejects(verifyAssertion({ ...assertionInput(), publicKey: spki }), /signature/);
});

test("reportClientData is the challenge, a newline, then the exact body", () => {
  const body = new TextEncoder().encode('{"a":1}');
  assert.equal(new TextDecoder().decode(reportClientData("abc", body)), 'abc\n{"a":1}');
});

test("base64 helpers round-trip and refuse junk", () => {
  const bytes = Uint8Array.from([0, 255, 10, 20]);
  assert.deepEqual(fromBase64(toBase64(bytes)), bytes);
  assert.equal(fromBase64("not base64!"), null);
  assert.equal(fromBase64(""), null);
  assert.equal(fromBase64(42), null);
});

function indexOf(haystack: Uint8Array, needle: Uint8Array): number {
  outer: for (let i = 0; i + needle.length <= haystack.length; i++) {
    for (let j = 0; j < needle.length; j++) if (haystack[i + j] !== needle[j]) continue outer;
    return i;
  }
  return -1;
}

// --- Supabase Edge Runtime: WebCrypto verifies only P-256/SHA-256 and P-384/SHA-384 -----------
// (edge-runtime v1.70.0: "NotSupportedError: Not implemented" for P-384/SHA-256, which Apple's
// App Attestation CA uses to sign device certificates). Found on the first iPhone attestation.

test("ecdsaVerifyDigest agrees with WebCrypto for every curve/hash pair", async () => {
  for (const [curve, hash] of [["P-256", "SHA-256"], ["P-384", "SHA-384"], ["P-384", "SHA-256"], ["P-256", "SHA-384"]]) {
    const keys = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"]);
    const point = new Uint8Array(await crypto.subtle.exportKey("raw", keys.publicKey));
    const other = new Uint8Array(await crypto.subtle.exportKey("raw",
      (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"])).publicKey));
    for (let i = 0; i < 3; i++) {
      const message = crypto.getRandomValues(new Uint8Array(64 + i));
      const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash }, keys.privateKey, message));
      const digest = new Uint8Array(await crypto.subtle.digest(hash, message));
      assert.equal(ecdsaVerifyDigest(curve, point, signature, digest), true, `${curve}/${hash}`);
      const tampered = digest.slice();
      tampered[0] ^= 1;
      assert.equal(ecdsaVerifyDigest(curve, point, signature, tampered), false, `${curve}/${hash} tampered`);
      assert.equal(ecdsaVerifyDigest(curve, other, signature, digest), false, `${curve}/${hash} other key`);
      const flipped = signature.slice();
      flipped[flipped.length - 1] ^= 1;
      assert.equal(ecdsaVerifyDigest(curve, point, flipped, digest), false, `${curve}/${hash} bad signature`);
    }
    assert.equal(ecdsaVerifyDigest(curve, point.subarray(1), new Uint8Array(point.length - 1), new Uint8Array(32)), false);
  }
  // A point that isn't on the curve is refused.
  const bogus = new Uint8Array(65);
  bogus[0] = 4;
  bogus[64] = 1;
  assert.equal(ecdsaVerifyDigest("P-256", bogus, new Uint8Array(64).fill(1), new Uint8Array(32)), false);
});

test("regression: a real Apple attestation verifies where WebCrypto only knows matched curve/hash pairs", async () => {
  const original = crypto.subtle.verify.bind(crypto.subtle);
  const native: Record<string, string> = { "P-256": "SHA-256", "P-384": "SHA-384" };
  const keyCurve = (key: CryptoKey) => (key.algorithm as EcKeyAlgorithm).namedCurve;
  let refused = 0;
  // Behave like Supabase's Edge Runtime.
  (crypto.subtle as { verify: typeof crypto.subtle.verify }).verify = (async (algorithm, key, signature, data) => {
    const hash = (algorithm as EcdsaParams).hash;
    const hashName = typeof hash === "string" ? hash : hash.name;
    if ((algorithm as Algorithm).name === "ECDSA" && native[keyCurve(key)] !== hashName) {
      refused++;
      throw new DOMException("Not implemented", "NotSupportedError");
    }
    return original(algorithm, key, signature, data);
  }) as typeof crypto.subtle.verify;
  try {
    const result = await verifyAttestation(inputs("production"));
    assert.equal(result.environment, "production");
    assert.equal(refused, 0, "mixed pairs never reach WebCrypto verify");
  } finally {
    (crypto.subtle as { verify: typeof crypto.subtle.verify }).verify = original;
  }
});
