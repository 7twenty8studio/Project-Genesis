import { test } from "node:test";
import assert from "node:assert/strict";
import {
  alertEmail,
  appStoreConnectToken,
  classifyFeedback,
  classifySentry,
  digestEmail,
  digestSummary,
  escapeHTML,
  feedbackItem,
  itemsToAlert,
  localDay,
  localHour,
  reportItems,
  sentryItem,
  sortItems,
  soundsSerious,
  testFlightItems,
  withTriage,
  type FeedbackRow,
  type OpsItem,
} from "./ops.ts";

const now = new Date("2026-10-14T20:00:00Z");

function feedback(overrides: Partial<FeedbackRow> = {}): FeedbackRow {
  return {
    id: "f1", created_at: "2026-10-14T19:00:00Z", category: "bug", message: "The highlight color is off",
    contact_email: "reader@example.com", app_version: "0.1.0 (202610141205)", os_version: "26.1", device: "iPhone",
    language: "en", context: null, resolved: false, ...overrides,
  };
}

test("a reported mistake in a Bible text is always urgent", () => {
  assert.equal(classifyFeedback("scripture", "Genesis 1:3 has a typo").priority, "urgent");
});

test("bugs are high, and urgent when they mention lost data, money, crashes or sign-in", () => {
  assert.equal(classifyFeedback("bug", "The highlight color is off").priority, "high");
  assert.equal(classifyFeedback("bug", "All my notes disappeared after the update").priority, "urgent");
  assert.equal(classifyFeedback("bug", "I was charged twice").priority, "urgent");
  assert.equal(classifyFeedback("bug", "I can't sign in with Apple").priority, "urgent");
  assert.equal(classifyFeedback("bug", "La app se cierra al abrir el lector").priority, "urgent");
});

test("ideas are low and questions normal", () => {
  assert.equal(classifyFeedback("idea", "Add a dark blue theme").priority, "low");
  assert.equal(classifyFeedback("question", "How do I share a verse?").priority, "normal");
});

test("serious words are matched as whole words", () => {
  assert.ok(soundsSerious("it crashed twice"));
  assert.ok(!soundsSerious("The app crashes-free design is lovely".replace("crashes-free", "calm")));
  assert.ok(!soundsSerious("Lovely app, thank you"));
  assert.ok(!soundsSerious("Paidea is a nice word")); // not "paid"
});

test("feedback rows become items with their details", () => {
  const item = feedbackItem(feedback());
  assert.equal(item.source, "feedback");
  assert.equal(item.priority, "high");
  assert.equal(item.meta.app_version, "0.1.0 (202610141205)");
  assert.ok(item.title.startsWith("Bug: "));
  assert.equal(feedbackItem(feedback({ resolved: true })).status, "resolved");
});

test("reports are grouped per post, and three open reports are urgent", () => {
  const base = { content_type: "group_post", content_id: "p1", reason: "Spam", resolved_at: null, group_id: "g1" };
  const items = reportItems([
    { id: "r1", created_at: "2026-10-14T10:00:00Z", ...base },
    { id: "r2", created_at: "2026-10-14T11:00:00Z", ...base },
    { id: "r3", created_at: "2026-10-14T12:00:00Z", ...base },
    { id: "r4", created_at: "2026-10-14T12:00:00Z", ...base, content_id: "p2" },
  ]);
  assert.equal(items.length, 2);
  const many = items.find((i) => i.id === "group_post:p1")!;
  assert.equal(many.priority, "urgent");
  assert.equal(many.meta.reports, 3);
  assert.equal(many.lastSeenAt, "2026-10-14T12:00:00Z");
  assert.equal(items.find((i) => i.id === "group_post:p2")!.priority, "high");
});

test("reviewed reports are resolved and low", () => {
  const [item] = reportItems([{ id: "r1", content_type: "community_post", content_id: "c1", reason: null, created_at: "2026-10-01T00:00:00Z", resolved_at: "2026-10-02T00:00:00Z", group_id: null }]);
  assert.equal(item.status, "resolved");
  assert.equal(item.priority, "low");
});

test("Sentry: crashes and widespread errors are urgent", () => {
  assert.equal(classifySentry({ id: "1", level: "fatal" }).priority, "urgent");
  assert.equal(classifySentry({ id: "2", level: "error", isUnhandled: true }).priority, "urgent");
  assert.equal(classifySentry({ id: "3", level: "error", userCount: 6, count: "8" }).priority, "urgent");
  assert.equal(classifySentry({ id: "4", level: "error", userCount: 1, count: "2" }).priority, "high");
  assert.equal(classifySentry({ id: "5", level: "warning" }).priority, "normal");
  const item = sentryItem({ id: "9", title: "Fatal error: index out of range", level: "fatal", count: "3", userCount: 2, permalink: "https://sentry.io/x", firstSeen: "2026-10-14T18:00:00Z", lastSeen: "2026-10-14T19:30:00Z" });
  assert.equal(item.link, "https://sentry.io/x");
  assert.equal(item.meta.events, 3);
});

test("TestFlight: crashes are urgent, feedback normal unless it sounds serious", () => {
  const builds = new Map([["b1", "202610141205"]]);
  const items = testFlightItems(
    [
      { id: "s1", attributes: { createdDate: "2026-10-14T19:00:00Z", comment: "Button looks small", deviceModel: "iPhone17,1", osVersion: "26.1", screenshots: [{ url: "https://example.com/a.png" }] }, relationships: { build: { data: { id: "b1" } } } },
      { id: "s2", attributes: { createdDate: "2026-10-14T19:05:00Z", comment: "My sermon notes were deleted" } },
    ],
    [{ id: "c1", attributes: { createdDate: "2026-10-14T19:10:00Z", comment: "" } }],
    builds,
  );
  assert.equal(items.find((i) => i.id === "s1")!.priority, "normal");
  assert.deepEqual(items.find((i) => i.id === "s1")!.images, ["https://example.com/a.png"]);
  assert.equal(items.find((i) => i.id === "s1")!.meta.build, "202610141205");
  assert.equal(items.find((i) => i.id === "s2")!.priority, "high");
  assert.equal(items.find((i) => i.id === "c1")!.priority, "urgent");
});

test("saved triage applies: status, chosen priority, note, emailed", () => {
  const item = feedbackItem(feedback());
  const [updated] = withTriage([item], [{ source: "feedback", external_id: "f1", status: "seen", priority: "low", note: "Known", alerted_at: "2026-10-14T19:01:00Z" }]);
  assert.equal(updated.status, "seen");
  assert.equal(updated.priority, "low");
  assert.equal(updated.priorityOverride, "low");
  assert.equal(updated.note, "Known");
  assert.equal(updated.alertedAt, "2026-10-14T19:01:00Z");
});

test("something resolved that happens again opens again and can be emailed again", () => {
  const item = sentryItem({ id: "9", level: "fatal", lastSeen: "2026-10-14T19:30:00Z", firstSeen: "2026-10-10T00:00:00Z" });
  const [updated] = withTriage([item], [{ source: "sentry", external_id: "9", status: "resolved", priority: null, note: null, alerted_at: "2026-10-11T00:00:00Z", updated_at: "2026-10-12T00:00:00Z" }]);
  assert.equal(updated.status, "new");
  assert.equal(updated.alertedAt, undefined);
  assert.ok(updated.reason.startsWith("Happened again"));
  const [still] = withTriage([item], [{ source: "sentry", external_id: "9", status: "resolved", priority: null, note: null, alerted_at: null, updated_at: "2026-10-14T19:45:00Z" }]);
  assert.equal(still.status, "resolved");
});

test("open first, then priority, then newest", () => {
  const a = { ...feedbackItem(feedback({ id: "a", category: "idea" })) };
  const b = { ...feedbackItem(feedback({ id: "b", category: "scripture" })) };
  const c = { ...feedbackItem(feedback({ id: "c", category: "scripture", resolved: true })) };
  assert.deepEqual(sortItems([a, c, b]).map((i) => i.id), ["b", "a", "c"]);
});

test("only recent, open, urgent items not yet emailed are alerted", () => {
  const urgent = feedbackItem(feedback({ id: "u", category: "scripture" }));
  const old = feedbackItem(feedback({ id: "o", category: "scripture", created_at: "2026-09-01T00:00:00Z" }));
  const emailed: OpsItem = { ...urgent, id: "e", alertedAt: "2026-10-14T19:30:00Z" };
  const resolved: OpsItem = { ...urgent, id: "r", status: "resolved" };
  const high = feedbackItem(feedback({ id: "h" }));
  assert.deepEqual(itemsToAlert([urgent, old, emailed, resolved, high], now).map((i) => i.id), ["u"]);
});

test("emails escape what people wrote and leave out their email addresses", () => {
  const item = feedbackItem(feedback({ category: "scripture", message: "<script>alert(1)</script> in John 3:16" }));
  const { subject, html } = alertEmail([item], "https://7twenty8studio.com/admin");
  assert.ok(subject.startsWith("[Versely urgent]"));
  assert.ok(!html.includes("<script>"));
  assert.ok(html.includes("&lt;script&gt;"));
  assert.ok(!html.includes("reader@example.com"));
  assert.ok(html.includes("https://7twenty8studio.com/admin"));
  assert.equal(escapeHTML(`"a" & <b>`), "&quot;a&quot; &amp; &lt;b&gt;");
});

test("the digest counts open items and lists the last day's", () => {
  const items = [
    feedbackItem(feedback({ id: "1", category: "scripture" })),
    feedbackItem(feedback({ id: "2", category: "idea", created_at: "2026-10-01T00:00:00Z" })),
    feedbackItem(feedback({ id: "3", category: "bug", resolved: true })),
  ];
  const summary = digestSummary(items, now);
  assert.deepEqual(summary.open, { urgent: 1, high: 0, normal: 0, low: 1 });
  assert.deepEqual(summary.newSince.map((i) => i.id), ["1"]);
  const { subject } = digestEmail({ ...summary, metrics: { accounts: 2 } }, "2026-10-14");
  assert.ok(subject.includes("1 new"));
  assert.ok(subject.includes("1 urgent"));
});

test("days and hours are the owner's (Chicago)", () => {
  assert.equal(localDay(new Date("2026-10-15T03:00:00Z")), "2026-10-14");
  assert.equal(localHour(new Date("2026-10-14T13:30:00Z")), 8);
});

test("App Store Connect tokens are ES256 with the right claims", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----`;
  const token = await appStoreConnectToken(pem, "KEY123", "issuer-1", 1_000);
  const [header, claims] = token.split(".").slice(0, 2).map((part) => JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/"))));
  assert.deepEqual(header, { alg: "ES256", kid: "KEY123", typ: "JWT" });
  assert.equal(claims.aud, "appstoreconnect-v1");
  assert.equal(claims.iss, "issuer-1");
  assert.ok(claims.exp - claims.iat <= 20 * 60);
});
