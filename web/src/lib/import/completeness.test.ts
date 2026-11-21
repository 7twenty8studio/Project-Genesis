import { test } from "node:test";
import assert from "node:assert/strict";
import { missingRuns, outlineWords, sourceWords, words } from "./completeness.ts";
import { importText } from "./paste.ts";
import { reviewDone, reviewItems, stillOpen } from "./review.ts";

test("words keep accents, case, digits and inner apostrophes; punctuation goes", () => {
  assert.deepEqual(words("¡Él vive! God's love—1 Cor. 13:4"), ["Él", "vive", "God's", "love", "1", "Cor", "13", "4"]);
  assert.deepEqual(words("é"), ["é"]);
});

test("an import of pasted text loses nothing", () => {
  const text = "# Hope\n\n- One\n- Two\n\nRomans 5:5 (KJV)\n\n> And hope maketh not ashamed\n\nThe end.";
  const result = importText(text, { language: "en" });
  assert.deepEqual(missingRuns(sourceWords(result.source), outlineWords(result.blocks)), []);
});

test("a dropped word is listed with the words around it, even when another word is added", () => {
  const source = words("the Lord is my shepherd I shall not want");
  const outline = words("the Lord is my good shepherd I shall want");
  assert.deepEqual(missingRuns(source, outline, 2), [{ words: ["not"], before: ["I", "shall"], after: ["want"], at: 7 }]);
});

test("a change of spelling or accent counts as missing", () => {
  assert.equal(missingRuns(words("Señor"), words("Senor")).length, 1);
  assert.equal(missingRuns(words("Lord"), words("lord")).length, 1);
});

test("long sources are compared in windows and still find the gap", () => {
  const source = Array.from({ length: 7000 }, (_, i) => `w${i}`);
  const outline = source.filter((_, i) => i !== 4500);
  const runs = missingRuns(source, outline);
  assert.deepEqual(runs.map((r) => r.words), [["w4500"]]);
});

test("the review list needs an answer for every finding before Publish", () => {
  const blocks = [
    { id: "b1", kind: "paragraph" as const, text: "Grace and peace" },
    { id: "b2", kind: "scripture" as const, ref: { raw: "Jo 1:1", start: 43001001, end: 43001001, status: "ambiguous" as const, label: null, quote: null } },
  ];
  const items = reviewItems("Grace and much peace\nJo 1:1", blocks, [{ kind: "tables", count: 1 }]);
  assert.deepEqual(items.map((i) => i.key), ["missing:2", "note:tables", "note:comments", "reference:b2"]);
  assert.equal(reviewDone(items, {}), false);
  assert.equal(reviewDone(items, { "missing:2": "dismissed", "note:tables": "kept" }), false);
  assert.equal(reviewDone(items, { "missing:2": "dismissed", "note:tables": "kept", "reference:b2": "fixed" }), true);
  const fixed = [blocks[0], { ...blocks[1], ref: { ...blocks[1].ref, status: "verified" as const } }];
  assert.deepEqual(stillOpen(items, fixed).map((i) => i.key), ["missing:2", "note:tables", "note:comments"]);
});
