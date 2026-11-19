#!/usr/bin/env python3
"""Builds Genesis/Resources/Study/Glosses.sqlite: the Original view's
word-by-word glosses in Spanish and Portuguese (VRS-6).

    python3 Tools/StudyData/add_gloss_translations.py

Reads the translated batches (Tools/StudyData/translations/glosses/<lang>/,
see glosses.py), keeps only glosses that pass glosses.py's check, and
writes one row per (Strong's, morphology, English gloss):

    glosses(key INTEGER PRIMARY KEY, es TEXT, pt TEXT)

`key` is glosses.gloss_key (FNV-1a 64 of "strongs\\x1fmorph\\x1fgloss"), which
the app computes from the word it shows (`OriginalGlosses.key`), so the
file doesn't depend on WordStudy.sqlite's form ids, and it's kept apart
from WordStudy.sqlite to keep that file's size down. A missing language
is NULL; the app shows the English for anything without a row.
"""
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glosses  # noqa: E402

OUTPUT = os.path.join(os.path.dirname(glosses.WORDSTUDY), "Glosses.sqlite")


def add(path=OUTPUT):
    rows, seen = {}, {}
    for column, lang in enumerate(glosses.LANGUAGES):
        for triple, text in glosses.check(lang, quiet=True).items():
            key = glosses.gloss_key(*triple)
            if seen.setdefault(key, triple) != triple:
                sys.exit(f"key collision: {seen[key]} and {triple}")
            rows.setdefault(key, [None] * len(glosses.LANGUAGES))[column] = text
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID")
    db.executemany("INSERT INTO meta VALUES (?, ?)", [
        ("source", "English glosses of STEPBible-Data TAHOT and TAGNT, data created by www.STEPBible.org based on work at Tyndale House Cambridge, https://STEPBible.github.io/STEPBible-Data"),
        ("license", "CC BY 4.0, https://creativecommons.org/licenses/by/4.0/"),
        ("changes", "Translated into Spanish and Brazilian Portuguese by Versely with AI assistance, one per Strong's number, morphology and English gloss; not reviewed or endorsed by STEPBible or Tyndale House (Tools/StudyData/translations/glosses/SOURCES.md)"),
        ("key", "FNV-1a 64 of strongs\\x1fmorph\\x1fgloss, signed"),
    ])
    db.execute(f"CREATE TABLE glosses (key INTEGER PRIMARY KEY, {', '.join(f'{l} TEXT' for l in glosses.LANGUAGES)})")
    db.executemany(f"INSERT INTO glosses VALUES (?{', ?' * len(glosses.LANGUAGES)})",
                   sorted((k, *v) for k, v in rows.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()
    return len(rows)


if __name__ == "__main__":
    print(f"glosses: {add()} rows in {OUTPUT}")
