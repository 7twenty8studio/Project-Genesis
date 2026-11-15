// End-to-end tests for dv-report, dv-admin and dv-retention against a LOCAL
// Supabase stack (never a hosted project). See README.md next to this file.
//
//   eval "$(supabase status -o env)"           # API_URL, ANON_KEY, PUBLISHABLE_KEY, SECRET_KEY, SERVICE_ROLE_KEY, JWT_SECRET
//   supabase functions serve --no-verify-jwt --env-file <test env>   # DV_* test values (DV_REPORT_KEYS=$PUBLISHABLE_KEY), mock Resend
//   DV_EMAIL_LOG=/tmp/dvb/emails.jsonl node --experimental-strip-types --test \
//     supabase/tests/daily_verse/functions/integration.test.ts
//
// It creates local test users, adds them to daily_verse.admins / public.ops_admins
// ON THE LOCAL STACK ONLY, stops and restarts the local Storage container to
// simulate a Storage outage, and resets Daily Verse rate limits between groups.
import assert from "node:assert/strict";
import { createHmac, randomUUID, randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { before, describe, test } from "node:test";

const API = process.env.API_URL ?? "";
const ANON = process.env.ANON_KEY ?? "";
// dv-report takes the publishable key in `apikey` only, as the app sends it (#36).
const PUBLISHABLE = process.env.PUBLISHABLE_KEY ?? "";
const SECRET_KEY = process.env.SECRET_KEY ?? "";
const SERVICE = process.env.SERVICE_ROLE_KEY ?? "";
const JWT_SECRET = process.env.JWT_SECRET ?? "";
const SUPER = "postgresql://supabase_admin:postgres@127.0.0.1:54322/postgres";
const PSQL = process.env.PSQL ?? "/opt/homebrew/opt/postgresql@17/bin/psql";
const EMAIL_LOG = process.env.DV_EMAIL_LOG ?? "/tmp/dvb/emails.jsonl";
const STORAGE_CONTAINER = process.env.STORAGE_CONTAINER ?? "supabase_storage_Project-Genesis";
const INTERNAL_BUILD = "202611141200";

if (!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(API)) throw new Error(`Refusing: ${API} is not a local Supabase API URL.`);

// --- helpers -------------------------------------------------------------------------------

function sql(query: string): string {
  return execFileSync(PSQL, [SUPER, "-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", query], { encoding: "utf8" }).trim();
}

const JPEG = (extra = 0) => {
  const bytes = randomBytes(64 + extra);
  bytes.set([0xff, 0xd8, 0xff, 0xe0], 0);
  bytes.set([0xff, 0xd9], bytes.length - 2);
  return bytes;
};
const b64 = (b: Uint8Array) => Buffer.from(b).toString("base64");
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function reportBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    appVersion: "0.1.0", build: INTERNAL_BUILD, osVersion: "26.1", deviceFamily: "phone", contentLanguage: "es",
    puzzleType: "crossword", contentId: "es-2026-11-14-gozo.crossword-" + randomUUID().slice(0, 8), challengeDate: "2026-11-14",
    reviewState: "draft", category: "unclear_clue", description: "La pista 3 horizontal no coincide con el versículo.",
    installID: randomUUID(), screenshots: [], ...overrides,
  };
}

const seenBodies: string[] = [];

async function call(fn: string, body: unknown, headers: Record<string, string> = {}, method = "POST") {
  const res = await fetch(`${API}/functions/v1/${fn}`, {
    method,
    headers: { "content-type": "application/json", ...headers },
    body: method === "GET" || method === "OPTIONS" ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
  const text = await res.text();
  seenBodies.push(text + JSON.stringify([...res.headers]));
  let json: any = null;
  try { json = JSON.parse(text); } catch { /* not JSON */ }
  return { status: res.status, json, text, headers: res.headers };
}

const anon = { apikey: PUBLISHABLE };
const report = (body: unknown, headers: Record<string, string> = anon) => call("dv-report", body, headers);
const admin = (token: string, body: unknown, extra: Record<string, string> = {}) =>
  call("dv-admin", body, { apikey: ANON, Authorization: `Bearer ${token}`, ...extra });

function resetLimits() {
  sql("delete from daily_verse.rate_limits");
}

function jwt(payload: Record<string, unknown>, secret: string): string {
  const enc = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const head = enc({ alg: "HS256", typ: "JWT" });
  const body = enc(payload);
  return `${head}.${body}.${createHmac("sha256", secret).update(`${head}.${body}`).digest("base64url")}`;
}

async function signUp(email: string): Promise<{ id: string; token: string }> {
  const password = "local-test-" + randomBytes(9).toString("hex");
  let res = await fetch(`${API}/auth/v1/signup`, { method: "POST", headers: { apikey: ANON, "content-type": "application/json" }, body: JSON.stringify({ email, password }) });
  let data: any = await res.json();
  if (!data.access_token) {
    // Already exists from an earlier run: reset its password locally, then sign in.
    sql(`update auth.users set encrypted_password = extensions.crypt('${password}', extensions.gen_salt('bf')) where email = '${email}'`);
    res = await fetch(`${API}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: ANON, "content-type": "application/json" }, body: JSON.stringify({ email, password }) });
    data = await res.json();
  }
  assert.ok(data.access_token, "local sign-in failed: " + JSON.stringify(data).slice(0, 200));
  return { id: data.user.id, token: data.access_token };
}

function emails(): { body: string }[] {
  if (!existsSync(EMAIL_LOG)) return [];
  return readFileSync(EMAIL_LOG, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
}

async function waitFor<T>(fn: () => T | undefined | null | false, ms = 8000): Promise<T> {
  const end = Date.now() + ms;
  for (;;) {
    const v = fn();
    if (v) return v;
    if (Date.now() > end) throw new Error("timed out");
    await sleep(200);
  }
}

async function storageObjects(prefix: string): Promise<string[]> {
  const res = await fetch(`${API}/storage/v1/object/list/attachments`, {
    method: "POST", headers: { Authorization: `Bearer ${SERVICE}`, "content-type": "application/json" },
    body: JSON.stringify({ prefix, limit: 100 }),
  });
  return ((await res.json()) as { name: string }[]).map((o) => o.name);
}

async function setStorage(running: boolean) {
  execFileSync("docker", [running ? "start" : "stop", STORAGE_CONTAINER], { stdio: "ignore" });
  if (!running) return;
  const end = Date.now() + 60_000;
  while (Date.now() < end) {
    const res = await fetch(`${API}/storage/v1/bucket`, { headers: { Authorization: `Bearer ${SERVICE}` } }).catch(() => null);
    if (res?.status === 200) return;
    await sleep(1000);
  }
  throw new Error("local Storage didn't come back");
}

// --- fixtures ------------------------------------------------------------------------------

let dvAdmin: { id: string; token: string };
let opsOnly: { id: string; token: string };
let plain: { id: string; token: string };
const DV_ADMIN_EMAIL = "dv-admin@example.test";
const OPS_ONLY_EMAIL = "ops-only@example.test";

before(async () => {
  assert.ok(ANON && SERVICE && JWT_SECRET, "run eval \"$(supabase status -o env)\" first");
  assert.match(PUBLISHABLE, /^sb_publishable_/, "PUBLISHABLE_KEY from `supabase status -o env` (and DV_REPORT_KEYS in the functions' env file)");
  dvAdmin = await signUp(DV_ADMIN_EMAIL);
  opsOnly = await signUp(OPS_ONLY_EMAIL);
  plain = await signUp("plain-user@example.test");
  // LOCAL stack only: the Daily Verse allow-list and Versely's ops list.
  sql(`insert into daily_verse.admins (email, note) values ('${DV_ADMIN_EMAIL}', 'local test') on conflict do nothing`);
  sql(`insert into public.ops_admins (email) values ('${OPS_ONLY_EMAIL}') on conflict do nothing`);
  sql(`delete from public.ops_admins where email = '${DV_ADMIN_EMAIL}'`);
  resetLimits();
});

// --- dv-report -------------------------------------------------------------------------------

describe("dv-report", () => {
  test("happy path: 201, HMACs only, screenshots stored under daily-verse/, alert email text-only", async () => {
    resetLimits();
    const before = emails().length;
    const shots = [JPEG(100), JPEG(200)];
    const body = reportBody({ channel: "public", screenshots: shots.map(b64) });
    const res = await report(body, { ...anon, "x-forwarded-for": "198.51.100.23" });
    assert.equal(res.status, 201, res.text);
    assert.match(res.json.id, /^[0-9a-f-]{36}$/);
    assert.deepEqual([res.json.screenshots, res.json.submitted], [2, 2]);
    assert.equal(res.headers.get("cache-control"), "no-store");

    const row = sql(`select channel || '|' || install_hash || '|' || array_to_string(screenshot_paths, ',') || '|' || array_to_string(screenshot_bytes, ',') from daily_verse.reports where id = '${res.json.id}'`);
    const [channel, installHash, paths, sizes] = row.split("|");
    assert.equal(channel, "internal", "client-sent channel ignored (rule 1)");
    assert.match(installHash, /^[0-9a-f]{64}$/);
    assert.notEqual(installHash, (body.installID as string).replace(/-/g, ""));
    assert.equal(paths, `daily-verse/reports/${res.json.id}/1.jpg,daily-verse/reports/${res.json.id}/2.jpg`);
    assert.equal(sizes, `${shots[0].length},${shots[1].length}`);
    assert.deepEqual((await storageObjects(`daily-verse/reports/${res.json.id}/`)).sort(), ["1.jpg", "2.jpg"]);

    // The raw install id and IP never reach the database (rule 6).
    const dump = sql(`select coalesce(string_agg(key, ' '), '') from daily_verse.rate_limits`) + sql(`select row_to_json(r)::text from daily_verse.reports r where id = '${res.json.id}'`);
    assert.equal(dump.includes(body.installID as string), false);
    assert.equal(dump.includes("198.51.100"), false);
    assert.match(sql(`select string_agg(key, ' ' order by key) from daily_verse.rate_limits where key <> 'alert:email'`), /^global install:[0-9a-f]{64} net:[0-9a-f]{64}$/);

    const mail = await waitFor(() => emails().length > before && emails().at(-1));
    const sent = JSON.parse(mail.body);
    assert.match(sent.subject, /^\[Daily Verse\] New problem report: unclear clue \(crossword, es\)$/);
    assert.deepEqual(sent.to, ["dv-alerts@example.test"]);
    assert.equal(/\.jpg|storage\/v1|sign\/|<img|base64/i.test(sent.html), false, "no screenshot or link to one in the email");
    assert.match(sent.html, new RegExp(res.json.id));
  });

  test("duplicate within 10 minutes: 200 {id, duplicate: true}, kept once", async () => {
    resetLimits();
    const body = reportBody();
    const first = await report(body);
    assert.equal(first.status, 201);
    const again = await report({ ...body, description: "Same thing again" });
    assert.equal(again.status, 200);
    assert.deepEqual(again.json, { id: first.json.id, duplicate: true, screenshots: 0 });
    assert.equal(sql(`select count(*) from daily_verse.reports where content_id = '${body.contentId}'`), "1");
  });

  test("the server decides the channel: an unlisted build is refused even if it says internal (503)", async () => {
    resetLimits();
    const res = await report(reportBody({ build: "999", channel: "internal" }));
    assert.deepEqual([res.status, res.json], [503, { error: "unavailable" }]);
  });

  test("400s name the field; spam maps to description", async () => {
    resetLimits();
    const cases: [Record<string, unknown>, string][] = [
      [{ installID: "nope" }, "installID"], [{ puzzleType: "verseGuess" }, "puzzleType"], [{ category: "rude" }, "category"],
      [{ contentLanguage: "fr" }, "contentLanguage"], [{ description: "" }, "description"], [{ challengeDate: "2026-02-31" }, "challengeDate"],
      [{ screenshots: [b64(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]))] }, "screenshots"],
      [{ screenshots: [b64(JPEG()), b64(JPEG()), b64(JPEG())] }, "screenshots"],
      [{ description: "see http://a.example http://b.example http://c.example http://d.example" }, "description"],
      [{ description: "a".repeat(40) }, "description"],
    ];
    for (const [overrides, field] of cases) {
      const res = await report(reportBody(overrides));
      assert.equal(res.status, 400, JSON.stringify(overrides) + " → " + res.text);
      assert.deepEqual(res.json, { error: "invalid", field }, JSON.stringify(overrides));
    }
    const notJson = await report("{not json");
    assert.deepEqual([notJson.status, notJson.json], [400, { error: "invalid", field: "body" }]);
  });

  test("413 for a body over 4 MB and for a screenshot over 1.5 MB", async () => {
    resetLimits();
    const huge = await report(reportBody({ description: "x", padding: "y".repeat(4 * 1024 * 1024 + 10) }));
    assert.equal(huge.status, 413);
    const bigShot = await report(reportBody({ screenshots: [b64(JPEG(1_572_864))] }));
    assert.deepEqual([bigShot.status, bigShot.json], [413, { error: "too_large" }]);
    const exact = await report(reportBody({ screenshots: [b64(JPEG(1_572_864 - 64))] }));
    assert.equal(exact.status, 201, "exactly 1.5 MB is accepted");
  });

  test("429 with Retry-After after 5 reports from one install in an hour", async () => {
    resetLimits();
    const installID = randomUUID();
    for (let i = 0; i < 5; i++) assert.equal((await report(reportBody({ installID }))).status, 201, `report ${i + 1}`);
    const sixth = await report(reportBody({ installID }));
    assert.deepEqual([sixth.status, sixth.json], [429, { error: "rate_limited" }]);
    assert.match(sixth.headers.get("retry-after") ?? "", /^\d+$/);
    assert.ok(Number(sixth.headers.get("retry-after")) > 0);
  });

  test("the network bucket (20/h) applies across installs; a client-supplied X-Forwarded-For can't dodge it", async () => {
    resetLimits();
    let last = 0;
    for (let i = 0; i < 21; i++) {
      last = (await report(reportBody(), { ...anon, "x-forwarded-for": `10.${i}.0.1` })).status;
      if (i < 20) assert.equal(last, 201, `report ${i + 1}`);
    }
    assert.equal(last, 429);
  });

  test("alert emails are throttled (take_token 'alert:email')", async () => {
    resetLimits();
    sql(`insert into daily_verse.rate_limits (key, tokens, refilled_at) values ('alert:email', 0, now())`);
    const before = emails().length;
    assert.equal((await report(reportBody())).status, 201);
    await sleep(2000);
    assert.equal(emails().length, before, "no email while the alert bucket is empty");
  });

  test("Storage down after the row is saved: still 201, nothing attached", async () => {
    resetLimits();
    await setStorage(false);
    try {
      const res = await report(reportBody({ screenshots: [b64(JPEG())] }));
      assert.equal(res.status, 201, res.text);
      assert.deepEqual([res.json.screenshots, res.json.submitted], [0, 1], "the app is told the picture wasn't saved");
      assert.equal(sql(`select cardinality(screenshot_paths) from daily_verse.reports where id = '${res.json.id}'`), "0");
    } finally {
      await setStorage(true);
    }
  });

  test("attach_screenshot failing removes the uploaded file (Storage first, database after)", async () => {
    resetLimits();
    sql("revoke execute on function daily_verse.attach_screenshot(uuid, integer, integer) from service_role");
    try {
      const res = await report(reportBody({ screenshots: [b64(JPEG())] }));
      assert.equal(res.status, 201);
      assert.deepEqual([res.json.screenshots, res.json.submitted], [0, 1]);
      assert.deepEqual(await storageObjects(`daily-verse/reports/${res.json.id}/`), [], "orphan upload removed");
    } finally {
      sql("grant execute on function daily_verse.attach_screenshot(uuid, integer, integer) to service_role");
    }
  });

  test("one of two screenshots saved: 201 {screenshots: 1, submitted: 2}, the duplicate says the same", async () => {
    resetLimits();
    // Local stack only: make the second attach fail, as a mid-report Storage/database hiccup would.
    sql(`create or replace function daily_verse.dvtest_second_attach_fails() returns trigger language plpgsql as $f$
      begin if cardinality(new.screenshot_paths) = 2 and cardinality(old.screenshot_paths) = 1 then
        raise exception 'simulated failure' using errcode = 'P0001'; end if; return new; end $f$`);
    sql("create trigger dvtest_second_attach_fails before update on daily_verse.reports for each row execute function daily_verse.dvtest_second_attach_fails()");
    try {
      const body = reportBody({ screenshots: [b64(JPEG(10)), b64(JPEG(20))] });
      const res = await report(body);
      assert.equal(res.status, 201, res.text);
      assert.deepEqual([res.json.screenshots, res.json.submitted], [1, 2]);
      assert.deepEqual(await storageObjects(`daily-verse/reports/${res.json.id}/`), ["1.jpg"], "the failed second upload was removed");
      const again = await report(body);
      assert.deepEqual([again.status, again.json], [200, { id: res.json.id, duplicate: true, screenshots: 1 }]);
    } finally {
      sql("drop trigger if exists dvtest_second_attach_fails on daily_verse.reports");
      sql("drop function if exists daily_verse.dvtest_second_attach_fails()");
    }
  });

  test("auth: only the publishable key in apikey; 401 without it, before anything is read", async () => {
    assert.equal((await call("dv-report", null, anon, "GET")).status, 405);
    const before = sql("select count(*) from daily_verse.reports");
    const refused: [string, Record<string, string>][] = [
      ["no headers", {}],
      ["a wrong publishable key", { apikey: "sb_publishable_" + "x".repeat(24) }],
      ["the key with one character changed", { apikey: PUBLISHABLE.slice(0, -1) + (PUBLISHABLE.endsWith("a") ? "b" : "a") }],
      ["the legacy anon JWT", { apikey: ANON, Authorization: `Bearer ${ANON}` }],
      ["the service role JWT", { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` }],
      ["the key only as Bearer", { Authorization: `Bearer ${PUBLISHABLE}` }],
      ...(SECRET_KEY ? [["the secret key", { apikey: SECRET_KEY }] as [string, Record<string, string>]] : []),
    ];
    for (const [label, headers] of refused) {
      const res = await report(reportBody(), headers);
      assert.deepEqual([res.status, res.json], [401, { error: "unauthorized" }], label);
    }
    assert.equal(sql("select count(*) from daily_verse.reports"), before, "nothing saved for a refused call");
    resetLimits();
    assert.equal((await report(reportBody(), { apikey: PUBLISHABLE })).status, 201, "the app's headers: apikey only");
  });
});

// --- dv-admin --------------------------------------------------------------------------------

describe("dv-admin", () => {
  const fixtureKeys = ["adminNote", "appVersion", "build", "category", "challengeDate", "channel", "closedAt", "contentId", "contentLanguage",
    "createdAt", "description", "deviceFamily", "handledBy", "id", "installTag", "osVersion", "puzzleType", "reviewState",
    "screenshotCount", "status", "updatedAt"];

  test("401: no token, the anon key, a forged token, an expired token, a deleted user", async () => {
    assert.equal((await call("dv-admin", { action: "me" }, { apikey: ANON })).status, 401);
    const anonCall = await admin(ANON, { action: "me" });
    assert.deepEqual([anonCall.status, anonCall.json], [401, { error: "unauthorized" }]);
    const now = Math.floor(Date.now() / 1000);
    const claims = { sub: dvAdmin.id, email: DV_ADMIN_EMAIL, role: "authenticated", aud: "authenticated", iat: now, exp: now + 3600 };
    assert.equal((await admin(jwt(claims, "not-the-project-secret-" + "x".repeat(20)), { action: "me" })).status, 401, "forged signature");
    assert.equal((await admin(jwt({ ...claims, iat: now - 7200, exp: now - 3600 }, JWT_SECRET), { action: "me" })).status, 401, "expired");
    const ghost = await admin(jwt({ ...claims, sub: randomUUID() }, JWT_SECRET), { action: "me" });
    assert.deepEqual([ghost.status, ghost.json], [401, { error: "unauthorized" }], "validly signed, but no such user: getUser refuses");
  });

  test("403 for a Versely ops admin who isn't a Daily Verse admin, even naming the admin in the body", async () => {
    for (const body of [{ action: "me" }, { action: "me", email: DV_ADMIN_EMAIL }, { action: "list", actor: DV_ADMIN_EMAIL }]) {
      const res = await admin(opsOnly.token, body, { "x-admin-email": DV_ADMIN_EMAIL });
      assert.deepEqual([res.status, res.json], [403, { error: "forbidden", email: OPS_ONLY_EMAIL }]);
      assert.equal(res.headers.get("cache-control"), "no-store");
    }
    const other = await admin(plain.token, { action: "me" });
    assert.deepEqual([other.status, other.json], [403, { error: "forbidden", email: "plain-user@example.test" }]);
  });

  test("me", async () => {
    const res = await admin(dvAdmin.token, { action: "me" });
    assert.deepEqual([res.status, res.json], [200, { email: DV_ADMIN_EMAIL, admin: true }]);
    assert.equal(res.headers.get("cache-control"), "no-store");
  });

  test("list: fixture shape, no hash or paths, filters, cursor", async () => {
    resetLimits();
    await report(reportBody({ contentLanguage: "en", puzzleType: "trivia", category: "biblical_inaccuracy", reviewState: null, challengeDate: null, osVersion: null, deviceFamily: null }));
    const res = await admin(dvAdmin.token, { action: "list", limit: 200 });
    assert.equal(res.status, 200);
    assert.ok(res.json.reports.length >= 2);
    for (const r of res.json.reports) {
      assert.deepEqual(Object.keys(r).sort(), fixtureKeys);
      assert.match(r.installTag, /^[0-9a-f]{8}$/);
    }
    const text = JSON.stringify(res.json);
    assert.equal(/[0-9a-f]{64}/.test(text), false, "no full install hash");
    assert.equal(text.includes("daily-verse/reports"), false, "no storage paths");
    const en = await admin(dvAdmin.token, { action: "list", language: "en", category: "biblical_inaccuracy" });
    assert.ok(en.json.reports.length >= 1 && en.json.reports.every((r: any) => r.contentLanguage === "en" && r.category === "biblical_inaccuracy"));
    const page1 = await admin(dvAdmin.token, { action: "list", limit: 1 });
    assert.equal(page1.json.reports.length, 1);
    assert.ok(page1.json.nextBefore);
    const page2 = await admin(dvAdmin.token, { action: "list", limit: 1, before: page1.json.nextBefore });
    assert.notEqual(page2.json.reports[0]?.id, page1.json.reports[0].id);
    const bad = await admin(dvAdmin.token, { action: "list", status: "open" });
    assert.deepEqual([bad.status, bad.json], [400, { error: "invalid", field: "status" }]);
  });

  test("update: status, note and audit by the verified admin; 400 and 404", async () => {
    resetLimits();
    const { json } = await report(reportBody());
    const res = await admin(dvAdmin.token, { action: "update", id: json.id, status: "in_review", note: "Checking with the editor", email: "someone@else.test" });
    assert.equal(res.status, 200, res.text);
    assert.deepEqual(Object.keys(res.json), ["report"]);
    assert.equal(res.json.report.status, "in_review");
    assert.equal(res.json.report.adminNote, "Checking with the editor");
    assert.equal(res.json.report.handledBy, DV_ADMIN_EMAIL);
    assert.equal(sql(`select actor_email || '|' || from_status || '|' || to_status from daily_verse.report_events where report_id = '${json.id}'`), `${DV_ADMIN_EMAIL}|new|in_review`);
    const resolved = await admin(dvAdmin.token, { action: "update", id: json.id, status: "resolved" });
    assert.ok(resolved.json.report.closedAt);
    assert.deepEqual((await admin(dvAdmin.token, { action: "update", id: json.id, status: "closed" })).json, { error: "invalid", field: "status" });
    const missing = await admin(dvAdmin.token, { action: "update", id: randomUUID(), status: "new" });
    assert.deepEqual([missing.status, missing.json], [404, { error: "not_found" }]);
  });

  test("screenshots: 5-minute signed URLs that serve the file; none for others' paths", async () => {
    resetLimits();
    const shots = [JPEG(300), JPEG(400)];
    const { json } = await report(reportBody({ screenshots: shots.map(b64) }));
    const res = await admin(dvAdmin.token, { action: "screenshots", id: json.id });
    assert.equal(res.status, 200);
    assert.equal(res.json.screenshots.length, 2);
    for (const [i, s] of res.json.screenshots.entries()) {
      assert.deepEqual(Object.keys(s).sort(), ["expiresAt", "index", "url"]);
      assert.equal(s.index, i);
      const ttl = (Date.parse(s.expiresAt) - Date.now()) / 1000;
      assert.ok(ttl > 290 && ttl <= 302, `expires in ${ttl}s (2 s allowed for clock skew between the container and this machine)`);
      const token = new URL(s.url).searchParams.get("token")!;
      const claims = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
      assert.equal(claims.exp - claims.iat, 300, "the signed URL itself expires after 300 s");
      const local = s.url.replace(/^https?:\/\/[^/]+/, API);
      const file = await fetch(local);
      assert.equal(file.status, 200);
      assert.deepEqual(Buffer.from(await file.arrayBuffer()), Buffer.from(shots[i]));
    }
    assert.deepEqual((await admin(dvAdmin.token, { action: "screenshots", id: randomUUID() })).json, { error: "not_found" });
    const forbidden = await admin(opsOnly.token, { action: "screenshots", id: json.id });
    assert.equal(forbidden.status, 403);
  });

  test("runCleanup is admin-only and rate-limited", async () => {
    resetLimits();
    assert.equal((await admin(opsOnly.token, { action: "runCleanup" })).status, 403);
    for (let i = 0; i < 2; i++) {
      const res = await admin(dvAdmin.token, { action: "runCleanup" });
      assert.equal(res.status, 200, res.text);
      assert.deepEqual(Object.keys(res.json).sort(), ["deleted", "failed", "rateLimitsPurged", "reportsPurged"]);
    }
    const third = await admin(dvAdmin.token, { action: "runCleanup" });
    assert.deepEqual([third.status, third.json], [429, { error: "rate_limited" }]);
    assert.match(third.headers.get("retry-after") ?? "", /^\d+$/);
  });

  test("CORS: the studio origin only, never a wildcard (asked of the function itself)", async () => {
    // The local Kong adds its own `Access-Control-Allow-Origin: *` to every function
    // response (a CLI default), so ask the edge runtime directly from inside the
    // Docker network.
    const ask = (origin: string, method: string) => JSON.parse(execFileSync("docker", ["exec", STORAGE_CONTAINER, "node", "-e", `
      fetch("http://supabase_edge_runtime_Project-Genesis:8081/dv-admin", { method: ${JSON.stringify(method)},
        headers: { Origin: ${JSON.stringify(origin)}, "Access-Control-Request-Method": "POST", "content-type": "application/json" },
        body: ${method === "POST" ? "'{}'" : "undefined"} })
        .then((r) => console.log(JSON.stringify({ status: r.status, acao: r.headers.get("access-control-allow-origin"), cache: r.headers.get("cache-control") })));
    `], { encoding: "utf8" }));
    assert.deepEqual(ask("http://localhost:3000", "OPTIONS"), { status: 204, acao: "http://localhost:3000", cache: "no-store" });
    assert.deepEqual(ask("https://evil.example", "OPTIONS"), { status: 204, acao: null, cache: "no-store" });
    const post = ask("https://evil.example", "POST");
    assert.equal(post.acao, null);
    assert.equal(post.status, 401);
  });
});

// --- dv-retention --------------------------------------------------------------------------------

describe("dv-retention", () => {
  const secret = () => sql("select decrypted_secret from vault.decrypted_secrets where name = 'dv_retention_secret'");

  test("refuses without the Vault secret", async () => {
    assert.deepEqual((await call("dv-retention", {})).json, { error: "forbidden" });
    assert.equal((await call("dv-retention", {}, { "x-dv-retention-secret": "x".repeat(64) })).status, 403);
    assert.equal((await call("dv-retention", {}, { "x-dv-retention-secret": secret().slice(0, -1) + "0" })).status, 403);
  });

  test("90 days after closing: a failed Storage delete stays listed, then the next run deletes and marks it", async () => {
    resetLimits();
    const { json } = await report(reportBody({ screenshots: [b64(JPEG())] }));
    await admin(dvAdmin.token, { action: "update", id: json.id, status: "resolved" });
    sql(`update daily_verse.reports set closed_at = now() - interval '91 days' where id = '${json.id}'`);
    const paths = () => sql(`select array_to_string(screenshot_paths, ',') from daily_verse.reports where id = '${json.id}'`);

    await setStorage(false);
    let failedRun;
    try {
      failedRun = await call("dv-retention", {}, { "x-dv-retention-secret": secret() });
    } finally {
      await setStorage(true);
    }
    assert.equal(failedRun.status, 200, failedRun.text);
    assert.ok(failedRun.json.failed >= 1);
    assert.equal(paths(), `daily-verse/reports/${json.id}/1.jpg`, "still listed after a failed delete");

    const ok = await call("dv-retention", {}, { "x-dv-retention-secret": secret() });
    assert.equal(ok.status, 200);
    assert.ok(ok.json.deleted >= 1);
    assert.equal(paths(), "", "marked deleted only after Storage succeeded");
    assert.deepEqual(await storageObjects(`daily-verse/reports/${json.id}/`), []);
    assert.equal(sql(`select count(*) from daily_verse.reports where id = '${json.id}'`), "1", "the report text stays (1 year)");
  });

  test("an open or recently closed report keeps its screenshots", async () => {
    resetLimits();
    const { json } = await report(reportBody({ screenshots: [b64(JPEG())] }));
    await admin(dvAdmin.token, { action: "update", id: json.id, status: "dismissed" });
    sql(`update daily_verse.reports set closed_at = now() - interval '89 days' where id = '${json.id}'`);
    await call("dv-retention", {}, { "x-dv-retention-secret": secret() });
    assert.equal(sql(`select cardinality(screenshot_paths) from daily_verse.reports where id = '${json.id}'`), "1");
    assert.deepEqual(await storageObjects(`daily-verse/reports/${json.id}/`), ["1.jpg"]);
  });

  test("report text is purged after a year; Versely objects in the bucket are never touched", async () => {
    resetLimits();
    const { json } = await report(reportBody());
    sql(`update daily_verse.reports set created_at = now() - interval '366 days' where id = '${json.id}'`);
    const versely = `${plain.id}/own.jpg`;
    await fetch(`${API}/storage/v1/object/attachments/${versely}`, { method: "POST", headers: { Authorization: `Bearer ${SERVICE}`, "content-type": "image/jpeg" }, body: JPEG() });
    const res = await call("dv-retention", {}, { "x-dv-retention-secret": secret() });
    assert.ok(res.json.reportsPurged >= 1);
    assert.equal(sql(`select count(*) from daily_verse.reports where id = '${json.id}'`), "0");
    assert.deepEqual(await storageObjects(`${plain.id}/`), ["own.jpg"]);
  });

  test("the schedule: call_retention does nothing without a URL, and calls the LOCAL function when given one", async () => {
    assert.equal(sql("select coalesce(daily_verse.call_retention()::text, 'null')"), "null");
    assert.equal(sql("select count(*) from cron.job where jobname = 'daily-verse-screenshot-cleanup' and schedule = '47 3 * * *' and active"), "1");
    sql("select vault.create_secret('http://kong:8000/functions/v1/dv-retention', 'dv_retention_url', 'LOCAL TEST ONLY')");
    try {
      const id = sql("select daily_verse.call_retention()");
      const status = await waitFor(() => sql(`select status_code from net._http_response where id = ${id}`) || null, 20_000);
      assert.equal(status, "200");
      assert.match(sql(`select content from net._http_response where id = ${id}`), /"deleted":\d+/);
    } finally {
      sql("delete from vault.secrets where name = 'dv_retention_url'");
    }
  });
});

// --- Versely regression -------------------------------------------------------------------------

describe("Versely unaffected", () => {
  test("ops-dashboard still serves its ops admin and refuses the Daily Verse-only admin", async () => {
    const ops = await call("ops-dashboard", { action: "overview" }, { apikey: ANON, Authorization: `Bearer ${opsOnly.token}`, Origin: "http://localhost:3000" });
    assert.equal(ops.status, 200, ops.text);
    assert.ok(Array.isArray(ops.json.items));
    const dv = await call("ops-dashboard", { action: "overview" }, { apikey: ANON, Authorization: `Bearer ${dvAdmin.token}` });
    assert.equal(dv.status, 403, "daily_verse.admins grants nothing in Versely");
  });

  test("a Versely user still reads their own attachments, and can't reach daily-verse/", async () => {
    const own = await fetch(`${API}/storage/v1/object/authenticated/attachments/${plain.id}/own.jpg`, { headers: { apikey: ANON, Authorization: `Bearer ${plain.token}` } });
    assert.equal(own.status, 200);
    const list = await fetch(`${API}/storage/v1/object/list/attachments`, { method: "POST", headers: { apikey: ANON, Authorization: `Bearer ${plain.token}`, "content-type": "application/json" }, body: JSON.stringify({ prefix: "daily-verse/reports/" }) });
    assert.deepEqual(await list.json(), []);
  });
});

describe("secrets never reach a client", () => {
  test("no response body or header ever contained the service key or the JWT secret (rule 3)", () => {
    assert.ok(seenBodies.length > 50, `checked ${seenBodies.length} responses`);
    for (const text of seenBodies) {
      assert.equal(text.includes(SERVICE), false);
      assert.equal(text.includes(JWT_SECRET), false);
    }
  });
});
