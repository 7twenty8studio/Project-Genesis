// The operations dashboard's rules: turning feedback, content reports,
// Sentry issues and TestFlight feedback into one prioritised list, choosing
// what to email, and writing the emails. Pure (no Deno, no network), so it's
// tested under Node: node --experimental-strip-types --test supabase/functions/_shared/ops.test.ts

export type Priority = "urgent" | "high" | "normal" | "low";
export type Source = "feedback" | "report" | "sentry" | "testflight";
export type Status = "new" | "seen" | "resolved";

export const PRIORITIES: Priority[] = ["urgent", "high", "normal", "low"];
export const SOURCES: Source[] = ["feedback", "report", "sentry", "testflight"];

export interface OpsItem {
  source: Source;
  id: string;
  /** bug, idea, question, scripture, other, report, fatal, error, warning, info, tester-feedback, tester-crash */
  kind: string;
  title: string;
  detail: string;
  createdAt: string;
  lastSeenAt?: string;
  priority: Priority;
  /** Why it has that priority, in a few words. */
  reason: string;
  meta: Record<string, string | number | null>;
  link?: string;
  images?: string[];
  status: Status;
  note?: string;
  alertedAt?: string;
  /** The priority someone chose by hand, if any (overrides the rules). */
  priorityOverride?: Priority;
}

export interface TriageRow {
  source: string;
  external_id: string;
  status: string;
  priority: string | null;
  note: string | null;
  alerted_at: string | null;
  updated_at?: string | null;
}

export function rank(priority: Priority): number {
  return PRIORITIES.indexOf(priority);
}

// Words that turn ordinary feedback into something serious: losing data,
// money, crashes, being locked out. English and Spanish.
const SERIOUS = [
  /\bcrash(es|ed|ing)?\b/i, /\bfreez(e|es|ing)\b/i, /\bfrozen\b/i,
  /\b(lost|lose|losing|deleted|disappear(ed|s)?|gone|missing|wiped)\b/i,
  /\b(charged|refund|payment|paid|billing|subscription)\b/i,
  /\b(can'?t|cannot|won'?t|unable to) (sign|log|open|start|restore|buy|purchase|sync)/i,
  /\bblank screen\b/i,
  /se (cierra|cerró|congela)/i, /\b(perd[ií]|borr[oó]|desapareci[oó]|cobr[oó]|reembolso)\b/i,
  /no (puedo|abre|inicia|sincroniza)/i,
];

export function soundsSerious(text: string): boolean {
  return SERIOUS.some((pattern) => pattern.test(text));
}

function clip(text: string, length: number): string {
  const clean = (text ?? "").replace(/\s+/g, " ").trim();
  return clean.length > length ? clean.slice(0, length - 1) + "…" : clean;
}

// MARK: In-app feedback (public.app_feedback)

export interface FeedbackRow {
  id: string;
  created_at: string;
  category: string | null;
  message: string | null;
  contact_email: string | null;
  app_version: string | null;
  os_version: string | null;
  device: string | null;
  language: string | null;
  context: string | null;
  resolved: boolean | null;
}

export function classifyFeedback(category: string, message: string): { priority: Priority; reason: string } {
  switch (category) {
    case "scripture":
      return { priority: "urgent", reason: "Reported mistake in a Bible text" };
    case "bug":
      return soundsSerious(message)
        ? { priority: "urgent", reason: "Bug that mentions a crash, lost data, payment or sign-in" }
        : { priority: "high", reason: "Bug report" };
    case "question":
      return { priority: "normal", reason: "Question" };
    case "idea":
      return soundsSerious(message)
        ? { priority: "normal", reason: "Idea that mentions a problem" }
        : { priority: "low", reason: "Idea" };
    default:
      return soundsSerious(message)
        ? { priority: "high", reason: "Mentions a crash, lost data, payment or sign-in" }
        : { priority: "normal", reason: "Feedback" };
  }
}

export function feedbackItem(row: FeedbackRow): OpsItem {
  const category = row.category ?? "other";
  const message = row.message ?? "";
  const { priority, reason } = classifyFeedback(category, message);
  const labels: Record<string, string> = {
    bug: "Bug", idea: "Idea", question: "Question", scripture: "Bible text mistake", other: "Feedback",
  };
  return {
    source: "feedback",
    id: row.id,
    kind: category,
    title: `${labels[category] ?? "Feedback"}: ${clip(message, 80) || "(no message)"}`,
    detail: message,
    createdAt: row.created_at,
    priority,
    reason,
    meta: {
      app_version: row.app_version, os_version: row.os_version, device: row.device,
      language: row.language, context: row.context, contact: row.contact_email,
    },
    status: row.resolved ? "resolved" : "new",
  };
}

// MARK: Content reports (public.content_reports)

export interface ReportRow {
  id: string;
  content_type: string;
  content_id: string;
  reason: string | null;
  created_at: string;
  resolved_at: string | null;
  group_id: string | null;
}

/** One item per reported post or prayer, however many people reported it. */
export function reportItems(rows: ReportRow[]): OpsItem[] {
  const byContent = new Map<string, ReportRow[]>();
  for (const row of rows) {
    const key = `${row.content_type}:${row.content_id}`;
    byContent.set(key, [...(byContent.get(key) ?? []), row]);
  }
  const items: OpsItem[] = [];
  for (const [key, reports] of byContent) {
    reports.sort((a, b) => a.created_at.localeCompare(b.created_at));
    const open = reports.filter((r) => !r.resolved_at);
    const first = reports[0];
    const latest = reports[reports.length - 1];
    const what = first.content_type.replace(/_/g, " ");
    const many = open.length >= 3;
    items.push({
      source: "report",
      id: key,
      kind: "report",
      title: `Reported ${what}${reports.length > 1 ? ` (${reports.length} reports)` : ""}`,
      detail: reports.map((r) => r.reason?.trim()).filter(Boolean).map((r) => `• ${r}`).join("\n") || "No reason given.",
      createdAt: first.created_at,
      lastSeenAt: latest.created_at,
      priority: open.length === 0 ? "low" : many ? "urgent" : "high",
      reason: open.length === 0
        ? "Reviewed in the app"
        : many ? "Three or more reports: hidden until reviewed" : "Content report (App Store 1.2: review promptly)",
      meta: { content_type: first.content_type, content_id: first.content_id, group_id: first.group_id, reports: reports.length, open: open.length },
      status: open.length === 0 ? "resolved" : "new",
    });
  }
  return items;
}

// MARK: Sentry issues

export interface SentryIssue {
  id: string;
  title?: string;
  culprit?: string;
  level?: string;
  count?: string | number;
  userCount?: number;
  firstSeen?: string;
  lastSeen?: string;
  permalink?: string;
  isUnhandled?: boolean;
  shortId?: string;
  metadata?: { value?: string; type?: string };
}

export function classifySentry(issue: SentryIssue): { priority: Priority; reason: string } {
  const level = issue.level ?? "error";
  const events = Number(issue.count ?? 0);
  const users = issue.userCount ?? 0;
  if (level === "fatal") return { priority: "urgent", reason: "Crash" };
  if (level === "error") {
    if (issue.isUnhandled) return { priority: "urgent", reason: "Unhandled error (crash)" };
    if (users >= 5 || events >= 50) return { priority: "urgent", reason: `Error affecting ${users} people, ${events} times` };
    return { priority: "high", reason: "Error" };
  }
  if (level === "warning") return { priority: "normal", reason: "Warning" };
  return { priority: "low", reason: level };
}

export function sentryItem(issue: SentryIssue): OpsItem {
  const { priority, reason } = classifySentry(issue);
  return {
    source: "sentry",
    id: String(issue.id),
    kind: issue.level ?? "error",
    title: clip(issue.title ?? "Sentry issue", 120),
    detail: [issue.metadata?.value, issue.culprit].filter(Boolean).join("\n"),
    createdAt: issue.firstSeen ?? new Date(0).toISOString(),
    lastSeenAt: issue.lastSeen,
    priority,
    reason,
    meta: { events: Number(issue.count ?? 0), people: issue.userCount ?? 0, short_id: issue.shortId ?? null },
    link: issue.permalink,
    status: "new",
  };
}

// MARK: TestFlight feedback (App Store Connect API)

export interface AscResource {
  id: string;
  type?: string;
  attributes?: Record<string, unknown>;
  relationships?: { build?: { data?: { id: string } | null } };
}

export function testFlightItems(
  screenshots: AscResource[],
  crashes: AscResource[],
  builds: Map<string, string> = new Map(),
): OpsItem[] {
  const text = (value: unknown) => (typeof value === "string" ? value : "");
  const make = (resource: AscResource, crash: boolean): OpsItem => {
    const a = resource.attributes ?? {};
    const comment = text(a.comment);
    const buildID = resource.relationships?.build?.data?.id;
    const images = Array.isArray(a.screenshots)
      ? (a.screenshots as Array<{ url?: string }>).map((s) => s?.url).filter((u): u is string => typeof u === "string")
      : [];
    const serious = soundsSerious(comment);
    return {
      source: "testflight",
      id: resource.id,
      kind: crash ? "tester-crash" : "tester-feedback",
      title: crash
        ? `TestFlight crash${comment ? `: ${clip(comment, 80)}` : ""}`
        : `TestFlight: ${clip(comment, 80) || "(screenshot, no comment)"}`,
      detail: comment,
      createdAt: text(a.createdDate) || new Date(0).toISOString(),
      priority: crash ? "urgent" : serious ? "high" : "normal",
      reason: crash ? "A tester's app crashed" : serious ? "Tester mentions a crash, lost data, payment or sign-in" : "Tester feedback",
      meta: {
        build: (buildID && builds.get(buildID)) || null,
        device: text(a.deviceModel) || null,
        os_version: text(a.osVersion) || null,
        tester: text(a.email) || null,
        locale: text(a.locale) || null,
      },
      images,
      status: "new",
    };
  };
  return [...screenshots.map((r) => make(r, false)), ...crashes.map((r) => make(r, true))];
}

// MARK: Triage state and ordering

/** Applies saved state (status, chosen priority, note, when emailed). */
export function withTriage(items: OpsItem[], rows: TriageRow[]): OpsItem[] {
  const byKey = new Map(rows.map((row) => [`${row.source}|${row.external_id}`, row]));
  return items.map((item) => {
    const row = byKey.get(`${item.source}|${item.id}`);
    if (!row) return item;
    const override = PRIORITIES.includes(row.priority as Priority) ? (row.priority as Priority) : undefined;
    // A source that says "resolved" (a reviewed report, feedback marked
    // resolved) wins over an older "new" here.
    let status = item.status === "resolved" && row.status !== "resolved" ? "resolved" : (row.status as Status);
    // Resolved here, but it happened again since (a Sentry issue that came
    // back, a post reported again): open again.
    let reason = item.reason;
    let alertedAt = row.alerted_at ?? undefined;
    if (status === "resolved" && item.status !== "resolved" && item.lastSeenAt && row.updated_at &&
        Date.parse(item.lastSeenAt) > Date.parse(row.updated_at)) {
      status = "new";
      reason = `Happened again after it was resolved · ${item.reason}`;
      alertedAt = undefined;
    }
    return {
      ...item,
      reason,
      status: ["new", "seen", "resolved"].includes(status) ? status : item.status,
      priority: override ?? item.priority,
      priorityOverride: override,
      note: row.note ?? undefined,
      alertedAt,
    };
  });
}

/** Open first, then by priority, then newest. */
export function sortItems(items: OpsItem[]): OpsItem[] {
  return [...items].sort((a, b) => {
    const openA = a.status === "resolved" ? 1 : 0;
    const openB = b.status === "resolved" ? 1 : 0;
    if (openA !== openB) return openA - openB;
    if (rank(a.priority) !== rank(b.priority)) return rank(a.priority) - rank(b.priority);
    return (b.lastSeenAt ?? b.createdAt).localeCompare(a.lastSeenAt ?? a.createdAt);
  });
}

// MARK: Alerts

/**
 * What to email straight away: urgent, still open, never emailed, and recent
 * (so turning alerts on doesn't send a flood of old things).
 */
export function itemsToAlert(items: OpsItem[], now: Date, maxAgeHours = 72): OpsItem[] {
  const cutoff = now.getTime() - maxAgeHours * 3_600_000;
  return items.filter((item) =>
    item.priority === "urgent" &&
    item.status !== "resolved" &&
    !item.alertedAt &&
    Date.parse(item.lastSeenAt ?? item.createdAt) >= cutoff
  );
}

/** The day in the owner's time zone ("2026-10-14"), for one digest a day. */
export function localDay(date: Date, timeZone = "America/Chicago"): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

export function localHour(date: Date, timeZone = "America/Chicago"): number {
  return Number(new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", hourCycle: "h23" }).format(date));
}

export function escapeHTML(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

const SOURCE_NAMES: Record<Source, string> = {
  feedback: "In-app feedback",
  report: "Content report",
  sentry: "Sentry",
  testflight: "TestFlight",
};

const PRIORITY_COLORS: Record<Priority, string> = {
  urgent: "#a33b2f",
  high: "#b0702a",
  normal: "#4a6a8a",
  low: "#7a7a72",
};

function itemRow(item: OpsItem): string {
  const meta = Object.entries(item.meta)
    .filter(([key, value]) => value !== null && value !== "" && key !== "contact" && key !== "tester")
    .map(([key, value]) => `${escapeHTML(key.replace(/_/g, " "))}: ${escapeHTML(String(value))}`)
    .join(" · ");
  const link = item.link ? ` <a href="${escapeHTML(item.link)}">Open</a>` : "";
  return `<tr><td style="padding:10px 0;border-bottom:1px solid #e6e1d6;vertical-align:top">
<span style="display:inline-block;padding:2px 8px;border-radius:10px;background:${PRIORITY_COLORS[item.priority]};color:#fff;font-size:11px;text-transform:uppercase;letter-spacing:.04em">${item.priority}</span>
<span style="color:#7a7a72;font-size:12px;margin-left:6px">${SOURCE_NAMES[item.source]} · ${escapeHTML(item.reason)}</span>
<div style="font-weight:600;margin:6px 0 2px">${escapeHTML(item.title)}${link}</div>
${item.detail ? `<div style="color:#3d3a33;font-size:14px;white-space:pre-wrap">${escapeHTML(clip(item.detail, 400))}</div>` : ""}
${meta ? `<div style="color:#7a7a72;font-size:12px;margin-top:4px">${meta}</div>` : ""}
</td></tr>`;
}

function page(heading: string, intro: string, rows: string, dashboardURL?: string): string {
  const button = dashboardURL
    ? `<p style="margin:24px 0 0"><a href="${escapeHTML(dashboardURL)}" style="background:#3d3a33;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">Open the dashboard</a></p>`
    : "";
  return `<!doctype html><html><body style="margin:0;background:#f6f3ec;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#2b2925">
<div style="max-width:640px;margin:0 auto;padding:28px 20px">
<div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#7a7a72">Versely operations</div>
<h1 style="font-size:22px;margin:6px 0 8px">${escapeHTML(heading)}</h1>
<p style="margin:0 0 16px;color:#4b4840">${escapeHTML(intro)}</p>
<table style="width:100%;border-collapse:collapse">${rows}</table>
${button}
<p style="margin-top:28px;font-size:12px;color:#9a968c">Sent by the ops-alerts function. Urgent items are emailed once; everything else is in the daily digest.</p>
</div></body></html>`;
}

export function alertEmail(items: OpsItem[], dashboardURL?: string): { subject: string; html: string } {
  const first = items[0];
  const subject = items.length === 1
    ? `[Versely urgent] ${clip(first.title, 90)}`
    : `[Versely urgent] ${items.length} urgent items need attention`;
  const intro = items.length === 1
    ? "Something urgent was just reported."
    : `${items.length} urgent items were just reported.`;
  return { subject, html: page("Needs attention now", intro, sortItems(items).map(itemRow).join(""), dashboardURL) };
}

export interface DigestSummary {
  open: Record<Priority, number>;
  newSince: OpsItem[];
  metrics?: Record<string, unknown>;
}

export function digestSummary(items: OpsItem[], now: Date, hours = 24): DigestSummary {
  const cutoff = now.getTime() - hours * 3_600_000;
  const open: Record<Priority, number> = { urgent: 0, high: 0, normal: 0, low: 0 };
  for (const item of items) if (item.status !== "resolved") open[item.priority] += 1;
  const newSince = sortItems(items.filter((item) => Date.parse(item.lastSeenAt ?? item.createdAt) >= cutoff && item.status !== "resolved"));
  return { open, newSince };
}

export function digestEmail(summary: DigestSummary, day: string, dashboardURL?: string): { subject: string; html: string } {
  const { open, newSince, metrics } = summary;
  const total = open.urgent + open.high + open.normal + open.low;
  const subject = `[Versely] Daily digest ${day}: ${newSince.length} new, ${total} open${open.urgent ? `, ${open.urgent} urgent` : ""}`;
  const counts = PRIORITIES.map((p) =>
    `<td style="padding:8px 10px;background:#fff;border-radius:8px;text-align:center"><div style="font-size:20px;font-weight:700;color:${PRIORITY_COLORS[p]}">${open[p]}</div><div style="font-size:11px;color:#7a7a72;text-transform:uppercase">${p}</div></td>`
  ).join('<td style="width:8px"></td>');
  const usage = metrics
    ? `<p style="font-size:13px;color:#4b4840;margin:16px 0 0">Accounts ${escapeHTML(String(metrics.accounts ?? "–"))} · new this week ${escapeHTML(String(metrics.new_accounts_7d ?? "–"))} · signed in this week ${escapeHTML(String(metrics.signed_in_7d ?? "–"))} · Premium ${escapeHTML(String(metrics.premium ?? "–"))}</p>`
    : "";
  const shown = newSince.slice(0, 15);
  const more = newSince.length > shown.length
    ? `<tr><td style="padding:10px 0;color:#7a7a72;font-size:13px">…and ${newSince.length - shown.length} more in the dashboard.</td></tr>`
    : "";
  const rows = `<tr><td><table style="border-collapse:separate"><tr>${counts}</tr></table>${usage}</td></tr>` +
    (shown.length
      ? `<tr><td style="padding-top:18px;font-weight:600">New in the last 24 hours</td></tr>${shown.map(itemRow).join("")}${more}`
      : `<tr><td style="padding-top:18px;color:#4b4840">Nothing new in the last 24 hours.</td></tr>`);
  return { subject, html: page(`Daily digest · ${day}`, "Open items by priority, and what came in yesterday.", rows, dashboardURL) };
}

// MARK: App Store Connect token

function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\\n/g, "").replace(/\s+/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/** An App Store Connect API token (ES256, 20 minutes). */
export async function appStoreConnectToken(pem: string, keyID: string, issuerID: string, now: number): Promise<string> {
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID, typ: "JWT" }));
  const claims = base64url(JSON.stringify({ iss: issuerID, iat: now, exp: now + 19 * 60, aud: "appstoreconnect-v1" }));
  const input = `${header}.${claims}`;
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input)));
  return `${input}.${base64url(signature)}`;
}
