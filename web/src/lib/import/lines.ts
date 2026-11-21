// From a document's lines to sermon blocks (VRS-18 import). Every importer
// (paste, DOCX, PDF) first turns its source into Lines; this file makes the
// outline from them. It never changes a word: it only decides what kind of
// block each line is. A line becomes a Scripture block when it is a
// reference by itself, optionally with a translation name and a quotation
// in quotation marks ("John 3:16 (KJV) “For God so loved…”"), or a
// quotation followed by its reference ("“For God so loved…” (John 3:16
// NIV)"). The same holds inside a quote (where the quotation needs no
// marks: the quote is one), a list item or a heading that carries quoted
// words, so a labelled NIV quotation always goes through the Scripture
// rules (its words are never published) wherever it was written. The
// reference, the name and the quotation are kept exactly as written.
// Anything that mentions a reference together with quotation marks or a
// translation name but isn't one of these shapes is listed for review
// (mayQuoteScripture). Nothing is guessed from wording.
import { newBlockID, type DraftBlock, type DraftRef } from "../draft.ts";
import { resolve } from "../shared/references.ts";

export type LineStyle = "h1" | "h2" | "h3" | "p" | "bullet" | "number" | "quote";

export interface Line {
  text: string;
  style: LineStyle;
}

export interface ImportOptions {
  /** The outline's language: in Portuguese, Brazilian abbreviations win ("Jo" is John, "Mc" Mark). */
  language: "en" | "es" | "pt" | "other";
}

/**
 * A list marker the pasted text carries ("- ", "• ", "● ", "1. ", "2) ", "a) "), removed from list items.
 * Google Docs exports "●" followed by an invisible zero-width space, which is part of the marker.
 */
export const LIST_MARKER = /^\s*(?:[-*•–·▪◦●○■□►▸➢✓]|\(?\d{1,3}[.)]|[a-z][.)])[\u200B\uFEFF]*\s+/;
const NUMBER_MARKER = /^\s*\(?\d{1,3}[.)]\s+/;

/** Lines from pasted plain text or Markdown: blank lines end paragraphs; "#", "-", "1.", ">" mark headings, lists and quotes. */
export function linesFromText(text: string): Line[] {
  const out: Line[] = [];
  let paragraph: string[] = [];
  let inQuote = false;
  const flush = () => {
    if (paragraph.length) out.push({ text: paragraph.join("\n"), style: "p" });
    paragraph = [];
  };
  for (const rawLine of text.replace(/\r\n?/g, "\n").split("\n")) {
    const line = rawLine.replace(/\s+$/, "");
    if (line.trim() === "") {
      flush();
      inQuote = false;
      continue;
    }
    const heading = /^\s*(#{1,3})\s+(.*)$/.exec(line);
    if (heading) {
      flush();
      out.push({ text: heading[2], style: `h${heading[1].length}` as LineStyle });
      inQuote = false;
      continue;
    }
    const quote = /^\s*>\s?(.*)$/.exec(line);
    if (quote) {
      flush();
      const last = out[out.length - 1];
      if (inQuote && last?.style === "quote") last.text += `\n${quote[1]}`;
      else out.push({ text: quote[1], style: "quote" });
      inQuote = true;
      continue;
    }
    inQuote = false;
    if (LIST_MARKER.test(line)) {
      flush();
      out.push({ text: line.replace(LIST_MARKER, ""), style: NUMBER_MARKER.test(line) ? "number" : "bullet" });
      continue;
    }
    paragraph.push(line.trim());
  }
  flush();
  return out;
}

const QUOTED = /^[“"«„‘']([\s\S]*)[”"»“’']$/;
const LABEL = /^(?:\(([^()]{1,60})\)|\[([^[\]]{1,60})\]|[-–—,]\s*([A-Za-zÀ-ÿ0-9 ]{2,40}))\s*/;
const REFERENCE_START = /^((?:[1-3](?:ª|º|o|st|nd|rd|\.)?\s*)?\p{L}[\p{L}.]*(?:\s+(?:de|of|dos|das|do|da)?\s*\p{L}[\p{L}.]*){0,3}\.?\s+\d{1,3}(?:\s*[:.,]\s*\d{1,3}(?:\s*[-–]\s*\d{1,3}(?:\s*[:.,]\s*\d{1,3})?)?)?(?:\s*[-–]\s*\d{1,3})?)(?=$|[\s(\[,–—-])/u;

/**
 * Reads a line that is a reference by itself, with an optional translation
 * name and quotation. Returns null for anything else (a sentence that
 * mentions a verse stays a paragraph). Inside a quote (`unquoted`) the
 * quotation needs no quotation marks.
 */
export function scriptureLine(text: string, options: ImportOptions, unquoted = false): DraftRef | null {
  const trimmed = text.trim();
  const match = REFERENCE_START.exec(trimmed);
  if (!match) return trailingScripture(trimmed, options, unquoted);
  const raw = match[1].trim();
  const resolved = resolve(raw, { portugueseFirst: options.language === "pt" });
  if (resolved.status === "unlinked") return trailingScripture(trimmed, options, unquoted);
  let rest = trimmed.slice(match[1].length).trim();
  let label: string | null = null;
  const named = LABEL.exec(rest);
  if (named) {
    label = (named[1] ?? named[2] ?? named[3]).trim();
    rest = rest.slice(named[0].length).trim();
  }
  // "John 3:16 NIV" with the name written bare.
  if (!label) {
    const bare = BARE_LABEL.exec(rest);
    if (bare) {
      label = bare[1];
      rest = rest.slice(bare[0].length).trim();
    }
  }
  let quote: string | null = null;
  if (rest) {
    const quoted = QUOTED.exec(rest);
    // More words that aren't a quotation: keep the line as written (in a quote, they are the quotation).
    // In a quote, unmarked words are the quotation when a translation is named or the reference has a line of its own.
    const ownLine = trimmed.slice(match[1].length).split("\n")[0].trim() === "";
    if (!quoted && !(unquoted && (label !== null || ownLine))) return trailingScripture(trimmed, options, unquoted);
    quote = rest;
  }
  // A bare "Romans 8" on its own line is a chapter; "John" alone isn't a reference at all.
  return { raw, start: resolved.start, end: resolved.end, status: resolved.status, label, quote };
}

// A reference at the end: "“…” — John 3:16 (NIV)", "“…” (John 3:16, NIV)", "… John 3:16 NIV" in a quote.
const REFERENCE_END = /(?:^|[\s(\[–—-])\(?\s*((?:[1-3](?:ª|º|o|st|nd|rd|\.)?\s*)?\p{L}[\p{L}.]*(?:\s+(?:de|of|dos|das|do|da)?\s*\p{L}[\p{L}.]*){0,3}\.?\s+\d{1,3}(?:\s*[:.,]\s*\d{1,3}(?:\s*[-–]\s*\d{1,3}(?:\s*[:.,]\s*\d{1,3})?)?)?(?:\s*[-–]\s*\d{1,3})?)\s*(?:[,(\[]\s*([^()[\]]{1,60}?)\s*[)\]]?|\s+([A-Z][A-Za-z0-9]{1,9}))?\s*[)\]]?\s*[.]?$/u;

function trailingScripture(text: string, options: ImportOptions, unquoted: boolean): DraftRef | null {
  // The quotation comes first, then the reference (after a dash, in brackets, or on the quote's last line).
  for (let start = 0; start < text.length; start++) {
    const match = REFERENCE_END.exec(text.slice(start));
    if (!match) return null;
    const at = start + match.index;
    const quote = text.slice(0, at).replace(/[\s–—-]+$/, "").trim();
    const raw = match[1].trim();
    const resolved = resolve(raw, { portugueseFirst: options.language === "pt" });
    const label = (match[2] ?? match[3] ?? "").trim() || null;
    // Unmarked words (in a quote) count when a translation is named or the reference follows a dash or a line break.
    const apart = /(?:\n|[–—-])\s*\(?\s*$/.test(text.slice(0, at + 1)) || /(?:\n|[–—-])\s*$/.test(text.slice(0, at));
    if (resolved.status !== "unlinked" && quote && (QUOTED.test(quote) || (unquoted && (label !== null || apart)))) {
      return { raw, start: resolved.start, end: resolved.end, status: resolved.status, label, quote };
    }
    // A longer book name may start further in ("1 John" vs "John"): try from the next character.
    start = at;
  }
  return null;
}

/** The outline, in the order of the lines; consecutive list lines of one kind become one list. */
export function blocksFromLines(lines: Line[], options: ImportOptions): DraftBlock[] {
  const blocks: DraftBlock[] = [];
  const scripture = (ref: DraftRef) => blocks.push({ id: newBlockID(), kind: "scripture", ref });
  for (const line of lines) {
    const text = line.text.replace(/\u00a0/g, " ");
    if (text.trim() === "") continue;
    switch (line.style) {
      case "h1":
      case "h2":
      case "h3": {
        // A heading that quotes a verse goes through the Scripture rules; a bare reference stays a heading.
        const ref = scriptureLine(text, options);
        if (ref?.quote) scripture(ref);
        else blocks.push({ id: newBlockID(), kind: "heading", text: text.trim(), level: line.style === "h1" ? 1 : line.style === "h2" ? 2 : 3 });
        break;
      }
      case "bullet":
      case "number": {
        const ref = scriptureLine(text, options);
        if (ref?.quote) {
          scripture(ref);
          break;
        }
        const ordered = line.style === "number";
        const last = blocks[blocks.length - 1];
        if (last?.kind === "list" && last.ordered === ordered) last.items.push(text.trim());
        else blocks.push({ id: newBlockID(), kind: "list", items: [text.trim()], ordered });
        break;
      }
      case "quote": {
        const ref = scriptureLine(text, options, true);
        if (ref && (ref.quote || ref.label)) scripture(ref);
        else blocks.push({ id: newBlockID(), kind: "quote", text: text.trim() });
        break;
      }
      default: {
        const ref = scriptureLine(text, options);
        if (ref) scripture(ref);
        else blocks.push({ id: newBlockID(), kind: "paragraph", text: text.trim() });
      }
    }
  }
  return blocks;
}

// Translation names as people write them next to a verse (uppercase codes, or the full name).
const TRANSLATION_CODES = "NIV|NIVUK|NIrV|ESV|ESVUK|NKJV|NKJ|NLT|NASB|NASB95|NASB2020|LSB|CSB|HCSB|MSG|AMP|AMPC|NRSV|NRSVUE|NRSVA|RSV|NET|NCV|GNT|GNB|CEV|ERV|EHV|TLB|TPT|ISV|NABRE|NAB|NJB|JB|KJV|AKJV|KJ21|MEV|WEB|ASV|YLT|DRA|RV1909|RVA|RVR|RVR60|RVR1960|RVR1995|RVC|RVA2015|NVI|NTV|LBLA|NBLA|DHH|PDT|TLA|BLP|BLPH|NBV|NBVP|NVIPT|ARA|ARC|ACF|AS21|NAA|NVT|NTLH|KJA|BLT|BLIVRE|OL";
const BARE_LABEL = new RegExp(`^(${TRANSLATION_CODES})\\b[.,:]?\\s*`);
const TRANSLATION_NAME = new RegExp(`(?:^|[^A-Za-z])(?:${TRANSLATION_CODES})(?:$|[^A-Za-z])|new international|english standard|king james|new living|new american standard|christian standard|the message|reina[- ]valera|nueva versi[oó]n internacional|nova vers[aã]o internacional|almeida|nueva traducci[oó]n viviente|nova tradu[cç][aã]o`, "i");
const CODE_ONLY = new RegExp(`(?:^|[^A-Za-z])(?:${TRANSLATION_CODES})(?:$|[^A-Za-z])`);
const QUOTE_MARKS = /[“”"«»„]|(?:^|\s)['‘][^'’]{12,}['’]/;
const ANY_REFERENCE = /(?:^|[^\p{L}\d])((?:[1-3](?:ª|º|o|st|nd|rd|\.)?\s*)?\p{L}[\p{L}.]*(?:\s+(?:de|of|dos|das|do|da)?\s*\p{L}[\p{L}.]*){0,3}\.?\s+\d{1,3}\s*[:.,]\s*\d{1,3})/gu;

/** Whether some words in this text name a passage the Bibles know (chapter and verse). */
function mentionsReference(text: string, options: ImportOptions): boolean {
  for (const match of text.matchAll(ANY_REFERENCE)) {
    // Try each way the words before the number could start ("in John 3:16", "John 3:16").
    const words = match[1].split(/\s+/);
    for (let i = 0; i < words.length - 1; i++) {
      if (resolve(words.slice(i).join(" "), { portugueseFirst: options.language === "pt" }).status !== "unlinked") return true;
    }
  }
  return false;
}

/**
 * Whether a block that isn't Scripture may still quote it: a reference
 * together with quotation marks or a translation name, or a quote that
 * names a translation. These go on the review list ("Is this Scripture?").
 */
export function mayQuoteScripture(block: DraftBlock, options: ImportOptions): boolean {
  if (block.kind === "scripture") return false;
  const texts = block.kind === "list" ? block.items : [block.text];
  return texts.some((text) => {
    const reference = mentionsReference(text, options);
    if (block.kind === "quote") return reference || CODE_ONLY.test(text);
    return reference && (QUOTE_MARKS.test(text) || TRANSLATION_NAME.test(text));
  });
}
