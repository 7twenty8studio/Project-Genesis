// ops-dashboard: the data behind the operations dashboard page (on the
// 7twenty8 website). Only people listed in public.ops_admins may use it.
//
// POST /functions/v1/ops-dashboard with the admin's access token and
//   { action: "overview" }                      → { items, sources, metrics, email, generatedAt }
//   { action: "update", source, id, status?, priority?, note? }
//                                               → saves triage (priority null = back to automatic)
//   { action: "testEmail" }                     → sends a test email through Resend
//
// Keys for Sentry, App Store Connect and Resend stay here as secrets; the
// page never sees them.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { PRIORITIES, SOURCES } from "../_shared/ops.ts";
import { collect, emailConfigured, metrics, sendEmail } from "../_shared/opsCollect.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Where the page is hosted, e.g. "https://7twenty8studio.com"; "*" allows any.
const ALLOWED_ORIGINS = (Deno.env.get("OPS_ALLOWED_ORIGINS") ?? "*").split(",").map((s) => s.trim()).filter(Boolean);

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function cors(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowed = ALLOWED_ORIGINS.includes("*") ? "*" : ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0] ?? "";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
}

Deno.serve(async (req) => {
  const headers = cors(req);
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...headers, "content-type": "application/json" } });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  try {
    // Who's asking: a signed-in account whose email is in ops_admins.
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false } });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    const email = userData?.user?.email?.toLowerCase();
    if (userError || !email) return json({ error: "Sign in first." }, 401);
    const { data: allowed, error: allowedError } = await admin.from("ops_admins").select("email").eq("email", email).maybeSingle();
    if (allowedError) throw allowedError;
    if (!allowed) return json({ error: "This account isn't on the dashboard's list.", email }, 403);

    const body = await req.json().catch(() => ({}));
    switch (body?.action) {
      case "overview": {
        const [{ items, sources }, usage] = await Promise.all([collect(admin), metrics(admin)]);
        return json({ items, sources, metrics: usage, email: emailConfigured() ? "ok" : "not_configured", generatedAt: new Date().toISOString(), viewer: email });
      }
      case "update": {
        const source = String(body.source ?? "");
        const id = String(body.id ?? "");
        if (!SOURCES.includes(source as never) || !id || id.length > 200) return json({ error: "Unknown item." }, 400);
        const row: Record<string, unknown> = { source, external_id: id, updated_at: new Date().toISOString() };
        if (body.status !== undefined) {
          if (!["new", "seen", "resolved"].includes(body.status)) return json({ error: "Unknown status." }, 400);
          row.status = body.status;
        }
        if (body.priority !== undefined) {
          if (body.priority !== null && !PRIORITIES.includes(body.priority)) return json({ error: "Unknown priority." }, 400);
          row.priority = body.priority;
        }
        if (body.note !== undefined) row.note = body.note === null ? null : String(body.note).slice(0, 2000);
        const { error } = await admin.from("ops_items").upsert(row, { onConflict: "source,external_id" });
        if (error) throw error;
        // In-app feedback keeps its own "resolved" too (read elsewhere).
        if (source === "feedback" && body.status !== undefined && /^[0-9a-f-]{36}$/i.test(id)) {
          const { error: feedbackError } = await admin.from("app_feedback").update({ resolved: body.status === "resolved" }).eq("id", id);
          if (feedbackError) throw feedbackError;
        }
        return json({ ok: true });
      }
      case "testEmail": {
        const sent = await sendEmail(
          "[Versely] Test email from the operations dashboard",
          `<p style="font-family:-apple-system,Helvetica,Arial,sans-serif">Alerts reach you here. Requested by ${email} at ${new Date().toISOString()}.</p>`,
        );
        return sent ? json({ ok: true }) : json({ error: "Email isn't set up: add the RESEND_API_KEY and OPS_ALERT_EMAIL secrets." }, 400);
      }
      default:
        return json({ error: "Unknown action." }, 400);
    }
  } catch (error) {
    console.error("ops-dashboard failed", error);
    return json({ error: "Something went wrong on the server." }, 500);
  }
});
