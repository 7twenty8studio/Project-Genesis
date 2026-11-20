import { test } from "node:test";
import assert from "node:assert/strict";
import { clientAddress, corsHeaders, dayKey, EventError, isAutomated, parseEventRequest, visitorHash } from "./lib.ts";

const secret = "s".repeat(40);

test("accepts a slug and a known event only", () => {
  assert.deepEqual(parseEventRequest({ slug: "abcdefgh23", kind: "open" }), { slug: "abcdefgh23", kind: "open" });
  assert.deepEqual(parseEventRequest({ slug: "abcdefgh23", kind: "passage", extra: 1 }), { slug: "abcdefgh23", kind: "passage" });
  for (const bad of [null, "x", {}, { slug: "ABCDEFGH23", kind: "open" }, { slug: "abc", kind: "open" },
    { slug: "abcdefgh23", kind: "delete" }, { slug: "../../etc12", kind: "open" }]) {
    assert.throws(() => parseEventRequest(bad), EventError);
  }
});

test("the same visitor on the same day hashes the same", async () => {
  const a = await visitorHash(secret, "2026-11-22", "203.0.113.9", "Safari");
  assert.match(a, /^[0-9a-f]{64}$/);
  assert.equal(a, await visitorHash(secret, "2026-11-22", "203.0.113.9", "Safari"));
});

test("a new day, address, browser or secret gives an unrelated value", async () => {
  const a = await visitorHash(secret, "2026-11-22", "203.0.113.9", "Safari");
  assert.notEqual(a, await visitorHash(secret, "2026-11-23", "203.0.113.9", "Safari"));
  assert.notEqual(a, await visitorHash(secret, "2026-11-22", "203.0.113.10", "Safari"));
  assert.notEqual(a, await visitorHash(secret, "2026-11-22", "203.0.113.9", "Chrome"));
  assert.notEqual(a, await visitorHash("t".repeat(40), "2026-11-22", "203.0.113.9", "Safari"));
  assert.ok(!a.includes("203"));
});

test("refuses a short secret", async () => {
  await assert.rejects(() => visitorHash("short", "2026-11-22", "1.2.3.4", "x"));
});

test("reads the caller's address from the proxy", () => {
  assert.equal(clientAddress(new Headers({ "x-forwarded-for": "203.0.113.9, 10.0.0.1" })), "203.0.113.9");
  assert.equal(clientAddress(new Headers({ "x-real-ip": "198.51.100.2" })), "198.51.100.2");
  assert.equal(clientAddress(new Headers()), "");
});

test("link previews and crawlers are never counted", () => {
  for (const ua of ["", "facebookexternalhit/1.1", "Slackbot-LinkExpanding 1.0", "WhatsApp/2.23", "Googlebot/2.1", "curl/8.4"]) {
    assert.ok(isAutomated(ua), ua);
  }
  assert.ok(!isAutomated("Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 Version/26.1 Mobile Safari/604.1"));
  assert.ok(!isAutomated("Versely/1.0.4 CFNetwork/3826 Darwin/25.1.0"));
});

test("days are UTC dates", () => {
  assert.equal(dayKey(new Date("2026-11-22T23:59:59-06:00")), "2026-11-23");
});

test("CORS only for the guest page's origins", () => {
  const allowed = ["https://versely.7twenty8studio.com"];
  assert.equal(corsHeaders("https://versely.7twenty8studio.com", allowed)["Access-Control-Allow-Origin"], "https://versely.7twenty8studio.com");
  assert.equal(corsHeaders("https://evil.example", allowed)["Access-Control-Allow-Origin"], undefined);
  assert.equal(corsHeaders(null, allowed)["Access-Control-Allow-Origin"], undefined);
});
