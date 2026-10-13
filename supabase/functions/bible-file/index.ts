// bible-file: a short-lived download link for a licensed Bible.
//
// POST /functions/v1/bible-file  { id }  →  { url }   (404 if not offered)
//
// Licensed Bibles (from the Digital Bible Library) are never in the public
// "bibles" bucket: their files live in the private "licensed-bibles" bucket
// and the app asks here for a link that works for ten minutes. A link is
// given only while the catalog row is enabled with rights = 'licensed', so
// turning a row off (a licence ending) stops new downloads at once, and the
// app removes copies already downloaded (BibleLibrary).
//
// Deploy: supabase functions deploy bible-file   (JWT verification on; the
// app calls it with the anon key, no account needed, as every Bible is free).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { LICENSED_BUCKET, LINK_SECONDS, licensedObjectPath, parseRequest } from "./lib.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const request = parseRequest(await req.json().catch(() => null));
  if (!request) return json({ error: "Which Bible?" }, 400);

  const { data: row, error } = await admin
    .from("bible_translations")
    .select("file_url")
    .eq("id", request.id)
    .eq("enabled", true)
    .eq("rights", "licensed")
    .maybeSingle();
  if (error) {
    console.error("bible-file", error.message);
    return json({ error: "Try again later." }, 500);
  }
  const path = row ? licensedObjectPath(row.file_url) : null;
  if (!path) return json({ error: "This Bible isn't offered." }, 404);

  const { data: signed, error: signError } = await admin.storage.from(LICENSED_BUCKET).createSignedUrl(path, LINK_SECONDS);
  if (signError || !signed) {
    console.error("bible-file sign", signError?.message);
    return json({ error: "Try again later." }, 500);
  }
  return json({ url: signed.signedUrl }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
