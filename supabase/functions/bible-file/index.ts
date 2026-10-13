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
// Premium Bibles (premium = true: the publisher charges Versely a fee) need
// Premium: the App Store subscription's signed transaction in the body (no
// account needed), or a signed-in account's token with a grant or a saved
// subscription (_shared/premium.ts). Free Bibles need neither.
//
// Deploy: supabase functions deploy bible-file   (JWT verification on; the
// app calls it with the anon key, or the account's token for a Premium Bible).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { hasPremium } from "../_shared/premium.ts";
import { bearerToken, LICENSED_BUCKET, LINK_SECONDS, licensedObjectPath, parseRequest } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const request = parseRequest(await req.json().catch(() => null));
  if (!request) return json({ error: "Which Bible?" }, 400);

  const { data: row, error } = await admin
    .from("bible_translations")
    .select("file_url, premium")
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

  if (row.premium) {
    const userID = await signedInUser(bearerToken(req.headers.get("Authorization")));
    if (!(await hasPremium(admin, userID, request.signedTransaction))) {
      return json({ error: "This Bible comes with Premium." }, 403);
    }
  }

  const { data: signed, error: signError } = await admin.storage.from(LICENSED_BUCKET).createSignedUrl(path, LINK_SECONDS);
  if (signError || !signed) {
    console.error("bible-file sign", signError?.message);
    return json({ error: "Try again later." }, 500);
  }
  return json({ url: signed.signedUrl }, 200);
});

/** The signed-in account behind a token, or null (the anon key, or none). */
async function signedInUser(token: string): Promise<string | null> {
  if (!token || token === SUPABASE_ANON_KEY) return null;
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.auth.getUser(token);
  return error || !data.user ? null : data.user.id;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
