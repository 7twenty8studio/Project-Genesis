// Mammoth's HTML (DOCX import) to Lines, without a browser DOM so the same
// code runs in Node tests. Mammoth writes plain, well-formed HTML: h1–h6, p,
// ul/ol/li, blockquote, table/tr/td, strong/em/a/sup/img, br.
import type { Line, LineStyle } from "./lines.ts";

export interface HtmlNotes {
  tables: number;
  images: number;
  footnotes: number;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

function decode(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, code: string) => {
    if (code[0] === "#") return String.fromCodePoint(code[1].toLowerCase() === "x" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10));
    return ENTITIES[code.toLowerCase()] ?? m;
  });
}

interface Token {
  kind: "open" | "close" | "text" | "void";
  name: string;
  attrs: string;
  text: string;
}

function tokenize(html: string): Token[] {
  const tokens: Token[] = [];
  const re = /<(\/?)([a-zA-Z0-9]+)([^>]*?)(\/?)>|([^<]+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) {
    if (m[5] !== undefined) tokens.push({ kind: "text", name: "", attrs: "", text: decode(m[5]) });
    else {
      const name = m[2].toLowerCase();
      const isVoid = m[4] === "/" || name === "br" || name === "img";
      tokens.push({ kind: m[1] ? "close" : isVoid ? "void" : "open", name, attrs: m[3], text: "" });
    }
  }
  return tokens;
}

/**
 * Lines in document order. Tables are flattened (each cell's paragraphs in
 * reading order) and images left out, both counted for the review list.
 * Footnote markers ("[1]") are dropped from the text and the footnotes
 * themselves come last, as paragraphs, so none of their words is lost.
 */
export function linesFromHtml(source: string): { lines: Line[]; notes: HtmlNotes } {
  const notes: HtmlNotes = { tables: 0, images: 0, footnotes: 0 };
  // Footnote reference markers and their back links are Mammoth's, not the document's words.
  const html = source
    .replace(/<sup><a href="#(?:foot|end)note-\d+"[^>]*>\[\d+\]<\/a><\/sup>/g, "")
    .replace(/\s*<a href="#(?:foot|end)note-ref-\d+"[^>]*>↑<\/a>/g, "");
  const lines: Line[] = [];
  const footnoteLines: Line[] = [];
  const stack: string[] = [];
  const lists: ("ul" | "ol")[] = [];
  let buffer = "";
  let style: LineStyle = "p";
  let footnoteDepth = 0;

  const listStyle = (): LineStyle => (lists.length ? (lists[lists.length - 1] === "ol" ? "number" : "bullet") : "p");
  const flush = () => {
    const text = buffer.replace(/[ \t]+/g, " ").replace(/ ?\n ?/g, "\n").trim();
    if (text) (footnoteDepth > 0 ? footnoteLines : lines).push({ text, style: footnoteDepth > 0 ? "p" : style });
    buffer = "";
  };

  for (const token of tokenize(html)) {
    const name = token.name;
    if (token.kind === "text") {
      buffer += token.text;
    } else if (token.kind === "void") {
      if (name === "br") buffer += "\n";
      if (name === "img") notes.images++;
    } else if (token.kind === "open") {
      stack.push(name);
      if (/^h[1-6]$/.test(name)) {
        flush();
        style = name === "h1" ? "h1" : name === "h2" ? "h2" : "h3";
      } else if (name === "p") {
        flush();
        style = stack.includes("blockquote") ? "quote" : stack.includes("li") ? listStyle() : "p";
      } else if (name === "li") {
        flush();
        if (/id="(?:foot|end)note-\d+"/.test(token.attrs)) {
          footnoteDepth++;
          notes.footnotes++;
        }
        style = listStyle();
      } else if (name === "ul" || name === "ol") {
        flush();
        lists.push(name);
      } else if (name === "blockquote") {
        flush();
        style = "quote";
      } else if (name === "table") {
        flush();
        notes.tables++;
      } else if (name === "td" || name === "th") {
        flush();
        style = "p";
      }
    } else {
      const index = stack.lastIndexOf(name);
      if (index >= 0) stack.splice(index);
      if (/^h[1-6]$/.test(name) || ["p", "li", "td", "th", "blockquote"].includes(name)) {
        flush();
        if (name === "li" && footnoteDepth > 0 && !stack.includes("li")) footnoteDepth = 0;
        style = stack.includes("li") ? listStyle() : stack.includes("blockquote") ? "quote" : "p";
      } else if (name === "ul" || name === "ol") {
        flush();
        lists.pop();
        style = stack.includes("li") ? listStyle() : "p";
      }
    }
  }
  flush();
  return { lines: [...lines, ...footnoteLines], notes };
}
