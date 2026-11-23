// Fill-in-the-blank handouts (owner-approved plan, 22 November 2026).
//
// In the draft, a blank is written inside the pastor's own words (headings,
// paragraphs and list items; never Scripture or a quotation) as
//   [[Thanking]]          a blank whose answer is "Thanking"
//   [[Thanking|T]]        ...with a hint shown under it
//   [[...]]  or [[…]]     an open blank: the member's own words, never checked
//   [[]]                  a blank still waiting for its answer (Publish says so)
// Publishing (publish_church_sermon, genesis_sermon_blanks) numbers them in
// order through the outline, writes "[[1]]", "[[2]]"… in their place, and
// keeps the answers apart in the revision's `blanks`. published_sermon gives
// readers each blank's number, hint and whether it's open, and its answer
// only once the key is revealed for that revision. These functions are the
// same rules for Studio's editor and preview, and for readers.

import type { DraftBlock } from "./draft.ts";

export const BLANK_LIMITS = { blanks: 100, answer: 100, hint: 60 };

/** One blank as the draft writes it. */
export interface DraftBlank {
  /** Where it sits in the text: "[[" up to and including "]]". */
  start: number;
  end: number;
  /** The answer, "" while it's still missing; null for an open blank. */
  answer: string | null;
  hint: string | null;
}

/** A blank as readers get it (published_sermon `blanks`). */
export interface PublishedBlank {
  n: number;
  open: boolean;
  hint: string | null;
  /** Only once the pastor has revealed the key for this revision. */
  answer?: string | null;
}

/** "reveal": after the pastor reveals them (the default); "now": right away; "never": no key, nothing checked. */
export type AnswersMode = "reveal" | "now" | "never";
/** What readers can do with the key now. */
export type AnswersState = "hidden" | "revealed" | "never";

const OPEN = new Set(["...", "…"]);

/** Every "[[…]]" in a piece of the pastor's text, in order. Content has no brackets or line breaks. */
export function draftBlanks(text: string): DraftBlank[] {
  const out: DraftBlank[] = [];
  let from = 0;
  for (;;) {
    const start = text.indexOf("[[", from);
    if (start < 0) break;
    const close = text.indexOf("]]", start + 2);
    if (close < 0) break;
    const inner = text.slice(start + 2, close);
    if (/[[\]\n\r]/.test(inner)) {
      from = start + 1;
      continue;
    }
    const bar = inner.indexOf("|");
    const answerPart = (bar < 0 ? inner : inner.slice(0, bar)).trim();
    const hint = bar < 0 ? null : inner.slice(bar + 1).trim() || null;
    out.push({ start, end: close + 2, answer: OPEN.has(answerPart) ? null : answerPart, hint });
    from = close + 2;
  }
  return out;
}

/** The markup for one blank. */
export function blankMarkup(answer: string | null, hint: string | null): string {
  const a = answer === null ? "..." : answer.replace(/[[\]|\n\r]/g, " ").trim();
  const h = hint ? hint.replace(/[[\]|\n\r]/g, " ").trim() : "";
  return `[[${a}${h ? `|${h}` : ""}]]`;
}

/** Replaces the blank at `index` in `text` (null removes it, keeping its answer as words). */
export function setBlank(text: string, index: number, next: { answer: string | null; hint: string | null } | null): string {
  const b = draftBlanks(text)[index];
  if (!b) return text;
  const replacement = next ? blankMarkup(next.answer, next.hint) : (b.answer ?? "");
  return text.slice(0, b.start) + replacement + text.slice(b.end);
}

/** Wraps text[start, end) in a blank whose answer is those words (an empty selection makes one waiting for its answer). */
export function makeBlank(text: string, start: number, end: number): string {
  const s = Math.max(0, Math.min(start, end));
  const e = Math.min(text.length, Math.max(start, end));
  // A selection inside or across an existing blank makes nothing.
  if (draftBlanks(text).some((b) => s < b.end && e > b.start)) return text;
  const words = text.slice(s, e);
  const lead = words.match(/^\s*/)?.[0] ?? "";
  const trail = words.match(/\s*$/)?.[0] ?? "";
  const answer = words.trim().replace(/\s+/g, " ");
  return text.slice(0, s) + lead + blankMarkup(answer, null) + (answer ? trail : "") + text.slice(e);
}

/** Blank lines from a printed handout ("_____", three or more underscores) become blanks waiting for their answers. */
export function blanksFromUnderscores(text: string): string {
  return text.replace(/_{3,}/g, "[[]]");
}

/** The pieces of the draft that may hold blanks: headings, paragraphs and list items (never Scripture or quotations). */
export function blankTexts(block: DraftBlock): string[] {
  switch (block.kind) {
    case "heading":
    case "paragraph":
      return [block.text];
    case "list":
      return block.items;
    default:
      return [];
  }
}

/** An import's blocks with printed blank lines turned into blanks, in the pastor's own words only. */
export function importBlanks(blocks: DraftBlock[]): DraftBlock[] {
  return blocks.map((b) => {
    if (b.kind === "heading" || b.kind === "paragraph") return { ...b, text: blanksFromUnderscores(b.text) };
    if (b.kind === "list") return { ...b, items: b.items.map(blanksFromUnderscores) };
    return b;
  });
}

export type BlankProblem = "blank_needs_answer" | "blank_too_long" | "blank_in_quotation" | "too_many_blanks";

/** Why Publish can't number these blanks yet (the same checks as genesis_sermon_blanks). */
export function blankProblems(blocks: DraftBlock[]): { blockId?: string; problem: BlankProblem }[] {
  const out: { blockId?: string; problem: BlankProblem }[] = [];
  let count = 0;
  for (const b of blocks) {
    if (b.kind === "quote" && draftBlanks(b.text).length) out.push({ blockId: b.id, problem: "blank_in_quotation" });
    const found = blankTexts(b).flatMap(draftBlanks);
    count += found.length;
    if (found.some((x) => x.answer === "")) out.push({ blockId: b.id, problem: "blank_needs_answer" });
    if (found.some((x) => (x.answer !== null && [...x.answer].length > BLANK_LIMITS.answer) || (x.hint !== null && [...x.hint].length > BLANK_LIMITS.hint))) {
      out.push({ blockId: b.id, problem: "blank_too_long" });
    }
  }
  if (count > BLANK_LIMITS.blanks) out.push({ problem: "too_many_blanks" });
  return out;
}

/** What publishing makes of the blanks: numbered markers in the text and the key apart (genesis_sermon_blanks). */
export function numberBlanks<B extends { kind: string }>(blocks: B[]): { blocks: B[]; blanks: { n: number; answer: string | null; hint: string | null }[] } {
  const blanks: { n: number; answer: string | null; hint: string | null }[] = [];
  const number = (text: string): string => {
    let out = "";
    let at = 0;
    for (const b of draftBlanks(text)) {
      blanks.push({ n: blanks.length + 1, answer: b.answer, hint: b.hint });
      out += text.slice(at, b.start) + `[[${blanks.length}]]`;
      at = b.end;
    }
    return out + text.slice(at);
  };
  const next = blocks.map((b) => {
    if (b.kind === "heading" || b.kind === "paragraph") return { ...b, text: number((b as unknown as { text: string }).text) };
    if (b.kind === "list") return { ...b, items: (b as unknown as { items: string[] }).items.map(number) };
    return b;
  });
  return { blocks: next, blanks };
}

/** A piece of published text: words, or the blank numbered `n`. */
export type Piece = { kind: "text"; text: string } | { kind: "blank"; n: number };

/** Splits published text at its "[[n]]" markers; a marker with no blank of that number stays as words. */
export function pieces(text: string, known: (n: number) => boolean): Piece[] {
  const out: Piece[] = [];
  const re = /\[\[(\d{1,3})\]\]/g;
  let at = 0;
  for (let m = re.exec(text); m; m = re.exec(text)) {
    const n = Number(m[1]);
    if (!known(n)) continue;
    if (m.index > at) out.push({ kind: "text", text: text.slice(at, m.index) });
    out.push({ kind: "blank", n });
    at = m.index + m[0].length;
  }
  if (at < text.length) out.push({ kind: "text", text: text.slice(at) });
  return out;
}

/** Published text with each blank as a line (for Copy), or as the given words. */
export function withBlanks(text: string, known: (n: number) => boolean, fill: (n: number) => string = () => "_____"): string {
  return pieces(text, known)
    .map((p) => (p.kind === "text" ? p.text : fill(p.n)))
    .join("");
}

/** An answer as it's compared: case, accents, spacing and the punctuation around it don't count. */
export function normalizedAnswer(s: string): string {
  return s
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/[’‘]/g, "'")
    .replace(/^[\s\p{P}]+|[\s\p{P}]+$/gu, "")
    .replace(/\s+/g, " ");
}

/** Whether a member's words match the key. */
export function isCorrect(response: string, answer: string): boolean {
  const r = normalizedAnswer(response);
  return r !== "" && r === normalizedAnswer(answer);
}
