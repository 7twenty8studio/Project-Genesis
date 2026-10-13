// App Store signed data (StoreKit 2 transactions, renewal info and App Store
// Server Notifications V2), verified with Web Crypto against Apple's
// certificate chain. Shared by study-ai, premium-sync and
// appstore-notifications. No Deno APIs here, so it also runs under Node for
// tests (supabase/functions/_shared/appstore.test.ts).
//
// No App Store Server API key is needed: everything Apple signs carries its
// certificate chain (x5c), which is checked up to Apple Root CA - G3.

// ---------------------------------------------------------------------------
// The app's subscriptions

export const DEFAULT_BUNDLE_ID = "com.7twenty8studio.versely";

/** Individual (one person) and Family (shared through Family Sharing) plans. */
export const PRODUCT_IDS: readonly string[] = [
  "com.7twenty8studio.versely.premium.monthly",
  "com.7twenty8studio.versely.premium.yearly",
  "com.7twenty8studio.versely.premium.family.monthly",
  "com.7twenty8studio.versely.premium.family.yearly",
];

export const APPLE_ROOT_URL = "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";

/** A saved subscription is re-verified at least this often, so a refund ends it. */
export const REVERIFY_AFTER_MS = 7 * 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Transactions

export interface VerifiedTransaction {
  /** True when a family member shares the subscription (Family Sharing). */
  familyShared: boolean;
  bundleId: string;
  productId: string;
  originalTransactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment: string;
}

export interface VerifyOptions {
  /** Apple Root CA - G3, DER. */
  appleRoot: Uint8Array;
  bundleId: string;
  productIds: readonly string[];
  now: Date;
  /** Accept Xcode's local StoreKit testing signature (development only). */
  allowXcode?: boolean;
}

/** What checking a signature needs (no product or app rules). */
export interface SignatureOptions {
  appleRoot: Uint8Array;
  now: Date;
  allowXcode?: boolean;
}

export class VerificationError extends Error {}

// Apple marker extensions: the leaf certificate for App Store receipts, and
// the WWDR intermediate.
const APPLE_LEAF_OID = "1.2.840.113635.100.6.11.1";
const APPLE_INTERMEDIATE_OID = "1.2.840.113635.100.6.2.1";

/**
 * Checks a JWS signed by the App Store (the x5c chain up to Apple's root, the
 * Apple marker extensions, validity when signed, and the signature) and
 * returns its payload. Doesn't look at what the payload says.
 */
export async function verifySignedData(jws: string, options: SignatureOptions): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new VerificationError("Not a JWS.");
  const header = JSON.parse(decodeText(base64UrlDecode(parts[0])));
  if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length === 0) {
    throw new VerificationError("Unexpected JWS header.");
  }
  const payload = JSON.parse(decodeText(base64UrlDecode(parts[1])));
  if (typeof payload !== "object" || payload === null) throw new VerificationError("Unexpected JWS payload.");
  const certificates = (header.x5c as string[]).map((c) => parseCertificate(base64Decode(c)));
  const leaf = certificates[0];

  const isXcode = payload.environment === "Xcode";
  if (isXcode) {
    if (!options.allowXcode) throw new VerificationError("Xcode test transactions aren't accepted.");
  } else {
    if (certificates.length !== 3) throw new VerificationError("Expected a three-certificate chain.");
    const [, intermediate, root] = certificates;
    if (!equalBytes(root.der, options.appleRoot)) throw new VerificationError("The chain doesn't end at Apple's root.");
    if (!leaf.extensionOIDs.includes(APPLE_LEAF_OID)) throw new VerificationError("Leaf certificate isn't an App Store certificate.");
    if (!intermediate.extensionOIDs.includes(APPLE_INTERMEDIATE_OID)) throw new VerificationError("Intermediate isn't Apple's.");
    const signedAt = new Date(typeof payload.signedDate === "number" ? payload.signedDate : options.now.getTime());
    for (const cert of certificates) {
      if (signedAt < cert.notBefore || signedAt > cert.notAfter) throw new VerificationError("A certificate wasn't valid when this was signed.");
    }
    if (!(await verifyCertificateSignature(leaf, intermediate))) throw new VerificationError("Leaf certificate signature is invalid.");
    if (!(await verifyCertificateSignature(intermediate, root))) throw new VerificationError("Intermediate certificate signature is invalid.");
  }

  const key = await importPublicKey(leaf);
  const signature = base64UrlDecode(parts[2]);
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, toArrayBuffer(signature), toArrayBuffer(signed));
  if (!valid) throw new VerificationError("Signature is invalid.");
  return payload as Record<string, unknown>;
}

/** The fields Versely uses from a transaction payload (JWSTransactionDecodedPayload). */
export function transactionFromPayload(payload: Record<string, unknown>): VerifiedTransaction {
  return {
    familyShared: payload.inAppOwnershipType === "FAMILY_SHARED",
    bundleId: String(payload.bundleId ?? ""),
    productId: String(payload.productId ?? ""),
    originalTransactionId: String(payload.originalTransactionId ?? ""),
    expiresDate: typeof payload.expiresDate === "number" ? payload.expiresDate : undefined,
    revocationDate: typeof payload.revocationDate === "number" ? payload.revocationDate : undefined,
    appAccountToken: typeof payload.appAccountToken === "string" ? payload.appAccountToken.toLowerCase() : undefined,
    environment: String(payload.environment ?? ""),
  };
}

/**
 * A current Premium subscription, as the app sends it: signed by Apple, for
 * this app and one of its Premium products, not refunded and not expired.
 */
export async function verifyTransaction(jws: string, options: VerifyOptions): Promise<VerifiedTransaction> {
  const payload = await verifySignedData(jws, options);
  const transaction = transactionFromPayload(payload);
  if (transaction.bundleId !== options.bundleId) throw new VerificationError("Wrong app.");
  if (!options.productIds.includes(transaction.productId)) throw new VerificationError("Not a Premium product.");
  if (transaction.revocationDate) throw new VerificationError("The purchase was refunded or revoked.");
  if (!transaction.expiresDate || transaction.expiresDate <= options.now.getTime()) throw new VerificationError("The subscription has expired.");
  if (!transaction.originalTransactionId) throw new VerificationError("Missing transaction id.");
  return transaction;
}

// ---------------------------------------------------------------------------
// Which account a subscription belongs to

/**
 * The premium_entitlements key for a transaction presented by an account, or
 * null when the purchase belongs to another account.
 *
 * - Family members sharing a subscription carry the purchaser's details, so
 *   each gets their own key ("<original>:family:<user>") and the account
 *   checks below apply only to the purchaser.
 * - A purchase made while signed in carries the account id
 *   (appAccountToken); it must match.
 * - `checkOwner`: one subscription unlocks one account, so the caller looks
 *   up who holds the key already; the first to present it keeps it
 *   (`ownerAllows`).
 */
export function ownershipFor(transaction: VerifiedTransaction, userID: string): { key: string; checkOwner: boolean } | null {
  if (transaction.familyShared) {
    return { key: familyKey(transaction.originalTransactionId, userID), checkOwner: false };
  }
  if (transaction.appAccountToken && transaction.appAccountToken !== userID.toLowerCase()) return null;
  return { key: transaction.originalTransactionId, checkOwner: true };
}

/** A family member's key for a shared subscription. */
export function familyKey(originalTransactionId: string, userID: string): string {
  return `${originalTransactionId}:family:${userID}`;
}

/** The pattern (SQL LIKE) matching every family member's key for a subscription. */
export function familyKeyPattern(originalTransactionId: string): string | null {
  // Transaction ids are digits; anything else can't be put in a pattern safely.
  if (!/^[0-9A-Za-z.-]+$/.test(originalTransactionId)) return null;
  return `${originalTransactionId}:family:%`;
}

/** Whoever holds the key already (if anyone) lets this account have it. */
export function ownerAllows(existingOwner: string | null | undefined, userID: string): boolean {
  return !existingOwner || existingOwner === userID;
}

// ---------------------------------------------------------------------------
// App Store Server Notifications V2

export interface RenewalInfo {
  originalTransactionId: string;
  autoRenewStatus?: number;
  /** Billing grace period end, while Apple retries a failed renewal. */
  gracePeriodExpiresDate?: number;
}

export interface DecodedNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  signedDate?: number;
  /** "Sandbox" or "Production". */
  environment: string;
  bundleId: string;
  transaction?: VerifiedTransaction;
  renewal?: RenewalInfo;
}

/**
 * Verifies a notification's signedPayload and the signed transaction and
 * renewal info inside it (each with its own Apple chain). Xcode signatures
 * are never accepted here. Throws VerificationError (or a parse error) for
 * anything that doesn't verify.
 */
export async function decodeNotification(signedPayload: string, options: { appleRoot: Uint8Array; now: Date }): Promise<DecodedNotification> {
  const signature = { appleRoot: options.appleRoot, now: options.now, allowXcode: false };
  const payload = await verifySignedData(signedPayload, signature);
  if (typeof payload.notificationType !== "string" || typeof payload.notificationUUID !== "string") {
    throw new VerificationError("Not an App Store notification.");
  }
  const data = (typeof payload.data === "object" && payload.data !== null ? payload.data : {}) as Record<string, unknown>;
  const notification: DecodedNotification = {
    notificationType: payload.notificationType,
    subtype: typeof payload.subtype === "string" ? payload.subtype : undefined,
    notificationUUID: payload.notificationUUID,
    signedDate: typeof payload.signedDate === "number" ? payload.signedDate : undefined,
    environment: String(data.environment ?? ""),
    bundleId: String(data.bundleId ?? ""),
  };
  if (typeof data.signedTransactionInfo === "string") {
    notification.transaction = transactionFromPayload(await verifySignedData(data.signedTransactionInfo, signature));
  }
  if (typeof data.signedRenewalInfo === "string") {
    const renewal = await verifySignedData(data.signedRenewalInfo, signature);
    notification.renewal = {
      originalTransactionId: String(renewal.originalTransactionId ?? ""),
      autoRenewStatus: typeof renewal.autoRenewStatus === "number" ? renewal.autoRenewStatus : undefined,
      gracePeriodExpiresDate: typeof renewal.gracePeriodExpiresDate === "number" ? renewal.gracePeriodExpiresDate : undefined,
    };
  }
  return notification;
}

// --- Minimal DER / X.509 reading -------------------------------------------

interface Node {
  tag: number;
  /** Offset of the tag byte. */
  start: number;
  /** Offset of the content. */
  contentStart: number;
  end: number;
}

function readNode(bytes: Uint8Array, offset: number): Node {
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let contentStart = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new VerificationError("Unsupported DER length.");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[offset + 2 + i];
    contentStart += count;
  }
  const end = contentStart + length;
  if (end > bytes.length) throw new VerificationError("Truncated DER.");
  return { tag, start: offset, contentStart, end };
}

function children(bytes: Uint8Array, node: Node): Node[] {
  const result: Node[] = [];
  let offset = node.contentStart;
  while (offset < node.end) {
    const child = readNode(bytes, offset);
    result.push(child);
    offset = child.end;
  }
  return result;
}

function oidString(bytes: Uint8Array): string {
  const parts: number[] = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    value = value * 128 + (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function parseTime(bytes: Uint8Array, node: Node): Date {
  const text = decodeText(bytes.slice(node.contentStart, node.end));
  if (node.tag === 0x17) {
    // UTCTime YYMMDDHHMMSSZ
    const year = Number(text.slice(0, 2));
    return new Date(Date.UTC(year >= 50 ? 1900 + year : 2000 + year, Number(text.slice(2, 4)) - 1, Number(text.slice(4, 6)), Number(text.slice(6, 8)), Number(text.slice(8, 10)), Number(text.slice(10, 12))));
  }
  // GeneralizedTime YYYYMMDDHHMMSSZ
  return new Date(Date.UTC(Number(text.slice(0, 4)), Number(text.slice(4, 6)) - 1, Number(text.slice(6, 8)), Number(text.slice(8, 10)), Number(text.slice(10, 12)), Number(text.slice(12, 14))));
}

export interface Certificate {
  der: Uint8Array;
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  spki: Uint8Array;
  curve: string;
  notBefore: Date;
  notAfter: Date;
  extensionOIDs: string[];
}

export function parseCertificate(der: Uint8Array): Certificate {
  const root = readNode(der, 0);
  const [tbsNode, algorithmNode, signatureNode] = children(der, root);
  const algorithm = oidString(der.slice(children(der, algorithmNode)[0].contentStart, children(der, algorithmNode)[0].end));
  // BIT STRING: first content byte is the count of unused bits.
  const signature = der.slice(signatureNode.contentStart + 1, signatureNode.end);

  const fields = children(der, tbsNode);
  let index = fields[0].tag === 0xa0 ? 1 : 0; // optional [0] version
  index += 3; // serialNumber, signature algorithm, issuer
  const validity = children(der, fields[index]);
  index += 2; // validity, subject
  const spkiNode = fields[index];
  const spkiAlgorithm = children(der, children(der, spkiNode)[0]);
  const curve = spkiAlgorithm.length > 1 ? oidString(der.slice(spkiAlgorithm[1].contentStart, spkiAlgorithm[1].end)) : "";

  const extensionOIDs: string[] = [];
  const extensionsWrapper = fields.find((f) => f.tag === 0xa3);
  if (extensionsWrapper) {
    const sequence = children(der, extensionsWrapper)[0];
    for (const extension of children(der, sequence)) {
      const oidNode = children(der, extension)[0];
      extensionOIDs.push(oidString(der.slice(oidNode.contentStart, oidNode.end)));
    }
  }

  return {
    der,
    tbs: der.slice(tbsNode.start, tbsNode.end),
    signatureAlgorithm: algorithm,
    signature,
    spki: der.slice(spkiNode.start, spkiNode.end),
    curve,
    notBefore: parseTime(der, validity[0]),
    notAfter: parseTime(der, validity[1]),
    extensionOIDs,
  };
}

const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const HASHES: Record<string, string> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

function importPublicKey(cert: Certificate): Promise<CryptoKey> {
  const curve = CURVES[cert.curve];
  if (!curve) throw new VerificationError("Unsupported key type.");
  return crypto.subtle.importKey("spki", toArrayBuffer(cert.spki), { name: "ECDSA", namedCurve: curve.name }, false, ["verify"]);
}

async function verifyCertificateSignature(cert: Certificate, issuer: Certificate): Promise<boolean> {
  const hash = HASHES[cert.signatureAlgorithm];
  const curve = CURVES[issuer.curve];
  if (!hash || !curve) throw new VerificationError("Unsupported certificate signature.");
  const key = await importPublicKey(issuer);
  const signature = derSignatureToRaw(cert.signature, curve.size);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, toArrayBuffer(signature), toArrayBuffer(cert.tbs));
}

/** ECDSA signatures in certificates are DER SEQUENCE { r, s }; Web Crypto wants r || s. */
export function derSignatureToRaw(der: Uint8Array, size: number): Uint8Array {
  const sequence = readNode(der, 0);
  const [r, s] = children(der, sequence);
  const out = new Uint8Array(size * 2);
  const put = (node: Node, at: number) => {
    let value = der.slice(node.contentStart, node.end);
    while (value.length > size && value[0] === 0) value = value.slice(1);
    out.set(value, at + size - value.length);
  };
  put(r, 0);
  put(s, size);
  return out;
}

// --- Encoding helpers --------------------------------------------------------

function base64Decode(text: string): Uint8Array {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlDecode(text: string): Uint8Array {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  return base64Decode(padded);
}

function decodeText(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}
