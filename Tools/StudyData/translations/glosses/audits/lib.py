"""Shared loading for the audits: units from the source batches, the
translations and their verse-specific glosses, and every verse's words
(from WordStudy.sqlite, through glosses.py)."""
import glob
import json
import os
import re  # noqa: F401  (the audits use it through `from lib import *`)
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "..")))
D = os.path.abspath(os.path.join(HERE, ".."))


def load():
    import glosses
    U = {}
    for f in sorted(glob.glob(f"{D}/source/0*.json")):
        j = json.load(open(f, encoding="utf-8"))
        for w in j["words"]:
            for g in w["glosses"]:
                U[g["id"]] = dict(strongs=w["strongs"], lemma=w["lemma"], morph=g["morph"], gloss=g["gloss"], batch=j["batch"], count=g["count"])
    T = {"es": {}, "pt": {}}
    O = {"es": {}, "pt": {}}
    F = {"es": {}, "pt": {}}
    for lang in T:
        for f in sorted(glob.glob(f"{D}/{lang}/0*.json")):
            j = json.load(open(f, encoding="utf-8"))
            T[lang].update(j["glosses"])
            for i in j["glosses"]:
                F[lang][i] = f
            for i, d in j.get("occurrences", {}).items():
                for p, t in d.items():
                    O[lang][(i, p)] = t
    _, byv = glosses.occurrences()
    return U, T, O, F, dict(byv)


def text(T, O, lang, i, v, pos):
    return O[lang].get((i, f"{v}.{pos}"), T[lang].get(i))
