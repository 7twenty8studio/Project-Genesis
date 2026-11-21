// DOCX import (VRS-18), entirely in the pastor's browser: the file never
// leaves their computer. Mammoth reads the structure (headings, lists,
// quotes, tables); the document's own XML gives every word it holds, so the
// completeness check can list anything Mammoth didn't carry over (a text
// box, a shape's words) instead of losing it quietly. Comments are never
// imported, and the review list says so.
import JSZip from "jszip";
import mammoth from "mammoth";
import { blocksFromLines, type ImportOptions } from "./lines.ts";
import { linesFromHtml } from "./html.ts";
import type { ImportResult, ImportNote } from "./result.ts";

const STYLE_MAP = [
  "p[style-name='Title'] => h1:fresh",
  "p[style-name='Subtitle'] => h2:fresh",
  "p[style-name='Quote'] => blockquote > p:fresh",
  "p[style-name='Intense Quote'] => blockquote > p:fresh",
  "p[style-name='Cita'] => blockquote > p:fresh",
  "p[style-name='Citação'] => blockquote > p:fresh",
];

/** The words a part of the document holds, paragraph by paragraph (deleted tracked changes and hidden text left out). */
export function textOfPart(xml: string): { text: string; hidden: number } {
  let hidden = 0;
  const paragraphs = xml.split(/<\/w:p>/);
  const out: string[] = [];
  for (const paragraph of paragraphs) {
    const runs = paragraph.split(/<w:r[ >]/).slice(1);
    let text = "";
    for (const run of runs) {
      const isHidden = /<w:vanish\/>|<w:vanish w:val="(?:1|true|on)"\/>/.test(run.split("</w:rPr>")[0] ?? "");
      const pieces = [...run.matchAll(/<w:t(?: [^>]*)?>([^<]*)<\/w:t>|<w:tab\/>|<w:br\/>/g)].map((m) => (m[1] !== undefined ? m[1] : " "));
      if (isHidden) {
        if (pieces.join("").trim()) hidden++;
        continue;
      }
      text += pieces.join("");
    }
    if (text.trim()) out.push(decodeXml(text));
  }
  return { text: out.join("\n"), hidden };
}

const HIDDEN_RUN = /<w:r(?: [^>]*)?><w:rPr>(?:(?!<\/w:rPr>)[\s\S])*?<w:vanish(?: w:val="(?:1|true|on)")?\/>(?:(?!<\/w:rPr>)[\s\S])*?<\/w:rPr>(?:(?!<w:r[ >])(?!<\/w:r>)[\s\S])*<\/w:r>/g;

/** The document without its hidden runs: Mammoth would otherwise publish text the pastor hid. */
export function withoutHiddenRuns(xml: string): string {
  return xml.replace(HIDDEN_RUN, "");
}

function decodeXml(text: string): string {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, h: string) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d: string) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&amp;/g, "&");
}

export async function importDocx(data: ArrayBuffer, options: ImportOptions): Promise<ImportResult> {
  const zip = await JSZip.loadAsync(data);
  const part = async (name: string) => (await zip.file(name)?.async("string")) ?? "";
  const body = textOfPart(await part("word/document.xml"));
  const footnotes = textOfPart(await part("word/footnotes.xml"));
  const endnotes = textOfPart(await part("word/endnotes.xml"));
  const comments = textOfPart(await part("word/comments.xml"));

  // Mammoth's own footnote and endnote text includes Word's separators; only real notes are compared.
  const source = [body.text, footnotes.text, endnotes.text].filter(Boolean).join("\n");

  // Hidden text is left out (and listed in the review); Mammoth reads the document without it.
  const documentXml = await part("word/document.xml");
  const visible = withoutHiddenRuns(documentXml);
  const forMammoth = visible === documentXml ? data : await zip.file("word/document.xml", visible).generateAsync({ type: "arraybuffer" });

  const result = await mammoth.convertToHtml(
    // arrayBuffer in the browser build, buffer in Node (the tests).
    { arrayBuffer: forMammoth, buffer: forMammoth } as never,
    {
      styleMap: STYLE_MAP,
      convertImage: mammoth.images.imgElement(async () => ({ src: "" })),
    },
  );
  const { lines, notes } = linesFromHtml(result.value);

  const found: ImportNote[] = [];
  if (notes.tables) found.push({ kind: "tables", count: notes.tables });
  if (notes.images) found.push({ kind: "images", count: notes.images });
  if (notes.footnotes) found.push({ kind: "footnotes", count: notes.footnotes });
  if (body.hidden) found.push({ kind: "hidden", count: body.hidden });
  if (comments.text.trim()) found.push({ kind: "comments", count: comments.text.split("\n").length });
  return { blocks: blocksFromLines(lines, options), source, notes: found };
}
