// POST /auth/password (the email form under Apple and Google): signs in with
// the same email and password as the app, or sends the reset email
// (intent=reset), then goes back to the page that asked.
import { NextResponse, type NextRequest } from "next/server";
import { sendPasswordReset, signInWithPassword } from "@/lib/supabase";
import { cookieOptions, encodeSession, safeNext, SESSION_COOKIE, SESSION_MAX_AGE_S } from "@/lib/session";

const field = (form: FormData | null, name: string) => {
  const value = form?.get(name);
  return typeof value === "string" ? value : "";
};

export async function POST(request: NextRequest) {
  const form = await request.formData().catch(() => null);
  const next = safeNext(field(form, "next"));
  const back = new URL(next, request.nextUrl.origin);
  const done = (status: string | null, session?: Parameters<typeof encodeSession>[0]) => {
    if (status) back.searchParams.set("signin", status);
    const response = NextResponse.redirect(back, 303);
    if (session) response.cookies.set(SESSION_COOKIE, encodeSession(session), cookieOptions(SESSION_MAX_AGE_S));
    response.headers.set("Cache-Control", "no-store");
    return response;
  };
  // Only this site's own form may sign someone in.
  const origin = request.headers.get("origin");
  if (origin && origin !== request.nextUrl.origin) return done("failed");

  const email = field(form, "email").trim().toLowerCase().slice(0, 320);
  if (!email.includes("@")) return done("missing");
  if (field(form, "intent") === "reset") {
    await sendPasswordReset(email);
    // The same answer whether or not the account exists.
    return done("reset");
  }
  const password = field(form, "password").slice(0, 200);
  if (!password) return done("missing");
  const result = await signInWithPassword(email, password);
  return "session" in result ? done(null, result.session) : done(result.error);
}
