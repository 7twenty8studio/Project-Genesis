// From a document's lines to sermon blocks (VRS-18 import). Every importer
// (paste, DOCX, PDF) first turns its source into Lines; this file makes the
// outline from them. It never changes a word: it only decides what kind of
// block each line is. A line becomes a Scripture block only when it is a
// reference by itself, optionally with a translation name and a quotation
// in quotation marks ("John 3:16 (KJV) “For God so loved…”"); the reference,
// the name and the quotation are kept exactly as written. Nothing is
// guessed from wording.
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

/** A list marker the pasted text carries ("- ", "• ", "1. ", "2) ", "a) "), removed from list items. */
export const LIST_MARKER = /^\s*(?:[-*•–·▪◦]|\(?\d{1,3}[.)]|[a-z][.)])\s+/;
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
 * mentions a verse stays a paragraph).
 */
export function scriptureLine(text: string, options: ImportOptions): DraftRef | null {
  const trimmed = text.trim();
  const match = REFERENCE_START.exec(trimmed);
  if (!match) return null;
  const raw = match[1].trim();
  const resolved = resolve(raw, { portugueseFirst: options.language === "pt" });
  if (resolved.status === "unlinked") return null;
  let rest = trimmed.slice(match[1].length).trim();
  let label: string | null = null;
  const named = LABEL.exec(rest);
  if (named) {
    label = (named[1] ?? named[2] ?? named[3]).trim();
    rest = rest.slice(named[0].length).trim();
  }
  let quote: string | null = null;
  if (rest) {
    const quoted = QUOTED.exec(rest);
    if (!quoted) return null; // More words that aren't a quotation: keep the line as written.
    quote = rest;
  }
  // A bare "Romans 8" on its own line is a chapter; "John" alone isn't a reference at all.
  return { raw, start: resolved.start, end: resolved.end, status: resolved.status, label, quote };
}

/** The outline, in the order of the lines; consecutive list lines of one kind become one list. */
export function blocksFromLines(lines: Line[], options: ImportOptions): DraftBlock[] {
  const blocks: DraftBlock[] = [];
  for (const line of lines) {
    const text = line.text.replace(/ /g, " ");
    if (text.trim() === "") continue;
    switch (line.style) {
      case "h1":
      case "h2":
      case "h3": {
        blocks.push({ id: newBlockID(), kind: "heading", text: text.trim(), level: line.style === "h1" ? 1 : line.style === "h2" ? 2 : 3 });
        break;
      }
      case "bullet":
      case "number": {
        const ordered = line.style === "number";
        const last = blocks[blocks.length - 1];
        if (last?.kind === "list" && last.ordered === ordered) last.items.push(text.trim());
        else blocks.push({ id: newBlockID(), kind: "list", items: [text.trim()], ordered });
        break;
      }
      case "quote":
        blocks.push({ id: newBlockID(), kind: "quote", text: text.trim() });
        break;
      default: {
        const ref = scriptureLine(text, options);
        if (ref) blocks.push({ id: newBlockID(), kind: "scripture", ref });
        else blocks.push({ id: newBlockID(), kind: "paragraph", text: text.trim() });
      }
    }
  }
  return blocks;
}
