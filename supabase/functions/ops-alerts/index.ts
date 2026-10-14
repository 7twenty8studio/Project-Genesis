// ops-alerts: emails urgent items as they arrive, and a daily digest.
// Run by pg_cron (migration 20261018030000): { kind: "check" } every five
// minutes and { kind: "digest" } each morning; { kind: "status" } is a
// health check. Deployed with --no-verify-jwt;
// it proves the caller with the random secret the schedule reads from the
// Vault (public.ops_cron_secret_matches), so nobody else can trigger mail.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { alertEmail, digestEmail, digestSummary, itemsToAlert, localDay } from "../_shared/ops.ts";
import { collect, dashboardURL, emailConfigured, metrics, sendEmail } from "../_shared/opsCollect.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const secret = req.headers.get("x-ops-secret") ?? "";
  const { data: matches, error: secretError } = await admin.rpc("ops_cron_secret_matches", { p_secret: secret });
  if (secretError || matches !== true) return json({ error: "Not allowed." }, 403);

  try {
    const body = await req.json().catch(() => ({}));
    const now = new Date();
    // A health check (from SQL: select public.ops_call_alerts('status')):
    // which sources answer, and how many open items of each priority. No
    // email, nothing personal.
    if (body?.kind === "status") {
      const { items, sources } = await collect(admin);
      return json({ ok: true, sources, email: emailConfigured(), open: digestSummary(items, now).open, items: items.length });
    }
    if (!emailConfigured()) return json({ ok: true, skipped: "email not configured" });
    const { items } = await collect(admin);

    if (body?.kind === "digest") {
      const day = localDay(now);
      const { data: state } = await admin.from("ops_state").select("value").eq("key", "last_digest").maybeSingle();
      if (state?.value?.day === day && body?.force !== true) return json({ ok: true, skipped: "digest already sent today" });
      const summary = { ...digestSummary(items, now), metrics: (await metrics(admin)) ?? undefined };
      const { subject, html } = digestEmail(summary, day, dashboardURL());
      await sendEmail(subject, html);
      await admin.from("ops_state").upsert({ key: "last_digest", value: { day, at: now.toISOString() }, updated_at: now.toISOString() });
      return json({ ok: true, digest: day, newItems: summary.newSince.length });
    }

    const due = itemsToAlert(items, now);
    if (due.length === 0) return json({ ok: true, alerted: 0 });
    const { subject, html } = alertEmail(due, dashboardURL());
    await sendEmail(subject, html);
    // Remember they were emailed (and re-open anything that came back).
    const rows = due.map((item) => ({
      source: item.source,
      external_id: item.id,
      status: item.status,
      alerted_at: now.toISOString(),
      updated_at: now.toISOString(),
    }));
    const { error } = await admin.from("ops_items").upsert(rows, { onConflict: "source,external_id" });
    if (error) throw error;
    return json({ ok: true, alerted: due.length });
  } catch (error) {
    console.error("ops-alerts failed", error);
    return json({ error: "Something went wrong." }, 500);
  }
});
