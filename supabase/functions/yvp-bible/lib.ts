// Pure helpers for yvp-bible (Node tests in lib.test.ts).
//
// A YouVersion Platform chapter arrives as HTML:
//   <div><div class="s1 yv-h">Heading</div>
//        <div class="p"><span class="yv-v" v="1"></span><span class="yv-vlbl">1</span>Words <span class="nd">Lord</span>…</div>
//        <div class="q1">…</div></div>
// The classes are USFM paragraph and character styles. This turns a chapter
// into the app's Bible format with the same rules as the Digital Bible
// Library importer (Tools/BibleData/import_dbl.py), so a YouVersion Bible
// reads like every other Bible in Versely:
//   - every word and punctuation mark of the verses is kept as given; only
//     whitespace is normalised;
//   - words marked as the divine name (nd, and the small capitals "sc" the
//     Lockman Bibles use for LORD) are written in capitals, as plain-text
//     editions print them;
//   - the translation's own headings and psalm titles are kept; chapter
//     labels, parallel references, verse labels and notes are left out;
//   - poetry lines are separated by "\n"; bridged verses ("16-17") are kept
//     on their first verse with `last`; verses with no words are left out.

export interface ParsedVerse {
  verse: number;
  /** Set for a bridged verse ("16-17"): the last verse it holds. */
  last?: number;
  text: string;
  paragraph: boolean;
  poetry: boolean;
}

export interface ParsedHeading {
  beforeVerse: number;
  text: string;
}

export interface ParsedChapter {
  chapter: number;
  verses: ParsedVerse[];
  headings: ParsedHeading[];
}

/** The 66 books in the app's order: USFM code and the KJV's chapter count. */
export const BOOKS: ReadonlyArray<readonly [string, number]> = [
  ["GEN", 50], ["EXO", 40], ["LEV", 27], ["NUM", 36], ["DEU", 34], ["JOS", 24], ["JDG", 21], ["RUT", 4],
  ["1SA", 31], ["2SA", 24], ["1KI", 22], ["2KI", 25], ["1CH", 29], ["2CH", 36], ["EZR", 10], ["NEH", 13],
  ["EST", 10], ["JOB", 42], ["PSA", 150], ["PRO", 31], ["ECC", 12], ["SNG", 8], ["ISA", 66], ["JER", 52],
  ["LAM", 5], ["EZK", 48], ["DAN", 12], ["HOS", 14], ["JOL", 3], ["AMO", 9], ["OBA", 1], ["JON", 4],
  ["MIC", 7], ["NAM", 3], ["HAB", 3], ["ZEP", 3], ["HAG", 2], ["ZEC", 14], ["MAL", 4],
  ["MAT", 28], ["MRK", 16], ["LUK", 24], ["JHN", 21], ["ACT", 28], ["ROM", 16], ["1CO", 16], ["2CO", 13],
  ["GAL", 6], ["EPH", 6], ["PHP", 4], ["COL", 4], ["1TH", 5], ["2TH", 3], ["1TI", 6], ["2TI", 4],
  ["TIT", 3], ["PHM", 1], ["HEB", 13], ["JAS", 5], ["1PE", 5], ["2PE", 3], ["1JN", 5], ["2JN", 1],
  ["3JN", 1], ["JUD", 1], ["REV", 22],
];

export interface BookRequest {
  /** The catalog id (public.youversion_bibles.id), e.g. "NIV". */
  id: string;
  /** USFM book code, e.g. "GEN". */
  book: string;
}

/** The request body, or null. */
export function parseRequest(body: unknown): BookRequest | null {
  if (!body || typeof body !== "object") return null;
  const { id, book } = body as { id?: unknown; book?: unknown };
  // Catalog ids keep the publisher's casing ("NIrV").
  if (typeof id !== "string" || !/^[A-Za-z0-9]{2,8}$/.test(id)) return null;
  if (typeof book !== "string" || !BOOKS.some(([code]) => code === book)) return null;
  return { id, book };
}

/** How many chapters the KJV gives a book (the request tries one more). */
export function chapterCount(book: string): number {
  return BOOKS.find(([code]) => code === book)?.[1] ?? 0;
}

// Paragraph styles that aren't verse text (titles, chapter labels, references).
const SKIPPED_PARAS = /^(id|ide|h\d?|toc\d|toca\d|rem|sts|restore|usfm|cl|cd|cp|r|mr|sr|lit|pb|imt\d?|imte\d?|is\d?|ip|ipi|im|imi|ipq|imq|ipr|ipc|iq\d?|ib|ili\d?|iot|io\d?|iex|ie|mt\d?|mte\d?)$/;
// The translation's own headings: section headings, speakers, acrostic
// letters and psalm titles ("d", when it holds no verse number).
const HEADING_PARAS = /^(ms\d?|s\d?|sp|qa|d)$/;
const POETRY_PARAS = /^(q\d?|qr|qc|qm\d?|qd)$/;
// Styles that open a new paragraph or stanza when a verse starts with them.
const PARAGRAPH_STARTS = /^(p|m|po|pi\d?|mi|pc|pr|pm|pmo|pmc|pmr|cls|li\d?|lh|q\d?|qr|qc|qm\d?|qd)$/;
// Character styles whose words are left out: verse labels, alternate and
// published numbers, footnotes and cross references.
const SKIPPED_CHARS = /^(yv-vlbl|yv-n|va|vp|ca|fig|note|f|fe|x|ft|fr|fq|fqa|xo|xt)$/;
// Character styles printed in small capitals for the divine name.
const DIVINE_NAME = /^(nd|sc)$/;

const SPACES = /[ \t   ]+/g;

/** Whitespace-only normalisation. Never alters words or punctuation. */
export function clean(text: string): string {
  return text
    .split("\n")
    .map((line) => line.replace(SPACES, " ").trim())
    .filter((line) => line.length > 0)
    .join("\n");
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };

function decode(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, name: string) => {
    if (name[0] === "#") {
      const code = name[1] === "x" || name[1] === "X" ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : whole;
    }
    return ENTITIES[name.toLowerCase()] ?? whole;
  });
}

interface Node {
  tag: string;
  classes: string[];
  attrs: Record<string, string>;
  children: (Node | string)[];
}

/** A small HTML reader for YouVersion's markup (divs and spans only). */
export function parseHTML(html: string): Node {
  const root: Node = { tag: "#root", classes: [], attrs: {}, children: [] };
  const stack: Node[] = [root];
  const pattern = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(\/?)>|([^<]+)/g;
  for (const match of html.matchAll(pattern)) {
    const [, closing, tag, rawAttrs, selfClosing, text] = match;
    const top = stack[stack.length - 1];
    if (text !== undefined) {
      top.children.push(decode(text));
      continue;
    }
    const name = tag.toLowerCase();
    if (closing) {
      // Close the nearest open element with this name.
      for (let i = stack.length - 1; i > 0; i--) {
        if (stack[i].tag === name) {
          stack.length = i;
          break;
        }
      }
      continue;
    }
    const attrs: Record<string, string> = {};
    for (const a of rawAttrs.matchAll(/([a-zA-Z_:-][a-zA-Z0-9_:.-]*)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/g)) {
      attrs[a[1].toLowerCase()] = decode(a[3] ?? a[4] ?? a[5] ?? "");
    }
    const node: Node = { tag: name, classes: (attrs["class"] ?? "").split(/\s+/).filter(Boolean), attrs, children: [] };
    top.children.push(node);
    if (!selfClosing && name !== "br") stack.push(node);
  }
  return root;
}

/** A block's USFM style: its first class that isn't YouVersion's own. */
function styleOf(node: Node): string {
  return node.classes.find((c) => !c.startsWith("yv-")) ?? "";
}

function isVerseMark(node: Node): boolean {
  return node.tag === "span" && node.classes.includes("yv-v");
}

function containsVerse(node: Node): boolean {
  return node.children.some((child) => typeof child !== "string" && (isVerseMark(child) || containsVerse(child)));
}

/** '16' → [16, 16]; '16-17' → [16, 17]; '3a' → [3, 3]; '[37]' → [37, 37]. */
export function verseNumbers(value: string): [number, number] | null {
  const numbers = (value.match(/\d+/g) ?? []).map(Number);
  if (numbers.length === 0) return null;
  return [numbers[0], Math.max(...numbers)];
}

interface Building {
  verse: number;
  last: number;
  parts: string[];
  paragraph: boolean;
  poetry: boolean;
}

/**
 * One chapter's HTML (format=html&include_headings=true) in the app's
 * format. `reference` is the API's label for the chapter ("Salmo 23"): a
 * heading that only repeats it is a chapter label and is left out.
 */
export function parseChapter(chapter: number, html: string, reference = ""): ParsedChapter {
  const verses = new Map<number, Building>();
  const headings: ParsedHeading[] = [];
  let pendingHeadings: string[] = [];
  let pendingText: string[] = [];
  let current: Building | null = null;
  let line: string[] = [];
  let style = "";
  let blockHasText = false;
  let stanzaBreak = true;
  const label = clean(reference).toLowerCase();

  const flushLine = () => {
    const text = line.join("");
    line = [];
    if (!text.trim()) return;
    if (!current) {
      pendingText.push(text);
      return;
    }
    current.parts.push(text);
    if (POETRY_PARAS.test(style)) current.poetry = true;
  };

  const startVerse = (value: string, labelText: string) => {
    flushLine();
    const fromMark = verseNumbers(value);
    const fromLabel = verseNumbers(labelText);
    if (!fromMark) return;
    const first = fromMark[0];
    // The label can show a bridge ("16-17") the mark doesn't.
    const last = Math.max(fromMark[1], fromLabel && fromLabel[0] === first ? fromLabel[1] : first);
    let verse = verses.get(first);
    if (!verse) {
      verse = {
        verse: first,
        last,
        parts: [],
        paragraph: !blockHasText && PARAGRAPH_STARTS.test(style) && (!POETRY_PARAS.test(style) || stanzaBreak),
        poetry: false,
      };
      verses.set(first, verse);
    } else {
      verse.last = Math.max(verse.last, last);
    }
    for (const heading of pendingHeadings) headings.push({ beforeVerse: first, text: heading });
    pendingHeadings = [];
    if (pendingText.length > 0) {
      verse.parts.push(...pendingText);
      pendingText = [];
    }
    current = verse;
  };

  const addText = (text: string) => {
    if (!text) return;
    line.push(text);
    if (text.trim()) blockHasText = true;
  };

  // The text of a verse label that follows a verse mark, if any.
  const labelAfter = (siblings: (Node | string)[], index: number): string => {
    for (let i = index + 1; i < siblings.length; i++) {
      const next = siblings[i];
      if (typeof next === "string") {
        if (next.trim()) return "";
        continue;
      }
      return next.classes.includes("yv-vlbl") ? textOf(next, false) : "";
    }
    return "";
  };

  const inline = (node: Node, upper: boolean) => {
    node.children.forEach((child, index) => {
      if (typeof child === "string") {
        addText(upper ? child.toUpperCase() : child);
        return;
      }
      if (isVerseMark(child)) {
        startVerse(child.attrs["v"] ?? "", labelAfter(node.children, index));
        return;
      }
      if (child.tag === "br") {
        addText(" ");
        return;
      }
      if (child.tag === "div") {
        // A block inside a block (a table row, say): its own paragraph.
        block(child);
        return;
      }
      const charStyle = styleOf(child) || child.classes[0] || "";
      if (SKIPPED_CHARS.test(charStyle) || child.classes.some((c) => SKIPPED_CHARS.test(c))) return;
      inline(child, upper || child.classes.some((c) => DIVINE_NAME.test(c)));
    });
  };

  const body = (node: Node) => {
    flushLine();
    style = styleOf(node);
    blockHasText = false;
    inline(node, false);
    flushLine();
    stanzaBreak = !POETRY_PARAS.test(style);
  };

  const block = (node: Node) => {
    const blockStyle = styleOf(node);
    if (blockStyle === "b") {
      stanzaBreak = true;
      return;
    }
    if (SKIPPED_PARAS.test(blockStyle)) return;
    const isHeading = (HEADING_PARAS.test(blockStyle) || node.classes.includes("yv-h")) && !containsVerse(node);
    if (isHeading) {
      const text = clean(textOf(node, false));
      if (text && text.toLowerCase() !== label) {
        // A verse can run on past a heading, so the verse stays open.
        flushLine();
        pendingHeadings.push(text);
        stanzaBreak = true;
      }
      return;
    }
    body(node);
  };

  const root = parseHTML(html);
  // The chapter is wrapped in one outer <div>; its children are the blocks.
  const blocks = root.children.length === 1 && typeof root.children[0] !== "string" && root.children[0].tag === "div"
    ? root.children[0].children
    : root.children;
  for (const child of blocks) {
    if (typeof child === "string") {
      if (child.trim()) {
        style = "";
        addText(child);
        flushLine();
      }
      continue;
    }
    if (child.tag === "div") block(child);
    else {
      // Stray inline content at the top level.
      style = "";
      inline({ tag: "div", classes: [], attrs: {}, children: [child] }, false);
      flushLine();
    }
  }
  flushLine();

  const parsed: ParsedVerse[] = [];
  for (const verse of [...verses.values()].sort((a, b) => a.verse - b.verse)) {
    const text = clean(verse.parts.join(verse.poetry ? "\n" : " "));
    if (!text) continue; // a number with no words ("[37]")
    const entry: ParsedVerse = { verse: verse.verse, text, paragraph: verse.paragraph, poetry: verse.poetry };
    if (verse.last > verse.verse) entry.last = verse.last;
    parsed.push(entry);
  }
  const kept = new Set(parsed.map((v) => v.verse));
  return { chapter, verses: parsed, headings: headings.filter((h) => kept.has(h.beforeVerse)) };
}

/** A heading's or label's words (verse labels and notes left out). */
function textOf(node: Node, upper: boolean): string {
  let out = "";
  for (const child of node.children) {
    if (typeof child === "string") {
      out += upper ? child.toUpperCase() : child;
      continue;
    }
    if (isVerseMark(child)) continue;
    const skip = child.classes.some((c) => SKIPPED_CHARS.test(c) && c !== "yv-vlbl");
    if (skip) continue;
    out += textOf(child, upper || child.classes.some((c) => DIVINE_NAME.test(c)));
  }
  return out;
}
