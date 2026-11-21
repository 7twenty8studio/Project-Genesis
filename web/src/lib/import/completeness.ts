// The word-for-word check after every import (VRS-18): every word of the
// source must be in the outline, in order. Anything not carried over is
// listed with the words around it, so the pastor can keep, fix or dismiss
// it before publishing. Punctuation and list markers are ignored (they
// don't change what's said); letters, digits, accents and case are not.
import type { DraftBlock } from "../draft.ts";
import { LIST_MARKER } from "./lines.ts";

const WORD = /[\p{L}\p{M}\p{N}]+(?:['’\-‐][\p{L}\p{M}\p{N}]+)*/gu;

export function words(text: string): string[] {
  return text.normalize("NFC").match(WORD) ?? [];
}

/** A source's words, without the list markers and Markdown signs that become structure. */
export function sourceWords(text: string): string[] {
  return text
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .flatMap((line) => words(line.replace(/^\s*#{1,3}\s+/, "").replace(/^\s*>\s?/, "").replace(LIST_MARKER, "")));
}

export function outlineWords(blocks: DraftBlock[]): string[] {
  return blocks.flatMap((b) => {
    switch (b.kind) {
      case "list":
        return b.items.flatMap(words);
      case "scripture":
        return [...words(b.ref.raw), ...words(b.ref.label ?? ""), ...words(b.ref.quote ?? "")];
      default:
        return words(b.text);
    }
  });
}

export interface MissingRun {
  /** The words left out, as in the source. */
  words: string[];
  /** A few words before and after, for finding it. */
  before: string[];
  after: string[];
  /** Index of the first missing word in the source's words. */
  at: number;
}

/**
 * The source's words that aren't in the outline, as runs. A longest common
 * subsequence over words, so a moved or added word doesn't hide a missing
 * one. Sermons are short (a few thousand words); larger sources are
 * compared in windows to bound the work.
 */
export function missingRuns(source: string[], outline: string[], context = 4): MissingRun[] {
  const kept = matchedSourceIndexes(source, outline);
  const runs: MissingRun[] = [];
  let i = 0;
  while (i < source.length) {
    if (kept[i]) {
      i++;
      continue;
    }
    const start = i;
    while (i < source.length && !kept[i]) i++;
    runs.push({ words: source.slice(start, i), before: source.slice(Math.max(0, start - context), start), after: source.slice(i, i + context), at: start });
  }
  return runs;
}

function matchedSourceIndexes(source: string[], outline: string[]): boolean[] {
  const kept = new Array<boolean>(source.length).fill(false);
  const WINDOW = 3000;
  let s0 = 0;
  let o0 = 0;
  while (s0 < source.length && o0 < outline.length) {
    const s1 = Math.min(source.length, s0 + WINDOW);
    const o1 = Math.min(outline.length, o0 + WINDOW + 200);
    const a = source.slice(s0, s1);
    const b = outline.slice(o0, o1);
    // LCS table, last row kept per column in Uint16 rows (3000 x 3200 fits comfortably).
    const n = a.length;
    const m = b.length;
    const table = new Array<Uint16Array>(n + 1);
    for (let x = 0; x <= n; x++) table[x] = new Uint16Array(m + 1);
    for (let x = n - 1; x >= 0; x--) {
      for (let y = m - 1; y >= 0; y--) {
        table[x][y] = a[x] === b[y] ? table[x + 1][y + 1] + 1 : Math.max(table[x + 1][y], table[x][y + 1]);
      }
    }
    let x = 0;
    let y = 0;
    let lastY = 0;
    while (x < n && y < m) {
      if (a[x] === b[y]) {
        kept[s0 + x] = true;
        x++;
        y++;
        lastY = y;
      } else if (table[x + 1][y] >= table[x][y + 1]) x++;
      else y++;
    }
    s0 = s1;
    o0 += Math.max(lastY, 1);
  }
  return kept;
}
