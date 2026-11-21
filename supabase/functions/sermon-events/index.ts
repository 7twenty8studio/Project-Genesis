// sermon-events: counts a church sermon being opened, a passage in it being
// opened, or its notes being saved (VRS-18). Aggregate counts only, for the
// church's Studio; nothing about the person is kept (lib.ts).
//
// POST /functions/v1/sermon-events  { slug, kind: "open" | "passage" | "save" }
//   -> 204 always for a well-formed request (counted or not, so the answer
//      says nothing about a sermon or a visitor), 400 otherwise.
//
// Called by the guest page in the browser and by the app. Deployed with
// --no-verify-jwt (guests have no account): it only ever adds to a published
// sermon's counts, once per visitor per day and at most 60 a minute per
// sermon (record_sermon_event, service role only), and ignores link previews.
//
// Secrets: SERMON_EVENTS_SECRET (32+ random characters; changing it only
// restarts today's de-duplication). Optional SERMON_EVENTS_ORIGINS, a
// comma-separated list of extra browser origins (e.g. http://localhost:3000).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientAddress, corsHeaders, dayKey, EventError, isAutomated, parseEventRequest, visitorHash } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SECRET = Deno.env.get("SERMON_EVENTS_SECRET") ?? "";
const ORIGINS = ["https://versely.7twenty8studio.com",
  ...(Deno.env.get("SERMON_EVENTS_ORIGINS") ?? "").split(",").map((o) => o.trim()).filter(Boolean)];

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

Deno.serve(async (req) => {
  const cors = corsHeaders(req.headers.get("Origin"), ORIGINS);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return new Response(null, { status: 405, headers: cors });
  try {
    const event = parseEventRequest(await req.json().catch(() => null));
    const userAgent = req.headers.get("User-Agent") ?? "";
    if (!SECRET || isAutomated(userAgent)) return new Response(null, { status: 204, headers: cors });
    const visitor = await visitorHash(SECRET, dayKey(new Date()), clientAddress(req.headers), userAgent);
    const { error } = await admin.rpc("record_sermon_event", { p_slug: event.slug, p_kind: event.kind, p_visitor: visitor });
    if (error) console.error("record_sermon_event", error.message);
    return new Response(null, { status: 204, headers: cors });
  } catch (error) {
    if (error instanceof EventError) {
      return new Response(JSON.stringify({ error: error.message }), { status: 400, headers: { ...cors, "Content-Type": "application/json" } });
    }
    console.error("sermon-events", error instanceof Error ? error.message : "failed");
    return new Response(null, { status: 204, headers: cors });
  }
});
