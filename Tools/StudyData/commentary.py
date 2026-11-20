#!/usr/bin/env python3
"""Matthew Henry's Concise Commentary, translated in batches (VRS-8 part 4b).

    python3 Tools/StudyData/commentary.py export RV1909.sqlite  # source batches from WordStudy.sqlite
    python3 Tools/StudyData/commentary.py status
    python3 Tools/StudyData/commentary.py check es 007          # one batch
    python3 Tools/StudyData/commentary.py check pt
    python3 Tools/StudyData/commentary.py verse es "Col 3:18-19"  # a verse's RV1909 / Bíblia Livre text

Source batches (translations/commentary/source/NNN.json) hold, in Bible
order, each book's introduction (kind "intro", id = book 1-66) before the
book's sections (kind "section", id = commentary.id): the passage it
comments on, the SHA-256 of its English, its title (Henry's outline
heading, if any) and text, the names glossary (bios.py) and `quotes`: the
runs of KJV words Henry works into his sentences, unmarked, as he does
(five or more words of the passage he's on, four of a verse he cites
beside them, seven of any verse), each with the verses and their
RV1909 / Bíblia Livre text. Batches are stable: export again keeps every
entry in its batch, refreshes changed texts (their translations then show
as stale) and puts new entries in new batches.

Translations live in translations/commentary/<lang>/NNN.json:

    {"batch": "007", "lang": "es", "entries": [
        {"kind": "section", "id": 12, "sha256": "<source sha>", "title": "…",
         "text": "…",
         "quotes": [{"n": 0, "text": "<the RV1909 / Bíblia Livre words used>"},
                    {"n": 1, "mode": "translated", "reason": "…"}],
         "flags": ["Henry's point rests on the KJV's word “…”"],
         "note": "…"}]}

Every source quote needs an answer: the target Bible's words used in the
translation ("text", checked verbatim against those verses and found in
the translation), or "mode": "translated" with a reason (the words don't
fit Henry's sentence, or he's not quoting). `flags` are wording-dependent
explanations (Henry explaining an English word of the KJV) and anything
else a reviewer should see. Every quote, flag and note goes to
translations/commentary/<lang>/review/NNN.md.

The check, run after each batch: every entry present with the source's
sha; a title exactly where the English has one; the same paragraphs; every
number; the same Bible references, book, chapter and verse, in order
(refs.py, with Henry's abbreviations below); every quote answered and
verbatim; no English left; a sensible length.
add_commentary_translations.py uses only entries that pass.
"""
import json
import os
import re
import sqlite3
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bios  # noqa: E402
import refs  # noqa: E402
import scripture_quotes as sq  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
WORDSTUDY = os.path.join(ROOT, "Genesis", "Resources", "Study", "WordStudy.sqlite")
OUT = os.path.join(HERE, "translations", "commentary")
SOURCE = os.path.join(OUT, "source")
LANGUAGES = ("es", "pt")
BATCH_WORDS = 7000
NUMBER = re.compile(r"\d+")
# Henry now and then writes "I Kin. 11:1": a translation's "1 R 11:1" is the same number.
ROMAN_BOOK = re.compile(r"\b(III|II|I) (?=(?:Kin|Ki|Sam|Sa|Chr|Ch|Cor|Co|Tim|Ti|Pet|Pe|Joh|Jo|Jn|Thes|Th)[a-z]*\b\.?)")


def _roman(m):
    return f"{len(m.group(1))} "

# Henry's (the SWORD module's) abbreviations that refs.py's table lacks.
# "Jud" is Jude in Jude and Judges elsewhere (`english_references`).
HENRY_BOOKS = {
    "Ge": "Gen", "Le": "Lev", "Nu": "Num", "De": "Deut", "Jos": "Josh", "Jdg": "Judg",
    "1Sa": "1Sam", "2Sa": "2Sam", "1Ki": "1Kings", "2Ki": "2Kings", "I Kin": "1Kings",
    "II Kin": "2Kings", "1Ch": "1Chr", "2Ch": "2Chr", "Ezr": "Ezra", "Psa": "Ps", "Pr": "Prov",
    "Ec": "Eccl", "Song": "Cant", "So": "Cant", "Is": "Isa", "Jr": "Jer", "La": "Lam",
    "Eze": "Ezek", "Dn": "Dan", "Da": "Dan", "Ho": "Hos", "Am": "Amos", "Mi": "Micah",
    "Ha": "Hab", "Zep": "Zeph", "Zec": "Zech", "Mt": "Matt", "Mr": "Mark", "Lu": "Luke",
    "Joh": "John", "Ac": "Acts", "Ro": "Rom", "1Co": "1Cor", "2Co": "2Cor", "Ga": "Gal",
    "Ep": "Eph", "Php": "Phil", "2Th": "2Thess", "1Ti": "1Tim", "2Ti": "2Tim", "Tit": "Titus",
    "He": "Heb", "Jas": "James", "1Pe": "1Pet", "2Pe": "2Pet", "I Pet": "1Pet", "II Pet": "2Pet",
    "1Jo": "1John", "2Jo": "2John", "3Jo": "3John", "Re": "Rev", "Judg": "Judg", "Jude": "Jude",
}
refs.NAMES["henry"] = {**refs.NAMES["en"], **HENRY_BOOKS}


def english_references(text, book):
    """refs.py references in Henry's English; `book` (1-66) settles "Jud"."""
    text = re.sub(r"(?<![\w-])Jud(?= \d+:)", "Jude" if book == 65 else "Judg", text)
    return refs.references(text, "henry")


# MARK: Source

def source_fixes():
    """{section id: [(old, new)]} from translations/commentary/source_fixes.json."""
    path = os.path.join(OUT, "source_fixes.json")
    fixes = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            for f in json.load(handle)["fixes"]:
                fixes.setdefault(f["id"], []).append((f["old"], f["new"]))
    return fixes


def fix_text(cid, text, fixes=None):
    """A section's English with its source fixes applied (once; fixed text is left)."""
    for old, new in (fixes if fixes is not None else source_fixes()).get(cid, []):
        if old in text:
            assert text.count(old) == 1, (cid, old)
            text = text.replace(old, new)
    return text


def fix_database(path=None):
    """Writes the source fixes into WordStudy.sqlite's commentary (idempotent),
    so English readers get the same text; returns the changed section count."""
    fixes = source_fixes()
    db = sqlite3.connect(path or WORDSTUDY)
    changed = 0
    for cid in fixes:
        row = db.execute("SELECT text FROM commentary WHERE id = ? AND source = 'mhcc'", (cid,)).fetchone()
        if row and fix_text(cid, row[0], fixes) != row[0]:
            db.execute("UPDATE commentary SET text = ? WHERE id = ?", (fix_text(cid, row[0], fixes), cid))
            changed += 1
    db.commit()
    db.close()
    return changed


def source_entries():
    """[(kind, id, book, start, end, title, text)] in Bible order."""
    db = sqlite3.connect(WORDSTUDY)
    intros = {b: t for b, t in db.execute("SELECT book, text FROM introductions WHERE source = 'mhcc'")}
    out, seen = [], set()
    for cid, start, end, title, text in db.execute(
            "SELECT id, start_verse, end_verse, title, text FROM commentary WHERE source = 'mhcc' ORDER BY start_verse, id"):
        book = start // 1_000_000
        if book in intros and book not in seen:
            seen.add(book)
            out.append(("intro", book, book, None, None, None, intros[book]))
        out.append(("section", cid, book, start, end, title, text))
    for book in sorted(set(intros) - seen):
        out.append(("intro", book, book, None, None, None, intros[book]))
    db.close()
    return out


def sha(title, text):
    return bios.sha((title or "") + "\x1f" + text)


class QuoteFinder:
    """Runs of KJV words in Henry's text (he weaves them in unmarked)."""
    PASSAGE, CITED, ANYWHERE = 5, 4, 7
    # Words a run of KJV words doesn't start or end on ("…, and").
    LEAD = {"and", "but", "for", "that", "or", "so"}
    TRAIL = {"and", "or", "of", "to", "the", "a", "an", "that", "for", "in", "with", "but", "which", "by", "as", "is", "be", "his", "their", "our", "my", "thy"}

    def __init__(self, bibles: sq.Bibles):
        self.b = bibles
        self.index = {}
        for v in bibles.order:
            w = bibles.normed[v].split()
            for i in range(len(w) - self.ANYWHERE + 1):
                self.index.setdefault(" ".join(w[i:i + self.ANYWHERE]), set()).add(v)

    def _ids(self, q, pool):
        """The shortest run of verses (from `pool` starts) holding q."""
        best = None
        for v in pool:
            found = self.b._at(q, v)
            if found and (best is None or len(found[0]) < len(best)):
                best = found[0]
        return best

    def _around(self, verses, before=1, after=2):
        out = []
        for v in verses:
            if v in self.b.position:
                n = self.b.position[v]
                out += [i for i in self.b.order[max(0, n - before): n + after + 1] if i not in out]
        return out

    def find(self, text, book, start=None, end=None):
        tokens = [(m.start(), m.end(), sq.norm(m.group(0))) for m in re.finditer(r"[A-Za-z0-9]+(?:'[A-Za-z]+)?", text)]
        tokens = [t for t in tokens if t[2]]
        words = [t[2] for t in tokens]
        passage = [v for v in self.b.order if start is not None and start <= v <= end]
        joined = " " + " ".join(self.b.normed[v] for v in passage) + " "
        ref_at = self._ref_offsets(text, book)
        out, i = [], 0
        while i < len(words):
            near = [r for off, r in ref_at if tokens[i][0] - 200 <= off <= tokens[i][1] + 250]
            pools = []
            if passage:
                pools.append((self.PASSAGE, passage, joined))
            if near:
                cited = self._around(near)
                pools.append((self.CITED, cited, " " + " ".join(self.b.normed[v] for v in cited) + " "))
            key = " ".join(words[i:i + self.ANYWHERE])
            if key in self.index:
                anywhere = self._around(sorted(self.index[key]), before=0, after=0)
                pools.append((self.ANYWHERE, anywhere, None))
            best = None
            for minimum, pool, flat in pools:
                j = i + minimum
                if j > len(words):
                    continue
                if flat is not None and f" {' '.join(words[i:j])} " not in flat:
                    continue
                starts = self._around(pool, before=3, after=0)
                ids = self._ids(" ".join(words[i:j]), starts)
                if not ids:
                    continue
                while j < len(words):
                    longer = self._ids(" ".join(words[i:j + 1]), starts)
                    if not longer:
                        break
                    ids, j = longer, j + 1
                if best is None or j > best[0]:
                    best = (j, ids, minimum)
            if not best:
                i += 1
                continue
            j, ids, minimum = best
            k = i
            while k < j and words[k] in self.LEAD:
                k += 1
            while j > k and words[j - 1] in self.TRAIL:
                j -= 1
            if j - k >= minimum and sum(len(w) > 3 for w in words[k:j]) >= 2:
                out.append({"n": len(out), "english": text[tokens[k][0]:tokens[j - 1][1]], "verses": ids,
                            "es": self.b.target("es", ids), "pt": self.b.target("pt", ids)})
            i = best[0]
        return out

    def _ref_offsets(self, text, book):
        """(offset, verse id) of each reference, for the cited-verse pool."""
        text = re.sub(r"(?<![\w-])Jud(?= \d+:)", "Jude" if book == 65 else "Judg", text)
        out = []
        for m in refs._pattern("henry").finditer(text):
            if m.group(1):
                code = refs._code("henry", m.group(1))
                if code in sq.BOOKS:
                    out.append((m.start(), (sq.BOOKS.index(code) + 1) * 1_000_000 + int(m.group(2)) * 1000 + int(m.group(3))))
            else:
                out.append((m.start(), book * 1_000_000 + int(m.group(4)) * 1000 + int(m.group(5))))
        return out


def export(rv1909):
    finder = QuoteFinder(sq.Bibles(rv1909))
    maps = bios.name_maps()
    entries = {}
    for kind, eid, book, start, end, title, text in source_entries():
        e = {"kind": kind, "id": eid, "book": book}
        if kind == "section":
            e["start_verse"], e["end_verse"] = start, end
        e["sha256"] = sha(title, text)
        if title:
            e["title"] = title
        e["text"] = text
        entries[(kind, eid)] = e
    placed, existing = {}, {}
    for b in batches():
        data = bios.load(os.path.join(SOURCE, f"{b}.json"))
        existing[b] = data
        for e in data["entries"]:
            placed[(e["kind"], e["id"])] = b

    def full(key, old=None):
        e = entries[key]
        if old and old.get("sha256") == e["sha256"] and "quotes" in old:
            return old
        e["quotes"] = finder.find(e["text"], e["book"], e.get("start_verse"), e.get("end_verse"))
        return e

    def save(b, items):
        texts = [(i.get("title") or "") + "\n" + i["text"] for i in items]
        joined = "\n".join(texts)
        # Names that are also English words here ("Sin", "So") would mislead.
        names = {k: v for k, v in bios.glossary(texts, maps).items()
                 if not re.search(rf"(?<![\w-]){re.escape(k.lower())}(?![\w-])", joined)}
        bios.save(os.path.join(SOURCE, f"{b}.json"), {"batch": b, "entries": items, "glossary": names})

    for b, data in existing.items():
        save(b, [full((e["kind"], e["id"]), e) for e in data["entries"] if (e["kind"], e["id"]) in entries])
    number, current, count = len(existing), [], 0
    for key, e in entries.items():
        if key in placed:
            continue
        n = len(e["text"].split()) + len((e.get("title") or "").split())
        if current and count + n > BATCH_WORDS:
            number += 1
            save(f"{number:03d}", current)
            print(f"batch {number:03d}", flush=True)
            current, count = [], 0
        current.append(full(key))
        count += n
    if current:
        number += 1
        save(f"{number:03d}", current)
    print(f"{number} batches, {len(entries)} entries in {SOURCE}")


def batches():
    if not os.path.isdir(SOURCE):
        return []
    return sorted(n[:-5] for n in os.listdir(SOURCE) if n.endswith(".json"))


# MARK: Check

def check_quotes(entry, t, lang):
    problems, review = [], []
    answers = {q.get("n"): q for q in t.get("quotes", [])}
    text = t.get("text", "")
    flat = " ".join(text.split())
    for q in entry.get("quotes", []):
        a = answers.pop(q["n"], None)
        ref = ", ".join(f"{sq.BOOKS[v // 1_000_000 - 1]} {v // 1000 % 1000}:{v % 1000}" for v in q["verses"])
        if a is None:
            problems.append(f"quote {q['n']} (“{q['english'][:40]}”) not answered")
            continue
        if a.get("mode") == "translated":
            if not a.get("reason", "").strip():
                problems.append(f"quote {q['n']}: translated needs a reason")
            review.append(f"- translated, not quoted ({ref}; {a.get('reason', '')}): “{q['english']}”")
            continue
        used = " ".join((a.get("text") or "").split())
        pieces = [p for p in re.split(r"\s*(?:…|\.\.\.)\s*", used) if p.strip(" ,.;:!?¡¿")]
        if not pieces:
            problems.append(f"quote {q['n']}: give the words used (text) or mode translated")
            continue
        bible = q[lang]
        if not all(bios.verbatim(p, bible) for p in pieces):
            problems.append(f"quote {q['n']}: “{used[:50]}” isn't the words of {ref} verbatim")
        elif sum(len(p.split()) for p in pieces) < 2:
            problems.append(f"quote {q['n']}: too few of the verse's words")
        for p in pieces:
            p = p.strip(" ,.;:!?¡¿")
            if p not in flat and (p[0].swapcase() + p[1:]) not in flat:
                problems.append(f"quote {q['n']}: “{p[:50]}” isn't in the translation")
        review.append(f"- quoted ({ref}): “{q['english']}” → “{used}”")
    for n in answers:
        problems.append(f"quote {n}: not in the source")
    return problems, review


def quoted(t):
    """The Bible's words a passing translation quotes (its verbatim answers),
    each run as it stands in the text, for the app to set in italics."""
    out = []
    for a in t.get("quotes", []):
        if a.get("mode") == "translated":
            continue
        for p in re.split(r"\s*(?:…|\.\.\.)\s*", " ".join((a.get("text") or "").split())):
            p = p.strip(" ,.;:!?¡¿")
            if p and p not in out:
                out.append(p)
    return out


def check_text(source, text, lang, book, long=True):
    problems = []
    if not text.strip():
        return ["empty"]
    if source.count("\n\n") != text.count("\n\n") or source.count("\n") != text.count("\n"):
        problems.append(f"paragraphs {source.count(chr(10) * 2) + 1} -> {text.count(chr(10) * 2) + 1}")
    a, b = Counter(NUMBER.findall(ROMAN_BOOK.sub(_roman, source))), Counter(NUMBER.findall(text))
    if a != b:
        problems.append(f"numbers differ (missing {list((a - b).elements())[:8]}, extra {list((b - a).elements())[:8]})")
    want, have = english_references(source, book), refs.references(text, lang)
    if want != have:
        missing = list((Counter(want) - Counter(have)).elements())
        extra = list((Counter(have) - Counter(want)).elements())
        problems.append(f"references differ (missing {[refs.label(r) for r in missing[:6]]}, extra {[refs.label(r) for r in extra[:6]]})"
                        if missing or extra else "references in another order")
    count = max(1, len(text.split()))
    english = len(bios.ENGLISH.findall(text))
    if (english / count > 0.03 and english > 2) or (not long and english > 1):
        problems.append(f"looks untranslated ({english} English words)")
    ratio = len(text) / max(1, len(source))
    if long and len(source) > 200 and not 0.8 <= ratio <= 1.7:
        problems.append(f"length {ratio:.2f}x the English")
    return problems


def check_entry(entry, t, lang):
    problems, review = [], []
    if bool(entry.get("title")) != bool(t.get("title")):
        problems.append("title: " + ("missing" if entry.get("title") else "not in the English"))
    elif entry.get("title"):
        problems += [f"title: {p}" for p in check_text(entry["title"], t["title"], lang, entry["book"], long=False)]
    problems += check_text(entry["text"], t.get("text", ""), lang, entry["book"])
    p, r = check_quotes(entry, t, lang)
    problems += p
    review += r
    for flag in t.get("flags", []):
        review.append(f"- flag: {flag}")
    if t.get("note"):
        review.append(f"- note: {t['note']}")
    return problems, review


def label(entry):
    if entry["kind"] == "intro":
        return f"intro {sq.BOOKS[entry['id'] - 1]}"
    s, e = entry["start_verse"], entry["end_verse"]
    return f"{entry['id']} {sq.BOOKS[s // 1_000_000 - 1]} {s // 1000 % 1000}:{s % 1000}-{e % 1000}"


def check(lang, only=None, quiet=False):
    """Prints problems; returns {(kind, id): (title, text, quotations)} of entries that pass."""
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
        done = {(e.get("kind"), e.get("id")): e for e in bios.load(path)["entries"]}
        keys = {(e["kind"], e["id"]) for e in src["entries"]}
        reviews = []
        for entry in src["entries"]:
            key = (entry["kind"], entry["id"])
            t = done.get(key)
            name = f"{lang} {b} {label(entry)}"
            if t is None:
                if not quiet:
                    print(f"{name}: missing")
                missing += 1
                continue
            if t.get("sha256") != entry["sha256"]:
                print(f"{name}: stale (English changed)")
                failed += 1
                continue
            problems, review = check_entry(entry, t, lang)
            if problems:
                print(f"{name}: " + "; ".join(problems))
                failed += 1
            else:
                passed[key] = (t.get("title"), t["text"], quoted(t))
                if review:
                    reviews.append(f"### {label(entry)} {entry.get('title') or ''}\n" + "\n".join(review))
        write_review(lang, b, reviews)
        for key in sorted(set(done) - keys, key=str):
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
        f.write(f"# To review: {lang} commentary batch {b}\n\n")
        f.write("\n\n".join(reviews) + "\n")


def status():
    total = sum(len(bios.load(os.path.join(SOURCE, f"{b}.json"))["entries"]) for b in batches())
    print(f"{len(batches())} batches, {total} entries")
    for lang in LANGUAGES:
        done = [b for b in batches() if os.path.exists(os.path.join(OUT, lang, f"{b}.json"))]
        print(f"{lang}: {len(done)} batches translated: {' '.join(done) or '-'}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["export"] and len(args) == 2:
        export(args[1])
    elif args[:1] == ["verse"] and len(args) == 3 and args[1] in LANGUAGES:
        # The RV1909 isn't bundled: --rv1909 is GENESIS_RV1909 (bios.FixBibles).
        print(bios.FixBibles().text(args[1], args[2]))
    elif args[:1] == ["status"]:
        status()
    elif args[:1] == ["check"] and len(args) in (2, 3) and args[1] in LANGUAGES:
        check(args[1], args[2] if len(args) == 3 else None)
    else:
        sys.exit(__doc__)
