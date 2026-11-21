// A published sermon as published_sermon(slug) returns it (VRS-18), and the
// pure helpers the guest page uses: sections for Jump to and Copy, and the
// text Copy puts on the clipboard. Scripture text is never part of an
// outline: references carry verse ids (KJV numbering) and, for a quotation
// from a free translation, only its code (KJV, WEB, ASV, RV1909, BLIVRE).

export type TranslationCode = "KJV" | "WEB" | "ASV" | "RV1909" | "BLIVRE";

export interface PublishedRef {
  raw: string;
  start: number | null;
  end: number | null;
  status: "verified" | "ambiguous" | "unlinked";
  label: string | null;
  /** The quoted translation, when it's one readers show from their own copy. */
  translation: TranslationCode | null;
  /** The pastor quoted words that aren't published (another translation, or no verified reference). */
  quote_withheld: boolean;
}

export type Block =
  | { id: string; kind: "heading"; text: string; level: 1 | 2 | 3 }
  | { id: string; kind: "paragraph"; text: string }
  | { id: string; kind: "quote"; text: string }
  | { id: string; kind: "list"; items: string[]; ordered: boolean }
  | { id: string; kind: "scripture"; ref: PublishedRef };

export interface SermonSummary {
  slug: string;
  title: string;
  speaker: string;
  series: string | null;
  preached_on: string | null;
  audience: "link" | "members";
}

export interface PublishedSermon {
  status: "ok";
  id: string;
  slug: string;
  group_id: string;
  church: string;
  title: string;
  speaker: string;
  series: string | null;
  preached_on: string | null;
  time_zone: string | null;
  location: string;
  language: "en" | "es" | "pt" | "other";
  cover: { id: string; path: string; alt: string; decorative: boolean } | null;
  audience: "link" | "members";
  revision: number;
  published_at: string;
  blocks: Block[];
  previous: SermonSummary | null;
  next: SermonSummary | null;
  is_member: boolean;
}

export type SermonLookup = PublishedSermon | { status: "members_only" } | { status: "not_found" };

export interface Section {
  /** The heading's block id, or "start" for anything before the first heading. */
  id: string;
  title: string | null;
  blocks: Block[];
}

/** Splits the outline at each heading, for Jump to and per-section Copy. */
export function sections(blocks: Block[]): Section[] {
  const out: Section[] = [];
  for (const block of blocks) {
    if (block.kind === "heading") out.push({ id: block.id, title: block.text, blocks: [block] });
    else if (out.length === 0) out.push({ id: "start", title: null, blocks: [block] });
    else out[out.length - 1].blocks.push(block);
  }
  return out;
}

/**
 * What Copy puts on the clipboard: the church's words exactly as published,
 * one block per paragraph; a reference as the pastor typed it (never verse
 * text, which the reader's own Bible shows).
 */
export function copyText(blocks: Block[]): string {
  return blocks
    .map((block) => {
      switch (block.kind) {
        case "heading":
        case "paragraph":
          return block.text;
        case "quote":
          return `“${block.text}”`;
        case "list":
          return block.items.map((item, i) => (block.ordered ? `${i + 1}. ${item}` : `• ${item}`)).join("\n");
        case "scripture":
          return block.ref.label ? `${block.ref.raw} (${block.ref.label})` : block.ref.raw;
      }
    })
    .filter((text) => text.trim() !== "")
    .join("\n\n");
}

/** A short anchor id that's safe in a URL fragment. */
export function anchorFor(section: Section): string {
  return section.id === "start" ? "top" : `s-${section.id}`;
}
