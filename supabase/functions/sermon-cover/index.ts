// sermon-cover: a church sermon's cover picture, for this caller, now
// (VRS-18). The only way a cover leaves the private sermon-covers bucket:
// no client can read the bucket (20261121000000), so there are no signed
// links, and an unpublish, a ban, a restriction to members, a hidden sermon
// or a switch turned off stops the very next request.
//
// GET /functions/v1/sermon-cover?name=<group>/<sermon>/<cover>.jpg
//   Authorization: Bearer <the reader's or leader's access token, or the anon key for guests>
//   -> 200 image/jpeg, private, no-store; 404 for anything the caller may not have.
//
// It asks sermon_cover_access(name) with the caller's own token (so the
// database decides with their account, membership, bans and both switches)
// and only then downloads the file with the service role. Called by the
// web's /s/<slug>/cover and /studio/<id>/cover routes (server to server) and
// by the app. Deployed with --no-verify-jwt so guests' anon key is accepted
// whatever its format; PostgREST checks every token in the access call, and
// a token it refuses gets no picture.
import { coverName, isJpeg, parseAccess, PRIVATE_HEADERS } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const notFound = () => new Response(null, { status: 404, headers: PRIVATE_HEADERS });

Deno.serve(async (req) => {
  if (req.method !== "GET") return new Response(null, { status: 405, headers: PRIVATE_HEADERS });
  const name = coverName(req.url);
  if (!name) return notFound();
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim() || ANON_KEY;
  try {
    const check = await fetch(`${SUPABASE_URL}/rest/v1/rpc/sermon_cover_access`, {
      method: "POST",
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_name: name }),
    });
    const access = parseAccess(check.status, await check.json().catch(() => undefined));
    if (!access) return notFound();
    const file = await fetch(`${SUPABASE_URL}/storage/v1/object/sermon-covers/${name}`, {
      headers: { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` },
    });
    if (!file.ok) return notFound();
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!isJpeg(bytes)) return notFound();
    return new Response(bytes, { status: 200, headers: { ...PRIVATE_HEADERS, "Content-Type": "image/jpeg" } });
  } catch (error) {
    console.error("sermon-cover", error instanceof Error ? error.message : "failed");
    return notFound();
  }
});
