#!/usr/bin/env python3
"""Checks the verse widget's categories (Genesis/Core/Widgets/VerseCategories.swift).

  python3 Tools/WidgetData/check_verse_categories.py [--print]

For every passage: it exists, whole, in the bundled KJV, WEB and ASV; it is
at most three verses of one chapter; its KJV text starts with a capital and
ends a sentence (. ! ?) with no psalm title or acrostic letter in it. Each
category has 15-30 passages and none twice. --print lists each passage's
KJV text, to read for relevance. Exits 1 on any problem. VerseWidgetTests
runs the same checks in the app's tests.
"""
import os
import re
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, "Genesis/Core/Widgets/VerseCategories.swift")
BIBLES = os.path.join(ROOT, "Genesis/Resources/Bibles")


def categories():
    text = open(SOURCE, encoding="utf-8").read()
    found = {}
    for m in re.finditer(r"static let (\w+) = list\(\[(.*?)\]\)", text, re.S):
        found[m.group(1)] = [tuple(map(int, t)) for t in re.findall(r"\((\d+), (\d+), (\d+), (\d+)\)", m.group(2))]
    return found


def verses(db, book, chapter, first, last):
    base = book * 1_000_000 + chapter * 1_000
    return db.execute("SELECT id, text FROM verses WHERE id BETWEEN ? AND ? ORDER BY id", (base + first, base + last)).fetchall()


def main():
    show = "--print" in sys.argv
    dbs = {t: sqlite3.connect(os.path.join(BIBLES, f"{t}.sqlite")) for t in ("KJV", "WEB", "ASV")}
    problems = []
    found = categories()
    if len(found) != 8:
        problems.append(f"expected 8 categories, found {sorted(found)}")
    for name, passages in found.items():
        if not 15 <= len(passages) <= 30:
            problems.append(f"{name}: {len(passages)} passages")
        if len(set(passages)) != len(passages):
            problems.append(f"{name}: a passage appears twice")
        for book, chapter, first, last in passages:
            label = f"{name} {book}:{chapter}:{first}-{last}"
            if not 1 <= last - first + 1 <= 3:
                problems.append(f"{label}: not 1-3 verses")
            for t, db in dbs.items():
                rows = verses(db, book, chapter, first, last)
                if len(rows) != last - first + 1 or any(not r[1] for r in rows):
                    problems.append(f"{label}: missing in {t}")
            kjv = " ".join(r[1] for r in verses(dbs["KJV"], book, chapter, first, last)).replace("\n", " ")
            if not kjv or not kjv[0].isupper() or kjv[-1] not in ".!?":
                problems.append(f"{label}: not a whole sentence in the KJV: {kjv!r}")
            if "chief Musician" in kjv or kjv.startswith("A Psalm") or re.match(r"^\S+ [A-Z]+\. ", kjv) and not kjv[0].isascii():
                problems.append(f"{label}: has a psalm title or acrostic letter")
            if show:
                print(f"{label:28} {kjv}")
    total = len({p for ps in found.values() for p in ps})
    print(f"{len(found)} categories, {total} passages: " + ", ".join(f"{n} {len(p)}" for n, p in found.items()))
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
