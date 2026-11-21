// Bible references for the web (Church Studio and the guest sermon page,
// VRS-18): the same reading as the app's ReferenceParser.swift, so "jn 3:16",
// "1 Cor 13:4-7", "Juan 3,16", "Sl 23" or "1ª João 1:9" mean the same passage
// on the web as in the app. Book names and verse counts come from
// bibleBooks.json (generated from BibleBook.swift and the KJV by
// Tools/BibleData/export_reference_books.py). Verse ids use the KJV's
// numbering: book * 1_000_000 + chapter * 1_000 + verse.
//
// Pure: no I/O, no verse text. Shared fixtures in fixtures/references.json.

import data from "./bibleBooks.json" with { type: "json" };

export interface LocalName {
  name: string;
  abbreviation: string;
  aliases: string[];
}

export interface BibleBook {
  id: number;
  osis: string;
  en: LocalName;
  es: LocalName;
  pt: LocalName;
  testament: "old" | "new";
  chapterCount: number;
  /** Verses in each chapter (the KJV's numbering). */
  verses: number[];
}

/** What ReferenceParser.parse returns: a book, a chapter or a verse range in one chapter. */
export interface PassageReference {
  book: BibleBook;
  chapter: number | null;
  verseStart: number | null;
  verseEnd: number | null;
}

export type ReferenceStatus = "verified" | "ambiguous" | "unlinked";

/** A reference as a sermon block stores it (church_sermons draft_blocks `ref`). */
export interface ResolvedReference {
  raw: string;
  start: number | null;
  end: number | null;
  status: ReferenceStatus;
}

export interface ParseOptions {
  /** Brazilian abbreviations win where they clash with English ("Mc" Mark, "Jn" Jonah, "Hb" Hebrews). */
  portugueseFirst?: boolean;
}

export const books: BibleBook[] = (data as { books: BibleBook[] }).books;

export function bookWithNumber(id: number): BibleBook {
  return books[Math.min(Math.max(id, 1), books.length) - 1];
}

// Parsing ------------------------------------------------------------------------

/** Parses a complete reference ("John 3:16"). Null if the text isn't one. */
export function parse(input: string, options: ParseOptions = {}): PassageReference | null {
  const text = normalize(input);
  if (!text) return null;
  const [bookText, numberText] = split(text);
  const book = bookNamed(bookText, options);
  if (!book) return null;

  const numbers = parseNumbers(numberText);
  if (!numbers.valid) return null;
  const first = numbers.chapter;
  if (first === null) return { book, chapter: null, verseStart: null, verseEnd: null };

  // Single-chapter books are cited by verse: "Jude 3" means verse 3.
  if (book.chapterCount === 1 && numbers.verse === null && first > 1) {
    return { book, chapter: 1, verseStart: first, verseEnd: numbers.verseEnd };
  }
  if (first < 1 || first > book.chapterCount) return null;
  if (numbers.verse !== null && numbers.verse < 1) return null;
  if (numbers.verse !== null && numbers.verseEnd !== null && numbers.verseEnd < numbers.verse) return null;
  return { book, chapter: first, verseStart: numbers.verse, verseEnd: numbers.verseEnd };
}

/** Books whose name or abbreviation starts with the typed text, for suggestions while typing. */
export function booksMatching(input: string, options: ParseOptions = {}): BibleBook[] {
  const [bookText, numberText] = split(normalize(input));
  if (!bookText || numberText) return [];
  const accented = accentedBook(bookText);
  if (accented) return [accented];
  const key = compact(bookText);
  const exact = indexFor(options).get(key);
  if (exact) return [exact];
  return books.filter((book) =>
    [...englishKeys(book), ...spanishKeys(book), ...portugueseKeys(book)].some((k) => k.startsWith(key))
  );
}

/** Resolves a book from any accepted spelling. */
export function bookNamed(text: string, options: ParseOptions = {}): BibleBook | null {
  const accented = accentedBook(text);
  if (accented) return accented;
  const key = compact(text);
  if (!key) return null;
  const found = indexFor(options).get(key);
  if (found) return found;
  // An unambiguous prefix of a book name ("gene", "phile").
  if ([...key].length < 3) return null;
  const matches = books.filter((book) => [book.en.name, book.es.name, book.pt.name].some((n) => compact(n).startsWith(key)));
  return matches.length === 1 ? matches[0] : null;
}

// Sermon references ----------------------------------------------------------------

/**
 * What a sermon block stores for typed text: "verified" with the first and
 * last verse ids when it names verses that exist (a whole chapter counts;
 * "John 3:16-4:2" crosses chapters), "ambiguous" when it reads as a book but
 * not as verses that exist (a book alone, John 3:99), and "unlinked"
 * otherwise. Only verified references open a passage.
 */
export function resolve(input: string, options: ParseOptions = {}): ResolvedReference {
  const raw = input.trim().slice(0, 120);
  const unlinked: ResolvedReference = { raw, start: null, end: null, status: "unlinked" };
  const ambiguous: ResolvedReference = { raw, start: null, end: null, status: "ambiguous" };
  const text = normalize(input);
  if (!text) return unlinked;
  const [bookText, numberText] = split(text);
  const book = bookNamed(bookText, options);
  if (!book) return unlinked;

  // "John 3:16-4:2": a range across chapters.
  const across = /^(\d+)\s*[:.,]\s*(\d+)\s*-\s*(\d+)\s*[:.,]\s*(\d+)$/.exec(numberText);
  if (across) {
    const [c1, v1, c2, v2] = across.slice(1).map(Number);
    if (!exists(book, c1, v1) || !exists(book, c2, v2) || c2 < c1 || (c2 === c1 && v2 < v1)) return ambiguous;
    return { raw, start: verseID(book.id, c1, v1), end: verseID(book.id, c2, v2), status: "verified" };
  }

  const ref = parse(input, options);
  if (!ref) return numberText ? ambiguous : unlinked;
  if (ref.chapter === null) return ambiguous;
  const chapter = ref.chapter;
  if (ref.verseStart === null) {
    return { raw, start: verseID(book.id, chapter, 1), end: verseID(book.id, chapter, book.verses[chapter - 1]), status: "verified" };
  }
  const last = ref.verseEnd ?? ref.verseStart;
  if (!exists(book, chapter, ref.verseStart) || !exists(book, chapter, last)) return ambiguous;
  return { raw, start: verseID(book.id, chapter, ref.verseStart), end: verseID(book.id, chapter, last), status: "verified" };
}

export function verseID(book: number, chapter: number, verse: number): number {
  return book * 1_000_000 + chapter * 1_000 + verse;
}

export function splitVerseID(id: number): { book: number; chapter: number; verse: number } {
  return { book: Math.floor(id / 1_000_000), chapter: Math.floor(id / 1_000) % 1_000, verse: id % 1_000 };
}

/** A verse id that exists in the KJV's numbering. */
export function isValidVerseID(id: number): boolean {
  if (!Number.isInteger(id)) return false;
  const { book, chapter, verse } = splitVerseID(id);
  return book >= 1 && book <= 66 && exists(bookWithNumber(book), chapter, verse);
}

/**
 * A verse range named in a language ("en", "es", "pt"), as the app writes it:
 * "John 3:16–18", "Juan 3:16", "Jude 3", "Psalms 23" (a whole chapter),
 * "John 3:16–4:2".
 */
export function describe(start: number, end: number = start, language = "en"): string {
  const a = splitVerseID(start);
  const b = splitVerseID(end);
  const book = bookWithNumber(a.book);
  const name = localName(book, language).name;
  if (book.chapterCount > 1 && a.chapter === b.chapter && a.verse === 1 && b.verse === book.verses[a.chapter - 1]) {
    return `${name} ${a.chapter}`;
  }
  const prefix = book.chapterCount === 1 ? `${name} ` : `${name} ${a.chapter}:`;
  if (a.chapter !== b.chapter) return `${prefix}${a.verse}–${b.chapter}:${b.verse}`;
  if (b.verse !== a.verse) return `${prefix}${a.verse}–${b.verse}`;
  return `${prefix}${a.verse}`;
}

export function localName(book: BibleBook, language: string): LocalName {
  if (language.startsWith("es")) return book.es;
  if (language.startsWith("pt")) return book.pt;
  return book.en;
}

// Internals ------------------------------------------------------------------------

function exists(book: BibleBook, chapter: number, verse: number): boolean {
  return chapter >= 1 && chapter <= book.chapterCount && verse >= 1 && verse <= book.verses[chapter - 1];
}

const ordinals: [string, string][] = [
  ["first ", "1"], ["second ", "2"], ["third ", "3"],
  ["1st ", "1"], ["2nd ", "2"], ["3rd ", "3"],
  ["primera de ", "1"], ["segunda de ", "2"], ["tercera de ", "3"],
  ["primera ", "1"], ["primero ", "1"], ["segunda ", "2"], ["segundo ", "2"], ["tercera ", "3"], ["tercero ", "3"],
  ["1ra ", "1"], ["1ro ", "1"], ["2da ", "2"], ["2do ", "2"], ["3ra ", "3"], ["3ro ", "3"],
  ["primeira ", "1"], ["primeiro ", "1"], ["terceira ", "3"], ["terceiro ", "3"],
  ["1ª ", "1"], ["1º ", "1"], ["2ª ", "2"], ["2º ", "2"], ["3ª ", "3"], ["3º ", "3"],
  ["iii ", "3"], ["ii ", "2"], ["i ", "1"],
];

function normalize(input: string): string {
  let text = input.normalize("NFC").toLowerCase().replace(/–|—/g, "-").trim();
  for (const [prefix, digit] of ordinals) {
    if (text.startsWith(prefix)) {
      text = digit + text.slice(prefix.length);
      break;
    }
  }
  return text;
}

const isLetter = (c: string) => /\p{L}/u.test(c);
const isNumber = (c: string) => /\p{N}/u.test(c);

/** "1 cor 13:4-7" → ["1 cor", "13:4-7"]. A leading 1–3 belongs to the book when letters follow it. */
function split(text: string): [string, string] {
  const characters = [...text];
  let index = 0;
  if (characters.length > 0 && "123".includes(characters[0])) {
    let lookahead = 1;
    while (lookahead < characters.length && characters[lookahead] === " ") lookahead += 1;
    if (lookahead < characters.length && isLetter(characters[lookahead])) index = lookahead;
  }
  while (index < characters.length && (isLetter(characters[index]) || characters[index] === " " || characters[index] === ".")) {
    index += 1;
  }
  const book = characters.slice(0, index).join("").replace(/\./g, " ");
  return [book.trim(), characters.slice(index).join("").trim()];
}

interface Numbers {
  chapter: number | null;
  verse: number | null;
  verseEnd: number | null;
  valid: boolean;
}

/** "3", "3:16", "3.16", "3,16", "3 16", "3:16-18" or "3:16-4:2" (end chapter ignored, as in the app). */
function parseNumbers(text: string): Numbers {
  const result: Numbers = { chapter: null, verse: null, verseEnd: null, valid: true };
  if (!text) return result;
  const characters = [...text];
  let index = 0;
  const skipSpaces = () => {
    while (index < characters.length && characters[index] === " ") index += 1;
  };
  const readNumber = (): number | null => {
    const start = index;
    while (index < characters.length && isNumber(characters[index])) index += 1;
    if (index === start) return null;
    const digits = characters.slice(start, index).join("");
    return /^[0-9]+$/.test(digits) ? Number(digits) : null;
  };

  const chapter = readNumber();
  if (chapter === null) return { ...result, valid: false };
  result.chapter = chapter;
  skipSpaces();
  if (index < characters.length && [":", ".", ","].includes(characters[index])) {
    index += 1;
    skipSpaces();
  }
  if (index < characters.length && isNumber(characters[index])) {
    result.verse = readNumber();
    skipSpaces();
    if (index < characters.length && characters[index] === "-") {
      index += 1;
      skipSpaces();
      const end = readNumber();
      // "3:16-4:2": the number after "-" was a chapter; keep the start verse only.
      if (index < characters.length && characters[index] === ":") index = characters.length;
      else result.verseEnd = end;
    }
  }
  skipSpaces();
  if (index < characters.length) result.valid = false;
  return result;
}

/** Lowercase, without spaces, dots or accents: "1 Crónicas" → "1cronicas". */
function compact(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replace(/[\s.]/g, "");
}

const englishKeys = (book: BibleBook) => [book.en.name, book.en.abbreviation, book.osis, ...book.en.aliases].map(compact);
const spanishKeys = (book: BibleBook) => [book.es.name, book.es.abbreviation, ...book.es.aliases].map(compact);
/** Job is "Jó" and John "Jo" in Portuguese, which fold to the same key: "jo" is John. */
const portugueseKeys = (book: BibleBook) =>
  [book.pt.name, book.pt.abbreviation, ...book.pt.aliases].map(compact).filter((k) => !(book.id === JOB && k === "jo"));
const JOB = 18;

function accentedBook(text: string): BibleBook | null {
  const spelled = text.normalize("NFC").toLowerCase().replace(/[\s.]/g, "");
  return spelled === "jó" ? bookWithNumber(JOB) : null;
}

const indexes = new Map<boolean, Map<string, BibleBook>>();

/** English, then Spanish, then Portuguese; Portuguese first for a Portuguese page. */
function indexFor(options: ParseOptions): Map<string, BibleBook> {
  const portugueseFirst = options.portugueseFirst ?? false;
  let index = indexes.get(portugueseFirst);
  if (index) return index;
  index = new Map();
  const layers = portugueseFirst ? [portugueseKeys, englishKeys, spanishKeys] : [englishKeys, spanishKeys, portugueseKeys];
  for (const keysOf of layers) {
    for (const book of books) {
      for (const key of keysOf(book)) if (!index.has(key)) index.set(key, book);
    }
  }
  indexes.set(portugueseFirst, index);
  return index;
}
