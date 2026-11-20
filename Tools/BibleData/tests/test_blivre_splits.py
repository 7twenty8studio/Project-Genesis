"""The Bíblia Livre's split contractions (blivre/split_contractions.json).

Versely keeps the publisher's text verbatim (owner, 20 November 2026). This
test fails when a rebuilt BLIVRE.sqlite no longer matches the list: then a
corrected source has arrived (or a new split), and the list, the Bible's
checksum in its catalog row and the commentary quotations named in
blivre/README.md need updating.

    python3 -m unittest discover Tools/BibleData/tests
"""
import json
import os
import re
import sqlite3
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
BLIVRE = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "BLIVRE.sqlite")
LIST = os.path.join(os.path.dirname(HERE), "blivre", "split_contractions.json")
SPLIT = re.compile(r"(?<![\wÀ-ú'’-])[dnDN] [a-zà-ú]+")


class BibliaLivreSplits(unittest.TestCase):
    def test_bundled_text_matches_the_documented_list(self):
        with open(LIST, encoding="utf-8") as handle:
            documented = [(s["verse"], s["as_published"]) for s in json.load(handle)["splits"]]
        db = sqlite3.connect(BLIVRE)
        columns = [row[1] for row in db.execute("PRAGMA table_info(verses)")]
        text = next(c for c in columns if "text" in c)
        found = [(verse, m.group(0))
                 for verse, value in db.execute(f"SELECT {columns[0]}, {text} FROM verses ORDER BY {columns[0]}")
                 for m in SPLIT.finditer(value)]
        db.close()
        self.assertEqual(found, documented)


if __name__ == "__main__":
    unittest.main()
