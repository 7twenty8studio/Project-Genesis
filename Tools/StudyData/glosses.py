#!/usr/bin/env python3
"""The Original view's word-by-word glosses ("in rage my", "they drank"),
translated into Spanish and Portuguese in batches (VRS-6).

    python3 Tools/StudyData/glosses.py export          # source batches from WordStudy.sqlite
    python3 Tools/StudyData/glosses.py status
    python3 Tools/StudyData/glosses.py check es 007    # one batch
    python3 Tools/StudyData/glosses.py check pt

A gloss is STEPBible's English for one Hebrew or Greek word in its verse
(TAHOT, TAGNT; CC BY 4.0). The same English gloss of the same Strong's
number can need two translations when the grammar differs ("your" after a
singular or plural suffix: tu / vuestro), so the unit translated is the
triple (Strong's, morphology, English gloss): about 114,000 of them.
Each has a stable id, the first 16 hex digits of the SHA-256 of
"strongs\\x1fmorph\\x1fgloss", which is also the source checksum: a changed
gloss is a new id, and its old translation shows as "not in this batch".

Source batches (translations/glosses/source/NNN.json) list words in
Strong's order (Hebrew, then Greek), each with its lemma and the lexicon's
meaning in English, Spanish and Portuguese (from lexicon_translations, as
a guide), then its glosses, most used first:

    {"batch": "001", "ids": [...], "words": [
        {"strongs": "H0001G", "lemma": "אָב", "meaning": {"en": "father", "es": "padre", "pt": "pai"},
         "glosses": [{"id": "3f1c…", "morph": "HNcmsa", "gloss": "father", "count": 120}]}]}

Translations, translations/glosses/<lang>/NNN.json:

    {"batch": "001", "lang": "es", "glosses": {"3f1c…": "padre"}, "notes": {"3f1c…": "why"},
     "uncertain": {"9a0b…": "why the meaning is uncertain"}}

The check (after each batch): every id present, a translation for each;
the same [supplied] and <untranslated> brackets, in the same order, and
the same ¿ (STEPBible's mark for Hebrew's question prefix), ? and ! (Spanish
may open ¿ ¡ where the English closes one); the same numbers; the first
letter capital only where the English's is; no Hebrew or Greek letters;
no English words left; a sensible length. A translation spelled as the
English (a name, "Baal") passes when it's capitalised or the lexicon's
Spanish/Portuguese meaning is spelled the same; otherwise it needs a note.
Notes, and glosses flagged `uncertain` for qualified review, are listed
in translations/glosses/<lang>/review/NNN.md. Sources, licences and the
credits they require: translations/glosses/SOURCES.md.
add_gloss_translations.py uses only glosses that pass.
"""
import hashlib
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bios  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
WORDSTUDY = os.path.join(ROOT, "Genesis", "Resources", "Study", "WordStudy.sqlite")
OUT = os.path.join(HERE, "translations", "glosses")
SOURCE = os.path.join(OUT, "source")
LANGUAGES = ("es", "pt")
BATCH_GLOSSES = 2000

ORIGINAL_LETTERS = re.compile(r"[֐-׿Ͱ-Ͽἀ-῿]")
NUMBER = re.compile(r"\d+")
BRACKETS = re.compile(r"[\[\]<>()]")
# English words that are never Spanish or Portuguese words ("he", "son",
# "come", "do", "me", "no", "a" are, so they aren't here).
ENGLISH = re.compile(r"(?<![\w’'-])(the|and|of|to|with|from|she|they|we|you|your|yours|my|our|his|her|their|him|them|is|was|were|will|shall|not|who|whom|which|that|this|these|those|upon|into|all|been|have|had|said|says|say|went|came|give|gave|man|men|house|day|days|king|land|people|it|its|out|up|there|what|when|be|let|made|make|over|under|before|after|against|because|one|ones|did|does)(?![\w’'-])", re.IGNORECASE)


def key_id(strongs, morph, gloss):
    return hashlib.sha256(f"{strongs}\x1f{morph}\x1f{gloss}".encode("utf-8")).hexdigest()[:16]


def gloss_key(strongs, morph, gloss):
    """The 64-bit key the app looks a gloss up by: FNV-1a over the UTF-8 of
    "strongs\\x1fmorph\\x1fgloss", as a signed integer (SQLite's INTEGER).
    `OriginalGlosses.key` in the app computes the same."""
    h = 0xcbf29ce484222325
    for byte in f"{strongs}\x1f{morph}\x1f{gloss}".encode("utf-8"):
        h ^= byte
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h - (1 << 64) if h >= (1 << 63) else h


def batches():
    if not os.path.isdir(SOURCE):
        return []
    return sorted(n[:-5] for n in os.listdir(SOURCE) if n.endswith(".json"))


def lexicon_meanings(db):
    english = {s: (g or "", l or "") for s, g, l in db.execute("SELECT strongs, gloss, lemma FROM lexicon")}
    translated = defaultdict(dict)
    if db.execute("SELECT 1 FROM sqlite_master WHERE name = 'lexicon_translations'").fetchone():
        for lang, s, g in db.execute("SELECT lang, strongs, gloss FROM lexicon_translations"):
            translated[s][lang] = g or ""
    return english, translated


def lexicon_key(strongs, english):
    """The lexicon entry a form's number reads (WordStudyRepository.entry:
    the number itself, else its plain number's first extended entry)."""
    if strongs in english:
        return strongs
    base = re.sub(r"[A-Z]$", "", strongs) if len(strongs) > 1 else strongs
    family = sorted(s for s in english if s == base or (s.startswith(base) and len(s) == len(base) + 1 and s[-1].isalpha()))
    return family[0] if family else None


def words_from_db():
    """{strongs: word} with every (morph, gloss) of it, most used first."""
    db = sqlite3.connect(WORDSTUDY)
    english, translated = lexicon_meanings(db)
    counts = Counter()
    for strongs, morph, gloss, n in db.execute("""
            SELECT f.strongs, f.morph, f.gloss, COUNT(*) FROM forms f
            JOIN (SELECT form FROM word_forms UNION ALL SELECT form FROM greek_words) u ON u.form = f.id
            WHERE f.gloss IS NOT NULL AND trim(f.gloss) != '' GROUP BY f.strongs, f.morph, f.gloss"""):
        counts[(strongs or "", morph or "", gloss)] += n
    db.close()
    words = {}
    for (strongs, morph, gloss), n in counts.items():
        word = words.get(strongs)
        if word is None:
            lex = lexicon_key(strongs, english)
            meaning = {"en": english[lex][0] if lex else ""}
            for lang in LANGUAGES:
                meaning[lang] = translated.get(lex, {}).get(lang, "") if lex else ""
            word = words[strongs] = {"strongs": strongs, "lemma": english[lex][1] if lex else "",
                                     "meaning": meaning, "glosses": []}
        word["glosses"].append({"id": key_id(strongs, morph, gloss), "morph": morph, "gloss": gloss, "count": n})
    for word in words.values():
        word["glosses"].sort(key=lambda g: (-g["count"], g["morph"], g["gloss"]))
    # Hebrew, then Greek, then any untagged word, each in number order.
    order = lambda s: ({"H": 0, "G": 1}.get(s[:1], 2), s)
    return {s: words[s] for s in sorted(words, key=order)}


# MARK: Export

def export():
    words = words_from_db()
    by_id = {g["id"]: (s, g) for s, w in words.items() for g in w["glosses"]}
    placed = {}
    for b in batches():
        for i in bios.load(os.path.join(SOURCE, f"{b}.json"))["ids"]:
            placed[i] = b

    def save(b, ids):
        grouped = {}
        for i in ids:
            strongs, gloss = by_id[i]
            if strongs not in grouped:
                w = words[strongs]
                grouped[strongs] = {k: w[k] for k in ("strongs", "lemma", "meaning")} | {"glosses": []}
            grouped[strongs]["glosses"].append(gloss)
        bios.save(os.path.join(SOURCE, f"{b}.json"), {"batch": b, "ids": ids, "words": list(grouped.values())})

    existing = sorted(set(placed.values()))
    for b in existing:
        save(b, [i for s, w in words.items() for g in w["glosses"] if placed.get(i := g["id"]) == b])
    number, current = len(existing), []
    for strongs, word in words.items():
        new = [g["id"] for g in word["glosses"] if g["id"] not in placed]
        if current and len(current) + len(new) > BATCH_GLOSSES:
            number += 1
            save(f"{number:03d}", current)
            current = []
        current += new
        while len(current) > BATCH_GLOSSES:   # one word with more glosses than a batch
            number += 1
            save(f"{number:03d}", current[:BATCH_GLOSSES])
            current = current[BATCH_GLOSSES:]
    if current:
        number += 1
        save(f"{number:03d}", current)
    print(f"{number} batches, {len(by_id)} glosses of {len(words)} words in {SOURCE}")


# MARK: Check

def first_letter(text):
    m = re.search(r"[^\W\d_]", text)
    return m.group(0) if m else ""


def check_gloss(source, text, lang, meaning, note):
    if not isinstance(text, str) or not text.strip():
        return ["empty"]
    problems = []
    if text != text.strip() or "  " in text:
        problems.append("extra spaces")
    if BRACKETS.findall(source) != BRACKETS.findall(text):
        problems.append(f"brackets differ ({''.join(BRACKETS.findall(source))} -> {''.join(BRACKETS.findall(text))})")
    elif re.search(r"\[\s*\]|<\s*>", text):
        problems.append("empty brackets")
    for mark in "?!":
        if source.count(mark) != text.count(mark):
            problems.append(f"{mark} differs")
    opened = {"?": "¿", "!": "¡"}
    for mark, opener in opened.items():
        lowest = source.count(opener)
        highest = lowest + (source.count(mark) if lang == "es" else 0)
        if not lowest <= text.count(opener) <= highest:
            problems.append(f"{opener} differs")
    if Counter(NUMBER.findall(source)) != Counter(NUMBER.findall(text)):
        problems.append("numbers differ")
    if ORIGINAL_LETTERS.search(text):
        problems.append("Hebrew or Greek letters")
    a, b = first_letter(source), first_letter(text)
    if a and b and a.isupper() != b.isupper():
        problems.append("capital first letter differs from the English")
    if not note:
        left = [w for w in ENGLISH.findall(text)]
        if left and text != source:
            problems.append(f"English left ({', '.join(left[:3])})")
        if text == source and re.search(r"[a-z]{3,}", source):
            spelled_alike = meaning and meaning.lower() == source.lower()
            proper = re.fullmatch(r"(?:[<\[(]?[A-ZÀ-Ý][\w’'-]*[>\])]?[ -]?)+", source)
            if not (spelled_alike or proper):
                problems.append("not translated (or give a note)")
    if len(text) > max(3 * len(source), len(source) + 25):
        problems.append(f"too long ({len(text)} for {len(source)})")
    return problems


def check(lang, only=None, quiet=False):
    """Prints problems; returns {(strongs, morph, gloss): text} that pass."""
    passed, failed, missing = {}, 0, 0
    for b in batches():
        if only and b != only:
            continue
        src = bios.load(os.path.join(SOURCE, f"{b}.json"))
        path = os.path.join(OUT, lang, f"{b}.json")
        if not os.path.exists(path):
            missing += len(src["ids"])
            if only:
                print(f"{lang} {b}: not translated yet")
            continue
        data = bios.load(path)
        done, notes, unsure = data.get("glosses", {}), data.get("notes", {}), data.get("uncertain", {})
        reviews, seen = [], set()
        for word in src["words"]:
            for g in word["glosses"]:
                i = g["id"]
                seen.add(i)
                label = f"{lang} {b} {word['strongs']} {g['morph']} “{g['gloss']}” [{i}]"
                if i not in done:
                    if not quiet:
                        print(f"{label}: missing")
                    missing += 1
                    continue
                problems = check_gloss(g["gloss"], done[i], lang, word["meaning"].get(lang, ""), notes.get(i))
                if problems:
                    print(f"{label} → “{done[i]}”: " + "; ".join(problems))
                    failed += 1
                    continue
                passed[(word["strongs"], g["morph"], g["gloss"])] = done[i]
                for tag, reason in (("uncertain", unsure.get(i)), ("note", notes.get(i))):
                    if reason:
                        reviews.append(f"- **{tag}** {word['strongs']} {word['lemma']} {g['morph']} “{g['gloss']}” → “{done[i]}”: {reason}")
        write_review(lang, b, reviews)
        for i in sorted((set(done) | set(notes) | set(unsure)) - seen):
            print(f"{lang} {b} {i}: not in this batch")
            failed += 1
    print(f"{lang}: {len(passed)} pass, {failed} fail, {missing} to do")
    return passed


def write_review(lang, b, reviews):
    path = os.path.join(OUT, lang, "review", f"{b}.md")
    if not reviews:
        if os.path.exists(path):
            os.remove(path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# To review: {lang} gloss batch {b}\n\n" + "\n".join(reviews) + "\n")


def status():
    total = sum(len(bios.load(os.path.join(SOURCE, f"{b}.json"))["ids"]) for b in batches())
    print(f"{len(batches())} batches, {total} glosses")
    for lang in LANGUAGES:
        done = [b for b in batches() if os.path.exists(os.path.join(OUT, lang, f"{b}.json"))]
        print(f"{lang}: {len(done)} batches translated: {' '.join(done) or '-'}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["export"]:
        export()
    elif args[:1] == ["status"]:
        status()
    elif args[:1] == ["check"] and len(args) in (2, 3) and args[1] in LANGUAGES:
        check(args[1], args[2] if len(args) == 3 else None)
    else:
        sys.exit(__doc__)
