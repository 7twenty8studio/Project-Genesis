// Pure helpers for bible-file (Node tests in lib.test.ts).

/** The private bucket licensed Bibles live in (never public). */
export const LICENSED_BUCKET = "licensed-bibles";
/** How long a download link works, in seconds. */
export const LINK_SECONDS = 600;

export interface FileRequest {
  id: string;
  /** For a Premium Bible: the App Store subscription's signed transaction. */
  signedTransaction?: string;
}

/** The request body, or null. Ids are the catalog's: 2-8 capitals or digits. */
export function parseRequest(body: unknown): FileRequest | null {
  if (!body || typeof body !== "object") return null;
  const { id, signedTransaction } = body as { id?: unknown; signedTransaction?: unknown };
  if (typeof id !== "string" || !/^[A-Z0-9]{2,8}$/.test(id)) return null;
  return typeof signedTransaction === "string" && signedTransaction.length > 0 && signedTransaction.length < 20_000
    ? { id, signedTransaction }
    : { id };
}

/** The bearer token from an Authorization header ("" when none). */
export function bearerToken(header: string | null): string {
  return header?.replace(/^Bearer\s+/i, "").trim() ?? "";
}

/**
 * The object's path in the licensed bucket, from a catalog row's file_url
 * ("https://<project>.supabase.co/storage/v1/object/licensed-bibles/NIV-1.sqlite.deflate"),
 * or null when the row doesn't point into that bucket (a public-domain
 * Bible, or a mistake), so nothing outside the bucket is ever signed.
 */
export function licensedObjectPath(fileURL: string): string | null {
  let url: URL;
  try {
    url = new URL(fileURL);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  const prefix = `/storage/v1/object/${LICENSED_BUCKET}/`;
  if (!url.pathname.startsWith(prefix)) return null;
  const path = decodeURIComponent(url.pathname.slice(prefix.length));
  return /^[A-Za-z0-9][A-Za-z0-9._-]*\.sqlite\.deflate$/.test(path) ? path : null;
}
