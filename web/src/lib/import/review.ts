// The review list after an import (VRS-18): words not carried over, notes
// about structure, and references to check. Publish stays off until every
// item is kept, fixed or dismissed.
import type { DraftBlock } from "../draft.ts";
import { missingRuns, outlineWords, sourceWords } from "./completeness.ts";
import type { ImportNote } from "./result.ts";

export type ReviewItem =
  | { key: string; kind: "missing"; words: string[]; before: string[]; after: string[] }
  | { key: string; kind: "note"; note: ImportNote }
  | { key: string; kind: "reference"; blockId: string; raw: string };

export type Decision = "kept" | "fixed" | "dismissed";

export function reviewItems(source: string, blocks: DraftBlock[], notes: ImportNote[]): ReviewItem[] {
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
  }
  return items;
}

/** Whether every item has an answer (Publish's gate). Informational notes with nothing found need none. */
export function reviewDone(items: ReviewItem[], decisions: Record<string, Decision | undefined>): boolean {
  return items.every((item) => (item.kind === "note" && item.note.count === 0) || decisions[item.key] !== undefined);
}

/** References still ambiguous in the current outline (fixed ones drop out by themselves). */
export function stillOpen(items: ReviewItem[], blocks: DraftBlock[]): ReviewItem[] {
  return items.filter((item) => {
    if (item.kind !== "reference") return true;
    const block = blocks.find((b) => b.id === item.blockId);
    return block?.kind === "scripture" && block.ref.status === "ambiguous";
  });
}
