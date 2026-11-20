#!/usr/bin/env python3
"""Builds Genesis/Resources/Study/Glosses.sqlite: the Original view's
word-by-word glosses in Spanish and Portuguese (VRS-6).

    python3 Tools/StudyData/add_gloss_translations.py

Reads the translated batches (Tools/StudyData/translations/glosses/<lang>/,
see glosses.py), keeps only glosses that pass glosses.py's check, and
writes one row per (Strong's, morphology, English gloss):

    glosses(key INTEGER PRIMARY KEY, es TEXT, pt TEXT, awaiting TEXT)
    occurrence_glosses(verse, position, key, es, pt)   -- a verse's own word

`awaiting` names the languages whose gloss is an uncertain meaning still
awaiting qualified review (the app marks it).

`key` is glosses.gloss_key (FNV-1a 64 of "strongs\\x1fmorph\\x1fgloss"), which
the app computes from the word it shows (`OriginalGlosses.key`), so the
file doesn't depend on WordStudy.sqlite's form ids, and it's kept apart
from WordStudy.sqlite to keep that file's size down. A missing language
is NULL; the app shows the English for anything without a row.
"""
import os
import sqlite3
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glosses  # noqa: E402

# STEPBible-Data commit WordStudy.sqlite's words and glosses come from (SOURCES.md).
SOURCE_COMMIT = "95927044f33c540073246306cea5b13f5a16eb02"
OUTPUT = os.path.join(os.path.dirname(glosses.WORDSTUDY), "Glosses.sqlite")


def add(path=OUTPUT):
    rows, seen, verses, awaiting = {}, {}, {}, defaultdict(set)
    width = len(glosses.LANGUAGES)
    for column, lang in enumerate(glosses.LANGUAGES):
        passed, per_verse, waits = glosses.check(lang, quiet=True, full=True)
        for triple, text in passed.items():
            key = glosses.gloss_key(*triple)
            if seen.setdefault(key, triple) != triple:
                sys.exit(f"key collision: {seen[key]} and {triple}")
            rows.setdefault(key, [None] * width)[column] = text
            if triple in waits:
                awaiting[key].add(lang)
        for (verse, position, triple), text in per_verse.items():
            verses.setdefault((verse, position, glosses.gloss_key(*triple)), [None] * width)[column] = text
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID")
    db.executemany("INSERT INTO meta VALUES (?, ?)", [
        ("source", f"English glosses of STEPBible-Data TAHOT and TAGNT at commit {SOURCE_COMMIT}, data created by www.STEPBible.org based on work at Tyndale House Cambridge, https://STEPBible.github.io/STEPBible-Data"),
        ("license", "CC BY 4.0, https://creativecommons.org/licenses/by/4.0/"),
        ("changes", "Translated into Spanish and Brazilian Portuguese by Versely with AI assistance, one per Strong's number, morphology and English gloss, with verse-specific translations where the verse needs another word; not reviewed or endorsed by STEPBible or Tyndale House (Tools/StudyData/translations/glosses/SOURCES.md)"),
        ("key", "FNV-1a 64 of strongs\\x1fmorph\\x1fgloss, signed"),
    ])
    langs = glosses.LANGUAGES
    # awaiting: languages whose translation is an uncertain meaning not yet
    # signed off by a qualified reviewer ("es", "pt", "es pt"); NULL otherwise.
    db.execute(f"CREATE TABLE glosses (key INTEGER PRIMARY KEY, {', '.join(f'{l} TEXT' for l in langs)}, awaiting TEXT)")
    db.executemany(f"INSERT INTO glosses VALUES (?{', ?' * width}, ?)",
                   sorted((k, *v, " ".join(sorted(awaiting[k])) or None) for k, v in rows.items()))
    db.execute(f"""CREATE TABLE occurrence_glosses (verse INTEGER NOT NULL, position INTEGER NOT NULL, key INTEGER NOT NULL,
        {', '.join(f'{l} TEXT' for l in langs)}, PRIMARY KEY (verse, position, key)) WITHOUT ROWID""")
    db.executemany(f"INSERT INTO occurrence_glosses VALUES (?, ?, ?{', ?' * width})",
                   sorted((*k, *v) for k, v in verses.items()))
    db.commit()
    db.execute("VACUUM")
    db.close()
    return len(rows), len(verses)


if __name__ == "__main__":
    units, verses = add()
    print(f"glosses: {units} rows, {verses} verse-specific, in {OUTPUT}")
