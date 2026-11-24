import { test } from "node:test";
import assert from "node:assert/strict";
import { chaptersFor, defaultBible, labelNames, noteLetter, ownRange, shownBible, startingBible, versesFor, withMarkers, type ChapterFile } from "./scripture.ts";

const file = (chapter: number, verses: ChapterFile["verses"]): ChapterFile => ({
  format: 1, translation: "RV1909", name: "Reina-Valera 1909", language: "es", license: "Dominio público", book: 4, chapter, verses,
});

test("the quoted Bible wins, else the outline's language picks a free one", () => {
  assert.equal(defaultBible("KJV", "es"), "KJV");
  assert.equal(defaultBible(null, "es"), "RV1909");
  assert.equal(defaultBible(null, "pt"), "BLIVRE");
  assert.equal(defaultBible(null, "other"), "WEB");
});

test("a KJV range across chapters asks for each chapter", () => {
  assert.deepEqual(chaptersFor(43003016, 43004002), [{ book: 43, chapter: 3 }, { book: 43, chapter: 4 }]);
  assert.deepEqual(chaptersFor(43003016, 43003016), [{ book: 43, chapter: 3 }]);
});

test("verses come in the Bible's own numbering, each once (Numbers 12:16 is the Reina-Valera's 13:1)", () => {
  const twelve = file(12, [
    { c: 12, v: 15, k: [4012015], t: "Así María…" },
    { c: 13, v: 1, k: [4012016], t: "Y DESPUÉS…" },
  ]);
  const thirteen = file(13, [
    { c: 13, v: 1, k: [], t: "never shown twice" },
    { c: 13, v: 2, k: [4013001], t: "Y Jehová habló…" },
  ]);
  const verses = versesFor([twelve, thirteen], 4012015, 4013001);
  assert.deepEqual(verses.map((v) => `${v.c}:${v.v}`), ["12:15", "13:1", "13:2"]);
  assert.equal(verses[1].t, "Y DESPUÉS…");
  assert.equal(ownRange(verses), "12:15–13:2");
  assert.equal(ownRange([verses[1]]), "13:1");
  assert.equal(ownRange([]), "");
});

test("a YouVersion Bible the pastor named opens first, when the page offers it", () => {
  const yv = [{ id: "NIV", name: "New International Version", language: "en" }, { id: "NIrV", name: "NIrV", language: "en" }];
  assert.equal(startingBible(null, "NIV", "en", yv), "NIV");
  assert.equal(startingBible(null, "nirv", "en", yv), "NIrV");
  assert.equal(startingBible(null, "NIV", "en", []), "WEB");
  assert.equal(startingBible("KJV", "KJV", "en", yv), "KJV");
  assert.equal(startingBible(null, "ESV", "es", yv), "RV1909");
});

test("footnote markers go where the notes say, the words untouched", () => {
  const verse = { c: 1, v: 1, k: [1001001], t: "In the beginning God created", n: [{ o: 28, t: "b" }, { o: 16, t: "a" }] };
  const parts = withMarkers(verse);
  assert.deepEqual(parts, ["In the beginning", 1, " God created", 0]);
  assert.equal(parts.filter((x) => typeof x === "string").join(""), verse.t);
  assert.deepEqual(withMarkers({ c: 1, v: 2, k: [], t: "Plain" }), ["Plain"]);
  assert.equal(noteLetter(0), "a");
  assert.equal(noteLetter(25), "z");
  assert.equal(noteLetter(26), "aa");
});

test("the reader's Bible applies to every passage on the page, when the page offers it", () => {
  const yv = [{ id: "NIV", name: "New International Version", language: "en" }];
  // No choice yet: each passage opens in the Bible the pastor named.
  assert.equal(shownBible(null, "WEB", "WEB", "en", yv), "WEB");
  assert.equal(shownBible(null, null, "NIV", "en", yv), "NIV");
  // A choice wins for every passage, whatever its label.
  assert.equal(shownBible("NIV", "WEB", "WEB", "en", yv), "NIV");
  assert.equal(shownBible("KJV", null, "NIV", "en", yv), "KJV");
  // A choice the page doesn't offer (Studio's preview has no YouVersion Bibles) is ignored.
  assert.equal(shownBible("NIV", "WEB", "WEB", "en", []), "WEB");
});

test("the card names the sermon's Bible only when it isn't the one shown", () => {
  assert.equal(labelNames("WEB", "WEB"), true);
  assert.equal(labelNames(" web ", "WEB"), true);
  assert.equal(labelNames("WEB", "NIV"), false);
  assert.equal(labelNames(null, "NIV"), false);
});
