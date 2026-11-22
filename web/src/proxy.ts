// Keeps the signed-in session fresh before a page or route reads it: an
// access token close to expiry is exchanged once here, and the new cookie
// goes both to this request (so the page sees it) and back to the browser
// (Supabase rotates refresh tokens, so the old one mustn't be used again).
import { NextResponse, type NextRequest } from "next/server";
import { refreshSession } from "@/lib/supabase";
import { cookieOptions, decodeSession, encodeSession, needsRefresh, SESSION_COOKIE, SESSION_MAX_AGE_S } from "@/lib/session";

export async function proxy(request: NextRequest) {
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);
  if (!session || !needsRefresh(session)) return NextResponse.next();

  const fresh = await refreshSession(session);
  if (!fresh) {
    request.cookies.delete(SESSION_COOKIE);
    const response = NextResponse.next({ request });
    response.cookies.set(SESSION_COOKIE, "", cookieOptions(0));
    return response;
  }
  const value = encodeSession({ ...fresh, name: fresh.name ?? session.name });
  request.cookies.set(SESSION_COOKIE, value);
  const response = NextResponse.next({ request });
  response.cookies.set(SESSION_COOKIE, value, cookieOptions(SESSION_MAX_AGE_S));
  return response;
}

export const config = {
  matcher: ["/s/:path*", "/studio/:path*", "/studio", "/api/:path*", "/launch", "/launch/:path*"],
};
