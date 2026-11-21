// The YouVersion Platform's chapters, shared by yvp-bible (the app's
// downloads) and yvp-web-passage (passages on church sermon pages): one pace
// for every reader (yvp_take_token), the shared cache that follows the
// Platform's Cache-Control exactly (yvp_chapter_cache) and any block the
// Platform gives (yvp_block). Each function passes its own app key, which
// never leaves the server.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { ageSeconds, cachePolicy, isFresh, type ParsedChapter, parseChapter } from "./lib.ts";

const API = "https://api.youversion.com/v1";

/** The Platform asked us to wait (HTTP 429), or our turn wouldn't come in time. */
export class RateLimited extends Error {
  constructor(readonly retryAfter: number) {
    super(`rate limited for ${retryAfter} s`);
  }
}

export interface CachedChapter {
  content: string;
  reference: string;
  /** What's left of its lifetime, in seconds: a reader given this copy keeps it no longer. */
  remaining: number;
}

export function platform(admin: SupabaseClient, appKey: string, label: string) {
  /** The book's chapters still fresh in the shared cache, by chapter number. */
  async function freshChapters(bibleID: number, book: string): Promise<Map<number, CachedChapter>> {
    const fresh = new Map<number, CachedChapter>();
    const { data, error } = await admin
      .from("yvp_chapter_cache")
      .select("passage, content, reference, fetched_at, max_age, age_at_fetch")
      .eq("bible", bibleID)
      .like("passage", `${book}.%`);
    if (error) {
      // The cache is a saving, never a requirement: read from the Platform.
      console.warn(label, "cache read", error.message);
      return fresh;
    }
    const now = Date.now();
    for (const row of data ?? []) {
      const chapter = Number(String(row.passage).slice(book.length + 1));
      const entry = { fetchedAt: Date.parse(row.fetched_at), maxAge: row.max_age, ageAtFetch: row.age_at_fetch };
      if (Number.isInteger(chapter) && isFresh(entry, now)) {
        const remaining = Math.floor(entry.maxAge - entry.ageAtFetch - (now - entry.fetchedAt) / 1000);
        fresh.set(chapter, { content: row.content, reference: row.reference, remaining });
      }
    }
    return fresh;
  }

  /**
   * Waits for a turn to ask the Platform (one token from the shared pace).
   * Throws RateLimited when the turn wouldn't come before `deadline`.
   */
  async function takeTurn(deadline: number): Promise<void> {
    for (;;) {
      const { data, error } = await admin.rpc("yvp_take_token");
      if (error) {
        // Never let the pace itself stop reading: go slowly instead.
        console.warn(label, "pace", error.message);
        await new Promise((resolve) => setTimeout(resolve, 400));
        return;
      }
      const waitSeconds = Number(data) || 0;
      if (waitSeconds <= 0) return;
      const waitMs = Math.ceil(waitSeconds * 1000) + Math.floor(Math.random() * 150);
      if (Date.now() + waitMs > deadline) throw new RateLimited(Math.max(2, Math.ceil(waitSeconds)));
      await new Promise((resolve) => setTimeout(resolve, waitMs));
    }
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
    if (error) console.warn(label, "cache write", error.message);
  }

  /** One chapter, parsed; null when the Bible doesn't have it and `optional`. */
  async function fetchChapter(bibleID: number, book: string, chapter: number, optional: boolean, lifetimes: Map<number, number>, deadline: number): Promise<ParsedChapter | null> {
    // Notes too: Biblica's licence requires every footnote to be included.
    const url = `${API}/bibles/${bibleID}/passages/${book}.${chapter}?format=html&include_headings=true&include_notes=true`;
    for (let attempt = 0; ; attempt++) {
      await takeTurn(deadline);
      let response: Response;
      try {
        response = await fetch(url, { headers: { "X-YVP-App-Key": appKey, Accept: "application/json" } });
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
        // Every reader waits it out: asking during a block can prolong it.
        const { error } = await admin.rpc("yvp_block", { p_seconds: Math.ceil(retryAfter) });
        if (error) console.warn(label, "block", error.message);
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

  return { freshChapters, fetchChapter };
}

function wait(attempt: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, 400 * 2 ** attempt));
}
