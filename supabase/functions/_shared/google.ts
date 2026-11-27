// Google service accounts: an OAuth access token for Google's APIs (the Play
// Developer API for play-sync and play-notifications, Firebase Cloud
// Messaging for group-notify), from a service account's JSON key kept in a
// function secret. Pure apart from `fetch`, so it runs under Node tests too.

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id?: string;
  token_uri?: string;
}

export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher";
export const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/** Reads a service account's JSON key (the secret's text); null when it isn't one. */
export function parseServiceAccount(text: string | undefined | null): ServiceAccount | null {
  if (!text) return null;
  try {
    const value = JSON.parse(text);
    if (typeof value?.client_email !== "string" || typeof value?.private_key !== "string") return null;
    if (!value.private_key.includes("PRIVATE KEY")) return null;
    return value as ServiceAccount;
  } catch {
    return null;
  }
}

export function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/** The claims of the assertion Google exchanges for an access token (an hour at most). */
export function assertionClaims(account: ServiceAccount, scope: string, issuedAt: number): Record<string, unknown> {
  return {
    iss: account.client_email,
    scope,
    aud: account.token_uri ?? GOOGLE_TOKEN_URL,
    iat: issuedAt,
    exp: issuedAt + 3600,
  };
}

/** An RS256 JWT signed with the service account's key. */
export async function signedAssertion(account: ServiceAccount, scope: string, issuedAt: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify(assertionClaims(account, scope, issuedAt)));
  const input = `${header}.${claims}`;
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(input)));
  return `${input}.${base64url(signature)}`;
}

/**
 * Access tokens for one service account and scope, reused until five
 * minutes before they end (Google asks for reuse rather than one per call).
 */
export class GoogleTokens {
  private cached?: { value: string; until: number };
  private account: ServiceAccount;
  private scope: string;
  private fetcher: typeof fetch;

  constructor(account: ServiceAccount, scope: string, fetcher: typeof fetch = fetch) {
    this.account = account;
    this.scope = scope;
    this.fetcher = fetcher;
  }

  async token(now = Math.floor(Date.now() / 1000)): Promise<string> {
    if (this.cached && now < this.cached.until) return this.cached.value;
    const assertion = await signedAssertion(this.account, this.scope, now);
    const response = await this.fetcher(this.account.token_uri ?? GOOGLE_TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }).toString(),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok || typeof body.access_token !== "string") {
      throw new Error(`Google token: HTTP ${response.status} ${body.error ?? ""}`);
    }
    const lifetime = typeof body.expires_in === "number" ? body.expires_in : 3600;
    this.cached = { value: body.access_token, until: now + Math.max(60, lifetime - 300) };
    return body.access_token;
  }
}
