// appstore-notifications: App Store Server Notifications V2.
//
// Apple POSTs { signedPayload } here when a subscription starts, renews,
// fails to renew, expires, is refunded or stops being shared. This keeps
// public.premium_entitlements current, so Premium is known on the server
// (public.genesis_is_premium(), used by storage policies) even when the app
// isn't opened.
//
// - There's no user token: deploy with JWT verification off
//     supabase functions deploy appstore-notifications --no-verify-jwt
//   Requests are authenticated instead by verifying signedPayload, and the
//   signed transaction and renewal info inside it, with Apple's certificate
//   chain (supabase/functions/_shared/appstore.ts). Anything that doesn't
//   verify gets 400 and changes nothing.
// - Rows are matched by original transaction id (the purchaser's
//   "<original>" and family members' "<original>:family:<user>"), only in
//   the notification's environment (Production or Sandbox).
// - Idempotent: end dates only move forward, and removals only touch rows
//   whose end is no later than the period that ended, so retries and
//   out-of-order deliveries are harmless. Verified notifications always get
//   200 (Apple retries anything else), even when nothing matched.
// - App Store Connect → the app → App Information → App Store Server
//   Notifications: Version 2, this URL for Production and Sandbox.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { decodeNotification, familyKeyPattern, PRODUCT_IDS } from "../_shared/appstore.ts";
import { appleRootCertificate, BUNDLE_ID } from "../_shared/premium.ts";
import { type NotificationAction, notificationAction } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Both by default: TestFlight and sandbox testers' purchases unlock Premium, as in study-ai.
const ENVIRONMENTS = (Deno.env.get("APPSTORE_ENVIRONMENTS") ?? "Production,Sandbox").split(",").map((e) => e.trim()).filter(Boolean);

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const body = await req.json().catch(() => null);
  const signedPayload = typeof body?.signedPayload === "string" ? body.signedPayload : undefined;
  if (!signedPayload) return json({ error: "Expected { signedPayload }." }, 400);

  // Apple's root certificate couldn't be fetched: a 500 makes Apple retry later.
  let root: Uint8Array;
  try {
    root = await appleRootCertificate();
  } catch (error) {
    console.error("appstore-notifications: Apple root certificate", error);
    return json({ error: "Try again later." }, 500);
  }

  let notification;
  try {
    notification = await decodeNotification(signedPayload, { appleRoot: root, now: new Date() });
  } catch (error) {
    console.warn("appstore-notifications: unverifiable notification", error instanceof Error ? error.message : error);
    return json({ error: "The notification couldn't be verified." }, 400);
  }

  const action = notificationAction(notification, {
    bundleId: BUNDLE_ID,
    productIds: PRODUCT_IDS,
    environments: ENVIRONMENTS,
    now: new Date(),
  });
  const label = `${notification.notificationType}${notification.subtype ? `/${notification.subtype}` : ""} ${notification.notificationUUID}`;
  try {
    const changed = await apply(action);
    console.log(`appstore-notifications: ${label} → ${action.kind}${action.kind === "ignore" ? ` (${action.reason})` : ""}, ${changed} row(s)`);
    return json({ ok: true, action: action.kind, changed });
  } catch (error) {
    // A database failure: let Apple retry (every change here is safe to repeat).
    console.error(`appstore-notifications: ${label} failed`, error);
    return json({ error: "Try again later." }, 500);
  }
});

/** Applies an action; returns how many rows changed. */
async function apply(action: NotificationAction): Promise<number> {
  if (action.kind === "ignore") return 0;
  // The purchaser's row (unless this is a family member's transaction) and
  // family members' rows.
  const filters: { op: "eq" | "like"; value: string }[] = [];
  if (!action.familyOnly) filters.push({ op: "eq", value: action.originalTransactionId });
  const pattern = familyKeyPattern(action.originalTransactionId);
  if (pattern) filters.push({ op: "like", value: pattern });

  let changed = 0;
  if (action.kind === "remove") {
    for (const filter of filters) {
      let query = admin.from("premium_entitlements").delete().eq("environment", action.environment);
      query = filter.op === "eq" ? query.eq("original_transaction_id", filter.value) : query.like("original_transaction_id", filter.value);
      if (action.upTo) query = query.lte("expires_at", new Date(action.upTo).toISOString());
      const { data, error } = await query.select("user_id");
      if (error) throw error;
      changed += data?.length ?? 0;
    }
    return changed;
  }

  // extend
  const expiresAt = new Date(action.expiresAt).toISOString();
  const now = new Date().toISOString();
  for (const filter of filters) {
    let query = admin
      .from("premium_entitlements")
      .update({ expires_at: expiresAt, product_id: action.productId, updated_at: now })
      .eq("environment", action.environment)
      .lte("expires_at", expiresAt);
    query = filter.op === "eq" ? query.eq("original_transaction_id", filter.value) : query.like("original_transaction_id", filter.value);
    const { data, error } = await query.select("user_id");
    if (error) throw error;
    changed += data?.length ?? 0;
  }

  // A purchase made while signed in names its account: record it even if the
  // app hasn't called premium-sync yet. Only when nobody holds this
  // subscription and the account has no row of its own (premium-sync and
  // study-ai decide anything more involved).
  if (action.claimFor && changed === 0) {
    const [{ data: holder, error: holderError }, { data: own, error: ownError }] = await Promise.all([
      admin.from("premium_entitlements").select("user_id").eq("original_transaction_id", action.originalTransactionId).maybeSingle(),
      admin.from("premium_entitlements").select("user_id").eq("user_id", action.claimFor).maybeSingle(),
    ]);
    if (holderError || ownError) throw holderError ?? ownError;
    if (!holder && !own) {
      const { error } = await admin.from("premium_entitlements").insert({
        user_id: action.claimFor,
        original_transaction_id: action.originalTransactionId,
        product_id: action.productId,
        environment: action.environment,
        expires_at: expiresAt,
        updated_at: now,
      });
      // 23503: the token isn't an account here (e.g. deleted); 23505: claimed
      // at the same moment. Either way there's nothing to retry.
      if (error && error.code !== "23503" && error.code !== "23505") throw error;
      if (!error) changed += 1;
    }
  }
  return changed;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
