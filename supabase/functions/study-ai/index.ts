// study-ai: the Genesis study assistant.
//
// POST /functions/v1/study-ai with the user's access token and
//   { action, start, end, reference, text, signedTransaction? }
// returns
//   { content, cached, tier, usedToday, limit, model }
//
// - Uses Claude Haiku 4.5 through the Anthropic API. The API key is the
//   ANTHROPIC_API_KEY secret; it never ships in the app.
// - Answers are cached per passage and action and shared by everyone, so each
//   is paid for once.
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
  MODEL,
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
const PRODUCT_IDS = ["com.7twenty8studio.genesis.premium.monthly", "com.7twenty8studio.genesis.premium.yearly"];
const APPLE_ROOT_URL = "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
let appleRoot: Uint8Array | undefined;

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

    // 2. What do they want?
    const body = await req.json().catch(() => null);
    const request = parseRequest(body);
    const signedTransaction = typeof body?.signedTransaction === "string" ? body.signedTransaction : undefined;

    // 3. Free or Premium?
    const tier = await tierFor(userID, signedTransaction);

    // 4. Allowed today? Free counts every answer; Premium counts new ones only.
    const day = new Date().toISOString().slice(0, 10);
    const usedToday = await usage(userID, day);
    const access = decideAccess(tier, request.action, usedToday);
    if (!access.allowed) {
      const message = access.reason === "premium_required"
        ? "This study tool is part of Genesis Premium."
        : `You've used today's ${access.limit} study assistant answers. They reset tomorrow.`;
      return json({ error: message, reason: access.reason, tier, usedToday, limit: access.limit }, 403);
    }

    // 5. Cached?
    const key = cacheKey(request);
    const { data: cached } = await admin.from("ai_cache").select("content").eq("key", key).maybeSingle();
    if (cached) {
      const used = tier === "free" ? await countUsage(userID, day) : usedToday;
      return json({ content: cached.content, cached: true, tier, usedToday: used, limit: access.limit, model: MODEL });
    }

    // 6. Ask the model.
    if (!ANTHROPIC_API_KEY) return json({ error: "The study assistant isn't set up yet." }, 503);
    const raw = await askClaude(buildUserMessage(request));
    const { text: content, removed } = removeQuotes(raw, request.text, request.reference);
    if (removed > 0) console.log(`Removed ${removed} quoted passage(s) from ${key}`);

    await admin.from("ai_cache").upsert({
      key,
      action: request.action,
      start_verse: request.start,
      end_verse: request.end,
      content,
      model: MODEL,
    });
    const used = await countUsage(userID, day);
    return json({ content, cached: false, tier, usedToday: used, limit: access.limit, model: MODEL });
  } catch (error) {
    if (error instanceof RequestError) return json({ error: error.message }, error.status);
    console.error(error);
    return json({ error: "The study assistant couldn't answer just now. Please try again." }, 500);
  }
});

/** Premium if a recently verified subscription is on file, or the one sent now verifies. */
async function tierFor(userID: string, signedTransaction?: string): Promise<Tier> {
  const { data: saved } = await admin
    .from("premium_entitlements")
    .select("expires_at")
    .eq("user_id", userID)
    .maybeSingle();
  if (saved && new Date(saved.expires_at) > new Date()) return "premium";
  if (!signedTransaction) return "free";

  try {
    appleRoot ??= new Uint8Array(await (await fetch(APPLE_ROOT_URL)).arrayBuffer());
    const transaction = await verifyTransaction(signedTransaction, {
      appleRoot,
      bundleId: BUNDLE_ID,
      productIds: PRODUCT_IDS,
      now: new Date(),
      allowXcode: ALLOW_XCODE_STOREKIT,
    });
    // A purchase made while signed in carries the account id; it must match.
    if (transaction.appAccountToken && transaction.appAccountToken !== userID.toLowerCase()) return "free";
    // One subscription unlocks one account: the first to present it keeps it.
    const { data: owner } = await admin
      .from("premium_entitlements")
      .select("user_id")
      .eq("original_transaction_id", transaction.originalTransactionId)
      .maybeSingle();
    if (owner && owner.user_id !== userID) return "free";
    await admin.from("premium_entitlements").upsert({
      user_id: userID,
      original_transaction_id: transaction.originalTransactionId,
      product_id: transaction.productId,
      environment: transaction.environment,
      expires_at: new Date(transaction.expiresDate!).toISOString(),
    });
    return "premium";
  } catch (error) {
    if (!(error instanceof VerificationError)) console.error(error);
    return "free";
  }
}

async function usage(userID: string, day: string): Promise<number> {
  const { data } = await admin.from("ai_usage").select("count").eq("user_id", userID).eq("day", day).maybeSingle();
  return data?.count ?? 0;
}

/** Records one answer and returns the new total for the day. */
async function countUsage(userID: string, day: string): Promise<number> {
  const { data, error } = await admin.rpc("increment_ai_usage", { p_user: userID, p_day: day });
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
