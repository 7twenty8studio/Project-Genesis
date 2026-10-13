// Tests for lib.ts (what each notification does). Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/appstore-notifications/lib.test.ts
// (Verifying the signed payloads is tested in _shared/appstore.test.ts.)
import assert from "node:assert/strict";
import { test } from "node:test";
import type { DecodedNotification, VerifiedTransaction } from "../_shared/appstore.ts";
import { notificationAction } from "./lib.ts";

const now = new Date("2026-10-15T12:00:00Z");
const day = 86_400_000;
const account = "6f9619ff-8b86-d011-b42d-00c04fc964ff";
const options = {
  bundleId: "com.7twenty8studio.versely",
  productIds: ["com.7twenty8studio.versely.premium.monthly", "com.7twenty8studio.versely.premium.family.yearly"],
  environments: ["Production", "Sandbox"],
  now,
};

const transaction: VerifiedTransaction = {
  familyShared: false,
  bundleId: "com.7twenty8studio.versely",
  productId: "com.7twenty8studio.versely.premium.monthly",
  originalTransactionId: "2000000123",
  expiresDate: now.getTime() + 30 * day,
  appAccountToken: account,
  environment: "Production",
};

function note(type: string, subtype?: string, changes: Partial<VerifiedTransaction> = {}, extra: Partial<DecodedNotification> = {}): DecodedNotification {
  return {
    notificationType: type,
    subtype,
    notificationUUID: "uuid",
    environment: "Production",
    bundleId: "com.7twenty8studio.versely",
    transaction: { ...transaction, ...changes },
    ...extra,
  };
}

test("a new subscription extends rows and can start the purchaser's", () => {
  assert.deepEqual(notificationAction(note("SUBSCRIBED", "INITIAL_BUY"), options), {
    kind: "extend",
    originalTransactionId: "2000000123",
    environment: "Production",
    familyOnly: false,
    productId: "com.7twenty8studio.versely.premium.monthly",
    expiresAt: now.getTime() + 30 * day,
    claimFor: account,
  });
});

test("bought while signed out: no account to start a row for", () => {
  const action = notificationAction(note("SUBSCRIBED", "RESUBSCRIBE", { appAccountToken: undefined }), options);
  assert.equal(action.kind, "extend");
  assert.ok(!("claimFor" in action));
  const odd = notificationAction(note("SUBSCRIBED", "INITIAL_BUY", { appAccountToken: "not-a-uuid" }), options);
  assert.ok(!("claimFor" in odd));
});

test("renewals move the end date on", () => {
  const action = notificationAction(note("DID_RENEW", undefined, { expiresDate: now.getTime() + 60 * day }), options);
  assert.equal(action.kind, "extend");
  if (action.kind === "extend") assert.equal(action.expiresAt, now.getTime() + 60 * day);
});

test("turning auto-renew off keeps access to the end of the period", () => {
  const action = notificationAction(note("DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_DISABLED"), options);
  assert.equal(action.kind, "extend");
  if (action.kind === "extend") assert.equal(action.claimFor, undefined, "only purchases start rows");
});

test("a billing grace period extends access to its end", () => {
  const grace = now.getTime() + 16 * day;
  const action = notificationAction(
    note("DID_FAIL_TO_RENEW", "GRACE_PERIOD", { expiresDate: now.getTime() - day }, { renewal: { originalTransactionId: "2000000123", gracePeriodExpiresDate: grace } }),
    options,
  );
  assert.equal(action.kind, "extend");
  if (action.kind === "extend") assert.equal(action.expiresAt, grace);
});

test("a failed renewal without grace changes nothing", () => {
  const action = notificationAction(note("DID_FAIL_TO_RENEW", undefined, { expiresDate: now.getTime() - day }), options);
  assert.deepEqual(action, { kind: "ignore", reason: "billing_retry" });
});

test("expiry, the end of grace, refunds and revocation remove rows up to that period", () => {
  for (const type of ["EXPIRED", "GRACE_PERIOD_EXPIRED", "REFUND", "REVOKE"]) {
    const action = notificationAction(note(type, undefined, { expiresDate: now.getTime() - day }), options);
    assert.equal(action.kind, "remove", type);
    if (action.kind === "remove") assert.equal(action.upTo, now.getTime() - day, type);
  }
});

test("the end of grace covers the grace period", () => {
  const grace = now.getTime() - 1000;
  const action = notificationAction(
    note("GRACE_PERIOD_EXPIRED", undefined, { expiresDate: now.getTime() - 16 * day }, { renewal: { originalTransactionId: "2000000123", gracePeriodExpiresDate: grace } }),
    options,
  );
  assert.equal(action.kind, "remove");
  if (action.kind === "remove") assert.equal(action.upTo, grace);
});

test("Family Sharing ending touches only family members' rows", () => {
  const action = notificationAction(note("REVOKE", undefined, { familyShared: true, productId: "com.7twenty8studio.versely.premium.family.yearly" }), options);
  assert.equal(action.kind, "remove");
  if (action.kind === "remove") assert.equal(action.familyOnly, true);
  const renewed = notificationAction(note("DID_RENEW", undefined, { familyShared: true, productId: "com.7twenty8studio.versely.premium.family.yearly" }), options);
  assert.equal(renewed.kind, "extend");
  if (renewed.kind === "extend") {
    assert.equal(renewed.familyOnly, true);
    assert.equal(renewed.claimFor, undefined, "family members' tokens aren't their own");
  }
});

test("a revoked transaction in an active notification removes rather than extends", () => {
  const action = notificationAction(note("DID_RENEW", undefined, { revocationDate: now.getTime() }), options);
  assert.equal(action.kind, "remove");
});

test("an active notification for a period already over changes nothing", () => {
  const action = notificationAction(note("DID_RENEW", undefined, { expiresDate: now.getTime() - 1 }), options);
  assert.deepEqual(action, { kind: "ignore", reason: "already_ended" });
});

test("tests, other apps, other products and other environments are ignored", () => {
  assert.deepEqual(notificationAction({ notificationType: "TEST", notificationUUID: "u", environment: "Sandbox", bundleId: "com.7twenty8studio.versely" }, options), { kind: "ignore", reason: "test" });
  assert.deepEqual(notificationAction(note("SUBSCRIBED", undefined, {}, { bundleId: "com.example.other" }), options), { kind: "ignore", reason: "other_app" });
  assert.deepEqual(notificationAction(note("SUBSCRIBED", undefined, { bundleId: "com.example.other" }), options), { kind: "ignore", reason: "other_app" });
  assert.deepEqual(notificationAction(note("SUBSCRIBED", undefined, { productId: "com.7twenty8studio.versely.coins" }), options), { kind: "ignore", reason: "other_product" });
  assert.deepEqual(notificationAction(note("SUBSCRIBED", undefined, {}, { environment: "Sandbox" }), { ...options, environments: ["Production"] }), { kind: "ignore", reason: "environment" });
  assert.deepEqual(notificationAction(note("SUBSCRIBED", undefined, {}, { transaction: undefined }), options), { kind: "ignore", reason: "no_transaction" });
});

test("notifications Versely doesn't act on", () => {
  for (const type of ["CONSUMPTION_REQUEST", "REFUND_DECLINED", "RENEWAL_EXTENSION", "SOMETHING_NEW"]) {
    assert.deepEqual(notificationAction(note(type), options), { kind: "ignore", reason: "not_relevant" }, type);
  }
});

test("the same notification twice gives the same action", () => {
  const first = notificationAction(note("DID_RENEW"), options);
  const again = notificationAction(note("DID_RENEW"), options);
  assert.deepEqual(first, again);
});
