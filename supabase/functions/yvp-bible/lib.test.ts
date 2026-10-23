// Tests for lib.ts. Run with Node 22+:
//   node --experimental-strip-types --test supabase/functions/yvp-bible/lib.test.ts
// The chapters below are shaped exactly like the YouVersion Platform's
// format=html&include_headings=true responses (checked October 2026).
import assert from "node:assert/strict";
import { test } from "node:test";
import { ageSeconds, BOOKS, cachePolicy, chapterCount, clean, isFresh, parseChapter, parseRequest, placeMarks, verseNumbers } from "./lib.ts";

test("reads a request", () => {
  assert.deepEqual(parseRequest({ id: "NIV", book: "GEN" }), { id: "NIV", book: "GEN" });
  assert.deepEqual(parseRequest({ id: "NASB2020", book: "1JN" }), { id: "NASB2020", book: "1JN" });
  assert.deepEqual(parseRequest({ id: "NIrV", book: "GEN" }), { id: "NIrV", book: "GEN" });
  assert.equal(parseRequest({ id: "N-V", book: "GEN" }), null);
  assert.equal(parseRequest({ id: "NIV", book: "TOB" }), null);
  assert.equal(parseRequest({ id: "NIV" }), null);
  assert.equal(parseRequest(null), null);
  // One chapter (the app refreshing what it shows), up to one past the KJV's count.
  assert.deepEqual(parseRequest({ id: "NIV", book: "JHN", chapter: 3 }), { id: "NIV", book: "JHN", chapter: 3 });
  assert.deepEqual(parseRequest({ id: "NIV", book: "JHN", chapter: 22 }), { id: "NIV", book: "JHN", chapter: 22 });
  assert.equal(parseRequest({ id: "NIV", book: "JHN", chapter: 23 }), null);
  assert.equal(parseRequest({ id: "NIV", book: "JHN", chapter: 0 }), null);
  assert.equal(parseRequest({ id: "NIV", book: "JHN", chapter: "3" }), null);
});

test("knows the 66 books", () => {
  assert.equal(BOOKS.length, 66);
  assert.equal(chapterCount("PSA"), 150);
  assert.equal(chapterCount("JUD"), 1);
  assert.equal(chapterCount("REV"), 22);
  assert.equal(BOOKS.reduce((sum, [, n]) => sum + n, 0), 1189);
});

test("reads verse numbers", () => {
  assert.deepEqual(verseNumbers("16"), [16, 16]);
  assert.deepEqual(verseNumbers("16-17"), [16, 17]);
  assert.deepEqual(verseNumbers("[37]"), [37, 37]);
  assert.equal(verseNumbers(""), null);
});

test("cleans whitespace only", () => {
  assert.equal(clean("  In the   beginning God \n\n  created  "), "In the beginning God\ncreated");
});

const PSALM_3 =
  '<div><div class="cl yv-h">Psalm 3</div><div class="d">A psalm of David. When he fled from his son Absalom.</div>' +
  '<div class="q1"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span> <span class="nd">Lord</span>, how many are my foes!</div>' +
  '<div class="q2">How many rise up against me!</div>' +
  '<div class="q1"><span class="yv-v" v="2"></span><span class="yv-vlbl">2</span>Many are saying of me,</div>' +
  '<div class="q2">“God will not deliver him.”</div>' +
  '<div class="q1"><span class="yv-v" v="7"></span><span class="yv-vlbl">7</span>Arise, <span class="nd">Lord</span>!</div>' +
  '<div class="q2">Deliver me, my God!</div><div class="q1">Strike all my enemies on the jaw;</div>' +
  '<div class="q2">break the teeth of the wicked.</div></div>';

test("poetry: lines, the divine name, the psalm title kept and the chapter label left out", () => {
  const chapter = parseChapter(3, PSALM_3, "Psalms 3");
  assert.deepEqual(chapter.headings, [{ beforeVerse: 1, text: "A psalm of David. When he fled from his son Absalom." }]);
  assert.deepEqual(chapter.verses[0], {
    verse: 1,
    text: "LORD, how many are my foes!\nHow many rise up against me!",
    paragraph: true,
    poetry: true,
  });
  assert.equal(chapter.verses[1].text, "Many are saying of me,\n“God will not deliver him.”");
  assert.equal(chapter.verses[2].text, "Arise, LORD!\nDeliver me, my God!\nStrike all my enemies on the jaw;\nbreak the teeth of the wicked.");
  // Verse labels never become text.
  assert.ok(chapter.verses.every((v) => !/^\d/.test(v.text)));
});

const ACTS_8 =
  '<div><div class="p"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span>And Saul approved of their killing him.</div>' +
  '<div class="s1 yv-h">The Church Persecuted and Scattered</div>' +
  '<div class="p">On that day a great persecution broke out. <span class="yv-v" v="2"></span><span class="yv-vlbl">2</span>Godly men buried Stephen.</div>' +
  '<div class="p"><span class="yv-v" v="36"></span><span class="yv-vlbl">36</span>“Look, here is water.” <span class="yv-v" v="37"></span><span class="yv-vlbl">[37]</span> ' +
  '<span class="yv-v" v="38"></span><span class="yv-vlbl">38</span>And he gave orders to stop the chariot.</div></div>';

test("prose: a verse runs on past a heading, the heading waits for the next verse, empty verses are left out", () => {
  const chapter = parseChapter(8, ACTS_8, "Acts 8");
  assert.deepEqual(
    chapter.verses.map((v) => [v.verse, v.text, v.paragraph, v.poetry]),
    [
      [1, "And Saul approved of their killing him. On that day a great persecution broke out.", true, false],
      [2, "Godly men buried Stephen.", false, false],
      [36, "“Look, here is water.”", true, false],
      [38, "And he gave orders to stop the chariot.", false, false],
    ],
  );
  assert.deepEqual(chapter.headings, [{ beforeVerse: 2, text: "The Church Persecuted and Scattered" }]);
});

const RUTH_1 =
  '<div><div class="s yv-h"><span class="it">Naomi Widowed</span></div>' +
  '<div class="p"><span class="yv-v" v="2"></span><span class="yv-vlbl">2</span>The name of the man <span class="it">was</span> Elimelech.</div>' +
  '<div class="p"><span class="yv-v" v="6"></span><span class="yv-vlbl">6</span>She had heard that the L<span class="sc">ord</span> had visited His people.</div></div>';

test("supplied words keep their words; small-capital LORD is written in capitals", () => {
  const chapter = parseChapter(1, RUTH_1, "Ruth 1");
  assert.equal(chapter.verses[0].text, "The name of the man was Elimelech.");
  assert.equal(chapter.verses[1].text, "She had heard that the LORD had visited His people.");
  assert.deepEqual(chapter.headings, [{ beforeVerse: 2, text: "Naomi Widowed" }]);
});

const SALMO_23 =
  '<div><div class="ms2 yv-h">Salmo 23</div><div class="s yv-h"><span class="it">El S<span class="sc"><span class="it">eñor</span></span> es mi pastor</span></div>' +
  '<div class="d">Salmo de David.</div>' +
  '<div class="q"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span>El S<span class="sc">eñor</span> es mi pastor,</div>' +
  '<div class="q">nada me faltará.</div>' +
  '<div class="q"><span class="yv-v" v="4"></span><span class="yv-vlbl">4</span>¶Aunque pase por el valle de sombra de muerte,</div></div>';

test("Spanish: SEÑOR in capitals, headings in order, a heading that only repeats the chapter is left out", () => {
  const chapter = parseChapter(23, SALMO_23, "Salmo 23");
  assert.deepEqual(chapter.headings, [
    { beforeVerse: 1, text: "El SEÑOR es mi pastor" },
    { beforeVerse: 1, text: "Salmo de David." },
  ]);
  assert.equal(chapter.verses[0].text, "El SEÑOR es mi pastor,\nnada me faltará.");
  // The text is kept exactly, even its own marks.
  assert.equal(chapter.verses[1].text, "¶Aunque pase por el valle de sombra de muerte,");
});

test("bridged verses stay on their first verse", () => {
  const html =
    '<div><div class="p"><span class="yv-v" v="16-17"></span><span class="yv-vlbl">16-17</span>Both verses in one.</div>' +
    '<div class="p"><span class="yv-v" v="18"></span><span class="yv-vlbl">18-19</span>Bridged by its label.</div></div>';
  const chapter = parseChapter(5, html);
  assert.deepEqual(chapter.verses.map((v) => [v.verse, v.last]), [[16, 17], [18, 19]]);
});

test("entities are decoded; notes and verse labels are never text", () => {
  const html =
    '<div><div class="p"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span>Faith &amp; hope&#8212;love<span class="yv-n f"><span class="ft">Or charity</span></span>.</div></div>';
  assert.equal(parseChapter(1, html).verses[0].text, "Faith & hope—love.");
});

test("words before the first verse join it", () => {
  const html = '<div><div class="p">Then</div><div class="p"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span>it began.</div></div>';
  assert.equal(parseChapter(1, html).verses[0].text, "Then it began.");
});

test("follows Cache-Control the way a shared cache must", () => {
  // What the Platform sends today (checked 23 October 2026).
  assert.deepEqual(cachePolicy("public, max-age=3600"), { store: true, maxAge: 3600 });
  assert.deepEqual(cachePolicy("max-age=600, s-maxage=120"), { store: true, maxAge: 120 });
  assert.deepEqual(cachePolicy("private, max-age=3600"), { store: false, maxAge: 0 });
  assert.deepEqual(cachePolicy("no-store"), { store: false, maxAge: 0 });
  assert.deepEqual(cachePolicy("no-cache, max-age=60"), { store: false, maxAge: 0 });
  assert.deepEqual(cachePolicy("public"), { store: false, maxAge: 0 });
  assert.deepEqual(cachePolicy("max-age=0"), { store: false, maxAge: 0 });
  assert.deepEqual(cachePolicy(null), { store: false, maxAge: 0 });
  assert.equal(ageSeconds("12"), 12);
  assert.equal(ageSeconds(null), 0);
  assert.equal(ageSeconds("soon"), 0);
});

test("a stored chapter is fresh only within its lifetime, counting the Age it arrived with", () => {
  const fetchedAt = Date.parse("2026-10-23T15:00:00Z");
  const entry = { fetchedAt, maxAge: 3600, ageAtFetch: 0 };
  assert.equal(isFresh(entry, fetchedAt + 59 * 60_000), true);
  assert.equal(isFresh(entry, fetchedAt + 60 * 60_000), false);
  // Arrived already 10 minutes old: 50 minutes left.
  const older = { fetchedAt, maxAge: 3600, ageAtFetch: 600 };
  assert.equal(isFresh(older, fetchedAt + 49 * 60_000), true);
  assert.equal(isFresh(older, fetchedAt + 51 * 60_000), false);
});

// Footnotes, shaped like the Platform's include_notes=true markup (checked
// 23 October 2026 with the NIV, John 1, and the NASB 2020, Matthew 1).
const withNotes =
  '<div><div class="s yv-h"><span class="it">The Genealogy</span><span class="yv-n f"><span class="fr">1:1 </span><span class="ft">Heading note</span></span></div>' +
  '<div class="p"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span>The <span class="yv-n f"><span class="fr">1:1 </span><span class="ft">Lit <span class="it">book</span></span></span>record of Jesus the <span class="yv-n f"><span class="fr">1:1 </span><span class="ft">The L<span class="sc">ord</span> is salvation</span></span>Messiah. ' +
  '<span class="yv-v" v="2"></span><span class="yv-vlbl">2</span>The darkness has not overcome<span class="yv-n f"><span class="fr">1:2 </span><span class="ft">Or </span><span class="fqa">understood</span></span> it. ' +
  '<span class="yv-v" v="3"></span><span class="yv-vlbl">3</span>Spaces <span class="yv-n f"><span class="ft">between</span></span> both.</div></div>';
const withoutNotes = withNotes.replace(/<span class="yv-n f">(<span[^>]*>(<span[^>]*>[^<]*<\/span>|[^<])*<\/span>)*<\/span>/g, "");

test("footnotes are kept apart: the verse text is exactly the text without them", () => {
  const noted = parseChapter(1, withNotes);
  const plain = parseChapter(1, withoutNotes);
  assert.deepEqual(noted.verses, plain.verses);
  assert.deepEqual(noted.headings, plain.headings);
  assert.deepEqual(plain.notes, []);
  assert.equal(noted.verses[0].text, "The record of Jesus the Messiah.");
});

test("each footnote sits where its marker was, with its own words verbatim", () => {
  const { verses, notes } = parseChapter(1, withNotes);
  const at = (verse: number, offset: number) => verses.find((v) => v.verse === verse)!.text.slice(offset);
  assert.deepEqual(notes.map((n) => [n.verse, n.offset, n.text]), [
    [1, 0, "Heading note"],                        // a heading's note: at the start of the next verse
    [1, 4, "Lit book"],                            // before the word (Lockman's style)
    [1, 24, "The LORD is salvation"],              // small capitals as capitals, as in verses
    [2, 29, "Or understood"],                      // after the word (Biblica's style); the "1:2 " label left out
    [3, 7, "between"],                             // between two spaces: one space stays
  ]);
  assert.ok(at(1, 4).startsWith("record"));
  assert.ok(at(1, 24).startsWith("Messiah"));
  assert.ok(at(2, 29).startsWith(" it."));
  assert.ok(at(3, 7).startsWith("both."));
});

test("marks take no room and never change the text", () => {
  const mark = (n: number) => String.fromCharCode(0xe000 + n);
  assert.deepEqual(placeMarks(`  a${mark(0)}  b `), { text: "a b", marks: [{ mark: 0, offset: 1 }] });
  assert.deepEqual(placeMarks(`a ${mark(0)} b`), { text: "a b", marks: [{ mark: 0, offset: 2 }] });
  assert.deepEqual(placeMarks(`line one${mark(1)}\n  ${mark(2)}line two`), {
    text: "line one\nline two",
    marks: [{ mark: 1, offset: 8 }, { mark: 2, offset: 9 }],
  });
  assert.deepEqual(placeMarks(`a\n${mark(0)}\nb`), { text: "a\nb", marks: [{ mark: 0, offset: 1 }] });
});
