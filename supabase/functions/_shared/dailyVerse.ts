// Daily Verse Games: pure helpers for the problem-report functions (dv-report,
// dv-admin, dv-retention). No Deno or Supabase imports, so Node can test them
// (dailyVerse.test.ts). Kept apart from Versely's shared code; nothing here is
// used by, or changes, any Versely function.
// Security rules: supabase/tests/daily_verse/PR_B_CONTRACT.md

export const APP_TAG = "daily-verse-games";
export const BUCKET = "attachments";
export const MAX_BODY_BYTES = 4 * 1024 * 1024;
export const MAX_SCREENSHOTS = 2;
export const MAX_SCREENSHOT_BYTES = 1_572_864; // 1.5 MB, the same limit as daily_verse.attach_screenshot
export const SIGNED_URL_SECONDS = 300; // 5 minutes

export const LANGUAGES = ["en", "es"] as const;
export const PUZZLE_TYPES = ["verse_guess", "word_search", "crossword", "trivia", "verse_builder", "reflection", "other"] as const;
export const CATEGORIES = ["incorrect_answer", "unclear_clue", "biblical_inaccuracy", "other"] as const;
export const STATUSES = ["new", "in_review", "resolved", "dismissed"] as const;

export type Channel = "internal" | "public";
export type Parsed<T> = { ok: true; value: T } | { ok: false; field: string; tooLarge?: boolean };

/** What the app may send (dv-report contract). Anything else in the body — `channel`, `email`, … — is ignored. */
export interface ReportInput {
  installID: string;
  appVersion: string;
  build: string;
  osVersion: string | null;
  deviceFamily: "phone" | "pad" | null;
  contentLanguage: (typeof LANGUAGES)[number];
  puzzleType: (typeof PUZZLE_TYPES)[number];
  contentId: string;
  challengeDate: string | null;
  reviewState: "draft" | "approved" | null;
  category: (typeof CATEGORIES)[number];
  description: string;
  screenshots: Uint8Array[];
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const CONTENT_ID = /^[A-Za-z0-9._:+-]{1,120}$/;
const VERSION = /^[0-9A-Za-z.()-]{1,20}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

function str(value: unknown): string | null {
  return typeof value === "string" ? value.trim() : null;
}

function oneOf<T extends readonly string[]>(list: T, value: unknown): T[number] | null {
  return typeof value === "string" && (list as readonly string[]).includes(value) ? value as T[number] : null;
}

function validDate(text: string): boolean {
  if (!DATE.test(text)) return false;
  const date = new Date(text + "T00:00:00Z");
  return !isNaN(date.getTime()) && date.toISOString().slice(0, 10) === text;
}

/** Decodes standard or URL-safe base64; null if it isn't base64. */
export function decodeBase64(text: string): Uint8Array | null {
  const clean = text.replace(/\s/g, "").replace(/-/g, "+").replace(/_/g, "/");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(clean) || clean.length % 4 === 1) return null;
  try {
    const binary = atob(clean.padEnd(Math.ceil(clean.length / 4) * 4, "="));
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/** True for a complete JPEG by its magic bytes: starts FF D8 FF, ends FF D9. The file name is never trusted. */
export function isJpeg(bytes: Uint8Array): boolean {
  return bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff &&
    bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9;
}

/** Validates the app's JSON body. On failure, `field` names what was wrong (safe to return to the app). */
export function parseReport(body: unknown): Parsed<ReportInput> {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false, field: "body" };
  const b = body as Record<string, unknown>;
  const installID = str(b.installID);
  if (!installID || !UUID.test(installID)) return { ok: false, field: "installID" };
  const appVersion = str(b.appVersion);
  if (!appVersion || !VERSION.test(appVersion)) return { ok: false, field: "appVersion" };
  const build = str(b.build);
  if (!build || !VERSION.test(build)) return { ok: false, field: "build" };
  const osVersion = b.osVersion == null ? null : str(b.osVersion);
  if (osVersion !== null && osVersion !== "" && !VERSION.test(osVersion)) return { ok: false, field: "osVersion" };
  const deviceFamily = b.deviceFamily == null ? null : oneOf(["phone", "pad"] as const, b.deviceFamily);
  if (b.deviceFamily != null && !deviceFamily) return { ok: false, field: "deviceFamily" };
  const contentLanguage = oneOf(LANGUAGES, b.contentLanguage);
  if (!contentLanguage) return { ok: false, field: "contentLanguage" };
  const puzzleType = oneOf(PUZZLE_TYPES, b.puzzleType);
  if (!puzzleType) return { ok: false, field: "puzzleType" };
  const category = oneOf(CATEGORIES, b.category);
  if (!category) return { ok: false, field: "category" };
  const contentId = str(b.contentId);
  if (!contentId || !CONTENT_ID.test(contentId)) return { ok: false, field: "contentId" };
  const challengeDate = b.challengeDate == null ? null : str(b.challengeDate);
  if (challengeDate !== null && !validDate(challengeDate)) return { ok: false, field: "challengeDate" };
  const reviewState = b.reviewState == null ? null : oneOf(["draft", "approved"] as const, b.reviewState);
  if (b.reviewState != null && !reviewState) return { ok: false, field: "reviewState" };
  const description = str(b.description);
  if (!description || description.length > 2000) return { ok: false, field: "description" };

  const raw = b.screenshots ?? [];
  if (!Array.isArray(raw) || raw.length > MAX_SCREENSHOTS) return { ok: false, field: "screenshots" };
  const screenshots: Uint8Array[] = [];
  for (const item of raw) {
    // Cheap length check before decoding anything.
    if (typeof item !== "string") return { ok: false, field: "screenshots" };
    if (item.length > Math.ceil(MAX_SCREENSHOT_BYTES / 3) * 4 + 8) return { ok: false, field: "screenshots", tooLarge: true };
    const bytes = decodeBase64(item);
    if (bytes && bytes.length > MAX_SCREENSHOT_BYTES) return { ok: false, field: "screenshots", tooLarge: true };
    if (!bytes || bytes.length === 0 || !isJpeg(bytes)) return { ok: false, field: "screenshots" };
    screenshots.push(bytes);
  }
  return {
    ok: true,
    value: {
      installID: installID.toLowerCase(), appVersion, build, osVersion: osVersion || null, deviceFamily,
      contentLanguage, puzzleType, contentId, challengeDate, reviewState, category, description, screenshots,
    },
  };
}

/**
 * The channel is decided here from server configuration, never from the request
 * (contract rule 1): a build number listed in DV_INTERNAL_BUILDS (comma-separated
 * Edge Function secret, updated when an Internal TestFlight build is uploaded) is
 * Internal; anything else is Public, which the database refuses while
 * settings.accepted_channels = {internal}. A policy gate, not device attestation
 * (rule 2): App Attest / DeviceCheck is required before public availability.
 */
export function channelFor(build: string, internalBuilds: string | undefined): Channel {
  const list = (internalBuilds ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  return list.includes(build) ? "internal" : "public";
}

/**
 * The caller's IP for the network rate-limit bucket. Supabase's gateway puts the
 * connecting address in x-forwarded-for; a client can prepend its own values, so
 * the LAST entry (added by the gateway) is used, then x-real-ip. Never stored:
 * only an HMAC of the network prefix reaches the database (rule 6).
 * Which header the HOSTED gateway really sets is a release gate
 * (PR_B_DEPLOYMENT.md, "Hosted validation"); until it's shown, the network
 * bucket is a coarse spam brake, not a guarantee.
 */
export function clientIP(headers: Headers): string | null {
  const parts = headers.get("x-forwarded-for")?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  return parts.at(-1) || headers.get("x-real-ip")?.trim() || null;
}

/** "1.2.3.4" or null. Accepts "1.2.3.4:443"; every octet 0–255 with no leading zeros. */
function parseIPv4(value: string): number[] | null {
  const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::\d{1,5})?$/.exec(value);
  if (!m) return null;
  const octets = m.slice(1).map((part) => (part.length > 1 && part.startsWith("0") ? NaN : Number(part)));
  return octets.every((n) => Number.isInteger(n) && n >= 0 && n <= 255) ? octets : null;
}

/** Eight 16-bit groups, or null. Accepts "[…]:port", a zone ("%en0"), "::" and an embedded IPv4 tail. */
function parseIPv6(value: string): number[] | null {
  let text = value;
  const bracketed = /^\[([^\]]+)\](?::\d{1,5})?$/.exec(text);
  if (bracketed) text = bracketed[1];
  text = text.split("%")[0].toLowerCase();
  if (!text.includes(":") || (text.match(/::/g)?.length ?? 0) > 1) return null;
  const groups = (part: string): number[] | null => {
    if (part === "") return [];
    const out: number[] = [];
    const pieces = part.split(":");
    for (const [i, piece] of pieces.entries()) {
      if (i === pieces.length - 1 && piece.includes(".")) {
        const v4 = parseIPv4(piece);
        if (!v4) return null;
        out.push((v4[0] << 8) | v4[1], (v4[2] << 8) | v4[3]);
      } else if (/^[0-9a-f]{1,4}$/.test(piece)) {
        out.push(parseInt(piece, 16));
      } else {
        return null;
      }
    }
    return out;
  };
  const [headText, tailText] = text.split("::");
  const head = groups(headText);
  const tail = tailText === undefined ? [] : groups(tailText);
  if (!head || !tail) return null;
  if (tailText === undefined) return head.length === 8 ? head : null;
  const missing = 8 - head.length - tail.length;
  return missing >= 1 ? [...head, ...Array(missing).fill(0), ...tail] : null;
}

/**
 * IPv4 → /24, IPv6 → /48, so one household or carrier block shares a bucket.
 * The prefix is canonical (so "2001:db8::1" and "2001:0db8:0:0::2" share one),
 * IPv4-mapped IPv6 counts as IPv4, and anything unparseable is "unknown"
 * (one shared bucket: never an error).
 */
export function networkPrefix(ip: string | null): string {
  if (!ip) return "unknown";
  const value = ip.trim();
  const v4 = parseIPv4(value);
  if (v4) return `${v4[0]}.${v4[1]}.${v4[2]}.0/24`;
  const v6 = parseIPv6(value);
  if (!v6) return "unknown";
  if (v6.slice(0, 5).every((g) => g === 0) && v6[5] === 0xffff) {
    return `${v6[6] >> 8}.${v6[6] & 0xff}.${v6[7] >> 8}.0/24`;
  }
  return v6.slice(0, 3).map((g) => g.toString(16)).join(":") + "::/48";
}

/**
 * The public keys dv-report accepts in its `apikey` header: the project's
 * publishable keys (SUPABASE_PUBLISHABLE_KEYS, a JSON object the platform sets
 * for every function) plus DV_REPORT_KEYS (comma-separated; local tests only,
 * since the local CLI doesn't set the former). Only sb_publishable_ keys count:
 * never a secret key or a JWT. No keys configured means nothing is accepted.
 */
export function acceptedReportKeys(publishableJSON: string | undefined, extra: string | undefined): string[] {
  const keys: string[] = [];
  try {
    const parsed = JSON.parse(publishableJSON ?? "null");
    if (parsed && typeof parsed === "object") for (const v of Object.values(parsed)) if (typeof v === "string") keys.push(v);
  } catch { /* not set or not JSON: none from there */ }
  for (const k of (extra ?? "").split(",")) keys.push(k.trim());
  return [...new Set(keys.filter((k) => /^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(k)))];
}

/** Constant-time comparison of the request's apikey with each accepted key. */
export function isAcceptedReportKey(apikey: string | null, accepted: string[]): boolean {
  if (!apikey || accepted.length === 0) return false;
  const given = new TextEncoder().encode(apikey);
  let ok = false;
  for (const key of accepted) {
    const want = new TextEncoder().encode(key);
    let diff = given.length ^ want.length;
    for (let i = 0; i < want.length; i++) diff |= want[i] ^ (given[i] ?? 0);
    if (diff === 0) ok = true;
  }
  return ok;
}

/** Hex HMAC-SHA256 keyed with the DV_HMAC_SECRET pepper. Raw values never leave the function. */
export async function hmacHex(secret: string, value: string): Promise<string> {
  if (!secret || secret.length < 32) throw new Error("DV_HMAC_SECRET missing or shorter than 32 characters");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value)));
  return Array.from(signature, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** The only object paths Daily Verse may touch: daily-verse/reports/<uuid>/<1|2>.jpg */
export const SCREENSHOT_PATH = /^daily-verse\/reports\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[12]\.jpg$/;

export function isDailyVersePath(path: unknown): path is string {
  return typeof path === "string" && SCREENSHOT_PATH.test(path);
}

/** Built from the report id only, never from the client (rule 5); the same shape attach_screenshot builds. */
export function screenshotPath(reportId: string, index: number): string {
  const path = `daily-verse/reports/${reportId.toLowerCase()}/${index}.jpg`;
  if (!isDailyVersePath(path)) throw new Error("refused: path outside daily-verse/reports/");
  return path;
}

/** A Postgres error as postgres.js reports it. */
export interface DbError { message?: string; code?: string; hint?: string }

export type HttpError = { status: number; body: Record<string, unknown>; retryAfter?: number };

/** dv-report: maps a submit_report error to the contract's generic responses. Details stay in the logs (rule 9). */
export function reportErrorToHttp(error: DbError): HttpError {
  const message = error.message ?? "";
  if (message.includes("rate_limited")) {
    const seconds = Math.max(1, Math.min(86_400, parseInt(error.hint ?? "60", 10) || 60));
    return { status: 429, body: { error: "rate_limited" }, retryAfter: seconds };
  }
  if (message.includes("channel_closed")) return { status: 503, body: { error: "unavailable" } };
  if (message.includes("rejected_content")) return { status: 400, body: { error: "invalid", field: "description" } };
  if (error.code === "23514" || error.code === "22023" || error.code === "22P02" || error.code === "22001") {
    return { status: 400, body: { error: "invalid" } };
  }
  return { status: 500, body: { error: "server" } };
}

/** dv-admin: maps a database error to a generic response (shapes in dv-admin.fixtures.json). */
export function adminErrorToHttp(error: DbError, email: string): HttpError {
  if (error.code === "42501" || (error.message ?? "").includes("not_authorized")) return { status: 403, body: { error: "forbidden", email } };
  if (error.code === "P0002" || (error.message ?? "").includes("not_found")) return { status: 404, body: { error: "not_found" } };
  if (error.code === "23514" || error.code === "22023" || error.code === "22P02") return { status: 400, body: { error: "invalid" } };
  return { status: 500, body: { error: "internal" } };
}

/** The list's cursor: the oldest createdAt on a full page, else null (last page). */
export function nextBefore(reports: { createdAt: string | null }[], limit: number): string | null {
  return reports.length === limit && reports.length > 0 ? reports[reports.length - 1].createdAt : null;
}

// Admin API (dv-admin) -------------------------------------------------------------

export type AdminAction =
  | { action: "me" }
  | { action: "list"; status: string | null; language: string | null; puzzleType: string | null; category: string | null; before: string | null; limit: number }
  | { action: "update"; id: string; status: (typeof STATUSES)[number]; note: string | null }
  | { action: "screenshots"; id: string }
  | { action: "runCleanup" };

/** Admin request body. The acting admin's email is never read from here (rule 4). */
export function parseAdminAction(body: unknown): Parsed<AdminAction> {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false, field: "body" };
  const b = body as Record<string, unknown>;
  const optional = <T extends readonly string[]>(list: T, value: unknown) =>
    value == null || value === "" || value === "all" ? null : oneOf(list, value);
  switch (b.action) {
    case "me":
      return { ok: true, value: { action: "me" } };
    case "runCleanup":
      return { ok: true, value: { action: "runCleanup" } };
    case "list": {
      const filters = { status: [STATUSES, b.status], language: [LANGUAGES, b.language], puzzleType: [PUZZLE_TYPES, b.puzzleType], category: [CATEGORIES, b.category] } as const;
      const parsed: Record<string, string | null> = {};
      for (const [name, [list, given]] of Object.entries(filters)) {
        parsed[name] = optional(list, given);
        if (given != null && given !== "" && given !== "all" && parsed[name] === null) return { ok: false, field: name };
      }
      const before = b.before == null || b.before === "" ? null : str(b.before);
      if (before !== null && isNaN(Date.parse(before))) return { ok: false, field: "before" };
      let limit = 50;
      if (b.limit != null) {
        if (typeof b.limit !== "number" || !Number.isInteger(b.limit) || b.limit < 1 || b.limit > 200) return { ok: false, field: "limit" };
        limit = b.limit;
      }
      return { ok: true, value: { action: "list", status: parsed.status, language: parsed.language, puzzleType: parsed.puzzleType, category: parsed.category, before, limit } };
    }
    case "update": {
      const id = str(b.id);
      if (!id || !UUID.test(id)) return { ok: false, field: "id" };
      const status = oneOf(STATUSES, b.status);
      if (!status) return { ok: false, field: "status" };
      const note = b.note == null ? null : str(b.note);
      if (note !== null && note.length > 2000) return { ok: false, field: "note" };
      return { ok: true, value: { action: "update", id: id.toLowerCase(), status, note: note || null } };
    }
    case "screenshots": {
      const id = str(b.id);
      return id && UUID.test(id) ? { ok: true, value: { action: "screenshots", id: id.toLowerCase() } } : { ok: false, field: "id" };
    }
    default:
      return { ok: false, field: "action" };
  }
}

/** A daily_verse.reports row as postgres.js returns it. */
export interface ReportRow {
  id: string; created_at: Date | string; updated_at: Date | string; app: string; channel: string;
  app_version: string; build: string; os_version: string | null; device_family: string | null;
  content_language: string; puzzle_type: string; content_id: string; challenge_date: Date | string | null;
  review_state: string | null; category: string; description: string; install_hash: string;
  screenshot_paths: string[]; screenshot_bytes: number[]; status: string; admin_note: string | null;
  handled_by: string | null; closed_at: Date | string | null;
}

const iso = (value: Date | string | null): string | null =>
  value === null ? null : value instanceof Date ? value.toISOString() : new Date(value).toISOString();

const day = (value: Date | string | null): string | null =>
  value === null ? null : value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10);

/** The admin API's Report: camelCase, no install hash (only an 8-hex grouping tag), no storage paths. */
export function toAdminReport(row: ReportRow) {
  return {
    id: row.id,
    createdAt: iso(row.created_at),
    updatedAt: iso(row.updated_at),
    channel: row.channel,
    appVersion: row.app_version,
    build: row.build,
    osVersion: row.os_version,
    deviceFamily: row.device_family,
    contentLanguage: row.content_language,
    puzzleType: row.puzzle_type,
    contentId: row.content_id,
    challengeDate: day(row.challenge_date),
    reviewState: row.review_state,
    category: row.category,
    description: row.description,
    screenshotCount: row.screenshot_paths?.length ?? 0,
    status: row.status,
    adminNote: row.admin_note,
    handledBy: row.handled_by,
    closedAt: iso(row.closed_at),
    installTag: row.install_hash.slice(0, 8),
  };
}

/** CORS for dv-admin: only the listed origins (no wildcard); others get no Allow-Origin header. */
export function corsHeaders(origin: string | null, allowed: string | undefined): Record<string, string> {
  const origins = (allowed ?? "").split(",").map((s) => s.trim()).filter((s) => s && s !== "*");
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    Vary: "Origin",
  };
  if (origin && origins.includes(origin)) headers["Access-Control-Allow-Origin"] = origin;
  return headers;
}

// Retention (dv-retention) ------------------------------------------------------------

export interface DueScreenshot { report_id: string; path: string }

/** Groups due paths by report, dropping anything outside daily-verse/reports/ (never deleted). */
export function groupDue(rows: DueScreenshot[]): Map<string, string[]> {
  const byReport = new Map<string, string[]>();
  for (const row of rows) {
    if (!isDailyVersePath(row.path)) continue;
    const list = byReport.get(row.report_id) ?? [];
    if (!list.includes(row.path)) list.push(row.path);
    byReport.set(row.report_id, list);
  }
  return byReport;
}

/**
 * Which paths may be marked deleted after a Storage remove call (rule 5): only
 * when the call succeeded, and then only paths that Storage reported deleted or
 * that are confirmed absent. Everything else stays listed for the next run.
 */
export function confirmedDeleted(requested: string[], removeOk: boolean, removed: string[], stillPresent: string[]): string[] {
  if (!removeOk) return [];
  return requested.filter((path) => removed.includes(path) || !stillPresent.includes(path));
}

// Alert email ---------------------------------------------------------------------------

export function escapeHTML(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

export interface AlertReport {
  id: string; category: string; puzzleType: string; contentLanguage: string; contentId: string;
  challengeDate: string | null; reviewState: string | null; appVersion: string; build: string;
  description: string; screenshots: number;
}

/** Urgent: a biblical-accuracy problem in approved (published) content. */
export function isUrgent(report: Pick<AlertReport, "category" | "reviewState">): boolean {
  return report.category === "biblical_inaccuracy" && report.reviewState !== "draft";
}

/** The Daily Verse alert email: its own "[Daily Verse]" subject prefix, separate from Versely's ops alerts. */
export function alertEmail(report: AlertReport, dashboardURL: string | undefined): { subject: string; html: string } {
  const urgent = isUrgent(report);
  const subject = `[Daily Verse]${urgent ? " URGENT" : ""} New problem report: ${report.category.replace(/_/g, " ")} (${report.puzzleType}, ${report.contentLanguage})`;
  const rows: [string, string][] = [
    ["Category", report.category], ["Puzzle", report.puzzleType], ["Language", report.contentLanguage],
    ["Content", report.contentId], ["Date", report.challengeDate ?? "—"], ["Review state", report.reviewState ?? "—"],
    ["App", `${report.appVersion} (${report.build})`], ["Screenshots", String(report.screenshots)], ["Report ID", report.id],
  ];
  const description = report.description.length > 500 ? report.description.slice(0, 500) + "…" : report.description;
  const link = dashboardURL ? `<p><a href="${escapeHTML(dashboardURL)}">Open the Daily Verse Games tab</a></p>` : "";
  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif">
<p>${urgent ? "<strong>Urgent:</strong> a biblical-accuracy problem was reported in published content." : "A new problem report arrived."}</p>
<table cellpadding="4">${rows.map(([k, v]) => `<tr><td><b>${escapeHTML(k)}</b></td><td>${escapeHTML(v)}</td></tr>`).join("")}</table>
<p style="white-space:pre-wrap">${escapeHTML(description)}</p>${link}
<p style="color:#888">Daily Verse Games reports. Versely's ops alerts are separate.</p></div>`;
  return { subject, html };
}
