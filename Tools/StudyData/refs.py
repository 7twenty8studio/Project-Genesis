"""Bible references in Easton's English and in its Spanish and Portuguese
translations, as (book, chapter, verse) so a check can compare them whole:
the numbers alone would let "John 3:16" become "Romanos 3:16".

    references("Gen. 4:8, 9; 5:3 (comp. 1 John 3:12)", "en")
    -> [("Gen", 4, 8), ("Gen", 5, 3), ("1John", 3, 12)]

Books are the codes in scripture_quotes.BOOKS. The Spanish and Portuguese
abbreviations are the ones in translations/bios/INSTRUCTIONS.md (the
table the translators follow), plus each book's full name. A chapter:verse
right after another reference ("…5:3; 6:1") belongs to the same book; one
on its own ("(34:6)") has the book None, and still has to match.
"""
import os
import re

import scripture_quotes

HERE = os.path.dirname(os.path.abspath(__file__))
INSTRUCTIONS = os.path.join(HERE, "translations", "bios", "INSTRUCTIONS.md")
BOOKS = scripture_quotes.BOOKS

# Easton's own spellings that aren't in the table (and his slips).
ENGLISH_EXTRA = {
    "Exod.": "Ex", "Judge.": "Judg", "Exek.": "Ezek", "Mat.": "Matt", "Job.": "Job",
    "Psalm": "Ps", "Psalms": "Ps", "1 Thes.": "1Thess", "2 King": "2Kings", "Ge": "Gen",
    "Acts.": "Acts", "1 Sam": "1Sam", "John.": "John",
    # Full names ("the prophet Isaiah, 19:13").
    "Genesis": "Gen", "Exodus": "Ex", "Leviticus": "Lev", "Numbers": "Num",
    "Deuteronomy": "Deut", "Joshua": "Josh", "Judges": "Judg", "Isaiah": "Isa",
    "Jeremiah": "Jer", "Ezekiel": "Ezek", "Daniel": "Dan", "Hosea": "Hos",
    "Matthew": "Matt", "Romans": "Rom", "Hebrews": "Heb", "Revelation": "Rev",
}


def _table():
    """{lang: {name: book code}} from INSTRUCTIONS.md's Books table."""
    names = {"en": dict(ENGLISH_EXTRA), "es": {}, "pt": {}}
    rows = [line for line in open(INSTRUCTIONS, encoding="utf-8") if line.startswith("| ") and "---" not in line]
    rows = [r for r in rows if not r.startswith("| Easton")]
    assert len(rows) == len(BOOKS), f"{len(rows)} book rows in INSTRUCTIONS.md"
    for code, row in zip(BOOKS, rows):
        easton, es, pt = [c.strip() for c in row.strip().strip("|").split("|")]
        names["en"][easton] = code
        names["en"][easton.rstrip(".")] = code
        for lang, cell in (("es", es), ("pt", pt)):
            m = re.match(r"(.+?) \((.+)\)$", cell)
            names[lang][m.group(1)] = code
            names[lang][m.group(2)] = code
    return names


NAMES = _table()
_PATTERNS = {}


def _pattern(lang):
    if lang not in _PATTERNS:
        alternatives = sorted(NAMES[lang], key=len, reverse=True)
        book = "|".join(re.escape(n.rstrip(".")) for n in alternatives)
        # A book (not inside a longer word), an optional period, then chapter:verse.
        _PATTERNS[lang] = re.compile(rf"(?<![\w-])({book})\.?,?\s+(\d+):\s?(\d+)|(?<![\d:])(\d+):\s?(\d+)", re.IGNORECASE if lang == "en" else 0)
    return _PATTERNS[lang]


def _code(lang, name):
    table = NAMES[lang]
    found = table.get(name) or table.get(name + ".")
    if not found and lang == "en":  # Easton's "jer. 40:1"
        found = table.get(name.capitalize()) or table.get(name.capitalize() + ".")
    return found


def references(text, lang):
    """[(book code or None, chapter, verse)] in the order they appear."""
    out = []
    book, end = None, None
    for m in _pattern(lang).finditer(text):
        if m.group(1):
            book = _code(lang, m.group(1))
            out.append((book, int(m.group(2)), int(m.group(3))))
        else:
            between = text[end:m.start()] if end is not None else None
            # "…4:8, 9; 5:3" and "…4:8-5:3" carry the book on.
            carried = book if between is not None and re.fullmatch(r"[\s,;\-–]*(?:\d+[\s,;\-–]*)*", between) else None
            out.append((carried, int(m.group(4)), int(m.group(5))))
            book = carried
        end = m.end()
    return out


def parse(reference):
    """'1Sam 1:26-28' (a book code), or several joined by '; ' ('Num 13:29;
    1Sam 15:7') -> the KJV verse ids they cover."""
    ids = []
    for part in reference.split(";"):
        m = re.fullmatch(r"(\w+) (\d+):(\d+)(?:-(\d+))?", part.strip())
        if not m or m.group(1) not in BOOKS:
            raise ValueError(f"not a reference: {reference!r} (write it as 'Gen 4:4-5', book codes from scripture_quotes.BOOKS)")
        book = BOOKS.index(m.group(1)) + 1
        chapter, first = int(m.group(2)), int(m.group(3))
        last = int(m.group(4) or first)
        if last < first:
            raise ValueError(f"not a reference: {reference!r}")
        ids += [book * 1_000_000 + chapter * 1_000 + v for v in range(first, last + 1)]
    return ids


def label(ref):
    book, chapter, verse = ref
    return f"{book or '?'} {chapter}:{verse}"
