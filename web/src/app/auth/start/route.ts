// GET /auth/start?provider=apple|google&next=/s/<slug> → Supabase's sign-in
// page with a PKCE challenge. The verifier waits in an httpOnly cookie for
// /auth/callback (ten minutes).
import { NextResponse, type NextRequest } from "next/server";
import { config } from "@/config";
import { authorizeURL, challengeFor, cookieOptions, encodePkce, newVerifier, PKCE_COOKIE, safeNext, type Provider } from "@/lib/session";

export async function GET(request: NextRequest) {
  const provider = request.nextUrl.searchParams.get("provider");
  if (provider !== "apple" && provider !== "google") return new NextResponse(null, { status: 400 });
  const next = safeNext(request.nextUrl.searchParams.get("next"));
  const verifier = newVerifier();
  const callback = new URL("/auth/callback", request.nextUrl.origin).toString();
  const response = NextResponse.redirect(authorizeURL(config.supabaseUrl, provider as Provider, callback, await challengeFor(verifier)));
  response.cookies.set(PKCE_COOKIE, encodePkce({ verifier, next }), cookieOptions(600));
  response.headers.set("Cache-Control", "no-store");
  return response;
}
