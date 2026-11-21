import { test } from "node:test";
import assert from "node:assert/strict";
import { authorizeURL, challengeFor, decodePkce, decodeSession, encodePkce, encodeSession, needsRefresh, safeNext, sessionFromToken } from "./session.ts";

test("a session survives the cookie and refuses anything malformed", () => {
  const s = { accessToken: "a.b.c", refreshToken: "r1", expiresAt: 1000, userId: "u1", name: "Ana" };
  assert.deepEqual(decodeSession(encodeSession(s)), s);
  assert.equal(decodeSession(undefined), null);
  assert.equal(decodeSession("garbage"), null);
  assert.equal(decodeSession(encodeURIComponent(JSON.stringify({ a: "", r: "x", e: 1, u: "u" }))), null);
  assert.equal(decodeSession(encodeURIComponent(JSON.stringify({ a: "x", r: "x", e: "1", u: "u" }))), null);
});

test("refresh happens two minutes before expiry", () => {
  const s = { accessToken: "a", refreshToken: "r", expiresAt: 1_000_000, userId: "u" };
  assert.equal(needsRefresh(s, 1_000_000 - 121_000), false);
  assert.equal(needsRefresh(s, 1_000_000 - 119_000), true);
});

test("PKCE challenge is RFC 7636's", async () => {
  assert.equal(await challengeFor("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
});

test("sign-in only returns to this site's sermon and Studio pages", () => {
  assert.equal(safeNext("/s/abcdefghij"), "/s/abcdefghij");
  assert.equal(safeNext("/studio"), "/studio");
  assert.equal(safeNext("/studio/0b9a1c8e-1111-2222-3333-444455556666"), "/studio/0b9a1c8e-1111-2222-3333-444455556666");
  for (const bad of ["https://evil.example", "//evil.example", "/s/ABC", "/s/abcdefghij?x=1", "/studio/../admin", "javascript:alert(1)", null, ""]) {
    assert.equal(safeNext(bad), "/studio", String(bad));
  }
  const state = decodePkce(encodePkce({ verifier: "v".repeat(64), next: "https://evil.example" }));
  assert.equal(state?.next, "/studio");
  assert.equal(decodePkce(encodePkce({ verifier: "short", next: "/studio" })), null);
});

test("the authorize URL asks for an S256 code", () => {
  const url = new URL(authorizeURL("https://x.supabase.co", "apple", "https://versely.7twenty8studio.com/auth/callback", "abc"));
  assert.equal(url.pathname, "/auth/v1/authorize");
  assert.equal(url.searchParams.get("provider"), "apple");
  assert.equal(url.searchParams.get("code_challenge_method"), "s256");
  assert.equal(url.searchParams.get("redirect_to"), "https://versely.7twenty8studio.com/auth/callback");
});

test("Supabase's token answer becomes a session with a first name", () => {
  const s = sessionFromToken({ access_token: "a", refresh_token: "r", expires_in: 3600, user: { id: "u", user_metadata: { full_name: "  Maria  da Silva" } } }, 0);
  assert.deepEqual(s, { accessToken: "a", refreshToken: "r", expiresAt: 3_600_000, userId: "u", name: "Maria" });
  assert.equal(sessionFromToken({ access_token: "a" }), null);
});
