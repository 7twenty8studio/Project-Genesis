// Tests for dailyVerse.ts. Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/*/*.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  acceptedReportKeys, adminErrorToHttp, alertEmail, channelFor, clientIP, confirmedDeleted, corsHeaders, decodeBase64, escapeHTML,
  groupDue, hmacHex, isAcceptedReportKey, isDailyVersePath, isJpeg, isUrgent, MAX_SCREENSHOT_BYTES, networkPrefix, nextBefore,
  parseAdminAction, parseReport, reportErrorToHttp, screenshotPath,
} from "./dailyVerse.ts";

const INSTALL = "3f2a6d9e-1b4c-4e8f-9a7d-2c5b8e1f0a3d";
const JPEG = Uint8Array.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 0xff, 0xd9]);
const b64 = (bytes: Uint8Array) => Buffer.from(bytes).toString("base64");

function body(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    appVersion: "0.1.0", build: "202611141200", osVersion: "26.1", deviceFamily: "phone",
    contentLanguage: "es", puzzleType: "crossword", contentId: "es-2026-11-14-gozo.crossword",
    challengeDate: "2026-11-14", reviewState: "draft", category: "unclear_clue",
    description: "La pista 3 horizontal no coincide.", installID: INSTALL, screenshots: [b64(JPEG)],
    ...overrides,
  };
}

// --- parseReport (the app's request, PR #36 ReportSubmission) -------------------------

test("accepts the app's request and keeps only known fields", () => {
  const r = parseReport(body({ channel: "public", email: "x@y.z", extra: 1 }));
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.value.installID, INSTALL);
  assert.equal(r.value.screenshots.length, 1);
  assert.equal("channel" in r.value, false, "a client-sent channel is ignored (rule 1)");
  assert.equal("email" in r.value, false);
});

test("optional fields may be absent or null", () => {
  const r = parseReport(body({ osVersion: undefined, deviceFamily: null, challengeDate: null, reviewState: undefined, screenshots: undefined }));
  assert.equal(r.ok, true);
  if (r.ok) assert.deepEqual([r.value.osVersion, r.value.deviceFamily, r.value.challengeDate, r.value.reviewState, r.value.screenshots.length], [null, null, null, null, 0]);
});

test("names the bad field", () => {
  const cases: [Record<string, unknown>, string][] = [
    [{ installID: "not-a-uuid" }, "installID"], [{ installID: undefined }, "installID"],
    [{ appVersion: "" }, "appVersion"], [{ build: "a b" }, "build"], [{ osVersion: "x".repeat(21) }, "osVersion"],
    [{ deviceFamily: "watch" }, "deviceFamily"], [{ contentLanguage: "fr" }, "contentLanguage"],
    [{ puzzleType: "verseGuess" }, "puzzleType"], [{ category: "rude" }, "category"],
    [{ contentId: "has space" }, "contentId"], [{ contentId: "x".repeat(121) }, "contentId"],
    [{ challengeDate: "2026-02-30" }, "challengeDate"], [{ challengeDate: "14/11/2026" }, "challengeDate"],
    [{ reviewState: "published" }, "reviewState"], [{ description: "   " }, "description"],
    [{ description: "x".repeat(2001) }, "description"], [{ screenshots: "abc" }, "screenshots"],
    [{ screenshots: [b64(JPEG), b64(JPEG), b64(JPEG)] }, "screenshots"],
  ];
  for (const [overrides, field] of cases) {
    const r = parseReport(body(overrides));
    assert.equal(r.ok, false, JSON.stringify(overrides));
    if (!r.ok) assert.equal(r.field, field, JSON.stringify(overrides));
  }
  assert.deepEqual(parseReport(null), { ok: false, field: "body" });
  assert.deepEqual(parseReport([1]), { ok: false, field: "body" });
});

test("2000 characters is fine, 2001 is not", () => {
  assert.equal(parseReport(body({ description: "x".repeat(2000) })).ok, true);
});

test("screenshots: JPEG magic bytes, not the name; oversize is flagged tooLarge (413)", () => {
  const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  assert.deepEqual(parseReport(body({ screenshots: [b64(png)] })), { ok: false, field: "screenshots" });
  const truncated = JPEG.slice(0, 6); // no FF D9 end marker
  assert.deepEqual(parseReport(body({ screenshots: [b64(truncated)] })), { ok: false, field: "screenshots" });
  assert.deepEqual(parseReport(body({ screenshots: ["***"] })), { ok: false, field: "screenshots" });
  const big = new Uint8Array(MAX_SCREENSHOT_BYTES + 1);
  big.set([0xff, 0xd8, 0xff], 0);
  big.set([0xff, 0xd9], big.length - 2);
  assert.deepEqual(parseReport(body({ screenshots: [b64(big)] })), { ok: false, field: "screenshots", tooLarge: true });
  const exact = new Uint8Array(MAX_SCREENSHOT_BYTES);
  exact.set([0xff, 0xd8, 0xff], 0);
  exact.set([0xff, 0xd9], exact.length - 2);
  assert.equal(parseReport(body({ screenshots: [b64(exact)] })).ok, true);
});

test("base64 and JPEG helpers", () => {
  assert.deepEqual(decodeBase64(b64(JPEG)), JPEG);
  assert.deepEqual(decodeBase64(b64(JPEG).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")), JPEG);
  assert.equal(decodeBase64("a"), null);
  assert.equal(isJpeg(JPEG), true);
  assert.equal(isJpeg(new Uint8Array([0xff, 0xd8])), false);
});

// --- server-side decisions --------------------------------------------------------------

test("the channel comes from server config only (rule 1)", () => {
  assert.equal(channelFor("202611141200", "202611141200, 202611150900"), "internal");
  assert.equal(channelFor("202611141200", undefined), "public");
  assert.equal(channelFor("202611141200", ""), "public");
  assert.equal(channelFor("2026111412", "202611141200"), "public");
});

test("client IP: the gateway's last x-forwarded-for entry, never a client-prepended one", () => {
  assert.equal(clientIP(new Headers({ "x-forwarded-for": "1.2.3.4, 203.0.113.9" })), "203.0.113.9");
  assert.equal(clientIP(new Headers({ "x-real-ip": "198.51.100.7" })), "198.51.100.7");
  assert.equal(clientIP(new Headers()), null);
  assert.equal(networkPrefix("203.0.113.9"), "203.0.113.0/24");
  assert.equal(networkPrefix("2001:db8:abcd:12::1"), "2001:db8:abcd::/48");
  assert.equal(networkPrefix(null), "unknown");
});

test("network prefix: canonical IPv4 /24 and IPv6 /48, anything odd shares 'unknown'", () => {
  // IPv4: ranges, leading zeros, ports
  assert.equal(networkPrefix("8.8.8.8:443"), "8.8.8.0/24");
  assert.equal(networkPrefix(" 10.0.0.255 "), "10.0.0.0/24");
  for (const bad of ["256.1.1.1", "1.2.3", "1.2.3.4.5", "01.2.3.4", "1.2.3.-4", "a.b.c.d", "", "not an ip"]) {
    assert.equal(networkPrefix(bad), "unknown", bad);
  }
  // IPv6: compressed and expanded forms of one /48 agree
  const same = ["2001:db8:abcd:12::1", "2001:0db8:abcd:0012:0:0:0:2", "2001:DB8:ABCD::", "[2001:db8:abcd::9]:443", "2001:db8:abcd::1%en0"];
  for (const ip of same) assert.equal(networkPrefix(ip), "2001:db8:abcd::/48", ip);
  assert.equal(networkPrefix("2001:db8::1"), "2001:db8:0::/48", "a short head is padded, not glued to the tail");
  assert.equal(networkPrefix("2001::1"), networkPrefix("2001:0:0:5::"), "the same /48 however it's written");
  assert.notEqual(networkPrefix("2001:db8:1::1"), networkPrefix("2001:db8:2::1"));
  assert.equal(networkPrefix("::1"), "0:0:0::/48");
  // IPv4-mapped IPv6 is the IPv4 address
  assert.equal(networkPrefix("::ffff:203.0.113.9"), "203.0.113.0/24");
  assert.equal(networkPrefix("::ffff:cb00:7109"), "203.0.113.0/24");
  for (const bad of ["1::2::3", "2001:db8:::1", "12345::1", "2001:db8:g::1", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7", ":::", "::ffff:999.0.0.1"]) {
    assert.equal(networkPrefix(bad), "unknown", bad);
  }
});

test("report keys: only the project's sb_publishable_ keys; fails closed", () => {
  const pub = "sb_publishable_rzsx7luLexampleKEY_-1";
  const other = "sb_publishable_secondKEYexample_22";
  const accepted = acceptedReportKeys(JSON.stringify({ default: pub, ios: other }), undefined);
  assert.deepEqual(accepted.sort(), [other, pub].sort());
  assert.ok(isAcceptedReportKey(pub, accepted));
  assert.ok(isAcceptedReportKey(other, accepted));
  for (const wrong of [null, "", pub + "x", pub.slice(0, -1), "Bearer " + pub, "sb_publishable_somethingElse123"]) {
    assert.equal(isAcceptedReportKey(wrong, accepted), false, String(wrong));
  }
  // Secret keys and JWTs are never accepted, even if configured by mistake.
  const jwtLike = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig";
  assert.deepEqual(acceptedReportKeys(JSON.stringify({ a: "sb_secret_abcdefghijklmnop", b: jwtLike }), `sb_secret_qrstuvwxyz123456,${jwtLike}`), []);
  // Local tests add theirs through DV_REPORT_KEYS.
  assert.deepEqual(acceptedReportKeys(undefined, ` ${pub} , `), [pub]);
  // Nothing configured, or a malformed variable: nothing accepted.
  assert.deepEqual(acceptedReportKeys(undefined, undefined), []);
  assert.deepEqual(acceptedReportKeys("{not json", ""), []);
  assert.equal(isAcceptedReportKey(pub, []), false);
});

test("HMACs: 64 hex, keyed, and refuse a short pepper (rule 6)", async () => {
  const pepper = "p".repeat(32);
  const a = await hmacHex(pepper, "install:" + INSTALL);
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.notEqual(a, await hmacHex("q".repeat(32), "install:" + INSTALL));
  assert.equal(a, await hmacHex(pepper, "install:" + INSTALL));
  assert.equal(a.includes(INSTALL.replace(/-/g, "")), false);
  await assert.rejects(hmacHex("short", "x"));
});

test("paths are built from the report id and confined to daily-verse/reports/ (rule 5)", () => {
  const id = "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10";
  assert.equal(screenshotPath(id, 1), `daily-verse/reports/${id}/1.jpg`);
  assert.equal(screenshotPath(id.toUpperCase(), 2), `daily-verse/reports/${id}/2.jpg`);
  assert.throws(() => screenshotPath(id, 3));
  assert.throws(() => screenshotPath("../../" + id, 1));
  for (const bad of [`daily-verse/reports/${id}/../x.jpg`, `${id}/note.jpg`, `daily-verse/reports/${id}/1.png`, `daily-verse/reports/x/1.jpg`, 42]) {
    assert.equal(isDailyVersePath(bad), false, String(bad));
  }
});

test("submit errors map to the contract's generic answers (rule 9)", () => {
  assert.deepEqual(reportErrorToHttp({ message: "rate_limited", hint: "37" }), { status: 429, body: { error: "rate_limited" }, retryAfter: 37 });
  assert.equal(reportErrorToHttp({ message: "rate_limited", hint: "nonsense" }).retryAfter, 60);
  assert.equal(reportErrorToHttp({ message: "rate_limited", hint: "999999" }).retryAfter, 86400);
  assert.deepEqual(reportErrorToHttp({ message: "channel_closed" }), { status: 503, body: { error: "unavailable" } });
  assert.deepEqual(reportErrorToHttp({ message: "rejected_content" }), { status: 400, body: { error: "invalid", field: "description" } });
  assert.deepEqual(reportErrorToHttp({ code: "23514", message: "new row violates check constraint" }), { status: 400, body: { error: "invalid" } });
  const unknown = reportErrorToHttp({ code: "XX000", message: "relation daily_verse.secret does not exist" });
  assert.deepEqual(unknown, { status: 500, body: { error: "server" } });
  assert.equal(JSON.stringify(unknown).includes("relation"), false, "no SQL detail leaks");
});

// --- admin ---------------------------------------------------------------------------------

test("admin actions parse; a body-supplied email or role is ignored (rule 4)", () => {
  assert.deepEqual(parseAdminAction({ action: "me", email: "attacker@example.com" }), { ok: true, value: { action: "me" } });
  const list = parseAdminAction({ action: "list", status: "new", language: "all", puzzleType: "", before: "2026-11-14T00:00:00Z", limit: 10, actor: "x@y.z" });
  assert.deepEqual(list, { ok: true, value: { action: "list", status: "new", language: null, puzzleType: null, category: null, before: "2026-11-14T00:00:00Z", limit: 10 } });
  assert.deepEqual(parseAdminAction({ action: "list" }), { ok: true, value: { action: "list", status: null, language: null, puzzleType: null, category: null, before: null, limit: 50 } });
  assert.deepEqual(parseAdminAction({ action: "update", id: "8D0C1A52-4C1E-4F0E-9A43-3C2B9A1F7E10", status: "resolved", note: " ok " }),
    { ok: true, value: { action: "update", id: "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10", status: "resolved", note: "ok" } });
  assert.deepEqual(parseAdminAction({ action: "screenshots", id: "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10" }).ok, true);
  assert.deepEqual(parseAdminAction({ action: "runCleanup" }), { ok: true, value: { action: "runCleanup" } });
});

test("admin input errors name the field", () => {
  const cases: [unknown, string][] = [
    [null, "body"], [{ action: "drop" }, "action"], [{ action: "list", status: "open" }, "status"],
    [{ action: "list", language: "fr" }, "language"], [{ action: "list", before: "yesterday" }, "before"],
    [{ action: "list", limit: 0 }, "limit"], [{ action: "list", limit: 201 }, "limit"], [{ action: "list", limit: 1.5 }, "limit"],
    [{ action: "update", id: "x", status: "new" }, "id"], [{ action: "update", id: "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10", status: "closed" }, "status"],
    [{ action: "update", id: "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10", status: "new", note: "x".repeat(2001) }, "note"],
    [{ action: "screenshots", id: "../x" }, "id"],
  ];
  for (const [input, field] of cases) assert.deepEqual(parseAdminAction(input), { ok: false, field }, JSON.stringify(input));
});

test("admin database errors map to generic answers", () => {
  assert.deepEqual(adminErrorToHttp({ code: "42501", message: "not_authorized" }, "a@b.c"), { status: 403, body: { error: "forbidden", email: "a@b.c" } });
  assert.deepEqual(adminErrorToHttp({ code: "P0002", message: "not_found" }, "a@b.c"), { status: 404, body: { error: "not_found" } });
  assert.deepEqual(adminErrorToHttp({ code: "XX000", message: "boom" }, "a@b.c"), { status: 500, body: { error: "internal" } });
});

test("nextBefore: the oldest createdAt on a full page only", () => {
  const page = [{ createdAt: "2026-11-14T00:00:00.000Z" }, { createdAt: "2026-11-13T00:00:00.000Z" }];
  assert.equal(nextBefore(page, 2), "2026-11-13T00:00:00.000Z");
  assert.equal(nextBefore(page, 3), null);
  assert.equal(nextBefore([], 50), null);
});

test("CORS: only listed origins, never a wildcard", () => {
  const allowed = "https://7twenty8studio.com, https://www.7twenty8studio.com";
  assert.equal(corsHeaders("https://7twenty8studio.com", allowed)["Access-Control-Allow-Origin"], "https://7twenty8studio.com");
  assert.equal(corsHeaders("https://evil.example", allowed)["Access-Control-Allow-Origin"], undefined);
  assert.equal(corsHeaders("https://evil.example", "*")["Access-Control-Allow-Origin"], undefined);
  assert.equal(corsHeaders(null, undefined)["Access-Control-Allow-Origin"], undefined);
  assert.equal(corsHeaders("https://7twenty8studio.com", allowed).Vary, "Origin");
});

// --- retention ---------------------------------------------------------------------------

test("cleanup marks only paths confirmed gone; a failed Storage delete stays listed (rule 5)", () => {
  const p1 = "daily-verse/reports/8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10/1.jpg";
  const p2 = "daily-verse/reports/8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10/2.jpg";
  assert.deepEqual(confirmedDeleted([p1, p2], false, [], [p1, p2]), [], "the remove call failed: nothing marked");
  assert.deepEqual(confirmedDeleted([p1, p2], true, [p1, p2], []), [p1, p2]);
  assert.deepEqual(confirmedDeleted([p1, p2], true, [p1], [p2]), [p1], "p2 still present: stays listed");
  assert.deepEqual(confirmedDeleted([p1, p2], true, [p1], []), [p1, p2], "p2 was already gone: marked");
});

test("cleanup never touches paths outside daily-verse/reports/", () => {
  const id = "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10";
  const grouped = groupDue([
    { report_id: id, path: `daily-verse/reports/${id}/1.jpg` },
    { report_id: id, path: `daily-verse/reports/${id}/1.jpg` },
    { report_id: id, path: `11111111-1111-1111-1111-111111111111/note.jpg` },
  ]);
  assert.deepEqual([...grouped], [[id, [`daily-verse/reports/${id}/1.jpg`]]]);
});

// --- alert email -------------------------------------------------------------------------

test("alert email: own prefix, escaped, text only — no screenshots or links to them", () => {
  const report = {
    id: "8d0c1a52-4c1e-4f0e-9a43-3c2b9a1f7e10", category: "unclear_clue", puzzleType: "crossword", contentLanguage: "es",
    contentId: "es-1", challengeDate: "2026-11-14", reviewState: "draft", appVersion: "0.1.0", build: "1",
    description: '<script>alert(1)</script> & "quotes"', screenshots: 2,
  };
  const { subject, html } = alertEmail(report, "https://7twenty8studio.com/admin/daily-verse");
  assert.match(subject, /^\[Daily Verse\] New problem report: unclear clue \(crossword, es\)$/);
  assert.equal(html.includes("<script>"), false);
  assert.match(html, /&lt;script&gt;/);
  assert.equal(/storage|sign\/|\.jpg|<img/i.test(html), false, "no screenshot or signed link");
  assert.match(html, /Screenshots<\/b><\/td><td>2</);
  assert.equal(subject.includes("Versely"), false);
});

test("urgent only for biblical inaccuracy outside drafts", () => {
  assert.equal(isUrgent({ category: "biblical_inaccuracy", reviewState: "approved" }), true);
  assert.equal(isUrgent({ category: "biblical_inaccuracy", reviewState: null }), true);
  assert.equal(isUrgent({ category: "biblical_inaccuracy", reviewState: "draft" }), false);
  assert.equal(isUrgent({ category: "other", reviewState: "approved" }), false);
  const { subject } = alertEmail({ id: "x", category: "biblical_inaccuracy", puzzleType: "trivia", contentLanguage: "en", contentId: "t1",
    challengeDate: null, reviewState: "approved", appVersion: "1", build: "1", description: "d", screenshots: 0 }, undefined);
  assert.match(subject, /^\[Daily Verse\] URGENT /);
  assert.equal(escapeHTML(`a<b>&"'`), "a&lt;b&gt;&amp;&quot;&#39;");
});
