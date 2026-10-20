// yvp-bible: one book of a YouVersion Platform Bible, in the app's format.
//
// POST /functions/v1/yvp-bible  { id: "NIV", book: "GEN" }
//   → { id, book, chapters: [{ chapter, verses: [{ verse, last?, text, paragraph, poetry }],
//                              headings: [{ beforeVerse, text }] }] }
//
// The app builds a YouVersion Bible on the device from these, book by book
// (BibleLibrary → YouVersionBibleBuilder), so it reads offline like every
// other Bible. Nothing is stored here: each request goes to the Platform.
// Our agreement with YouVersion (LICENSED_BIBLES.md › 5) allows storing the
// Bible on the device; it is always free to read and never used in paid
// features.
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
    const numbers = Array.from({ length: count + 1 }, (_, i) => i + 1);
    const chapters = (await mapLimited(numbers, CONCURRENCY, (n) => fetchChapter(row.yvp_id, request.book, n, n > count)))
      .filter((c): c is ParsedChapter => c !== null && c.verses.length > 0);
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

/** One chapter, parsed; null when the Bible doesn't have it. */
async function fetchChapter(bibleID: number, book: string, chapter: number, optional: boolean): Promise<ParsedChapter | null> {
  const url = `${API}/bibles/${bibleID}/passages/${book}.${chapter}?format=html&include_headings=true`;
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
    return parseChapter(chapter, body.content, typeof body.reference === "string" ? body.reference : "");
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
