// DOCX import (VRS-18), entirely in the pastor's browser: the file never
// leaves their computer. Mammoth reads the structure (headings, lists,
// quotes, tables); the document's own XML gives every word it holds, so the
// completeness check can list anything Mammoth didn't carry over (a text
// box, a shape's words) instead of losing it quietly. Comments are never
// imported, and the review list says so. The XML is parsed as XML (any
// namespace prefix, any spelling of an empty element) and hidden text is
// worked out the way Word does: the run's own setting, then its character
// style, its paragraph's style (each with the styles they're based on) and
// the document default.
import { DOMParser, XMLSerializer } from "@xmldom/xmldom";
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

const W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";

/** The w:val of an on/off property: absent means on; "0", "false" and "off" mean off. */
function onOff(element: Element): boolean {
  const value = element.getAttributeNS(W, "val") || element.getAttribute("w:val") || "";
  return !["0", "false", "off"].includes(value.trim().toLowerCase());
}

/** The first child element in Word's namespace with this local name (whatever prefix the file uses). */
function child(element: Element | null | undefined, name: string): Element | null {
  if (!element) return null;
  for (let node = element.firstChild; node; node = node.nextSibling) {
    if (node.nodeType === 1 && (node as Element).namespaceURI === W && (node as Element).localName === name) return node as Element;
  }
  return null;
}

function attr(element: Element | null, name: string): string | null {
  if (!element) return null;
  return element.getAttributeNS(W, name) || null;
}

/** "Hidden" (w:vanish) as each style sets it, and what each style is based on. */
export interface WordStyles {
  /** styleId -> true / false where the style sets vanish itself. */
  vanish: Map<string, boolean>;
  basedOn: Map<string, string>;
  /** The document default for runs (docDefaults › rPrDefault). */
  defaultHidden: boolean;
  /** The default paragraph and character styles (w:default="1"). */
  defaultParagraph: string | null;
  defaultCharacter: string | null;
}

export function readStyles(xml: string): WordStyles {
  const styles: WordStyles = { vanish: new Map(), basedOn: new Map(), defaultHidden: false, defaultParagraph: null, defaultCharacter: null };
  if (!xml.trim()) return styles;
  const doc = parse(xml);
  const defaults = child(child(child(doc.documentElement, "docDefaults"), "rPrDefault"), "rPr");
  const vanish = child(defaults, "vanish");
  if (vanish) styles.defaultHidden = onOff(vanish);
  const list = doc.getElementsByTagNameNS(W, "style");
  for (let i = 0; i < list.length; i++) {
    const style = list[i];
    const id = attr(style, "styleId");
    if (!id) continue;
    const based = attr(child(style, "basedOn"), "val");
    if (based) styles.basedOn.set(id, based);
    const own = child(child(style, "rPr"), "vanish");
    if (own) styles.vanish.set(id, onOff(own));
    if (["1", "true", "on"].includes(attr(style, "default") ?? "")) {
      const type = attr(style, "type");
      if (type === "paragraph") styles.defaultParagraph = id;
      if (type === "character") styles.defaultCharacter = id;
    }
  }
  return styles;
}

/** Whether a style (or a style it's based on) sets hidden; undefined when none in the chain says. */
function styleHidden(styles: WordStyles, id: string | null): boolean | undefined {
  const seen = new Set<string>();
  for (let current = id; current && !seen.has(current); current = styles.basedOn.get(current) ?? null) {
    seen.add(current);
    const value = styles.vanish.get(current);
    if (value !== undefined) return value;
  }
  return undefined;
}

function closest(node: Node, name: string): Element | null {
  for (let p = node.parentNode; p; p = p.parentNode) {
    if (p.nodeType === 1 && (p as Element).namespaceURI === W && (p as Element).localName === name) return p as Element;
  }
  return null;
}

/**
 * Whether Word hides this run: its own w:vanish (any spelling, any prefix,
 * w:val honoured), else its character style's chain, else its paragraph
 * style's chain, else the document default. The nearest one that says wins.
 */
export function isHiddenRun(run: Element, styles: WordStyles): boolean {
  const rPr = child(run, "rPr");
  const own = child(rPr, "vanish");
  if (own) return onOff(own);
  const character = styleHidden(styles, attr(child(rPr, "rStyle"), "val") ?? styles.defaultCharacter);
  if (character !== undefined) return character;
  const paragraph = closest(run, "p");
  const paragraphStyle = paragraph ? attr(child(child(paragraph, "pPr"), "pStyle"), "val") : null;
  const inherited = styleHidden(styles, paragraphStyle ?? styles.defaultParagraph);
  if (inherited !== undefined) return inherited;
  return styles.defaultHidden;
}

function parse(xml: string): Document {
  const errors: string[] = [];
  const doc = new DOMParser({
    errorHandler: { warning: () => undefined, error: (m: string) => errors.push(m), fatalError: (m: string) => errors.push(m) },
  }).parseFromString(xml, "text/xml");
  if (errors.length || !doc.documentElement) throw new Error("This Word file couldn't be read.");
  return doc as unknown as Document;
}

/** The words one run holds: text, tabs and breaks (deleted text, w:delText, is never read). */
function runText(run: Element): string {
  let text = "";
  for (let node = run.firstChild; node; node = node.nextSibling) {
    if (node.nodeType !== 1 || (node as Element).namespaceURI !== W) continue;
    const name = (node as Element).localName;
    if (name === "t") text += node.textContent ?? "";
    else if (name === "tab" || name === "br" || name === "cr") text += " ";
  }
  return text;
}

/** Every run of a part, in document order, with the paragraph it belongs to. */
function runsOf(doc: Document): Element[] {
  const list = doc.getElementsByTagNameNS(W, "r");
  const out: Element[] = [];
  for (let i = 0; i < list.length; i++) out.push(list[i]);
  return out;
}

/** A part read once: its visible words paragraph by paragraph, how many hidden runs held words, and the XML without them. */
export function readPart(xml: string, styles: WordStyles): { text: string; hidden: number; visibleXml: string } {
  if (!xml.trim()) return { text: "", hidden: 0, visibleXml: xml };
  const doc = parse(xml);
  let hidden = 0;
  const byParagraph = new Map<Element | null, string>();
  const order: (Element | null)[] = [];
  const remove: Element[] = [];
  for (const run of runsOf(doc)) {
    if (closest(run, "del")) continue; // a deleted tracked change: not part of the document
    const text = runText(run);
    if (isHiddenRun(run, styles)) {
      if (text.trim()) hidden++;
      remove.push(run);
      continue;
    }
    const paragraph = closest(run, "p");
    if (!byParagraph.has(paragraph)) {
      byParagraph.set(paragraph, "");
      order.push(paragraph);
    }
    byParagraph.set(paragraph, byParagraph.get(paragraph) + text);
  }
  for (const run of remove) run.parentNode?.removeChild(run);
  // Paragraphs in the order their first words appear (a text box's paragraph sits inside its anchor's).
  const text = order.map((p) => byParagraph.get(p) ?? "").filter((t) => t.trim()).join("\n");
  const visibleXml = remove.length ? new XMLSerializer().serializeToString(doc as unknown as Node) : xml;
  return { text, hidden, visibleXml };
}

/** The words a part of the document holds, paragraph by paragraph (deleted tracked changes and hidden text left out). */
export function textOfPart(xml: string, styles: WordStyles = readStyles("")): { text: string; hidden: number } {
  const { text, hidden } = readPart(xml, styles);
  return { text, hidden };
}

/** The part without its hidden runs: Mammoth would otherwise publish text the pastor hid. */
export function withoutHiddenRuns(xml: string, styles: WordStyles = readStyles("")): string {
  return readPart(xml, styles).visibleXml;
}

export async function importDocx(data: ArrayBuffer, options: ImportOptions): Promise<ImportResult> {
  const zip = await JSZip.loadAsync(data);
  const part = async (name: string) => (await zip.file(name)?.async("string")) ?? "";
  const styles = readStyles(await part("word/styles.xml"));
  const body = readPart(await part("word/document.xml"), styles);
  const footnotes = readPart(await part("word/footnotes.xml"), styles);
  const endnotes = readPart(await part("word/endnotes.xml"), styles);
  const comments = readPart(await part("word/comments.xml"), styles);

  // Mammoth's own footnote and endnote text includes Word's separators; only real notes are compared.
  const source = [body.text, footnotes.text, endnotes.text].filter(Boolean).join("\n");

  // Hidden text is left out (and listed in the review): Mammoth reads the
  // document, footnotes and endnotes without it.
  let changed = false;
  for (const [name, read] of [["word/document.xml", body], ["word/footnotes.xml", footnotes], ["word/endnotes.xml", endnotes]] as const) {
    if (read.visibleXml !== (await part(name))) {
      zip.file(name, read.visibleXml);
      changed = true;
    }
  }
  const forMammoth = changed ? await zip.generateAsync({ type: "arraybuffer" }) : data;

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
  const hidden = body.hidden + footnotes.hidden + endnotes.hidden;
  if (hidden) found.push({ kind: "hidden", count: hidden });
  if (comments.text.trim()) found.push({ kind: "comments", count: comments.text.split("\n").length });
  return { blocks: blocksFromLines(lines, options), source, notes: found };
}
