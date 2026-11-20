#!/usr/bin/env python3
"""Puts the Spanish and Portuguese Matthew Henry commentary into WordStudy.sqlite.

    python3 Tools/StudyData/add_commentary_translations.py

Reads the translated batches (Tools/StudyData/translations/commentary/<lang>/,
see commentary.py), keeps only entries that pass commentary.py's check, and
replaces four tables:

    commentary_translations(lang, id, title, text)       -- commentary.id
    introduction_translations(lang, source, book, text)
    commentary_quotations(lang, id, n, text)  -- RV1909 / Bíblia Livre words quoted
    editorial_notes(source, section, paragraph, lang, text)  -- Versely's notes

commentary_quotations are the Bible's words each translated section quotes
verbatim (checked against the RV1909 or the Bíblia Livre): the app sets
them in italics and credits the Bible they come from.

Editorial notes (translations/commentary/editorial.json, in English,
Spanish and Portuguese) are Versely's words, not Henry's: the app shows
each before paragraph `paragraph` (from 0) of its section, set apart from
the commentary. The owner paused them on 19 November 2026: the proposals
wait in editorial-proposed.json, so the table is built empty (NOTES.md).

The app shows the English for any section or introduction without a row.
Running it again is safe; run it after build_wordstudy.py (which runs it).
"""
import json
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import commentary  # noqa: E402


def add(path=commentary.WORDSTUDY):
    commentary.fix_database(path)  # Henry's English as the translations have it (source_fixes.json)
    sections, intros, quotes = [], [], []
    for lang in commentary.LANGUAGES:
        for (kind, eid), (title, text, quotations) in commentary.check(lang, quiet=True).items():
            if kind == "section":
                sections.append((lang, eid, title, text))
                quotes += [(lang, eid, n, q) for n, q in enumerate(quotations)]
            else:
                intros.append((lang, "mhcc", eid, text))
    db = sqlite3.connect(path)
    db.execute("DROP TABLE IF EXISTS commentary_translations")
    db.execute("""CREATE TABLE commentary_translations (
        lang TEXT NOT NULL, id INTEGER NOT NULL, title TEXT, text TEXT NOT NULL,
        PRIMARY KEY (lang, id)) WITHOUT ROWID""")
    db.execute("DROP TABLE IF EXISTS introduction_translations")
    db.execute("""CREATE TABLE introduction_translations (
        lang TEXT NOT NULL, source TEXT NOT NULL, book INTEGER NOT NULL, text TEXT NOT NULL,
        PRIMARY KEY (lang, source, book)) WITHOUT ROWID""")
    db.execute("DROP TABLE IF EXISTS commentary_quotations")
    db.execute("""CREATE TABLE commentary_quotations (
        lang TEXT NOT NULL, id INTEGER NOT NULL, n INTEGER NOT NULL, text TEXT NOT NULL,
        PRIMARY KEY (lang, id, n)) WITHOUT ROWID""")
    db.executemany("INSERT INTO commentary_quotations VALUES (?, ?, ?, ?)", quotes)
    db.execute("DROP TABLE IF EXISTS editorial_notes")
    db.execute("""CREATE TABLE editorial_notes (
        source TEXT NOT NULL, section INTEGER NOT NULL, paragraph INTEGER NOT NULL,
        lang TEXT NOT NULL, text TEXT NOT NULL,
        PRIMARY KEY (source, section, paragraph, lang)) WITHOUT ROWID""")
    notes = []
    shipped = os.path.join(commentary.OUT, "editorial.json")
    if os.path.exists(shipped):
        with open(shipped, encoding="utf-8") as f:
            notes = json.load(f)["notes"]
    for note in notes:
        for lang, text in note["text"].items():
            db.execute("INSERT INTO editorial_notes VALUES (?, ?, ?, ?, ?)",
                       (note["source"], note["section"], note["paragraph"], lang, text))
    db.executemany("INSERT INTO commentary_translations VALUES (?, ?, ?, ?)", sorted(sections))
    db.executemany("INSERT INTO introduction_translations VALUES (?, ?, ?, ?)", sorted(intros))
    db.commit()
    db.execute("VACUUM")
    db.close()
    return len(sections), len(intros)


if __name__ == "__main__":
    s, i = add()
    print(f"commentary_translations: {s} rows, introduction_translations: {i} rows in {commentary.WORDSTUDY}")
