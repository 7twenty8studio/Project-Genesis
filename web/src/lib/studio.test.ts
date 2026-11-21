import { test } from "node:test";
import assert from "node:assert/strict";
import type { DraftBlock } from "./draft.ts";
import { outlineWords } from "./import/completeness.ts";
import { placeFor, publishableBlocks, publishBlockers } from "./studio.ts";

const scripture = (label: string | null, quote: string | null, status: "verified" | "ambiguous" = "verified"): DraftBlock => ({
  id: "s",
  kind: "scripture",
  ref: { raw: "John 3:16", start: status === "verified" ? 43003016 : null, end: status === "verified" ? 43003016 : null, status, label, quote },
});

test("readers never get quoted words (as genesis_publishable_blocks)", () => {
  const [kjv] = publishableBlocks([scripture("KJV", "For God so loved")]);
  assert.deepEqual(kjv.kind === "scripture" && kjv.ref, { raw: "John 3:16", start: 43003016, end: 43003016, status: "verified", label: "KJV", translation: "KJV", quote_withheld: false });
  const [niv] = publishableBlocks([scripture("NIV", "For God so loved")]);
  assert.equal(niv.kind === "scripture" && niv.ref.translation, null);
  assert.equal(niv.kind === "scripture" && niv.ref.quote_withheld, true);
  assert.ok(!("quote" in (niv.kind === "scripture" ? niv.ref : {})));
  const [unverified] = publishableBlocks([scripture("KJV", "words", "ambiguous")]);
  assert.equal(unverified.kind === "scripture" && unverified.ref.quote_withheld, true);
  const [bare] = publishableBlocks([scripture(null, null)]);
  assert.equal(bare.kind === "scripture" && bare.ref.quote_withheld, false);
});

test("Publish stays off until the title, cover description and review are done", () => {
  const row = { title: "", cover_id: "c", cover_alt: "", cover_decorative: false, draft_blocks: [] as DraftBlock[] };
  assert.deepEqual(publishBlockers(row, null, true), ["needs_title", "empty_outline", "needs_cover_alt", "saving"]);
  const ready = { ...row, title: "Hope", cover_decorative: true, draft_blocks: [{ id: "p", kind: "paragraph", text: "Hi" } as DraftBlock] };
  assert.deepEqual(publishBlockers(ready, null), []);
  const review = { items: [{ key: "note:tables", kind: "note" as const, note: { kind: "tables" as const, count: 1 } }], decisions: {} };
  assert.deepEqual(publishBlockers(ready, review), ["review_open"]);
  assert.deepEqual(publishBlockers(ready, { ...review, decisions: { "note:tables": "kept" as const } }), []);
});

test("words added back go after the words that came before them", () => {
  const blocks: DraftBlock[] = [
    { id: "a", kind: "paragraph", text: "Grace and" },
    { id: "b", kind: "paragraph", text: "Truth endures" },
  ];
  const words = (b: DraftBlock) => outlineWords([b]);
  assert.equal(placeFor(blocks, ["Grace", "and"], words), 1);
  assert.equal(placeFor(blocks, [], words), 0);
  assert.equal(placeFor(blocks, ["nowhere"], words), 2);
});

test("covers fit within 2000 px on the long side and never grow", async () => {
  const { fitWithin } = await import("./coverImage.ts");
  assert.deepEqual(fitWithin(4032, 3024), { width: 2000, height: 1500 });
  assert.deepEqual(fitWithin(1200, 3000), { width: 800, height: 2000 });
  assert.deepEqual(fitWithin(640, 480), { width: 640, height: 480 });
});
