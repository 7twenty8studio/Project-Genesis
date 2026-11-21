// The person's session in server components and route handlers.
import { cookies } from "next/headers";
import { decodeSession, SESSION_COOKIE, type Session } from "./session";

/** The session the proxy has already refreshed for this request (or null for a guest). */
export async function currentSession(): Promise<Session | null> {
  const store = await cookies();
  return decodeSession(store.get(SESSION_COOKIE)?.value);
}
