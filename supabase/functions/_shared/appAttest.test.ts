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
  APPLE_APP_ATTEST_ROOT_PEM, AttestError, certificateSignedBy, concatBytes, decodeCbor, fromBase64, parseCertificate,
  reportClientData, sha256, toBase64, verifyAssertion, verifyAttestation, verifyP384Sha256,
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

// Regression (production, 17 Nov 2026): Supabase's Edge Runtime (Deno 2.1) throws
// NotSupportedError for ECDSA P-384 with SHA-256, which is how Apple's intermediate signs
// the credential certificate. That pair is checked in pure code there; it must agree with WebCrypto.
function chain() {
  const att = decodeCbor(fromBase64(fixture("production").attestation, 20_000)!) as Map<string, unknown>;
  const x5c = (att.get("attStmt") as Map<string, unknown>).get("x5c") as Uint8Array[];
  return { leaf: parseCertificate(x5c[0]), intermediate: parseCertificate(x5c[1]) };
}

test("Apple's intermediate (P-384) signs the credential certificate with SHA-256", () => {
  const { leaf, intermediate } = chain();
  assert.equal(intermediate.curve, "1.3.132.0.34");
  assert.equal(leaf.signatureAlg, "1.2.840.10045.4.3.2");
});

test("the pure P-384/SHA-256 check accepts Apple's real credential certificate", async () => {
  const { leaf, intermediate } = chain();
  assert.equal(await certificateSignedBy(leaf, intermediate, true), true);
  assert.equal(await certificateSignedBy(leaf, intermediate, false), true, "same answer as WebCrypto");
});

test("the pure P-384/SHA-256 check refuses a changed certificate, signature or key", async () => {
  const { leaf, intermediate } = chain();
  const tbs = leaf.tbs.slice(); tbs[tbs.length - 1] ^= 1;
  assert.equal(await verifyP384Sha256(intermediate.publicPoint, leaf.signature, tbs), false);
  const sig = leaf.signature.slice(); sig[sig.length - 1] ^= 1;
  assert.equal(await verifyP384Sha256(intermediate.publicPoint, sig, leaf.tbs), false);
  const key = intermediate.publicPoint.slice(); key[96] ^= 1; // off the curve
  assert.equal(await verifyP384Sha256(key, leaf.signature, leaf.tbs), false);
  assert.equal(await verifyP384Sha256(intermediate.publicPoint, new Uint8Array([0x30, 0x00]), leaf.tbs), false);
});

test("a real attestation verifies on a runtime without P-384/SHA-256 (as Supabase's Edge Runtime)", async () => {
  const subtle = crypto.subtle as SubtleCrypto & { verify: SubtleCrypto["verify"] };
  const original = subtle.verify.bind(subtle);
  let refused = 0;
  subtle.verify = (async (algorithm: EcdsaParams, key: CryptoKey, signature: BufferSource, data: BufferSource) => {
    if ((key.algorithm as EcKeyAlgorithm).namedCurve === "P-384" && algorithm.hash === "SHA-256") {
      refused++;
      throw new DOMException("Not implemented", "NotSupportedError");
    }
    return original(algorithm, key, signature, data);
  }) as SubtleCrypto["verify"];
  try {
    const result = await verifyAttestation(inputs("production"));
    assert.equal(result.environment, "production");
    assert.equal(refused, 1, "the WebCrypto path was refused once and the pure check took over");
  } finally {
    subtle.verify = original;
  }
});
