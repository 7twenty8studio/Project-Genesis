// Daily Verse Games: database, Storage and email access for dv-report, dv-admin
// and dv-retention (Deno only; the pure rules are in dailyVerse.ts).
//
// The daily_verse schema is NOT exposed to the Data API, so these functions use
// a direct Postgres connection (SUPABASE_DB_URL, provided to every Edge
// Function) and switch to service_role in each transaction: exactly the rights
// PR A granted, nothing more. Versely's shared code is not used or changed.
import postgres from "npm:postgres@3.4.5";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { BUCKET } from "./dailyVerse.ts";

const DB_URL = Deno.env.get("SUPABASE_DB_URL")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// prepare: false works with both the direct connection and the transaction pooler.
const sql = postgres(DB_URL, { prepare: false, max: 3, idle_timeout: 20, connect_timeout: 10 });

export type Tx = postgres.TransactionSql;

/**
 * A Daily Verse setting: the Edge Function secret if set (local tests, CLI deploys),
 * otherwise the Vault entry of the same name in lower case (e.g. DV_HMAC_SECRET →
 * vault "dv_hmac_secret"), read as the connection's own role (postgres), never as
 * service_role. Cached for 60 s, so a change (e.g. a new Internal build) applies
 * within a minute. Only names starting with DV_ are read from the Vault.
 */
const settingCache = new Map<string, { value: string | undefined; at: number }>();
export async function setting(name: string): Promise<string | undefined> {
  const fromEnv = Deno.env.get(name);
  if (fromEnv) return fromEnv;
  if (!/^DV_[A-Z_]+$/.test(name)) return undefined;
  const cached = settingCache.get(name);
  if (cached && Date.now() - cached.at < 60_000) return cached.value;
  const rows = await sql`select decrypted_secret from vault.decrypted_secrets where name = ${name.toLowerCase()} limit 1`;
  const value = (rows[0]?.decrypted_secret as string | undefined)?.trim() || undefined;
  settingCache.set(name, { value, at: Date.now() });
  return value;
}

/** The sender for Daily Verse alerts: DV_EMAIL_FROM, else Versely's verified sender address under the Daily Verse name. */
async function emailFrom(): Promise<string> {
  const own = await setting("DV_EMAIL_FROM");
  if (own) return own;
  const shared = Deno.env.get("OPS_EMAIL_FROM"); // read-only; Versely's setting is not changed
  const address = shared?.match(/<([^>]+)>/)?.[1] ?? (shared?.includes("@") ? shared.trim() : undefined);
  return `Daily Verse Games <${address ?? "onboarding@resend.dev"}>`;
}

/** Runs `fn` in one transaction as service_role (set local: it ends with the transaction). */
export function asService<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
  return sql.begin(async (tx) => {
    await tx`set local role service_role`;
    return await fn(tx);
  }) as Promise<T>;
}

/** Storage with the service role key (an Edge Function secret only; never sent to any client). */
export const storage = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } }).storage.from(BUCKET);

/** The signed-in caller's verified email, from Supabase Auth (contract rule 4), lower-cased; null if none. */
export async function verifiedEmail(authorization: string | null): Promise<string | null> {
  const token = authorization?.replace(/^Bearer\s+/i, "").trim() ?? "";
  if (!token || token === ANON_KEY) return null;
  const client = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false } });
  const { data, error } = await client.auth.getUser(token);
  const email = data?.user?.email?.toLowerCase();
  return error || !email ? null : email;
}

/** Sends the Daily Verse alert with the existing Resend key, to its own recipients. False when not set up. */
export async function sendDailyVerseEmail(subject: string, html: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  const to = ((await setting("DV_ALERT_EMAIL")) ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (!key || to.length === 0) return false;
  const from = await emailFrom();
  // DV_RESEND_URL exists only so local tests can point at a mock (env only; production leaves it unset).
  const url = Deno.env.get("DV_RESEND_URL") || "https://api.resend.com/emails";
  const response = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject, html }),
  });
  if (!response.ok) throw new Error(`Resend HTTP ${response.status}`);
  return true;
}

/** Runs work after the response is sent, when the runtime supports it. */
export function inBackground(promise: Promise<unknown>): void {
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
  const guarded = promise.catch((error) => console.error("dv background task failed", error?.message ?? error));
  if (runtime?.waitUntil) runtime.waitUntil(guarded);
}
