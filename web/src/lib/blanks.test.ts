import { test } from "node:test";
import assert from "node:assert/strict";
import {
  blankProblems,
  draftBlanks,
  importBlanks,
  isCorrect,
  makeBlank,
  numberBlanks,
  pieces,
  setBlank,
  withBlanks,
} from "./blanks.ts";
import type { DraftBlock } from "./draft.ts";

test("draft blanks: answers, hints, open and waiting", () => {
  const found = draftBlanks("Gratitude Starts with [[Seeing]] God the [[Giver|G]], then [[...]] and [[ ]] and [[…|your words]].");
  assert.deepEqual(
    found.map((b) => [b.answer, b.hint]),
    [["Seeing", null], ["Giver", "G"], [null, null], ["", null], [null, "your words"]],
  );
  // Brackets or line breaks inside are words, not a blank.
  assert.equal(draftBlanks("a [[x\ny]] b").length, 0);
  assert.equal(draftBlanks("a [[ no close").length, 0);
  assert.deepEqual(draftBlanks("[[[a]]").map((b) => b.answer), ["a"]);
});

test("Make Blank wraps the selection and keeps the spaces around it", () => {
  const text = "Gratitude starts with seeing God";
  const s = text.indexOf("seeing");
  assert.equal(makeBlank(text, s - 1, s + "seeing".length + 1), "Gratitude starts with [[seeing]] God");
  assert.equal(makeBlank(text, text.length, text.length), "Gratitude starts with seeing God[[]]");
  // Not across an existing blank.
  const once = makeBlank(text, s, s + 6);
  assert.equal(makeBlank(once, 0, once.length), once);
});

test("editing and removing a blank", () => {
  const text = "God the [[Giver]] and [[...]]";
  assert.equal(setBlank(text, 0, { answer: "Giver", hint: "G" }), "God the [[Giver|G]] and [[...]]");
  assert.equal(setBlank(text, 1, { answer: "Thanks", hint: null }), "God the [[Giver]] and [[Thanks]]");
  assert.equal(setBlank(text, 0, null), "God the Giver and [[...]]");
  assert.equal(setBlank(text, 0, { answer: "a]]b|c", hint: null }), "God the [[a  b c]] and [[...]]");
});

test("an imported handout's blank lines wait for answers; Scripture and quotations stay as written", () => {
  const blocks: DraftBlock[] = [
    { id: "h", kind: "heading", text: "1. Gratitude Starts with ______ God the _____", level: 2 },
    { id: "l", kind: "list", items: ["Thanks __", "Praise ____"], ordered: false },
    { id: "q", kind: "quote", text: "a ____ b" },
    { id: "s", kind: "scripture", ref: { raw: "Luke 17:15", start: 42017015, end: null, status: "verified", label: "NLT", quote: "One of them ____" } },
  ];
  const out = importBlanks(blocks);
  assert.deepEqual(out[0], { ...blocks[0], text: "1. Gratitude Starts with [[]] God the [[]]" });
  assert.deepEqual(out[1], { ...blocks[1], items: ["Thanks __", "Praise [[]]"] });
  assert.deepEqual(out[2], blocks[2]);
  assert.deepEqual(out[3], blocks[3]);
  assert.deepEqual(blankProblems(out).map((p) => [p.blockId, p.problem]), [["h", "blank_needs_answer"], ["l", "blank_needs_answer"]]);
});

test("blank problems: quotations, length, count", () => {
  assert.deepEqual(blankProblems([{ id: "q", kind: "quote", text: "x [[y]]" }]), [{ blockId: "q", problem: "blank_in_quotation" }]);
  assert.deepEqual(blankProblems([{ id: "p", kind: "paragraph", text: `[[${"a".repeat(101)}]]` }]), [{ blockId: "p", problem: "blank_too_long" }]);
  assert.deepEqual(blankProblems([{ id: "p", kind: "paragraph", text: "[[a]]".repeat(101) }]), [{ problem: "too_many_blanks" }]);
  assert.deepEqual(blankProblems([{ id: "p", kind: "paragraph", text: "[[a]] [[...]]" }]), []);
});

test("publishing numbers blanks through the outline and keeps the key apart", () => {
  const { blocks, blanks } = numberBlanks<DraftBlock>([
    { id: "h", kind: "heading", text: "Starts with [[Seeing]]", level: 2 },
    { id: "q", kind: "quote", text: "stays [[x]]" },
    { id: "l", kind: "list", items: ["[[Giver|G]] and [[...]]"], ordered: true },
  ]);
  assert.deepEqual(blocks.map((b) => (b.kind === "list" ? b.items : b.kind === "scripture" ? [] : [b.text])), [["Starts with [[1]]"], ["stays [[x]]"], ["[[2]] and [[3]]"]]);
  assert.deepEqual(blanks, [
    { n: 1, answer: "Seeing", hint: null },
    { n: 2, answer: "Giver", hint: "G" },
    { n: 3, answer: null, hint: null },
  ]);
});

test("readers split text at known markers only", () => {
  const known = (n: number) => n === 1 || n === 2;
  assert.deepEqual(pieces("God the [[1]], [[9]] and [[2]]", known), [
    { kind: "text", text: "God the " },
    { kind: "blank", n: 1 },
    { kind: "text", text: ", [[9]] and " },
    { kind: "blank", n: 2 },
  ]);
  assert.equal(withBlanks("God the [[1]]", known), "God the _____");
  assert.equal(withBlanks("God the [[1]]", known, () => "Giver"), "God the Giver");
});

test("answers compare without case, accents, spacing or punctuation around them", () => {
  assert.ok(isCorrect("  seeing ", "Seeing"));
  assert.ok(isCorrect("Gracias.", "gracias"));
  assert.ok(isCorrect("acción  de gracias", "Accion de Gracias"));
  assert.ok(isCorrect("God’s", "God's"));
  assert.ok(!isCorrect("", "Seeing"));
  assert.ok(!isCorrect("Seen", "Seeing"));
});
