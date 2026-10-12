// premium-sync: tells the server about the person's App Store subscription.
//
// POST /functions/v1/premium-sync with the user's access token and
//   { signedTransaction }   (the StoreKit 2 JWS of the active subscription)
// or an empty body (just asks), returns
//   { premium, expiresAt, source }   source: "grant" | "subscription" | null
//
// The app calls it after a purchase or restore, on sign-in, and on launch or
// return to the front when the subscription has changed (EntitlementService).
// It records the subscription in public.premium_entitlements exactly as
// study-ai does (same products, same appAccountToken and Family Sharing
// rules: supabase/functions/_shared/premium.ts), so public.genesis_is_premium()
// (storage upload policies) knows about it. App Store Server Notifications
// (appstore-notifications) keep the row current afterwards.
//
// Deploy: supabase functions deploy premium-sync   (JWT verification on)
import { createClient } from "jsr:@supabase/supabase-js@2";
import { VerificationError } from "../_shared/appstore.ts";
import { activeGrant, claimTransaction, forgetEntitlement, savedEntitlement } from "../_shared/premium.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

type Source = "grant" | "subscription" | null;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "Sign in first." }, 401);
    const userID = userData.user.id;

    const body = await req.json().catch(() => null);
    const signedTransaction = typeof body?.signedTransaction === "string" && body.signedTransaction.length > 0
      ? body.signedTransaction
      : undefined;

    // 1. The subscription the app sent, if any: verify and record it.
    let subscription: { expiresAt: string } | null = null;
    let checkFailed = false;
    if (signedTransaction) {
      try {
        subscription = await claimTransaction(admin, userID, signedTransaction);
      } catch (error) {
        if (error instanceof VerificationError) {
          // Expired, refunded or not valid: whatever was saved no longer applies.
          await forgetEntitlement(admin, userID);
        } else {
          // Couldn't check right now: fall back to what's on file.
          console.error(error);
          checkFailed = true;
        }
      }
    }

    // 2. Otherwise what's on file (kept current by App Store notifications).
    if (!subscription && (!signedTransaction || checkFailed)) {
      const saved = await savedEntitlement(admin, userID);
      if (saved && new Date(saved.expires_at).getTime() > Date.now()) subscription = { expiresAt: saved.expires_at };
    }

    // 3. A grant from the owner (public.premium_grants).
    const grant = await activeGrant(admin, userID);

    const source: Source = subscription ? "subscription" : grant ? "grant" : null;
    const expiresAt = subscription?.expiresAt ?? grant?.expiresAt ?? null;
    return json({ premium: source !== null, expiresAt, source });
  } catch (error) {
    console.error("premium-sync", error);
    return json({ error: "Couldn't check Premium just now." }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
