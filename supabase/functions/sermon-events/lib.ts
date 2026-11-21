// sermon-events: the pure parts (Node tests in lib.test.ts).
//
// Counts are aggregate only. A visitor is an HMAC of their address and
// browser under a key that changes every day (derived from the
// SERMON_EVENTS_SECRET secret and the UTC date), so the same person opening a
// sermon twice in a day counts once, yesterday's values can't be linked to
// today's, and nobody reading the database can work an address back out.
// The database keeps a value one day at most (record_sermon_event).

export type SermonEventKind = "open" | "passage" | "save";

export interface SermonEvent {
  slug: string;
  kind: SermonEventKind;
}

export class EventError extends Error {}

const KINDS: SermonEventKind[] = ["open", "passage", "save"];

export function parseEventRequest(body: unknown): SermonEvent {
  if (!body || typeof body !== "object") throw new EventError("Send { slug, kind }.");
  const { slug, kind } = body as Record<string, unknown>;
  if (typeof slug !== "string" || !/^[a-z0-9]{10}$/.test(slug)) throw new EventError("Unknown sermon.");
  if (typeof kind !== "string" || !KINDS.includes(kind as SermonEventKind)) throw new EventError("Unknown event.");
  return { slug, kind: kind as SermonEventKind };
}

/** The caller's address as the platform's proxy reports it (first x-forwarded-for entry). */
export function clientAddress(headers: Headers): string {
  const forwarded = headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || headers.get("x-real-ip")?.trim() || headers.get("cf-connecting-ip")?.trim() || "";
}

/** Link previews and crawlers open pages without a person: never counted. */
export function isAutomated(userAgent: string): boolean {
  return userAgent.trim() === "" ||
    /bot|crawler|spider|preview|facebookexternalhit|slackbot|whatsapp|telegram|discord|embedly|headless|curl|wget|python|node-fetch|go-http/i.test(userAgent);
}

/** "2026-11-22" (UTC): the day the key belongs to. */
export function dayKey(date: Date): string {
  return date.toISOString().slice(0, 10);
}

async function hmac(key: string | Uint8Array, message: string): Promise<Uint8Array> {
  const raw = typeof key === "string" ? new TextEncoder().encode(key) : key;
  const cryptoKey = await crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message)));
}

/** 64 hex characters, as record_sermon_event expects. */
export async function visitorHash(secret: string, day: string, address: string, userAgent: string): Promise<string> {
  if (secret.length < 32) throw new Error("SERMON_EVENTS_SECRET must be at least 32 characters.");
  const dailyKey = await hmac(secret, `versely-sermon-visitor:${day}`);
  const value = await hmac(dailyKey, `${address}\n${userAgent.slice(0, 512)}`);
  return [...value].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** CORS for the guest page (and local development); the app sends no Origin. */
export function corsHeaders(origin: string | null, allowed: string[]): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
  if (origin && allowed.includes(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}
