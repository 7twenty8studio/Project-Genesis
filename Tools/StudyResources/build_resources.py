#!/usr/bin/env python3
"""Builds the downloadable study resources (Library › Study Library) and the
Supabase rows that list them.

Every pack is one SQLite file in the same shape, compressed with raw DEFLATE
(as Tools/BibleData/package_translation.py does for Bibles) and listed in
public.study_resources with its size and SHA-256. Packs hold verse ids only,
never verse text: the app shows Scripture from its Bible databases.

  info(key, value)                       id, name, kind, version
  notes(id, start_verse, end_verse, title, text)
                                         study notes and commentary; a note whose
                                         start is verse 0 introduces its chapter
  introductions(book, title, text)       book introductions
  articles(id, title, kind, sort_key, text)
  article_verses(article, start_verse, end_verse)
  lexicon(strongs, source, lemma, translit, gloss, definition)

Text is light Markdown, one paragraph per blank line: "## " starts a heading,
"- " a list item, and inline only *italic*, **bold** and links
[text](verse:START-END) or [text](article:PACK/ID). Everything else is
escaped.

Sources (download them first; see PHASE4_SETUP.md › Study resources):
  --tyndale-notes   folder "Tyndale Open Study Notes" from
                    tyndaleopenresources.com (tyndale_open-studynotes.zip), CC BY-SA 4.0
  --tyndale-dict    folder of TyndaleOpenBibleDictionary.zip, CC BY-SA 4.0
  --sword           folder holding CrossWire's Barnes, Wesley, TDavid and Burkitt
                    rawzip modules unzipped (modules/comments/zcom/...), public domain
  --hebrew-lexicon  checkout of github.com/openscriptures/HebrewLexicon (CC BY 4.0)
  --lsj             STEPBible TFLSJ 0-5624 text file (CC BY 4.0)
  --palabras        folder with es-419_tw and es-419_twl from git.door43.org (CC BY-SA 4.0)
  Commentaries from bible.helloao.org (public domain) are fetched and cached
  in --cache.

  python3 Tools/StudyResources/build_resources.py --tyndale-notes ... --out build/study

Then upload build/study/*.sqlite.deflate to the public "study" bucket in
Supabase Storage and run build/study/study_resources.sql in the SQL Editor.
Bump a pack's version below to publish a corrected edition; the app updates
downloaded copies on Wi-Fi.
"""
import argparse
import concurrent.futures
import hashlib
import html
import json
import os
import re
import sqlite3
import struct
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zlib
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "Tools", "BibleData"))
from books import BOOKS, verse_id  # noqa: E402

KJV = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "KJV.sqlite")
DEFAULT_URL_BASE = "https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object/public/study"
HELLOAO = "https://bible.helloao.org"

TYNDALE_NOTES_ATTRIBUTION = ("Adapted from Tyndale Open Study Notes. The original work by Tyndale House Publishers "
                             "is available for free at http://www.tyndaleopenresources.com. Copyright © 2022 Tyndale "
                             "House Publishers, CC BY-SA 4.0. Changes: converted to Genesis's format; book introduction "
                             "summaries, maps and pictures left out.")
TYNDALE_DICT_ATTRIBUTION = ("Adapted from Tyndale Open Bible Dictionary. The original work by Tyndale House Publishers "
                            "is available for free at http://www.tyndaleopenresources.com. Copyright © 2023 Tyndale "
                            "House Publishers, CC BY-SA 4.0. Changes: converted to Genesis's format; maps, pictures, "
                            "charts and text boxes left out.")
PALABRAS_ATTRIBUTION = ("Palabras de Traducción, Copyright © 2022 Fundación Idiomas Puentes, CC BY-SA 4.0. Obra original "
                        "disponible en unfoldingword.org/utw. Changes: converted to Genesis's format; the translation "
                        "suggestions for Bible translators left out; verse links from es-419_twl.")
PD_HELLOAO = "Public domain. Text from the Free Use Bible API (bible.helloao.org)."
PD_CROSSWIRE = "Public domain. Text from the CrossWire Bible Society's SWORD module."

# Every pack Genesis offers. kind: notes | commentary | dictionary | lexicon.
# tradition: the author's church tradition, shown so readers know the angle.
PACKS = {
    "tyndale-notes": dict(kind="notes", name="Tyndale Open Study Notes", author="Tyndale House Publishers",
                          tradition="evangelical", language="en", license="CC BY-SA 4.0", premium=False, sort=1,
                          summary="Verse-by-verse study notes, book introductions, and articles on people and themes.",
                          attribution=TYNDALE_NOTES_ATTRIBUTION, version=1),
    "tyndale-dictionary": dict(kind="dictionary", name="Tyndale Open Bible Dictionary", author="Tyndale House Publishers",
                               tradition="evangelical", language="en", license="CC BY-SA 4.0", premium=False, sort=2,
                               summary="Thousands of articles on the Bible's people, places, customs and ideas.",
                               attribution=TYNDALE_DICT_ATTRIBUTION, version=1),
    "es-palabras": dict(kind="dictionary", name="Palabras de Traducción", author="unfoldingWord · Fundación Idiomas Puentes",
                        tradition="evangelical", language="es", license="CC BY-SA 4.0", premium=False, sort=3,
                        summary="A Spanish dictionary of key Bible terms, names and ideas, linked to the verses that use them.",
                        attribution=PALABRAS_ATTRIBUTION, version=1),
    "jfb": dict(kind="commentary", name="Jamieson-Fausset-Brown Commentary", author="Robert Jamieson, A. R. Fausset, David Brown",
                tradition="presbyterian", language="en", license="Public domain", premium=True, sort=10, year="1871",
                summary="A concise, careful commentary on the whole Bible, verse by verse.",
                attribution=PD_HELLOAO, helloao="jamieson-fausset-brown", version=1),
    "mhc": dict(kind="commentary", name="Matthew Henry's Complete Commentary", author="Matthew Henry",
                tradition="puritan", language="en", license="Public domain", premium=True, sort=11, year="1706",
                summary="Henry's full devotional commentary on the whole Bible, section by section.",
                attribution=PD_HELLOAO, helloao="matthew-henry", version=1),
    "barnes": dict(kind="commentary", name="Barnes' Notes on the New Testament", author="Albert Barnes",
                   tradition="presbyterian", language="en", license="Public domain", premium=True, sort=12, year="1834",
                   summary="Clear explanatory notes on the New Testament, written for teachers and families.",
                   attribution=PD_CROSSWIRE, sword="barnes", version=1),
    "gill": dict(kind="commentary", name="John Gill's Exposition of the Bible", author="John Gill",
                 tradition="reformed_baptist", language="en", license="Public domain", premium=True, sort=13, year="1763",
                 summary="A detailed verse-by-verse exposition drawing on Hebrew and Jewish sources.",
                 attribution=PD_HELLOAO, helloao="john-gill", version=1),
    "clarke": dict(kind="commentary", name="Adam Clarke's Commentary", author="Adam Clarke",
                   tradition="wesleyan", language="en", license="Public domain", premium=True, sort=14, year="1832",
                   summary="A scholarly Methodist commentary with notes on language, history and customs.",
                   attribution=PD_HELLOAO, helloao="adam-clarke", version=1,
                   # Off: Clarke denied Christ's eternal sonship and has other idiosyncratic notes.
                   enabled=False),
    "wesley": dict(kind="commentary", name="John Wesley's Notes on the Bible", author="John Wesley",
                   tradition="wesleyan", language="en", license="Public domain", premium=True, sort=15, year="1765",
                   summary="Brief, practical notes on the whole Bible from the founder of Methodism.",
                   attribution=PD_CROSSWIRE, sword="wesley", version=1),
    "calvin": dict(kind="commentary", name="John Calvin's Commentaries", author="John Calvin",
                   tradition="reformed", language="en", license="Public domain", premium=True, sort=16, year="1564",
                   summary="The Reformer's commentaries on most books of the Bible, in English translation.",
                   attribution=PD_HELLOAO, helloao="john-calvin", version=1),
    "keil-delitzsch": dict(kind="commentary", name="Keil & Delitzsch Old Testament Commentary", author="C. F. Keil, Franz Delitzsch",
                           tradition="lutheran", language="en", license="Public domain", premium=True, sort=17, year="1891",
                           summary="A thorough Old Testament commentary attentive to the Hebrew text.",
                           attribution=PD_HELLOAO, helloao="keil-delitzsch", version=1),
    "treasury-of-david": dict(kind="commentary", name="The Treasury of David", author="C. H. Spurgeon",
                              tradition="reformed_baptist", language="en", license="Public domain", premium=True, sort=18, year="1885",
                              summary="Spurgeon's devotional exposition of every psalm.",
                              attribution=PD_CROSSWIRE, sword="tdavid", sword4=True, version=1),
    "burkitt": dict(kind="commentary", name="Burkitt's Expository Notes", author="William Burkitt",
                    tradition="anglican", language="en", license="Public domain", premium=True, sort=19, year="1700",
                    summary="Practical, pastoral notes on the New Testament.",
                    attribution=PD_CROSSWIRE, sword="burkitt", version=1),
    "lexicons": dict(kind="lexicon", name="Hebrew & Greek Lexicons", author="Brown, Driver & Briggs · Liddell, Scott & Jones",
                     tradition=None, language="en", license="CC BY 4.0", premium=True, sort=30,
                     summary="Brown-Driver-Briggs for Hebrew and the full Liddell-Scott-Jones for Greek, by Strong's number.",
                     attribution=("Brown-Driver-Briggs from the Open Scriptures Hebrew Bible Project (CC BY 4.0). "
                                  "Liddell-Scott-Jones from STEPBible.org's TFLSJ, based on the Perseus Digital Library "
                                  "(CC BY 4.0)."), version=1),
}

# --------------------------------------------------------------------------
# Books and references

USFM = ["GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR",
        "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS", "JOL", "AMO",
        "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM",
        "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
        "2PE", "1JN", "2JN", "3JN", "JUD", "REV"]

ABBREVIATIONS = {
    1: "ge gn", 2: "exo ex", 3: "le lv", 4: "nu nm nb", 5: "deu de dt", 6: "jos jsh", 7: "jdg jg jgs",
    8: "rut ru rth", 9: "1sa 1sm 1samuel", 10: "2sa 2sm 2samuel", 11: "1ki 1kg 1kings", 12: "2ki 2kg 2kings",
    13: "1ch 1chron 1chronicles", 14: "2ch 2chron 2chronicles", 15: "ezr", 16: "ne", 17: "est es esther",
    18: "jb", 19: "psa pss psalm psalms", 20: "pro pr prv proverbs", 21: "ecc ec eccles qoh ecclesiastes",
    22: "sng so sos cant songofsongs songofsolomon", 23: "is isaiah", 24: "je jr jeremiah", 25: "la lamentations",
    26: "eze ezk ezekiel", 27: "da dn daniel", 28: "ho hosea", 29: "joe jl", 30: "am", 31: "ob oba obadiah",
    32: "jon jnh", 33: "mi micah", 34: "na nahum", 35: "habakkuk", 36: "zep zephaniah", 37: "hagg haggai",
    38: "zec zechariah", 39: "malachi", 40: "mat mt matthew", 41: "mar mrk mk", 42: "luk lk", 43: "joh jn jhn",
    44: "act ac", 45: "ro rm romans", 46: "1co 1corinthians", 47: "2co 2corinthians", 48: "ga galatians",
    49: "ep ephesians", 50: "php phi philippians", 51: "colossians", 52: "1thes 1th 1thessalonians",
    53: "2thes 2th 2thessalonians", 54: "1ti 1timothy", 55: "2ti 2timothy", 56: "tit", 57: "phm philem phile philemon",
    58: "hebrews", 59: "jam jm james", 60: "1pe 1pt 1peter", 61: "2pe 2pt 2peter", 62: "1jn 1jo 1joh",
    63: "2jn 2jo 2joh", 64: "3jn 3jo 3joh", 65: "jud", 66: "re rv revelation",
}

BOOK_LOOKUP = {}
for number, osis, name, _ in BOOKS:
    BOOK_LOOKUP[osis.lower()] = number
    BOOK_LOOKUP[name.lower().replace(" ", "")] = number
    BOOK_LOOKUP[USFM[number - 1].lower()] = number
    for abbreviation in ABBREVIATIONS.get(number, "").split():
        BOOK_LOOKUP[abbreviation] = number


def book_number(token):
    return BOOK_LOOKUP.get(re.sub(r"[\s.]", "", token).lower())


def load_verse_counts():
    counts = {}
    with sqlite3.connect(KJV) as db:
        for (vid,) in db.execute("SELECT id FROM verses"):
            book, chapter, verse = vid // 1_000_000, (vid // 1000) % 1000, vid % 1000
            chapters = counts.setdefault(book, {})
            chapters[chapter] = max(chapters.get(chapter, 0), verse)
    return counts


COUNTS = load_verse_counts()

REFERENCE = re.compile(
    r"^\s*(?P<book>[1-3]?\s?[A-Za-z]+)\.?\s*(?P<ch>\d+)(?:[.:](?P<v>\d+))?"
    r"(?:\s*[-–—]\s*(?:(?P<ech>\d+)[.:])?(?P<ev>\d+))?\s*$"
)


def parse_reference(text):
    """'Gen.1.1-2.3', 'Pr.8.22-31', 'Rom 16:20', 'Gen.1' -> (start id, end id), or None."""
    text = text.strip().lstrip("\\").replace("?bref=", "").strip()
    match = REFERENCE.match(text)
    if not match:
        return None
    book = book_number(match["book"])
    if not book or book not in COUNTS:
        return None
    chapters = COUNTS[book]
    chapter = int(match["ch"])
    if chapter not in chapters:
        return None
    if match["v"] is None:
        # A chapter, or a run of chapters ("Gen.1-3").
        last_chapter = int(match["ev"]) if match["ev"] and not match["ech"] else chapter
        last_chapter = last_chapter if last_chapter in chapters and last_chapter >= chapter else chapter
        return verse_id(book, chapter, 1), verse_id(book, last_chapter, chapters[last_chapter])
    verse = min(int(match["v"]), chapters[chapter])
    start = verse_id(book, chapter, max(verse, 1))
    end_chapter = int(match["ech"]) if match["ech"] else chapter
    if end_chapter not in chapters:
        end_chapter = chapter
    end_verse = int(match["ev"]) if match["ev"] else verse
    end = verse_id(book, end_chapter, max(1, min(end_verse, chapters[end_chapter])))
    return start, max(start, end)


def verse_link(start, end):
    return f"verse:{start}-{end}"


# --------------------------------------------------------------------------
# Text

ESCAPED = set("\\`*_[]<>&~#|")


def escape(text):
    return "".join("\\" + c if c in ESCAPED else c for c in text)


def fold(text):
    """Lower case without accents, for search."""
    decomposed = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in decomposed if not unicodedata.combining(c))


class Paragraph:
    def __init__(self, style="p"):
        self.style = style
        self.parts = []


class MarkupConverter(HTMLParser):
    """Turns the sources' HTML-ish markup (Tyndale XML, ThML, OSIS, STEPBible
    HTML) into Genesis's light Markdown."""

    HEADINGS = {"h2", "h3", "h4", "intro-h1", "intro-sidebar-h1", "theme-h2", "profile-h1", "profile-refs-title",
                "theme-refs-title", "h2-preview"}
    LISTS = {"list", "list-text", "sn-list-1", "sn-list-2", "sn-list-3", "intro-list", "intro-list-sp",
             "theme-list", "theme-list-sp", "preview-list", "preview-list-first"}
    SKIPPED = {"profile-title", "theme-title", "intro-title", "h1", "toc"}
    ITALIC_SPANS = {"ital", "sn-excerpt", "sn-excerpt-roman", "sn-excerpt-sc", "sn-excerpt-divine-name",
                    "divine-name-ital", "hebrew", "greek", "aramaic", "latin", "sc-ital", "sn-hebrew-chars", "intro-h2"}
    BOLD_SPANS = {"bold", "bold-sc", "ital-bold", "sn-ref", "bold-era"}

    def __init__(self, pack):
        super().__init__(convert_charrefs=True)
        self.pack = pack
        self.paragraphs = []
        self.current = Paragraph()
        self.stack = []  # (tag, action)
        self.marks = []  # open emphasis or link: [kind, index, url]
        self.skip = 0

    # Paragraphs

    def new_paragraph(self, style="p"):
        reopen = [(kind, url) for kind, _, url in self.marks]
        while self.marks:
            self.close_mark()
        self.flush()
        self.current = Paragraph(style)
        for kind, url in reopen:
            self.open_mark(kind, url)

    def flush(self):
        text = re.sub(r"\s+", " ", "".join(self.current.parts)).strip()
        if text and re.sub(r"[\\*\s]", "", text):
            prefix = {"h": "## ", "li": "- "}.get(self.current.style, "")
            if not prefix and text[0] in "-+":
                text = "\\" + text
            self.paragraphs.append(prefix + text)
        self.current.parts = []

    def result(self):
        while self.marks:
            self.close_mark()
        self.flush()
        return "\n\n".join(self.paragraphs)

    # Emphasis and links

    def open_mark(self, kind, url=None):
        if kind in ("*", "**") and any(m[0] == kind for m in self.marks):
            self.marks.append([None, len(self.current.parts), None])
            return
        if kind == "link" and any(m[0] == "link" for m in self.marks):
            self.marks.append([None, len(self.current.parts), None])
            return
        self.marks.append([kind, len(self.current.parts), url])
        self.current.parts.append("")

    def close_mark(self):
        kind, index, url = self.marks.pop()
        if kind is None:
            return
        inner = "".join(self.current.parts[index + 1:])
        del self.current.parts[index:]
        lead = " " if inner[:1].isspace() else ""
        trail = " " if inner[-1:].isspace() else ""
        inner = re.sub(r"\s+", " ", inner).strip()
        if not inner:
            self.current.parts.append(lead + trail)
        elif kind == "link":
            self.current.parts.append(f"{lead}[{inner}]({url}){trail}")
        else:
            self.current.parts.append(f"{lead}{kind}{inner}{kind}{trail}")

    # Parser callbacks

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "br":
            self.new_paragraph()
            return
        action = None
        css = attrs.get("class", "")
        kind = attrs.get("type", "")
        if self.skip:
            action = "skip"
        elif tag in ("note",) or (tag == "span" and css in ("sup",)) or css in self.SKIPPED:
            action = "skip"
        elif tag == "p" or (tag == "div" and kind in ("paragraph", "x-p", "section")) or re.fullmatch(r"level\d", tag):
            style = "h" if css in self.HEADINGS else "li" if css in self.LISTS else "p"
            self.new_paragraph(style)
            action = "paragraph"
        elif tag == "title":
            self.new_paragraph("h")
            action = "paragraph"
        elif tag in ("i", "em") or (tag == "hi" and kind == "italic") or (tag == "span" and css in self.ITALIC_SPANS) \
                or tag == "foreign":
            self.open_mark("*")
            action = "mark"
        elif tag in ("b", "strong") or (tag == "hi" and kind == "bold") or (tag == "span" and css in self.BOLD_SPANS):
            self.open_mark("**")
            action = "mark"
        elif tag == "a" and attrs.get("href", "").startswith("javascript"):
            # STEPBible puts the references in the title; the link text only names their kind.
            title = attrs.get("title", "").strip()
            if title:
                self.current.parts.append(escape(title))
            action = "skip"
        elif tag in ("a", "scripref", "reference"):
            url = self.link(attrs)
            if url:
                self.open_mark("link", url)
                action = "mark"
        if action == "skip":
            self.skip += 1
        self.stack.append((tag, action))

    def handle_endtag(self, tag):
        # Close the most recent matching tag (sources aren't always balanced).
        for position in range(len(self.stack) - 1, -1, -1):
            if self.stack[position][0] == tag:
                break
        else:
            if tag in ("div",):
                self.new_paragraph()
            return
        while len(self.stack) > position:
            _, action = self.stack.pop()
            if action == "skip":
                self.skip -= 1
            elif action == "mark":
                self.close_mark()
            elif action == "paragraph":
                self.new_paragraph()

    def handle_startendtag(self, tag, attrs):
        if tag == "br":
            self.new_paragraph()
        elif tag in ("div", "p", "lb", "milestone", "chapter") or re.fullmatch(r"level\d", tag):
            self.new_paragraph()

    def handle_data(self, data):
        if not self.skip:
            self.current.parts.append(escape(data))

    def link(self, attrs):
        href = attrs.get("href") or ""
        passage = attrs.get("passage") or attrs.get("osisref") or ""
        if "?item=" in href:
            item = href.split("?item=", 1)[1]
            name, _, rest = item.partition("_")
            kind = rest.split("_")[0]
            if kind == "StudyNote":
                found = parse_reference(name)
                return verse_link(*found) if found else None
            if kind in ("ThemeNote", "Profile"):
                return f"article:tyndale-notes/{name}"
            if kind == "Article":
                return f"article:tyndale-dictionary/{name}"
            return None
        target = passage or href
        if target and not target.startswith("#"):
            found = parse_reference(target.split(";")[0].split(",")[0])
            return verse_link(*found) if found else None
        return None


def convert(markup, pack):
    converter = MarkupConverter(pack)
    converter.feed(markup)
    converter.close()
    return converter.result()


def plain_paragraphs(text):
    """Plain text with blank lines between paragraphs (HelloAO)."""
    paragraphs = []
    for block in re.split(r"\n\s*\n", text or ""):
        line = re.sub(r"\s+", " ", block).strip()
        if line:
            line = escape(line)
            if line[0] in "-+":
                line = "\\" + line
            paragraphs.append(line)
    return "\n\n".join(paragraphs)


# --------------------------------------------------------------------------
# Packs

SCHEMA = """
CREATE TABLE info (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE notes (id INTEGER PRIMARY KEY, start_verse INTEGER NOT NULL, end_verse INTEGER NOT NULL, title TEXT, text TEXT NOT NULL);
CREATE INDEX notes_start ON notes(start_verse);
CREATE TABLE introductions (book INTEGER PRIMARY KEY, title TEXT, text TEXT NOT NULL);
CREATE TABLE articles (id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL, sort_key TEXT NOT NULL, text TEXT NOT NULL);
CREATE INDEX articles_sort ON articles(sort_key);
CREATE TABLE article_verses (article TEXT NOT NULL, start_verse INTEGER NOT NULL, end_verse INTEGER NOT NULL);
CREATE INDEX article_verses_start ON article_verses(start_verse);
CREATE TABLE lexicon (strongs TEXT NOT NULL, source TEXT NOT NULL, lemma TEXT NOT NULL, translit TEXT NOT NULL, gloss TEXT NOT NULL, definition TEXT NOT NULL);
CREATE INDEX lexicon_strongs ON lexicon(strongs);
"""


class Pack:
    def __init__(self, pack_id):
        self.id = pack_id
        self.meta = PACKS[pack_id]
        self.notes = []  # (start, end, title, text)
        self.introductions = {}  # book -> (title, text)
        self.articles = {}  # id -> (title, kind, text)
        self.article_verses = []  # (article, start, end)
        self.lexicon = []  # (strongs, source, lemma, translit, gloss, definition)

    def write(self, out):
        name = f"{self.id}-{self.meta['version']}"
        path = os.path.join(out, f"{name}.sqlite")
        if os.path.exists(path):
            os.remove(path)
        db = sqlite3.connect(path)
        db.executescript(SCHEMA)
        info = {"id": self.id, "name": self.meta["name"], "kind": self.meta["kind"], "version": str(self.meta["version"])}
        db.executemany("INSERT INTO info VALUES (?, ?)", info.items())
        self.notes.sort(key=lambda n: (n[0], -n[1]))
        db.executemany("INSERT INTO notes (start_verse, end_verse, title, text) VALUES (?, ?, ?, ?)", self.notes)
        db.executemany("INSERT INTO introductions VALUES (?, ?, ?)", [(b, t, x) for b, (t, x) in sorted(self.introductions.items())])
        db.executemany("INSERT INTO articles VALUES (?, ?, ?, ?, ?)",
                       [(i, t, k, fold(t), x) for i, (t, k, x) in sorted(self.articles.items(), key=lambda a: fold(a[1][0]))])
        known = set(self.articles)
        db.executemany("INSERT INTO article_verses VALUES (?, ?, ?)",
                       sorted({row for row in self.article_verses if row[0] in known}, key=lambda r: (r[1], r[0])))
        db.executemany("INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?)", self.lexicon)
        db.commit()
        db.execute("VACUUM")
        db.close()
        raw = open(path, "rb").read()
        compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
        packed = compressor.compress(raw) + compressor.flush()
        assert zlib.decompress(packed, -15) == raw
        open(path + ".deflate", "wb").write(packed)
        print(f"{self.id}: {len(self.notes)} notes, {len(self.introductions)} introductions, {len(self.articles)} articles, "
              f"{len(self.lexicon)} lexicon entries; {len(raw) / 1e6:.1f} MB, {len(packed) / 1e6:.1f} MB compressed")
        return dict(file=f"{name}.sqlite.deflate", file_bytes=len(packed), database_bytes=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest())


def sql_text(value):
    return "null" if value is None else "'" + str(value).replace("'", "''") + "'"


def catalog_sql(pack_id, built, url_base):
    meta = PACKS[pack_id]
    url = f"{url_base.rstrip('/')}/{built['file']}"
    columns = ("id, kind, name, author, summary, tradition, language, year, license, attribution, premium, "
               "file_url, file_bytes, database_bytes, sha256, version, enabled, sort, updated_at")
    values = ", ".join([
        sql_text(pack_id), sql_text(meta["kind"]), sql_text(meta["name"]), sql_text(meta["author"]),
        sql_text(meta["summary"]), sql_text(meta.get("tradition")), sql_text(meta["language"]), sql_text(meta.get("year")),
        sql_text(meta["license"]), sql_text(meta["attribution"]), "true" if meta["premium"] else "false",
        sql_text(url), str(built["file_bytes"]), str(built["database_bytes"]), sql_text(built["sha256"]),
        str(meta["version"]), "true" if meta.get("enabled", True) else "false", str(meta["sort"]), "now()",
    ])
    updates = ", ".join(f"{c} = excluded.{c}" for c in columns.split(", ")[1:-1]) + ", updated_at = now()"
    return f"insert into public.study_resources ({columns})\nvalues ({values})\non conflict (id) do update set {updates};\n"


# --------------------------------------------------------------------------
# Tyndale

def tyndale_items(path):
    root = ET.parse(path).getroot()
    for item in root.iter("item"):
        body = item.find("body")
        markup = ET.tostring(body, encoding="unicode") if body is not None else ""
        yield item.get("name"), item.get("typename"), (item.findtext("title") or "").strip(), \
            (item.findtext("refs") or "").strip(), markup


def build_tyndale_notes(folder):
    pack = Pack("tyndale-notes")
    for name, kind, _, refs, markup in tyndale_items(os.path.join(folder, "StudyNotes.xml")):
        found = parse_reference(refs or name)
        if not found:
            continue  # the Apocrypha, or a reference outside the 66 books
        text = convert(markup, pack.id)
        if text:
            pack.notes.append((found[0], found[1], None, text))
    for name, kind, title, refs, markup in tyndale_items(os.path.join(folder, "BookIntros.xml")):
        found = parse_reference(refs)
        if found:
            pack.introductions[found[0] // 1_000_000] = (title, convert(markup, pack.id))
    for file, kind in (("Profiles.xml", "profile"), ("ThemeNotes.xml", "theme")):
        for name, _, title, refs, markup in tyndale_items(os.path.join(folder, file)):
            pack.articles[name] = (title, kind, convert(markup, pack.id))
            for ref in re.split(r"[;,\s]+", refs):
                found = parse_reference(ref) if ref else None
                if found:
                    pack.article_verses.append((name, found[0], found[1]))
    return pack


def build_tyndale_dictionary(folder):
    pack = Pack("tyndale-dictionary")
    articles = os.path.join(folder, "Articles")
    for file in sorted(os.listdir(articles)):
        if not file.endswith(".xml"):
            continue
        for name, kind, title, _, markup in tyndale_items(os.path.join(articles, file)):
            if kind != "Article" or not title:
                continue
            text = convert(markup, pack.id)
            if text:
                pack.articles[name] = (title, "dictionary", text)
    return pack


# --------------------------------------------------------------------------
# Commentaries

def fetch_json(path, cache):
    local = os.path.join(cache, path.strip("/").replace("/", os.sep))
    if os.path.exists(local):
        with open(local, encoding="utf-8") as f:
            return json.load(f)
    for attempt in range(4):
        try:
            request = urllib.request.Request(HELLOAO + path, headers={"User-Agent": "GenesisStudyBuilder/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            os.makedirs(os.path.dirname(local), exist_ok=True)
            with open(local, "wb") as f:
                f.write(data)
            return json.loads(data)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None  # the commentary skips this chapter
            if attempt == 3:
                raise RuntimeError(f"{path}: {error}") from error
            time.sleep(2 * (attempt + 1))
        except Exception as error:  # noqa: BLE001
            if attempt == 3:
                raise RuntimeError(f"{path}: {error}") from error
            time.sleep(2 * (attempt + 1))


def commentary_ranges(pack, book, chapter, entries, introduction):
    """entries: [(verse, text)] in order. Each entry runs until the next one
    starts (sparse commentaries comment on sections)."""
    last = COUNTS[book].get(chapter)
    if not last:
        return
    if introduction:
        pack.notes.append((verse_id(book, chapter, 0), verse_id(book, chapter, last), None, introduction))
    entries = [(v, t) for v, t in entries if 1 <= v <= last and t]
    for index, (verse, text) in enumerate(entries):
        end = entries[index + 1][0] - 1 if index + 1 < len(entries) else last
        pack.notes.append((verse_id(book, chapter, verse), verse_id(book, chapter, max(verse, end)), None, text))


def build_helloao(pack_id, cache):
    pack = Pack(pack_id)
    source = PACKS[pack_id]["helloao"]
    books = fetch_json(f"/api/c/{source}/books.json", cache)["books"]
    jobs = []
    for book in books:
        if book["id"] not in USFM:
            continue
        number = USFM.index(book["id"]) + 1
        introduction = plain_paragraphs(book.get("introduction") or "")
        if introduction:
            pack.introductions[number] = (book.get("commonName") or book.get("name"), introduction)
        if book.get("firstChapterNumber") is None or book.get("lastChapterNumber") is None:
            continue  # the commentary has nothing on this book
        for chapter in range(int(book["firstChapterNumber"]), int(book["lastChapterNumber"]) + 1):
            jobs.append((number, chapter, f"/api/c/{source}/{book['id']}/{chapter}.json"))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(lambda job: (job[0], job[1], fetch_json(job[2], cache)), jobs))
    for number, chapter, data in results:
        if not data:
            continue
        content = data["chapter"]
        entries = []
        for item in content.get("content", []):
            if item.get("type") != "verse":
                continue
            parts = [p if isinstance(p, str) else p.get("text", "") for p in item.get("content", [])]
            entries.append((int(item["number"]), plain_paragraphs("\n\n".join(parts))))
        commentary_ranges(pack, number, chapter, entries, plain_paragraphs(content.get("introduction") or ""))
    return pack


def read_zcom(path, size4):
    """A SWORD zCom/zCom4 module in KJV versification -> {(book, chapter, verse): (key, markup)};
    chapter 0 is the book's heading, verse 0 a chapter's. Linked entries share a key."""
    entries = {}
    for testament, books in (("ot", range(1, 40)), ("nt", range(40, 67))):
        names = [f for f in os.listdir(path) if f.startswith(testament + ".")]
        if not names:
            continue
        letter = names[0][-3]
        index = open(os.path.join(path, f"{testament}.{letter}zv"), "rb").read()
        blocks_raw = open(os.path.join(path, f"{testament}.{letter}zs"), "rb").read()
        data = open(os.path.join(path, f"{testament}.{letter}zz"), "rb").read()
        width = 12 if size4 else 10
        blocks = [struct.unpack("<III", blocks_raw[i:i + 12]) for i in range(0, len(blocks_raw), 12)]
        cache = {}

        def entry(n):
            raw = index[n * width:(n + 1) * width]
            if len(raw) < width:
                return None
            block, offset = struct.unpack("<II", raw[:8])
            size = struct.unpack("<I" if size4 else "<H", raw[8:])[0]
            if size == 0 or block >= len(blocks):
                return None
            if block not in cache:
                start, compressed, _ = blocks[block]
                cache.clear()
                cache[block] = zlib.decompress(data[start:start + compressed])
            return (block, offset, size), cache[block][offset:offset + size].decode("utf-8", "replace")

        n = 2  # 0: module heading, 1: testament heading
        for book in books:
            found = entry(n)
            if found:
                entries[(book, 0, 0)] = found
            n += 1
            for chapter in sorted(COUNTS[book]):
                found = entry(n)
                if found:
                    entries[(book, chapter, 0)] = found
                n += 1
                for verse in range(1, COUNTS[book][chapter] + 1):
                    found = entry(n)
                    if found:
                        entries[(book, chapter, verse)] = found
                    n += 1
    return entries


def build_sword(pack_id, folder):
    meta = PACKS[pack_id]
    pack = Pack(pack_id)
    entries = read_zcom(os.path.join(folder, "modules", "comments", "zcom", meta["sword"]), meta.get("sword4", False))
    for book in sorted(COUNTS):
        heading = entries.get((book, 0, 0))
        if heading:
            text = convert(heading[1], pack_id)
            if text:
                pack.introductions[book] = (BOOKS[book - 1][2], text)
        for chapter in sorted(COUNTS[book]):
            introduction = entries.get((book, chapter, 0))
            items, previous = [], None
            for verse in range(1, COUNTS[book][chapter] + 1):
                found = entries.get((book, chapter, verse))
                if not found or found[0] == previous:
                    continue  # linked to the entry before: it runs on
                previous = found[0]
                items.append((verse, convert(found[1], pack_id)))
            commentary_ranges(pack, book, chapter, items, convert(introduction[1], pack_id) if introduction else "")
    return pack


# --------------------------------------------------------------------------
# Lexicons

def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def bdb_markup(element):
    """A BDB entry (OSHB XML) -> HTML-ish markup the converter understands."""
    parts = []

    def walk(node):
        tag = local_name(node.tag)
        if tag == "status":
            parts.append(html.escape(node.tail or ""))
            return
        open_, close = "", ""
        if tag == "sense":
            number = node.get("n")
            open_, close = "<p>" + (f"<b>{html.escape(number)}.</b> " if number else ""), "</p>"
        elif tag in ("def",):
            open_, close = "<b>", "</b>"
        elif tag in ("pos", "em", "foreign", "stem", "asp"):
            open_, close = "<i>", "</i>"
        elif tag == "ref" and node.get("r"):
            open_, close = f'<reference osisref="{html.escape(node.get("r"))}">', "</reference>"
        parts.append(open_ + html.escape(node.text or ""))
        for child in node:
            walk(child)
        parts.append(close + html.escape(node.tail or ""))

    parts.append(html.escape(element.text or ""))
    for child in element:
        walk(child)
    return "".join(parts)


def build_lexicons(hebrew_folder, lsj_path):
    pack = Pack("lexicons")
    namespace = {"o": "http://openscriptures.github.com/morphhb/namespace"}
    if hebrew_folder:
        bdb = {}
        for entry in ET.parse(os.path.join(hebrew_folder, "BrownDriverBriggs.xml")).getroot().iter(f"{{{namespace['o']}}}entry"):
            bdb[entry.get("id")] = entry
        for entry in ET.parse(os.path.join(hebrew_folder, "LexicalIndex.xml")).getroot().iter(f"{{{namespace['o']}}}entry"):
            xref = entry.find("o:xref", namespace)
            word = entry.find("o:w", namespace)
            if xref is None or not xref.get("strong") or xref.get("bdb") not in bdb:
                continue
            digits = re.sub(r"\D", "", xref.get("strong"))
            if not digits:
                continue
            strongs = f"H{int(digits):04d}"
            definition = convert(bdb_markup(bdb[xref.get("bdb")]), pack.id)
            if not definition:
                continue
            lemma = (word.text or "").strip() if word is not None else ""
            translit = (word.get("xlit") or "") if word is not None else ""
            gloss = (entry.findtext("o:def", default="", namespaces=namespace) or "").strip()
            pack.lexicon.append((strongs, "bdb", lemma, translit, gloss, definition))
    if lsj_path:
        with open(lsj_path, encoding="utf-8") as f:
            for line in f:
                # Columns: number, "Gnnnn =", number, lemma, transliteration, grammar, gloss, definition.
                fields = line.rstrip("\n").split("\t")
                if len(fields) < 8 or not re.fullmatch(r"G\d{4,5}[A-Z]?", fields[0]):
                    continue
                markup = fields[7]
                if "LSJ has no entry" in markup:
                    continue  # Abbott-Smith, which Genesis already has
                markup = re.sub(r"<(/?)Level(\d)>", r"<\1level\2>", markup)
                markup = re.sub(r"(<b>\s*)_+", r"\1", markup)
                definition = convert(markup, pack.id)
                if definition:
                    strongs = re.match(r"G(\d+)", fields[0])
                    pack.lexicon.append((f"G{int(strongs[1]):04d}", "lsj", fields[3].strip(), fields[4].strip(),
                                         fields[6].strip(), definition))
    return pack


# --------------------------------------------------------------------------
# Palabras de Traducción (Spanish)

def palabras_text(markdown, article_id):
    """unfoldingWord's Markdown -> Genesis's: no translator suggestions, links
    made into verse and article links."""
    paragraphs, skipping = [], False
    folder = article_id.split("/")[0]

    def link(match):
        label, target = match[1], match[2]
        found = re.match(r"rc://[^/]+/tn/help/([1-3a-z]{3})/(\d+)/(\d+)", target)
        if found and found[1].upper() in USFM:
            book = USFM.index(found[1].upper()) + 1
            chapter, verse = int(found[2]), int(found[3])
            if chapter in COUNTS[book]:
                vid = verse_id(book, chapter, min(verse, COUNTS[book][chapter]))
                end = vid
                span = re.search(r"(\d+):(\d+)\s*[-–]\s*(\d+)\s*$", label)
                if span and int(span[1]) == chapter and int(span[2]) == verse:
                    end = verse_id(book, chapter, max(verse, min(int(span[3]), COUNTS[book][chapter])))
                return f"[{escape(label)}]({verse_link(vid, end)})"
        found = re.match(r"(?:\.\./([a-z]+)/|\./)?([\w-]+)\.md$", target)
        if found:
            return f"[{escape(label)}](article:es-palabras/{found[1] or folder}/{found[2]})"
        return escape(label)

    for block in re.split(r"\n\s*\n", markdown):
        for line in block.split("\n"):
            line = line.strip()
            if not line:
                continue
            if line.startswith("# "):
                continue  # the title
            heading = re.match(r"#{2,6}\s+(.*)", line)
            if heading:
                title = heading[1].strip()
                skipping = fold(title).startswith(("sugerencias de traduccion", "datos de esta palabra"))
                if not skipping:
                    paragraphs.append("## " + escape(title.rstrip(":")))
                continue
            if skipping:
                continue
            bullet = re.match(r"[*-]\s+(.*)", line)
            body = bullet[1] if bullet else line
            # Escape the text between links, keep the source's **bold** and *italic*.
            pieces, position = [], 0
            for match in re.finditer(r"\[([^\]]+)\]\(([^)]+)\)", body):
                pieces.append(escape(body[position:match.start()]))
                pieces.append(link(match))
                position = match.end()
            pieces.append(escape(body[position:]))
            text = "".join(pieces)
            text = re.sub(r"\\\*\\\*(.+?)\\\*\\\*", r"**\1**", text)
            text = re.sub(r"\\\*(.+?)\\\*", r"*\1*", text)
            text = re.sub(r"\\_(.+?)\\_", r"*\1*", text)
            if not bullet and text[:1] in "-+":
                text = "\\" + text
            paragraphs.append(("- " if bullet else "") + text)
    return "\n\n".join(paragraphs)


def build_palabras(folder):
    pack = Pack("es-palabras")
    words = os.path.join(folder, "es-419_tw", "bible")
    kinds = {"kt": "keyterm", "names": "name", "other": "term"}
    for sub, kind in kinds.items():
        for file in sorted(os.listdir(os.path.join(words, sub))):
            if not file.endswith(".md"):
                continue
            article_id = f"{sub}/{file[:-3]}"
            markdown = open(os.path.join(words, sub, file), encoding="utf-8").read()
            title = re.search(r"^#\s+(.+)$", markdown, re.M)
            text = palabras_text(markdown, article_id)
            if title and text:
                pack.articles[article_id] = (title[1].strip(), kind, text)
    links = os.path.join(folder, "es-419_twl")
    for file in sorted(os.listdir(links)):
        match = re.fullmatch(r"twl_([1-3A-Z]{3})\.tsv", file)
        if not match or match[1] not in USFM:
            continue
        book = USFM.index(match[1]) + 1
        for line in open(os.path.join(links, file), encoding="utf-8"):
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 6 or not re.fullmatch(r"\d+:\d+", fields[0]):
                continue
            chapter, verse = map(int, fields[0].split(":"))
            target = re.search(r"/tw/dict/bible/(\w+/[\w-]+)$", fields[5])
            if target and chapter in COUNTS[book] and 1 <= verse <= COUNTS[book][chapter]:
                vid = verse_id(book, chapter, verse)
                pack.article_verses.append((target[1], vid, vid))
    return pack


# --------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tyndale-notes")
    parser.add_argument("--tyndale-dict")
    parser.add_argument("--sword")
    parser.add_argument("--hebrew-lexicon")
    parser.add_argument("--lsj")
    parser.add_argument("--palabras")
    parser.add_argument("--only", help="comma-separated pack ids (default: every pack with its source given)")
    parser.add_argument("--no-helloao", action="store_true", help="skip the commentaries fetched from bible.helloao.org")
    parser.add_argument("--cache", default="build/study/cache")
    parser.add_argument("--url-base", default=DEFAULT_URL_BASE, help="public https folder the files will be in")
    parser.add_argument("--out", default="build/study")
    args = parser.parse_args()
    if not args.url_base.startswith("https://"):
        sys.exit("--url-base must be https")
    wanted = set(args.only.split(",")) if args.only else set(PACKS)
    unknown = wanted - set(PACKS)
    if unknown:
        sys.exit(f"Unknown packs: {', '.join(sorted(unknown))}")
    os.makedirs(args.out, exist_ok=True)

    builders = []
    if args.tyndale_notes:
        builders.append(("tyndale-notes", lambda: build_tyndale_notes(args.tyndale_notes)))
    if args.tyndale_dict:
        builders.append(("tyndale-dictionary", lambda: build_tyndale_dictionary(args.tyndale_dict)))
    if args.palabras:
        builders.append(("es-palabras", lambda: build_palabras(args.palabras)))
    if args.hebrew_lexicon or args.lsj:
        builders.append(("lexicons", lambda: build_lexicons(args.hebrew_lexicon, args.lsj)))
    for pack_id, meta in PACKS.items():
        if meta.get("helloao") and not args.no_helloao:
            builders.append((pack_id, lambda pack_id=pack_id: build_helloao(pack_id, args.cache)))
        if meta.get("sword") and args.sword:
            builders.append((pack_id, lambda pack_id=pack_id: build_sword(pack_id, args.sword)))

    statements = []
    for pack_id, build in builders:
        if pack_id not in wanted:
            continue
        built = build().write(args.out)
        statement = catalog_sql(pack_id, built, args.url_base)
        open(os.path.join(args.out, f"{pack_id}-{PACKS[pack_id]['version']}.sql"), "w").write(statement)
        statements.append(statement)
    header = "-- Generated by Tools/StudyResources/build_resources.py. Upload the .deflate files first, then run this.\n"
    open(os.path.join(args.out, "study_resources.sql"), "w").write(header + "\n".join(statements))
    print(f"Wrote {len(statements)} packs and {os.path.join(args.out, 'study_resources.sql')}")


if __name__ == "__main__":
    main()
