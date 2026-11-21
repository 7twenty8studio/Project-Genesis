// Text PDF import (VRS-18), in the pastor's browser with pdf.js. PDFs have
// no paragraphs or headings, only positioned text, so lines are rebuilt
// from positions: a larger font starts a heading, a gap starts a
// paragraph, a bullet or number starts a list item. Words are never
// changed. A PDF with (almost) no text is a scan: the pastor is asked to
// paste the text or send the editable file instead.
import { blocksFromLines, LIST_MARKER, type ImportOptions, type Line } from "./lines.ts";
import { ScannedPDF, type ImportResult } from "./result.ts";

export interface PdfText {
  str: string;
  /** pdf.js transform: [a, b, c, d, x, y]. */
  transform: number[];
  height: number;
  width?: number;
  hasEOL?: boolean;
}

interface PdfLine {
  text: string;
  size: number;
  y: number;
  page: number;
}

/** Groups one page's text items into lines, top to bottom. */
export function pageLines(items: PdfText[], page: number): PdfLine[] {
  const rows: { y: number; size: number; parts: { x: number; width: number; str: string }[] }[] = [];
  for (const item of items) {
    if (!item.str) continue;
    const y = item.transform[5];
    const x = item.transform[4];
    const size = Math.abs(item.height || item.transform[3] || 0);
    const row = rows.find((r) => Math.abs(r.y - y) <= Math.max(2, size * 0.4));
    if (row) {
      row.parts.push({ x, width: item.width ?? 0, str: item.str });
      row.size = Math.max(row.size, size);
    } else rows.push({ y, size, parts: [{ x, width: item.width ?? 0, str: item.str }] });
  }
  return rows
    .sort((a, b) => b.y - a.y)
    .map((r) => ({
      text: joinParts(r.parts.sort((a, b) => a.x - b.x), r.size),
      size: r.size,
      y: r.y,
      page,
    }))
    .filter((l) => l.text);
}

/** Joins a row's pieces; a gap wider than a fifth of the font size is a space some PDFs don't write. */
function joinParts(parts: { x: number; width: number; str: string }[], size: number): string {
  let text = "";
  let end: number | null = null;
  for (const part of parts) {
    if (end !== null && part.width >= 0 && part.x - end > size * 0.2 && !/\s$/.test(text) && !/^\s/.test(part.str)) text += " ";
    text += part.str;
    end = part.width > 0 ? part.x + part.width : null;
  }
  return text.replace(/\s+/g, " ").trim();
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
}

/** Lines of the whole document as sermon Lines (headings, list items, paragraphs). */
export function linesFromPdf(all: PdfLine[]): Line[] {
  const body = median(all.map((l) => l.size)) || 12;
  const out: Line[] = [];
  let paragraph: string[] = [];
  let previous: PdfLine | null = null;
  const flush = () => {
    if (paragraph.length) out.push({ text: paragraph.join(" "), style: "p" });
    paragraph = [];
  };
  for (const line of all) {
    const gap = previous && previous.page === line.page ? previous.y - line.y : Infinity;
    const newBlock = gap > body * 1.9 || previous?.page !== line.page;
    if (line.size >= body * 1.25 && line.text.length <= 140) {
      flush();
      out.push({ text: line.text, style: line.size >= body * 1.6 ? "h1" : "h2" });
    } else if (LIST_MARKER.test(line.text)) {
      flush();
      out.push({ text: line.text.replace(LIST_MARKER, ""), style: /^\s*\(?\d/.test(line.text) ? "number" : "bullet" });
    } else if (!newBlock && out.length && paragraph.length === 0 && (out[out.length - 1].style === "bullet" || out[out.length - 1].style === "number")) {
      // A list item that wraps onto the next line.
      out[out.length - 1].text += ` ${line.text}`;
    } else {
      if (newBlock) flush();
      paragraph.push(line.text);
    }
    previous = line;
  }
  flush();
  return out;
}

/** Fewer than this many letters a page means the pages are pictures. */
const SCANNED_BELOW = 40;

export async function importPdf(data: ArrayBuffer, options: ImportOptions): Promise<ImportResult> {
  const pdfjs = await import("pdfjs-dist");
  pdfjs.GlobalWorkerOptions.workerSrc = "/pdf.worker.min.mjs";
  const document = await pdfjs.getDocument({ data: new Uint8Array(data) }).promise;
  const all: PdfLine[] = [];
  for (let n = 1; n <= document.numPages; n++) {
    const page = await document.getPage(n);
    const content = await page.getTextContent();
    const items: PdfText[] = content.items.flatMap((i) => ("str" in i ? [{ str: i.str, transform: i.transform, height: i.height, width: i.width }] : []));
    all.push(...pageLines(items, n));
  }
  const letters = all.reduce((sum, l) => sum + (l.text.match(/\p{L}/gu)?.length ?? 0), 0);
  if (letters < SCANNED_BELOW * document.numPages) throw new ScannedPDF();
  const source = all.map((l) => l.text).join("\n");
  return { blocks: blocksFromLines(linesFromPdf(all), options), source, notes: [] };
}
