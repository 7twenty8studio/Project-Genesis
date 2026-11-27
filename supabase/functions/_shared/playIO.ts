// Google Play subscriptions against the database and Google's API, shared by
// play-sync and play-notifications so both apply the same rules (the pure
// parts are in play.ts, tested under Node).
//
// Secrets: GOOGLE_PLAY_SERVICE_ACCOUNT (the JSON key of a service account
// invited to the Play Console with "View financial data" and "Manage orders
// and subscriptions"), optional GOOGLE_PLAY_PACKAGE (defaults to the app id).
import { GoogleTokens, parseServiceAccount, PLAY_SCOPE } from "./google.ts";
import {
  acknowledgeURL,
  DEFAULT_PACKAGE_NAME,
  evaluateSubscription,
  PLAY_PRODUCT_IDS,
  type PlaySubscription,
  playKey,
  type SubscriptionPurchaseV2,
  subscriptionURL,
} from "./play.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export const PLAY_PACKAGE = Deno.env.get("GOOGLE_PLAY_PACKAGE") ?? DEFAULT_PACKAGE_NAME;
const account = parseServiceAccount(Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT"));
const tokens = account ? new GoogleTokens(account, PLAY_SCOPE) : undefined;

export class PlayNotConfigured extends Error {}

export function playConfigured(): boolean {
  return tokens !== undefined;
}

/** The Play Developer API's answer for a purchase token; null when Google doesn't know it. */
export async function fetchSubscription(purchaseToken: string): Promise<SubscriptionPurchaseV2 | null> {
  if (!tokens) throw new PlayNotConfigured("GOOGLE_PLAY_SERVICE_ACCOUNT isn't set.");
  const response = await fetch(subscriptionURL(PLAY_PACKAGE, purchaseToken), {
    headers: { authorization: `Bearer ${await tokens.token()}` },
  });
  if (response.status === 404 || response.status === 410 || response.status === 400) return null;
  if (!response.ok) throw new Error(`Play Developer API: HTTP ${response.status}`);
  return await response.json();
}

/** Acknowledges a new purchase (Play refunds unacknowledged ones after three days); failures are left to the app's own acknowledgement. */
export async function acknowledge(subscription: PlaySubscription, purchaseToken: string): Promise<void> {
  if (subscription.acknowledged || !tokens) return;
  const response = await fetch(acknowledgeURL(PLAY_PACKAGE, subscription.productId, purchaseToken), {
    method: "POST",
    headers: { authorization: `Bearer ${await tokens.token()}`, "content-type": "application/json" },
    body: "{}",
  }).catch(() => null);
  if (response && !response.ok) console.warn(`Play acknowledge: HTTP ${response.status}`);
}

/**
 * Verifies a purchase token the app sent and records it for the account.
 * Returns the subscription's end, or null when another account already
 * holds it. Throws PlayVerificationError when it doesn't unlock Premium.
 * An App Store subscription that lasts longer stays on file (one row per
 * account), and the answer is then its end.
 */
export async function claimPlayPurchase(admin: Admin, userID: string, purchaseToken: string): Promise<{ expiresAt: string } | null> {
  const subscription = evaluateSubscription(await fetchSubscription(purchaseToken), {
    productIds: PLAY_PRODUCT_IDS,
    userID,
    now: new Date(),
  });
  const key = playKey(purchaseToken);
  const { data: holder } = await admin
    .from("premium_entitlements")
    .select("user_id")
    .eq("original_transaction_id", key)
    .maybeSingle();
  if (holder && holder.user_id !== userID) return null;

  await acknowledge(subscription, purchaseToken);

  const { data: saved } = await admin
    .from("premium_entitlements")
    .select("store, expires_at")
    .eq("user_id", userID)
    .maybeSingle();
  if (saved && saved.store === "app_store" && Date.parse(saved.expires_at) > Date.parse(subscription.expiresAt)) {
    return { expiresAt: saved.expires_at };
  }
  const { error } = await admin.from("premium_entitlements").upsert({
    user_id: userID,
    original_transaction_id: key,
    product_id: subscription.productId,
    environment: subscription.environment,
    expires_at: subscription.expiresAt,
    store: "google_play",
    updated_at: new Date().toISOString(),
  });
  // A unique clash means another account claimed it at the same moment.
  if (error) return null;
  return { expiresAt: subscription.expiresAt };
}
