"""Matthew Henry's English source fixes (translations/commentary/source_fixes.json).

    python3 -m unittest Tools/StudyData/test_commentary_fixes.py
"""
import json
import os
import sqlite3
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import commentary  # noqa: E402

DB = os.path.join(HERE, "..", "..", "Genesis", "Resources", "Study", "WordStudy.sqlite")


class SourceFixes(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(commentary.OUT, "source_fixes.json"), encoding="utf-8") as handle:
            self.data = json.load(handle)
        self.db = sqlite3.connect(DB)

    def tearDown(self):
        self.db.close()

    def text(self, cid):
        return self.db.execute("SELECT text FROM commentary WHERE id = ?", (cid,)).fetchone()[0]

    def test_every_fix_has_a_reason(self):
        for f in self.data["fixes"]:
            self.assertTrue(f["why"].strip(), f["id"])
            self.assertNotEqual(f["old"], f["new"], f["id"])

    def test_bundled_commentary_has_every_fix(self):
        for f in self.data["fixes"]:
            text = self.text(f["id"])
            self.assertIn(f["new"], text, f["id"])
            if f["new"] not in f["old"]:
                self.assertNotIn(f["old"], text, f["id"])

    def test_fixing_is_idempotent(self):
        fixes = commentary.source_fixes()
        for cid in fixes:
            text = self.text(cid)
            self.assertEqual(commentary.fix_text(cid, text, fixes), text, cid)

    def test_examples(self):
        self.assertIn("All confidence must be placed on God's free grace", self.text(1403))
        self.assertNotIn("pan answer", self.text(1403))
        self.assertEqual(self.text(466).count("He looks back upon what had been done for them."), 1)

    def test_translations_follow_the_fixed_english(self):
        ids = {f["id"] for f in self.data["fixes"]}
        for lang in ("es", "pt"):
            rows = dict(self.db.execute(
                "SELECT id, text FROM commentary_translations WHERE lang = ?", (lang,)).fetchall())
            self.assertTrue(ids <= set(rows), lang)
            self.assertNotIn("[…]", rows[1403], lang)
        es = dict(self.db.execute("SELECT id, text FROM commentary_translations WHERE lang = 'es'").fetchall())
        pt = dict(self.db.execute("SELECT id, text FROM commentary_translations WHERE lang = 'pt'").fetchall())
        self.assertIn("libre gracia de Dios", es[1403])
        self.assertIn("livre graça de Deus", pt[1403])
        self.assertEqual(es[466].count("Mira atrás a lo que se había hecho por ellos."), 1)
        self.assertEqual(pt[466].count("para o que havia sido feito por eles."), 1)


if __name__ == "__main__":
    unittest.main()
