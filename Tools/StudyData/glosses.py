#!/usr/bin/env python3
"""The Original view's word-by-word glosses ("in rage my", "they drank"),
translated into Spanish and Portuguese in batches (VRS-6).

    python3 Tools/StudyData/glosses.py export          # source batches from WordStudy.sqlite
    python3 Tools/StudyData/glosses.py status
    python3 Tools/StudyData/glosses.py check es 007    # one batch
    python3 Tools/StudyData/glosses.py check pt
    python3 Tools/StudyData/glosses.py needs-context 007   # ids to read in their verses
    python3 Tools/StudyData/glosses.py context 007 <id> [<id>…] [--all]

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
     "uncertain": {"9a0b…": "why the meaning is uncertain"},
     "checked": ["5d2e…"],
     "occurrences": {"5d2e…": {"1004009.13": "[soy] yo"}}}

`checked` lists the glosses read in their verses (`context`): every id
`needs-context` names must be there. One (Strong's, morphology, English)
can cover verses that need different words ("[was]" era / estaba / fue /
había): `occurrences` gives those verses their own translation, by
"<verse id>.<position>" (OriginalWord.position: the Hebrew word's place,
TAGNT's word number), and the gloss in `glosses` serves the rest.

The check (after each batch): every id present, a translation for each;
the same [supplied] and <untranslated> brackets, in the same order, and
the same ¿ (STEPBible's mark for Hebrew's question prefix), ? and ! (Spanish
may open ¿ ¡ where the English closes one); the same numbers; no capital first
letter where the English has none; no Hebrew or Greek letters;
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

KJV = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "KJV.sqlite")
# Words English supplies in brackets whose tense, mood or verb (ser/estar,
# era/fue) only the verse settles; modals that may be future or "want".
SUPPLIED_VERB = re.compile(r"\[(?:[^\]]*\s)?(?:was|were|is|are|am|be|been|being|will|shall|would|should|may|might|let|had|has|have|did|do|does)\b[^\]]*\]", re.IGNORECASE)
MODAL = re.compile(r"(?<![\w-])(?:will|shall|would|should|may|might|let)(?![\w-])", re.IGNORECASE)
# The Hebrew interrogative particle (morph Ti), which STEPBible marks "¿":
# a word, not punctuation, so it's translated: "acaso" / "porventura".
QUESTION_WORD = {"es": "acaso", "pt": "porventura"}
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


# MARK: Verses

_OCCURRENCES = None


def occurrences():
    """{unit id: [(verse, position)]} and {verse: [(position, english gloss, id)]}."""
    global _OCCURRENCES
    if _OCCURRENCES is None:
        db = sqlite3.connect(WORDSTUDY)
        by_id, by_verse = defaultdict(list), defaultdict(list)
        rows = db.execute("""
            SELECT w.verse, w.position, f.strongs, f.morph, f.gloss FROM word_forms w JOIN forms f ON f.id = w.form
            UNION SELECT g.verse, g.number, f.strongs, f.morph, f.gloss FROM greek_words g JOIN forms f ON f.id = g.form""")
        for verse, position, strongs, morph, gloss in rows:
            if not gloss or not gloss.strip():
                continue
            i = key_id(strongs or "", morph or "", gloss)
            by_id[i].append((verse, position))
            by_verse[verse].append((position, gloss, i))
        db.close()
        for v in by_verse.values():
            v.sort()
        for v in by_id.values():
            v.sort()
        _OCCURRENCES = by_id, by_verse
    return _OCCURRENCES


def needs_context(gloss):
    return bool(SUPPLIED_VERB.search(gloss) or MODAL.search(gloss) or "¿" in gloss)


def needs_context_ids(src, data=None):
    """Ids that must be read in their verses: supplied verbs and modals,
    the question particle, and whatever the translator flagged uncertain."""
    unsure = set((data or {}).get("uncertain", {}))
    by_id = occurrences()[0]
    return [g["id"] for w in src["words"] for g in w["glosses"]
            if (needs_context(g["gloss"]) or g["id"] in unsure) and by_id.get(g["id"])]


def reference(verse):
    book, chapter, number = verse // 1_000_000, verse // 1000 % 1000, verse % 1000
    return f"{BOOK_NAMES[book - 1]} {chapter}:{number}"


BOOK_NAMES = ("Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr Ezra Neh Esth Job Ps Prov Eccl Song "
              "Isa Jer Lam Ezek Dan Hos Joel Amos Obad Jonah Mic Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom "
              "1Cor 2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Phlm Heb Jas 1Pet 2Pet 1John 2John 3John Jude Rev").split()


def context(b, ids, show_all=False):
    """Each gloss in its verses: the KJV (public domain) and the verse's
    English glosses with this word in ⟦ ⟧."""
    by_id, by_verse = occurrences()
    src = bios.load(os.path.join(SOURCE, f"{b}.json"))
    glosses = {g["id"]: (w, g) for w in src["words"] for g in w["glosses"]}
    kjv = sqlite3.connect(KJV)
    for i in ids:
        if i not in glosses:
            print(f"{i}: not in batch {b}")
            continue
        w, g = glosses[i]
        places = by_id.get(i, [])
        print(f"== {i} {w['strongs']} {w['lemma']} {g['morph']} “{g['gloss']}” ({len(places)}×)")
        for verse, position in (places if show_all else places[:8]):
            line = " | ".join(f"⟦{gl}⟧" if p == position and gi == i else gl for p, gl, gi in by_verse[verse])
            text = kjv.execute("SELECT text FROM verses WHERE id = ?", (verse,)).fetchone()
            print(f"  {verse}.{position} {reference(verse)}: {line}")
            if text:
                print(f"      KJV: {text[0]}")
        if len(places) > 8 and not show_all:
            print(f"  … {len(places) - 8} more (--all)")


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
    # A question the English shows only by its word order ("will we eat")
    # may take one "?" (Spanish "¿…?").
    if source.count("!") != text.count("!"):
        problems.append("! differs")
    if not source.count("?") <= text.count("?") <= source.count("?") + 1:
        problems.append("? differs")
    if lang == "es" and text.count("¿") > text.count("?") or text.count("¡") > text.count("!"):
        problems.append("¿ ¡ without ? !")
    if Counter(NUMBER.findall(source)) != Counter(NUMBER.findall(text)):
        problems.append("numbers differ")
    # STEPBible's "¿" is the Hebrew question particle: a word in both
    # languages, never a lone inverted mark (Portuguese has none at all).
    if "¿" in source:
        word = QUESTION_WORD[lang]
        if len(re.findall(rf"(?<!\w){word}(?!\w)", text, re.IGNORECASE)) < source.count("¿"):
            problems.append(f"the question particle ¿ is “{word}” here")
    if lang == "pt" and re.search("[¿¡]", text):
        problems.append("Portuguese has no ¿ or ¡")
    if lang == "es":
        opened = 0
        for ch in text:
            if ch in "¿¡":
                opened += 1
            elif ch in "?!" and opened:
                opened -= 1
        if opened:
            problems.append("a ¿ or ¡ with no closing mark in this gloss")
    if ORIGINAL_LETTERS.search(text):
        problems.append("Hebrew or Greek letters")
    a, b = first_letter(source), first_letter(text)
    # No capital the English lacks; a capital English start may become lower
    # case (gentilics "Edomite" → "edomita", "Abel towards" → "hacia Abel").
    if a and b and b.isupper() and not a.isupper():
        problems.append("capital first letter where the English has none")
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


def reviewed():
    """{lang: {id: "who, when"}}: uncertain glosses a qualified reviewer has
    signed off (translations/glosses/reviewed.json, edited by hand only)."""
    path = os.path.join(OUT, "reviewed.json")
    return bios.load(path) if os.path.exists(path) else {}


def check(lang, only=None, quiet=False, full=False):
    """Prints problems; returns {(strongs, morph, gloss): text} that pass, or
    with full=True (glosses, occurrences, awaiting): glosses as above,
    occurrences {(verse, position, triple): text}, and the triples whose
    uncertain meaning awaits qualified review."""
    passed, verses, awaiting, failed, missing = {}, {}, set(), 0, 0
    signed = reviewed().get(lang, {})
    by_id = occurrences()[0]
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
        checked, per_verse = set(data.get("checked", [])), data.get("occurrences", {})
        must = set(needs_context_ids(src, data))
        reviews, seen = [], set()
        for word in src["words"]:
            for g in word["glosses"]:
                i = g["id"]
                seen.add(i)
                triple = (word["strongs"], g["morph"], g["gloss"])
                label = f"{lang} {b} {word['strongs']} {g['morph']} “{g['gloss']}” [{i}]"
                if i not in done:
                    if not quiet:
                        print(f"{label}: missing")
                    missing += 1
                    continue
                meaning = word["meaning"].get(lang, "")
                problems = check_gloss(g["gloss"], done[i], lang, meaning, notes.get(i))
                if i in must and i not in checked:
                    problems.append("read it in its verses (context) and list it in checked")
                places = set(by_id.get(i, []))
                for place, text in per_verse.get(i, {}).items():
                    verse, _, position = place.partition(".")
                    if not (verse.isdigit() and position.isdigit()) or (int(verse), int(position)) not in places:
                        problems.append(f"occurrence {place} isn't this gloss's")
                    else:
                        problems += [f"{place}: {x}" for x in check_gloss(g["gloss"], text, lang, meaning, notes.get(i))]
                if problems:
                    print(f"{label} → “{done[i]}”: " + "; ".join(problems))
                    failed += 1
                    continue
                passed[triple] = done[i]
                for place, text in per_verse.get(i, {}).items():
                    verse, _, position = place.partition(".")
                    verses[(int(verse), int(position), triple)] = text
                waits = i in unsure and i not in signed
                if waits:
                    awaiting.add(triple)
                if i in unsure:
                    status = "AWAITING QUALIFIED REVIEW" if waits else f"reviewed ({signed[i]})"
                    reviews.append(f"- **uncertain, {status}** {word['strongs']} {word['lemma']} {g['morph']} “{g['gloss']}” → “{done[i]}”: {unsure[i]}")
                if notes.get(i):
                    reviews.append(f"- **note** {word['strongs']} {word['lemma']} {g['morph']} “{g['gloss']}” → “{done[i]}”: {notes[i]}")
                for place, text in per_verse.get(i, {}).items():
                    reviews.append(f"- **in {reference(int(place.partition('.')[0]))} ({place})** “{g['gloss']}” → “{text}” (elsewhere “{done[i]}”)")
        write_review(lang, b, reviews)
        for i in sorted((set(done) | set(notes) | set(unsure) | set(per_verse)) - seen):
            print(f"{lang} {b} {i}: not in this batch")
            failed += 1
    print(f"{lang}: {len(passed)} pass, {failed} fail, {missing} to do; {len(awaiting)} uncertain awaiting qualified review")
    return (passed, verses, awaiting) if full else passed


def write_review(lang, b, reviews):
    path = os.path.join(OUT, lang, "review", f"{b}.md")
    if not reviews:
        if os.path.exists(path):
            os.remove(path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# To review: {lang} gloss batch {b}\n\n"
                "Uncertain meanings stay AWAITING QUALIFIED REVIEW until a reviewer signs them off in\n"
                "../../reviewed.json; passing glosses.py check never marks them reviewed.\n\n"
                + "\n".join(reviews) + "\n")


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
    elif args[:1] == ["needs-context"] and len(args) == 2:
        src = bios.load(os.path.join(SOURCE, f"{args[1]}.json"))
        extra = {}
        for lang in LANGUAGES:
            path = os.path.join(OUT, lang, f"{args[1]}.json")
            if os.path.exists(path):
                extra.setdefault("uncertain", {}).update(bios.load(path).get("uncertain", {}))
        print("\n".join(needs_context_ids(src, extra)))
    elif args[:1] == ["context"] and len(args) >= 3:
        context(args[1], [a for a in args[2:] if a != "--all"], show_all="--all" in args)
    else:
        sys.exit(__doc__)
