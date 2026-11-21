// The review list after an import (VRS-18): words not carried over, notes
// about structure, references to check, and anything that may quote
// Scripture without being a Scripture item. Publish stays off until every
// item is kept, fixed or dismissed. The list is saved with the draft
// (church_sermons.draft_review) and the database refuses to publish while an
// item is open, by the same rules as reviewDone and stillOpen here
// (genesis_review_open, 20261121000000).
import type { DraftBlock } from "../draft.ts";
import { missingRuns, outlineWords, sourceWords } from "./completeness.ts";
import { mayQuoteScripture, type ImportOptions } from "./lines.ts";
import type { ImportNote } from "./result.ts";

export type ReviewItem =
  | { key: string; kind: "missing"; words: string[]; before: string[]; after: string[] }
  | { key: string; kind: "note"; note: ImportNote }
  | { key: string; kind: "reference"; blockId: string; raw: string }
  | { key: string; kind: "quotation"; blockId: string; text: string };

export type Decision = "kept" | "fixed" | "dismissed";

/** The review as it is saved with the draft (church_sermons.draft_review). */
export interface DraftReview {
  items: ReviewItem[];
  decisions: Record<string, Decision | undefined>;
}

export function reviewItems(source: string, blocks: DraftBlock[], notes: ImportNote[], options: ImportOptions = { language: "en" }): ReviewItem[] {
  const items: ReviewItem[] = [];
  for (const run of missingRuns(sourceWords(source), outlineWords(blocks))) {
    items.push({ key: `missing:${run.at}`, kind: "missing", words: run.words, before: run.before, after: run.after });
  }
  for (const note of notes) items.push({ key: `note:${note.kind}`, kind: "note", note });
  // Comments are never imported; say so even when there were none to find.
  if (!notes.some((n) => n.kind === "comments")) items.push({ key: "note:comments", kind: "note", note: { kind: "comments", count: 0 } });
  for (const block of blocks) {
    if (block.kind === "scripture" && block.ref.status === "ambiguous") {
      items.push({ key: `reference:${block.id}`, kind: "reference", blockId: block.id, raw: block.ref.raw });
    }
    if (mayQuoteScripture(block, options)) {
      const text = block.kind === "list" ? block.items.join(" · ") : block.kind === "scripture" ? "" : block.text;
      items.push({ key: `quotation:${block.id}`, kind: "quotation", blockId: block.id, text: text.slice(0, 300) });
    }
  }
  return items;
}

/** Whether every item has an answer (Publish's gate). Informational notes with nothing found need none. */
export function reviewDone(items: ReviewItem[], decisions: Record<string, Decision | undefined>): boolean {
  return items.every((item) => (item.kind === "note" && item.note.count === 0) || decisions[item.key] !== undefined);
}

/** Items still to check in the current outline: a reference fixed, or a possible quotation made a Scripture item (or removed), drops out by itself. */
export function stillOpen(items: ReviewItem[], blocks: DraftBlock[]): ReviewItem[] {
  return items.filter((item) => {
    if (item.kind === "reference") {
      const block = blocks.find((b) => b.id === item.blockId);
      return block?.kind === "scripture" && block.ref.status === "ambiguous";
    }
    if (item.kind === "quotation") {
      const block = blocks.find((b) => b.id === item.blockId);
      return block !== undefined && block.kind !== "scripture";
    }
    return true;
  });
}

/**
 * The review after another import is added to the end of the outline: every
 * item of the earlier review is kept with its answer (its blocks are still
 * there), and the new import's items are added under keys of their own
 * (`tag`), so an earlier answer never covers a new item.
 */
export function appendReview(earlier: DraftReview | null, items: ReviewItem[], tag: string): DraftReview | null {
  const added = items.map((item) => ({ ...item, key: `${tag}:${item.key}` }));
  const all = [...(earlier?.items ?? []), ...added];
  return all.length ? { items: all, decisions: { ...(earlier?.decisions ?? {}) } } : null;
}
