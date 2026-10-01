#!/usr/bin/env python3
"""Builds the Supabase row for a recorded Bible narration.

Recorded narration is listed in public.audio_recordings (see
supabase/migrations/20261002000000_audio_recordings.sql). Each row maps every
chapter to an audio file. This script reads a folder listing of per-chapter
MP3 or M4A files, works out the book and chapter from each file name, checks
that nothing is missing, and writes the SQL to paste into the Supabase SQL
Editor.

Example (World English Bible read by Basil Sands, public domain):

  python3 Tools/AudioData/make_audio_manifest.py \\
      --listing https://ebible.org/engwebu/mp3/ \\
      --id web-basil-sands --translation WEB --title "Basil Sands" \\
      --description "World English Bible, read by Basil Sands." \\
      --license "Public domain" --source https://ebible.org/engwebu/mp3/ \\
      --enable --out build/audio-web-basil-sands.sql

If you mirror the files on your own storage (recommended once many people
listen), add --rebase https://your-cdn.example/web/ to point every chapter
there while keeping the file names.

Other inputs: --files names.txt (one file URL or name per line, with --rebase
for names) or --folder path/to/mp3s (with --rebase).

Only the Python standard library is needed. Run it on your Mac.
"""
from __future__ import annotations

import argparse
import html.parser
import json
import os
import re
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BOOKS_SWIFT = os.path.join(ROOT, "Genesis", "Core", "Bible", "BibleBook.swift")
AUDIO_EXTENSIONS = (".mp3", ".m4a", ".aac")

USFM = (
    "GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM "
    "EZK DAN HOS JOL AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP "
    "COL 1TH 2TH 1TI 2TI TIT PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV"
).split()

EXTRA_ALIASES = {
    1: ["gn"], 19: ["psalm", "pslm"], 22: ["songofsongs", "sos", "canticles"],
    40: ["matt", "mt", "matthew"], 41: ["mk", "mark", "mar"], 42: ["lk", "luke", "luk"],
    43: ["jn", "john", "joh"], 44: ["acts", "act"], 50: ["phil", "phili"], 57: ["phlm", "philem"],
    59: ["jas", "jam", "james"], 62: ["1jn", "1jo", "1john"], 63: ["2jn", "2jo", "2john"],
    64: ["3jn", "3jo", "3john"], 65: ["jud", "jude"], 66: ["rev", "revelation", "revelations", "apocalypse"],
}

# Tokens in file names that are never book names.
IGNORED = {"web", "kjv", "asv", "bible", "chapter", "ch", "mp", "mpeg", "audio", "eng", "engwebu", "engweb", "nt", "ot", "kb", "m4a", "aac"}


def load_books() -> list[dict]:
    """Book numbers, names and chapter counts, read from the app's own table."""
    source = open(BOOKS_SWIFT, encoding="utf-8").read()
    pattern = re.compile(
        r'\.init\(id: (\d+), osis: "([^"]+)", name: "([^"]+)", abbreviation: "([^"]+)", '
        r'testament: \.\w+, chapterCount: (\d+), aliases: \[([^\]]*)\]\)'
    )
    books = []
    for match in pattern.finditer(source):
        number, osis, name, abbreviation, chapters, aliases = match.groups()
        books.append({
            "id": int(number),
            "name": name,
            "chapters": int(chapters),
            "keys": {osis, name, abbreviation} | set(re.findall(r'"([^"]+)"', aliases)),
        })
    if len(books) != 66:
        sys.exit(f"Expected 66 books in {BOOKS_SWIFT}, found {len(books)}")
    return books


def alias_table(books: list[dict]) -> dict[str, int]:
    table: dict[str, int] = {}
    for book in books:
        keys = set(book["keys"]) | {USFM[book["id"] - 1]} | set(EXTRA_ALIASES.get(book["id"], []))
        for key in keys:
            normalized = re.sub(r"[^a-z0-9]", "", key.lower())
            # Two-letter aliases ("is", "so") collide with ordinary words.
            if len(normalized) >= 3 or normalized[:1].isdigit():
                table.setdefault(normalized, book["id"])
    return table


def parse_name(name: str, aliases: dict[str, int], books: list[dict]) -> tuple[int, int] | None:
    """(book, chapter) from a file name like '02_GEN_01.mp3',
    'WEB-070-Matt_01.mp3', '01_Genesis01_KJV.mp3' or '09_1SA_12.mp3', or from
    a book folder and chapter file like 'Genesis/01.mp3'."""
    path = urllib.parse.unquote(urllib.parse.urlparse(name).path if "://" in name else name)
    parts = [part for part in path.replace("\\", "/").split("/") if part]
    if not parts:
        return None
    file_only = parse_stem(os.path.splitext(parts[-1])[0], aliases, books)
    if file_only is not None or len(parts) < 2:
        return file_only
    return parse_stem(parts[-2] + "_" + os.path.splitext(parts[-1])[0], aliases, books)


def parse_stem(stem: str, aliases: dict[str, int], books: list[dict]) -> tuple[int, int] | None:
    stem = stem.lower()
    tokens = re.findall(r"[a-z]+|\d+", stem)
    for index, token in enumerate(tokens):
        if not token.isalpha():
            continue
        book = None
        rest = index + 1
        # A numbered book: "1" + "sa", "2" + "kings", "1" + "ch".
        if index > 0 and tokens[index - 1] in {"1", "2", "3"}:
            book = aliases.get(tokens[index - 1] + token)
        if book is None and token in IGNORED:
            continue
        # The name followed by "of" + more words: "song of solomon".
        if book is None and index + 2 < len(tokens) and tokens[index + 1] == "of":
            book = aliases.get(token + "of" + tokens[index + 2])
            if book is not None:
                rest = index + 3
        if book is None:
            book = aliases.get(token)
        if book is None:
            continue
        numbers = [t for t in tokens[rest:] if t.isdigit()]
        if numbers:
            chapter = int(numbers[0])
        elif books[book - 1]["chapters"] == 1:
            chapter = 1
        else:
            continue
        if 1 <= chapter <= books[book - 1]["chapters"]:
            return book, chapter
    return None


class LinkParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "GenesisAudioManifest/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8", errors="replace")


def list_files(listing: str, depth: int = 2) -> list[str]:
    """Audio file URLs in a web folder listing, following sub-folders."""
    parser = LinkParser()
    parser.feed(fetch(listing))
    files: list[str] = []
    for href in parser.links:
        url = urllib.parse.urljoin(listing, href)
        if not url.startswith(listing) or url == listing:
            continue
        if url.lower().endswith(AUDIO_EXTENSIONS):
            files.append(url)
        elif url.endswith("/") and depth > 0:
            files.extend(list_files(url, depth - 1))
    return sorted(set(files))


def sql_text(value: str | None) -> str:
    return "null" if value is None else "'" + value.replace("'", "''") + "'"


def build(args: argparse.Namespace) -> int:
    books = load_books()
    aliases = alias_table(books)

    listing = ""
    if args.listing:
        listing = args.listing if args.listing.endswith("/") else args.listing + "/"
        names = list_files(listing)
    elif args.files:
        names = [line.strip() for line in open(args.files, encoding="utf-8") if line.strip()]
    else:
        names = sorted(
            os.path.relpath(os.path.join(folder, file), args.folder)
            for folder, _, files in os.walk(args.folder)
            for file in files if file.lower().endswith(AUDIO_EXTENSIONS)
        )

    chapters: dict[str, str] = {}
    unmatched: list[str] = []
    duplicates: list[str] = []
    for name in names:
        parsed = parse_name(name, aliases, books)
        if parsed is None:
            unmatched.append(name)
            continue
        if args.rebase:
            # Keep the path below the listing (book folders included).
            if args.listing and name.startswith(listing):
                relative = name[len(listing):]
            elif name.startswith("http"):
                relative = urllib.parse.urlparse(name).path.rsplit("/", 1)[-1]
            else:
                relative = name.replace(os.sep, "/")
            url = urllib.parse.urljoin(args.rebase.rstrip("/") + "/", relative)
        else:
            url = name
        if not url.startswith("https://"):
            sys.exit(f"Chapter files must be https URLs (got {url}). Use --rebase for local names.")
        key = f"{parsed[0]}.{parsed[1]}"
        if key in chapters:
            duplicates.append(f"{key}: {chapters[key]} and {url}")
            continue
        chapters[key] = url

    expected = {f"{book['id']}.{chapter}" for book in books for chapter in range(1, book["chapters"] + 1)}
    missing = sorted(expected - set(chapters), key=lambda key: tuple(map(int, key.split("."))))

    print(f"Files found: {len(names)}; chapters matched: {len(chapters)} of {len(expected)}", file=sys.stderr)
    if unmatched:
        print(f"Not a Bible chapter (skipped), {len(unmatched)}: " + ", ".join(unmatched[:12]) + (" ..." if len(unmatched) > 12 else ""), file=sys.stderr)
    if duplicates:
        print(f"Duplicates (first kept), {len(duplicates)}: " + "; ".join(duplicates[:5]), file=sys.stderr)
    if missing:
        readable = [f"{books[int(k.split('.')[0]) - 1]['name']} {k.split('.')[1]}" for k in missing]
        print(f"Missing {len(missing)}: " + ", ".join(readable[:20]) + (" ..." if len(readable) > 20 else ""), file=sys.stderr)
        if not args.allow_partial:
            print("Stopping. Fix the names (or pass --allow-partial to publish what's there).", file=sys.stderr)
            return 1

    payload = json.dumps(dict(sorted(chapters.items(), key=lambda item: tuple(map(int, item[0].split("."))))), separators=(",", ":"))
    if "$chapters$" in payload:
        sys.exit("Unexpected text in file names.")
    statement = (
        "-- Generated by Tools/AudioData/make_audio_manifest.py. Paste into the Supabase SQL Editor and Run.\n"
        "insert into public.audio_recordings (id, translation, title, description, license, source_url, chapter_urls, enabled, sort, updated_at)\n"
        f"values ({sql_text(args.id)}, {sql_text(args.translation.upper())}, {sql_text(args.title)}, {sql_text(args.description)}, "
        f"{sql_text(args.license)}, {sql_text(args.source)}, $chapters${payload}$chapters$::jsonb, {'true' if args.enable else 'false'}, {args.sort}, now())\n"
        "on conflict (id) do update set translation = excluded.translation, title = excluded.title, description = excluded.description,\n"
        "  license = excluded.license, source_url = excluded.source_url, chapter_urls = excluded.chapter_urls,\n"
        "  enabled = excluded.enabled, sort = excluded.sort, updated_at = now();\n"
    )
    if args.out:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        open(args.out, "w", encoding="utf-8").write(statement)
        print(f"Wrote {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(statement)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--listing", help="URL of a web folder listing the chapter files")
    source.add_argument("--files", help="text file with one file URL or name per line")
    source.add_argument("--folder", help="local folder of chapter files (use with --rebase)")
    parser.add_argument("--rebase", help="base URL where the files are served, replacing the listing's")
    parser.add_argument("--id", required=True, help="stable id, e.g. web-basil-sands")
    parser.add_argument("--translation", required=True, choices=["KJV", "WEB", "ASV", "kjv", "web", "asv"])
    parser.add_argument("--title", required=True, help="usually the narrator's name")
    parser.add_argument("--description", default="")
    parser.add_argument("--license", required=True, help='e.g. "Public domain"')
    parser.add_argument("--source", help="where the recording comes from (shown for attribution)")
    parser.add_argument("--sort", type=int, default=0)
    parser.add_argument("--enable", action="store_true", help="make it available in the app right away")
    parser.add_argument("--allow-partial", action="store_true", help="publish even if chapters are missing")
    parser.add_argument("--out", help="write the SQL here instead of printing it")
    return build(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
