// Tests for lib.ts. Run with Node 22+ (needs openssl on the PATH):
//   node --experimental-strip-types --test supabase/functions/group-notify/lib.test.ts
import { execFileSync } from "node:child_process";
import { createPublicKey, verify } from "node:crypto";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import { test } from "node:test";
import { apnsHost, apnsToken, isDeadToken, notificationPayload, NotifyError, parseNotifyRequest, pemToDer, parseNudgeRequest, nudgePayload, NUDGE_BODY_KEY } from "./lib.ts";

test("parses the announcement id", () => {
  assert.equal(parseNotifyRequest({ announcementID: "AAAAAAAA-0000-0000-0000-000000000001" }).announcementID, "aaaaaaaa-0000-0000-0000-000000000001");
  assert.throws(() => parseNotifyRequest({}), NotifyError);
  assert.throws(() => parseNotifyRequest({ announcementID: "1; drop table" }), NotifyError);
});

test("signs an APNs provider token Apple can verify", async () => {
  const folder = mkdtempSync(join(tmpdir(), "apns-"));
  const keyPath = join(folder, "AuthKey.p8");
  execFileSync("openssl", ["genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", keyPath]);
  const pem = readFileSync(keyPath, "utf8");
  const jwt = await apnsToken(pem, "ABC123DEFG", "TEAM123456", 1_700_000_000);
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url").toString()), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url").toString()), { iss: "TEAM123456", iat: 1_700_000_000 });
  const publicKey = createPublicKey(pem);
  const ok = verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url"));
  assert.ok(ok, "signature verifies as raw r||s");
  // A key pasted with literal \n (as some dashboards store it) still works.
  assert.deepEqual(pemToDer(pem.replace(/\n/g, "\\n")), pemToDer(pem));
});

test("builds the notification", () => {
  const payload = notificationPayload("Tuesday Study", { id: "a1", group_id: "g1", title: "Potluck Sunday", body: "Bring a dish" }) as any;
  assert.equal(payload.aps.alert.title, "Tuesday Study");
  assert.equal(payload.aps.alert.subtitle, "Potluck Sunday");
  assert.equal(payload.versely.groupID, "g1");
  const long = notificationPayload("G", { id: "a", group_id: "g", title: "t", body: "x".repeat(500) }) as any;
  assert.ok(long.aps.alert.body.length <= 180);
});

test("hosts and dead tokens", () => {
  assert.equal(apnsHost("sandbox"), "https://api.sandbox.push.apple.com");
  assert.equal(apnsHost("production"), "https://api.push.apple.com");
  assert.ok(isDeadToken(410, undefined));
  assert.ok(isDeadToken(400, "BadDeviceToken"));
  assert.ok(!isDeadToken(429, "TooManyRequests"));
});

test("reads a nudge request, and leaves announcements alone", () => {
  const id = "0f8fad5b-d9cb-469f-a165-70867728950e";
  assert.deepEqual(parseNudgeRequest({ nudgeID: id.toUpperCase() }), { nudgeID: id });
  assert.equal(parseNudgeRequest({ announcementID: id }), null);
  assert.throws(() => parseNudgeRequest({ nudgeID: "nope" }));
});

test("a nudge reads in the receiver's language", () => {
  const payload = nudgePayload("Tuesday Bible Study", "g1", "Ruth") as { aps: { alert: Record<string, unknown> }; versely: Record<string, unknown> };
  assert.equal(payload.aps.alert.title, "Tuesday Bible Study");
  assert.equal(payload.aps.alert["loc-key"], NUDGE_BODY_KEY);
  assert.deepEqual(payload.aps.alert["loc-args"], ["Ruth"]);
  assert.equal(payload.versely.groupID, "g1");
});

test("an Android message carries the announcement and the group's link", async () => {
  const { fcmMessage, isDeadFcmToken, ANDROID_NUDGE_KEY } = await import("./lib.ts");
  const announcement = notificationPayload("Grace Church", { id: "a1", group_id: "g1", title: "Sunday", body: "Bring a friend." });
  const message = fcmMessage("token-1", announcement).message as Record<string, any>;
  assert.equal(message.token, "token-1");
  assert.equal(message.android.notification.title, "Grace Church");
  assert.equal(message.android.notification.body, "Sunday\nBring a friend.");
  assert.equal(message.android.notification.channel_id, "groups");
  assert.equal(message.data.link, "versely://group/g1");
  assert.equal(message.data.announcementID, "a1");

  const nudge = fcmMessage("token-2", nudgePayload("Grace Church", "g1", "Ana")).message as Record<string, any>;
  assert.equal(nudge.android.notification.body_loc_key, ANDROID_NUDGE_KEY);
  assert.deepEqual(nudge.android.notification.body_loc_args, ["Ana"]);
  assert.equal(nudge.android.notification.body, undefined);
  assert.equal(nudge.data.nudge, "true");

  assert.ok(isDeadFcmToken(404, undefined));
  assert.ok(isDeadFcmToken(400, "INVALID_ARGUMENT"));
  assert.ok(!isDeadFcmToken(503, "UNAVAILABLE"));
});
