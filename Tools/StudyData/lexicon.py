#!/usr/bin/env python3
"""The word-study lexicon's glosses, definitions and origins, translated in
batches (VRS-8 part 4).

    python3 Tools/StudyData/lexicon.py export          # source batches from WordStudy.sqlite
    python3 Tools/StudyData/lexicon.py status
    python3 Tools/StudyData/lexicon.py check es 007    # one batch
    python3 Tools/StudyData/lexicon.py check pt

Source batches (translations/lexicon/source/NNN.json) hold lexicon entries
in Strong's order: each entry's Strong's number, language (hebrew, greek),
lemma (for context only), the SHA-256 of its English fields, and the fields
to translate: gloss (one or two words), definition (Abbott-Smith for the
Greek, Strong's for the Hebrew; line breaks are the layout) and derivation
(Strong's "from 2336"). "In the KJV" (usage) stays English: it lists the
KJV's own English words. Batches are stable: running export again keeps
every entry in its batch, refreshes changed texts (their translations then
show as stale) and puts new entries in new batches.

Translations live in translations/lexicon/<lang>/NNN.json:

    {"batch": "007", "lang": "es", "entries": [
        {"strongs": "G0026", "sha256": "<source sha>", "gloss": "amor",
         "definition": "…", "derivation": "…"}]}

The check, run after each batch: every entry present with the source's
sha; every field the English has, and no other; the same lines; every
number; the Hebrew and Greek words verbatim and in order; the STEPBible
references ("Jhn.13:35", "1Co.2:3") verbatim and in order, and the others
("Ezekiel 29:4") book, chapter and verse (refs.py); no English left; a
sensible length. An entry may carry "note" (why something stays as it
is), listed in translations/lexicon/<lang>/review/NNN.md.
add_lexicon_translations.py uses only entries that pass.
"""
import hashlib
import os
import re
import sqlite3
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bios  # noqa: E402
import refs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
WORDSTUDY = os.path.join(ROOT, "Genesis", "Resources", "Study", "WordStudy.sqlite")
OUT = os.path.join(HERE, "translations", "lexicon")
SOURCE = os.path.join(OUT, "source")
LANGUAGES = ("es", "pt")
FIELDS = ("gloss", "definition", "derivation")
BATCH_WORDS = 6000

# Hebrew and Greek letters; the Greek question mark (;, U+037E) and ano
# teleia (·, U+0387) are punctuation, kept as they are but not part of a word.
LETTER = "֐-׿Ͱ-ͽͿ-ΆΈ-Ͽἀ-῿"
ORIGINAL_WORD = re.compile(rf"[{LETTER}][{LETTER}̀-ͯ]*")
# STEPBible's references: "Jhn.13:35", "1Co.2:3", "2Mac.4:1", "Mat.5" (a chapter).
STEP_REFERENCE = re.compile(r"(?<![\w.])[1-4]?[A-Z][a-z]{1,3}\. ?\d+(?::\d+(?:[-–]\d+)?)?")
# Abbott-Smith also cites with a space ("Jn 2:13", "La 3:63", "Su 1:13",
# often a numbered book's later chapters): in the Greek these are codes too.
SHORT_REFERENCE = re.compile(r"(?<![\w.])(?:[1-4IV]{1,3} ?)?[A-Z][a-z]{0,3} \d+:\d+(?:[-–]\d+)?")
NUMBER = re.compile(r"\d+")
# Sigla of works, editions and versions (LXX, MM, WH, VGT…) and marks (†, *, §).
SIGLUM = re.compile(r"(?<![\w])(?:[A-Z]{2,}[a-z]*|[IVX]+)(?![\w])")
MARKS = re.compile(r"[†*§]")
GREEK_STOPS = re.compile(r"[\u037e\u0387][;,.:]?")
# Words in capitals that aren't sigla, and the ones that change: OT is AT.
NOT_SIGLA = {"JESUS", "LORD", "GOD", "I", "SEÑOR", "SENHOR", "DIOS", "DEUS", "JESÚS", "QUESTION", "PREGUNTA", "PERGUNTA"}
SIGLA_IN = {"OT": "AT"}


# STEPBible's slips in the English, fixed before translating (each with why).
SOURCE_FIXES = {
    # Strong's has "(and irreg. in Exod. 8:17, 18 [Heb. 13, 14])": the Hebrew
    # Bible's verse numbers, which the expansion of "Heb." made Hebrews 13:14.
    ("H3654", "derivation"): ("Exodus 8:17,18; Hebrews 13:14", "Exodus 8:17,18 [Hebrew 8:13,14]"),
}


def sha(entry):
    return hashlib.sha256("\x1f".join(entry.get(f) or "" for f in FIELDS).encode("utf-8")).hexdigest()


def batches():
    if not os.path.isdir(SOURCE):
        return []
    return sorted(n[:-5] for n in os.listdir(SOURCE) if n.endswith(".json"))


def entries_from_db():
    db = sqlite3.connect(WORDSTUDY)
    rows = db.execute("SELECT strongs, language, lemma, gloss, definition, derivation FROM lexicon ORDER BY language DESC, strongs")
    out = {}
    for strongs, language, lemma, gloss, definition, derivation in rows:
        entry = {"strongs": strongs, "language": language, "lemma": lemma or ""}
        for field, value in zip(FIELDS, (gloss, definition, derivation)):
            if (strongs, field) in SOURCE_FIXES and value:
                was, now = SOURCE_FIXES[(strongs, field)]
                assert value.count(was) == 1, (strongs, field)
                value = value.replace(was, now)
            if value and value.strip():
                entry[field] = value
        if any(f in entry for f in FIELDS):
            entry["sha256"] = sha(entry)
            out[strongs] = entry
    db.close()
    return out


def words(entry):
    return sum(len((entry.get(f) or "").split()) for f in FIELDS)


# MARK: Export

def export():
    entries = entries_from_db()
    placed = {}
    for b in batches():
        for s in bios.load(os.path.join(SOURCE, f"{b}.json"))["strongs"]:
            placed[s] = b

    def save(b, keys):
        bios.save(os.path.join(SOURCE, f"{b}.json"),
                  {"batch": b, "strongs": keys, "entries": [entries[k] for k in keys]})

    existing = sorted(set(placed.values()))
    for b in existing:
        save(b, [s for s, pb in placed.items() if pb == b and s in entries])
    number, current, count = len(existing), [], 0
    for key, entry in entries.items():
        if key in placed:
            continue
        n = words(entry)
        if current and count + n > BATCH_WORDS:
            number += 1
            save(f"{number:03d}", current)
            current, count = [], 0
        current.append(key)
        count += n
    if current:
        number += 1
        save(f"{number:03d}", current)
    print(f"{number} batches, {len(entries)} entries in {SOURCE}")


# MARK: Check

def masked(text):
    """The text with STEPBible references blanked, for refs.py."""
    return STEP_REFERENCE.sub(" ", text)


def codes(text, greek):
    """The references copied unchanged: STEPBible's, and in the Greek also
    Abbott-Smith's "Jn 2:13" kind."""
    found = [(m.start(), m.group(0)) for m in STEP_REFERENCE.finditer(text)]
    if greek:
        found += [(m.start(), m.group(0)) for m in SHORT_REFERENCE.finditer(STEP_REFERENCE.sub(lambda m: " " * len(m.group(0)), text))]
    return [code for _, code in sorted(found)]


def check_field(field, source, text, lang, greek=False):
    problems = []
    if not text.strip():
        return ["empty"]
    if source.count("\n") != text.count("\n"):
        problems.append(f"lines {source.count(chr(10)) + 1} -> {text.count(chr(10)) + 1}")
    a, b = Counter(NUMBER.findall(source)), Counter(NUMBER.findall(text))
    if a != b:
        problems.append(f"numbers differ (missing {list((a - b).elements())[:8]}, extra {list((b - a).elements())[:8]})")
    if ORIGINAL_WORD.findall(source) != ORIGINAL_WORD.findall(text):
        want, have = ORIGINAL_WORD.findall(source), ORIGINAL_WORD.findall(text)
        first = next((i for i, (x, y) in enumerate(zip(want, have)) if x != y), min(len(want), len(have)))
        problems.append(f"Hebrew or Greek changed at word {first + 1} (“{want[first] if first < len(want) else ''}” → “{have[first] if first < len(have) else ''}”)")
    sigla = Counter(SIGLA_IN.get(x, x) for x in SIGLUM.findall(source) if x not in NOT_SIGLA)
    kept = Counter(x for x in SIGLUM.findall(text) if x not in NOT_SIGLA)
    if sigla != kept:
        problems.append(f"sigla differ (missing {list((sigla - kept).elements())[:6]}, extra {list((kept - sigla).elements())[:6]})")
    if Counter(GREEK_STOPS.findall(source)) != Counter(GREEK_STOPS.findall(text)):
        problems.append("Greek punctuation differs (a ; or · after a Greek word is the source's own: don't add another)")
    if Counter(MARKS.findall(source)) != Counter(MARKS.findall(text)):
        problems.append("marks † * § differ")
    if codes(source, greek) != codes(text, greek):
        want, have = codes(source, greek), codes(text, greek)
        missing = list((Counter(want) - Counter(have)).elements())
        extra = list((Counter(have) - Counter(want)).elements())
        problems.append(f"STEPBible references differ (missing {missing[:6]}, extra {extra[:6]})" if missing or extra
                        else "STEPBible references in another order")
    if greek:  # Abbott-Smith's references are all codes, checked above
        want = have = []
    else:
        want, have = refs.references(masked(source), "en"), refs.references(masked(text), lang)
    if want != have:
        problems.append(f"references differ ({[refs.label(r) for r in want[:6]]} -> {[refs.label(r) for r in have[:6]]})")
    if field != "gloss":
        count = max(1, len(text.split()))
        english = len(bios.ENGLISH.findall(text))
        if english / count > 0.03 and english > 2:
            problems.append(f"looks untranslated ({english} English words)")
        ratio = len(text) / max(1, len(source))
        if len(source) > 200 and not 0.75 <= ratio <= 1.8:
            problems.append(f"length {ratio:.2f}x the English")
    return problems


def check_entry(entry, t, lang):
    problems, review = [], []
    for field in FIELDS:
        if field not in entry:
            if t.get(field):
                problems.append(f"{field}: not in the English")
            continue
        source, text = entry[field], t.get(field) or ""
        if text == source and re.search(r"(?<![\w-])[a-z]{3,}", STEP_REFERENCE.sub("", source)) and not t.get("note"):
            problems.append(f"{field}: not translated (or give a note)")
        for p in check_field(field, source, text, lang, greek=entry["language"] == "greek"):
            problems.append(f"{field}: {p}")
    if t.get("note"):
        review.append(f"- note: {t['note']}")
    return problems, review


def check(lang, only=None, quiet=False):
    """Prints problems; returns {strongs: {field: text}} of entries that pass."""
    passed, failed, missing = {}, 0, 0
    for b in batches():
        if only and b != only:
            continue
        src = bios.load(os.path.join(SOURCE, f"{b}.json"))
        path = os.path.join(OUT, lang, f"{b}.json")
        if not os.path.exists(path):
            missing += len(src["entries"])
            if only:
                print(f"{lang} {b}: not translated yet")
            continue
        done = {e.get("strongs"): e for e in bios.load(path)["entries"]}
        reviews = []
        for entry in src["entries"]:
            key = entry["strongs"]
            t = done.get(key)
            label = f"{lang} {b} {key} “{(entry.get('gloss') or entry['lemma'])[:30]}”"
            if t is None:
                if not quiet:
                    print(f"{label}: missing")
                missing += 1
                continue
            if t.get("sha256") != entry["sha256"]:
                print(f"{label}: stale (English changed)")
                failed += 1
                continue
            problems, review = check_entry(entry, t, lang)
            if problems:
                print(f"{label}: " + "; ".join(problems))
                failed += 1
            else:
                passed[key] = {f: t[f] for f in FIELDS if f in entry}
                if review:
                    reviews.append(f"### {key} {entry['lemma']} ({entry.get('gloss', '')})\n" + "\n".join(review))
        write_review(lang, b, reviews)
        for key in sorted(set(done) - set(src["strongs"]), key=str):
            print(f"{lang} {b} {key}: not in this batch")
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
        f.write(f"# To review: {lang} lexicon batch {b}\n\n")
        f.write("\n\n".join(reviews) + "\n")


def status():
    total = sum(len(bios.load(os.path.join(SOURCE, f"{b}.json"))["entries"]) for b in batches())
    print(f"{len(batches())} batches, {total} entries")
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
