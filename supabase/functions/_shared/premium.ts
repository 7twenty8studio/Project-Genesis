// Premium on the server: grants (public.premium_grants) and verified App Store
// subscriptions (public.premium_entitlements). Shared by study-ai and
// premium-sync, so both apply exactly the same rules; the pure parts live in
// appstore.ts (tested under Node).
import {
  APPLE_ROOT_URL,
  DEFAULT_BUNDLE_ID,
  ownerAllows,
  ownershipFor,
  PRODUCT_IDS,
  VerificationError,
  verifyTransaction,
} from "./appstore.ts";

export const BUNDLE_ID = Deno.env.get("GENESIS_BUNDLE_ID") ?? DEFAULT_BUNDLE_ID;
// Development only: accept purchases made with Xcode's local StoreKit testing.
export const ALLOW_XCODE_STOREKIT = Deno.env.get("ALLOW_XCODE_STOREKIT") === "true";
if (ALLOW_XCODE_STOREKIT) {
  console.warn("ALLOW_XCODE_STOREKIT is on: Xcode test purchases unlock Premium. Remove this secret before release.");
}

// The service-role client (supabase-js). Typed loosely so this file needs no
// import of the client library.
// deno-lint-ignore no-explicit-any
type Admin = any;

let appleRoot: Uint8Array | undefined;

/** Apple Root CA - G3, downloaded once per instance; a failed download is retried next time. */
export async function appleRootCertificate(): Promise<Uint8Array> {
  if (appleRoot) return appleRoot;
  const response = await fetch(APPLE_ROOT_URL);
  if (!response.ok) throw new Error(`Apple root certificate: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length < 400 || bytes[0] !== 0x30) throw new Error("Apple root certificate: unexpected download");
  appleRoot = bytes;
  return bytes;
}

/** An active grant from the owner (no end date, or one in the future). */
export async function activeGrant(admin: Admin, userID: string): Promise<{ expiresAt: string | null } | null> {
  const { data: grant } = await admin
    .from("premium_grants")
    .select("expires_at")
    .eq("user_id", userID)
    .maybeSingle();
  if (grant && (!grant.expires_at || new Date(grant.expires_at).getTime() > Date.now())) {
    return { expiresAt: grant.expires_at ?? null };
  }
  return null;
}

export interface SavedEntitlement {
  expires_at: string;
  updated_at: string;
}

export async function savedEntitlement(admin: Admin, userID: string): Promise<SavedEntitlement | null> {
  const { data } = await admin
    .from("premium_entitlements")
    .select("expires_at, updated_at")
    .eq("user_id", userID)
    .maybeSingle();
  return data ?? null;
}

export async function forgetEntitlement(admin: Admin, userID: string): Promise<void> {
  await admin.from("premium_entitlements").delete().eq("user_id", userID);
}

/**
 * Verifies a signed transaction the app sent and records it for the account.
 * Returns the subscription's end, or null when it belongs to another account
 * (or another account claimed it at the same moment). Throws
 * VerificationError when it's expired, refunded or not valid, and other
 * errors when it couldn't be checked right now (e.g. Apple's certificate
 * didn't download).
 */
export async function claimTransaction(admin: Admin, userID: string, signedTransaction: string): Promise<{ expiresAt: string } | null> {
  const root = await appleRootCertificate();
  const transaction = await verifyTransaction(signedTransaction, {
    appleRoot: root,
    bundleId: BUNDLE_ID,
    productIds: PRODUCT_IDS,
    now: new Date(),
    allowXcode: ALLOW_XCODE_STOREKIT,
  });
  const ownership = ownershipFor(transaction, userID);
  if (!ownership) return null;
  if (ownership.checkOwner) {
    const { data: owner } = await admin
      .from("premium_entitlements")
      .select("user_id")
      .eq("original_transaction_id", ownership.key)
      .maybeSingle();
    if (!ownerAllows(owner?.user_id, userID)) return null;
  }
  const expiresAt = new Date(transaction.expiresDate!).toISOString();
  const { error } = await admin.from("premium_entitlements").upsert({
    user_id: userID,
    original_transaction_id: ownership.key,
    product_id: transaction.productId,
    environment: transaction.environment,
    expires_at: expiresAt,
    updated_at: new Date().toISOString(),
  });
  // A unique clash means another account claimed it at the same moment.
  if (error) return null;
  return { expiresAt };
}

/**
 * Premium for a read-only check (bible-file: downloading a Premium Bible).
 * A current App Store subscription's signed transaction is enough on its own
 * (Premium works without an account); otherwise a signed-in account with a
 * grant or a saved, unexpired subscription. Records nothing.
 */
export async function hasPremium(admin: Admin, userID: string | null, signedTransaction?: string): Promise<boolean> {
  if (signedTransaction) {
    try {
      await verifyTransaction(signedTransaction, {
        appleRoot: await appleRootCertificate(),
        bundleId: BUNDLE_ID,
        productIds: PRODUCT_IDS,
        now: new Date(),
        allowXcode: ALLOW_XCODE_STOREKIT,
      });
      return true;
    } catch (error) {
      if (!(error instanceof VerificationError)) console.error("hasPremium", error);
    }
  }
  if (!userID) return false;
  if (await activeGrant(admin, userID)) return true;
  const saved = await savedEntitlement(admin, userID);
  return saved !== null && new Date(saved.expires_at).getTime() > Date.now();
}
