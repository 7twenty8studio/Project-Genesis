#!/usr/bin/env python3
"""Puts the Spanish and Portuguese lexicon glosses, definitions and origins
into WordStudy.sqlite.

    python3 Tools/StudyData/add_lexicon_translations.py

Reads the translated batches (Tools/StudyData/translations/lexicon/<lang>/,
see lexicon.py), keeps only entries that pass lexicon.py's check, and
replaces the `lexicon_translations` table:

    lexicon_translations(lang, strongs, gloss, definition, derivation)

One row per translated entry; a field the English lacks is NULL, and the
app shows the English for any entry without a row. "In the KJV" (usage)
isn't translated. Running it again is safe; run it after build_wordstudy.py.
"""
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lexicon  # noqa: E402


def add(path=lexicon.WORDSTUDY):
    # The English slips and misplaced articles first (lexicon.py SOURCE_FIXES,
    # ARTICLE_FIXES), so English readers see the corrected entries too.
    lexicon.fix_database(path)
    rows = []
    for lang in lexicon.LANGUAGES:
        for strongs, fields in lexicon.check(lang, quiet=True).items():
            rows.append((lang, strongs, fields.get("gloss"), fields.get("definition"), fields.get("derivation")))
    db = sqlite3.connect(path)
    db.execute("DROP TABLE IF EXISTS lexicon_translations")
    db.execute("""CREATE TABLE lexicon_translations (
        lang TEXT NOT NULL, strongs TEXT NOT NULL,
        gloss TEXT, definition TEXT, derivation TEXT,
        PRIMARY KEY (lang, strongs)) WITHOUT ROWID""")
    db.executemany("INSERT INTO lexicon_translations VALUES (?, ?, ?, ?, ?)", sorted(rows))
    db.commit()
    db.execute("VACUUM")
    db.close()
    return len(rows)


if __name__ == "__main__":
    print(f"lexicon_translations: {add()} rows in {lexicon.WORDSTUDY}")
