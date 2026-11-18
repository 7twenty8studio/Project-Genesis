#!/usr/bin/env python3
"""Easton's biographies and place descriptions, translated in batches.

    python3 Tools/StudyData/bios.py export RV1909.sqlite  # source batches from Study.sqlite
    python3 Tools/StudyData/bios.py status          # what's done, stale or missing
    python3 Tools/StudyData/bios.py check es 007    # check one translated batch
    python3 Tools/StudyData/bios.py check pt        # check every batch in a language

Source batches (translations/bios/source/NNN.json) hold each entry's kind
(person or place), id, the SHA-256 of its English text and the text, plus
a glossary of the names it mentions as they're spelled in the app
(translations/<lang>.json), and its quotations: which are Scripture and
the Reina-Valera 1909 / Bíblia Livre words to quote (scripture_quotes.py). Batches are stable: running export again keeps
every entry in its batch, refreshes changed texts (their translations then
show as stale) and puts new entries in new batches.

Translations live in translations/bios/<lang>/NNN.json:

    {"batch": "007", "lang": "es", "entries": [
        {"kind": "person", "id": 12, "sha256": "<source sha>", "text": "…"}]}

The check, run after each batch: every entry present, its sha256 the
source's, the same paragraphs, every number the source has (references,
years, ages), the same quotations in the same order, Scripture quoted
verbatim from the RV1909 / Bíblia Livre, Hebrew and Greek letters kept, no
English left, a sensible length. add_study_translations.py uses only
entries that pass. Partial, loose and KJV-wording quotations also go to
translations/bios/<lang>/review/NNN.md for a person to look over.
"""
import hashlib
import json
import os
import re
import sqlite3
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scripture_quotes  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUDY = os.path.join(ROOT, "Genesis", "Resources", "Study", "Study.sqlite")
HERE = os.path.join(ROOT, "Tools", "StudyData", "translations")
BIOS = os.path.join(HERE, "bios")
SOURCE = os.path.join(BIOS, "source")
LANGUAGES = ("es", "pt")
BATCH_WORDS = 5000

ORIGINAL_LETTERS = re.compile(r"[֐-׿Ͱ-Ͽἀ-῿]")
NUMBER = re.compile(r"\d+")
ENGLISH = re.compile(r"\b(the|and|which|was|were|with|from|this|that|who|his|their|by|of)\b")


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def source_texts(db=None):
    db = db or sqlite3.connect(STUDY)
    texts = {}
    for kind, table in (("person", "people"), ("place", "places")):
        for pid, name, bio in db.execute(f"SELECT id, name, bio FROM {table} WHERE bio <> '' ORDER BY id"):
            texts[(kind, pid)] = (name, bio)
    return texts


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


def batches():
    if not os.path.isdir(SOURCE):
        return []
    return sorted(n[:-5] for n in os.listdir(SOURCE) if n.endswith(".json"))


# MARK: Glossary

def name_maps():
    """English name -> {lang: name in the app}, from the short-label translations."""
    db = sqlite3.connect(STUDY)
    english = {}
    for kind, table in (("person", "people"), ("place", "places")):
        for pid, name in db.execute(f"SELECT id, name FROM {table}"):
            english[(kind, str(pid))] = re.sub(r"\s*\(.*\)$", "", name)
    maps = {}
    for lang in LANGUAGES:
        data = load(os.path.join(HERE, f"{lang}.json"))
        spellings = {}
        for kind in ("person", "place"):
            for key, entry in data[kind].items():
                base = english.get((kind, key))
                local = re.sub(r"\s*\(.*\)$", "", entry["name"])
                if base and local and local != base:
                    spellings.setdefault(base, Counter())[(kind, local)] += 1
        for base, counts in spellings.items():
            locals_ = {}
            for (kind, local), n in counts.most_common():
                locals_.setdefault(local, kind)
            if len(locals_) == 1:
                maps.setdefault(base, {})[lang] = next(iter(locals_))
            else:
                # One English name, several people or places ("Tamar"): say which is which.
                maps.setdefault(base, {})[lang] = "; ".join(f"{local} ({kind})" for local, kind in locals_.items())
    return maps


def glossary(texts, maps):
    found = {}
    joined = "\n".join(texts)
    for name, local in maps.items():
        if re.search(r"(?<![\w-])" + re.escape(name) + r"(?![\w-])", joined):
            found[name] = local
    return dict(sorted(found.items()))


# MARK: Export

def export(rv1909: str):
    texts = source_texts()
    bibles = scripture_quotes.Bibles(rv1909)

    def entry(kind, pid, name, text):
        return {"kind": kind, "id": pid, "name": name, "sha256": sha(text), "text": text,
                "quotes": scripture_quotes.quotations(text, bibles)}

    maps = name_maps()
    placed = {}
    existing = {}
    for b in batches():
        data = load(os.path.join(SOURCE, f"{b}.json"))
        existing[b] = data
        for e in data["entries"]:
            placed[(e["kind"], e["id"])] = b
    changed = 0
    for b, data in existing.items():
        entries = []
        for e in data["entries"]:
            key = (e["kind"], e["id"])
            if key not in texts:
                changed += 1
                continue  # no longer has a description
            name, text = texts[key]
            if e["sha256"] != sha(text):
                changed += 1
            entries.append(e if e["sha256"] == sha(text) and "quotes" in e else entry(e["kind"], e["id"], name, text))
        data["entries"] = entries
        data["glossary"] = glossary([e["text"] for e in entries], maps)
        save(os.path.join(SOURCE, f"{b}.json"), data)
    new = [k for k in texts if k not in placed]
    number = len(existing)
    current, words = [], 0

    def flush():
        nonlocal number, current, words
        if not current:
            return
        number += 1
        b = f"{number:03d}"
        entries = [entry(k, i, *texts[(k, i)]) for k, i in current]
        save(os.path.join(SOURCE, f"{b}.json"), {"batch": b, "entries": entries, "glossary": glossary([e["text"] for e in entries], maps)})
        current, words = [], 0

    for key in new:
        n = len(texts[key][1].split())
        if current and words + n > BATCH_WORDS:
            flush()
        current.append(key)
        words += n
    flush()
    print(f"{number} batches ({len(new)} new entries, {changed} changed or removed) in {SOURCE}")


# MARK: Check

QUOTED = re.compile(r"“([^”]*)”")


def verbatim(piece: str, bible: str) -> bool:
    """A quoted piece is the Bible's own words: a run of its text, edge
    punctuation and the first letter's case aside."""
    piece = piece.strip(" ,.;:!?¡¿")
    if not piece:
        return False
    if piece in bible:
        return True
    return (piece[0].swapcase() + piece[1:]) in bible


def check_quotes(lang, quotes, text):
    """Problems with the quotations, and the review lines for this entry."""
    problems, review = [], []
    found = QUOTED.findall(text)
    if len(found) != len(quotes):
        return [f"{len(quotes)} quotations in the English, {len(found)} in the translation"], []
    for q, t in zip(quotes, found):
        bible = q.get(lang, "")
        kind = q["kind"]
        ref = ", ".join(f"{scripture_quotes.BOOKS[v // 1_000_000 - 1]} {v // 1000 % 1000}:{v % 1000}" for v in q.get("verses", []))
        if kind == "whole" and not (verbatim(t, bible) and len(t.strip(" ,.;:")) >= 0.8 * len(bible.strip(" ,.;:"))):
            problems.append(f"quotation {q['n'] + 1} isn't the whole verse verbatim")
        elif kind in ("partial", "loose") and not all(verbatim(p, bible) for p in re.split(r"\s*(?:…|\.\.\.)\s*", t) if p.strip()):
            problems.append(f"quotation {q['n'] + 1} isn't the Bible's words verbatim")
        if kind in ("partial", "loose", "wording", "unsure"):
            review.append(f"- {kind} ({ref}): “{q['english']}” → “{t}”")
    return problems, review


def check_entry(source: str, text: str, quotes=(), lang="es"):
    """(problems, review lines) for one translation; no problems when it's fine."""
    problems = []
    if not text.strip():
        return ["empty"], []
    if source.count("\n\n") != text.count("\n\n"):
        problems.append(f"paragraphs {source.count(chr(10) * 2) + 1} -> {text.count(chr(10) * 2) + 1}")
    a, b = Counter(NUMBER.findall(source)), Counter(NUMBER.findall(text))
    if a != b:
        missing = list((a - b).elements())
        extra = list((b - a).elements())
        problems.append(f"numbers differ (missing {missing[:8]}, extra {extra[:8]})")
    if Counter(ORIGINAL_LETTERS.findall(source)) != Counter(ORIGINAL_LETTERS.findall(text)):
        problems.append("Hebrew or Greek letters changed")
    words = max(1, len(text.split()))
    english = len(ENGLISH.findall(text))
    if english / words > 0.03 and english > 2:
        problems.append(f"looks untranslated ({english} English words)")
    ratio = len(text) / max(1, len(source))
    if len(source) > 200 and not 0.8 <= ratio <= 1.7:
        problems.append(f"length {ratio:.2f}x the English")
    quote_problems, review = check_quotes(lang, list(quotes), text)
    return problems + quote_problems, review


def check(lang, only=None):
    """Prints problems; returns {(kind, id): text} of entries that pass."""
    passed, failed, missing = {}, 0, 0
    for b in batches():
        if only and b != only:
            continue
        src = load(os.path.join(SOURCE, f"{b}.json"))
        path = os.path.join(BIOS, lang, f"{b}.json")
        if not os.path.exists(path):
            missing += len(src["entries"])
            if only:
                print(f"{lang} {b}: not translated yet")
            continue
        done = {(e["kind"], e["id"]): e for e in load(path)["entries"]}
        reviews = []
        for e in src["entries"]:
            key = (e["kind"], e["id"])
            t = done.get(key)
            if t is None:
                print(f"{lang} {b} {e['kind']} {e['id']} {e['name']}: missing")
                missing += 1
                continue
            if t.get("sha256") != e["sha256"]:
                print(f"{lang} {b} {e['kind']} {e['id']} {e['name']}: stale (English changed)")
                failed += 1
                continue
            problems, review = check_entry(e["text"], t["text"], e.get("quotes", []), lang)
            if problems:
                print(f"{lang} {b} {e['kind']} {e['id']} {e['name']}: " + "; ".join(problems))
                failed += 1
            else:
                passed[key] = t["text"]
                if review:
                    reviews.append(f"### {e['name']} ({e['kind']} {e['id']})\n" + "\n".join(review))
        write_review(lang, b, reviews)
        extra = set(done) - {(e["kind"], e["id"]) for e in src["entries"]}
        for kind, pid in sorted(extra):
            print(f"{lang} {b} {kind} {pid}: not in this batch")
            failed += 1
    print(f"{lang}: {len(passed)} pass, {failed} fail, {missing} to do")
    return passed


def write_review(lang, b, reviews):
    path = os.path.join(BIOS, lang, "review", f"{b}.md")
    if not reviews:
        if os.path.exists(path):
            os.remove(path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"# Quotations to review: {lang} batch {b}\n\n")
        f.write("Partial and loose quotations use the Bible's words verbatim; wording ones are Easton commenting on a KJV rendering; unsure ones were found in a verse he doesn't cite and were translated.\n\n")
        f.write("\n\n".join(reviews) + "\n")


def status():
    total = sum(len(load(os.path.join(SOURCE, f"{b}.json"))["entries"]) for b in batches())
    print(f"{len(batches())} batches, {total} entries")
    for lang in LANGUAGES:
        done = [b for b in batches() if os.path.exists(os.path.join(BIOS, lang, f"{b}.json"))]
        print(f"{lang}: {len(done)} batches translated: {' '.join(done) or '-'}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["export"] and len(args) == 2:
        export(args[1])
    elif args[:1] == ["status"]:
        status()
    elif args[:1] == ["check"] and len(args) in (2, 3) and args[1] in LANGUAGES:
        ok = check(args[1], args[2] if len(args) == 3 else None)
    else:
        sys.exit(__doc__)
