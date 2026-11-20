"""Tests for the full place names in Study.sqlite (build_study.PLACE_NAMES).

    python3 -m unittest Tools/StudyData/test_study_names.py
"""
import os
import sqlite3
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_study  # noqa: E402


class PlaceNames(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(build_study.OUTPUT)

    def tearDown(self):
        self.db.close()

    def test_bundled_database_has_the_full_names(self):
        for pid, name in build_study.PLACE_NAMES.items():
            (stored,) = self.db.execute("SELECT name FROM places WHERE id = ?", (pid,)).fetchone()
            self.assertEqual(stored, name, pid)

    def test_no_place_named_by_one_word_of_its_name(self):
        cut = {"Place", "Forest", "Highway", "Pillars", "Throne", "Judgment", "Rocks", "There",
               "Willows", "Angle", "Tower", "Pool", "Salt", "Destruction", "Field", "Skull"}
        names = {name for (name,) in self.db.execute("SELECT name FROM places")}
        self.assertEqual(names & cut, set())

    def test_spanish_and_portuguese_names_are_pinned(self):
        for lang in ("es", "pt"):
            for pid in build_study.PLACE_NAMES:
                row = self.db.execute(
                    "SELECT name FROM translations WHERE lang = ? AND kind = 'place' AND key = ?",
                    (lang, str(pid))).fetchone()
                self.assertTrue(row and row[0], f"{lang} place {pid}")
        examples = {("es", 954): "Lugar de la Calavera", ("pt", 954): "Lugar da Caveira",
                    ("es", 690): "Camino Real", ("pt", 1232): "Penhascos das Cabras Montesas"}
        for (lang, pid), name in examples.items():
            (stored,) = self.db.execute(
                "SELECT name FROM translations WHERE lang = ? AND kind = 'place' AND key = ?",
                (lang, str(pid))).fetchone()
            self.assertEqual(stored, name)


if __name__ == "__main__":
    unittest.main()
