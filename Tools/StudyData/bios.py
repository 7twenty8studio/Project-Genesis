#!/usr/bin/env python3
"""Easton's biographies and place descriptions, translated in batches.

    python3 Tools/StudyData/bios.py export RV1909.sqlite  # source batches from Study.sqlite
    python3 Tools/StudyData/bios.py status          # what's done, stale or missing
    python3 Tools/StudyData/bios.py check es 007    # check one translated batch
    python3 Tools/StudyData/bios.py check pt        # check every batch in a language
    python3 Tools/StudyData/bios.py check es --rv1909 RV1909.sqlite  # also re-read fixed quotes' verses
    python3 Tools/StudyData/bios.py fix es --rv1909 RV1909.sqlite    # save fixed quotes' Bible words

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

An entry may also carry corrections, each with a reason, all listed for
review:
  quote_fixes      [{"n", "reference", "mode", "reason", "bible"}]: the
                   finder matched quotation n to the wrong verses.
                   "verbatim": the quotation must be the words of the
                   corrected reference ("1Sam 1:26-28", book codes from
                   scripture_quotes.BOOKS; several joined by "; "), whose
                   RV1909 / Bíblia Livre text `fix` saves in "bible" and
                   the check compares with the Bible when it has it (the
                   Bíblia Livre always; the RV1909 with --rv1909 or
                   GENESIS_RV1909). "translated": not Scripture, or words
                   that Bible lacks (an A.V., R.V. or LXX reading Easton
                   discusses); the reference is optional.
  reference_fixes  [{"was", "now", "reason"}]: Easton's slip in a
                   reference ("John. 15:44" for Josh. 15:44), applied to
                   the English before references are compared.

The check, run after each batch: every entry present, its sha256 the
source's, the same paragraphs, every number the source has (years, ages),
the same Bible references, book, chapter and verse, in the same order
(refs.py), the same quotations in the same order, Scripture quoted
verbatim from the RV1909 / Bíblia Livre, Hebrew and Greek letters kept, no
English left, a sensible length. add_study_translations.py uses only
entries that pass. Partial, loose, KJV-wording and fixed quotations go to
translations/bios/<lang>/review/NNN.md for a person to look over, with a
note where the verses found hold under 85% of Easton's words (the
translation may leave part of the quotation out). Passing the check
doesn't prove a translation complete; the review files and NOTES.md are
for that. Tests: python3 -m unittest Tools/StudyData/test_bios.py
"""
import hashlib
import json
import os
import re
import sqlite3
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refs  # noqa: E402
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
                if base and local:
                    spellings.setdefault(base, Counter())[(kind, local)] += 1
        # Names the translation keeps ("Tamar") count too, so a shared
        # English name shows every spelling.
        for (kind, key), base in english.items():
            if key not in data[kind] and base in spellings:
                spellings[base][(kind, base)] += 1
        for base, counts in spellings.items():
            if all(local == base for _, local in counts):
                continue
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


_KJV = {}


def kjv_coverage(english, verses):
    """The share of the quotation's longer words found in the KJV verses
    it was matched to: low means the finder may have missed a verse and
    the translation could leave part of Easton's quotation out (Hannah)."""
    if not _KJV:
        db = sqlite3.connect(os.path.join(scripture_quotes.BIBLES, "KJV.sqlite"))
        _KJV.update(db.execute("SELECT id, text FROM verses"))
        db.close()
    words = {w for w in scripture_quotes.norm(re.sub(r"\[[^\]]*\]", " ", english)).split() if len(w) > 3}
    have = set(scripture_quotes.norm(" ".join(_KJV.get(v, "") for v in verses)).split())
    return len(words & have) / len(words) if words else 1.0


def fix_problems(fix):
    """What's wrong with one quote_fixes entry itself."""
    problems = []
    if not fix.get("reason", "").strip():
        problems.append(f"quote fix {fix.get('n')} needs a reason")
    mode = fix.get("mode")
    if mode not in ("verbatim", "translated"):
        problems.append(f"quote fix {fix.get('n')}: mode must be verbatim or translated")
    if mode == "verbatim":
        try:
            refs.parse(fix.get("reference", ""))
        except ValueError as error:
            problems.append(f"quote fix {fix.get('n')}: {error}")
        if not fix.get("bible"):
            problems.append(f"quote fix {fix.get('n')}: no Bible text yet (run bios.py fix)")
    elif fix.get("reference"):
        try:
            refs.parse(fix["reference"])
        except ValueError as error:
            problems.append(f"quote fix {fix.get('n')}: {error}")
    return problems


def check_quotes(lang, quotes, text, fixes=()):
    """Problems with the quotations, and the review lines for this entry.
    `fixes` are the entry's quote_fixes: a quotation whose verse the
    finder got wrong, with the corrected reference and either `verbatim`
    (checked against that reference's RV1909 / Bíblia Livre words, kept in
    `bible` by `bios.py fix` and compared with the Bible itself whenever
    it's at hand) or `translated` (not Scripture, or words that Bible
    lacks; a reason is required). Every fix is listed for review."""
    problems, review = [], []
    found = QUOTED.findall(text)
    if len(found) != len(quotes):
        return [f"{len(quotes)} quotations in the English, {len(found)} in the translation"], []
    by_n = {}
    for fix in fixes:
        if fix.get("n") not in range(len(quotes)):
            problems.append(f"quote fix for quotation {fix.get('n')}, which doesn't exist")
            continue
        by_n[fix["n"]] = fix
        problems += fix_problems(fix)
    for q, t in zip(quotes, found):
        bible = q.get(lang, "")
        kind = q["kind"]
        ref = ", ".join(f"{scripture_quotes.BOOKS[v // 1_000_000 - 1]} {v // 1000 % 1000}:{v % 1000}" for v in q.get("verses", []))
        fix = by_n.get(q["n"])
        if fix:
            was = f"{kind}, {ref}" if ref else kind
            if fix.get("mode") == "verbatim":
                if not all(verbatim(p, fix.get("bible", "")) for p in re.split(r"\s*(?:…|\.\.\.)\s*", t) if p.strip()):
                    problems.append(f"quotation {q['n'] + 1} isn't the words of {fix.get('reference')} verbatim")
                review.append(f"- corrected to {fix.get('reference')}, quoted verbatim (found: {was}; {fix.get('reason', '')}): “{q['english']}” → “{t}”")
            else:
                at = f"{fix['reference']}, " if fix.get("reference") else ""
                review.append(f"- translated, not quoted ({at}found: {was}; {fix.get('reason', '')}): “{q['english']}” → “{t}”")
            continue
        if kind == "whole" and not (verbatim(t, bible) and len(t.strip(" ,.;:")) >= 0.8 * len(bible.strip(" ,.;:"))):
            problems.append(f"quotation {q['n'] + 1} isn't the whole verse verbatim")
        elif kind in ("partial", "loose") and not all(verbatim(p, bible) for p in re.split(r"\s*(?:…|\.\.\.)\s*", t) if p.strip()):
            problems.append(f"quotation {q['n'] + 1} isn't the Bible's words verbatim")
        if kind in ("partial", "loose", "wording", "unsure"):
            review.append(f"- {kind} ({ref}): “{q['english']}” → “{t}”")
        if kind in ("whole", "partial", "loose") and (share := kjv_coverage(q["english"], q.get("verses", []))) < 0.85:
            review.append(f"  - only {share:.0%} of Easton's words are in {ref}: check the translation leaves none of the quotation out")
    return problems, review


def check_references(source, text, lang, fixes=()):
    """Problems if the translation's Bible references aren't the source's,
    book, chapter and verse, in the same order. `fixes` are the entry's
    reference_fixes: {"was", "now", "reason"}, a correction of Easton's
    English (a slip such as "John. 15:44" for Josh. 15:44) made before
    comparing; "was" must appear in the English exactly once."""
    problems = []
    for fix in fixes:
        was, now = fix.get("was", ""), fix.get("now", "")
        if not fix.get("reason", "").strip():
            problems.append(f"reference fix “{was}” needs a reason")
        if not was or source.count(was) != 1:
            problems.append(f"reference fix “{was}” isn't in the English exactly once")
            continue
        source = source.replace(was, now)
    want, have = refs.references(source, "en"), refs.references(text, lang)
    if want != have:
        missing = list((Counter(want) - Counter(have)).elements())
        extra = list((Counter(have) - Counter(want)).elements())
        if missing or extra:
            problems.append(f"references differ (missing {[refs.label(r) for r in missing[:6]]}, extra {[refs.label(r) for r in extra[:6]]})")
        else:
            problems.append("references in another order")
    return problems


def check_entry(source: str, text: str, quotes=(), lang="es", quote_fixes=(), reference_fixes=()):
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
    problems += check_references(source, text, lang, reference_fixes)
    quote_problems, review = check_quotes(lang, list(quotes), text, quote_fixes)
    for fix in reference_fixes:
        review.append(f"- reference corrected: “{fix.get('was')}” → “{fix.get('now')}” ({fix.get('reason', '')})")
    return problems + quote_problems, review


class FixBibles:
    """The RV1909 / Bíblia Livre words of a corrected reference, for quote
    fixes. The Bíblia Livre is bundled; the RV1909 is the catalog's file,
    decompressed (--rv1909 PATH or GENESIS_RV1909)."""

    def __init__(self, rv1909=None):
        rv1909 = rv1909 or os.environ.get("GENESIS_RV1909")
        self.paths = {"pt": os.path.join(scripture_quotes.BIBLES, "BLIVRE.sqlite"), "es": rv1909}
        self.verses = {}
        self.rv_map = None

    def has(self, lang):
        return bool(self.paths.get(lang)) and os.path.exists(self.paths[lang])

    def text(self, lang, reference):
        if lang not in self.verses:
            db = sqlite3.connect(self.paths[lang])
            self.verses[lang] = dict(db.execute("SELECT id, text FROM verses"))
            db.close()
        ids = refs.parse(reference)
        if lang == "es":
            if self.rv_map is None:
                self.rv_map = scripture_quotes.rv1909_map()
            ids = [r for i in ids for r in self.rv_map.get(i, [i])]
            ids = list(dict.fromkeys(ids))
        missing = [i for i in ids if i not in self.verses[lang]]
        if missing:
            raise ValueError(f"{reference}: no verse {missing[0]} in the {lang} Bible")
        return " ".join(self.verses[lang][i] for i in ids)


def bible_text_problems(lang, fixes, bibles):
    """A verbatim fix's saved `bible` text must be the Bible's own."""
    problems = []
    if not bibles.has(lang):
        return problems
    for fix in fixes:
        if fix.get("mode") != "verbatim" or not fix.get("reference"):
            continue
        try:
            if bibles.text(lang, fix["reference"]) != fix.get("bible"):
                problems.append(f"quote fix {fix.get('n')}: its bible text isn't {fix['reference']} (run bios.py fix)")
        except ValueError as error:
            problems.append(f"quote fix {fix.get('n')}: {error}")
    return problems


def fill_fixes(lang, rv1909=None):
    """Writes each verbatim quote fix's Bible text (`bible`) from its reference."""
    bibles = FixBibles(rv1909)
    if not bibles.has(lang):
        sys.exit(f"{lang}: the Bible isn't at hand (pass --rv1909 PATH)")
    changed = 0
    for b in batches():
        path = os.path.join(BIOS, lang, f"{b}.json")
        if not os.path.exists(path):
            continue
        data = load(path)
        touched = False
        for e in data["entries"]:
            for fix in e.get("quote_fixes", []):
                if fix.get("mode") == "verbatim" and fix.get("reference"):
                    text = bibles.text(lang, fix["reference"])
                    if fix.get("bible") != text:
                        fix["bible"] = text
                        touched = True
                        changed += 1
        if touched:
            save(path, data)
    print(f"{lang}: {changed} quote fixes given their Bible text")


def check(lang, only=None, bibles=None):
    """Prints problems; returns {(kind, id): text} of entries that pass.
    With `bibles` (scripture_quotes.Bibles) each verbatim quote fix's
    `bible` text is also compared with the Bible itself."""
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
            if "wrong_verse" in t:
                print(f"{lang} {b} {e['kind']} {e['id']} {e['name']}: wrong_verse is replaced by quote_fixes")
                failed += 1
                continue
            problems, review = check_entry(e["text"], t["text"], e.get("quotes", []), lang,
                                           t.get("quote_fixes", []), t.get("reference_fixes", []))
            if bibles:
                problems += bible_text_problems(lang, t.get("quote_fixes", []), bibles)
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
    elif args[:1] in (["check"], ["fix"]):
        rv1909 = None
        if "--rv1909" in args:
            at = args.index("--rv1909")
            rv1909 = args[at + 1] if at + 1 < len(args) else sys.exit(__doc__)
            args = args[:at] + args[at + 2:]
        if len(args) not in (2, 3) or args[1] not in LANGUAGES:
            sys.exit(__doc__)
        if args[0] == "fix":
            fill_fixes(args[1], rv1909)
        else:
            check(args[1], args[2] if len(args) == 3 else None, FixBibles(rv1909))
    else:
        sys.exit(__doc__)
