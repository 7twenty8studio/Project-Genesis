// Tests for lib.ts. Run with Node 22+ (needs openssl on the PATH):
//   node --experimental-strip-types --test supabase/functions/group-notify/lib.test.ts
import { execFileSync } from "node:child_process";
import { createPublicKey, verify } from "node:crypto";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import { test } from "node:test";
import { apnsHost, apnsToken, isDeadToken, notificationPayload, NotifyError, parseNotifyRequest, pemToDer } from "./lib.ts";

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
  assert.equal(payload.genesis.groupID, "g1");
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
