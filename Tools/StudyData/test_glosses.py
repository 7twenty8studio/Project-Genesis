"""Tests for the checks on translated Original glosses (glosses.py).

    python3 -m unittest Tools/StudyData/test_glosses.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glosses  # noqa: E402


def problems(source, text, lang="es", meaning="", note=None):
    return glosses.check_gloss(source, text, lang, meaning, note)


class Key(unittest.TestCase):
    def test_matches_the_app(self):
        # OriginalGlossesTests (WordStudyTests.swift) expects the same numbers.
        self.assertEqual(glosses.gloss_key("H0430G", "HNcmpa", "God"), 4483138548866997674)
        self.assertEqual(glosses.gloss_key("", "", ""), 610775443798759267)

    def test_id_is_stable(self):
        self.assertEqual(glosses.key_id("H0001G", "HNcmsc/Sp3ms", "father his"), "011a94384553160b")


class Check(unittest.TestCase):
    def test_good_translations_pass(self):
        self.assertEqual(problems("father his", "su padre"), [])
        self.assertEqual(problems("[the] father of", "[el] padre de"), [])
        self.assertEqual(problems("to <the> yourself", "a <el> ti mismo"), [])
        self.assertEqual(problems("He put", "Puso"), [])
        self.assertEqual(problems("¿ human", "¿ humano"), [])
        self.assertEqual(problems("[is] it not?", "¿no [es] así?"), [])
        self.assertEqual(problems("Baal", "Baal"), [])
        self.assertEqual(problems("Selah", "Selá", "pt"), [])

    def test_brackets_and_marks(self):
        self.assertIn("brackets differ ([] -> )", problems("[the] father of", "el padre de"))
        self.assertIn("empty brackets", problems("[the] father", "[] padre"))
        self.assertIn("¿ differs", problems("¿ human", "humano"))
        # Portuguese doesn't open questions.
        self.assertIn("¿ differs", problems("[is] it not?", "¿não [é]?", "pt"))
        self.assertIn("numbers differ", problems("[19] And", "Y"))

    def test_capitals_english_and_length(self):
        self.assertIn("capital first letter differs from the English", problems("he covered", "Cubrió"))
        self.assertIn("English left (the)", problems("the fathers", "the padres"))
        self.assertIn("not translated (or give a note)", problems("eduth", "eduth"))
        self.assertEqual(problems("eduth", "eduth", note="a transliteration"), [])
        self.assertEqual(problems("memorial", "memorial", meaning="memorial"), [])
        self.assertTrue(any(p.startswith("too long") for p in problems("go", "ir caminando por todo el camino largo hasta allá")))


if __name__ == "__main__":
    unittest.main()
