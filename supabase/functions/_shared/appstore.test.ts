// Tests for appstore.ts (App Store signed data). Run with Node 22+ (needs
// openssl on the PATH):
//   node --experimental-strip-types --test supabase/functions/_shared/appstore.test.ts
// or every server test at once:
//   node --experimental-strip-types --test supabase/functions/*/*.test.ts
import { execFileSync } from "node:child_process";
import { createSign } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  decodeNotification,
  derSignatureToRaw,
  familyKey,
  familyKeyPattern,
  ownerAllows,
  ownershipFor,
  parseCertificate,
  PRODUCT_IDS,
  verifyTransaction,
  VerificationError,
} from "./appstore.ts";

// ---------------------------------------------------------------------------
// App Store transaction verification, against a chain shaped like Apple's.

const dir = mkdtempSync(join(tmpdir(), "appstore-"));
function openssl(...args: string[]) {
  execFileSync("openssl", args, { cwd: dir, stdio: "pipe" });
}
function der(name: string): Uint8Array {
  openssl("x509", "-in", `${name}.pem`, "-outform", "DER", "-out", `${name}.der`);
  return new Uint8Array(readFileSync(join(dir, `${name}.der`)));
}

writeFileSync(join(dir, "ext.cnf"), `
[root]
basicConstraints=critical,CA:true
keyUsage=critical,keyCertSign,cRLSign
[intermediate]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
1.2.840.113635.100.6.2.1=ASN1:NULL
[leaf]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
1.2.840.113635.100.6.11.1=ASN1:NULL
`);
// Root and intermediate on P-384 (signed with SHA-384), leaf on P-256, as Apple does.
openssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key");
openssl("req", "-x509", "-new", "-key", "root.key", "-subj", "/CN=Test Root CA - G3", "-days", "3650", "-sha384", "-out", "root.pem", "-extensions", "root", "-config", "ext.cnf");
openssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "int.key");
openssl("req", "-new", "-key", "int.key", "-subj", "/CN=Test WWDR G6", "-out", "int.csr", "-config", "ext.cnf");
openssl("x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-days", "3650", "-sha384", "-out", "int.pem", "-extfile", "ext.cnf", "-extensions", "intermediate");
openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key");
openssl("req", "-new", "-key", "leaf.key", "-subj", "/CN=Test StoreKit Signing", "-out", "leaf.csr", "-config", "ext.cnf");
openssl("x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key", "-CAcreateserial", "-days", "365", "-sha256", "-out", "leaf.pem", "-extfile", "ext.cnf", "-extensions", "leaf");

const rootDer = der("root");
const chain = [der("leaf"), der("int"), rootDer].map((d) => Buffer.from(d).toString("base64"));
const leafKey = readFileSync(join(dir, "leaf.key"), "utf8");

function base64url(value: string | Buffer): string {
  return Buffer.from(value).toString("base64url");
}

function sign(payload: object, key = leafKey, x5c = chain): string {
  const header = base64url(JSON.stringify({ alg: "ES256", x5c }));
  const body = base64url(JSON.stringify(payload));
  const signer = createSign("SHA256");
  signer.update(`${header}.${body}`);
  // Web Crypto verifies the raw r||s form JWS uses.
  const signature = signer.sign({ key, dsaEncoding: "ieee-p1363" });
  return `${header}.${body}.${base64url(signature)}`;
}

const now = new Date();
const valid = {
  bundleId: "com.7twenty8studio.versely",
  productId: "com.7twenty8studio.versely.premium.yearly",
  originalTransactionId: "2000000123",
  expiresDate: now.getTime() + 86_400_000,
  signedDate: now.getTime(),
  appAccountToken: "6F9619FF-8B86-D011-B42D-00C04FC964FF",
  environment: "Production",
};
const options = {
  appleRoot: rootDer,
  bundleId: "com.7twenty8studio.versely",
  productIds: ["com.7twenty8studio.versely.premium.monthly", "com.7twenty8studio.versely.premium.yearly"],
  now,
};

test("parses certificates", () => {
  const leaf = parseCertificate(der("leaf"));
  assert.equal(leaf.curve, "1.2.840.10045.3.1.7");
  assert.ok(leaf.extensionOIDs.includes("1.2.840.113635.100.6.11.1"));
  assert.ok(leaf.notAfter > now);
});

test("accepts a valid subscription", async () => {
  const transaction = await verifyTransaction(sign(valid), options);
  assert.equal(transaction.productId, valid.productId);
  assert.equal(transaction.appAccountToken, valid.appAccountToken.toLowerCase());
});

test("rejects expired, refunded, other apps and other products", async () => {
  await assert.rejects(verifyTransaction(sign({ ...valid, expiresDate: now.getTime() - 1 }), options), VerificationError);
  await assert.rejects(verifyTransaction(sign({ ...valid, revocationDate: now.getTime() }), options), VerificationError);
  await assert.rejects(verifyTransaction(sign({ ...valid, bundleId: "com.example.other" }), options), VerificationError);
  await assert.rejects(verifyTransaction(sign({ ...valid, productId: "com.7twenty8studio.versely.coins" }), options), VerificationError);
});

test("rejects a tampered payload", async () => {
  const [header, , signature] = sign(valid).split(".");
  const forged = base64url(JSON.stringify({ ...valid, expiresDate: now.getTime() + 10 * 365 * 86_400_000 }));
  await assert.rejects(verifyTransaction(`${header}.${forged}.${signature}`, options), VerificationError);
});

test("rejects a chain that doesn't end at the trusted root", async () => {
  openssl("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "other.key");
  openssl("req", "-x509", "-new", "-key", "other.key", "-subj", "/CN=Someone Else", "-days", "30", "-sha384", "-out", "other.pem", "-extensions", "root", "-config", "ext.cnf");
  await assert.rejects(verifyTransaction(sign(valid), { ...options, appleRoot: der("other") }), VerificationError);
});

test("rejects a self-signed leaf pretending to be Apple's", async () => {
  openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "fake.key");
  openssl("req", "-x509", "-new", "-key", "fake.key", "-subj", "/CN=Fake", "-days", "30", "-sha256", "-out", "fake.pem", "-extensions", "leaf", "-config", "ext.cnf");
  const fakeKey = readFileSync(join(dir, "fake.key"), "utf8");
  const fakeChain = [der("fake"), der("int"), rootDer].map((d) => Buffer.from(d).toString("base64"));
  await assert.rejects(verifyTransaction(sign(valid, fakeKey, fakeChain), options), VerificationError);
});

test("Xcode test transactions only when allowed", async () => {
  const xcode = { ...valid, environment: "Xcode" };
  const selfSigned = [der("fake")].map((d) => Buffer.from(d).toString("base64"));
  const fakeKey = readFileSync(join(dir, "fake.key"), "utf8");
  await assert.rejects(verifyTransaction(sign(xcode, fakeKey, selfSigned), options), VerificationError);
  const accepted = await verifyTransaction(sign(xcode, fakeKey, selfSigned), { ...options, allowXcode: true });
  assert.equal(accepted.environment, "Xcode");
});

test("DER signatures convert to raw r||s", () => {
  // SEQUENCE { INTEGER 0x00 0x80 (leading zero), INTEGER 0x01 }
  const derSig = new Uint8Array([0x30, 0x07, 0x02, 0x02, 0x00, 0x80, 0x02, 0x01, 0x01]);
  const raw = derSignatureToRaw(derSig, 4);
  assert.deepEqual(Array.from(raw), [0, 0, 0, 0x80, 0, 0, 0, 1]);
});

// ---------------------------------------------------------------------------
// The products the app sells

test("the four Premium products", () => {
  assert.deepEqual([...PRODUCT_IDS].sort(), [
    "com.7twenty8studio.versely.premium.family.monthly",
    "com.7twenty8studio.versely.premium.family.yearly",
    "com.7twenty8studio.versely.premium.monthly",
    "com.7twenty8studio.versely.premium.yearly",
  ]);
});

// ---------------------------------------------------------------------------
// Which account a subscription belongs to

const user = "6f9619ff-8b86-d011-b42d-00c04fc964ff";
const purchase = {
  familyShared: false,
  bundleId: "com.7twenty8studio.versely",
  productId: "com.7twenty8studio.versely.premium.yearly",
  originalTransactionId: "2000000123",
  expiresDate: now.getTime() + 86_400_000,
  environment: "Production",
};

test("the purchaser's account owns the subscription", () => {
  assert.deepEqual(ownershipFor({ ...purchase, appAccountToken: user }, user.toUpperCase()), { key: "2000000123", checkOwner: true });
  assert.deepEqual(ownershipFor(purchase, user), { key: "2000000123", checkOwner: true }, "bought while signed out");
  assert.equal(ownershipFor({ ...purchase, appAccountToken: "00000000-0000-0000-0000-000000000001" }, user), null);
});

test("family members each get their own key, whatever the purchaser's token", () => {
  const shared = { ...purchase, familyShared: true, appAccountToken: "00000000-0000-0000-0000-000000000001" };
  assert.deepEqual(ownershipFor(shared, user), { key: `2000000123:family:${user}`, checkOwner: false });
  assert.equal(familyKey("2000000123", user), `2000000123:family:${user}`);
  assert.equal(familyKeyPattern("2000000123"), "2000000123:family:%");
  assert.equal(familyKeyPattern("12%_3"), null);
});

test("the first account to present a subscription keeps it", () => {
  assert.ok(ownerAllows(null, user));
  assert.ok(ownerAllows(undefined, user));
  assert.ok(ownerAllows(user, user));
  assert.ok(!ownerAllows("someone-else", user));
});

// ---------------------------------------------------------------------------
// App Store Server Notifications V2

function notification(type: string, subtype?: string, transaction: object = valid, renewal?: object, data: object = {}) {
  return sign({
    notificationType: type,
    subtype,
    notificationUUID: "c2f1d5d2-0000-4000-8000-000000000001",
    version: "2.0",
    signedDate: now.getTime(),
    data: {
      bundleId: "com.7twenty8studio.versely",
      environment: "Sandbox",
      signedTransactionInfo: sign(transaction),
      ...(renewal ? { signedRenewalInfo: sign(renewal) } : {}),
      ...data,
    },
  });
}

test("decodes a notification with its transaction and renewal info", async () => {
  const grace = now.getTime() + 16 * 86_400_000;
  const decoded = await decodeNotification(
    notification("DID_FAIL_TO_RENEW", "GRACE_PERIOD", { ...valid, expiresDate: now.getTime() - 1 }, { originalTransactionId: "2000000123", gracePeriodExpiresDate: grace, autoRenewStatus: 1, signedDate: now.getTime() }),
    { appleRoot: rootDer, now },
  );
  assert.equal(decoded.notificationType, "DID_FAIL_TO_RENEW");
  assert.equal(decoded.subtype, "GRACE_PERIOD");
  assert.equal(decoded.environment, "Sandbox");
  assert.equal(decoded.bundleId, "com.7twenty8studio.versely");
  assert.equal(decoded.transaction?.originalTransactionId, "2000000123");
  assert.equal(decoded.transaction?.expiresDate, now.getTime() - 1, "expired transactions still decode here");
  assert.equal(decoded.renewal?.gracePeriodExpiresDate, grace);
});

test("a TEST notification has no transaction", async () => {
  const decoded = await decodeNotification(
    sign({ notificationType: "TEST", notificationUUID: "u", signedDate: now.getTime(), data: { bundleId: "com.7twenty8studio.versely", environment: "Production" } }),
    { appleRoot: rootDer, now },
  );
  assert.equal(decoded.notificationType, "TEST");
  assert.equal(decoded.transaction, undefined);
});

test("rejects notifications that aren't signed by Apple, inside or out", async () => {
  const fakeKey = readFileSync(join(dir, "fake.key"), "utf8");
  const fakeChain = [der("fake"), der("int"), rootDer].map((d) => Buffer.from(d).toString("base64"));
  // The outer payload forged.
  await assert.rejects(decodeNotification(sign({ notificationType: "SUBSCRIBED", notificationUUID: "u", data: {} }, fakeKey, fakeChain), { appleRoot: rootDer, now }), VerificationError);
  // A genuine envelope can't carry a forged transaction.
  const forgedInside = sign({
    notificationType: "SUBSCRIBED",
    notificationUUID: "u",
    signedDate: now.getTime(),
    data: { bundleId: "com.7twenty8studio.versely", environment: "Production", signedTransactionInfo: sign(valid, fakeKey, fakeChain) },
  });
  await assert.rejects(decodeNotification(forgedInside, { appleRoot: rootDer, now }), VerificationError);
  // Xcode signatures are never accepted for notifications.
  const selfSigned = [der("fake")].map((d) => Buffer.from(d).toString("base64"));
  await assert.rejects(decodeNotification(sign({ notificationType: "TEST", notificationUUID: "u", environment: "Xcode", data: {} }, fakeKey, selfSigned), { appleRoot: rootDer, now }), VerificationError);
  // Not a notification at all.
  await assert.rejects(decodeNotification(sign(valid), { appleRoot: rootDer, now }), VerificationError);
});
