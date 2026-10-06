#!/usr/bin/env python3
"""Builds Genesis/Resources/Study/WordStudy.sqlite: the original-language
words of every verse (Hebrew and Greek, with Strong's numbers), a lexicon of
their definitions, and Matthew Henry's Concise Commentary.

No Scripture translation is stored here. `words` holds the Hebrew and Greek
source text word by word (keyed by verse id), never English verse text; the
app shows verses from its own Bible databases.

Sources and licences
- Words: STEPBible-Data (https://github.com/STEPBible/STEPBible-Data),
  "Translators Amalgamated OT+NT": TAHOT (Hebrew OT) and TAGNT (Greek NT),
  CC BY 4.0, data created by www.STEPBible.org based on work at Tyndale House
  Cambridge. Hebrew follows the Leningrad codex with the Qere (as the KJV
  does); words STEPBible adds from the LXX ("X") are left out. Greek keeps
  the words of the Textus Receptus (edition "TR", the KJV's Greek).
- Lexicon, Greek: STEPBible TBESG (Translators Brief lexicon of Extended
  Strongs for Greek), CC BY 4.0; its definitions are Abbott-Smith (1922) and
  Middle Liddell (1889), both public domain.
- Lexicon, Hebrew: lemma, transliteration and gloss from STEPBible TBESH
  (CC BY 4.0). TBESH's "Meaning" column is NOT used: STEPBible says it comes
  from Online Bible's Abridged BDB and needs Online Bible's permission. The
  definitions come instead from Strong's Hebrew Dictionary (1890, public
  domain) as edited by the Open Scriptures Hebrew Bible project,
  HebrewStrong.xml in https://github.com/openscriptures/HebrewLexicon
  (CC BY 4.0).
- Commentary: Matthew Henry's Concise Commentary on the Whole Bible
  (1706-1721; public domain), from the CrossWire SWORD module MHCC as
  converted to one JSON file per book in
  https://github.com/daiyip/interactive-bible (data/commentary). Henry has
  no comment on Leviticus 19 or Psalm 108 in this edition.

Versification: every word is keyed to the app's KJV/English versification,
VerseID = book * 1_000_000 + chapter * 1_000 + verse (books 1-66). TAHOT's
first reference is the English one (Hebrew numbering in brackets is
ignored); Psalm titles (STEPBible's verse 0) belong to verse 1, as in the
app's KJV. TAGNT's KJV reference in [square brackets] wins over its NRSV
one. The build checks every verse id against Genesis/Resources/Bibles/KJV.sqlite
(reading ids only) and fails if any word lands outside the KJV.

Strong's numbers are STEPBible's: a letter and four digits, plus an optional
upper-case disambiguation letter (H0430G, H1254A, G2316). Look-ups fall back
from H1254A to the plain number H1254 (see WordStudyRepository.swift).

Usage (git clone through the proxy; raw downloads are blocked):
  git clone --depth 1 --filter=blob:none --sparse https://github.com/STEPBible/STEPBible-Data /tmp/step
  git -C /tmp/step sparse-checkout set --no-cone "/Lexicons/TBES*" "/Translators Amalgamated OT+NT/TA*"
  git clone --depth 1 --filter=blob:none --sparse https://github.com/openscriptures/HebrewLexicon /tmp/hebrewlexicon
  git -C /tmp/hebrewlexicon sparse-checkout set --no-cone /HebrewStrong.xml
  git clone --depth 1 --filter=blob:none --sparse https://github.com/daiyip/interactive-bible /tmp/interactive-bible
  git -C /tmp/interactive-bible sparse-checkout set --no-cone /data/commentary/
  python3 -I Tools/StudyData/build_wordstudy.py /tmp/step /tmp/hebrewlexicon /tmp/interactive-bible
"""
import collections
import datetime
import glob
import html
import json
import os
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "Tools", "BibleData"))
from books import OSIS_TO_NUMBER  # noqa: E402

OUTPUT = os.path.join(ROOT, "Genesis", "Resources", "Study", "WordStudy.sqlite")
KJV = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "KJV.sqlite")

# STEPBible's book codes, in Protestant order (1-66).
STEP_BOOKS = (
    "Gen Exo Lev Num Deu Jos Jdg Rut 1Sa 2Sa 1Ki 2Ki 1Ch 2Ch Ezr Neh Est Job Psa Pro Ecc Sng Isa Jer Lam "
    "Ezk Dan Hos Jol Amo Oba Jon Mic Nam Hab Zep Hag Zec Mal Mat Mrk Luk Jhn Act Rom 1Co 2Co Gal Eph Php "
    "Col 1Th 2Th 1Ti 2Ti Tit Phm Heb Jas 1Pe 2Pe 1Jn 2Jn 3Jn Jud Rev"
).split()
STEP_BOOK = {code: number for number, code in enumerate(STEP_BOOKS, start=1)}

# "Gen.1.1#01=L", "Mal.4.1(3.19)#01=L", "3Jn.1.15[1.14]#03=NKO"
WORD_REF = re.compile(
    r"^(?P<book>[0-9A-Za-z]{3})\.(?P<ch>\d+)\.(?P<v>\d+)"
    r"(?:\((?P<heb>[\d.]+)\)|\[(?P<kjv>[\d.]+)\]|\{(?P<other>[\d.]+)\})?"
    r"#(?P<word>\d+)=(?P<type>\S+)$"
)
STRONGS = re.compile(r"^([HG])0*(\d+)([A-Za-z]?)$")


def verse_id(book, chapter, verse):
    return book * 1_000_000 + chapter * 1_000 + verse


def normalise_strongs(tag):
    """'H430' / 'h0430g' / 'G2316' -> 'H0430G' / 'G2316': letter, 4+ digits, upper-case suffix."""
    match = STRONGS.match(tag.strip())
    if not match:
        return None
    letter, number, suffix = match.groups()
    return f"{letter.upper()}{int(number):04d}{suffix.upper()}"


def base_strongs(tag):
    """'H1254A' -> 'H1254'."""
    return tag.rstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ")


def clean_markup(text, keep_breaks=False):
    """Lexicon HTML to plain text; <br> becomes a line break when kept."""
    text = re.sub(r"<\s*br\s*/?\s*>", "\n" if keep_breaks else " ", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = text.replace("__", "")
    lines = [re.sub(r"[ \t ]+", " ", line).strip() for line in text.split("\n")]
    return "\n".join(line for line in lines if line) if keep_breaks else " ".join(lines).strip()


def read_rows(path):
    with open(path, encoding="utf-8-sig") as handle:
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            match = WORD_REF.match(fields[0])
            if match:
                yield match, fields


# MARK: Words

def hebrew_words(step):
    """(verse id, source order, word, translit, strongs, gloss, morph) for the OT."""
    files = sorted(glob.glob(os.path.join(step, "Translators Amalgamated OT+NT", "TAHOT *.txt")))
    assert len(files) == 4, files
    order = 0
    for path in files:
        for ref, fields in read_rows(path):
            if ref["type"].startswith("X"):  # Words restored from the LXX: not in the KJV's Hebrew.
                continue
            book = STEP_BOOK[ref["book"]]
            chapter, verse = int(ref["ch"]), int(ref["v"])
            verse = max(verse, 1)  # Psalm titles (verse 0) are part of verse 1 in the KJV.
            # Separators out; the Leningrad paragraph marks (a lone pe or samekh after
            # the verse) aren't words.
            text = fields[1].replace("/", "").replace("\\", "").strip()
            text = re.sub(r"\s+[\u05e4\u05e1]$", "", text)
            translit = fields[2].replace("/", "").strip()
            gloss = re.sub(r"\s+", " ", fields[3].replace("/", " ")).strip()
            tags = fields[4]
            root = re.search(r"\{([^}]+)\}", tags)
            tag = root.group(1) if root else re.split(r"[/\\+]", tags)[0]
            strongs = normalise_strongs(tag.split("+")[0])
            order += 1
            yield verse_id(book, chapter, verse), order, text, translit, strongs, gloss, fields[5].strip()


def greek_words(step):
    files = sorted(glob.glob(os.path.join(step, "Translators Amalgamated OT+NT", "TAGNT *.txt")))
    assert len(files) == 2, files
    order = 0
    for path in sorted(files, key=lambda p: "Act" in p):  # Mat-Jhn before Act-Rev
        for ref, fields in read_rows(path):
            if not re.search(r"\bTR\b", fields[5]):  # Keep the Textus Receptus, the KJV's Greek.
                continue
            book = STEP_BOOK[ref["book"]]
            if ref["kjv"]:
                chapter, verse = (int(n) for n in ref["kjv"].split("."))
            else:
                chapter, verse = int(ref["ch"]), int(ref["v"])
            match = re.match(r"^(.*?)\s*\(([^)]*)\)\s*$", fields[1])
            text, translit = (match.group(1), match.group(2)) if match else (fields[1], "")
            # Editorial marks aren't words: paragraph signs and NA's [[double brackets]].
            text = re.sub(r"\[\[|\]\]|[¶¬]", "", text)
            gloss = re.sub(r"^\{[\d.]+\}\s*", "", fields[2].strip()).rstrip(",.;:·")
            parts = [part.strip() for part in fields[3].split("+")]
            strongs = normalise_strongs(parts[0].split("=")[0])
            morph = " + ".join(part.split("=", 1)[1] for part in parts if "=" in part)
            order += 1
            yield verse_id(book, chapter, verse), order, text.strip(), translit.strip(), strongs, gloss, morph


# MARK: Lexicon

def step_lexicon(path, language):
    """dStrong -> (lemma, translit, gloss, meaning) from a TBES* file."""
    entries = {}
    with open(path, encoding="utf-8-sig") as handle:
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 8 or not re.match(r"^[HG]\d", fields[0]):
                continue
            key = normalise_strongs(fields[1].split()[0])
            if key and key not in entries:
                entries[key] = (fields[3].strip(), fields[4].strip(), fields[6].strip(), fields[7])
    return entries


def strongs_hebrew(path):
    """Strong's number (H0430) -> (definition, derivation, KJV usage) from OSHB HebrewStrong.xml."""
    ns = "{http://openscriptures.github.com/morphhb/namespace}"
    entries = {}

    def text_of(element):
        if element is None:
            return ""
        return re.sub(r"\s+", " ", "".join(element.itertext())).strip()

    for entry in ET.parse(path).getroot().iter(f"{ns}entry"):
        key = normalise_strongs(entry.get("id", ""))
        if not key:
            continue
        meaning = text_of(entry.find(f"{ns}meaning"))
        source = text_of(entry.find(f"{ns}source"))
        usage = text_of(entry.find(f"{ns}usage"))
        entries[key] = (meaning, source, usage)
    return entries


# MARK: Commentary

def clean_comment(text):
    text = re.sub(r"\{([^{}|]*)\|[^{}]*\}", r"\1", text)  # {Mal 2:10|Mal.2.10} -> Mal 2:10
    text = text.replace("{", "").replace("}", "")
    text = re.sub(r"^\s*--\s*", "", text)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


RANGE = re.compile(r"^\((\d+)(?:\s*[-–]\s*(\d+))?\)$")


def commentary(folder, last_verse):
    """(book, chapter, start, end, title, text) for every section, plus book introductions."""
    sections, intros = [], {}
    files = glob.glob(os.path.join(folder, "*.json"))
    assert len(files) == 66, f"expected 66 books, found {len(files)}"
    for path in files:
        osis = os.path.splitext(os.path.basename(path))[0]
        book = OSIS_TO_NUMBER[osis]
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        intro = [clean_comment(p) for p in data.get("intro", [])]
        if any(intro):
            intros[book] = "\n\n".join(p for p in intro if p)
        for index, chapter_data in enumerate(data["ch"]):
            chapter = index + 1
            titles = {int(start): title for title, start, _ in chapter_data.get("o", [])}
            for start, end, paragraphs in chapter_data["s"]:
                paragraphs = list(paragraphs)
                # Some chapters carry Henry's outline as the first paragraphs:
                # "Chapter Outline", then title, "(1-4)", title, "(5-9)", ...
                if paragraphs and paragraphs[0].strip() == "Chapter Outline":
                    paragraphs.pop(0)
                    while len(paragraphs) >= 2 and RANGE.match(paragraphs[1].strip()):
                        title, span = paragraphs.pop(0), RANGE.match(paragraphs.pop(0).strip())
                        titles.setdefault(int(span.group(1)), clean_comment(title))
                # A single section may start with its title, then "--" and the comment.
                title = titles.get(int(start))
                if len(paragraphs) >= 2 and paragraphs[1].lstrip().startswith("--") and len(paragraphs[0]) < 200:
                    title = title or clean_comment(paragraphs[0])
                    paragraphs.pop(0)
                body = "\n\n".join(p for p in (clean_comment(p) for p in paragraphs) if p)
                if not body:
                    continue
                last = last_verse.get((book, chapter))
                assert last, f"{osis} {chapter} is not in the KJV"
                start, end = max(1, int(start)), min(int(end), last)
                assert start <= end, f"{osis} {chapter}:{start}-{end}"
                sections.append((book, chapter, start, end, title, body))
    sections.sort()
    return sections, intros


# MARK: Build

def delta_list(ids):
    """[1001001, 1001003, 1002001] -> '1001001,2,998'."""
    return ",".join(str(b - a) for a, b in zip([0] + ids, ids))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    step, hebrew_lexicon, interactive_bible = (os.path.abspath(p) for p in sys.argv[1:])

    kjv = sqlite3.connect(f"file:{KJV}?mode=ro", uri=True)
    kjv_verses = {row[0] for row in kjv.execute("SELECT id FROM verses")}
    last_verse = {(b, c): v for b, c, v in kjv.execute("SELECT book, chapter, MAX(verse) FROM verses GROUP BY book, chapter")}
    kjv.close()

    # Words, renumbered 1... within each (KJV) verse in source order.
    words, positions = [], collections.Counter()
    for row in list(hebrew_words(step)) + list(greek_words(step)):
        verse, _, text, translit, strongs, gloss, morph = row
        positions[verse] += 1
        words.append((verse, positions[verse], text, translit or None, strongs, gloss or None, morph or None))
    outside = sorted({w[0] for w in words} - kjv_verses)
    assert not outside, f"words outside the KJV versification: {outside[:20]}"
    missing = sorted(kjv_verses - {w[0] for w in words})
    print(f"words: {len(words)}; KJV verses without words: {len(missing)} {missing[:20]}")

    # Lexicon.
    tbesh = step_lexicon(glob.glob(os.path.join(step, "Lexicons", "TBESH *.txt"))[0], "hebrew")
    tbesg = step_lexicon(glob.glob(os.path.join(step, "Lexicons", "TBESG *.txt"))[0], "greek")
    strong = strongs_hebrew(os.path.join(hebrew_lexicon, "HebrewStrong.xml"))
    used = {w[4] for w in words if w[4]}
    used_bases = {base_strongs(s) for s in used}

    def wanted(key):
        number = int(key[1:5]) if key[1:5].isdigit() else 0
        in_strong = number <= (8674 if key[0] == "H" else 5624)
        return key in used or base_strongs(key) in used_bases or (in_strong and len(base_strongs(key)) == 5)

    lexicon = []
    for key, (lemma, translit, gloss, _meaning) in tbesh.items():
        if not wanted(key):
            continue
        definition, derivation, usage = strong.get(base_strongs(key), ("", "", ""))
        lexicon.append((key, lemma, translit, gloss, definition or None, derivation or None, usage or None, "hebrew"))
    for key, (lemma, translit, gloss, meaning) in tbesg.items():
        if not wanted(key):
            continue
        definition = clean_markup(meaning, keep_breaks=True)
        definition = re.sub(r"\s*\((AS|MD)\)\s*$", "", definition)  # source tags
        lexicon.append((key, lemma, translit, gloss, definition or None, None, None, "greek"))
    # Strong's Hebrew numbers STEPBible doesn't list on their own.
    have_bases = {base_strongs(row[0]) for row in lexicon}
    for key, (definition, derivation, usage) in strong.items():
        if key not in have_bases:
            lexicon.append((key, None, None, None, definition or None, derivation or None, usage or None, "hebrew"))
    lexicon_keys = {row[0] for row in lexicon}
    lexicon_bases = {base_strongs(k) for k in lexicon_keys}
    unknown = sorted(s for s in used if s not in lexicon_keys and base_strongs(s) not in lexicon_bases)
    print(f"lexicon: {len(lexicon)}; word tags without an entry: {len(unknown)} {unknown[:20]}")

    occurrences = collections.Counter(w[4] for w in words if w[4])
    verses_by_strongs = collections.defaultdict(set)
    for w in words:
        if w[4]:
            verses_by_strongs[w[4]].add(w[0])

    sections, intros = commentary(os.path.join(interactive_bible, "data", "commentary"), last_verse)
    covered = set()
    for book, chapter, start, end, _, _ in sections:
        covered.update(verse_id(book, chapter, v) for v in range(start, end + 1))
    uncovered = sorted(kjv_verses - covered)
    print(f"commentary: {len(sections)} sections, {len(intros)} introductions; KJV verses not covered: {len(uncovered)}")

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    db = sqlite3.connect(OUTPUT)
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        -- Each distinct word form once; word_forms places them in verses.
        CREATE TABLE forms (
            id INTEGER PRIMARY KEY,
            text TEXT NOT NULL,          -- the Hebrew or Greek word, verbatim
            translit TEXT,
            strongs TEXT,                -- STEPBible dStrong: H0430G, G2316
            gloss TEXT,                  -- English gloss in context
            morph TEXT                   -- ETCBC (Hebrew) / Robinson-style (Greek) morphology
        );
        CREATE TABLE word_forms (
            verse INTEGER NOT NULL,      -- book*1000000 + chapter*1000 + verse (KJV versification)
            position INTEGER NOT NULL,   -- 1... in the original-language order
            form INTEGER NOT NULL REFERENCES forms(id),
            PRIMARY KEY (verse, position)
        ) WITHOUT ROWID;
        CREATE VIEW words AS
            SELECT w.verse, w.position, f.text, f.translit, f.strongs, f.gloss, f.morph
            FROM word_forms w JOIN forms f ON f.id = w.form;
        CREATE TABLE lexicon (
            strongs TEXT PRIMARY KEY,
            lemma TEXT,
            translit TEXT,
            gloss TEXT,
            definition TEXT,             -- plain text; may contain line breaks
            derivation TEXT,             -- Strong's derivation (Hebrew)
            usage TEXT,                  -- Strong's KJV renderings (Hebrew)
            language TEXT NOT NULL       -- 'hebrew' | 'greek'
        );
        -- How many words carry each tag, and the verses they're in: ascending verse
        -- ids as comma-separated decimal deltas (the first is the id itself).
        CREATE TABLE occurrences (
            strongs TEXT PRIMARY KEY,
            count INTEGER NOT NULL,
            verses TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE TABLE commentary (
            id INTEGER PRIMARY KEY,
            source TEXT NOT NULL,        -- 'mhcc'
            start_verse INTEGER NOT NULL,
            end_verse INTEGER NOT NULL,
            title TEXT,                  -- Henry's outline heading for the section, if any
            text TEXT NOT NULL           -- paragraphs separated by blank lines
        );
        CREATE TABLE introductions (
            source TEXT NOT NULL,
            book INTEGER NOT NULL,
            text TEXT NOT NULL,
            PRIMARY KEY (source, book)
        ) WITHOUT ROWID;
    """)
    forms = {}
    for word in sorted(words, key=lambda w: (w[4] or "", w[2], w[3] or "", w[5] or "", w[6] or "")):
        forms.setdefault(word[2:], len(forms) + 1)
    db.executemany("INSERT INTO forms VALUES (?, ?, ?, ?, ?, ?)", [(i, *f) for f, i in forms.items()])
    db.executemany("INSERT INTO word_forms VALUES (?, ?, ?)", [(w[0], w[1], forms[w[2:]]) for w in words])
    db.executemany("INSERT INTO lexicon VALUES (?, ?, ?, ?, ?, ?, ?, ?)", sorted(lexicon))
    db.executemany("INSERT INTO occurrences VALUES (?, ?, ?)", [
        (tag, count, delta_list(sorted(verses_by_strongs[tag]))) for tag, count in sorted(occurrences.items())
    ])
    db.executemany(
        "INSERT INTO commentary (source, start_verse, end_verse, title, text) VALUES ('mhcc', ?, ?, ?, ?)",
        [(verse_id(b, c, s), verse_id(b, c, e), title, text) for b, c, s, e, title, text in sections],
    )
    db.executemany("INSERT INTO introductions VALUES ('mhcc', ?, ?)", sorted(intros.items()))
    db.executescript("""
        CREATE INDEX commentary_range ON commentary(start_verse, end_verse);
    """)
    db.executemany("INSERT INTO meta VALUES (?, ?)", [
        ("built", datetime.date.today().isoformat()),
        ("words_source", "STEPBible TAHOT (Hebrew OT) and TAGNT (Greek NT), https://github.com/STEPBible/STEPBible-Data"),
        ("words_license", "CC BY 4.0"),
        ("lexicon_source", "STEPBible TBESG and TBESH (gloss, lemma, transliteration); Hebrew definitions from Strong's Hebrew Dictionary via the Open Scriptures Hebrew Bible project (HebrewStrong.xml, https://github.com/openscriptures/HebrewLexicon)"),
        ("lexicon_license", "CC BY 4.0 (STEPBible; Open Scriptures). Abbott-Smith (1922), Middle Liddell (1889) and Strong (1890) are public domain."),
        ("commentary_source", "Matthew Henry's Concise Commentary (CrossWire SWORD module MHCC) via https://github.com/daiyip/interactive-bible"),
        ("commentary_license", "Public domain"),
        ("attribution", "Original-language data created by www.STEPBible.org based on work at Tyndale House Cambridge (CC BY 4.0). Hebrew definitions from Strong's Hebrew Dictionary, Open Scriptures Hebrew Bible project (CC BY 4.0). Commentary: Matthew Henry's Concise Commentary (public domain)."),
        ("versification", "KJV"),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"wrote {OUTPUT}: {os.path.getsize(OUTPUT) / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
