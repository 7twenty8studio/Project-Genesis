import type { DraftBlock } from "../draft.ts";

/** Something an importer had to change about structure (never words), for the review list. */
export interface ImportNote {
  kind: "tables" | "images" | "footnotes" | "comments" | "hidden";
  count: number;
}

export interface ImportResult {
  blocks: DraftBlock[];
  /** Every word the source holds, for the word-for-word check. */
  source: string;
  notes: ImportNote[];
}

export class ScannedPDF extends Error {
  constructor() {
    super("scanned_pdf");
  }
}
