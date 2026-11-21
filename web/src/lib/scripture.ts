// Passages on the guest page (VRS-18), from the free Bibles exported verbatim
// by Tools/BibleData/export_web_chapters.py into the public bibles bucket
// (web/v1/<CODE>/<book>-<chapter>.json, one file per KJV chapter, each verse
// with the KJV verses it holds). Nothing here changes a word: verses are
// shown as the files hold them, in the Bible's own numbering.
import type { TranslationCode } from "./outline.ts";
import { splitVerseID } from "./shared/references.ts";

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
  /** Footnotes (YouVersion Bibles): where each marker goes in `t` (UTF-16 offset) and its text. */
  n?: { o: number; t: string }[];
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
  /** A free Bible's code, or a YouVersion Bible's catalog id ("NIV"). */
  translation: string;
  name: string;
  /** The Bible's language (book names in the credit follow it). */
  language: string;
  license: string;
  verses: ChapterVerse[];
  /** YouVersion Bibles: the publisher's site, linked under the passage (their agreements ask it). */
  publisherUrl?: string | null;
}

/** A YouVersion Bible a sermon page may offer (youversion_web_bibles; text through yvp-web-passage). */
export interface YouVersionBible {
  id: string;
  name: string;
  language: string;
}

/**
 * The Bible a passage opens in: a YouVersion Bible the pastor named ("NIV")
 * when the page offers it, else defaultBible.
 */
export function startingBible(quoted: TranslationCode | null, label: string | null, language: string, youversion: YouVersionBible[]): string {
  const named = label ? youversion.find((b) => b.id.toLowerCase() === label.trim().toLowerCase()) : undefined;
  return named ? named.id : defaultBible(quoted, language);
}

export function isFreeBible(code: string): code is TranslationCode {
  return WEB_BIBLES.some((b) => b.code === code);
}

/** Fetches a YouVersion Bible's passage in the browser (never cached; footnotes included). */
export async function loadYouVersionPassage(supabaseUrl: string, anonKey: string, id: string, start: number, end: number): Promise<Passage> {
  const response = await fetch(`${supabaseUrl}/functions/v1/yvp-web-passage`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ bible: id, start, end }),
    cache: "no-store",
  });
  if (!response.ok) throw new Error(`passage ${response.status}`);
  const body = (await response.json()) as { bible: string; name: string; language: string; license: string; publisherUrl: string | null; verses: ChapterVerse[] };
  return { translation: body.bible, name: body.name, language: body.language, license: body.license, verses: body.verses, publisherUrl: body.publisherUrl };
}

/** A verse's text cut at its footnote markers: text, then the note's index, and so on. */
export function withMarkers(verse: ChapterVerse): (string | number)[] {
  if (!verse.n?.length) return [verse.t];
  const notes = verse.n.map((note, i) => ({ ...note, i })).sort((a, b) => a.o - b.o || a.i - b.i);
  const out: (string | number)[] = [];
  let at = 0;
  for (const note of notes) {
    const o = Math.min(Math.max(note.o, at), verse.t.length);
    if (o > at) out.push(verse.t.slice(at, o));
    out.push(note.i);
    at = o;
  }
  if (at < verse.t.length) out.push(verse.t.slice(at));
  return out;
}

/** Footnote letters: a…z, then aa, ab… */
export function noteLetter(index: number): string {
  const letters = "abcdefghijklmnopqrstuvwxyz";
  return index < 26 ? letters[index] : letters[Math.floor(index / 26) - 1] + letters[index % 26];
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
  return { translation: code, name: files[0].name, language: files[0].language, license: files[0].license, verses: versesFor(files, start, end) };
}
