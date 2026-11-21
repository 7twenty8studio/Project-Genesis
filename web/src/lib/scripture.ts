// Passages on the guest page (VRS-18), from the free Bibles exported verbatim
// by Tools/BibleData/export_web_chapters.py into the public bibles bucket
// (web/v1/<CODE>/<book>-<chapter>.json, one file per KJV chapter, each verse
// with the KJV verses it holds). Nothing here changes a word: verses are
// shown as the files hold them, in the Bible's own numbering.
import type { TranslationCode } from "./outline";
import { splitVerseID } from "./shared/references";

export const WEB_BIBLES: { code: TranslationCode; name: string; language: "en" | "es" | "pt" }[] = [
  { code: "WEB", name: "World English Bible", language: "en" },
  { code: "KJV", name: "King James Version", language: "en" },
  { code: "ASV", name: "American Standard Version", language: "en" },
  { code: "RV1909", name: "Reina-Valera 1909", language: "es" },
  { code: "BLIVRE", name: "Bíblia Livre", language: "pt" },
];

export interface ChapterVerse {
  /** The Bible's own chapter and verse number. */
  c: number;
  v: number;
  /** The KJV verse ids this verse holds (in this KJV chapter). */
  k: number[];
  t: string;
  /** Poetry: lines separated by \n. */
  p?: 1;
}

export interface ChapterFile {
  format: number;
  translation: TranslationCode;
  name: string;
  language: string;
  license: string;
  book: number;
  chapter: number;
  verses: ChapterVerse[];
}

export interface Passage {
  translation: TranslationCode;
  name: string;
  license: string;
  verses: ChapterVerse[];
}

/** The Bible a passage opens in: the one quoted, else the outline's language's free Bible. */
export function defaultBible(quoted: TranslationCode | null, language: string): TranslationCode {
  if (quoted) return quoted;
  if (language === "es") return "RV1909";
  if (language === "pt") return "BLIVRE";
  return "WEB";
}

/** The KJV chapters a verse range (KJV ids, one book) covers, in order. */
export function chaptersFor(start: number, end: number): { book: number; chapter: number }[] {
  const a = splitVerseID(start);
  const b = splitVerseID(end);
  const out = [];
  for (let c = a.chapter; c <= b.chapter; c++) out.push({ book: a.book, chapter: c });
  return out;
}

/**
 * The verses of a Bible holding any KJV verse from start to end, each once,
 * in the Bible's order. A verse holding two KJV verses (Acts 19:40 in the
 * Reina-Valera) is shown whole; a KJV verse a Bible leaves empty is simply
 * not there.
 */
export function versesFor(files: ChapterFile[], start: number, end: number): ChapterVerse[] {
  const seen = new Set<string>();
  const out: ChapterVerse[] = [];
  for (const file of files) {
    for (const verse of file.verses) {
      if (!verse.k.some((k) => k >= start && k <= end)) continue;
      const key = `${verse.c}:${verse.v}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(verse);
    }
  }
  return out.sort((x, y) => x.c - y.c || x.v - y.v);
}

/** The Bible's own reference for the verses shown ("13:1", "3:16–18", "14:24–26"). */
export function ownRange(verses: ChapterVerse[]): string {
  if (verses.length === 0) return "";
  const first = verses[0];
  const last = verses[verses.length - 1];
  if (first.c !== last.c) return `${first.c}:${first.v}–${last.c}:${last.v}`;
  return first.v === last.v ? `${first.c}:${first.v}` : `${first.c}:${first.v}–${last.v}`;
}

export function chapterURL(supabaseUrl: string, code: TranslationCode, book: number, chapter: number): string {
  return `${supabaseUrl}/storage/v1/object/public/bibles/web/v1/${code}/${book}-${chapter}.json`;
}

/** Fetches a passage in the browser (public files, cached by the browser). */
export async function loadPassage(supabaseUrl: string, code: TranslationCode, start: number, end: number): Promise<Passage> {
  const files = await Promise.all(
    chaptersFor(start, end).map(async ({ book, chapter }) => {
      const response = await fetch(chapterURL(supabaseUrl, code, book, chapter));
      if (!response.ok) throw new Error(`passage ${response.status}`);
      return (await response.json()) as ChapterFile;
    }),
  );
  return { translation: code, name: files[0].name, license: files[0].license, verses: versesFor(files, start, end) };
}
