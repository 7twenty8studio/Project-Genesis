// yvp-web-passage's rules, pure so they're tested in Node: which requests
// are accepted and how a YouVersion chapter becomes the guest page's verses
// (the same shape as the free Bibles' web/v1 files, plus footnotes).
// Nothing changes a word: verse text and notes are as the Platform gives them.
import { BOOKS, type ParsedChapter } from "../yvp-bible/lib.ts";

/** Biblica's display limit: no more than two chapters shown at once. */
export const MAX_CHAPTERS = 2;

export interface PassageRequest {
  /** The catalog id (public.youversion_bibles.id), e.g. "NIV". */
  bible: string;
  /** KJV verse ids (book*1_000_000 + chapter*1_000 + verse), one book. */
  start: number;
  end: number;
  /** USFM book code and the chapters to read, in order. */
  book: string;
  chapters: number[];
}

export interface WebNote {
  /** Where the marker goes in the verse's text (UTF-16 offset). */
  o: number;
  t: string;
}

export interface WebVerse {
  c: number;
  v: number;
  /** The KJV verse ids it holds (YouVersion Bibles number verses as the KJV does). */
  k: number[];
  t: string;
  p?: 1;
  /** Its footnotes, every one (Biblica's licence). */
  n?: WebNote[];
}

function split(id: number): { book: number; chapter: number; verse: number } {
  return { book: Math.floor(id / 1_000_000), chapter: Math.floor(id / 1_000) % 1_000, verse: id % 1_000 };
}

/** The request body, or null. */
export function parsePassageRequest(body: unknown): PassageRequest | null {
  if (!body || typeof body !== "object") return null;
  const { bible, start, end } = body as { bible?: unknown; start?: unknown; end?: unknown };
  if (typeof bible !== "string" || !/^[A-Za-z0-9]{2,8}$/.test(bible)) return null;
  if (typeof start !== "number" || !Number.isInteger(start)) return null;
  const last = end === undefined || end === null ? start : end;
  if (typeof last !== "number" || !Number.isInteger(last) || last < start) return null;
  const a = split(start);
  const b = split(last);
  if (a.book !== b.book || a.book < 1 || a.book > BOOKS.length) return null;
  const [book, count] = BOOKS[a.book - 1];
  if (a.chapter < 1 || b.chapter > count || a.verse < 1 || b.verse < 1) return null;
  if (b.chapter - a.chapter + 1 > MAX_CHAPTERS) return null;
  const chapters = [];
  for (let c = a.chapter; c <= b.chapter; c++) chapters.push(c);
  return { bible, start, end: last, book, chapters };
}

/** The verses of these chapters holding any KJV verse from start to end, with their notes. */
export function webVerses(book: number, chapters: ParsedChapter[], start: number, end: number): WebVerse[] {
  const out: WebVerse[] = [];
  for (const chapter of chapters) {
    for (const verse of chapter.verses) {
      const lastVerse = verse.last ?? verse.verse;
      const k: number[] = [];
      for (let v = verse.verse; v <= lastVerse; v++) k.push(book * 1_000_000 + chapter.chapter * 1_000 + v);
      if (!k.some((id) => id >= start && id <= end)) continue;
      const notes = chapter.notes.filter((n) => n.verse === verse.verse).map((n) => ({ o: n.offset, t: n.text }));
      out.push({
        c: chapter.chapter,
        v: verse.verse,
        k,
        t: verse.text,
        ...(verse.poetry ? { p: 1 as const } : {}),
        ...(notes.length ? { n: notes } : {}),
      });
    }
  }
  return out;
}
