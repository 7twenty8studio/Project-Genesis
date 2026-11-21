// GET /auth/callback?code=… (Supabase, after Apple or Google): swaps the code
// and the waiting verifier for a session, keeps it in an httpOnly cookie and
// goes back to the page that asked.
import { NextResponse, type NextRequest } from "next/server";
import { exchangeCode } from "@/lib/supabase";
import { cookieOptions, decodePkce, encodeSession, PKCE_COOKIE, SESSION_COOKIE, SESSION_MAX_AGE_S } from "@/lib/session";

export async function GET(request: NextRequest) {
  const pkce = decodePkce(request.cookies.get(PKCE_COOKIE)?.value);
  const code = request.nextUrl.searchParams.get("code");
  const back = new URL(pkce?.next ?? "/studio", request.nextUrl.origin);
  let session = null;
  if (pkce && code) session = await exchangeCode(code, pkce.verifier);
  if (!session) back.searchParams.set("signin", "failed");
  const response = NextResponse.redirect(back);
  response.cookies.set(PKCE_COOKIE, "", cookieOptions(0));
  if (session) response.cookies.set(SESSION_COOKIE, encodeSession(session), cookieOptions(SESSION_MAX_AGE_S));
  response.headers.set("Cache-Control", "no-store");
  return response;
}
