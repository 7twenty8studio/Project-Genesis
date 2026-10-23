// yvp-bible: one book of a YouVersion Platform Bible, in the app's format.
//
// POST /functions/v1/yvp-bible  { id: "NIV", book: "GEN" [, chapter: 3] }
//   → { id, book, chapters: [{ chapter, maxAge, verses: [{ verse, last?, text, paragraph, poetry }],
//                              headings: [{ beforeVerse, text }],
//                              notes: [{ verse, offset, text }] }] }
// Without `chapter`, the whole book; with it, that chapter only (the app
// refreshing a chapter it shows). A chapter's `maxAge` is how long, in
// seconds, the Platform lets it be kept before it's fetched again (its
// Cache-Control, less the time our shared copy has already been kept),
// which the app follows.
//
// The app builds a YouVersion Bible on the device from these, book by book
// (BibleLibrary → YouVersionBibleBuilder), so it reads offline like every
// other Bible. Our agreement with YouVersion (LICENSED_BIBLES.md › 5) allows
// storing the Bible on the device; it is always free to read and never used
// in paid features.
//
// Chapters are shared between readers through public.yvp_chapter_cache, a
// shared HTTP cache that follows the Platform's Cache-Control header exactly
// (RFC 9111; YouVersion confirmed that's how caching complies): a chapter is
// reused only while fresh ("public, max-age=3600" today), never stored when
// the header says private, no-store or no-cache, and expired copies are
// deleted hourly.
//
// Only Bibles listed in public.youversion_bibles with enabled = true are
// served, so turning a row off stops new downloads at once, and the app
// removes copies already on devices (BibleLibrary).
//
// The Platform app key is the Supabase secret YVP_APP_KEY and never leaves
// this function.
//
// Deploy: supabase functions deploy yvp-bible   (JWT verification on; the
// app calls it with the anon key or the account's token).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { ageSeconds, cachePolicy, chapterCount, isFresh, type ParsedChapter, parseChapter, parseRequest } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const APP_KEY = Deno.env.get("YVP_APP_KEY")?.trim() ?? "";
const API = "https://api.youversion.com/v1";
// Chapters read at once for one book. The Platform limits requests per app
// key (a burst of about a thousand at once was refused for five minutes),
// and the app asks for two books at a time, so a whole Bible stays gentle.
const CONCURRENCY = 4;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  if (!APP_KEY) return json({ error: "YouVersion Bibles aren't set up yet." }, 503);
  const request = parseRequest(await req.json().catch(() => null));
  if (!request) return json({ error: "Which Bible and book?" }, 400);

  const { data: row, error } = await admin
    .from("youversion_bibles")
    .select("yvp_id")
    .eq("id", request.id)
    .eq("enabled", true)
    .maybeSingle();
  if (error) {
    console.error("yvp-bible", error.message);
    return json({ error: "Try again later." }, 500);
  }
  if (!row) return json({ error: "This Bible isn't offered." }, 404);

  try {
    const count = chapterCount(request.book);
    // One past the KJV's count, in case a Bible numbers a book differently.
    const numbers = request.chapter ? [request.chapter] : Array.from({ length: count + 1 }, (_, i) => i + 1);
    const cached = await freshChapters(row.yvp_id, request.book);
    const lifetimes = new Map<number, number>();
    const chapters = (await mapLimited(numbers, CONCURRENCY, (n) => {
      const hit = cached.get(n);
      if (hit) {
        lifetimes.set(n, hit.remaining);
        return Promise.resolve(parseChapter(n, hit.content, hit.reference));
      }
      return fetchChapter(row.yvp_id, request.book, n, n > count, lifetimes);
    }))
      .filter((c): c is ParsedChapter => c !== null && c.verses.length > 0)
      .map((c) => ({ ...c, maxAge: Math.max(0, lifetimes.get(c.chapter) ?? 0) }));
    if (chapters.length === 0) return json({ error: "This book isn't in this Bible." }, 404);
    return json({ id: request.id, book: request.book, chapters }, 200);
  } catch (error) {
    if (error instanceof RateLimited) {
      console.warn("yvp-bible rate limited", request.id, request.book, error.retryAfter);
      return json({ error: "Busy. Try again later.", retryAfter: error.retryAfter }, 429);
    }
    console.error("yvp-bible", request.id, request.book, error instanceof Error ? error.message : error);
    return json({ error: "Try again later." }, 502);
  }
});

/** The Platform asked us to wait (HTTP 429). */
class RateLimited extends Error {
  constructor(readonly retryAfter: number) {
    super(`rate limited for ${retryAfter} s`);
  }
}

/** The book's chapters still fresh in the shared cache, by chapter number. */
async function freshChapters(bibleID: number, book: string): Promise<Map<number, { content: string; reference: string; remaining: number }>> {
  const fresh = new Map<number, { content: string; reference: string; remaining: number }>();
  const { data, error } = await admin
    .from("yvp_chapter_cache")
    .select("passage, content, reference, fetched_at, max_age, age_at_fetch")
    .eq("bible", bibleID)
    .like("passage", `${book}.%`);
  if (error) {
    // The cache is a saving, never a requirement: read from the Platform.
    console.warn("yvp-bible cache read", error.message);
    return fresh;
  }
  const now = Date.now();
  for (const row of data ?? []) {
    const chapter = Number(String(row.passage).slice(book.length + 1));
    const entry = { fetchedAt: Date.parse(row.fetched_at), maxAge: row.max_age, ageAtFetch: row.age_at_fetch };
    if (Number.isInteger(chapter) && isFresh(entry, now)) {
      // What's left of its lifetime: a reader given this copy keeps it no longer.
      const remaining = Math.floor(entry.maxAge - entry.ageAtFetch - (now - entry.fetchedAt) / 1000);
      fresh.set(chapter, { content: row.content, reference: row.reference, remaining });
    }
  }
  return fresh;
}

/** Keeps a chapter response for other readers, if its Cache-Control allows. */
async function store(bibleID: number, passage: string, response: Response, content: string, reference: string): Promise<void> {
  const policy = cachePolicy(response.headers.get("cache-control"));
  if (!policy.store) return;
  const age = ageSeconds(response.headers.get("age"));
  if (age >= policy.maxAge) return;
  const { error } = await admin.from("yvp_chapter_cache").upsert({
    bible: bibleID, passage, content, reference,
    fetched_at: new Date().toISOString(), max_age: policy.maxAge, age_at_fetch: age,
  });
  if (error) console.warn("yvp-bible cache write", error.message);
}

/** One chapter, parsed; null when the Bible doesn't have it. */
async function fetchChapter(bibleID: number, book: string, chapter: number, optional: boolean, lifetimes: Map<number, number>): Promise<ParsedChapter | null> {
  // Notes too: Biblica's licence requires every footnote to be included.
  const url = `${API}/bibles/${bibleID}/passages/${book}.${chapter}?format=html&include_headings=true&include_notes=true`;
  for (let attempt = 0; ; attempt++) {
    let response: Response;
    try {
      response = await fetch(url, { headers: { "X-YVP-App-Key": APP_KEY, Accept: "application/json" } });
    } catch (error) {
      if (attempt < 3) {
        await wait(attempt);
        continue;
      }
      throw error;
    }
    if (response.status === 404) {
      await response.body?.cancel();
      if (optional) return null;
      throw new Error(`${book} ${chapter} not found`);
    }
    if (response.status === 429) {
      await response.body?.cancel();
      const retryAfter = Number(response.headers.get("retry-after") ?? "60") || 60;
      // A short pause is waited out; a long one goes back to the app.
      if (retryAfter <= 5 && attempt < 3) {
        await new Promise((resolve) => setTimeout(resolve, retryAfter * 1000));
        continue;
      }
      throw new RateLimited(retryAfter);
    }
    if (response.status >= 500 && attempt < 3) {
      await response.body?.cancel();
      await wait(attempt);
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`${book} ${chapter}: HTTP ${response.status}`);
    }
    const body = await response.json() as { content?: unknown; reference?: unknown };
    if (typeof body.content !== "string") throw new Error(`${book} ${chapter}: no content`);
    const reference = typeof body.reference === "string" ? body.reference : "";
    const policy = cachePolicy(response.headers.get("cache-control"));
    // No lifetime (or private/no-store): 0, so the app refreshes it next time.
    lifetimes.set(chapter, policy.store ? policy.maxAge - ageSeconds(response.headers.get("age")) : 0);
    await store(bibleID, `${book}.${chapter}`, response, body.content, reference);
    return parseChapter(chapter, body.content, reference);
  }
}

function wait(attempt: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 400 * 2 ** attempt));
}

/** `items` mapped with at most `limit` running at once, in order. */
async function mapLimited<T, R>(items: T[], limit: number, work: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await work(items[index]);
    }
  });
  await Promise.all(runners);
  return results;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
