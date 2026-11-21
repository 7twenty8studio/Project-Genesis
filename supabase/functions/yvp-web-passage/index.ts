// yvp-web-passage: a passage from a YouVersion Platform Bible for a church
// sermon page on the web (VRS-18).
//
// POST /functions/v1/yvp-web-passage  { bible: "NIV", start: 40011028, end: 40011030 }
//   → { bible, name, language, license, publisherUrl, verses: [{ c, v, k, t, p?, n?: [{ o, t }] }] }
//   (KJV verse ids, one book, at most two chapters: Biblica's display limit.)
//
// Served only while the `web_youversion` switch is on and the Bible's row in
// public.youversion_bibles is enabled with web_allowed (owner, 21 November
// 2026: on for every YouVersion Bible we offer; turning a row's web_allowed
// off removes it from the web at once, the app keeps it). Every footnote is
// returned with the text, and the page links to the publisher, as the
// publishers' agreements ask of the app (LICENSED_BIBLES.md › 5).
//
// Chapters come through the same shared pace and Cache-Control-following
// cache as the app's downloads (../yvp-bible/platform.ts), with the web
// app's own Platform key, the Supabase secret YVP_WEB_APP_KEY, which never
// leaves this function. Answers to the browser are never cached (no-store).
//
// Deploy: supabase functions deploy yvp-web-passage --no-verify-jwt
// (guests have no account; browsers on versely.7twenty8studio.com only, plus
// YVP_WEB_ORIGINS, comma separated, e.g. http://localhost:3000).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../sermon-events/lib.ts";
import { platform, RateLimited } from "../yvp-bible/platform.ts";
import { parseChapter } from "../yvp-bible/lib.ts";
import { parsePassageRequest, webVerses } from "./lib.ts";

const APP_KEY = Deno.env.get("YVP_WEB_APP_KEY")?.trim() ?? "";
const ORIGINS = ["https://versely.7twenty8studio.com",
  ...(Deno.env.get("YVP_WEB_ORIGINS") ?? "").split(",").map((o) => o.trim()).filter(Boolean)];
// A reader is waiting: give up sooner than the app's downloads do.
const WAIT_BUDGET_MS = 20_000;
const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const { freshChapters, fetchChapter } = platform(admin, APP_KEY, "yvp-web-passage");

Deno.serve(async (req) => {
  const cors = corsHeaders(req.headers.get("Origin"), ORIGINS);
  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  if (!APP_KEY) return json({ error: "YouVersion Bibles aren't set up on the web yet." }, 503);
  const request = parsePassageRequest(await req.json().catch(() => null));
  if (!request) return json({ error: "Which Bible and verses? (One book, at most two chapters.)" }, 400);

  const [{ data: flag }, { data: row, error }] = await Promise.all([
    admin.from("feature_flags").select("enabled").eq("key", "web_youversion").maybeSingle(),
    admin.from("youversion_bibles")
      .select("yvp_id, name, language, license, publisher_url")
      .eq("id", request.bible).eq("enabled", true).eq("web_allowed", true)
      .maybeSingle(),
  ]);
  if (error) {
    console.error("yvp-web-passage", error.message);
    return json({ error: "Try again later." }, 500);
  }
  if (!flag?.enabled || !row) return json({ error: "This Bible isn't offered on the web." }, 404);

  const deadline = Date.now() + WAIT_BUDGET_MS;
  try {
    const cached = await freshChapters(row.yvp_id, request.book);
    const lifetimes = new Map<number, number>();
    const chapters = [];
    for (const n of request.chapters) {
      const hit = cached.get(n);
      const chapter = hit ? parseChapter(n, hit.content, hit.reference) : await fetchChapter(row.yvp_id, request.book, n, true, lifetimes, deadline);
      if (chapter) chapters.push(chapter);
    }
    const book = Math.floor(request.start / 1_000_000);
    return json({
      bible: request.bible,
      name: row.name,
      language: row.language,
      license: row.license,
      publisherUrl: row.publisher_url ?? null,
      verses: webVerses(book, chapters, request.start, request.end),
    }, 200);
  } catch (error) {
    if (error instanceof RateLimited) return json({ error: "Busy. Try again in a moment.", retryAfter: error.retryAfter }, 429);
    console.error("yvp-web-passage", request.bible, request.book, error instanceof Error ? error.message : error);
    return json({ error: "Try again later." }, 502);
  }
});
