// The signed-in session on the web (VRS-18): Supabase's PKCE sign-in with
// Apple or Google, kept in an httpOnly cookie so page scripts never see the
// tokens. Pure: the cookie format, PKCE values and the refresh rule, tested
// in session.test.ts. Every access decision is the database's; this only
// carries who is asking.

export const SESSION_COOKIE = "vs_session";
export const PKCE_COOKIE = "vs_pkce";
/** Refresh when the access token has less than this left. */
export const REFRESH_MARGIN_MS = 120_000;
/** A refresh token lasts until Supabase revokes it; the cookie keeps it 30 days. */
export const SESSION_MAX_AGE_S = 30 * 24 * 3600;

export type Provider = "apple" | "google";

export interface Session {
  accessToken: string;
  refreshToken: string;
  /** Milliseconds since 1970. */
  expiresAt: number;
  userId: string;
  name?: string;
}

export function encodeSession(session: Session): string {
  return encodeURIComponent(JSON.stringify({ a: session.accessToken, r: session.refreshToken, e: session.expiresAt, u: session.userId, n: session.name }));
}

export function decodeSession(value: string | undefined): Session | null {
  if (!value) return null;
  try {
    const raw = JSON.parse(decodeURIComponent(value)) as Record<string, unknown>;
    if (typeof raw.a !== "string" || typeof raw.r !== "string" || typeof raw.e !== "number" || typeof raw.u !== "string") return null;
    if (!raw.a || !raw.r) return null;
    return { accessToken: raw.a, refreshToken: raw.r, expiresAt: raw.e, userId: raw.u, name: typeof raw.n === "string" ? raw.n : undefined };
  } catch {
    return null;
  }
}

export function needsRefresh(session: Session, now = Date.now()): boolean {
  return session.expiresAt - now < REFRESH_MARGIN_MS;
}

/** Supabase's token answer (grant_type=pkce or refresh_token) as a Session. */
export function sessionFromToken(body: Record<string, unknown>, now = Date.now()): Session | null {
  const user = (body.user ?? {}) as Record<string, unknown>;
  const meta = (user.user_metadata ?? {}) as Record<string, unknown>;
  if (typeof body.access_token !== "string" || typeof body.refresh_token !== "string" || typeof user.id !== "string") return null;
  const name = [meta.full_name, meta.name].find((n): n is string => typeof n === "string" && n.trim() !== "");
  return {
    accessToken: body.access_token,
    refreshToken: body.refresh_token,
    expiresAt: now + Number(body.expires_in ?? 3600) * 1000,
    userId: user.id,
    name: name?.trim().split(/\s+/)[0],
  };
}

// PKCE (RFC 7636) ------------------------------------------------------------------

function base64url(bytes: Uint8Array): string {
  let text = "";
  for (const b of bytes) text += String.fromCharCode(b);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function newVerifier(): string {
  return base64url(crypto.getRandomValues(new Uint8Array(48)));
}

export async function challengeFor(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  return base64url(new Uint8Array(digest));
}

/**
 * Where to go after signing in: only this site's own sermon and Studio pages,
 * never another host (an open redirect would hand someone's sign-in away).
 */
export function safeNext(next: string | null | undefined): string {
  if (!next) return "/studio";
  if (/^\/s\/[a-z0-9]{10}$/.test(next)) return next;
  if (/^\/studio(\/[A-Za-z0-9-]{1,40})?$/.test(next)) return next;
  return "/studio";
}

export interface PkceState {
  verifier: string;
  next: string;
}

export function encodePkce(state: PkceState): string {
  return encodeURIComponent(JSON.stringify({ v: state.verifier, n: state.next }));
}

export function decodePkce(value: string | undefined): PkceState | null {
  if (!value) return null;
  try {
    const raw = JSON.parse(decodeURIComponent(value)) as Record<string, unknown>;
    if (typeof raw.v !== "string" || raw.v.length < 43) return null;
    return { verifier: raw.v, next: safeNext(typeof raw.n === "string" ? raw.n : null) };
  } catch {
    return null;
  }
}

export function authorizeURL(supabaseUrl: string, provider: Provider, redirectTo: string, challenge: string): string {
  const params = new URLSearchParams({
    provider,
    redirect_to: redirectTo,
    code_challenge: challenge,
    code_challenge_method: "s256",
  });
  return `${supabaseUrl}/auth/v1/authorize?${params}`;
}

export const cookieOptions = (maxAge: number) => ({
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
  path: "/",
  maxAge,
});

/** What a refused password sign-in tells the person (Supabase's error_code, older servers' message). */
export function passwordError(status: number, json: Record<string, unknown> | null): "wrong" | "unconfirmed" | "failed" {
  const code = String(json?.error_code ?? json?.code ?? "");
  const message = String(json?.msg ?? json?.error_description ?? json?.message ?? "").toLowerCase();
  if (code === "email_not_confirmed" || message.includes("not confirmed")) return "unconfirmed";
  if (status === 400 && (code === "invalid_credentials" || code === "invalid_grant" || message.includes("invalid login"))) return "wrong";
  return "failed";
}
