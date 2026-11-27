// Tests for play.ts and google.ts. Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/_shared/play.test.ts
import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { test } from "node:test";
import { assertionClaims, GoogleTokens, parseServiceAccount, PLAY_SCOPE, signedAssertion } from "./google.ts";
import {
  evaluateSubscription,
  isPurchaseToken,
  parseDeveloperNotification,
  PLAY_PRODUCT_IDS,
  playKey,
  PlayVerificationError,
  sameSecret,
  subscriptionURL,
} from "./play.ts";

const now = new Date("2026-11-27T12:00:00Z");
const user = "AAAAAAAA-0000-0000-0000-000000000001";
const active = {
  subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
  acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
  externalAccountIdentifiers: { obfuscatedExternalAccountId: user.toLowerCase() },
  lineItems: [{ productId: "com.7twenty8studio.versely.premium", expiryTime: "2026-12-27T12:00:00.000Z" }],
};
const options = { productIds: PLAY_PRODUCT_IDS, userID: user, now };

function reason(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    if (error instanceof PlayVerificationError) return error.reason;
    throw error;
  }
  return "ok";
}

test("an active subscription unlocks Premium until its end", () => {
  const result = evaluateSubscription(active, options);
  assert.equal(result.expiresAt, "2026-12-27T12:00:00.000Z");
  assert.equal(result.environment, "Production");
  assert.equal(result.acknowledged, false);
  assert.equal(evaluateSubscription({ ...active, testPurchase: {} }, options).environment, "Test");
});

test("grace period and a cancelled one still unlock it; hold, pause and expiry don't", () => {
  assert.equal(reason(() => evaluateSubscription({ ...active, subscriptionState: "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" }, options)), "ok");
  assert.equal(reason(() => evaluateSubscription({ ...active, subscriptionState: "SUBSCRIPTION_STATE_CANCELED" }, options)), "ok");
  for (const state of ["SUBSCRIPTION_STATE_ON_HOLD", "SUBSCRIPTION_STATE_PAUSED", "SUBSCRIPTION_STATE_EXPIRED", "SUBSCRIPTION_STATE_PENDING"]) {
    assert.equal(reason(() => evaluateSubscription({ ...active, subscriptionState: state }, options)), "not_active");
  }
  const ended = { ...active, subscriptionState: "SUBSCRIPTION_STATE_CANCELED", lineItems: [{ productId: active.lineItems[0].productId, expiryTime: "2026-11-01T00:00:00Z" }] };
  assert.equal(reason(() => evaluateSubscription(ended, options)), "expired");
});

test("other products, other accounts and nothing at all are refused", () => {
  assert.equal(reason(() => evaluateSubscription(null, options)), "not_found");
  assert.equal(reason(() => evaluateSubscription({ ...active, lineItems: [{ productId: "coins", expiryTime: "2027-01-01T00:00:00Z" }] }, options)), "wrong_product");
  assert.equal(reason(() => evaluateSubscription(active, { ...options, userID: "bbbbbbbb-0000-0000-0000-000000000002" })), "wrong_account");
  // Bought while signed out: the first account to send it keeps it (the key is unique).
  assert.equal(reason(() => evaluateSubscription({ ...active, externalAccountIdentifiers: {} }, options)), "ok");
});

test("purchase tokens, keys and addresses", () => {
  const token = "abcdefghij.klmnopqrst-UVWXYZ_0123456789";
  assert.ok(isPurchaseToken(token));
  assert.ok(!isPurchaseToken("short"));
  assert.ok(!isPurchaseToken("has spaces in it and is long enough"));
  assert.equal(playKey(token), `play:${token}`);
  assert.ok(subscriptionURL("com.seventwenty8studio.versely", token).endsWith(`/purchases/subscriptionsv2/tokens/${token}`));
});

test("reads a Real-time Developer Notification", () => {
  const data = Buffer.from(JSON.stringify({
    version: "1.0",
    packageName: "com.seventwenty8studio.versely",
    eventTimeMillis: "1764244800000",
    subscriptionNotification: { version: "1.0", notificationType: 4, purchaseToken: "abcdefghij.klmnopqrst-UVWXYZ", subscriptionId: "com.7twenty8studio.versely.premium" },
  })).toString("base64");
  const parsed = parseDeveloperNotification({ message: { data, messageId: "1" }, subscription: "x" });
  assert.equal(parsed?.purchaseToken, "abcdefghij.klmnopqrst-UVWXYZ");
  assert.equal(parsed?.notificationType, 4);
  assert.equal(parsed?.test, false);
  const ping = Buffer.from(JSON.stringify({ packageName: "com.seventwenty8studio.versely", testNotification: { version: "1.0" } })).toString("base64");
  assert.equal(parseDeveloperNotification({ message: { data: ping } })?.test, true);
  assert.equal(parseDeveloperNotification({ message: { data: "not base64 json" } }), null);
  assert.equal(parseDeveloperNotification(null), null);
});

test("secrets compare whole", () => {
  assert.ok(sameSecret("abc123", "abc123"));
  assert.ok(!sameSecret("abc123", "abc124"));
  assert.ok(!sameSecret("abc", "abc123"));
});

test("signs a service account assertion Google can verify, and reuses the token", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  const account = parseServiceAccount(JSON.stringify({ client_email: "play@versely.iam.gserviceaccount.com", private_key: pem }));
  assert.ok(account);
  assert.equal(parseServiceAccount("{}"), null);
  assert.equal(parseServiceAccount("not json"), null);

  const jwt = await signedAssertion(account!, PLAY_SCOPE, 1_764_244_800);
  const [header, claims, signature] = jwt.split(".");
  const decode = (part: string) => JSON.parse(Buffer.from(part, "base64url").toString());
  assert.equal(decode(header).alg, "RS256");
  assert.deepEqual(decode(claims), assertionClaims(account!, PLAY_SCOPE, 1_764_244_800));
  assert.ok(verify("RSA-SHA256", Buffer.from(`${header}.${claims}`), publicKey, Buffer.from(signature, "base64url")));

  let calls = 0;
  const fakeFetch = (async () => {
    calls += 1;
    return new Response(JSON.stringify({ access_token: `token-${calls}`, expires_in: 3600 }), { status: 200 });
  }) as typeof fetch;
  const tokens = new GoogleTokens(account!, PLAY_SCOPE, fakeFetch);
  assert.equal(await tokens.token(1000), "token-1");
  assert.equal(await tokens.token(2000), "token-1");
  assert.equal(await tokens.token(1000 + 3600), "token-2");
});
