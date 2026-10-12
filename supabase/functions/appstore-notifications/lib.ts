// Pure logic for appstore-notifications: what each App Store Server
// Notification (V2) means for public.premium_entitlements. No Deno APIs here,
// so it runs under Node for tests (appstore-notifications/lib.test.ts).
import type { DecodedNotification } from "../_shared/appstore.ts";

/**
 * What to do with the rows for a subscription. Rows are matched by original
 * transaction id: the purchaser's row ("<original>") and family members'
 * rows ("<original>:family:<user>"), only in the notification's environment.
 *
 * - extend: set the end date (and product) on matching rows, never moving it
 *   backwards, so notifications arriving late or twice change nothing. With
 *   `claimFor` (a purchase made while signed in carries the account id), the
 *   account gets a row when it has none yet, as premium-sync would give it.
 * - remove: delete matching rows whose end is no later than `upTo` (the
 *   period that ended or was refunded), so a late EXPIRED never removes a
 *   subscription renewed since.
 * - ignore: nothing to change (Apple still gets a 200).
 */
export type NotificationAction =
  | {
    kind: "extend";
    originalTransactionId: string;
    environment: string;
    productId: string;
    expiresAt: number;
    /** Family Sharing: only family members' rows. */
    familyOnly: boolean;
    claimFor?: string;
  }
  | {
    kind: "remove";
    originalTransactionId: string;
    environment: string;
    upTo?: number;
    familyOnly: boolean;
  }
  | { kind: "ignore"; reason: string };

export interface ActionOptions {
  bundleId: string;
  productIds: readonly string[];
  /** Environments accepted ("Production", "Sandbox"). */
  environments: readonly string[];
  now: Date;
}

/** Notifications that mean the subscription is (still) active until its expiresDate. */
const ACTIVE = new Set([
  "SUBSCRIBED", // INITIAL_BUY, RESUBSCRIBE
  "DID_RENEW", // including BILLING_RECOVERY
  "DID_CHANGE_RENEWAL_PREF", // upgrade (immediate) or downgrade (next period)
  "DID_CHANGE_RENEWAL_STATUS", // auto-renew turned on or off: access unchanged
  "OFFER_REDEEMED",
  "RENEWAL_EXTENDED",
  "REFUND_REVERSED",
  "PRICE_INCREASE",
]);

/** Notifications that end access for the period they carry. */
const ENDED = new Set([
  "EXPIRED", // VOLUNTARY, BILLING_RETRY, PRICE_INCREASE, PRODUCT_NOT_FOR_SALE
  "GRACE_PERIOD_EXPIRED",
  "REFUND", // Apple refunded it
  "REVOKE", // Family Sharing ended for this member
]);

/** Notifications that only start a new account row (the purchaser's). */
const CLAIMS = new Set(["SUBSCRIBED", "DID_RENEW", "OFFER_REDEEMED", "REFUND_REVERSED", "DID_CHANGE_RENEWAL_PREF"]);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function notificationAction(notification: DecodedNotification, options: ActionOptions): NotificationAction {
  const type = notification.notificationType;
  if (type === "TEST") return { kind: "ignore", reason: "test" };
  if (notification.bundleId !== options.bundleId) return { kind: "ignore", reason: "other_app" };
  if (!options.environments.includes(notification.environment)) return { kind: "ignore", reason: "environment" };
  const transaction = notification.transaction;
  if (!transaction) return { kind: "ignore", reason: "no_transaction" };
  if (transaction.bundleId !== options.bundleId) return { kind: "ignore", reason: "other_app" };
  if (!options.productIds.includes(transaction.productId)) return { kind: "ignore", reason: "other_product" };
  if (!transaction.originalTransactionId) return { kind: "ignore", reason: "no_transaction" };

  const base = {
    originalTransactionId: transaction.originalTransactionId,
    environment: notification.environment,
    familyOnly: transaction.familyShared,
  };
  const grace = notification.renewal?.gracePeriodExpiresDate;
  const periodEnd = Math.max(transaction.expiresDate ?? 0, grace ?? 0) || undefined;

  if (ENDED.has(type)) return { kind: "remove", ...base, upTo: periodEnd };

  // Billing trouble: with a grace period, access runs to its end; without one
  // the period has ended already (the rows simply run out).
  if (type === "DID_FAIL_TO_RENEW") {
    if (notification.subtype === "GRACE_PERIOD" && grace && grace > options.now.getTime()) {
      return { kind: "extend", ...base, productId: transaction.productId, expiresAt: grace };
    }
    return { kind: "ignore", reason: "billing_retry" };
  }

  if (ACTIVE.has(type)) {
    if (transaction.revocationDate) return { kind: "remove", ...base, upTo: periodEnd };
    if (!periodEnd || periodEnd <= options.now.getTime()) return { kind: "ignore", reason: "already_ended" };
    const token = transaction.appAccountToken;
    const claimFor = CLAIMS.has(type) && !transaction.familyShared && token && UUID.test(token) ? token : undefined;
    return { kind: "extend", ...base, productId: transaction.productId, expiresAt: periodEnd, ...(claimFor ? { claimFor } : {}) };
  }

  // CONSUMPTION_REQUEST, REFUND_DECLINED, RENEWAL_EXTENSION (summary),
  // EXTERNAL_PURCHASE_TOKEN, ONE_TIME_CHARGE and anything new.
  return { kind: "ignore", reason: "not_relevant" };
}
