#!/usr/bin/env python3
"""Puts the Spanish and Portuguese topic names and headings into Topics.sqlite.

    python3 Tools/TopicData/add_topic_translations.py

Reads the translated batches (Tools/TopicData/translations/<lang>/, see
naves.py), keeps only items that pass naves.py's check, and replaces the
`translations` table:

    translations(lang, kind, key, text, folded)

kind is topic (a topic's name) or entry (a heading); key is its id. folded
is the name in lower case without accents or apostrophes, for search (the
topics' own search_key, accents aside). Rows only for
translated items: the app shows the English for anything without one.
Running it again is safe; run it after build_topics.py.
"""
import os
import sqlite3
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import naves  # noqa: E402


def fold(text: str) -> str:
    text = "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c)).lower()
    text = text.replace("’", "").replace("'", "")
    return " ".join(re.split(r"[^\w]+", text)).strip()


def add(path=naves.TOPICS):
    rows = []
    for lang in naves.LANGUAGES:
        for (kind, key), text in naves.check(lang).items():
            rows.append((lang, kind, key, text, fold(text) if kind == "topic" else ""))
    db = sqlite3.connect(path)
    db.execute("DROP TABLE IF EXISTS translations")
    db.execute("CREATE TABLE translations (lang TEXT NOT NULL, kind TEXT NOT NULL, key INTEGER NOT NULL, text TEXT NOT NULL, folded TEXT NOT NULL, PRIMARY KEY (lang, kind, key)) WITHOUT ROWID")
    db.execute("CREATE INDEX translations_search ON translations(lang, kind, folded)")
    db.executemany("INSERT INTO translations VALUES (?, ?, ?, ?, ?)", sorted(rows))
    db.commit()
    db.execute("VACUUM")
    db.close()
    return len(rows)


if __name__ == "__main__":
    print(f"translations: {add()} rows in {naves.TOPICS}")
