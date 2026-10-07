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
  does); words STEPBible adds from the LXX ("X") are left out.
- Greek (table `greek_words`): four editions rebuilt from TAGNT, Nestle-Aland
  28 (NA28), Westcott-Hort 1881 (WH), Scrivener's Textus Receptus 1894 (TR)
  and Robinson-Pierpont's Byzantine text 2005 (Byz). TAGNT lists each word
  once, in NA28's order and spelling (another edition's where NA28 lacks
  it), with the editions that have it; the different words other editions
  read at the same place (meaning variants); each edition's own spelling
  where it noted one (spelling variants); and words an edition puts
  elsewhere ("TR»2": two words later, "TR«3": after the word three before).
  See greek_words(). Nothing is respelled: a word is TAGNT's text, or the
  spelling TAGNT gives for that edition, with TAGNT's punctuation after it.
  Spellings TAGNT doesn't record (some Byzantine forms) follow NA28; complex
  reorderings that TAGNT notes word by word can come out slightly unlike
  the printed edition. Checked against Robinson's Scrivener and
  Robinson-Pierpont texts (github.com/byztxt, unaccented, word for word):
  the TR matches in 7262 of 7957 verses and the Byzantine in 6964 of 7956.
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
import unicodedata
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
            yield verse_id(book, chapter, verse), order, text, translit, strongs, gloss, fields[5].strip(), None


# Greek editions kept, as bits in greek_words.editions / .found (GreekEdition
# in WordStudyRepository.swift uses the same values).
GREEK_EDITIONS = {"NA28": 1, "WH": 2, "TR": 4, "Byz": 8}
EDITION_TOKEN = re.compile(r"^(NA28|WH|TR|Byz)(?:([«»])(\d+(?:\.\d+)?))?$")
# "εὐδοκία (t=eudokia) good will - G2107=N-NSF in: TR+Byz"
MEANING_VARIANT = re.compile(
    r"^\s*(?P<text>\S.*?) \((?P<kind>[a-zA-Z])=(?P<translit>[^)]*)\) (?P<gloss>.*?) - "
    r"(?P<tags>[GH]\d\S*=\S+(?: \+ [GH]\d\S*=\S+)*) in: (?P<editions>.+?)\s*$"
)
TRAILING_PUNCTUATION = re.compile(r"[,.;\u00b7\u0387\u037e]+$")  # comma, stop, question mark, raised dot


def greek_editions(text):
    """'NA28+NA27+TR»1+Byz«14.24' -> {4: 1, 1: 0, 8: 0}: the kept editions
    that have the word, each with its displacement (+n: n words later, -n:
    earlier; 0 in place). A move to another verse (Byz«14.24, the Romans
    doxology) counts as in place: OriginalVersification lines verses up."""
    found = {}
    for token in text.split("+"):
        match = EDITION_TOKEN.match(token.strip())
        if not match:
            continue
        edition, direction, amount = match.groups()
        shift = 0
        if direction and "." not in amount:
            shift = int(amount) if direction == "»" else -int(amount)
        found[GREEK_EDITIONS[edition]] = shift
    return found


GREEK_LETTERS = {
    "α": "a", "β": "b", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "ē", "θ": "th", "ι": "i", "κ": "k",
    "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "π": "p", "ρ": "r", "σ": "s", "ς": "s", "τ": "t",
    "υ": "u", "φ": "ph", "χ": "ch", "ψ": "ps", "ω": "ō",
}


def transliterate(word):
    """Greek to TAGNT-style transliteration (agrees with TAGNT's own for
    99.4% of its words), for edition spellings TAGNT gives no
    transliteration of. Rough breathing h/rh, γγ ng, η ē, ω ō, υ u,
    elision kept; a perispomenon η with iota subscript is "ēa" as in TAGNT."""
    letters = []
    for char in unicodedata.normalize("NFD", word):
        if unicodedata.category(char).startswith("M"):
            if letters:
                letters[-1][2].add(char)
        elif char.lower() in GREEK_LETTERS:
            letters.append([char.lower(), char != char.lower(), set()])
        elif char == "\u1fbd":  # elision
            letters.append([char, False, set()])
    rough = any("\u0314" in marks for _, _, marks in letters[:2])
    out = ""
    for index, (letter, _, marks) in enumerate(letters):
        following = letters[index + 1][0] if index + 1 < len(letters) else ""
        if letter == "\u1fbd":
            out += letter
            continue
        sound = "n" if letter == "γ" and following == "γ" else GREEK_LETTERS[letter]
        if letter == "η" and "\u0342" in marks and "\u0345" in marks and index > 0:
            sound = "ēa"
        if letter == "ρ" and index == 0 and "\u0314" in marks:
            sound = "rh"
        if index == 0 and "\u0314" in marks and letter in "ειυ" and following in "αεηιουω":
            sound += "'"
        out += sound
    if rough and letters and letters[0][0] in "αεηιουωρ" and not out.startswith("rh"):
        out = "h" + out
    if letters and letters[0][1]:
        out = out[:1].upper() + out[1:]
    return out


def greek_words(step):
    """Every reading of every TAGNT word that one of the kept editions has:
    (verse id, slot, word number, editions, found, text, translit, strongs,
    gloss, morph).

    TAGNT lists each word once, in NA28's order, with the editions that have
    it (column 6: NA28, NA27, Tyn, SBL, WH, Treg, TR, Byz; "TR»2" = two
    words later in that edition, "TR«3" = placed after the word three
    before). Column 7 gives the different words other editions have at the
    same place ("εὐδοκία (t=eudokia) good will - G2107=N-NSF in: TR+Byz",
    several joined by ¦) and column 8 each edition's own spelling of the
    word ("TR: Δαβὶδ ; +Tyn+WH: Δαυεὶδ ;"). Column 2 is NA28's spelling, or
    another edition's where NA28 lacks the word. A row here is one spelling
    of one word at one place; `editions` says which kept editions read
    exactly that, `found` which have the word there in any spelling.
    Punctuation (TAGNT's, after the Tyndale House GNT) is the same for every
    edition, so an edition's own spelling keeps the punctuation that
    follows the word in column 2."""
    files = sorted(glob.glob(os.path.join(step, "Translators Amalgamated OT+NT", "TAGNT *.txt")))
    assert len(files) == 2, files
    # Words of one TAGNT verse that the KJV numbers as one verse go together;
    # where the KJV joins parts of two (Mat.17.15[17.14]) the later part's
    # words are numbered on after the earlier one's.
    groups, offsets = [], collections.Counter()
    for path in sorted(files, key=lambda p: "Act" in p):  # Mat-Jhn before Act-Rev
        for ref, fields in read_rows(path):
            book = STEP_BOOK[ref["book"]]
            if ref["kjv"]:
                chapter, verse = (int(n) for n in ref["kjv"].split("."))
            else:
                chapter, verse = int(ref["ch"]), int(ref["v"])
            key = (ref["book"], ref["ch"], ref["v"], verse_id(book, chapter, verse))
            if not groups or groups[-1][0] != key:
                groups.append((key, []))
            groups[-1][1].append((int(ref["word"]), fields))
    for key, rows in groups:
        verse = key[3]
        yield from greek_verse(verse, rows, offsets[verse])
        offsets[verse] += max(number for number, _ in rows)


def greek_verse(verse, rows, offset):
    """The readings of one TAGNT verse's words (or the part of one the KJV
    gives another verse), numbered from `offset` + 1."""
    count = max(number for number, _ in rows)
    seen = collections.Counter()
    for number, fields in rows:
        match = re.match(r"^(.*?)\s*\(([^)]*)\)\s*$", fields[1])
        text, translit = (match.group(1), match.group(2)) if match else (fields[1], "")
        # Editorial marks aren't words: paragraph signs and NA's [[double brackets]].
        text = re.sub(r"\[\[|\]\]|[¶¬]", "", text).strip()
        translit = translit.strip()
        punctuation = TRAILING_PUNCTUATION.search(text)
        punctuation = punctuation.group(0) if punctuation else ""
        gloss = re.sub(r"^\{[\d.]+\}\s*", "", fields[2].strip()).rstrip(",.;:·")
        parts = [part.strip() for part in fields[3].split("+")]
        strongs = normalise_strongs(parts[0].split("=")[0])
        morph = " + ".join(part.split("=", 1)[1] for part in parts if "=" in part)

        base = greek_editions(fields[5])
        # Each edition's own spelling where it differs (same word, same grammar).
        spellings = {}
        for part in fields[7].split(";"):
            part = part.strip().lstrip("+").strip()
            if ":" not in part:
                continue
            editions, spelling = part.split(":", 1)
            spelling = spelling.strip()
            for bit, shift in greek_editions(editions).items():
                spellings[bit] = (spelling + punctuation, shift)
        # Different words other editions have here.
        variants = []
        for part in fields[6].split("¦"):
            if not part.strip():
                continue
            found = MEANING_VARIANT.match(part)
            assert found, f"{fields[0]}: unreadable variant {part!r}"
            tags = [tag.strip() for tag in found["tags"].split(" + ")]
            variants.append({
                "text": found["text"].strip() + punctuation,
                "translit": found["translit"].strip(),
                "gloss": found["gloss"].strip().rstrip(",.;:·"),
                # "G0846|G3165«G3450": alternatives, then the tag used (after «).
                "strongs": normalise_strongs(tags[0].split("=")[0].split("«")[-1].split("|")[0]),
                "morph": " + ".join(tag.split("=", 1)[1] for tag in tags),
                "editions": greek_editions(found["editions"]),
            })

        base_found = sum(set(base) | set(spellings))
        readings = collections.OrderedDict()  # (text, translit, strongs, gloss, morph, found, shift) -> editions
        for bit in GREEK_EDITIONS.values():
            variant = next((v for v in variants if bit in v["editions"]), None)
            if variant:
                reading = (variant["text"], variant["translit"], variant["strongs"], variant["gloss"],
                           variant["morph"], sum(variant["editions"]), variant["editions"][bit])
            elif bit in base or bit in spellings:
                spelling, shift = spellings.get(bit, (text, base.get(bit, 0)))
                shift = shift or base.get(bit, 0)
                own_translit = translit
                if spelling != text and transliterate(spelling) != transliterate(text):
                    own_translit = transliterate(spelling)
                reading = (spelling, own_translit, strongs, gloss, morph, base_found, shift)
            else:
                continue
            readings[reading] = readings.get(reading, 0) | bit
        for (word, word_translit, word_strongs, word_gloss, word_morph, found, shift), editions in readings.items():
            # In place: slot 2n. Moved: just after word n±shift, slot 2(n±shift)+1.
            anchor = number if shift == 0 else min(max(number + shift, 0), count)
            slot = 2 * (offset + anchor) + (0 if shift == 0 else 1)
            for bit in GREEK_EDITIONS.values():
                if editions & bit:
                    seen[(number, bit)] += 1
                    assert seen[(number, bit)] == 1, f"{verse} #{number}: two readings for edition {bit}"
            yield verse, slot, offset + number, editions, found, word, word_translit, word_strongs, word_gloss, word_morph


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

    # Hebrew words, renumbered 1... within each (KJV) verse in source order.
    words, positions = [], collections.Counter()
    for row in hebrew_words(step):
        verse, _, text, translit, strongs, gloss, morph, _ = row
        positions[verse] += 1
        words.append((verse, positions[verse], text, translit or None, strongs, gloss or None, morph or None))
    # Greek: every kept edition's reading of every word (see greek_words).
    greek = [
        (verse, slot, number, editions, found, text, translit or None, strongs, gloss or None, morph or None)
        for verse, slot, number, editions, found, text, translit, strongs, gloss, morph in greek_words(step)
    ]
    every_verse = {w[0] for w in words} | {g[0] for g in greek}
    outside = sorted(every_verse - kjv_verses)
    assert not outside, f"words outside the KJV versification: {outside[:20]}"
    missing = sorted(kjv_verses - every_verse)
    print(f"Hebrew words: {len(words)}; Greek readings: {len(greek)}; KJV verses without words: {len(missing)} {missing[:20]}")
    for name, bit in GREEK_EDITIONS.items():
        print(f"  {name}: {sum(1 for g in greek if g[3] & bit)} words, "
              f"{sum(1 for g in greek if g[3] & bit and g[1] % 2)} moved")
    # Word study (lexicon, counts, verse lists) treats the Greek as one text:
    # each TAGNT word once per Strong's number, in any kept edition.
    tagged = [(w[0], w[4]) for w in words] + list({(g[0], g[2], g[7]): (g[0], g[7]) for g in greek}.values())

    # Lexicon.
    tbesh = step_lexicon(glob.glob(os.path.join(step, "Lexicons", "TBESH *.txt"))[0], "hebrew")
    tbesg = step_lexicon(glob.glob(os.path.join(step, "Lexicons", "TBESG *.txt"))[0], "greek")
    strong = strongs_hebrew(os.path.join(hebrew_lexicon, "HebrewStrong.xml"))
    used = {tag for _, tag in tagged if tag}
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

    occurrences = collections.Counter(tag for _, tag in tagged if tag)
    verses_by_strongs = collections.defaultdict(set)
    for verse, tag in tagged:
        if tag:
            verses_by_strongs[tag].add(verse)

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
        -- Hebrew words (the Greek is in greek_words).
        CREATE TABLE word_forms (
            verse INTEGER NOT NULL,      -- book*1000000 + chapter*1000 + verse (KJV versification)
            position INTEGER NOT NULL,   -- 1... in the original-language order
            form INTEGER NOT NULL REFERENCES forms(id),
            PRIMARY KEY (verse, position)
        ) WITHOUT ROWID;
        -- The Greek New Testament in four editions (TAGNT): every spelling of
        -- every word at every place one of them puts it. An edition's text of
        -- a verse is its rows (editions & bit) ordered by slot, number.
        -- Bits: 1 Nestle-Aland 28, 2 Westcott-Hort 1881, 4 Textus Receptus
        -- (Scrivener 1894), 8 Byzantine (Robinson-Pierpont 2005).
        CREATE TABLE greek_words (
            verse INTEGER NOT NULL,      -- book*1000000 + chapter*1000 + verse (KJV versification)
            slot INTEGER NOT NULL,       -- 2 * number in place; 2 * n + 1 when moved after word n
            number INTEGER NOT NULL,     -- TAGNT's word number in the verse (NA28 order)
            editions INTEGER NOT NULL,   -- editions that read exactly this word here
            found INTEGER NOT NULL,      -- editions that have this word here, in any spelling
            form INTEGER NOT NULL REFERENCES forms(id),
            PRIMARY KEY (verse, slot, number, editions)
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
    every_form = [w[2:] for w in words] + [g[5:] for g in greek]
    for form in sorted(every_form, key=lambda f: (f[2] or "", f[0], f[1] or "", f[3] or "", f[4] or "")):
        forms.setdefault(form, len(forms) + 1)
    db.executemany("INSERT INTO forms VALUES (?, ?, ?, ?, ?, ?)", [(i, *f) for f, i in forms.items()])
    db.executemany("INSERT INTO word_forms VALUES (?, ?, ?)", [(w[0], w[1], forms[w[2:]]) for w in words])
    db.executemany("INSERT INTO greek_words VALUES (?, ?, ?, ?, ?, ?)",
                   sorted((g[0], g[1], g[2], g[3], g[4], forms[g[5:]]) for g in greek))
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
        ("greek_editions", "1 NA28 (Nestle-Aland 28th edition), 2 WH (Westcott-Hort 1881), 4 TR (Scrivener 1894 Textus Receptus), 8 Byz (Robinson-Pierpont 2005 Byzantine), from TAGNT's editions, meaning-variant and spelling-variant columns"),
    ])
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"wrote {OUTPUT}: {os.path.getsize(OUTPUT) / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
