// End-to-end test of dv-report's App Attest flow over HTTP, against a LOCAL
// Postgres and a locally served dv-report (run.sh starts both; never a hosted
// project). The "device" is fakeDevice.ts with a throwaway root that run.sh
// pins through testRoot.ts. Covers: challenge → attest → report, retries
// without duplicates, replays, tampering, unknown keys, development keys,
// public builds without attestation, a closed channel then a retry, both
// languages, the per-key rate limit, and older Internal builds.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { before, beforeEach, describe, test } from "node:test";
import { FakeCA, FakeDevice } from "./fakeDevice.ts";

const URL_ = process.env.DV_E2E_URL ?? "";
const KEY = process.env.DV_E2E_APIKEY ?? "";
const DB = process.env.DV_E2E_DB ?? "";
const PSQL = process.env.PSQL ?? "psql";
const APP_ID = "4XTR53RY2V.com.7twenty8studio.dailyverse";
const PUBLIC_BUILD = "202611170100";
const INTERNAL_BUILD = "202611141200";
if (!/^http:\/\/127\.0\.0\.1:\d+/.test(URL_) || !/127\.0\.0\.1/.test(DB)) throw new Error("Refusing: local URLs only.");

// The CA whose root the local server pins (run.sh made it and passes its folder).
const ca = new FakeCA(JSON.parse(process.env.DV_E2E_CA ?? "{}").dir ?? (() => { throw new Error("DV_E2E_CA not set"); })());

function sql(q: string): string {
  return execFileSync(PSQL, [DB, "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", q], { encoding: "utf8" }).trim();
}

async function post(body: unknown, headers: Record<string, string> = {}, raw?: Buffer) {
  const res = await fetch(URL_, {
    method: "POST",
    headers: { apikey: KEY, "content-type": "application/json", ...headers },
    body: raw ?? JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() as Record<string, unknown>, retryAfter: res.headers.get("retry-after") };
}

async function challenge(purpose: "attest" | "report"): Promise<string> {
  const r = await post({ action: "challenge", purpose });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.challenge as string;
}

async function attested(environment: "production" | "development" = "production"): Promise<FakeDevice> {
  const device = new FakeDevice(ca, APP_ID);
  const c = await challenge("attest");
  const r = await post({ action: "attest", keyId: device.keyId, attestation: device.attest(c, environment), challenge: c });
  if (environment === "production") assert.equal(r.status, 200, JSON.stringify(r.body));
  return device;
}

function report(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    reportID: randomUUID(), installID: randomUUID(), appVersion: "1.0", build: PUBLIC_BUILD, osVersion: "26.1",
    deviceFamily: "phone", contentLanguage: "en", puzzleType: "crossword", contentId: "en-2026-11-17.crossword",
    challengeDate: "2026-11-17", reviewState: "approved", category: "unclear_clue",
    description: "Clue 3 Across doesn't match the verse.", screenshots: [], ...overrides,
  };
}

/** Sends a report the way the app does: fresh challenge, assertion over the exact body. */
async function send(device: FakeDevice, body: Record<string, unknown>, opts: { counter?: number; tamper?: boolean } = {}) {
  const c = await challenge("report");
  const raw = Buffer.from(JSON.stringify(body));
  const assertion = device.assert(c, raw, opts.counter);
  const sent = opts.tamper ? Buffer.from(JSON.stringify({ ...body, description: "Changed after signing." })) : raw;
  const headers = { "x-dv-attest-key": device.keyId, "x-dv-assertion": assertion, "x-dv-challenge": c };
  return { ...(await post(null, headers, sent)), headers, raw: sent };
}

const openPublic = () => sql("update daily_verse.settings set accepted_channels = array['internal','public'] where id = 1");
const closePublic = () => sql("update daily_verse.settings set accepted_channels = array['internal'] where id = 1");
const resetLimits = () => sql("delete from daily_verse.rate_limits");

describe("dv-report with App Attest (local)", () => {
  before(() => openPublic());
  // Every request here comes from 127.0.0.1, one network: start each test with fresh per-network limits.
  beforeEach(() => resetLimits());

  test("English and Spanish reports from a public build are accepted and stored as public", async () => {
    const device = await attested();
    for (const lang of ["en", "es"]) {
      const body = report({ contentLanguage: lang, contentId: `${lang}-2026-11-17.crossword`,
        description: lang === "es" ? "La pista 3 horizontal no coincide con el versículo." : "Clue 3 Across doesn't match the verse." });
      const r = await send(device, body);
      assert.equal(r.status, 201, JSON.stringify(r.body));
      const row = sql(`select channel || '|' || content_language || '|' || client_report_id from daily_verse.reports where id = '${r.body.id}'`);
      assert.equal(row, `public|${lang}|${body.reportID}`);
    }
  });

  test("a retry of the same report (new challenge, same reportID) is kept once", async () => {
    const device = await attested();
    const body = report();
    const first = await send(device, body);
    assert.equal(first.status, 201);
    const again = await send(device, body);
    assert.equal(again.status, 200, JSON.stringify(again.body));
    assert.equal(again.body.duplicate, true);
    assert.equal(again.body.id, first.body.id);
    assert.equal(sql(`select count(*) from daily_verse.reports where client_report_id = '${body.reportID}'`), "1");
  });

  test("a failed submission (channel closed) can be retried with the same report and is then saved once", async () => {
    const device = await attested();
    const body = report({ contentId: "en-2026-11-18.word_search", puzzleType: "word_search" });
    closePublic();
    const failed = await send(device, body);
    assert.equal(failed.status, 503);
    assert.equal(sql(`select count(*) from daily_verse.reports where client_report_id = '${body.reportID}'`), "0");
    openPublic();
    const retried = await send(device, body);
    assert.equal(retried.status, 201, JSON.stringify(retried.body));
    const twice = await send(device, body);
    assert.equal(twice.status, 200);
    assert.equal(sql(`select count(*) from daily_verse.reports where client_report_id = '${body.reportID}'`), "1");
  });

  test("replaying a captured request is refused (challenge already used)", async () => {
    const device = await attested();
    const sent = await send(device, report({ contentId: "en-replay" }));
    assert.equal(sent.status, 201);
    const replay = await post(null, sent.headers, sent.raw);
    assert.equal(replay.status, 401);
    assert.equal(replay.body.reason, "challenge");
  });

  test("an old counter is refused even with a fresh challenge", async () => {
    const device = await attested();
    assert.equal((await send(device, report({ contentId: "en-counter-1" }), { counter: 5 })).status, 201);
    const old = await send(device, report({ contentId: "en-counter-2" }), { counter: 5 });
    assert.equal(old.status, 401);
    assert.equal(old.body.reason, "invalid");
  });

  test("a body changed after signing is refused", async () => {
    const device = await attested();
    const r = await send(device, report({ contentId: "en-tamper" }), { tamper: true });
    assert.equal(r.status, 401);
    assert.equal(r.body.reason, "invalid");
  });

  test("a public build without attestation is refused", async () => {
    const r = await post(report({ contentId: "en-none" }));
    assert.equal(r.status, 401);
    assert.equal(r.body.reason, "required");
  });

  test("a key the server never attested is refused with reason key", async () => {
    const stranger = new FakeDevice(ca, APP_ID);
    const r = await send(stranger, report({ contentId: "en-stranger" }));
    assert.equal(r.status, 401);
    assert.equal(r.body.reason, "key");
  });

  test("development-environment keys are refused", async () => {
    const device = new FakeDevice(ca, APP_ID);
    const c = await challenge("attest");
    const r = await post({ action: "attest", keyId: device.keyId, attestation: device.attest(c, "development"), challenge: c });
    assert.equal(r.status, 401);
    assert.equal(r.body.reason, "invalid");
  });

  test("an attestation from another root (not the pinned one) is refused", async () => {
    const other = new FakeDevice(new FakeCA(), APP_ID);
    const c = await challenge("attest");
    const r = await post({ action: "attest", keyId: other.keyId, attestation: other.attest(c), challenge: c });
    assert.equal(r.status, 401);
    assert.equal(r.body.reason, "invalid");
  });

  test("an attestation for another app is refused", async () => {
    const other = new FakeDevice(ca, "AAAAAAAAAA.com.example.other");
    const c = await challenge("attest");
    const r = await post({ action: "attest", keyId: other.keyId, attestation: other.attest(c), challenge: c });
    assert.equal(r.status, 401);
  });

  test("an attest challenge can't be used again", async () => {
    const device = new FakeDevice(ca, APP_ID);
    const c = await challenge("attest");
    const attestation = device.attest(c);
    assert.equal((await post({ action: "attest", keyId: device.keyId, attestation, challenge: c })).status, 200);
    const again = await post({ action: "attest", keyId: device.keyId, attestation, challenge: c });
    assert.equal(again.status, 401);
    assert.equal(again.body.reason, "challenge");
  });

  test("one key can send at most 5 new reports an hour (429 with Retry-After)", async () => {
    resetLimits();
    const device = await attested();
    for (let i = 0; i < 5; i++) {
      const r = await send(device, report({ installID: randomUUID(), contentId: `en-limit-${i}` }));
      assert.equal(r.status, 201, `report ${i}: ${JSON.stringify(r.body)}`);
    }
    const sixth = await send(device, report({ installID: randomUUID(), contentId: "en-limit-6" }));
    assert.equal(sixth.status, 429);
    assert.ok(Number(sixth.retryAfter) > 0);
    resetLimits();
  });

  test("older Internal builds (no attestation, no reportID) still work", async () => {
    const body = report({ build: INTERNAL_BUILD, contentId: "en-internal-legacy" });
    delete body.reportID;
    const r = await post(body);
    assert.equal(r.status, 201, JSON.stringify(r.body));
    assert.equal(sql(`select channel from daily_verse.reports where id = '${r.body.id}'`), "internal");
  });

  test("an attested report must carry a reportID", async () => {
    const device = await attested();
    const body = report({ contentId: "en-noid" });
    delete body.reportID;
    const r = await send(device, body);
    assert.equal(r.status, 400);
    assert.equal(r.body.field, "reportID");
  });

  test("nothing identifying is stored: hashes only, no raw key id, install id or IP", async () => {
    const keys = sql("select count(*) from daily_verse.attest_keys where key_hash !~ '^[0-9a-f]{64}$'");
    assert.equal(keys, "0");
    const cols = sql("select string_agg(column_name, ',' order by column_name) from information_schema.columns where table_schema = 'daily_verse' and table_name = 'attest_keys'");
    assert.equal(cols, "created_at,environment,key_hash,last_used_at,public_key,sign_count");
  });
});
