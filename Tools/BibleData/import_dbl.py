#!/usr/bin/env python3
"""Imports a licensed Bible from a Digital Bible Library (DBL) text bundle.

Versely is a DBL distributor. Once a publisher approves a Bible for Versely,
download its *text* bundle from thedigitalbiblelibrary.org (a zip holding
metadata.xml and one USX file per book) and run:

  python3 Tools/BibleData/import_dbl.py --bundle ~/Downloads/NIV_dbl.zip --id NIV \\
      --summary "Accurate and readable, the most read modern English Bible." \\
      --approach balanced --reading-level everyday --popularity 2 \\
      --url https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object/licensed-bibles/NIV-1.sqlite.deflate \\
      --out build/bibles

It writes the same files as package_translation.py: <ID>-<version>.sqlite
.deflate to upload to the private "licensed-bibles" bucket (never the public
"bibles" one: the app gets a ten-minute link from the bible-file function), and <ID>-<version>.sql to run in
the SQL Editor (rights = 'licensed', license = the publisher's copyright
statement from metadata.xml, shown in the app under every chapter). It also
prints a report: the verse numbering compared with the KJV, bridged verses
("16-17") and anything it set aside. Read it before publishing.

Scripture is never changed. From the USX it keeps every word of the verses
and their punctuation, and the translation's own section headings and psalm
titles (shown as headings). It leaves out what isn't verse text: footnotes,
cross references, introductions, book titles and figures. Words marked as
the divine name (\\nd, printed LORD in small capitals) are written in
capitals, as plain-text editions of these Bibles do. Only whitespace is
normalised.

Usage-rights reminder: import only Bibles the DBL shows as licensed to
Versely, and only publish what the licence allows (LICENSED_BIBLES.md).
"""
import argparse
import glob
import hashlib
import os
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
import zipfile
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_bibles import USFX_BOOKS, Verse, clean, create_bible_db  # noqa: E402
from books import BOOKS, verse_id  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KJV_DATABASE = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "KJV.sqlite")

BOOK_NUMBERS = {code: number for number, code in enumerate(USFX_BOOKS, start=1)}

# Paragraph styles that aren't verse text (introductions, titles, references).
SKIPPED_PARAS = re.compile(
    r"^(id|ide|h\d?|toc\d|toca\d|rem|sts|restore|usfm|cl|cd|cp|r|mr|sr|lit|pb|"
    r"imt\d?|imte\d?|is\d?|ip|ipi|im|imi|ipq|imq|ipr|ipc|iq\d?|ib|ili\d?|iot|io\d?|iex|ie|"
    r"mt\d?|mte\d?)$"
)
# The translation's own headings: section headings, speakers, acrostic
# letters and psalm titles ("d", when it holds no verse number).
HEADING_PARAS = re.compile(r"^(ms\d?|s\d?|sp|qa|d)$")
POETRY_PARAS = re.compile(r"^(q\d?|qr|qc|qm\d?|qd)$")
# Styles that open a new paragraph or stanza when a verse starts with them.
PARAGRAPH_STARTS = re.compile(r"^(p|m|po|pi\d?|mi|pc|pr|pm|pmo|pmc|pmr|cls|li\d?|lh|q\d?|qr|qc|qm\d?|qd)$")
# Inline styles to leave out: alternate and published verse/chapter numbers.
SKIPPED_CHARS = {"va", "vp", "ca", "fig"}
SKIPPED_ELEMENTS = {"note", "figure", "fig", "sidebar", "ms", "optbreak", "periph"}


class Report:
    def __init__(self):
        self.warnings = []
        self.skipped_books = []

    def warn(self, message):
        self.warnings.append(message)


def parse_verse_number(value):
    """'16' → (16, 16); '16-17' → (16, 17); '3a' → (3, 3); '3,4' → (3, 4)."""
    numbers = [int(n) for n in re.findall(r"\d+", value or "")]
    if not numbers:
        return None
    return numbers[0], max(numbers)


class BookParser:
    """Walks one USX book in reading order, gathering verses, headings and
    bridged verses. Works with USX 2 (verse starts only) and USX 3 (start
    and end milestones)."""

    def __init__(self, book, report):
        self.book = book
        self.report = report
        self.verses = {}       # (chapter, verse) → Verse
        self.order = []
        self.headings = []     # (book, chapter, before_verse, text)
        self.spans = []        # (first id, last id)
        self.pending_headings = []
        self.pending_text = []
        self.chapter = 0
        self.current = None    # Verse being read
        self.line = []         # this paragraph's text for the current verse
        self.para_style = None
        self.para_has_text = False
        self.stanza_break = True

    # Output helpers

    def flush_line(self):
        text = "".join(self.line)
        self.line = []
        if not text.strip():
            return
        if self.current is None:
            # Words outside any verse inside a body paragraph: never drop
            # them; they join the next verse, and the report says so.
            self.pending_text.append(text)
            self.report.warn(f"{USFX_BOOKS[self.book - 1]} {self.chapter}: text before a verse number joined to the next verse: {clean(text)[:60]!r}")
            return
        self.current.parts.append(text)
        if POETRY_PARAS.match(self.para_style or ""):
            self.current.poetry = True

    def start_verse(self, number_text):
        self.flush_line()
        parsed = parse_verse_number(number_text)
        if parsed is None:
            self.report.warn(f"{USFX_BOOKS[self.book - 1]} {self.chapter}: unreadable verse number {number_text!r}")
            return
        first, last = parsed
        if self.chapter == 0:
            self.report.warn(f"{USFX_BOOKS[self.book - 1]}: verse {first} before any chapter, set aside")
            self.current = None
            return
        key = (self.chapter, first)
        verse = self.verses.get(key)
        if verse is None:
            verse = Verse(self.book, self.chapter, first)
            verse.paragraph = (not self.para_has_text) and bool(PARAGRAPH_STARTS.match(self.para_style or "")) and (
                not POETRY_PARAS.match(self.para_style or "") or self.stanza_break)
            self.verses[key] = verse
            self.order.append(key)
        if last > first:
            self.spans.append((verse_id(self.book, self.chapter, first), verse_id(self.book, self.chapter, last)))
        for heading in self.pending_headings:
            self.headings.append((self.book, self.chapter, first, heading))
        self.pending_headings = []
        if self.pending_text:
            verse.parts.extend(self.pending_text)
            self.pending_text = []
        self.current = verse

    def end_verse(self):
        self.flush_line()
        self.current = None

    def add_text(self, text):
        if text:
            self.line.append(text)
            if text.strip():
                self.para_has_text = True

    # Walking

    def parse(self, root):
        for element in root:
            tag = element.tag
            if tag == "chapter":
                if element.get("number"):
                    self.end_verse()
                    self.chapter = int(re.findall(r"\d+", element.get("number"))[0])
                    self.stanza_break = True
                elif element.get("eid"):
                    self.end_verse()
            elif tag == "para":
                self.para(element)
            elif tag == "table":
                for row in element.iter("row"):
                    for cell in row:
                        self.body(cell, "p")
            elif tag in ("book",) or tag in SKIPPED_ELEMENTS:
                continue
        self.end_verse()
        if self.pending_text:
            self.report.warn(f"{USFX_BOOKS[self.book - 1]}: text after the last verse set aside: {clean(''.join(self.pending_text))[:60]!r}")
        return self

    def para(self, element):
        style = element.get("style", "")
        if style == "b":
            self.stanza_break = True
            return
        if SKIPPED_PARAS.match(style):
            return
        has_verse = element.find(".//verse") is not None
        if HEADING_PARAS.match(style) and not has_verse:
            text = clean(self.inline_text(element))
            if text:
                # A verse can run on past a heading, so the verse stays open.
                self.flush_line()
                self.pending_headings.append(text)
                self.stanza_break = True
            return
        self.body(element, style)

    def body(self, element, style):
        self.flush_line()
        self.para_style = style
        self.para_has_text = False
        self.inline(element, top=True)
        self.flush_line()
        self.stanza_break = not POETRY_PARAS.match(style)

    def inline(self, element, top=False, upper=False):
        def emit(text):
            self.add_text(text.upper() if upper and text else text)

        emit(element.text)
        for child in element:
            tag = child.tag
            if tag == "verse":
                if child.get("sid") or (child.get("number") and not child.get("eid")):
                    self.start_verse(child.get("number"))
                elif child.get("eid"):
                    self.end_verse()
            elif tag == "char" and child.get("style") in SKIPPED_CHARS:
                pass
            elif tag in SKIPPED_ELEMENTS:
                pass
            elif tag == "char":
                self.inline(child, upper=upper or child.get("style") == "nd")
            else:
                # ref, link, jmp, wg/wh/wa, rb, etc.: keep their words.
                self.inline(child, upper=upper)
            emit(child.tail)

    def inline_text(self, element):
        """Heading text (no verse numbers, notes left out)."""
        parts = [element.text or ""]
        for child in element:
            if child.tag not in SKIPPED_ELEMENTS and not (child.tag == "char" and child.get("style") in SKIPPED_CHARS):
                inner = self.inline_text(child)
                parts.append(inner.upper() if child.tag == "char" and child.get("style") == "nd" else inner)
            parts.append(child.tail or "")
        return "".join(parts)


def parse_usx(data, report):
    """Returns (book number, verses, headings, spans) for one USX file, or
    None for a book outside the 66-book canon."""
    root = ET.fromstring(data)
    book_element = root.find("book")
    code = book_element.get("code") if book_element is not None else None
    number = BOOK_NUMBERS.get(code)
    if number is None:
        report.skipped_books.append(code or "?")
        return None
    parser = BookParser(number, report).parse(root)
    verses = [parser.verses[key] for key in sorted(parser.order)]
    empty = [v for v in verses if not v.text]
    for v in empty:
        report.warn(f"{code} {v.chapter}:{v.verse} has no words; left out")
    verses = [v for v in verses if v.text]
    return number, verses, parser.headings, parser.spans


def text_of(element):
    return clean(" ".join(t.strip() for t in element.itertext() if t.strip())) if element is not None else None


def parse_metadata(data):
    """Name, abbreviation, language and copyright statement from a DBL
    metadata.xml (versions 1.x and 2.x)."""
    root = ET.fromstring(data)
    ident = root.find("identification")
    def first(*paths):
        for path in paths:
            value = text_of(root.find(path))
            if value:
                return value
        return None
    iso = first("language/iso", "language/ldml") or ""
    language = {"eng": "en", "spa": "es"}.get(iso[:3], iso[:2])
    copyright_statement = first(
        "copyright/fullStatement/statementContent",
        "copyright/statement",
        "copyright/shortStatement/statementContent",
    )
    return {
        "name": text_of(ident.find("nameLocal")) or text_of(ident.find("name")) if ident is not None else None,
        "english_name": text_of(ident.find("name")) if ident is not None else None,
        "abbreviation": (text_of(ident.find("abbreviationLocal")) or text_of(ident.find("abbreviation"))) if ident is not None else None,
        "language": language,
        "copyright": copyright_statement,
        "dbl_id": root.get("id"),
        "revision": root.get("revision") or first("archiveStatus/revision"),
    }


def read_bundle(path):
    """(metadata.xml bytes, [USX bytes]) from a bundle zip or folder."""
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            meta = next((n for n in names if n.endswith("metadata.xml")), None)
            usx = sorted(n for n in names if n.lower().endswith(".usx"))
            return (archive.read(meta) if meta else None), [archive.read(n) for n in usx]
    meta_path = next(iter(glob.glob(os.path.join(path, "**", "metadata.xml"), recursive=True)), None)
    usx_paths = sorted(glob.glob(os.path.join(path, "**", "*.usx"), recursive=True))
    return (open(meta_path, "rb").read() if meta_path else None), [open(p, "rb").read() for p in usx_paths]


def import_bundle(path, report):
    metadata, usx_files = read_bundle(path)
    if not usx_files:
        sys.exit("No USX files in the bundle. Download the text bundle (USX), not audio or print.")
    verses, headings, spans, books = [], [], [], set()
    for data in usx_files:
        parsed = parse_usx(data, report)
        if parsed is None:
            continue
        number, book_verses, book_headings, book_spans = parsed
        books.add(number)
        verses.extend(book_verses)
        headings.extend(book_headings)
        spans.extend(book_spans)
    verses.sort(key=lambda v: verse_id(v.book, v.chapter, v.verse))
    spans.sort()
    headings.sort(key=lambda h: (h[0], h[1], h[2]))
    meta = parse_metadata(metadata) if metadata else {}
    return meta, verses, headings, spans, books


def compare_with_kjv(verses, spans, report):
    """Verse numbers the KJV has and this Bible doesn't (or the other way
    round), so versification differences are known before publishing."""
    if not os.path.exists(KJV_DATABASE):
        return [], []
    with sqlite3.connect(KJV_DATABASE) as kjv:
        kjv_ids = {row[0] for row in kjv.execute("SELECT id FROM verses")}
    ids = {verse_id(v.book, v.chapter, v.verse) for v in verses}
    covered = set(ids)
    for first, last in spans:
        covered.update(range(first, last + 1))
    missing = sorted(kjv_ids - covered)
    extra = sorted(ids - kjv_ids)
    return missing, extra


def describe(ids, limit=40):
    def name(i):
        return f"{USFX_BOOKS[i // 1_000_000 - 1]} {i // 1000 % 1000}:{i % 1000}"
    shown = ", ".join(name(i) for i in ids[:limit])
    return shown + (f" … ({len(ids)} in all)" if len(ids) > limit else "")


def sql_text(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bundle", required=True, help="DBL text bundle: the downloaded zip, or its unzipped folder")
    parser.add_argument("--id", required=True, help="the Bible's id in Versely, e.g. NIV, NVI, RVR1960 (also its file name)")
    parser.add_argument("--name", help="display name (default: metadata.xml's local name)")
    parser.add_argument("--year", required=True, help="edition year shown in the app, e.g. 2011")
    parser.add_argument("--copyright", help="copyright statement to show (default: metadata.xml's); use the exact wording the licence requires")
    parser.add_argument("--summary", required=True)
    parser.add_argument("--url", required=True, help="the file's URL in the private licensed-bibles bucket: https://<project>.supabase.co/storage/v1/object/licensed-bibles/<ID>-<version>.sqlite.deflate")
    parser.add_argument("--version", type=int, default=1)
    parser.add_argument("--sort", type=int, default=10)
    parser.add_argument("--approach", choices=["word_for_word", "balanced", "thought_for_thought"])
    parser.add_argument("--reading-level", choices=["traditional", "formal", "everyday"])
    parser.add_argument("--popularity", type=int, help="1 = most read in its language")
    parser.add_argument("--out", default="build/bibles")
    args = parser.parse_args()
    if not re.fullmatch(r"https://[^/]+/storage/v1/object/licensed-bibles/[A-Za-z0-9][A-Za-z0-9._-]*\.sqlite\.deflate", args.url):
        sys.exit("--url must point into the private licensed-bibles bucket, e.g. https://<project>.supabase.co/storage/v1/object/licensed-bibles/NIV-1.sqlite.deflate")
    if not re.fullmatch(r"[A-Z0-9]{2,8}", args.id):
        sys.exit("--id must be 2-8 capital letters or digits, e.g. NIV or RVR1960")

    report = Report()
    meta, verses, headings, spans, books = import_bundle(args.bundle, report)
    missing_books = [code for number, code in enumerate(USFX_BOOKS, start=1) if number not in books]
    if missing_books:
        sys.exit(f"The bundle lacks {len(missing_books)} of the 66 books ({', '.join(missing_books[:10])}…). Versely needs a whole Bible.")
    copyright_statement = args.copyright or meta.get("copyright")
    if not copyright_statement:
        sys.exit("No copyright statement in metadata.xml: pass --copyright with the wording the licence requires.")
    name = args.name or meta.get("name") or args.id
    language = meta.get("language") or "en"

    os.makedirs(args.out, exist_ok=True)
    file_name = f"{args.id}-{args.version}"
    database = os.path.join(args.out, f"{file_name}.sqlite")
    create_bible_db(database, args.id, verses, headings, meta={
        "name": name, "year": args.year, "license": copyright_statement, "language": language,
    }, spans=spans)
    raw = open(database, "rb").read()
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    packed = compressor.compress(raw) + compressor.flush()
    open(database + ".deflate", "wb").write(packed)
    assert zlib.decompress(packed, -15) == raw

    statement = (
        "-- Generated by Tools/BibleData/import_dbl.py from the Digital Bible Library"
        + (f" (entry {meta['dbl_id']}, revision {meta.get('revision')})" if meta.get("dbl_id") else "")
        + ". Upload the .deflate file first, then run this.\n"
        "insert into public.bible_translations (id, name, year, license, summary, language, file_url, file_bytes, database_bytes, sha256, version, enabled, sort,\n"
        "  approach, reading_level, rights, popularity, updated_at)\n"
        f"values ({sql_text(args.id)}, {sql_text(name)}, {sql_text(args.year)}, {sql_text(copyright_statement)}, {sql_text(args.summary)}, {sql_text(language)}, "
        f"{sql_text(args.url)}, {len(packed)}, {len(raw)}, {sql_text(hashlib.sha256(raw).hexdigest())}, {args.version}, true, {args.sort},\n"
        f"  {sql_text(args.approach)}, {sql_text(args.reading_level)}, 'licensed', {args.popularity if args.popularity else 'null'}, now())\n"
        "on conflict (id) do update set name = excluded.name, year = excluded.year, license = excluded.license, summary = excluded.summary, language = excluded.language,\n"
        "  file_url = excluded.file_url, file_bytes = excluded.file_bytes, database_bytes = excluded.database_bytes, sha256 = excluded.sha256,\n"
        "  version = excluded.version, enabled = excluded.enabled, sort = excluded.sort,\n"
        "  approach = excluded.approach, reading_level = excluded.reading_level, rights = excluded.rights, popularity = excluded.popularity, updated_at = now();\n"
    )
    open(os.path.join(args.out, f"{file_name}.sql"), "w").write(statement)

    missing, extra = compare_with_kjv(verses, spans, report)
    print(f"{args.id} ({name}, {language}): {len(verses)} verses, {len(headings)} headings, {len(spans)} bridged verses")
    print(f"Copyright shown in the app: {copyright_statement}")
    if spans:
        print(f"Bridged verses: {describe([first for first, _ in spans], 20)}")
    if missing:
        print(f"Verse numbers in the KJV but not here: {describe(missing)}")
    if extra:
        print(f"Verse numbers here but not in the KJV: {describe(extra)}")
    if missing or extra:
        print("  Normal for some Bibles (e.g. Spanish numbering, verses kept in footnotes). The Original-language view stays off for this Bible until it has a versification map (align_versification.py).")
    if report.skipped_books:
        print(f"Books outside the 66 left out: {', '.join(report.skipped_books)}")
    for warning in report.warnings[:50]:
        print(f"  ! {warning}")
    if len(report.warnings) > 50:
        print(f"  ! … {len(report.warnings) - 50} more")
    print(f"Wrote {database}.deflate and {os.path.join(args.out, file_name + '.sql')}")


if __name__ == "__main__":
    main()
