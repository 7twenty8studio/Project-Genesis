// Project Genesis: delete the signed-in person's account (App Store guideline
// 5.1.1(v) requires account deletion in the app).
//
// First empties the person's folder in the private `attachments` storage
// bucket (photos, recordings, PDFs and Pencil pages on prayers and sermons):
// files aren't rows, so nothing cascades to them. If that fails the account
// is left as it was and the app asks to try again, so no files are orphaned.
// Then deletes the auth user; every table that references auth.users uses
// "on delete cascade" (or "set null" for feedback), so their highlights,
// notes, plans, prayers, memory verses, sermon notes, attachment details,
// group memberships and posts go too.
//
// Deploy: supabase functions deploy delete-account
// (Uses the built-in SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY; nothing to configure.)

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const ATTACHMENTS_BUCKET = "attachments";
const PAGE = 1000;
const REMOVE_BATCH = 100;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });
  const { data, error } = await userClient.auth.getUser(token);
  if (error || !data.user) return json({ error: "Sign in again to delete your account." }, 401);

  const removal = await removeAttachments(data.user.id);
  if (removal) {
    console.error("delete-account attachments", removal);
    return json({ error: "Your account couldn't be deleted. Please try again." }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    console.error("delete-account", deleteError.message);
    return json({ error: "Your account couldn't be deleted. Please try again." }, 500);
  }
  return json({ deleted: true }, 200);
});

/**
 * Removes every file in the person's folder ("<user id>/...") of the
 * attachments bucket, listing by prefix and removing in batches. Returns an
 * error message, or null when the folder is empty (or never existed).
 */
async function removeAttachments(userID: string): Promise<string | null> {
  const bucket = admin.storage.from(ATTACHMENTS_BUCKET);
  const folder = userID.toLowerCase();
  // Removing shifts what's left, so always list from the start until it's empty.
  for (let round = 0; round < 1000; round++) {
    const { data: files, error } = await bucket.list(folder, { limit: PAGE, offset: 0 });
    if (error) {
      // No bucket yet (the migration hasn't been run): nothing to remove.
      if (/not.?found/i.test(error.message)) return null;
      return error.message;
    }
    const paths = (files ?? []).filter((file) => file.name).map((file) => `${folder}/${file.name}`);
    if (paths.length === 0) return null;
    for (let start = 0; start < paths.length; start += REMOVE_BATCH) {
      const { error: removeError } = await bucket.remove(paths.slice(start, start + REMOVE_BATCH));
      if (removeError) return removeError.message;
    }
  }
  return "Too many files to remove.";
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
