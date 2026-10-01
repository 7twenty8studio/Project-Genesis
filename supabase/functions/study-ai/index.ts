// study-ai: the Genesis study assistant.
//
// POST /functions/v1/study-ai with the user's access token and
//   { action, start, end, text, signedTransaction? }
// returns
//   { content, cached, tier, usedToday, limit, model }
//
// - Uses Claude Haiku 4.5 through the Anthropic API. The API key is the
//   ANTHROPIC_API_KEY secret; it never ships in the app.
// - Answers are cached per passage and action and shared by everyone, so each
//   is paid for once. Only server-built values go into the prompt, so a
//   modified app can't plant content in the shared cache.
// - Never returns Scripture: the prompt forbids quoting and removeQuotes()
//   strips any run of six or more words from the passage. The app shows verse
//   text from its own database and labels this content as AI-generated.
// - Free accounts: 3 passage explanations a day. Premium (a verified App Store
//   subscription): every action, up to 50 new answers a day.
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  buildUserMessage,
  cacheKey,
  decideAccess,
  FREE_DAILY_LIMIT,
  MODEL,
  PREMIUM_DAILY_LIMIT,
  parseRequest,
  removeQuotes,
  RequestError,
  SYSTEM_PROMPT,
  type Tier,
  verifyTransaction,
  VerificationError,
} from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const BUNDLE_ID = Deno.env.get("GENESIS_BUNDLE_ID") ?? "com.7twenty8studio.genesis";
// Development only: accept purchases made with Xcode's local StoreKit testing.
const ALLOW_XCODE_STOREKIT = Deno.env.get("ALLOW_XCODE_STOREKIT") === "true";
if (ALLOW_XCODE_STOREKIT) {
  console.warn("ALLOW_XCODE_STOREKIT is on: Xcode test purchases unlock Premium. Remove this secret before release.");
}
const PRODUCT_IDS = ["com.7twenty8studio.genesis.premium.monthly", "com.7twenty8studio.genesis.premium.yearly"];
const APPLE_ROOT_URL = "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";
/** A saved subscription is re-verified at least this often, so a refund ends it. */
const REVERIFY_AFTER_MS = 7 * 24 * 60 * 60 * 1000;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
let appleRoot: Uint8Array | undefined;

/** Reads the study_assistant switch; a missing row or a failed read means off. */
async function assistantIsOn(): Promise<boolean> {
  const { data, error } = await admin.from("feature_flags").select("enabled").eq("key", "study_assistant").maybeSingle();
  return !error && data?.enabled === true;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    // 1. Who is asking? (Anonymous requests are refused: limits need an account.)
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "Sign in to use the study assistant." }, 401);
    const userID = userData.user.id;

    // 2. Is the assistant switched on? (public.feature_flags, so it can be
    //    turned off without an app update; older apps get the same answer.)
    if (!(await assistantIsOn())) {
      return json({ error: "The study assistant isn't available right now.", reason: "disabled" }, 503);
    }

    // 3. What do they want?
    const body = await req.json().catch(() => null);
    const request = parseRequest(body);
    const signedTransaction = typeof body?.signedTransaction === "string" ? body.signedTransaction : undefined;

    // 4. Free or Premium?
    const tier = await tierFor(userID, signedTransaction);

    // 5. Is this tool included? (Limits are reserved below, in one database step.)
    const day = new Date().toISOString().slice(0, 10);
    const limit = tier === "free" ? FREE_DAILY_LIMIT : PREMIUM_DAILY_LIMIT;
    const access = decideAccess(tier, request.action, 0);
    if (!access.allowed) {
      return json({ error: "This study tool is part of Genesis Premium.", reason: access.reason, tier, limit }, 403);
    }
    const overLimit = () =>
      json({ error: `You've used today's ${limit} study assistant answers. They reset tomorrow.`, reason: "daily_limit", tier, usedToday: limit, limit }, 403);

    // 6. Cached? Free accounts count every answer; Premium counts new ones only.
    const key = cacheKey(request);
    const { data: cached } = await admin.from("ai_cache").select("content").eq("key", key).maybeSingle();
    if (cached) {
      let used: number | undefined;
      if (tier === "free") {
        used = await reserve(userID, day, limit);
        if (used < 0) return overLimit();
      }
      return json({ content: cached.content, cached: true, tier, usedToday: used, limit, model: MODEL });
    }

    // 7. Reserve one answer, then ask the model; give it back if that fails.
    if (!ANTHROPIC_API_KEY) return json({ error: "The study assistant isn't set up yet." }, 503);
    const used = await reserve(userID, day, limit);
    if (used < 0) return overLimit();
    let content: string;
    try {
      const raw = await askClaude(buildUserMessage(request));
      const cleaned = removeQuotes(raw, request.text, request.reference);
      if (cleaned.removed > 0) console.log(`Removed ${cleaned.removed} quoted passage(s) from ${key}`);
      content = cleaned.text;
    } catch (error) {
      await admin.rpc("release_ai_usage", { p_user: userID, p_day: day });
      throw error;
    }

    await admin.from("ai_cache").upsert({
      key,
      action: request.action,
      start_verse: request.start,
      end_verse: request.end,
      content,
      model: MODEL,
    });
    return json({ content, cached: false, tier, usedToday: used, limit, model: MODEL });
  } catch (error) {
    if (error instanceof RequestError) return json({ error: error.message }, error.status);
    console.error(error);
    return json({ error: "The study assistant couldn't answer just now. Please try again." }, 500);
  }
});

/**
 * Premium if a subscription verified in the last week is on file, or the one
 * sent now verifies. Re-verifying weekly means a refund or cancellation ends
 * Premium here too.
 */
async function tierFor(userID: string, signedTransaction?: string): Promise<Tier> {
  const { data: saved } = await admin
    .from("premium_entitlements")
    .select("expires_at, updated_at")
    .eq("user_id", userID)
    .maybeSingle();
  const now = Date.now();
  const savedIsCurrent = saved && new Date(saved.expires_at).getTime() > now &&
    now - new Date(saved.updated_at).getTime() < REVERIFY_AFTER_MS;
  if (savedIsCurrent && !signedTransaction) return "premium";
  if (!signedTransaction) {
    if (saved) await admin.from("premium_entitlements").delete().eq("user_id", userID);
    return "free";
  }

  try {
    const root = await appleRootCertificate();
    const transaction = await verifyTransaction(signedTransaction, {
      appleRoot: root,
      bundleId: BUNDLE_ID,
      productIds: PRODUCT_IDS,
      now: new Date(),
      allowXcode: ALLOW_XCODE_STOREKIT,
    });
    // Family members sharing a subscription carry the purchaser's details, so
    // the account checks below apply only to the purchaser.
    let ownershipKey = transaction.originalTransactionId;
    if (transaction.familyShared) {
      ownershipKey = `${transaction.originalTransactionId}:family:${userID}`;
    } else {
      // A purchase made while signed in carries the account id; it must match.
      if (transaction.appAccountToken && transaction.appAccountToken !== userID.toLowerCase()) return "free";
      // One subscription unlocks one account: the first to present it keeps it.
      const { data: owner } = await admin
        .from("premium_entitlements")
        .select("user_id")
        .eq("original_transaction_id", ownershipKey)
        .maybeSingle();
      if (owner && owner.user_id !== userID) return "free";
    }
    const { error } = await admin.from("premium_entitlements").upsert({
      user_id: userID,
      original_transaction_id: ownershipKey,
      product_id: transaction.productId,
      environment: transaction.environment,
      expires_at: new Date(transaction.expiresDate!).toISOString(),
      updated_at: new Date().toISOString(),
    });
    // A unique clash means another account claimed it at the same moment.
    if (error) return "free";
    return "premium";
  } catch (error) {
    if (error instanceof VerificationError) {
      // Expired, refunded or not valid: whatever was saved no longer applies.
      if (saved) await admin.from("premium_entitlements").delete().eq("user_id", userID);
      return "free";
    }
    // Couldn't check right now (e.g. Apple's certificate didn't download):
    // keep a recent verification rather than locking a subscriber out.
    console.error(error);
    return savedIsCurrent ? "premium" : "free";
  }
}

/** Apple Root CA - G3, downloaded once per instance; a failed download is retried next time. */
async function appleRootCertificate(): Promise<Uint8Array> {
  if (appleRoot) return appleRoot;
  const response = await fetch(APPLE_ROOT_URL);
  if (!response.ok) throw new Error(`Apple root certificate: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length < 400 || bytes[0] !== 0x30) throw new Error("Apple root certificate: unexpected download");
  appleRoot = bytes;
  return bytes;
}

/** Reserves one of today's answers: the new count, or -1 at the limit. */
async function reserve(userID: string, day: string, limit: number): Promise<number> {
  const { data, error } = await admin.rpc("reserve_ai_usage", { p_user: userID, p_day: day, p_limit: limit });
  if (error) throw error;
  return data as number;
}

async function askClaude(message: string): Promise<string> {
  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": ANTHROPIC_API_KEY!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 900,
      temperature: 0.3,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: message }],
    }),
  });
  if (!response.ok) throw new Error(`Anthropic API ${response.status}: ${await response.text()}`);
  const result = await response.json();
  const text = (result.content ?? [])
    .filter((block: { type: string }) => block.type === "text")
    .map((block: { text: string }) => block.text)
    .join("\n")
    .trim();
  if (!text) throw new Error("Empty answer from the model.");
  return text;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
