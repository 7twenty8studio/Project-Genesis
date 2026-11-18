#!/usr/bin/env python3
"""Nave's topic names and headings, translated in batches (VRS-8 part 3).

    python3 Tools/TopicData/naves.py export RV1909.sqlite  # source batches from Topics.sqlite
    python3 Tools/TopicData/naves.py status
    python3 Tools/TopicData/naves.py check es 007          # one batch
    python3 Tools/TopicData/naves.py check pt [--rv1909 RV1909.sqlite]
    python3 Tools/TopicData/naves.py fix es --rv1909 RV1909.sqlite

Source batches (translations/source/NNN.json) hold whole topics in id
order: each topic's name and every heading (entry) under it, each with
its id and the SHA-256 of its English, plus the quotations in it
("…" in Nave's; whether they're Scripture and the RV1909 / Bíblia Livre
words to quote, found from the entry's own verses), a glossary of the
people and places named (as the app spells them, from Study's
translations) and the fixed phrases (translations/phrases.json). Batches
are stable: running export again keeps every topic in its batch, refreshes
changed texts (their translations then show as stale) and puts new topics
in new batches.

Translations live in translations/<lang>/NNN.json:

    {"batch": "007", "lang": "es", "items": [
        {"kind": "topic", "id": 12, "sha256": "<source sha>", "text": "…"},
        {"kind": "entry", "id": 301, "sha256": "…", "text": "…"}]}

The check is Easton's (Tools/StudyData/bios.py, the same rules and the
same quote_fixes / reference_fixes corrections): every item present with
the source's sha, every number, the same Bible references (book, chapter
and verse, in order), the same quotations, Scripture quoted verbatim from
the RV1909 / Bíblia Livre, no English left. Here also: a heading that is a
fixed phrase ("General scriptures concerning") uses the phrase's
translation, and a topic named after one person or place uses the app's
spelling (or says why not in "name_note"). add_topic_translations.py uses
only items that pass. Partial, loose, KJV-wording and fixed quotations go
to translations/<lang>/review/NNN.md.
"""
import hashlib
import json
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "Tools", "StudyData"))
import bios  # noqa: E402
import scripture_quotes  # noqa: E402

TOPICS = os.path.join(ROOT, "Genesis", "Resources", "Study", "Topics.sqlite")
OUT = os.path.join(HERE, "translations")
SOURCE = os.path.join(OUT, "source")
PHRASES = os.path.join(OUT, "phrases.json")
LANGUAGES = ("es", "pt")
BATCH_WORDS = 5000
STRAIGHT = re.compile(r'"([^"]*)"')


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def curly(text):
    """Nave's straight quotation marks as “ ”, so bios.py's quote checks apply."""
    return STRAIGHT.sub(lambda m: f"“{m.group(1)}”", text)


def batches():
    if not os.path.isdir(SOURCE):
        return []
    return sorted(n[:-5] for n in os.listdir(SOURCE) if n.endswith(".json"))


def phrases():
    return bios.load(PHRASES) if os.path.exists(PHRASES) else {}


def topics_from_db():
    """{topic id: (name, [(entry id, parent id, label, [verse ids])])} in sort order."""
    db = sqlite3.connect(TOPICS)
    verses = {}
    for entry, start, end in db.execute("SELECT entry_id, start_verse, end_verse FROM refs ORDER BY entry_id, sort"):
        # The first few verses of each passage are enough to find a quotation.
        verses.setdefault(entry, []).extend(range(start, min(end, start + 3) + 1))
    topics = {}
    for tid, name in db.execute("SELECT id, name FROM topics ORDER BY id"):
        topics[tid] = (name, [])
    for eid, tid, parent, label in db.execute("SELECT id, topic_id, parent_id, label FROM entries ORDER BY topic_id, sort"):
        topics[tid][1].append((eid, parent, label, verses.get(eid, [])))
    db.close()
    return topics


# MARK: Export

def export(rv1909):
    bibles = scripture_quotes.Bibles(rv1909)
    maps = bios.name_maps()
    fixed = phrases()
    topics = topics_from_db()

    def quotes(text, hints):
        out = []
        for n, m in enumerate(STRAIGHT.finditer(text)):
            kind, ids = bibles.find(m.group(1), hints)
            q = {"n": n, "english": m.group(1), "kind": kind}
            if ids:
                q.update(verses=ids, es=bibles.target("es", ids), pt=bibles.target("pt", ids))
            out.append(q)
        return out

    def items(tid):
        name, entries = topics[tid]
        out = [{"kind": "topic", "id": tid, "sha256": sha(name), "text": name}]
        labels = {eid: label for eid, _, label, _ in entries}
        for eid, parent, label, verses in entries:
            item = {"kind": "entry", "id": eid, "topic": tid, "sha256": sha(label), "text": label}
            if parent:
                item["under"] = labels.get(parent, "")
            q = quotes(label, verses)
            if q:
                item["quotes"] = q
            out.append(item)
        return out

    def batch(b, tids):
        listed = [i for t in tids for i in items(t)]
        joined = "\n".join(i["text"] for i in listed)
        used = {k: v for k, v in fixed.items() if any(i["kind"] == "entry" and i["text"] == k for i in listed)}
        data = {"batch": b, "topics": tids, "items": listed,
                "glossary": bios.glossary([joined], maps), "phrases": used}
        bios.save(os.path.join(SOURCE, f"{b}.json"), data)

    placed = {}
    for b in batches():
        for t in bios.load(os.path.join(SOURCE, f"{b}.json"))["topics"]:
            placed[t] = b
    existing = sorted(set(placed.values()))
    for b in existing:
        batch(b, [t for t, pb in placed.items() if pb == b and t in topics])
    number, current, words = len(existing), [], 0
    for tid in topics:
        if tid in placed:
            continue
        name, entries = topics[tid]
        n = len(name.split()) + sum(len(label.split()) for _, _, label, _ in entries)
        if current and words + n > BATCH_WORDS:
            number += 1
            batch(f"{number:03d}", current)
            current, words = [], 0
        current.append(tid)
        words += n
    if current:
        number += 1
        batch(f"{number:03d}", current)
    print(f"{number} batches in {SOURCE}")


# MARK: Check

def check_item(lang, item, t, fixed, glossary):
    """(problems, review lines) for one translated item."""
    source, text = curly(item["text"]), curly(t.get("text", ""))
    problems, review = bios.check_entry(source, text, item.get("quotes", []), lang,
                                        t.get("quote_fixes", []), t.get("reference_fixes", []))
    if t.get("text") == item["text"] and re.search(r"(?<![\w-])[a-z]{3,}", item["text"]):
        problems.append("not translated")
    if item["kind"] == "entry" and item["text"] in fixed:
        want = fixed[item["text"]][lang]
        if t["text"] != want and not t.get("phrase_note"):
            problems.append(f"fixed phrase: “{item['text']}” is “{want}”")
    if item["kind"] == "topic":
        local = glossary.get(item["text"], {}).get(lang)
        if local and "; " not in local and t["text"] != local and not t.get("name_note"):
            problems.append(f"the app calls {item['text']} “{local}” (or give a name_note)")
    for key in ("phrase_note", "name_note"):
        if t.get(key):
            review.append(f"- {key.replace('_', ' ')}: {t[key]}")
    return problems, review


def check(lang, only=None, bibles=None):
    """Prints problems; returns {(kind, id): text} of items that pass."""
    passed, failed, missing = {}, 0, 0
    fixed = phrases()
    for b in batches():
        if only and b != only:
            continue
        src = bios.load(os.path.join(SOURCE, f"{b}.json"))
        path = os.path.join(OUT, lang, f"{b}.json")
        if not os.path.exists(path):
            missing += len(src["items"])
            if only:
                print(f"{lang} {b}: not translated yet")
            continue
        done = {(i["kind"], i["id"]): i for i in bios.load(path)["items"]}
        reviews = []
        for item in src["items"]:
            key = (item["kind"], item["id"])
            t = done.get(key)
            label = f"{lang} {b} {item['kind']} {item['id']} “{item['text'][:50]}”"
            if t is None:
                print(f"{label}: missing")
                missing += 1
                continue
            if t.get("sha256") != item["sha256"]:
                print(f"{label}: stale (English changed)")
                failed += 1
                continue
            problems, review = check_item(lang, item, t, fixed, src.get("glossary", {}))
            if bibles:
                problems += bios.bible_text_problems(lang, t.get("quote_fixes", []), bibles)
            if problems:
                print(f"{label}: " + "; ".join(problems))
                failed += 1
            else:
                passed[key] = t["text"]
                if review:
                    reviews.append(f"### {item['text']} ({item['kind']} {item['id']})\n" + "\n".join(review))
        write_review(lang, b, reviews)
        for kind, iid in sorted(set(done) - {(i["kind"], i["id"]) for i in src["items"]}):
            print(f"{lang} {b} {kind} {iid}: not in this batch")
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
        f.write(f"# To review: {lang} batch {b}\n\n")
        f.write("Partial and loose quotations use the Bible's words verbatim; wording ones are Nave's quoting a KJV rendering; unsure ones were found in a verse the heading doesn't list and were translated; fixes and notes say why.\n\n")
        f.write("\n\n".join(reviews) + "\n")


def fill_fixes(lang, rv1909=None):
    bibles = bios.FixBibles(rv1909)
    if not bibles.has(lang):
        sys.exit(f"{lang}: the Bible isn't at hand (pass --rv1909 PATH)")
    changed = 0
    for b in batches():
        path = os.path.join(OUT, lang, f"{b}.json")
        if not os.path.exists(path):
            continue
        data = bios.load(path)
        touched = False
        for i in data["items"]:
            for fix in i.get("quote_fixes", []):
                if fix.get("mode") == "verbatim" and fix.get("reference"):
                    text = bibles.text(lang, fix["reference"])
                    if fix.get("bible") != text:
                        fix["bible"], touched = text, True
                        changed += 1
        if touched:
            bios.save(path, data)
    print(f"{lang}: {changed} quote fixes given their Bible text")


def status():
    total = sum(len(bios.load(os.path.join(SOURCE, f"{b}.json"))["items"]) for b in batches())
    print(f"{len(batches())} batches, {total} items")
    for lang in LANGUAGES:
        done = [b for b in batches() if os.path.exists(os.path.join(OUT, lang, f"{b}.json"))]
        print(f"{lang}: {len(done)} batches translated: {' '.join(done) or '-'}")


if __name__ == "__main__":
    args = sys.argv[1:]
    rv1909 = None
    if "--rv1909" in args:
        at = args.index("--rv1909")
        rv1909 = args[at + 1] if at + 1 < len(args) else sys.exit(__doc__)
        args = args[:at] + args[at + 2:]
    if args[:1] == ["export"] and len(args) == 2:
        export(args[1])
    elif args[:1] == ["status"]:
        status()
    elif args[:1] == ["fix"] and len(args) == 2 and args[1] in LANGUAGES:
        fill_fixes(args[1], rv1909)
    elif args[:1] == ["check"] and len(args) in (2, 3) and args[1] in LANGUAGES:
        check(args[1], args[2] if len(args) == 3 else None, bios.FixBibles(rv1909))
    else:
        sys.exit(__doc__)
