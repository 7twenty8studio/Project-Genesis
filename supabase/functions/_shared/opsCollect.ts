// Gathers everything the operations dashboard shows, from the database,
// Sentry and App Store Connect (TestFlight), and sends email through Resend.
// Shared by ops-dashboard and ops-alerts. Every outside source is optional:
// without its secrets it's reported as "not set up" and the rest still works.
import {
  appStoreConnectToken,
  type AscResource,
  feedbackItem,
  type FeedbackRow,
  type OpsItem,
  reportItems,
  type ReportRow,
  sentryItem,
  type SentryIssue,
  sortItems,
  testFlightItems,
  type TriageRow,
  withTriage,
} from "./ops.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

export type SourceState = "ok" | "not_configured" | string;

export interface Collected {
  items: OpsItem[];
  sources: Record<string, SourceState>;
}

const env = (name: string) => Deno.env.get(name)?.trim() || undefined;

async function fetchJSON(url: string, headers: Record<string, string>): Promise<unknown> {
  const response = await fetch(url, { headers });
  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(`HTTP ${response.status}${body ? `: ${body.slice(0, 160)}` : ""}`);
  }
  return await response.json();
}

async function feedbackItems(admin: Admin): Promise<OpsItem[]> {
  const since = new Date(Date.now() - 120 * 86_400_000).toISOString();
  const { data, error } = await admin
    .from("app_feedback")
    .select("id, created_at, category, message, contact_email, app_version, os_version, device, language, context, resolved")
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(300);
  if (error) throw error;
  return ((data ?? []) as FeedbackRow[]).map(feedbackItem);
}

async function reports(admin: Admin): Promise<OpsItem[]> {
  const since = new Date(Date.now() - 60 * 86_400_000).toISOString();
  const { data, error } = await admin
    .from("content_reports")
    .select("id, content_type, content_id, reason, created_at, resolved_at, group_id")
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(500);
  if (error) throw error;
  return reportItems((data ?? []) as ReportRow[]);
}

async function sentry(): Promise<OpsItem[] | null> {
  const token = env("SENTRY_AUTH_TOKEN");
  const org = env("SENTRY_ORG");
  const project = env("SENTRY_PROJECT");
  if (!token || !org || !project) return null;
  const base = (env("SENTRY_API_BASE") ?? "https://sentry.io").replace(/\/$/, "");
  const url = `${base}/api/0/projects/${encodeURIComponent(org)}/${encodeURIComponent(project)}/issues/` +
    `?query=${encodeURIComponent("is:unresolved")}&statsPeriod=14d&sort=date&limit=50`;
  const issues = await fetchJSON(url, { Authorization: `Bearer ${token}` }) as SentryIssue[];
  return (Array.isArray(issues) ? issues : []).map(sentryItem);
}

let ascToken: { value: string; issuedAt: number } | undefined;

async function testFlight(): Promise<OpsItem[] | null> {
  const keyID = env("ASC_KEY_ID");
  const issuer = env("ASC_ISSUER_ID");
  const pem = env("ASC_PRIVATE_KEY");
  const appID = env("ASC_APP_ID");
  if (!keyID || !issuer || !pem || !appID) return null;
  const now = Math.floor(Date.now() / 1000);
  if (!ascToken || now - ascToken.issuedAt > 15 * 60) {
    ascToken = { value: await appStoreConnectToken(pem, keyID, issuer, now), issuedAt: now };
  }
  const headers = { Authorization: `Bearer ${ascToken.value}` };
  const base = `https://api.appstoreconnect.apple.com/v1/apps/${encodeURIComponent(appID)}`;
  const query = "?limit=100&sort=-createdDate&include=build&fields%5Bbuilds%5D=version";
  type Page = { data?: AscResource[]; included?: AscResource[] };
  const [shots, crashes] = await Promise.all([
    fetchJSON(`${base}/betaFeedbackScreenshotSubmissions${query}`, headers) as Promise<Page>,
    fetchJSON(`${base}/betaFeedbackCrashSubmissions${query}`, headers) as Promise<Page>,
  ]);
  const builds = new Map<string, string>();
  for (const resource of [...(shots.included ?? []), ...(crashes.included ?? [])]) {
    const version = resource.attributes?.version;
    if (resource.type === "builds" && typeof version === "string") builds.set(resource.id, version);
  }
  return testFlightItems(shots.data ?? [], crashes.data ?? [], builds);
}

function describe(error: unknown): string {
  const text = error instanceof Error ? error.message : String(error);
  return `error: ${text.slice(0, 200)}`;
}

/** Everything, with saved triage applied, sorted for the inbox. */
export async function collect(admin: Admin): Promise<Collected> {
  const sources: Record<string, SourceState> = {};
  const items: OpsItem[] = [];
  const run = async (name: string, load: () => Promise<OpsItem[] | null>) => {
    try {
      const loaded = await load();
      if (loaded === null) {
        sources[name] = "not_configured";
      } else {
        items.push(...loaded);
        sources[name] = "ok";
      }
    } catch (error) {
      console.error(`ops: ${name} failed`, error);
      sources[name] = describe(error);
    }
  };
  await Promise.all([
    run("feedback", () => feedbackItems(admin)),
    run("report", () => reports(admin)),
    run("sentry", sentry),
    run("testflight", testFlight),
  ]);
  const { data: triage, error } = await admin
    .from("ops_items")
    .select("source, external_id, status, priority, note, alerted_at, updated_at");
  if (error) throw error;
  return { items: sortItems(withTriage(items, (triage ?? []) as TriageRow[])), sources };
}

export async function metrics(admin: Admin): Promise<Record<string, unknown> | null> {
  const { data, error } = await admin.rpc("ops_metrics");
  if (error) {
    console.error("ops: metrics failed", error);
    return null;
  }
  return data as Record<string, unknown>;
}

/** Sends an email with Resend; false when it isn't set up. */
export async function sendEmail(subject: string, html: string): Promise<boolean> {
  const key = env("RESEND_API_KEY");
  const to = env("OPS_ALERT_EMAIL")?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  if (!key || to.length === 0) return false;
  const from = env("OPS_EMAIL_FROM") ?? "Versely Alerts <onboarding@resend.dev>";
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject, html }),
  });
  if (!response.ok) {
    throw new Error(`Resend HTTP ${response.status}: ${(await response.text().catch(() => "")).slice(0, 200)}`);
  }
  return true;
}

export const emailConfigured = () => Boolean(env("RESEND_API_KEY") && env("OPS_ALERT_EMAIL"));
export const dashboardURL = () => env("OPS_DASHBOARD_URL");
