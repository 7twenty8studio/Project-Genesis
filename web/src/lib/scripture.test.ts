import { test } from "node:test";
import assert from "node:assert/strict";
import { chaptersFor, defaultBible, ownRange, versesFor, type ChapterFile } from "./scripture.ts";

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
