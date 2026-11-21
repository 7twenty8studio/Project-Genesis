import { test } from "node:test";
import assert from "node:assert/strict";
import { anchorFor, copyText, sections, type Block } from "./outline.ts";

const blocks: Block[] = [
  { id: "a", kind: "paragraph", text: "Welcome." },
  { id: "h1", kind: "heading", text: "Rest", level: 2 },
  { id: "s", kind: "scripture", ref: { raw: "Sl 23", start: 19023001, end: 19023006, status: "verified", label: "NVI", translation: null, quote_withheld: true } },
  { id: "l", kind: "list", items: ["Lie down", "Be led"], ordered: true },
  { id: "h2", kind: "heading", text: "Goodness", level: 2 },
  { id: "q", kind: "quote", text: "Surely" },
];

test("sections split at headings, with an untitled opening", () => {
  const s = sections(blocks);
  assert.deepEqual(s.map((x) => [x.id, x.title, x.blocks.length]), [["start", null, 1], ["h1", "Rest", 3], ["h2", "Goodness", 2]]);
  assert.equal(anchorFor(s[0]), "top");
  assert.equal(anchorFor(s[1]), "s-h1");
});

test("Copy gives the church's words exactly, references as typed, never verse text", () => {
  assert.equal(copyText(sections(blocks)[1].blocks), "Rest\n\nSl 23 (NVI)\n\n1. Lie down\n2. Be led");
  assert.equal(copyText([blocks[5]]), "“Surely”");
  assert.equal(copyText([{ id: "u", kind: "list", items: ["x"], ordered: false }]), "• x");
});
