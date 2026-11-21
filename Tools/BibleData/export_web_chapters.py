#!/usr/bin/env python3
"""Writes the passages the guest sermon page shows (VRS-18): one JSON file per
KJV chapter for each Bible Versely may show on the web, read verbatim from the
same databases the app reads. Only free Bibles: KJV, ASV and WEB (public
domain), the Reina-Valera 1909 (public domain) and the Bíblia Livre (CC BY 4.0
Brasil, its credit carried in every file). YouVersion and licensed Bibles are
never exported; the page offers "Read in your Bible in Versely" instead.

Sermon blocks hold verse ids in the KJV's numbering, so the files are keyed by
KJV chapter: web/v1/<CODE>/<book>-<chapter>.json holds every verse of that
Bible whose text is in that KJV chapter, with its own chapter and verse
number. Where a Bible numbers verses differently (the WEB's Romans doxology,
the Reina-Valera's 44 places), the alignment is the app's own
(Genesis/Core/Study/OriginalVersification.swift and VersificationTables.swift),
so the web lands on the same verse as the app. The Bíblia Livre is read with
the KJV's numbering, as the app reads it.

    python3 Tools/BibleData/export_web_chapters.py --rv1909 RV1909.sqlite --out build/web-bibles
    python3 Tools/BibleData/export_web_chapters.py --rv1909 spa-rv1909.usfx.xml --out build/web-bibles
    python3 Tools/BibleData/export_web_chapters.py --rv1909 … --out build/web-bibles --check

--check rereads every file and compares it, verse for verse, with the
databases (text, numbers, alignment, credit); it fails on any difference.
Upload: build/web-bibles/web/v1 to the public "bibles" bucket as web/v1
(CHURCH_SERMONS.md › going live).
"""
import argparse
import json
import os
import re
import sqlite3
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BIBLES = os.path.join(ROOT, "Genesis", "Resources", "Bibles")
TABLES = os.path.join(ROOT, "Genesis", "Core", "Study", "VersificationTables.swift")
FORMAT = 1
CODES = ["KJV", "ASV", "WEB", "RV1909", "BLIVRE"]


def vid(book, chapter, verse):
    return book * 1_000_000 + chapter * 1_000 + verse


# Alignment with the KJV (the app's tables) -------------------------------------------

def shift(book, chapter, first, last, kjv_chapter, by):
    return [([vid(book, chapter, v)], [vid(book, kjv_chapter, v + by)]) for v in range(first, last + 1)]


def group(book, verses, kjv):
    return [([vid(book, c, v) for c, v in verses], [vid(book, c, v) for c, v in kjv])]


def rv1909_rules():
    """The Reina-Valera's rules, parsed from VersificationTables.swift."""
    source = open(TABLES, encoding="utf-8").read()
    rules = []
    for line in source.splitlines():
        line = line.strip().rstrip(",")
        m = re.fullmatch(r"shift\(book: (\d+), chapter: (\d+), verses: (\d+)\.\.\.(\d+), kjvChapter: (\d+), by: (-?\d+)\)", line)
        if m:
            rules += shift(*map(int, m.groups()))
            continue
        m = re.fullmatch(r"group\(book: (\d+), \[(.*)\], kjv: \[(.*)\]\)", line)
        if m:
            pairs = lambda text: [tuple(map(int, p)) for p in re.findall(r"\((\d+), (\d+)\)", text)]
            rules += group(int(m.group(1)), pairs(m.group(2)), pairs(m.group(3)))
        elif line.startswith(("shift(", "group(")):
            sys.exit(f"unreadable rule in VersificationTables.swift: {line}")
    if len(rules) < 100:
        sys.exit("VersificationTables.swift: too few Reina-Valera rules found")
    return rules


def web_rules():
    """OriginalVersification.webExceptions: the doxology at 14:24–26, 16:25 empty."""
    return shift(45, 14, 24, 26, 16, 1) + [([vid(45, 16, 25)], [])]


class Alignment:
    """Mirrors VersificationMap.alignment(of:)."""

    def __init__(self, rules):
        self.table = {}
        for verses, kjv in rules:
            for v in verses:
                self.table[v] = kjv
        self.claimed = {k for _, kjv in rules for k in kjv}

    def kjv(self, verse):
        if verse in self.table:
            return self.table[verse]
        return [] if verse in self.claimed else [verse]


ALIGNMENTS = {
    "KJV": Alignment([]),
    "ASV": Alignment([]),
    "WEB": None,  # built in main (needs nothing external)
    "RV1909": None,
    "BLIVRE": Alignment([]),
}


# Reading the Bibles -------------------------------------------------------------------

def rv1909_database(path):
    if path.endswith(".sqlite"):
        return path
    sys.path.insert(0, HERE)
    from build_bibles import create_bible_db, load_usfx  # noqa: E402
    verses, headings = load_usfx(path)
    out = os.path.join(tempfile.mkdtemp(), "RV1909.sqlite")
    create_bible_db(out, "RV1909", verses, headings)
    return out


def read_bible(path):
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    meta = dict(db.execute("select key, value from meta"))
    verses = db.execute("select book, chapter, verse, text, poetry from verses order by id").fetchall()
    return meta, verses


def chapter_files(code, meta, verses, alignment):
    """{(book, kjv chapter): file dict}."""
    files = {}
    for book, chapter, verse, text, poetry in verses:
        kjv = alignment.kjv(vid(book, chapter, verse))
        for k in kjv:
            key = (book, k // 1000 % 1000)
            entry = files.setdefault(key, {
                "format": FORMAT,
                "translation": code,
                "name": meta["name"],
                "language": meta["language"],
                "license": meta["license"],
                "book": book,
                "chapter": key[1],
                "verses": [],
            })
            row = {"c": chapter, "v": verse, "k": [x for x in kjv if x // 1000 % 1000 == key[1]], "t": text}
            if poetry:
                row["p"] = 1
            if not entry["verses"] or entry["verses"][-1]["c"] != chapter or entry["verses"][-1]["v"] != verse:
                entry["verses"].append(row)
    return files


def path_for(out, code, book, chapter):
    return os.path.join(out, "web", f"v{FORMAT}", code, f"{book}-{chapter}.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rv1909", required=True, help="RV1909 .sqlite (the downloadable build) or open-bibles' spa-rv1909.usfx.xml")
    parser.add_argument("--out", default="build/web-bibles")
    parser.add_argument("--check", action="store_true", help="compare the files in --out with the databases")
    args = parser.parse_args()

    ALIGNMENTS["WEB"] = Alignment(web_rules())
    ALIGNMENTS["RV1909"] = Alignment(rv1909_rules())
    sources = {code: os.path.join(BIBLES, f"{code}.sqlite") for code in ("KJV", "ASV", "WEB", "BLIVRE")}
    sources["RV1909"] = rv1909_database(args.rv1909)

    problems = 0
    total = 0
    for code in CODES:
        meta, verses = read_bible(sources[code])
        if meta.get("abbreviation", code) != code:
            sys.exit(f"{sources[code]} is {meta.get('abbreviation')}, not {code}")
        meta.setdefault("name", {"RV1909": "Reina-Valera 1909"}.get(code, code))
        meta.setdefault("language", "es" if code == "RV1909" else "en")
        files = chapter_files(code, meta, verses, ALIGNMENTS[code])
        if args.check:
            seen = set()
            for (book, chapter), expected in files.items():
                path = path_for(args.out, code, book, chapter)
                try:
                    actual = json.load(open(path, encoding="utf-8"))
                except (OSError, ValueError) as error:
                    print(f"{code} {book}-{chapter}: {error}")
                    problems += 1
                    continue
                if actual != expected:
                    print(f"{code} {book}-{chapter}: differs from the database")
                    problems += 1
                for row in actual.get("verses", []):
                    seen.add((book, row["c"], row["v"]))
            # Every verse of the database is in some file, word for word.
            for book, chapter, verse, text, _ in verses:
                if ALIGNMENTS[code].kjv(vid(book, chapter, verse)) and (book, chapter, verse) not in seen:
                    print(f"{code} {book} {chapter}:{verse} is in no file")
                    problems += 1
            folder = os.path.join(args.out, "web", f"v{FORMAT}", code)
            extra = set(os.listdir(folder)) - {f"{b}-{c}.json" for b, c in files} if os.path.isdir(folder) else set()
            for name in sorted(extra):
                print(f"{code} {name}: not from the database")
                problems += 1
        else:
            for (book, chapter), content in files.items():
                path = path_for(args.out, code, book, chapter)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8") as handle:
                    json.dump(content, handle, ensure_ascii=False, separators=(",", ":"))
        total += len(files)
        print(f"{code}: {len(verses)} verses in {len(files)} chapter files")
    if args.check:
        if problems:
            sys.exit(f"{problems} problem(s)")
        print(f"All {total} files match the databases verse for verse.")
    else:
        print(f"Wrote {total} files under {os.path.join(args.out, 'web', f'v{FORMAT}')}")


if __name__ == "__main__":
    main()
