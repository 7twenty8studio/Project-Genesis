// Tests for lib.ts. Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/delete-account/lib.test.ts
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { test } from "node:test";
import {
  APPLE_CLIENT_ID,
  APPLE_REVOKE_URL,
  APPLE_TOKEN_URL,
  appleClientSecret,
  appleConfig,
  type AppleSignInConfig,
  base64url,
  type Fetch,
  parseDeleteRequest,
  pemToDer,
  revokeAppleTokens,
  revokeForm,
  tokenForm,
} from "./lib.ts";

const subtle = webcrypto.subtle;

/** A fresh P-256 key, its .p8-style PEM and the matching public key. */
async function makeKey(): Promise<{ pem: string; publicKey: webcrypto.CryptoKey }> {
  const pair = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = Buffer.from(await subtle.exportKey("pkcs8", pair.privateKey));
  const lines = der.toString("base64").match(/.{1,64}/g)!.join("\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${lines}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

function decode(part: string): unknown {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

test("base64url has no padding or +/", () => {
  assert.equal(base64url("hello"), "aGVsbG8");
  assert.equal(base64url(new Uint8Array([0xfb, 0xff, 0xfe])), "-__-");
  assert.equal(base64url(new Uint8Array([])), "");
});

test("reads the Apple code from the request body", () => {
  assert.deepEqual(parseDeleteRequest({}), { appleAuthorizationCode: null });
  assert.deepEqual(parseDeleteRequest(null), { appleAuthorizationCode: null });
  assert.deepEqual(parseDeleteRequest({ appleAuthorizationCode: 42 }), { appleAuthorizationCode: null });
  assert.deepEqual(parseDeleteRequest({ appleAuthorizationCode: "  " }), { appleAuthorizationCode: null });
  assert.deepEqual(parseDeleteRequest({ appleAuthorizationCode: "a b" }), { appleAuthorizationCode: null });
  assert.deepEqual(parseDeleteRequest({ appleAuthorizationCode: "x".repeat(3000) }), { appleAuthorizationCode: null });
  assert.deepEqual(parseDeleteRequest({ appleAuthorizationCode: " c1a2.0.abc.XYZ \n" }), { appleAuthorizationCode: "c1a2.0.abc.XYZ" });
});

test("needs all three secrets", () => {
  const env = (values: Record<string, string>) => (name: string) => values[name];
  assert.equal(appleConfig(env({})), null);
  assert.equal(appleConfig(env({ APPLE_SIGNIN_KEY: "k", APPLE_SIGNIN_KEY_ID: "id" })), null);
  assert.equal(appleConfig(env({ APPLE_SIGNIN_KEY: " ", APPLE_SIGNIN_KEY_ID: "id", APPLE_TEAM_ID: "t" })), null);
  assert.deepEqual(appleConfig(env({ APPLE_SIGNIN_KEY: "k", APPLE_SIGNIN_KEY_ID: " id ", APPLE_TEAM_ID: "t" })), {
    key: "k",
    keyID: "id",
    teamID: "t",
    clientID: APPLE_CLIENT_ID,
  });
});

test("signs a client secret Apple can verify", async () => {
  const { pem, publicKey } = await makeKey();
  const config: AppleSignInConfig = { key: pem, keyID: "KEY1234567", teamID: "TEAM123456", clientID: APPLE_CLIENT_ID };
  const jwt = await appleClientSecret(config, 1_700_000_000);
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(decode(header), { alg: "ES256", kid: "KEY1234567" });
  assert.deepEqual(decode(claims), {
    iss: "TEAM123456",
    iat: 1_700_000_000,
    exp: 1_700_000_300,
    aud: "https://appleid.apple.com",
    sub: "com.7twenty8studio.versely",
  });
  for (const part of [header, claims, signature]) assert.match(part, /^[A-Za-z0-9_-]+$/);
  const raw = Buffer.from(signature, "base64url");
  assert.equal(raw.length, 64, "raw r||s, not DER");
  const ok = await subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    raw,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert.ok(ok, "signature verifies with the matching public key");
  // A key pasted with literal \n still works.
  assert.deepEqual(pemToDer(pem.replace(/\n/g, "\\n")), pemToDer(pem));
});

test("builds the token and revoke forms", () => {
  assert.equal(
    tokenForm("com.example", "secret", "code/1+").toString(),
    "client_id=com.example&client_secret=secret&code=code%2F1%2B&grant_type=authorization_code",
  );
  assert.equal(
    revokeForm("com.example", "secret", "r.1", "refresh_token").toString(),
    "client_id=com.example&client_secret=secret&token=r.1&token_type_hint=refresh_token",
  );
});

function recorder(responses: { status: number; body: string }[]) {
  const calls: { url: string; body: URLSearchParams; contentType: string }[] = [];
  const fetcher: Fetch = async (url, init) => {
    calls.push({ url, body: new URLSearchParams(init.body), contentType: init.headers["Content-Type"] });
    const next = responses.shift() ?? { status: 500, body: "" };
    return { ok: next.status >= 200 && next.status < 300, status: next.status, text: async () => next.body };
  };
  return { calls, fetcher };
}

test("exchanges the code, then revokes the refresh token", async () => {
  const { pem } = await makeKey();
  const config: AppleSignInConfig = { key: pem, keyID: "K", teamID: "T", clientID: APPLE_CLIENT_ID };
  const { calls, fetcher } = recorder([
    { status: 200, body: JSON.stringify({ access_token: "a.1", refresh_token: "r.1", id_token: "i" }) },
    { status: 200, body: "" },
  ]);
  const result = await revokeAppleTokens(config, "code-1", fetcher, 1_700_000_000);
  assert.deepEqual(result, { revoked: true });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, APPLE_TOKEN_URL);
  assert.equal(calls[0].contentType, "application/x-www-form-urlencoded");
  assert.equal(calls[0].body.get("grant_type"), "authorization_code");
  assert.equal(calls[0].body.get("code"), "code-1");
  assert.equal(calls[0].body.get("client_id"), APPLE_CLIENT_ID);
  assert.equal(calls[1].url, APPLE_REVOKE_URL);
  assert.equal(calls[1].body.get("token"), "r.1");
  assert.equal(calls[1].body.get("token_type_hint"), "refresh_token");
  assert.equal(calls[1].body.get("client_secret"), calls[0].body.get("client_secret"));
});

test("revokes the access token when there's no refresh token", async () => {
  const { pem } = await makeKey();
  const config: AppleSignInConfig = { key: pem, keyID: "K", teamID: "T", clientID: APPLE_CLIENT_ID };
  const { calls, fetcher } = recorder([{ status: 200, body: JSON.stringify({ access_token: "a.1" }) }, { status: 200, body: "" }]);
  assert.deepEqual(await revokeAppleTokens(config, "c", fetcher), { revoked: true });
  assert.equal(calls[1].body.get("token"), "a.1");
  assert.equal(calls[1].body.get("token_type_hint"), "access_token");
});

test("reports Apple's refusals without throwing", async () => {
  const { pem } = await makeKey();
  const config: AppleSignInConfig = { key: pem, keyID: "K", teamID: "T", clientID: APPLE_CLIENT_ID };

  const rejected = recorder([{ status: 400, body: JSON.stringify({ error: "invalid_grant" }) }]);
  assert.deepEqual(await revokeAppleTokens(config, "old", rejected.fetcher), { revoked: false, reason: "token 400: invalid_grant" });
  assert.equal(rejected.calls.length, 1);

  const revokeFails = recorder([{ status: 200, body: JSON.stringify({ refresh_token: "r" }) }, { status: 400, body: "nope" }]);
  assert.deepEqual(await revokeAppleTokens(config, "c", revokeFails.fetcher), { revoked: false, reason: "revoke 400: unknown" });

  const empty = recorder([{ status: 200, body: "{}" }]);
  assert.equal((await revokeAppleTokens(config, "c", empty.fetcher)).revoked, false);

  const badKey = recorder([]);
  const result = await revokeAppleTokens({ ...config, key: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----" }, "c", badKey.fetcher);
  assert.equal(result.revoked, false);
  assert.equal(badKey.calls.length, 0);

  const offline = await revokeAppleTokens(config, "c", async () => {
    throw new Error("network down");
  });
  assert.deepEqual(offline, { revoked: false, reason: "network down" });
});
