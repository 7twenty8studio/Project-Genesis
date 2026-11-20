import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import fixtures from "./fixtures/references.json" with { type: "json" };
import { books, booksMatching, describe, isValidVerseID, parse, resolve } from "./references.ts";

test("parses every shared case as the app does", () => {
  for (const c of fixtures.parse) {
    const ref = parse(c.input);
    assert.ok(ref, c.input);
    assert.equal(ref.book.id, c.book, c.input);
    assert.equal(ref.chapter, c.chapter, c.input);
    assert.equal(ref.verseStart, c.verse, c.input);
    assert.equal(ref.verseEnd, (c as { end?: number }).end ?? null, c.input);
  }
});

test("Portuguese abbreviations win on a Portuguese page", () => {
  for (const c of fixtures.portugueseFirst) {
    assert.equal(parse(c.input, { portugueseFirst: true })?.book.id, c.book, c.input);
  }
  assert.equal(parse("Mc 4")?.book.id, 33);
});

test("rejects what isn't a reference", () => {
  for (const input of fixtures.rejects) assert.equal(parse(input), null, input);
});

test("resolves sermon references to verse ids", () => {
  for (const c of fixtures.resolve) {
    const r = resolve(c.input);
    assert.deepEqual({ status: r.status, start: r.start, end: r.end }, { status: c.status, start: c.start, end: c.end }, c.input);
    assert.equal(r.raw, c.input.trim());
  }
});

test("names passages as the app does", () => {
  for (const c of fixtures.describe) assert.equal(describe(c.start, c.end, c.language), c.text);
});

test("book suggestions while typing", () => {
  assert.ok(booksMatching("phil").map((b) => b.id).includes(50));
  assert.equal(booksMatching("joh")[0]?.id, 43);
  assert.deepEqual(booksMatching("John 3"), []);
  assert.deepEqual(booksMatching("Apoc").map((b) => b.id), [66]);
});

test("verse ids follow the KJV's numbering", () => {
  assert.ok(isValidVerseID(19119176));
  assert.ok(!isValidVerseID(19119177));
  assert.ok(!isValidVerseID(43000001));
  assert.ok(!isValidVerseID(67001001));
  assert.equal(books.length, 66);
  assert.equal(books.reduce((n, b) => n + b.verses.length, 0), 1189);
});

test("bibleBooks.json matches BibleBook.swift and the KJV", () => {
  const script = fileURLToPath(new URL("../../../Tools/BibleData/export_reference_books.py", import.meta.url));
  execFileSync("python3", [script, "--check"], { stdio: "pipe" });
});

test("the church sermons migration checks verses against the same counts", async () => {
  const { readFile } = await import("node:fs/promises");
  const sql = await readFile(new URL("../../migrations/20261120000000_church_sermons.sql", import.meta.url), "utf8");
  const rows = [...sql.matchAll(/^\s*\((\d+), array\[([\d,]+)\]\)/gm)].map((m) => [Number(m[1]), m[2].split(",").map(Number)]);
  assert.deepEqual(rows, books.map((b) => [b.id, b.verses]));
});
