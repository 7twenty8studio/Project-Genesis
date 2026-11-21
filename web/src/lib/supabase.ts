// Calls to the Versely Supabase project from the web server (route handlers,
// server components, proxy). Raw fetch with the public anon key, as the
// 7twenty8 site's dashboards do: no SDK. A signed-in person's own access
// token goes in Authorization, so the database decides what they may do.
import { config } from "@/config";
import { sessionFromToken, type Session } from "./session.ts";

export class RpcError extends Error {
  /** The database's own code ("not_allowed", "draft_changed", "invalid_blocks"…) or the HTTP status. */
  code: string;
  status: number;
  detail?: string;
  constructor(code: string, status: number, detail?: string) {
    super(code);
    this.code = code;
    this.status = status;
    this.detail = detail;
  }
}

function headers(token?: string): Record<string, string> {
  return {
    apikey: config.supabaseAnonKey,
    Authorization: `Bearer ${token ?? config.supabaseAnonKey}`,
    "Content-Type": "application/json",
  };
}

/** Calls a database function as the person (or as a guest without a token). Never cached. */
export async function rpc<T>(fn: string, args: Record<string, unknown>, token?: string): Promise<T> {
  const response = await fetch(`${config.supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: headers(token),
    body: JSON.stringify(args),
    cache: "no-store",
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    // PostgREST: { code, message, details }. Our functions raise their reason as the message.
    const message = typeof body?.message === "string" ? body.message : String(response.status);
    throw new RpcError(message, response.status, typeof body?.details === "string" ? body.details : undefined);
  }
  return body as T;
}

/** Reads rows the person may see (RLS), e.g. Studio's own drafts. */
export async function select<T>(path: string, token: string): Promise<T> {
  const response = await fetch(`${config.supabaseUrl}/rest/v1/${path}`, { headers: headers(token), cache: "no-store" });
  if (!response.ok) throw new RpcError(String(response.status), response.status);
  return (await response.json()) as T;
}

async function token(body: Record<string, string>, grant: "pkce" | "refresh_token"): Promise<Session | null> {
  const response = await fetch(`${config.supabaseUrl}/auth/v1/token?grant_type=${grant}`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify(body),
    cache: "no-store",
  });
  if (!response.ok) return null;
  return sessionFromToken(await response.json());
}

export const exchangeCode = (code: string, verifier: string) => token({ auth_code: code, code_verifier: verifier }, "pkce");
export const refreshSession = (session: Session) => token({ refresh_token: session.refreshToken }, "refresh_token");

export async function signOut(session: Session): Promise<void> {
  await fetch(`${config.supabaseUrl}/auth/v1/logout`, { method: "POST", headers: headers(session.accessToken), cache: "no-store" }).catch(() => undefined);
}

/**
 * A private cover for the person (or guest), from the sermon-cover Edge
 * Function: it asks sermon_cover_access with this token on every call and
 * only then reads the file, so this answers 404 the moment the sermon is
 * unpublished, restricted, hidden or switched off. No client can read the
 * bucket itself, so no signed link to a cover exists (20261121000000).
 */
export async function downloadCover(path: string, token?: string): Promise<Response> {
  return fetch(`${config.supabaseUrl}/functions/v1/sermon-cover?name=${encodeURIComponent(path)}`, {
    headers: { apikey: config.supabaseAnonKey, Authorization: `Bearer ${token ?? config.supabaseAnonKey}` },
    cache: "no-store",
  });
}

/** Uploads a cover picture to the path new_church_sermon_cover gave (leaders only, by storage's INSERT policy; never upserted, never read back). */
export async function uploadCover(path: string, jpeg: ArrayBuffer, token: string): Promise<Response> {
  return fetch(`${config.supabaseUrl}/storage/v1/object/sermon-covers/${path}`, {
    method: "POST",
    headers: { apikey: config.supabaseAnonKey, Authorization: `Bearer ${token}`, "Content-Type": "image/jpeg", "x-upsert": "false" },
    body: jpeg,
    cache: "no-store",
  });
}
