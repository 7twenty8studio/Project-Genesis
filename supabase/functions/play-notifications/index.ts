// play-notifications: Google Play Real-time Developer Notifications.
//
// Google Play publishes to a Pub/Sub topic when a subscription renews, is
// cancelled, goes on hold, recovers, is revoked or expires; a push
// subscription POSTs each message here:
//   https://<project>.supabase.co/functions/v1/play-notifications?secret=<PLAY_RTDN_SECRET>
//
// - There's no user token: deploy with JWT verification off
//     supabase functions deploy play-notifications --no-verify-jwt
//   A request without the secret gets 401 and changes nothing. Even with it,
//   a message only says which purchase to look at again: Premium is decided
//   from the Play Developer API's answer (_shared/playIO.ts), never from the
//   message, so a forged one can't grant anything.
// - Rows are matched by key ("play:<purchase token>"). A purchase that isn't
//   on file yet is recorded for the account the app named when buying
//   (obfuscatedAccountId), so Premium is known even before the app syncs.
// - Answers 200 for every message it has handled (or can ignore), and 500
//   when Google couldn't be asked, so Pub/Sub retries it.
// - Secrets: PLAY_RTDN_SECRET, GOOGLE_PLAY_SERVICE_ACCOUNT (PLAY_SETUP.md).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { evaluateSubscription, parseDeveloperNotification, PLAY_PRODUCT_IDS, playKey, PlayVerificationError, sameSecret } from "../_shared/play.ts";
import { acknowledge, fetchSubscription, PLAY_PACKAGE, playConfigured } from "../_shared/playIO.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SECRET = Deno.env.get("PLAY_RTDN_SECRET") ?? "";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const given = new URL(req.url).searchParams.get("secret") ?? "";
  if (SECRET.length < 24 || !sameSecret(given, SECRET)) return json({ error: "Not allowed." }, 401);

  const notification = parseDeveloperNotification(await req.json().catch(() => null));
  if (!notification) return json({ ignored: "not_a_notification" });
  if (notification.test) return json({ ignored: "test_notification" });
  if (notification.packageName !== PLAY_PACKAGE) return json({ ignored: "other_package" });
  const token = notification.purchaseToken;
  if (!token) return json({ ignored: "not_a_subscription" });
  if (!playConfigured()) {
    console.warn("play-notifications: GOOGLE_PLAY_SERVICE_ACCOUNT isn't set; nothing checked.");
    return json({ error: "Not configured." }, 500);
  }

  try {
    const key = playKey(token);
    const purchase = await fetchSubscription(token);
    const { data: row } = await admin.from("premium_entitlements").select("user_id, expires_at").eq("original_transaction_id", key).maybeSingle();
    let subscription;
    try {
      subscription = evaluateSubscription(purchase, { productIds: PLAY_PRODUCT_IDS, userID: row?.user_id ?? null, now: new Date() });
    } catch (error) {
      if (!(error instanceof PlayVerificationError)) throw error;
      // Ended, on hold, paused or revoked: that purchase no longer unlocks Premium.
      if (row) await admin.from("premium_entitlements").delete().eq("original_transaction_id", key);
      return json({ updated: row ? "removed" : "nothing", reason: error.reason });
    }

    const owner = row?.user_id ?? purchase?.externalAccountIdentifiers?.obfuscatedExternalAccountId;
    if (!owner || !UUID.test(owner)) return json({ updated: "nothing", reason: "no_account" });
    await acknowledge(subscription, token);

    // The account's row (one per account): keep a longer App Store subscription.
    const { data: saved } = await admin.from("premium_entitlements").select("store, expires_at").eq("user_id", owner.toLowerCase()).maybeSingle();
    if (saved && saved.store === "app_store" && Date.parse(saved.expires_at) > Date.parse(subscription.expiresAt)) {
      return json({ updated: "nothing", reason: "app_store_longer" });
    }
    const { error } = await admin.from("premium_entitlements").upsert({
      user_id: owner.toLowerCase(),
      original_transaction_id: key,
      product_id: subscription.productId,
      environment: subscription.environment,
      expires_at: subscription.expiresAt,
      store: "google_play",
      updated_at: new Date().toISOString(),
    });
    // A clash means another account holds this purchase: leave it with them.
    if (error) return json({ updated: "nothing", reason: "held_elsewhere" });
    return json({ updated: "saved", expiresAt: subscription.expiresAt });
  } catch (error) {
    console.error("play-notifications", error);
    return json({ error: "Couldn't check the purchase just now." }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
