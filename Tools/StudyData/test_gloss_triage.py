"""The AI triage of uncertain word meanings (translations/glosses/ai-triage).

    python3 -m unittest Tools/StudyData/test_gloss_triage.py
"""
import glob
import json
import os
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GLOSSES = os.path.join(HERE, "translations", "glosses")


class GlossTriage(unittest.TestCase):
    def setUp(self):
        with open(os.path.join(GLOSSES, "ai-triage", "triage.jsonl"), encoding="utf-8") as handle:
            self.records = [json.loads(line) for line in handle]
        self.batches = {}
        for lang in ("es", "pt"):
            for path in glob.glob(os.path.join(GLOSSES, lang, "*.json")):
                with open(path, encoding="utf-8") as handle:
                    data = json.load(handle)
                self.batches[(lang, data["batch"])] = data

    def test_every_uncertain_meaning_has_a_triage_and_stays_uncertain(self):
        for lang in ("es", "pt"):
            uncertain = {i for (l, _), d in self.batches.items() if l == lang for i in d["uncertain"]}
            self.assertEqual({r["id"] for r in self.records}, uncertain, lang)

    def test_triage_matches_the_batches(self):
        for r in self.records:
            for lang in ("es", "pt"):
                self.assertEqual(self.batches[(lang, r["batch"])]["glosses"][r["id"]], r[lang]["now"], (lang, r["id"]))
                self.assertIn(r[lang]["verdict"], ("ok", "fix", "scholar"))

    def test_examples(self):
        by = {r["id"]: r for r in self.records}
        self.assertEqual(by["4d559f486a2e8ecd"]["es"]["now"], "se castrarán")  # Gal 5:12
        self.assertEqual(by["42d12843672f9cfd"]["es"]["now"], "¿tienes en suspenso?")  # John 10:24
        self.assertEqual(by["af1322b9" + by_suffix(by, "af1322b9")]["es"]["now"], "un buey salvaje")


def by_suffix(by, prefix):
    return next(i for i in by if i.startswith(prefix))[len(prefix):]


if __name__ == "__main__":
    unittest.main()
