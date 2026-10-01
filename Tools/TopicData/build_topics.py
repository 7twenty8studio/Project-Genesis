#!/usr/bin/env python3
"""Builds Topics.sqlite: Nave's Topical Bible as a topic index for search.

Source: NavesTopicalDictionary.csv from
https://github.com/BradyStephenson/bible-data (CC BY 4.0; Nave's Topical
Bible, 1896, is public domain). The database holds topic names, sub-topic
labels and verse ids only, never verse text: the app shows verses from its
own Bible databases.

Usage:
  git clone --depth 1 https://github.com/BradyStephenson/bible-data /tmp/bible-data
  python3 Tools/TopicData/build_topics.py --naves /tmp/bible-data/NavesTopicalDictionary.csv \\
      --bible Genesis/Resources/Bibles/KJV.sqlite --out Genesis/Resources/Study/Topics.sqlite
"""
import argparse
import csv
import os
import re
import sqlite3

USFM = (
    "GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM "
    "EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP "
    "COL 1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV"
).split()
BOOK = {code: number for number, code in enumerate(USFM, start=1)}
BOOK.update({"SOS": 22, "SON": 22, "1JHN": 62, "JDE": 65})

SMALL_WORDS = {"of", "the", "and", "in", "to", "a", "an", "for", "on", "by", "with", "at", "or", "from", "as"}
REF_START = re.compile(r"\b(" + "|".join(sorted(BOOK, key=len, reverse=True)) + r")\s+\d")
CHAPTER_REF = re.compile(r"^(\d+)(?::([\d,\-–\s]+))?$")


def verse_id(book, chapter, verse):
    return book * 1_000_000 + chapter * 1_000 + verse


def nice(text):
    """Nave's capitalises headings; show them in title case instead."""
    text = text.strip(" ,;:-")
    if not text or not text.isupper():
        return text
    words = text.lower().split()
    return " ".join(w if (i > 0 and w in SMALL_WORDS) else w[:1].upper() + w[1:] for i, w in enumerate(words))


def parse_refs(text, chapters):
    """'EXO 6:16-20; JOS 21:4,10; 1CH 6:2,3; 23:13; NUM 17' -> [(start, end)]."""
    refs = []
    book = None
    for segment in text.split(";"):
        segment = segment.strip()
        match = REF_START.search(segment)
        if match:
            book = BOOK[match.group(1)]
            segment = segment[match.end(1):].strip()
        if book is None:
            continue
        # Words between references ("with 1KI 2:8") are dropped.
        segment = re.sub(r"^[a-z][a-z ]*", "", segment).strip()
        found = CHAPTER_REF.match(segment)
        if not found:
            continue
        chapter = int(found.group(1))
        if (book, chapter) not in chapters:
            continue
        last = chapters[(book, chapter)]
        if not found.group(2):
            refs.append((verse_id(book, chapter, 1), verse_id(book, chapter, last), True))
            continue
        for part in re.split(r",", found.group(2)):
            part = part.strip()
            if not part:
                continue
            bounds = re.split(r"[-–]", part)
            try:
                start = int(bounds[0])
                end = int(bounds[-1]) if len(bounds) > 1 and bounds[-1] else start
            except ValueError:
                continue
            if end < start:
                end = start
            if start < 1 or start > last:
                continue
            refs.append((verse_id(book, chapter, start), verse_id(book, chapter, min(end, last)), False))
    # "4,5" reads better as 4-5: join references that run on.
    merged = []
    for start, end, whole in refs:
        if merged and not whole and not merged[-1][2] and start == merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], end, False)
        else:
            merged.append((start, end, whole))
    return merged


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--naves", required=True)
    parser.add_argument("--bible", required=True, help="a bundled Bible database, to check references")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    bible = sqlite3.connect(args.bible)
    chapters = {(b, c): v for b, c, v in bible.execute("SELECT book, chapter, MAX(verse) FROM verses GROUP BY book, chapter")}

    rows = list(csv.DictReader(open(args.naves, encoding="utf-8-sig")))
    topics, entries, refs, see_also = [], [], [], []
    names = {}
    for topic_id, row in enumerate(rows, start=1):
        name = row["subject"].strip()
        names[name.upper()] = topic_id
        topics.append([topic_id, name, nice(name), row["section"].strip(), 0])

    entry_id = 0
    skipped = 0
    labels = {}
    for topic_id, row in enumerate(rows, start=1):
        parents = {}
        sort = 0
        for raw in row["entry"].split("\n"):
            if not raw.strip():
                continue
            depth = (len(raw) - len(raw.lstrip(" "))) // 5
            line = raw.strip().lstrip("-").strip()
            see = re.match(r"^See (.+)$", line)
            if see:
                for target in re.split(r";", see.group(1)):
                    target = target.strip().rstrip(".").upper()
                    if target in names and names[target] != topic_id:
                        see_also.append((topic_id, names[target]))
                    elif target.split(",")[0].strip() in names:
                        see_also.append((topic_id, names[target.split(",")[0].strip()]))
                continue
            match = REF_START.search(line)
            label = line[: match.start()] if match else line
            found = parse_refs(line[match.start():], chapters) if match else []
            if match and not found:
                skipped += 1
            entry_id += 1
            sort += 1
            label = nice(label) or "General"
            # The app shows two levels; deeper headings join their parent's
            # ("Parable: Of the sower") under the top-level heading.
            if depth >= 2 and (depth - 1) in parents and 0 in parents:
                label = f"{labels[parents[depth - 1]]}: {label}"
                parent = parents[0]
            else:
                parent = parents.get(depth - 1) if depth > 0 else None
            entries.append((entry_id, topic_id, parent, sort, label))
            labels[entry_id] = label
            parents[depth] = entry_id
            for deeper in [d for d in parents if d > depth]:
                del parents[deeper]
            for index, (start, end, whole) in enumerate(found):
                refs.append((entry_id, index, start, end, int(whole)))
            topics[topic_id - 1][4] += len(found)

    if os.path.exists(args.out):
        os.remove(args.out)
    db = sqlite3.connect(args.out)
    db.executescript(
        """
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE topics (
            id INTEGER PRIMARY KEY,
            source_name TEXT NOT NULL,
            name TEXT NOT NULL,
            search_name TEXT NOT NULL,   -- lowercase name
            search_key TEXT NOT NULL,    -- lowercase without apostrophes, for search
            section TEXT NOT NULL,
            reference_count INTEGER NOT NULL
        );
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY,
            topic_id INTEGER NOT NULL,
            parent_id INTEGER,
            sort INTEGER NOT NULL,
            label TEXT NOT NULL
        );
        CREATE INDEX entries_topic ON entries(topic_id, sort);
        CREATE TABLE refs (
            entry_id INTEGER NOT NULL,
            sort INTEGER NOT NULL,
            start_verse INTEGER NOT NULL,
            end_verse INTEGER NOT NULL,
            whole_chapter INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX refs_entry ON refs(entry_id, sort);
        CREATE INDEX refs_verse ON refs(start_verse);
        CREATE TABLE see_also (topic_id INTEGER NOT NULL, target_id INTEGER NOT NULL);
        CREATE INDEX see_also_topic ON see_also(topic_id);
        CREATE INDEX topics_search ON topics(search_key);
        """
    )
    db.executemany("INSERT INTO meta VALUES (?, ?)", [
        ("source", "Nave's Topical Bible (1896, public domain), via BibleData by Brady Stephenson (CC BY 4.0), github.com/BradyStephenson/bible-data"),
        ("schema_version", "1"),
    ])
    db.executemany("INSERT INTO topics VALUES (?,?,?,?,?,?,?)", [(t[0], t[1], t[2], t[2].lower(), t[2].lower().replace("'", "").replace("\u2019", ""), t[3], t[4]) for t in topics])
    db.executemany("INSERT INTO entries VALUES (?,?,?,?,?)", entries)
    db.executemany("INSERT INTO refs VALUES (?,?,?,?,?)", refs)
    db.executemany("INSERT INTO see_also VALUES (?,?)", sorted(set(see_also)))
    db.commit()
    db.execute("VACUUM")
    db.close()
    print(f"Topics: {len(topics)}, entries: {len(entries)}, references: {len(refs)}, see-also: {len(set(see_also))}, entries with unreadable refs: {skipped}")


if __name__ == "__main__":
    main()
