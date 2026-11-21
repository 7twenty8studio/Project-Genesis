// A sermon draft as Church Studio edits it (church_sermons.draft_blocks and
// its details), in the exact shape save_church_sermon checks
// (genesis_clean_sermon_blocks): unknown fields are refused there, so
// nothing else is ever sent.
import type { DraftReview } from "./import/review.ts";
import type { ReferenceStatus } from "./shared/references.ts";

export interface DraftRef {
  /** What the pastor typed, kept as written ("Jn 3:16", "Juan 3,16"). */
  raw: string;
  start: number | null;
  end: number | null;
  status: ReferenceStatus;
  /** The translation the pastor named ("NIV", "RVR1960", "KJV"), or null. */
  label: string | null;
  /** The pastor's quotation as written. Stays in the draft; only KJV, WEB, ASV, RV1909 and Bíblia Livre are shown to readers, from their own copy. */
  quote: string | null;
}

export type DraftBlock =
  | { id: string; kind: "heading"; text: string; level: 1 | 2 | 3 }
  | { id: string; kind: "paragraph"; text: string }
  | { id: string; kind: "quote"; text: string }
  | { id: string; kind: "list"; items: string[]; ordered: boolean }
  | { id: string; kind: "scripture"; ref: DraftRef };

export interface DraftDetails {
  title: string;
  speaker: string;
  series: string | null;
  preached_on: string | null;
  time_zone: string | null;
  location: string;
  language: "en" | "es" | "pt" | "other";
  audience: "link" | "members";
  cover_alt: string;
  cover_decorative: boolean;
}

/** A church_sermons row as leaders read it (RLS "Leaders read"). */
export interface DraftRow extends DraftDetails {
  id: string;
  group_id: string;
  slug: string;
  cover_id: string | null;
  draft_blocks: DraftBlock[];
  draft_version: number;
  status: "draft" | "published" | "unpublished";
  live_audience: "link" | "members" | null;
  hidden_at: string | null;
  published_at: string | null;
  published_revision_id: string | null;
  /** The import review, saved with the draft; Publish is refused while an item is open. */
  draft_review: DraftReview | null;
}

/** The same limits the database enforces, checked before saving so people see why. */
export const LIMITS = { blocks: 400, heading: 300, text: 5000, items: 100, item: 2000, raw: 120, label: 60, quote: 5000, total: 200_000 };

let counter = 0;
/** A block id that survives edits (letters, digits, - and _; at most 40). */
export function newBlockID(): string {
  counter = (counter + 1) % 1_000_000;
  const random = Math.random().toString(36).slice(2, 10);
  return `b${Date.now().toString(36)}${counter.toString(36)}${random}`.slice(0, 40);
}

/** The characters a draft holds, as the database counts them (at most 200,000). */
export function draftLength(blocks: DraftBlock[]): number {
  let total = 0;
  for (const b of blocks) {
    if (b.kind === "list") total += b.items.reduce((n, i) => n + [...i].length, 0);
    else if (b.kind === "scripture") total += [...b.ref.raw].length + (b.ref.quote ? [...b.ref.quote].length : 0);
    else total += [...b.text].length;
  }
  return total;
}

/** Problems save_church_sermon would refuse, in words Studio can show (empty when fine). */
export function draftProblems(blocks: DraftBlock[]): { blockId?: string; problem: string }[] {
  const out: { blockId?: string; problem: string }[] = [];
  if (blocks.length > LIMITS.blocks) out.push({ problem: "too_many_blocks" });
  if (draftLength(blocks) > LIMITS.total) out.push({ problem: "too_long" });
  for (const b of blocks) {
    const len = (s: string) => [...s].length;
    if (b.kind === "heading" && len(b.text) > LIMITS.heading) out.push({ blockId: b.id, problem: "heading_too_long" });
    if ((b.kind === "paragraph" || b.kind === "quote") && len(b.text) > LIMITS.text) out.push({ blockId: b.id, problem: "text_too_long" });
    if (b.kind === "list" && (b.items.length > LIMITS.items || b.items.some((i) => len(i) > LIMITS.item))) out.push({ blockId: b.id, problem: "list_too_long" });
    if (b.kind === "scripture") {
      if (b.ref.raw.trim() === "" || len(b.ref.raw.trim()) > LIMITS.raw) out.push({ blockId: b.id, problem: "reference_length" });
      if (b.ref.label && len(b.ref.label) > LIMITS.label) out.push({ blockId: b.id, problem: "label_too_long" });
      if (b.ref.quote && len(b.ref.quote) > LIMITS.quote) out.push({ blockId: b.id, problem: "quote_too_long" });
    }
  }
  return out;
}

/** Translations whose quoted words Versely shows readers (from its own copy), as the database reads labels (genesis_quote_translation). */
export function quoteTranslation(label: string | null): "KJV" | "WEB" | "ASV" | "RV1909" | "BLIVRE" | null {
  if (!label) return null;
  const key = label
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  const map: Record<string, "KJV" | "WEB" | "ASV" | "RV1909" | "BLIVRE"> = {
    kjv: "KJV", kingjames: "KJV", kingjamesversion: "KJV", authorizedversion: "KJV", av: "KJV",
    web: "WEB", worldenglishbible: "WEB",
    asv: "ASV", americanstandardversion: "ASV",
    rv1909: "RV1909", rva1909: "RV1909", reinavalera1909: "RV1909", reinavaleraantigua: "RV1909",
    blivre: "BLIVRE", biblialivre: "BLIVRE",
  };
  return map[key] ?? null;
}
