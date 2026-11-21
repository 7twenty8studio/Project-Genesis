import assert from "node:assert/strict";
import { test } from "node:test";
import { parsePassageRequest, webVerses } from "./lib.ts";

test("accepts one or two chapters of one book", () => {
  assert.deepEqual(parsePassageRequest({ bible: "NIV", start: 40011028, end: 40011030 }), { bible: "NIV", start: 40011028, end: 40011030, book: "MAT", chapters: [11] });
  assert.deepEqual(parsePassageRequest({ bible: "NIrV", start: 43003016 })?.chapters, [3]);
  assert.deepEqual(parsePassageRequest({ bible: "NASB2020", start: 19022001, end: 19023006 })?.chapters, [22, 23]);
});

test("refuses more than two chapters, two books, backwards ranges and bad ids", () => {
  assert.equal(parsePassageRequest({ bible: "NIV", start: 19022001, end: 19024001 }), null);
  assert.equal(parsePassageRequest({ bible: "NIV", start: 43021025, end: 44001001 }), null);
  assert.equal(parsePassageRequest({ bible: "NIV", start: 43003016, end: 43003015 }), null);
  assert.equal(parsePassageRequest({ bible: "NIV", start: 67001001 }), null);
  assert.equal(parsePassageRequest({ bible: "NIV", start: 43022001 }), null);
  assert.equal(parsePassageRequest({ bible: "N I V", start: 43003016 }), null);
  assert.equal(parsePassageRequest({ bible: "NIV", start: "43003016" }), null);
  assert.equal(parsePassageRequest(null), null);
});

test("keeps the verses in range, word for word, with their notes", () => {
  const chapter = {
    chapter: 11,
    headings: [{ beforeVerse: 28, text: "Rest" }],
    verses: [
      { verse: 27, text: "Before.", paragraph: true, poetry: false },
      { verse: 28, text: "Come to me.", paragraph: true, poetry: false },
      { verse: 29, last: 30, text: "Take my yoke.", paragraph: false, poetry: true },
    ],
    notes: [{ verse: 28, offset: 4, text: "Or come here" }],
  };
  assert.deepEqual(webVerses(40, [chapter], 40011028, 40011029), [
    { c: 11, v: 28, k: [40011028], t: "Come to me.", n: [{ o: 4, t: "Or come here" }] },
    { c: 11, v: 29, k: [40011029, 40011030], t: "Take my yoke.", p: 1 },
  ]);
});
