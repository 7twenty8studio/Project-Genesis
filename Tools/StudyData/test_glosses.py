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
        self.assertEqual(problems("¿ human", "acaso humano"), [])
        self.assertEqual(problems("¿ is it willing", "porventura quererá", "pt"), [])
        self.assertEqual(problems("who?", "¿quién?"), [])
        self.assertEqual(problems("who?", "quem?", "pt"), [])
        self.assertEqual(problems("[is] it not?", "¿no [es] así?"), [])
        self.assertEqual(problems("Baal", "Baal"), [])
        self.assertEqual(problems("Selah", "Selá", "pt"), [])

    def test_brackets_and_marks(self):
        self.assertIn("brackets differ ([] -> )", problems("[the] father of", "el padre de"))
        self.assertIn("empty brackets", problems("[the] father", "[] padre"))
        self.assertEqual(problems("[ ]", "[ ]"), [])  # STEPBible's empty placeholder
        # A supplied "[one]" may go: Spanish and Portuguese use the adjective as the noun.
        self.assertEqual(problems("a cruel [one]", "un cruel"), [])
        self.assertEqual(problems("the [one] who", "el que"), [])
        self.assertEqual(problems("[the] mighty [one] of", "[el] poderoso de"), [])
        self.assertIn("brackets differ ([][] -> )", problems("[the] mighty [one] of", "el poderoso de"))
        self.assertIn("the question particle ¿ is “acaso” here", problems("¿ human", "¿ humano"))
        self.assertIn("a ¿ or ¡ with no closing mark in this gloss", problems("¿ human", "¿ acaso humano"))
        self.assertIn("Portuguese has no ¿ or ¡", problems("¿ is it willing", "¿ porventura quererá", "pt"))
        self.assertIn("Portuguese has no ¿ or ¡", problems("[is] it not?", "¿não [é]?", "pt"))
        self.assertEqual(problems("will we eat", "¿comeremos?"), [])
        self.assertEqual(problems("will we eat", "comeremos?", "pt"), [])
        self.assertIn("? differs", problems("will we eat", "¿comeremos??"))
        self.assertIn("numbers differ", problems("[19] And", "Y"))

    def test_will_is_the_future_not_wanting(self):
        # Regression: batch 004 had "[will] you" → "[queréis] vosotros", and
        # every structural check passed it.
        self.assertIn("“will/shall” is the future here, not “querer” (a note if the verse means wanting)",
                      problems("[will] you", "[queréis] vosotros"))
        self.assertIn("“will/shall” is the future here, not “querer” (a note if the verse means wanting)",
                      problems("[will] you", "[quereis] vós", "pt"))
        self.assertEqual(problems("he will eat", "comerá"), [])
        self.assertEqual(problems("they were willing", "quisieron"), [])
        self.assertEqual(problems("[will] you", "[queréis] vosotros", note="the verse asks what they want"), [])

    def test_capitals_english_and_length(self):
        self.assertIn("capital first letter where the English has none", problems("he covered", "Cubrió"))
        self.assertEqual(problems("Edomite", "edomita"), [])
        self.assertEqual(problems("Abel towards", "hacia Abel"), [])
        self.assertIn("English left (the)", problems("the fathers", "the padres"))
        self.assertIn("not translated (or give a note)", problems("eduth", "eduth"))
        self.assertEqual(problems("eduth", "eduth", note="a transliteration"), [])
        self.assertEqual(problems("memorial", "memorial", meaning="memorial"), [])
        self.assertTrue(any(p.startswith("too long") for p in problems("go", "ir caminando por todo el camino largo hasta allá")))


def _translations():
    """{lang: ({id: gloss}, {(id, "verse.position"): gloss})} from every batch."""
    import glob
    import json
    out = {}
    for lang in ("es", "pt"):
        units, own = {}, {}
        for path in sorted(glob.glob(os.path.join(glosses.OUT, lang, "0*.json"))):
            with open(path, encoding="utf-8") as f:
                batch = json.load(f)
            units.update(batch["glosses"])
            for i, places in batch.get("occurrences", {}).items():
                for place, text in places.items():
                    own[(i, place)] = text
        out[lang] = (units, own)
    return out


_TRANSLATED = None


def verse(lang, ref):
    """A verse's glosses in reading order: [(position, english, translation, id)]."""
    global _TRANSLATED
    if _TRANSLATED is None:
        _TRANSLATED = _translations()
    units, own = _TRANSLATED[lang]
    _, by_verse = glosses.occurrences()
    return [(p, g, own.get((i, f"{ref}.{p}"), units.get(i)), i) for p, g, i in by_verse[ref]]


def word(lang, ref, english, nth=0):
    found = [t for _, g, t, _ in verse(lang, ref) if g == english]
    return found[nth]


@unittest.skipUnless(os.path.exists(glosses.WORDSTUDY), "needs WordStudy.sqlite")
class ReviewedExamples(unittest.TestCase):
    """The owner's review of 19 November 2026 (PR #33): each example fixed,
    and the kind of mistake checked across every batch."""

    def test_one_object_pronoun_that_agrees(self):
        # Matthew 5:29 (the eye: masculine) and 5:30 (the hand: feminine)
        # had "échala [la]" / "lança [-a]": the pronoun twice, and feminine.
        self.assertEqual(word("es", 40005029, "do cast [it]"), "echa [lo]")
        self.assertEqual(word("pt", 40005029, "do cast [it]"), "lança [-o]")
        self.assertEqual(word("es", 40005030, "do cast [it]"), "echa [la]")
        self.assertEqual(word("pt", 40005030, "do cast [it]"), "lança [-a]")
        self.assertEqual(word("es", 40005029, "it"), "lo")
        self.assertEqual(word("es", 40005030, "it"), "la")

    def test_sorceries_not_sorcerers(self):
        # Revelation 9:21: φαρμακειῶν (G5331) is sorceries; STEPBible's English says "sorcerers".
        self.assertEqual(word("es", 66009021, "sorcerers"), "hechicerías")
        self.assertEqual(word("pt", 66009021, "sorcerers"), "feitiçarias")
        # And the article agrees with the Portuguese noun: a imoralidade.
        words = verse("pt", 66009021)
        at = next(n for n, w in enumerate(words) if w[1] == "sexual immorality")
        self.assertEqual(words[at - 1][2], "a")
        self.assertEqual(verse("es", 66009021)[at - 1][2], "la")

    def test_you_as_an_object(self):
        # John 13:34 and 15:12: ὑμᾶς after "I loved" is the object: os / vos, not vosotros / vós.
        self.assertEqual(word("es", 43013034, "you"), "os")
        self.assertEqual(word("pt", 43013034, "you"), "vos")
        self.assertEqual(word("es", 43015012, "you"), "os")
        self.assertEqual(word("pt", 43015012, "you"), "vos")
        # After a preposition the stressed form stays: "iré delante de vosotros" (Matthew 26:32).
        self.assertEqual(word("es", 40026032, "you"), "vosotros")
        # The subject of an infinitive keeps the subject form: "después que yo resucite".
        self.assertEqual(word("es", 40026032, "Me"), "Yo")

    def test_articles_and_adjectives_agree(self):
        # John 13:34 "un mandamiento nuevo", 15:12 "este es el mandamiento, el mío".
        self.assertEqual(word("es", 43013034, "new"), "nuevo")
        self.assertEqual(word("pt", 43013034, "new"), "novo")
        self.assertEqual(word("es", 43015012, "This"), "Este")
        self.assertEqual(word("es", 43015012, "<the>", 1), "<el>")
        self.assertEqual(word("pt", 43015012, "<the>", 1), "<o>")

    def test_no_pronoun_twice(self):
        # Across every batch: no verb with a pronoun on it followed by the same pronoun supplied.
        import re
        same = {"es": re.compile(r"\w{2}(lo|la|los|las|le|les)\s*\[\1\]"),
                "pt": re.compile(r"-(o|a|os|as|lo|la|los|las|no|na|nos|nas)\s*\[-?\1\]")}
        for lang, pattern in same.items():
            units, own = _translations()[lang]
            for text in list(units.values()) + list(own.values()):
                self.assertIsNone(pattern.search(text), text)

    def test_greek_object_pronouns_are_clitics(self):
        # Across every batch: a Greek accusative personal pronoun glossed
        # "him", "them", "you"… is an object (lo, los, os…; o, os, vos…)
        # wherever no preposition and no infinitive it's the subject of make
        # it otherwise; those verses have their own (occurrences).
        import glob
        import json
        import re
        stressed = {"es": {"él", "ella", "ellos", "ellas", "vosotros", "nosotros", "ti", "mí"},
                    "pt": {"ele", "ela", "eles", "elas", "vós", "nós", "ti", "mim"}}
        bare = re.compile(r"^(him|them|you|me|it|her|us)$", re.I)
        accusative = re.compile(r"^P-(1AS|2AS|1AP|2AP|AS[MFN]|AP[MFN])$")
        pronouns = set()
        for path in sorted(glob.glob(os.path.join(glosses.OUT, "source", "0*.json"))):
            with open(path, encoding="utf-8") as f:
                for w in json.load(f)["words"]:
                    for g in w["glosses"]:
                        if accusative.match(g["morph"]) and bare.match(g["gloss"]):
                            pronouns.add(g["id"])
        self.assertGreater(len(pronouns), 10)
        for lang in ("es", "pt"):
            units, _ = _translations()[lang]
            for i in pronouns:
                self.assertNotIn(units[i].lower(), stressed[lang], i)

    def test_full_review_examples(self):
        # The full review of every changed word (19 November 2026), one example of each kind.
        self.assertEqual(word("es", 66004004, "golden"), "de oro")         # a fixed phrase, never "de ora"
        self.assertEqual(word("es", 66006005, "third"), "tercero")         # after its noun, never "tercer"
        self.assertEqual(word("es", 40026068, "You?"), "¿Te?")             # the clitic, and the opening ¿ kept
        self.assertEqual(word("es", 41015013, "Him!"), "Lo!")              # a plain object: the clitic, as in Portuguese
        self.assertEqual(word("es", 47010013, "you"), "vosotros")          # ἄχρι καὶ ὑμῶν: a preposition further back
        self.assertEqual(word("pt", 47010013, "you"), "vós")

    def test_el_agua(self):
        # Across every verse: a feminine noun with a stressed a takes "el" in the singular.
        import re
        noun = re.compile(r"[\[<]?(agua|alma|águila|área|arca|hacha|habla)\b")
        article = re.compile(r"[\[<]?(la|una|de la|a la)[\]>]?")
        _, by_verse = glosses.occurrences()
        for v in by_verse:
            words, seen = [], set()
            for p, _, t, _ in verse("es", v):
                if p not in seen:
                    seen.add(p)
                    words.append(t or "")
            for a, b in zip(words, words[1:]):
                if article.fullmatch(a):
                    self.assertIsNone(noun.match(b), (v, a, b))

if __name__ == "__main__":
    unittest.main()
