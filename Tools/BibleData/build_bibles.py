#!/usr/bin/env python3
"""Builds the offline Bible databases bundled with Genesis.

Each translation becomes its own SQLite file so it can later be downloaded
independently. Scripture text is copied verbatim from the source: this script
only changes whitespace (trimming, collapsing runs of spaces) and never edits
words or punctuation.

Sources (public domain text):
  KJV, ASV  https://github.com/scrollmapper/bible_databases  (formats/json)
  WEB       https://github.com/TehShrike/world-english-bible  (json/)
  Cross references: OpenBible.info (CC-BY), via scrollmapper
                    sources/extras/cross_references.txt

Usage:
  python3 build_bibles.py --scrollmapper PATH --web PATH --out PATH
"""
import argparse
import json
import os
import re
import sqlite3

from books import BOOKS, OSIS_TO_NUMBER, verse_id

SCHEMA_VERSION = 1

TRANSLATIONS = {
    "KJV": {
        "name": "King James Version",
        "year": "1769",
        "license": "Public domain",
        "language": "en",
    },
    "ASV": {
        "name": "American Standard Version",
        "year": "1901",
        "license": "Public domain",
        "language": "en",
    },
    "BSB": {
        "name": "Berean Standard Bible",
        "year": "2023",
        "license": "Public domain (dedicated April 30, 2023). With thanks to Bible Hub, Discovery Bible, OpenBible.com and the Berean Bible Translation Committee.",
        "language": "en",
    },
    "RV1909": {
        "name": "Reina-Valera 1909",
        "year": "1909",
        # Shown as written, so in the Bible's language.
        "license": "Dominio público",
        "language": "es",
        # From github.com/seven1m/open-bibles (spa-rv1909.usfx.xml), which keeps
        # the Spanish verse numbering (Jonah 2 has 11 verses). Not
        # scrollmapper's SpaRV, which drops the verses where Spanish and
        # English numbering differ.
        "usfx": "spa-rv1909.usfx.xml",
    },
    "WEB": {
        "name": "World English Bible",
        "year": "2020",
        "license": "Public domain. “World English Bible” is a trademark of eBible.org.",
        "language": "en",
    },
}

WEB_FILES = {
    1: "genesis", 2: "exodus", 3: "leviticus", 4: "numbers", 5: "deuteronomy",
    6: "joshua", 7: "judges", 8: "ruth", 9: "1samuel", 10: "2samuel",
    11: "1kings", 12: "2kings", 13: "1chronicles", 14: "2chronicles", 15: "ezra",
    16: "nehemiah", 17: "esther", 18: "job", 19: "psalms", 20: "proverbs",
    21: "ecclesiastes", 22: "songofsolomon", 23: "isaiah", 24: "jeremiah",
    25: "lamentations", 26: "ezekiel", 27: "daniel", 28: "hosea", 29: "joel",
    30: "amos", 31: "obadiah", 32: "jonah", 33: "micah", 34: "nahum",
    35: "habakkuk", 36: "zephaniah", 37: "haggai", 38: "zechariah", 39: "malachi",
    40: "matthew", 41: "mark", 42: "luke", 43: "john", 44: "acts", 45: "romans",
    46: "1corinthians", 47: "2corinthians", 48: "galatians", 49: "ephesians",
    50: "philippians", 51: "colossians", 52: "1thessalonians", 53: "2thessalonians",
    54: "1timothy", 55: "2timothy", 56: "titus", 57: "philemon", 58: "hebrews",
    59: "james", 60: "1peter", 61: "2peter", 62: "1john", 63: "2john",
    64: "3john", 65: "jude", 66: "revelation",
}

SPACES = re.compile(r"[ \t ]+")


HYPHENS = "‐‑–-"
HYPHENATED = re.compile(r"\w+(?:[" + HYPHENS + r"]\w+)+")


def search_form(text: str) -> str:
    """Index-only text, never displayed. Hyphenated names such as
    "Beth–lehem" are indexed both joined ("Bethlehem") and split, so
    either spelling finds them."""
    def expand(match):
        word = match.group(0)
        return word + " " + re.sub("[" + HYPHENS + "]", "", word)
    return HYPHENATED.sub(expand, text)


def clean(text: str) -> str:
    """Whitespace-only normalisation. Never alters words or punctuation."""
    lines = [SPACES.sub(" ", line).strip() for line in text.split("\n")]
    return "\n".join(line for line in lines if line)


class Verse:
    __slots__ = ("book", "chapter", "verse", "parts", "paragraph", "poetry")

    def __init__(self, book, chapter, verse):
        self.book, self.chapter, self.verse = book, chapter, verse
        self.parts = []
        self.paragraph = False  # verse begins a new paragraph
        self.poetry = False     # verse is set as poetry lines

    @property
    def text(self):
        sep = "\n" if self.poetry else " "
        return clean(sep.join(self.parts))


USFX_BOOKS = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH",
    "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS",
    "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL",
    "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH",
    "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]


def load_usfx(path):
    """Verses from a USFX file (open-bibles). Word tags (<w>, Strong's
    numbers) and supplied-word tags (<add>) are removed, keeping their words;
    the text itself is not changed. Verses with no words (a number the
    translation doesn't use) are left out."""
    import re as _re
    source = open(path, encoding="utf-8-sig").read()
    verses = []
    for number, code in enumerate(USFX_BOOKS, start=1):
        start = source.find(f'<book id="{code}">')
        assert start >= 0, f"{code} missing"
        end = source.find("</book>", start)
        book = source[start:end]
        assert "<f " not in book and "<f>" not in book and "<x" not in book, f"{code}: footnotes need handling"
        chapter = 0
        # Split into tokens: chapter markers, verse markers, verse ends, text.
        for token in _re.split(r'(<c id="\d+"\s*/>|<v id="\d+"\s*/>|<ve\s*/>)', book):
            c = _re.match(r'<c id="(\d+)"', token)
            v = _re.match(r'<v id="(\d+)"', token)
            if c:
                chapter = int(c.group(1))
            elif v:
                verse = Verse(number, chapter, int(v.group(1)))
                verses.append(verse)
            elif token.startswith("<ve") or not verses or verses[-1].book != number:
                continue
            else:
                current = verses[-1]
                if current.parts and current.parts[-1] is None:
                    continue  # after <ve/>: text between verses (headings) isn't verse text
                text = _re.sub(r"</?(w|add)\b[^>]*>", "", token)
                text = _re.sub(r"</?p\b[^>]*>", " ", text)
                assert "<" not in text, f"unexpected markup in {code} {chapter}:{current.verse}: {text[:80]}"
                current.parts.append(text)
            if token.startswith("<ve"):
                if verses and verses[-1].book == number:
                    verses[-1].parts.append(None)
        for verse in verses:
            verse.parts = [part for part in verse.parts if part is not None]
    return [v for v in verses if v.text.strip()], []


def load_scrollmapper(path, abbreviation):
    usfx = TRANSLATIONS.get(abbreviation, {}).get("usfx")
    if usfx:
        return load_usfx(os.path.join(path, usfx))
    data = json.load(open(os.path.join(path, "formats", "json", f"{abbreviation}.json")))
    assert len(data["books"]) == 66, "expected the 66-book canon"
    verses = []
    for number, book in enumerate(data["books"], start=1):
        for chapter in book["chapters"]:
            for v in chapter["verses"]:
                # Some modern texts leave out verses that later manuscripts
                # added (e.g. Matthew 17:21); the source keeps them empty.
                if not v["text"].strip():
                    continue
                verse = Verse(number, chapter["chapter"], v["verse"])
                verse.parts.append(v["text"])
                verses.append(verse)
    return verses, []


def load_web(path):
    verses, headings = [], []
    for number in range(1, 67):
        entries = json.load(open(os.path.join(path, "json", f"{WEB_FILES[number]}.json")))
        by_key = {}
        pending_paragraph = False
        pending_headings = []
        for e in entries:
            kind = e["type"]
            if kind in ("paragraph start", "stanza start"):
                pending_paragraph = True
            elif kind == "header":
                pending_headings.append(e["value"])
            elif kind in ("paragraph text", "line text"):
                key = (e["chapterNumber"], e["verseNumber"])
                verse = by_key.get(key)
                if verse is None:
                    verse = Verse(number, *key)
                    by_key[key] = verse
                    verses.append(verse)
                    verse.paragraph = pending_paragraph
                    for h in pending_headings:
                        headings.append((number, key[0], key[1], clean(h)))
                    pending_headings = []
                pending_paragraph = False
                if kind == "line text":
                    verse.poetry = True
                verse.parts.append(e["value"])
    return verses, headings


def create_bible_db(out_path, abbreviation, verses, headings):
    if os.path.exists(out_path):
        os.remove(out_path)
    db = sqlite3.connect(out_path)
    meta = TRANSLATIONS[abbreviation]
    # The Porter stemmer is English-only ("loving" finds "love"); other
    # languages are matched by whole words and prefixes, accents ignored.
    tokenizer = "porter unicode61 remove_diacritics 2" if meta["language"] == "en" else "unicode61 remove_diacritics 2"
    db.executescript(
        """
        PRAGMA page_size = 4096;
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE books (
            id INTEGER PRIMARY KEY,
            osis TEXT NOT NULL,
            name TEXT NOT NULL,
            testament TEXT NOT NULL,
            chapter_count INTEGER NOT NULL
        );
        CREATE TABLE verses (
            id INTEGER PRIMARY KEY,         -- book*1000000 + chapter*1000 + verse
            book INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL,             -- verbatim; poetry lines separated by \\n
            paragraph INTEGER NOT NULL DEFAULT 0,
            poetry INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE headings (
            book INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            before_verse INTEGER NOT NULL,
            text TEXT NOT NULL
        );
        CREATE INDEX headings_chapter ON headings(book, chapter);
        -- Contentless index: the app reads display text from `verses` and
        -- highlights matches itself, so the index can hold a search-friendly
        -- form of each verse without that form ever being shown to the reader.
        CREATE VIRTUAL TABLE verses_fts USING fts5(
            text,
            content='',
            tokenize='TOKENIZER',
            prefix='2 3 4'
        );
        """.replace("TOKENIZER", tokenizer)
    )
    for key, value in {
        "abbreviation": abbreviation,
        "name": meta["name"],
        "year": meta["year"],
        "license": meta["license"],
        "language": meta["language"],
        "schema_version": str(SCHEMA_VERSION),
    }.items():
        db.execute("INSERT INTO meta VALUES (?, ?)", (key, value))

    chapters = {}
    for v in verses:
        chapters[v.book] = max(chapters.get(v.book, 0), v.chapter)
    for number, osis, name, testament in BOOKS:
        db.execute("INSERT INTO books VALUES (?,?,?,?,?)", (number, osis, name, testament, chapters[number]))

    db.executemany(
        "INSERT INTO verses VALUES (?,?,?,?,?,?,?)",
        (
            (verse_id(v.book, v.chapter, v.verse), v.book, v.chapter, v.verse, v.text, int(v.paragraph), int(v.poetry))
            for v in verses
        ),
    )
    db.executemany("INSERT INTO headings VALUES (?,?,?,?)", headings)
    db.executemany(
        "INSERT INTO verses_fts(rowid, text) VALUES (?, ?)",
        ((verse_id(v.book, v.chapter, v.verse), search_form(v.text)) for v in verses),
    )
    db.execute("INSERT INTO verses_fts(verses_fts) VALUES ('optimize')")
    db.commit()
    db.execute("VACUUM")
    db.close()


def parse_osis_ref(ref):
    osis, chapter, verse = ref.split(".")
    return verse_id(OSIS_TO_NUMBER[osis], int(chapter), int(verse))


def create_crossref_db(scrollmapper, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    db = sqlite3.connect(out_path)
    db.executescript(
        """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE cross_references (
            from_id INTEGER NOT NULL,
            to_start INTEGER NOT NULL,
            to_end INTEGER NOT NULL,
            votes INTEGER NOT NULL
        );
        """
    )
    db.execute("INSERT INTO meta VALUES ('source', 'OpenBible.info cross references (CC-BY), openbible.info/labs/cross-references')")
    rows = []
    with open(os.path.join(scrollmapper, "sources", "extras", "cross_references.txt")) as f:
        next(f)  # header
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            votes = int(parts[2])
            if votes < 1:  # negative votes mean the community rejected the link
                continue
            target = parts[1].split("-")
            start = parse_osis_ref(target[0])
            end = parse_osis_ref(target[-1])
            rows.append((parse_osis_ref(parts[0]), start, end, votes))
    db.executemany("INSERT INTO cross_references VALUES (?,?,?,?)", rows)
    db.execute("CREATE INDEX cross_references_from ON cross_references(from_id, votes DESC)")
    db.commit()
    db.execute("VACUUM")
    db.close()
    return len(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scrollmapper", required=True)
    parser.add_argument("--web", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)

    web_verses, web_headings = load_web(args.web)
    # KJV and ASV sources carry no paragraph or poetry markers. Layout (not
    # text) is borrowed from the WEB so all translations read in paragraphs
    # and set the poetic books line by line.
    web_layout = {(v.book, v.chapter, v.verse): (v.paragraph, v.poetry) for v in web_verses}

    for abbreviation in ("KJV", "ASV"):
        verses, headings = load_scrollmapper(args.scrollmapper, abbreviation)
        for v in verses:
            v.paragraph, poetry = web_layout.get((v.book, v.chapter, v.verse), (v.verse == 1, False))
            # Poetry in these sources is a single line per verse, so it is
            # flagged but has no internal line breaks.
            v.poetry = poetry
        create_bible_db(os.path.join(args.out, f"{abbreviation}.sqlite"), abbreviation, verses, headings)
        print(f"{abbreviation}: {len(verses)} verses")

    create_bible_db(os.path.join(args.out, "WEB.sqlite"), "WEB", web_verses, web_headings)
    print(f"WEB: {len(web_verses)} verses, {len(web_headings)} headings")

    count = create_crossref_db(args.scrollmapper, os.path.join(args.out, "CrossReferences.sqlite"))
    print(f"Cross references: {count}")


if __name__ == "__main__":
    main()
