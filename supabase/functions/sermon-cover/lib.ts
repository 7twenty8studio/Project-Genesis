// sermon-cover: the pure parts (Node tests in lib.test.ts).
//
// A cover is served only after the database says, as the caller, that they
// may have it right now (sermon_cover_access). No client can read the
// sermon-covers bucket itself, so nobody can make a signed link that would
// outlive an unpublish, a ban or a restriction to members.

/** <group>/<sermon>/<cover>.jpg, lower-case UUIDs, nothing else. */
export const COVER_NAME =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$/;

export type CoverAccess = "edit" | "read";

/** The cover named in ?name=, or null when it isn't a cover's name. */
export function coverName(url: string): string | null {
  const name = new URL(url).searchParams.get("name") ?? "";
  return COVER_NAME.test(name) ? name : null;
}

/** sermon_cover_access's answer as PostgREST returns it: "edit", "read" or null. Anything else (an error) is no access. */
export function parseAccess(status: number, body: unknown): CoverAccess | null {
  if (status !== 200) return null;
  return body === "edit" || body === "read" ? body : null;
}

/** Never stored by a browser or a proxy, never read as anything but a JPEG. */
export const PRIVATE_HEADERS: Record<string, string> = {
  "Cache-Control": "private, no-store, max-age=0",
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "default-src 'none'; sandbox",
  "Cross-Origin-Resource-Policy": "same-site",
};

/** A JPEG starts FF D8 FF; anything else in the bucket isn't served. */
export function isJpeg(bytes: Uint8Array): boolean {
  return bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}
