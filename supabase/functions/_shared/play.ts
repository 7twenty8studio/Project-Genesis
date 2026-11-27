// Google Play subscriptions, the pure rules (Node tests in play.test.ts):
// which products are Premium, what a Play Developer API answer
// (purchases.subscriptionsv2.get) means, and what a Real-time Developer
// Notification asks. The App Store's rules are in appstore.ts; both write
// public.premium_entitlements, keyed so they never meet ("play:<token>").

export const DEFAULT_PACKAGE_NAME = "com.seventwenty8studio.versely";

/**
 * Play subscription products (each with "monthly" and "yearly" base plans).
 * Google Play has no Family Sharing for subscriptions, so the family product
 * is listed only so a plan created for it is honoured; whether Android
 * offers it is the owner's choice (PLAY_SETUP.md).
 */
export const PLAY_PRODUCT_IDS: readonly string[] = [
  "com.7twenty8studio.versely.premium",
  "com.7twenty8studio.versely.premium.family",
];

/** A purchase token as Play gives it: long, URL-safe text. */
export function isPurchaseToken(value: unknown): value is string {
  return typeof value === "string" && value.length >= 20 && value.length <= 4096 && /^[A-Za-z0-9._:-]+$/.test(value);
}

/** The row key for a Play subscription in premium_entitlements. */
export function playKey(purchaseToken: string): string {
  return `play:${purchaseToken}`;
}

export class PlayVerificationError extends Error {
  reason: "not_found" | "wrong_package" | "wrong_product" | "not_active" | "expired" | "wrong_account";

  constructor(reason: PlayVerificationError["reason"]) {
    super(reason);
    this.reason = reason;
  }
}

/** The parts of a SubscriptionPurchaseV2 this needs. */
export interface SubscriptionPurchaseV2 {
  subscriptionState?: string;
  linkedPurchaseToken?: string;
  testPurchase?: unknown;
  acknowledgementState?: string;
  externalAccountIdentifiers?: { obfuscatedExternalAccountId?: string };
  lineItems?: { productId?: string; expiryTime?: string }[];
}

export interface PlaySubscription {
  productId: string;
  expiresAt: string;
  environment: "Production" | "Test";
  linkedPurchaseToken?: string;
  acknowledged: boolean;
}

/**
 * States that unlock Premium. CANCELED still does until its paid period
 * ends; ON_HOLD (payment failed after grace), PAUSED, PENDING and EXPIRED
 * don't. IN_GRACE_PERIOD does (Google keeps access while it retries).
 */
const ACTIVE_STATES = new Set(["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "SUBSCRIPTION_STATE_CANCELED"]);

/**
 * What a Play Developer API answer means for an account. Throws
 * PlayVerificationError when it doesn't unlock Premium (or belongs to
 * another account: the app sets obfuscatedAccountId to the signed-in
 * account's id when buying, as iOS sets appAccountToken).
 */
export function evaluateSubscription(
  purchase: SubscriptionPurchaseV2 | null,
  options: { productIds: readonly string[]; userID: string | null; now: Date },
): PlaySubscription {
  if (!purchase) throw new PlayVerificationError("not_found");
  const items = (purchase.lineItems ?? []).filter((item) => item.productId && options.productIds.includes(item.productId));
  if (items.length === 0) throw new PlayVerificationError("wrong_product");
  if (!ACTIVE_STATES.has(purchase.subscriptionState ?? "")) throw new PlayVerificationError("not_active");
  // The latest end among its Premium line items.
  const latest = items
    .map((item) => ({ productId: item.productId!, end: Date.parse(item.expiryTime ?? "") }))
    .filter((item) => Number.isFinite(item.end))
    .sort((a, b) => b.end - a.end)[0];
  if (!latest || latest.end <= options.now.getTime()) throw new PlayVerificationError("expired");
  const owner = purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId?.toLowerCase();
  if (owner && options.userID && owner !== options.userID.toLowerCase()) throw new PlayVerificationError("wrong_account");
  return {
    productId: latest.productId,
    expiresAt: new Date(latest.end).toISOString(),
    environment: purchase.testPurchase ? "Test" : "Production",
    linkedPurchaseToken: purchase.linkedPurchaseToken || undefined,
    acknowledged: purchase.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
  };
}

/** The Play Developer API address for one subscription purchase. */
export function subscriptionURL(packageName: string, purchaseToken: string): string {
  return `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
}

/** Acknowledging a purchase (Play refunds unacknowledged ones after three days). */
export function acknowledgeURL(packageName: string, productId: string, purchaseToken: string): string {
  return `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${encodeURIComponent(packageName)}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
}

export interface DeveloperNotification {
  packageName: string;
  purchaseToken?: string;
  subscriptionId?: string;
  notificationType?: number;
  test: boolean;
}

/**
 * A Pub/Sub push of a Real-time Developer Notification:
 * { message: { data: base64(JSON) } }. Null when it isn't one. The
 * notification only says which purchase to look at again: Premium is never
 * decided from it, only from the Play Developer API.
 */
export function parseDeveloperNotification(body: unknown): DeveloperNotification | null {
  const data = (body as { message?: { data?: unknown } } | null)?.message?.data;
  if (typeof data !== "string" || data.length > 20_000) return null;
  let decoded: Record<string, unknown>;
  try {
    const binary = atob(data.replace(/-/g, "+").replace(/_/g, "/"));
    decoded = JSON.parse(new TextDecoder().decode(Uint8Array.from(binary, (c) => c.charCodeAt(0))));
  } catch {
    return null;
  }
  if (typeof decoded?.packageName !== "string") return null;
  const subscription = decoded.subscriptionNotification as Record<string, unknown> | undefined;
  return {
    packageName: decoded.packageName,
    purchaseToken: isPurchaseToken(subscription?.purchaseToken) ? subscription.purchaseToken : undefined,
    subscriptionId: typeof subscription?.subscriptionId === "string" ? subscription.subscriptionId : undefined,
    notificationType: typeof subscription?.notificationType === "number" ? subscription.notificationType : undefined,
    test: decoded.testNotification !== undefined,
  };
}

/** Compares two secrets without stopping at the first difference. */
export function sameSecret(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let index = 0; index < Math.max(left.length, right.length); index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}
