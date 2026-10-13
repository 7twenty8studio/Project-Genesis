// Tests for lib.ts. Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/bible-file/lib.test.ts
import assert from "node:assert/strict";
import { test } from "node:test";
import { bearerToken, licensedObjectPath, parseRequest } from "./lib.ts";

test("reads a catalog id", () => {
  assert.deepEqual(parseRequest({ id: "NIV" }), { id: "NIV" });
  assert.deepEqual(parseRequest({ id: "RVR1960" }), { id: "RVR1960" });
  assert.equal(parseRequest({ id: "niv" }), null);
  assert.equal(parseRequest({ id: "TOOLONGID" }), null);
  assert.equal(parseRequest({}), null);
  assert.equal(parseRequest(null), null);
  assert.deepEqual(parseRequest({ id: "NIV", signedTransaction: "eyJ.a.b" }), { id: "NIV", signedTransaction: "eyJ.a.b" });
  assert.deepEqual(parseRequest({ id: "NIV", signedTransaction: 5 }), { id: "NIV" });
  assert.deepEqual(parseRequest({ id: "NIV", signedTransaction: "" }), { id: "NIV" });
});

test("reads the bearer token", () => {
  assert.equal(bearerToken("Bearer abc.def"), "abc.def");
  assert.equal(bearerToken("bearer  xyz"), "xyz");
  assert.equal(bearerToken(null), "");
});

test("signs only files in the licensed bucket", () => {
  const base = "https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object";
  assert.equal(licensedObjectPath(`${base}/licensed-bibles/NIV-1.sqlite.deflate`), "NIV-1.sqlite.deflate");
  assert.equal(licensedObjectPath(`${base}/public/bibles/BSB-1.sqlite.deflate`), null);
  assert.equal(licensedObjectPath(`${base}/licensed-bibles/../attachments/x.sqlite.deflate`), null);
  assert.equal(licensedObjectPath(`${base}/licensed-bibles/sub/NIV.sqlite.deflate`), null);
  assert.equal(licensedObjectPath(`${base}/licensed-bibles/NIV-1.pdf`), null);
  assert.equal(licensedObjectPath(`http://example.com/storage/v1/object/licensed-bibles/NIV-1.sqlite.deflate`), null);
  assert.equal(licensedObjectPath("not a url"), null);
});
