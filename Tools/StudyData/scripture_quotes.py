"""Finds the Bible verses Easton quotes, so translations can use the
Reina-Valera 1909 and the Bíblia Livre's own words (bios.py).

Each “quotation” in a description is one of:
  whole    the whole of a KJV verse (or of consecutive verses): the
           translation quotes the RV1909 / Bíblia Livre verse verbatim;
  partial  three or more words from inside a KJV verse: the translation
           quotes the matching words of that verse verbatim, flagged for
           review;
  wording  one or two words found in a KJV verse he refers to beside them
           (Easton commenting on the KJV's rendering, "the “plain” of Mamre"): translated, flagged
           for review;
  loose    four or more longer words close to, but not exactly, a KJV verse
           (Easton's brackets, ellipses or his own wording): quoted from
           the verse's RV1909 / Bíblia Livre words as closely as fits,
           flagged for review;
  unsure   three to five words found in the KJV, but not near a reference
           he gives (a common phrase, or a verse he doesn't cite):
           translated, flagged for review with the verse found;
  other    not in the KJV (Easton's own term, a name, another book):
           translated like the rest of the text.
"""
import os
import re
import sqlite3
import unicodedata
from functools import lru_cache

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BIBLES = os.path.join(ROOT, "Genesis", "Resources", "Bibles")
TABLES = os.path.join(ROOT, "Genesis", "Core", "Study", "VersificationTables.swift")
QUOTE = re.compile(r"“([^”]+)”")


def norm(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return " ".join(re.findall(r"[a-z0-9]+", text))


def rv1909_map():
    """KJV verse id -> the RV1909 verse ids holding it, where they differ."""
    source = open(TABLES, encoding="utf-8").read()
    source = source[source.index("reinaValera1909Rules"):]
    mapping = {}
    vid = lambda b, c, v: b * 1_000_000 + c * 1_000 + v
    for m in re.finditer(r"shift\(book: (\d+), chapter: (\d+), verses: (\d+)\.\.\.(\d+), kjvChapter: (\d+), by: (-?\d+)\)", source):
        b, c, a, z, kc, by = map(int, m.groups())
        for v in range(a, z + 1):
            mapping.setdefault(vid(b, kc, v + by), []).append(vid(b, c, v))
    for m in re.finditer(r"group\(book: (\d+), \[([^\]]*)\], kjv: \[([^\]]*)\]\)", source):
        b = int(m.group(1))
        own = [vid(b, int(c), int(v)) for c, v in re.findall(r"\((\d+), (\d+)\)", m.group(2))]
        for c, v in re.findall(r"\((\d+), (\d+)\)", m.group(3)):
            mapping[vid(b, int(c), int(v))] = own
    return mapping


class Bibles:
    def __init__(self, rv1909_path: str):
        def verses(path):
            db = sqlite3.connect(path)
            return dict(db.execute("SELECT id, text FROM verses"))
        self.kjv = verses(os.path.join(BIBLES, "KJV.sqlite"))
        self.es = verses(rv1909_path)
        self.pt = verses(os.path.join(BIBLES, "BLIVRE.sqlite"))
        self.rv_map = rv1909_map()
        self.order = sorted(self.kjv)
        self.normed = {i: norm(t) for i, t in self.kjv.items()}
        self.position = {i: n for n, i in enumerate(self.order)}

    def target(self, lang, kjv_ids):
        if lang == "es":
            ids = []
            for i in kjv_ids:
                for r in self.rv_map.get(i, [i]):
                    if r not in ids:
                        ids.append(r)
            return " ".join(self.es[i] for i in ids if i in self.es)
        return " ".join(self.pt[i] for i in kjv_ids if i in self.pt)

    def find(self, quote: str, hints):
        """(kind, kjv ids) for a quotation; hints are verse ids referenced near it."""
        q = norm(quote)
        words = q.split()
        if not words:
            return "other", []
        found = self._search(q, hints)
        if not found:
            # Easton's insertions ("[Heb., Adam]") and ellipses aside.
            pieces = [norm(p) for p in re.split(r"\[[^\]]*\]|\.\.\.|…", quote) if len(norm(p).split()) >= 4]
            for piece in sorted(pieces, key=len, reverse=True):
                found = self._search(piece, hints)
                if found:
                    return "loose", found[0]
            content = [w for w in words if len(w) > 3]
            if len(content) >= 4:
                ids = self._closest(content, hints)
                if ids:
                    return "loose", ids
            return "other", []
        ids, whole, near = found
        if whole:
            return "whole", ids
        if len(words) >= 6 or (len(words) >= 3 and near):
            return "partial", ids
        if len(words) >= 3:
            # A short common phrase found only far from any reference
            # ("on one stone"): maybe Scripture, maybe not.
            return "unsure", ids
        # One or two words are the KJV's rendering only beside their reference.
        return ("wording", ids) if near else ("other", [])

    def _search(self, q, hints):
        """(kjv ids, whole) for the shortest run of verses holding the
        quotation, near the references first, then anywhere; or None."""
        near = []
        for h in hints:
            if h in self.position:
                n = self.position[h]
                near += [i for i in self.order[max(0, n - 2): n + 5] if i not in near]
        for pool in (near, self.order):
            for i in pool:
                found = self._at(q, i)
                if found:
                    return found + (pool is near,)
        return None

    def _closest(self, words, hints):
        """The verse (or pair) holding most of the quotation's longer words, if 75%+."""
        want = set(words)
        best, score = None, 0.0
        pools = []
        for h in hints:
            if h in self.position:
                n = self.position[h]
                pools += self.order[max(0, n - 2): n + 5]
        for pool in (pools, self.order):
            for i in pool:
                n = self.position[i]
                for ids in (self.order[n:n + 1], self.order[n:n + 2]):
                    if ids[-1] // 1000 != i // 1000:
                        continue
                    have = set(" ".join(self.normed[x] for x in ids).split())
                    s = len(want & have) / len(want)
                    if s > score + 1e-9:
                        best, score = ids, s
            if score >= 0.85:
                break
        return best if score >= 0.75 else None

    def _at(self, q, start):
        n = self.position[start]
        padded = f" {q} "
        for length in range(1, 5):
            ids = self.order[n:n + length]
            if len(ids) < length or ids[-1] // 1000 != start // 1000:
                return None
            joined = " ".join(self.normed[x] for x in ids)
            if q == joined:
                return ids, True
            if padded in f" {joined} ":
                # Must need every verse in the run (spans into the last one).
                first = " " + " ".join(self.normed[x] for x in ids[:-1]) + " "
                rest = " " + " ".join(self.normed[x] for x in ids[1:]) + " "
                if length == 1 or (padded not in first and padded not in rest):
                    return ids, False
                return None
        return None


BOOKS = "Gen Ex Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kings 2Kings 1Chr 2Chr Ezra Neh Esther Job Ps Prov Eccl Cant Isa Jer Lam Ezek Dan Hos Joel Amos Obad Jonah Micah Nah Hab Zeph Hag Zech Mal Matt Mark Luke John Acts Rom 1Cor 2Cor Gal Eph Phil Col 1Thess 2Thess 1Tim 2Tim Titus Philemon Heb James 1Pet 2Pet 1John 2John 3John Jude Rev".split()
ALIASES = {"Exod": "Ex", "Judge": "Judg", "Psalms": "Ps", "Psalm": "Ps", "Mat": "Matt", "Exek": "Ezek", "1Thes": "1Thess", "2King": "2Kings", "Ge": "Gen", "Song": "Cant"}
REF = re.compile(r"\b([123] )?([A-Z][a-z]+)\.? (\d+):(\d+)")


def references(text: str):
    """[(offset, verse id)] for every 'Gen. 12:1' style reference."""
    out = []
    for m in REF.finditer(text):
        book = (m.group(1) or "").replace(" ", "") + m.group(2)
        book = ALIASES.get(book, book)
        if book in BOOKS:
            out.append((m.start(), (BOOKS.index(book) + 1) * 1_000_000 + int(m.group(3)) * 1_000 + int(m.group(4))))
    return out


def quotations(text: str, bibles: Bibles):
    """Every quotation in a description with what it is and, for Scripture,
    its verses and the RV1909 / Bíblia Livre text to quote from."""
    refs = references(text)
    out = []
    for n, m in enumerate(QUOTE.finditer(text)):
        # References after the quote (the usual place), then before it.
        after = [v for o, v in refs if m.end() <= o <= m.end() + 60]
        before = [v for o, v in refs if o < m.start()][-3:]
        kind, ids = bibles.find(m.group(1), after + before)
        entry = {"n": n, "english": m.group(1), "kind": kind}
        if ids:
            entry["verses"] = ids
            entry["es"] = bibles.target("es", ids)
            entry["pt"] = bibles.target("pt", ids)
        out.append(entry)
    return out
