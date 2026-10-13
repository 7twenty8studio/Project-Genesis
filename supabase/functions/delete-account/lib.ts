// Pure helpers for delete-account: revoking the person's Sign in with Apple
// tokens (App Store guideline 5.1.1(v)). Kept free of Deno APIs so they can be
// tested with Node.
//
// The app confirms with Apple right before deleting and sends the fresh
// authorization code; nothing is stored. Here the code is exchanged for a
// refresh token (https://appleid.apple.com/auth/token), which is then revoked
// (https://appleid.apple.com/auth/revoke). Both calls authenticate with a
// client secret: an ES256 JWT signed with the Sign in with Apple key.

export const APPLE_CLIENT_ID = "com.7twenty8studio.versely";
export const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
export const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
/** Apple allows up to six months; the secret is only used for two calls. */
export const CLIENT_SECRET_LIFETIME_SECONDS = 5 * 60;

export interface AppleSignInConfig {
  /** The .p8 file's contents (PEM). */
  key: string;
  keyID: string;
  teamID: string;
  clientID: string;
}

/** The Apple key, key id and team id from secrets, or null when any is missing. */
export function appleConfig(env: (name: string) => string | undefined): AppleSignInConfig | null {
  const key = env("APPLE_SIGNIN_KEY")?.trim();
  const keyID = env("APPLE_SIGNIN_KEY_ID")?.trim();
  const teamID = env("APPLE_TEAM_ID")?.trim();
  if (!key || !keyID || !teamID) return null;
  return { key, keyID, teamID, clientID: APPLE_CLIENT_ID };
}

/** Reads { appleAuthorizationCode? } from the request body (which may be empty). */
export function parseDeleteRequest(body: unknown): { appleAuthorizationCode: string | null } {
  const code = (body as { appleAuthorizationCode?: unknown } | null)?.appleAuthorizationCode;
  if (typeof code !== "string") return { appleAuthorizationCode: null };
  const trimmed = code.trim();
  // Apple's codes are short printable tokens; ignore anything else.
  if (!trimmed || trimmed.length > 2048 || !/^[\x21-\x7e]+$/.test(trimmed)) return { appleAuthorizationCode: null };
  return { appleAuthorizationCode: trimmed };
}

export function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The DER bytes of a PEM private key (the .p8 file from Apple). */
export function pemToDer(pem: string): Uint8Array {
  // A key pasted with literal "\n" (as some dashboards store it) still works.
  const body = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  if (!body) throw new Error("APPLE_SIGNIN_KEY is empty.");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/** The client secret for Apple's token and revoke endpoints: an ES256 JWT. */
export async function appleClientSecret(config: AppleSignInConfig, issuedAt: number): Promise<string> {
  const der = pemToDer(config.key);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der.buffer.slice(der.byteOffset, der.byteOffset + der.byteLength) as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "ES256", kid: config.keyID }));
  const claims = base64url(JSON.stringify({
    iss: config.teamID,
    iat: issuedAt,
    exp: issuedAt + CLIENT_SECRET_LIFETIME_SECONDS,
    aud: "https://appleid.apple.com",
    sub: config.clientID,
  }));
  const signingInput = `${header}.${claims}`;
  // Web Crypto returns the raw r||s signature JWS ES256 expects (not DER).
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput)),
  );
  return `${signingInput}.${base64url(signature)}`;
}

/** Form body exchanging an authorization code for tokens. */
export function tokenForm(clientID: string, clientSecret: string, code: string): URLSearchParams {
  return new URLSearchParams({
    client_id: clientID,
    client_secret: clientSecret,
    code,
    grant_type: "authorization_code",
  });
}

/** Form body revoking a token. */
export function revokeForm(
  clientID: string,
  clientSecret: string,
  token: string,
  hint: "refresh_token" | "access_token",
): URLSearchParams {
  return new URLSearchParams({
    client_id: clientID,
    client_secret: clientSecret,
    token,
    token_type_hint: hint,
  });
}

export type Fetch = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<
  { ok: boolean; status: number; text(): Promise<string> }
>;

export type RevokeResult = { revoked: true } | { revoked: false; reason: string };

/**
 * Exchanges the code and revokes the refresh token (or the access token when
 * Apple returns no refresh token). Never throws: deleting the account matters
 * more, so the caller logs the reason and carries on.
 */
export async function revokeAppleTokens(
  config: AppleSignInConfig,
  code: string,
  fetcher: Fetch,
  now: number = Math.floor(Date.now() / 1000),
): Promise<RevokeResult> {
  try {
    const secret = await appleClientSecret(config, now);
    const post = (url: string, form: URLSearchParams) =>
      fetcher(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });

    const tokenResponse = await post(APPLE_TOKEN_URL, tokenForm(config.clientID, secret, code));
    const tokenText = await tokenResponse.text();
    if (!tokenResponse.ok) return { revoked: false, reason: `token ${tokenResponse.status}: ${errorCode(tokenText)}` };
    let tokens: { refresh_token?: unknown; access_token?: unknown };
    try {
      tokens = JSON.parse(tokenText);
    } catch {
      return { revoked: false, reason: "token response wasn't JSON" };
    }
    let token: string;
    let hint: "refresh_token" | "access_token";
    if (typeof tokens.refresh_token === "string" && tokens.refresh_token) {
      token = tokens.refresh_token;
      hint = "refresh_token";
    } else if (typeof tokens.access_token === "string" && tokens.access_token) {
      token = tokens.access_token;
      hint = "access_token";
    } else {
      return { revoked: false, reason: "no token in Apple's response" };
    }

    const revokeResponse = await post(APPLE_REVOKE_URL, revokeForm(config.clientID, secret, token, hint));
    if (!revokeResponse.ok) {
      return { revoked: false, reason: `revoke ${revokeResponse.status}: ${errorCode(await revokeResponse.text())}` };
    }
    return { revoked: true };
  } catch (error) {
    return { revoked: false, reason: error instanceof Error ? error.message : String(error) };
  }
}

/** Apple's error code ("invalid_grant", ...) without echoing anything else. */
function errorCode(text: string): string {
  try {
    const parsed = JSON.parse(text) as { error?: unknown };
    if (typeof parsed.error === "string") return parsed.error.slice(0, 64);
  } catch {
    // Not JSON.
  }
  return "unknown";
}
