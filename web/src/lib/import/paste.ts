import { blocksFromLines, linesFromText, type ImportOptions } from "./lines.ts";
import type { ImportResult } from "./result.ts";

/** Pasted text or Markdown: the source is exactly what was pasted. */
export function importText(text: string, options: ImportOptions): ImportResult {
  return { blocks: blocksFromLines(linesFromText(text), options), source: text, notes: [] };
}
