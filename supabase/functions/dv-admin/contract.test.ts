// dv-admin's answers must match the admin site's fixtures exactly
// (7twenty8-studio-web src/app/admin/daily-verse/contract/dv-admin.fixtures.json,
// copied here as dv-admin.fixtures.json). Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/*/*.test.ts
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { adminErrorToHttp, nextBefore, toAdminReport, type ReportRow } from "../_shared/dailyVerse.ts";

const fixtures = JSON.parse(readFileSync(new URL("./dv-admin.fixtures.json", import.meta.url), "utf8"));

/** A database row that should produce `report` (what admin_list_reports returns). */
function rowFor(report: Record<string, unknown>, installHash: string, paths: string[]): ReportRow {
  return {
    id: report.id as string,
    created_at: new Date(report.createdAt as string),
    updated_at: new Date(report.updatedAt as string),
    app: "daily-verse-games",
    channel: report.channel as string,
    app_version: report.appVersion as string,
    build: report.build as string,
    os_version: report.osVersion as string | null,
    device_family: report.deviceFamily as string | null,
    content_language: report.contentLanguage as string,
    puzzle_type: report.puzzleType as string,
    content_id: report.contentId as string,
    challenge_date: report.challengeDate === null ? null : new Date((report.challengeDate as string) + "T00:00:00Z"),
    review_state: report.reviewState as string | null,
    category: report.category as string,
    description: report.description as string,
    install_hash: installHash,
    screenshot_paths: paths,
    screenshot_bytes: paths.map(() => 1000),
    status: report.status as string,
    admin_note: report.adminNote as string | null,
    handled_by: report.handledBy as string | null,
    closed_at: report.closedAt === null ? null : new Date(report.closedAt as string),
  };
}

const hash = (tag: string) => tag + "f".repeat(56);
const paths = (n: number, id: string) => Array.from({ length: n }, (_, i) => `daily-verse/reports/${id}/${i + 1}.jpg`);

test("list reports match the fixtures exactly (keys, order-insensitive values)", () => {
  for (const expected of fixtures.list.reports) {
    const actual = toAdminReport(rowFor(expected, hash(expected.installTag), paths(expected.screenshotCount, expected.id)));
    assert.deepEqual(actual, expected);
  }
});

test("update's report matches the fixture", () => {
  const expected = fixtures.update.report;
  assert.deepEqual({ report: toAdminReport(rowFor(expected, hash(expected.installTag), paths(1, expected.id))) }, fixtures.update);
});

test("no install hash or storage path leaks into a report", () => {
  const expected = fixtures.list.reports[0];
  const actual = toAdminReport(rowFor(expected, hash(expected.installTag), paths(2, expected.id)));
  const text = JSON.stringify(actual);
  assert.equal(text.includes("f".repeat(56)), false);
  assert.equal(text.includes("daily-verse/reports"), false);
  assert.equal(actual.screenshotCount, 2);
  assert.match(actual.installTag, /^[0-9a-f]{8}$/);
});

test("list cursor matches the fixtures", () => {
  assert.equal(nextBefore(fixtures.list.reports, fixtures.list.reports.length), fixtures.list.nextBefore);
  assert.equal(nextBefore(fixtures.listLastPage.reports, 50), fixtures.listLastPage.nextBefore);
});

test("error bodies match the fixtures", () => {
  assert.deepEqual(adminErrorToHttp({ code: "42501" }, "ops@example.com").body, fixtures.errors["403"]);
  assert.deepEqual(adminErrorToHttp({ code: "P0002" }, "x").body, fixtures.errors["404"]);
  assert.deepEqual(adminErrorToHttp({ code: "XX000" }, "x").body, fixtures.errors["500"]);
  // 401, 400 and 429 bodies are written literally in index.ts; checked against the
  // running function by the local integration test (supabase/tests/daily_verse/functions).
  assert.deepEqual(Object.keys(fixtures.errors).sort(), ["400", "401", "403", "404", "429", "500"]);
});

test("me, screenshots and runCleanup fixtures have the documented keys", () => {
  assert.deepEqual(Object.keys(fixtures.me).sort(), ["admin", "email"]);
  assert.deepEqual(Object.keys(fixtures.screenshots.screenshots[0]).sort(), ["expiresAt", "index", "url"]);
  assert.deepEqual(Object.keys(fixtures.runCleanup).sort(), ["deleted", "failed", "rateLimitsPurged", "reportsPurged"]);
});
