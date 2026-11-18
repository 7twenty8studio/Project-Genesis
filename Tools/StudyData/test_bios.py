"""Tests for the checks on translated Easton descriptions (bios.py, refs.py).

    python3 -m unittest Tools/StudyData/test_bios.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bios  # noqa: E402
import refs  # noqa: E402


class References(unittest.TestCase):
    def test_books_chapters_and_carried_books(self):
        self.assertEqual(refs.references("(Gen. 4:8, 9; 5:3; comp. 1 John 3:12)", "en"),
                         [("Gen", 4, 8), ("Gen", 5, 3), ("1John", 3, 12)])
        self.assertEqual(refs.references("(Gn 4:8, 9; 5:3; comp. 1 Jn 3:12)", "es"),
                         [("Gen", 4, 8), ("Gen", 5, 3), ("1John", 3, 12)])
        self.assertEqual(refs.references("(Gn 4:8, 9; 5:3; cf. 1 Jo 3:12)", "pt"),
                         [("Gen", 4, 8), ("Gen", 5, 3), ("1John", 3, 12)])

    def test_eastons_spellings(self):
        self.assertEqual(refs.references("jer. 40:1; Matt, 1:4; Ps. 135: 10; the prophet Isaiah, 19:13", "en"),
                         [("Jer", 40, 1), ("Matt", 1, 4), ("Ps", 135, 10), ("Isa", 19, 13)])

    def test_same_letters_other_language(self):
        # "Jn" is John in Spanish and Jonah in Portuguese.
        self.assertEqual(refs.references("Jn 1:1", "es"), [("John", 1, 1)])
        self.assertEqual(refs.references("Jn 1:1", "pt"), [("Jonah", 1, 1)])

    def test_another_book_with_the_same_numbers_fails(self):
        self.assertEqual(bios.check_references("(John 3:16)", "(Jn 3:16)", "es"), [])
        problems = bios.check_references("(John 3:16)", "(Romanos 3:16)", "es")
        self.assertTrue(problems and "references differ" in problems[0], problems)
        self.assertTrue(bios.check_references("(John 3:16)", "(Ro 3:16)", "es"))
        self.assertTrue(bios.check_references("(John 3:16)", "(Jua 3:16)", "es"))

    def test_order_counts(self):
        self.assertEqual(bios.check_references("(Gen. 1:1; Ex. 2:2)", "(Éx 2:2; Gn 1:1)", "es"), ["references in another order"])

    def test_reference_fix_needs_a_reason_and_the_exact_text(self):
        fix = {"was": "John. 15:44", "now": "Josh. 15:44", "reason": "Easton's slip"}
        self.assertEqual(bios.check_references("(John. 15:44)", "(Jos 15:44)", "es", [fix]), [])
        self.assertTrue(bios.check_references("(John. 15:44)", "(Jos 15:44)", "es", [dict(fix, reason="")]))
        self.assertTrue(bios.check_references("(John 15:44)", "(Jos 15:44)", "es", [fix]))


class QuoteFixes(unittest.TestCase):
    QUOTE = [{"n": 0, "english": "What dost thou here, Elijah?", "kind": "loose", "verses": [11018008, 11018009],
              "es": "Y él respondió: Yo soy; ve, di á tu amo: He aquí Elías."}]
    BIBLE = "Y allí se metió en una cueva, donde tuvo la noche. Y fué á él palabra de Jehová, el cual le dijo: ¿Qué haces aquí, Elías?"

    def check(self, text, fix):
        return bios.check_quotes("es", self.QUOTE, text, [fix])

    def test_verbatim_fix_is_checked_against_the_corrected_verse(self):
        fix = {"n": 0, "reference": "1Kings 19:9", "mode": "verbatim", "reason": "1 Kings 19:9", "bible": self.BIBLE}
        problems, review = self.check("dijo: “¿Qué haces aquí, Elías?”", fix)
        self.assertEqual(problems, [])
        self.assertIn("corrected to 1Kings 19:9", review[0])
        problems, _ = self.check("dijo: “¿Qué haces tú aquí, Elías?”", fix)
        self.assertEqual(problems, ["quotation 1 isn't the words of 1Kings 19:9 verbatim"])

    def test_verbatim_fix_needs_its_bible_text_and_a_real_reference(self):
        fix = {"n": 0, "reference": "1Kings 19:9", "mode": "verbatim", "reason": "1 Kings 19:9"}
        self.assertTrue(self.check("“¿Qué haces aquí, Elías?”", fix)[0])
        fix = {"n": 0, "reference": "Kings 19:9", "mode": "verbatim", "reason": "x", "bible": self.BIBLE}
        self.assertTrue(self.check("“¿Qué haces aquí, Elías?”", fix)[0])

    def test_translated_fix_needs_a_reason(self):
        fix = {"n": 0, "mode": "translated", "reason": ""}
        self.assertEqual(self.check("“¿Qué haces aquí, Elías?”", fix)[0], ["quote fix 0 needs a reason"])
        fix = {"n": 0, "mode": "translated", "reason": "not Scripture: an inscription"}
        problems, review = self.check("“¿Qué haces aquí, Elías?”", fix)
        self.assertEqual(problems, [])
        self.assertIn("translated, not quoted", review[0])

    def test_saved_bible_text_must_be_the_bibles(self):
        bibles = bios.FixBibles()
        good = {"n": 0, "reference": "1Kings 19:9", "mode": "verbatim", "reason": "x",
                "bible": bibles.text("pt", "1Kings 19:9")}
        self.assertEqual(bios.bible_text_problems("pt", [good], bibles), [])
        self.assertTrue(bios.bible_text_problems("pt", [dict(good, bible="Que fazes aqui?")], bibles))

    def test_low_coverage_is_flagged_for_review(self):
        hannah = ("Oh my lord, I am the woman that stood by thee here, praying unto the Lord. For this child I prayed; "
                  "and the Lord hath given me my petition which I asked of him: therefore I also have granted him to "
                  "the Lord; as long as he liveth he is granted to the Lord")
        self.assertLess(bios.kjv_coverage(hannah, [9001026, 9001027]), 0.85)
        self.assertGreater(bios.kjv_coverage(hannah, [9001026, 9001027, 9001028]), 0.85)


if __name__ == "__main__":
    unittest.main()
