import { test } from "node:test";
import assert from "node:assert/strict";
import { coverName, isJpeg, parseAccess, PRIVATE_HEADERS } from "./lib.ts";

const g = "11111111-2222-4333-8444-555555555555";
const s = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const c = "01234567-89ab-4cde-8f01-23456789abcd";
const base = "https://x.supabase.co/functions/v1/sermon-cover";

test("only a cover's own name is accepted", () => {
  assert.equal(coverName(`${base}?name=${g}/${s}/${c}.jpg`), `${g}/${s}/${c}.jpg`);
  for (const bad of ["", `${g}/${s}.jpg`, `${g}/${s}/${c}.png`, `${g}/${s}/../${c}.jpg`, `${g}/${s.toUpperCase()}/${c}.jpg`,
    `${g}/${s}/${c}.jpg/extra`, `x/${g}/${s}/${c}.jpg`]) {
    assert.equal(coverName(`${base}?name=${encodeURIComponent(bad)}`), null, bad);
  }
  assert.equal(coverName(base), null);
});

test("access is only ever what the database said", () => {
  assert.equal(parseAccess(200, "read"), "read");
  assert.equal(parseAccess(200, "edit"), "edit");
  assert.equal(parseAccess(200, null), null);
  assert.equal(parseAccess(200, "READ"), null);
  assert.equal(parseAccess(401, "read"), null);
  assert.equal(parseAccess(500, { message: "boom" }), null);
  assert.equal(parseAccess(200, { error: "x" }), null);
});

test("covers are never cached and never sniffed", () => {
  assert.match(PRIVATE_HEADERS["Cache-Control"], /private/);
  assert.match(PRIVATE_HEADERS["Cache-Control"], /no-store/);
  assert.equal(PRIVATE_HEADERS["X-Content-Type-Options"], "nosniff");
});

test("only JPEG bytes are served", () => {
  assert.ok(isJpeg(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0])));
  assert.ok(!isJpeg(new Uint8Array([0x89, 0x50, 0x4e, 0x47])));
  assert.ok(!isJpeg(new Uint8Array([])));
});
