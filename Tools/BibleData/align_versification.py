#!/usr/bin/env python3
"""Writes Genesis/Core/Study/VersificationTables.swift: where a downloadable
Bible numbers its verses differently from the KJV, which KJV verses each of
its verses holds. The Original parallel Bible (Hebrew and Greek from
WordStudy.sqlite, keyed by KJV verse ids) uses it to line the original text
up with the Bible being read.

Only the Reina-Valera 1909 needs a table today (KJV and ASV share the KJV's
numbering; the WEB's one difference, the Romans doxology, is written by hand
in OriginalVersification.swift). Its file (open-bibles' USFX, with Spanish
numbering) is built by package_translation.py:

  python3 -I Tools/BibleData/align_versification.py build/bibles/RV1909-1.sqlite

How: within each book, KJV and RV1909 verses are aligned by length
(Gale-Church dynamic programming: one verse to one, two to one, one to
several...), since a Spanish verse's length follows its English one closely.
Every stretch it reports was then read side by side; the DP misreads Job
38:37-40:24, where the RV1909 joins nine KJV verses into 39:30, so that
stretch is written out below (MANUAL). Re-read any new stretch it reports
before shipping. Reads verse ids and text lengths only; writes no text.
"""
import math
import os
import sqlite3
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KJV = os.path.join(ROOT, "Genesis", "Resources", "Bibles", "KJV.sqlite")
OUTPUT = os.path.join(ROOT, "Genesis", "Core", "Study", "VersificationTables.swift")


def vid(book, chapter, verse):
    return book * 1_000_000 + chapter * 1_000 + verse


# Checked by hand: Job 38:37 to 40:24 (RV1909 numbering -> KJV).
MANUAL_BOOK = 18
MANUAL = (
    [([vid(18, 38, v)], [vid(18, 38, v)]) for v in (37, 38)]
    + [([vid(18, 39, v)], [vid(18, 38, v + 38)]) for v in range(1, 4)]
    + [([vid(18, 39, v)], [vid(18, 39, v - 3)]) for v in range(4, 30)]
    + [([vid(18, 39, 30)], [vid(18, 39, v) for v in range(27, 31)] + [vid(18, 40, v) for v in range(1, 6)])]
    + [([vid(18, 40, v)], [vid(18, 40, v + 5)]) for v in range(1, 20)]
)
MANUAL_RV = {v for group in MANUAL for v in group[0]}
MANUAL_KJV = {v for group in MANUAL for v in group[1]}


def norm_cdf(x):
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def align(first, second, ratio, variance=6.8):
    """Gale-Church alignment of two lists of (id, length)."""
    def cost(a, b):
        if a == 0 and b == 0:
            return 0
        mean = max((a + b / ratio) / 2, 1)
        delta = (a * ratio - b) / math.sqrt(mean * variance)
        return -math.log(max(2 * (1 - norm_cdf(abs(delta))), 1e-12))

    priors = {(1, 1): 0, (1, 2): -math.log(0.05), (2, 1): -math.log(0.05), (2, 2): -math.log(0.0124),
              (1, 0): -math.log(0.005), (0, 1): -math.log(0.005)}
    priors.update({(1, k): 4 + 1.5 * k for k in range(3, 10)})
    priors.update({(k, 1): 4 + 1.5 * k for k in range(3, 6)})
    n, m = len(first), len(second)
    inf = float("inf")
    best = [[inf] * (m + 1) for _ in range(n + 1)]
    step = [[None] * (m + 1) for _ in range(n + 1)]
    best[0][0] = 0
    band = max(60, abs(n - m) + 40)
    for i in range(n + 1):
        centre = i * m // max(n, 1)
        for j in range(max(0, centre - band), min(m, centre + band) + 1):
            for (a, b), prior in priors.items():
                if i >= a and j >= b and best[i - a][j - b] < inf:
                    total = best[i - a][j - b] + prior + cost(
                        sum(x[1] for x in first[i - a:i]), sum(x[1] for x in second[j - b:j]))
                    if total < best[i][j]:
                        best[i][j], step[i][j] = total, (a, b)
    i, j, groups = n, m, []
    while i > 0 or j > 0:
        a, b = step[i][j]
        groups.append(([x[0] for x in second[j - b:j]], [x[0] for x in first[i - a:i]]))
        i, j = i - a, j - b
    return groups[::-1]


def groups_for(bible_path):
    kjv, other = sqlite3.connect(f"file:{KJV}?mode=ro", uri=True), sqlite3.connect(f"file:{bible_path}?mode=ro", uri=True)
    total = lambda db: sum(length for (length,) in db.execute("SELECT length(text) FROM verses"))
    ratio = total(other) / total(kjv)
    found = []
    for book in range(1, 67):
        rows = lambda db: list(db.execute("SELECT id, length(text) FROM verses WHERE book = ? ORDER BY id", (book,)))
        for verses, kjv_verses in align(rows(kjv), rows(other), ratio):
            if book == MANUAL_BOOK and (set(verses) & MANUAL_RV or set(kjv_verses) & MANUAL_KJV):
                continue
            if verses == kjv_verses and len(verses) == 1:
                continue
            found.append((verses, kjv_verses))
    found.extend(MANUAL)
    found = [g for g in found if not (len(g[0]) == 1 and g[0] == g[1])]
    found.sort(key=lambda g: (g[0] or g[1])[0])
    return found


def swift_lines(groups):
    """Runs of one verse to one verse with the same offset become `shift`s."""
    lines, run = [], []

    def flush():
        if not run:
            return
        (v0, k0), (v1, _) = run[0], run[-1]
        b, c, kc = v0 // 1_000_000, v0 // 1000 % 1000, k0 // 1000 % 1000
        offset = k0 % 1000 - v0 % 1000
        lines.append(f"shift(book: {b}, chapter: {c}, verses: {v0 % 1000}...{v1 % 1000}, kjvChapter: {kc}, by: {offset})")
        run.clear()

    def pairs(ids):
        return ", ".join(f"({i // 1000 % 1000}, {i % 1000})" for i in ids)

    for verses, kjv in groups:
        if len(verses) == 1 and len(kjv) == 1:
            v, k = verses[0], kjv[0]
            if run:
                pv, pk = run[-1]
                same = v == pv + 1 and k == pk + 1 and v // 1000 == pv // 1000 and k // 1000 == pk // 1000
                if not same:
                    flush()
            run.append((v, k))
            continue
        flush()
        book = (verses or kjv)[0] // 1_000_000
        lines.append(f"group(book: {book}, [{pairs(verses)}], kjv: [{pairs(kjv)}])")
    flush()
    return lines


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    lines = swift_lines(groups_for(os.path.abspath(sys.argv[1])))
    body = ",\n".join(f"        {line}" for line in lines)
    with open(OUTPUT, "w", encoding="utf-8") as handle:
        handle.write(f"""// Generated by Tools/BibleData/align_versification.py. Don't edit by hand.

extension OriginalVersification {{
    /// Reina-Valera 1909 verses numbered differently from the KJV (open-bibles'
    /// USFX keeps the Spanish numbering): which KJV verses each one holds.
    /// Every other verse has the KJV's number.
    static let reinaValera1909Exceptions: [VerseAlignment] = reinaValera1909Rules.flatMap {{ $0 }}

    private static let reinaValera1909Rules: [[VerseAlignment]] = [
{body},
    ]
}}
""")
    print(f"wrote {OUTPUT}: {len(lines)} rules")


if __name__ == "__main__":
    main()
