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
import { chapterCount, type ParsedChapter, parseChapter, parseRequest } from "./lib.ts";
import { platform, RateLimited } from "./platform.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const APP_KEY = Deno.env.get("YVP_APP_KEY")?.trim() ?? "";
// Chapters read at once for one book. Every request to the Platform also
// takes a token from one pace shared by all readers (public.yvp_take_token:
// 150 a minute): the Platform blocks bursts for five minutes even far below
// its hourly limit (about 575 requests in 22 seconds did, 24 October 2026).
const CONCURRENCY = 2;
// How long one call may wait for its turn. Chapters fetched meanwhile are in
// the shared cache, so when this runs out the app's next call (after
// `retryAfter`) carries on from there.
const WAIT_BUDGET_MS = 55_000;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const { freshChapters, fetchChapter } = platform(admin, APP_KEY, "yvp-bible");

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

  const deadline = Date.now() + WAIT_BUDGET_MS;
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
      return fetchChapter(row.yvp_id, request.book, n, n > count, lifetimes, deadline);
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
