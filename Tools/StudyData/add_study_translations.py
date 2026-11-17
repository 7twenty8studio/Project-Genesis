#!/usr/bin/env python3
"""Puts the Spanish and Portuguese names into Study.sqlite.

    python3 Tools/StudyData/add_study_translations.py

Reads Tools/StudyData/translations/<lang>.json (made by translate_study.py
from manual.json and the Bibles' own spellings) and replaces the
`translations` table:

    translations(lang, kind, key, name, other, detail, folded)

kind is person, place, event, era or route; key is the row's id as text.
name replaces the English name or title; other replaces also_called
(people), aliases (places), the summary (eras) or the passage (routes);
detail is kept for translated descriptions (Easton) and is empty for now.
folded is the name and other names in lower case without accents, for
search. An empty value means "keep the English". Running it again is safe.
build_study.py calls it after building the database.
"""
import json
import os
import sqlite3
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUDY = os.path.join(ROOT, "Genesis", "Resources", "Study", "Study.sqlite")
HERE = os.path.join(ROOT, "Tools", "StudyData", "translations")
LANGUAGES = ("es", "pt")
KINDS = {"person": "people", "place": "places", "event": "events", "era": "eras", "route": "routes"}


def fold(text: str) -> str:
    """Lower case without accents, as Swift's folding(options: [.caseInsensitive, .diacriticInsensitive])."""
    return "".join(c for c in unicodedata.normalize("NFD", text) if not unicodedata.combining(c)).lower()


def searchable(kind: str, name: str, other: str) -> str:
    """", moises, ..." so a LIKE '%, mo%' finds a name or any other name by its start."""
    if kind not in ("person", "place"):
        return ""
    names = [name] + [part.strip() for part in other.split(",")]
    return "".join(", " + fold(n) for n in names if n)


def add(path: str = STUDY) -> int:
    db = sqlite3.connect(path)
    db.execute("DROP TABLE IF EXISTS translations")
    db.executescript(
        """
        CREATE TABLE translations (
            lang TEXT NOT NULL, kind TEXT NOT NULL, key TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '', other TEXT NOT NULL DEFAULT '', detail TEXT NOT NULL DEFAULT '',
            folded TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (lang, kind, key)) WITHOUT ROWID;
        """
    )
    total = 0
    for lang in LANGUAGES:
        with open(os.path.join(HERE, f"{lang}.json"), encoding="utf-8") as f:
            data = json.load(f)
        details = {}
        bios = os.path.join(HERE, "bios", lang)
        if os.path.isdir(bios):
            for name in sorted(os.listdir(bios)):
                if name.endswith(".json"):
                    with open(os.path.join(bios, name), encoding="utf-8") as f:
                        for entry in json.load(f)["entries"]:
                            details[(entry["kind"], str(entry["id"]))] = entry["text"]
        for kind, table in KINDS.items():
            ids = {str(row[0]) for row in db.execute(f"SELECT id FROM {table}")}
            entries = data.get(kind, {})
            unknown = set(entries) - ids
            if unknown:
                sys.exit(f"{lang}.json has {kind} ids that Study.sqlite doesn't: {sorted(unknown)[:10]}")
            keys = set(entries) | {k for (dk, k) in details if dk == kind}
            for key in sorted(keys):
                entry = entries.get(key, {})
                db.execute(
                    "INSERT INTO translations VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (lang, kind, key, entry.get("name", ""), entry.get("other", ""), details.get((kind, key), ""),
                     searchable(kind, entry.get("name", ""), entry.get("other", ""))),
                )
                total += 1
    db.commit()
    db.execute("VACUUM")
    db.close()
    return total


if __name__ == "__main__":
    print(f"translations: {add()} rows in {STUDY}")
