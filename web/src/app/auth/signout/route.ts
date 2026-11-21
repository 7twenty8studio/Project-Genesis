// POST /auth/signout (a form button): ends the session here and at Supabase.
import { NextResponse, type NextRequest } from "next/server";
import { signOut } from "@/lib/supabase";
import { cookieOptions, decodeSession, safeNext, SESSION_COOKIE } from "@/lib/session";

export async function POST(request: NextRequest) {
  const session = decodeSession(request.cookies.get(SESSION_COOKIE)?.value);
  if (session) await signOut(session);
  const form = await request.formData().catch(() => null);
  const next = safeNext(typeof form?.get("next") === "string" ? (form.get("next") as string) : null);
  const response = NextResponse.redirect(new URL(next, request.nextUrl.origin), 303);
  response.cookies.set(SESSION_COOKIE, "", cookieOptions(0));
  return response;
}
