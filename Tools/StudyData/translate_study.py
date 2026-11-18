#!/usr/bin/env python3
"""Spanish and Portuguese names and titles for Study.sqlite (VRS-8).

Writes Tools/StudyData/translations/es.json and pt.json, which
add_study_translations.py puts into Study.sqlite's `translations` table.

People and places are named as the Bibles name them, so Explore matches what
people read: each name is found in the verses that mention the person or
place (person_verses / place_verses), in the Reina-Valera 1909 for Spanish
and the Bíblia Livre for Portuguese. The word that appears in most of those
verses and sounds most like the English name wins; a word that better fits
another person or place named in the same verses is left for them. When
nothing fits well enough the English name stays. Reina-Valera 1909 spellings
are brought up to date (ph → f, th → t, ch → c/qu, circumflexes → today's
accents: "Ezechîas" → "Ezequías", "Rachêl" → "Raquel").

Titles (events, eras, journeys), descriptions in parentheses and names of
more than one word come from translations/manual.json, written by hand; a
`{Name}` in them is filled from the names found above.

Only names and titles: no Scripture text is stored.

Usage:
    python3 Tools/StudyData/translate_study.py /path/to/RV1909.sqlite
(RV1909.sqlite is the catalog's RV1909 file, decompressed; the Bíblia Livre
is the bundled Genesis/Resources/Bibles/BLIVRE.sqlite.)
"""
import json
import math
import os
import re
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from difflib import SequenceMatcher

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STUDY = os.path.join(ROOT, "Genesis", "Resources", "Study", "Study.sqlite")
BLIVRE = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "BLIVRE.sqlite")
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "translations")

WORD = re.compile(r"[A-ZÁÉÍÓÚÂÊÎÔÛÃÕÇÜÑ][A-Za-zÀ-ÿ'’-]*")


def fold(text: str) -> str:
    text = unicodedata.normalize("NFD", text.lower())
    return "".join(ch for ch in text if unicodedata.category(ch) != "Mn")


def similarity(a: str, b: str) -> float:
    return SequenceMatcher(None, fold(a), fold(b)).ratio()


# MARK: Spanish spelling

STRONG = set("aeoáéó")
VOWELS = set("aeiouáéíóú")
ACUTE = {"a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú"}
CIRCUMFLEX = {"â": "a", "ê": "e", "î": "i", "ô": "o", "û": "u"}


def modern_spanish(word: str) -> str:
    """Reina-Valera 1909 spelling as it's written today."""
    if "-" in word:
        return "-".join(modern_spanish(part) for part in word.split("-"))
    w = word
    w = re.sub(r"Ph|ph", lambda m: "F" if m.group(0)[0] == "P" else "f", w)
    w = re.sub(r"Th|th", lambda m: "T" if m.group(0)[0] == "T" else "t", w)

    def ch(m):
        upper = m.group(1)[0] == "C"
        nxt = m.group(2)
        if fold(nxt) in ("e", "i"):
            return ("Qu" if upper else "qu") + nxt
        return ("C" if upper else "c") + nxt
    w = re.sub(r"(Ch|ch)(.)", ch, w)
    # Double letters are single today (Mattathías -> Matatías); ll, rr and cc stay.
    w = re.sub(r"([bdfgkmnpstvz])\1", r"\1", w)
    stress = next((i for i, c in enumerate(w) if c in CIRCUMFLEX), None)
    if stress is None:
        return w
    plain = "".join(CIRCUMFLEX.get(c, c) for c in w)
    return with_accent(plain, stress)


def nuclei(word: str, stress: int):
    """Vowel groups (start, end) of a Spanish word; the stressed weak vowel
    and two strong vowels side by side are in hiatus."""
    groups = []
    lower = word.lower()
    i = 0
    while i < len(lower):
        c = lower[i]
        silent_u = c == "u" and i > 0 and lower[i - 1] in "qg" and i + 1 < len(lower) and fold(lower[i + 1]) in ("e", "i")
        if c in VOWELS and not silent_u:
            if groups and groups[-1][1] == i - 1:
                prev = lower[i - 1]
                hiatus = (prev in STRONG and c in STRONG) or i == stress or i - 1 == stress and prev in "iu"
                if not hiatus:
                    groups[-1][1] = i
                    i += 1
                    continue
            groups.append([i, i])
        i += 1
    return groups


def with_accent(word: str, stress: int) -> str:
    groups = nuclei(word, stress)
    index = next((n for n, g in enumerate(groups) if g[0] <= stress <= g[1]), None)
    if index is None or any(c in "áéíóú" for c in word.lower()):
        return word
    from_end = len(groups) - 1 - index
    last = fold(word[-1])
    lower = word.lower()
    before = stress > 0 and lower[stress - 1] in VOWELS and not (stress > 1 and lower[stress - 1] == "u" and lower[stress - 2] in "qg")
    after = stress + 1 < len(word) and lower[stress + 1] in VOWELS
    if lower[stress] in "iu" and (before or after):
        needs = True  # hiatus: Ezequías, Saúl
    elif from_end == 0:
        needs = last in "aeiouns"
    elif from_end == 1:
        needs = last not in "aeiouns"
    else:
        needs = True
    if not needs:
        return word
    c = word[stress]
    accented = ACUTE[c.lower()]
    return word[:stress] + (accented.upper() if c.isupper() else accented) + word[stress + 1:]


# MARK: Finding names in a Bible

class Bible:
    def __init__(self, path: str):
        db = sqlite3.connect(path)
        self.words = {}
        self.frequency = Counter()
        for vid, text in db.execute("SELECT id, text FROM verses"):
            words = {m.group(0).strip("'’-") for m in WORD.finditer(text)}
            words = {w for w in words if len(w) > 1}
            self.words[vid] = words
            self.frequency.update(words)
        self.count = len(self.words)

    def candidates(self, verses):
        verses = [v for v in verses if v in self.words][:400]
        counts = Counter()
        for v in verses:
            counts.update(self.words[v])
        return counts, len(verses)


def find_name(name, verses, bible, others):
    """The Bible's word for `name` in its verses, or None. `others` are the
    English names of everyone else named in those verses."""
    counts, n = bible.candidates(verses)
    if not n:
        return None
    best, best_score = None, -1.0
    for word, c in counts.items():
        sim = similarity(name, word)
        share = c / n
        # A word that sounds more like someone else in these verses is
        # theirs; in nearly every verse about this one, only when it's
        # plainly the other's name ("Zorobabel" is Zerubbabel's, not
        # Shealtiel's, though they're named together).
        if share < 0.6:
            taken = any(similarity(o, word) > sim + 0.05 for o in others if o != name)
        else:
            taken = any(similarity(o, word) >= 0.8 and similarity(o, word) > sim + 0.15 for o in others if o != name)
        if taken:
            continue
        rarity = math.log(bible.count / bible.frequency[word]) / math.log(bible.count)
        score = share * 1.5 + rarity * 0.4 + sim
        # Ties go to the closer spelling, then the word itself, so every
        # run gives the same answer whatever the order of `counts`.
        if (score, sim, word) > (best_score, best[2] if best else -1.0, best[0] if best else ""):
            best, best_score = (word, share, sim), score
    if not best:
        return None
    word, share, sim = best
    if sim >= 0.55 or (share >= 0.75 and n >= 4):
        return word
    return None


BASE = re.compile(r"^(.*?)\s*\((.*)\)\s*$")


def split_name(name: str):
    m = BASE.match(name)
    return (m.group(1), m.group(2)) if m else (name, None)


def main(rv1909: str):
    study = sqlite3.connect(STUDY)
    manual = json.load(open(os.path.join(HERE, "manual.json"), encoding="utf-8"))
    bibles = {"es": Bible(rv1909), "pt": Bible(BLIVRE)}

    entities = {}  # (kind, id) -> (name, verse_count, verses)
    verse_names = defaultdict(set)
    for kind, table, link in (("person", "people", "person_verses"), ("place", "places", "place_verses")):
        verses = defaultdict(list)
        for pid, v in study.execute(f"SELECT {kind}_id, verse FROM {link} ORDER BY verse"):
            verses[pid].append(v)
        for pid, name, count in study.execute(f"SELECT id, name, verse_count FROM {table}"):
            entities[(kind, pid)] = (name, count, verses[pid])
            base, _ = split_name(name)
            for v in verses[pid]:
                verse_names[v].add(base)

    for lang, bible in bibles.items():
        names = manual[lang]["names"]           # whole English names written by hand
        words = dict(manual[lang].get("words", {}))  # English single words written by hand
        found = {}
        # Single-word names, the best known first, so the map below prefers them.
        order = sorted(entities.items(), key=lambda e: -e[1][1])
        for key, (name, count, verses) in order:
            base, _ = split_name(name)
            if " " in base or base in words:
                continue
            others = set().union(*(verse_names[v] for v in verses[:400])) if verses else set()
            word = find_name(base, verses, bible, others)
            if word:
                found[key] = modern_spanish(word) if lang == "es" else word
        best = {}
        for key, (name, count, _) in order:
            base, _ = split_name(name)
            if key in found and base not in best:
                best[base] = found[key]
        best.update(words)

        def say(english: str) -> str:
            """An English name (or phrase) in this language: written by hand,
            found in the Bible, or kept."""
            if english in names:
                return names[english]
            if english in best:
                return best[english]
            return fill(manual[lang]["phrases"], english) or english

        def fill(patterns, text):
            for pattern, template in patterns.items():
                if "{X}" not in pattern:
                    continue
                regex = "^" + re.escape(pattern).replace(re.escape("{X}"), "(.+)") + "$"
                m = re.match(regex, text)
                if m:
                    return template.replace("{X}", say(m.group(1)))
            return None

        out = {"person": {}, "place": {}, "event": {}, "era": {}, "route": {}}
        for (kind, pid), (name, _, _) in entities.items():
            base, note = split_name(name)
            pinned = manual[lang].get("ids", {}).get(f"{kind}:{pid}")
            if pinned:
                text = pinned  # one person or place, where others share the English name
            elif name in names:
                text = names[name]
            else:
                text = found.get((kind, pid)) or say(base)
                if note:
                    text += " (" + (manual[lang]["notes"].get(note) or fill(manual[lang]["notes"], note) or say(note)) + ")"
            entry = {"name": text}
            if kind == "person":
                (also,) = study.execute("SELECT also_called FROM people WHERE id = ?", (pid,)).fetchone()
                if also:
                    entry["other"] = manual[lang]["also"].get(name) or ", ".join(say(a.strip()) for a in also.split(","))
            else:
                (aliases,) = study.execute("SELECT aliases FROM places WHERE id = ?", (pid,)).fetchone()
                if aliases:
                    entry["other"] = manual[lang]["aliases"].get(aliases, aliases)
            if entry["name"] != name or "other" in entry:
                out[kind][str(pid)] = entry
        for eid, title in study.execute("SELECT id, title FROM events"):
            text = manual[lang]["events"].get(str(eid)) or fill(manual[lang]["event_patterns"], title)
            if not text:
                print(f"{lang}: no translation for event {eid} {title!r}", file=sys.stderr)
                continue
            out["event"][str(eid)] = {"name": text}
        for eid, era in manual[lang]["eras"].items():
            out["era"][eid] = {"name": era[0], "other": era[1]}
        for rid, route in manual[lang]["routes"].items():
            out["route"][rid] = {"name": route[0], "other": route[1]}
        path = os.path.join(HERE, f"{lang}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write("\n")
        print(f"{lang}: {sum(len(v) for v in out.values())} entries -> {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
