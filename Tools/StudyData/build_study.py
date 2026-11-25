#!/usr/bin/env python3
"""Builds Genesis/Resources/Study/Study.sqlite: people, places, events and
map routes for the timeline, maps and character explorer.

Source: Theographic Bible Metadata by Robert Rouse
(https://github.com/robertrouse/theographic-bible-metadata), CC BY-SA 4.0.
Its place coordinates come from OpenBible.info's Bible Geocoding (CC BY 4.0)
and the Recogito/DARE gazetteer; biographies are Easton's Bible Dictionary
(1897, public domain). Because the source is ShareAlike, Study.sqlite is
distributed under CC BY-SA 4.0 too (see Genesis/Resources/Study/LICENSE.txt).
The app's code is not affected by that license.

No Scripture text is stored here, only verse ids.

How sure each place's location is comes from OpenBible.info's Bible
Geocoding Data (CC BY 4.0): its current confidence score (0–1000) for the
best identification, drawn from 70+ atlases, dictionaries and commentaries.
The app shows places as known (750+), likely (500–749) or uncertain.

Usage:
    git clone --depth 1 https://github.com/robertrouse/theographic-bible-metadata /tmp/theographic
    git clone --depth 1 https://github.com/openbibleinfo/Bible-Geocoding-Data /tmp/openbible
    python3 Tools/StudyData/build_study.py /tmp/theographic /tmp/openbible

    python3 Tools/StudyData/build_study.py --place-names   # PLACE_NAMES only
    python3 Tools/StudyData/build_study.py --routes        # ROUTES only
"""
import collections
import json
import csv
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "BibleData"))
from books import OSIS_TO_NUMBER, verse_id  # noqa: E402

csv.field_size_limit(10**9)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUTPUT = os.path.join(ROOT, "Genesis", "Resources", "Study", "Study.sqlite")

# Eras shown on the timeline, in order (from the PRD). An event belongs to the
# era of the passage where it's told.
# Each era has a short neutral summary and the chapter where it begins, so
# every era can be opened even where the dataset has few events.
ERAS = [
    ("creation", "Creation", "God creates the heavens and the earth, and humanity's first generations.", "Gen", 1),
    ("noah", "Noah", "The flood, God's covenant with Noah, and the tower of Babel.", "Gen", 6),
    ("abraham", "Abraham", "God's call and promise to Abraham, and the lives of Isaac, Jacob and Joseph.", "Gen", 12),
    ("moses", "Moses", "Israel's deliverance from Egypt, the law at Sinai and the wilderness years.", "Exod", 1),
    ("joshua", "Joshua", "Israel enters and settles the promised land.", "Josh", 1),
    ("judges", "Judges", "Cycles of turning away and deliverance before Israel has a king.", "Judg", 1),
    ("kings", "Kings", "Saul, David and Solomon, the divided kingdom, and the fall of Israel and Judah.", "1Sam", 8),
    ("prophets", "Prophets", "Prophets speak to Israel and the nations; exile and the return to Jerusalem.", "Isa", 1),
    ("jesus", "Jesus", "The birth, ministry, death and resurrection of Jesus.", "Matt", 1),
    ("acts", "Acts", "The early church spreads from Jerusalem to Rome.", "Acts", 1),
    ("letters", "Letters", "Letters from Paul and other apostles to churches and believers.", "Rom", 1),
    ("revelation", "Revelation", "John's vision of Christ, judgment and the new creation.", "Rev", 1),
]
# Before Abraham the traditional (Ussher) dates are too contested to show, so
# those eras are ordered without dates.
UNDATED_ERAS = {"creation", "noah"}


# Old Testament events after Genesis 11 are placed by their (traditional,
# approximate) date rather than by the book that tells them, so a flashback in
# Chronicles lands in the right era. Boundaries are astronomical years.
DATED_ERA_ENDS = [(-1490, "abraham"), (-1450, "moses"), (-1420, "joshua"), (-1094, "judges"), (-585, "kings")]


# Places the dataset names by one word of a longer name ("Place" for the place
# of a skull, "Forest" for the house of the forest): the full name in the KJV's
# words at the place's verses (the ASV's where the KJV has none, 1 Kgs 7:7,
# Ezra 4:10). Same ids as the bundled Study.sqlite; the Spanish and Portuguese
# names are pinned in translations/manual.json (`ids`).
PLACE_NAMES = {
    66: "Turning of the Wall",          # 2 Chr 26:9
    244: "Beyond the River",            # Ezra 4:10 (ASV; KJV "this side the river")
    261: "Brook of the Willows",        # Isa 15:7
    301: "City of Destruction",         # Isa 19:18
    302: "City of Salt",                # Josh 15:62
    511: "Porch of Judgment",           # 1 Kgs 7:7
    512: "Porch of Pillars",            # 1 Kgs 7:6
    513: "Porch of the Throne",         # 1 Kgs 7:7 (ASV)
    584: "House of the Forest",         # Isa 22:8
    690: "King's Highway",              # Num 20:17
    691: "King's Pool",                 # Neh 2:14
    954: "Place of a Skull",            # Matt 27:33, Mark 15:22
    957: "Pool of Siloah",              # Neh 3:15
    1152: "The Lord Is There",          # Ezek 48:35
    1153: "Place of a Skull",           # John 19:17
    1154: "Calvary",                    # Luke 23:33
    1177: "Tower of Hananeel",          # Neh 3:1
    1179: "Tower of Meah",              # Neh 3:1
    1180: "Tower of the Furnaces",      # Neh 3:11
    1229: "Fuller's Field",             # 2 Kgs 18:17, Isa 7:3
    1232: "Rocks of the Wild Goats",    # 1 Sam 24:2
}


def apply_place_names(db) -> int:
    """Gives the places in PLACE_NAMES their full names. Safe to run again."""
    changed = 0
    for pid, name in PLACE_NAMES.items():
        changed += db.execute("UPDATE places SET name = ? WHERE id = ? AND name != ?", (name, pid, name)).rowcount
    db.commit()
    return changed


def era_for_event(book: int, chapter: int, start):
    era = era_for(book, chapter)
    if era in UNDATED_ERAS or book >= 40 or start is None:
        return era
    for end, name in DATED_ERA_ENDS:
        if start < end:
            return name
    return "prophets"


def era_for(book: int, chapter: int) -> str:
    if book == 1:
        if chapter <= 5:
            return "creation"
        if chapter <= 11:
            return "noah"
        return "abraham"
    if book == 18:  # Job: traditionally set in the patriarchal age
        return "abraham"
    if 2 <= book <= 5:
        return "moses"
    if book == 6:
        return "joshua"
    if book in (7, 8) or (book == 9 and chapter <= 7):
        return "judges"
    if book <= 14 or 19 <= book <= 22:  # Samuel-Chronicles, Psalms-Song
        return "kings"
    if book <= 39:  # Ezra-Esther, the prophets
        return "prophets"
    if book <= 43:
        return "jesus"
    if book == 44:
        return "acts"
    if book <= 65:
        return "letters"
    return "revelation"


OSIS_REF = re.compile(r"^([1-3]?[A-Za-z]+)\.(\d+)\.(\d+)$")


def parse_verse(ref: str):
    match = OSIS_REF.match(ref.strip())
    if not match or match.group(1) not in OSIS_TO_NUMBER:
        return None
    return verse_id(OSIS_TO_NUMBER[match.group(1)], int(match.group(2)), int(match.group(3)))


def verses(field: str):
    ids = (parse_verse(ref) for ref in (field or "").split(",") if ref.strip())
    return sorted({v for v in ids if v is not None})


def slugs(field: str):
    return [s.strip() for s in (field or "").split(",") if s.strip()]


# "[Ex. 6:20](/exod#Exod.6.20)" -> "Ex. 6:20"; drop other markdown.
LINK = re.compile(r"\[([^\]]+)\]\([^)]*\)")


def clean_text(text: str) -> str:
    text = LINK.sub(r"\1", text or "")
    text = re.sub(r"[*_]{1,2}([^*_]+)[*_]{1,2}", r"\1", text)
    text = re.sub(r"[ \t]+", " ", text).strip()
    # Some entries start with stray markup such as "'=Saul".
    return re.sub(r"^['=\s]+", "", text)


EXCLUDED_PEOPLE = {"god_1324", "holy_spirit_7400"}


def other_names(field: str, name: str) -> str:
    """'Saul,Mercurius' -> 'Saul, Mercurius'; drops duplicates, lowercase words
    and editors' notes ('4b is just "mount" or "mountain"', Mount of Olives)."""
    seen, names = {name.lower()}, []
    for other in (field or "").split(","):
        other = other.strip()
        if other and other[0].isupper() and not other[0].isdigit() and '"' not in other and other.lower() not in seen:
            seen.add(other.lower())
            names.append(other)
    return ", ".join(names)


def number(field: str):
    try:
        return float(field) if field not in (None, "") else None
    except ValueError:
        return None


def year(field: str):
    value = number(field)
    return int(value) if value is not None else None


def place_confidence(openbible: str):
    """Returns a function from a Theographic place row to OpenBible's current
    confidence (0–1000) in its location, or None when it can't be matched.

    Places are matched by the verses that mention them (the two datasets
    use the same OSIS references), preferring an OpenBible place with the
    same name; otherwise the place sharing most of its verses."""
    ancient = []
    with open(os.path.join(openbible, "data", "ancient.jsonl"), encoding="utf-8") as handle:
        for line in handle:
            ancient.append(json.loads(line))
    by_verse = collections.defaultdict(set)
    for index, place in enumerate(ancient):
        for verse in place.get("verses", []):
            by_verse[verse["osis"]].add(index)

    def best_score(place):
        scores = [i["score"]["time_total"] for i in place["identifications"] if "time_total" in i.get("score", {})]
        return max(0, min(1000, max(scores))) if scores else None

    def simple(name):
        return re.sub(r"[^a-z]", "", re.sub(r"\s*\d+$", "", (name or "").lower()))

    def confidence(row):
        refs = [v for v in (row["verses"] or "").split(",") if v]
        shared = collections.Counter()
        for ref in refs:
            for index in by_verse.get(ref, ()):
                shared[index] += 1
        names = {simple(row["kjvName"]), simple(row["displayTitle"]), simple(row["esvName"])}
        same_name = [(count, index) for index, count in shared.items() if simple(ancient[index]["friendly_id"]) in names]
        if same_name:
            return best_score(ancient[max(same_name)[1]])
        if shared:
            index, count = shared.most_common(1)[0]
            if count >= max(1, len(refs) * 0.6):
                return best_score(ancient[index])
        return None

    return confidence


def rows(directory: str, name: str):
    with open(os.path.join(directory, "CSV", name), encoding="utf-8-sig") as handle:
        yield from csv.DictReader(handle)


# Map routes (PRD: Paul's missionary journeys, Exodus route). Stops are place
# names resolved against the dataset; the build fails if one is missing.
# Names follow the KJV spellings used by the dataset (Coos = Cos, Melita =
# Malta). A name the dataset gives two places is pinned to one in
# ROUTE_PLACES, by its slug ("Succoth (Egypt)": the Succoth of Exodus 12:37,
# not Jacob's Succoth by the Jordan).
#
# A (latitude, longitude) pair between stops is a point the line passes
# without a marker, where a straight line would contradict the text: under
# the lee of Cyprus and south of Crete (Acts 27:4-8), south of Cyprus (Acts
# 21:3), by sea along the coast rather than over land (Acts 14:26, 18:18-22),
# by land through Macedonia to Greece and back (Acts 20:1-3),
# and "by the way of the Red sea, to compass the land of Edom" (Numbers 21:4,
# Deuteronomy 2:8), east of Edom and Moab (Numbers 21:11-13).
#
# Paul's routes follow Acts. Where Acts names a region rather than towns
# (Syria and Cilicia, Acts 15:41; Galatia and Phrygia, 16:6 and 18:23), the
# towns are the ones Bible atlases usually draw: Tarsus, Derbe, Lystra,
# Iconium and Pisidian Antioch.
#
# The Exodus route is the traditional (southern) reconstruction found in most
# Bible atlases, and is labelled as such in the app: Rameses (Qantir), the
# sea crossed near the head of the Gulf of Suez, Mount Sinai at Jebel Musa,
# Hazeroth at Ain Hudra, Kadesh-barnea at Ain el-Qudeirat, Mount Hor at Jebel
# Harun, then south to Ezion-geber and around Edom to the plains of Moab
# (Numbers 33:5-49). Debated alternatives (a northern crossing by Lake
# Sirbonis, a central route, Sinai in Arabia at Jebel al-Lawz, Kadesh at
# Petra) aren't drawn.
ROUTE_PLACES = {
    "Succoth (Egypt)": "succoth_1114",
}
ROUTES = [
    ("paul-1", "Paul's First Journey", "Acts 13–14", 44013004,
     ["Antioch (Syria)", "Seleucia", "Salamis", "Paphos", "Perga", "Antioch (Pisidia)",
      "Iconium", "Lystra", "Derbe", "Lystra", "Iconium", "Antioch (Pisidia)", "Perga",
      "Attalia",
      (36.45, 31.20), (35.95, 32.80), (36.15, 34.20), (36.40, 35.50), (36.11, 35.93),
      "Antioch (Syria)"]),
    ("paul-2", "Paul's Second Journey", "Acts 15:36–18:22", 44015036,
     ["Antioch (Syria)", "Tarsus", "Derbe", "Lystra", "Iconium", "Antioch (Pisidia)", "Troas",
      "Samothrace", "Neapolis", "Philippi", "Amphipolis", "Apollonia", "Thessalonica", "Berea",
      "Athens", "Corinth", "Cenchreae",
      (37.55, 24.05),
      "Ephesus",
      (37.65, 27.05), (36.80, 27.45), (36.30, 28.40),
      "Caesarea", "Jerusalem", "Antioch (Syria)"]),
    ("paul-3", "Paul's Third Journey", "Acts 18:23–21:17", 44018023,
     ["Antioch (Syria)", "Tarsus", "Derbe", "Lystra", "Iconium", "Antioch (Pisidia)", "Ephesus",
      "Troas", "Philippi",
      (40.63, 22.93), (39.64, 22.42), (38.32, 23.32),
      "Corinth",
      (38.32, 23.32), (39.64, 22.42), (40.63, 22.93),
      "Philippi", "Troas", "Assos", "Mitylene", "Chios",
      "Samos", "Trogyllium", "Miletus", "Coos", "Rhodes", "Patara",
      (34.35, 32.50),
      "Tyre", "Ptolemais", "Caesarea", "Jerusalem"]),
    ("paul-rome", "Paul's Journey to Rome", "Acts 27–28", 44027001,
     ["Caesarea", "Sidon",
      (35.30, 35.10), (35.95, 34.40), (35.85, 33.30), (35.95, 32.30), (36.05, 30.45),
      "Myra",
      (36.10, 29.60), (36.35, 28.90), (36.52, 28.30), (36.62, 27.80),
      "Cnidus", "Salmone",
      (34.92, 26.15), (34.90, 25.50),
      "Fair Havens", "Clauda", "Melita", "Syracuse", "Rhegium", "Puteoli",
      "Appii Forum", "Three Taverns", "Rome"]),
    ("exodus", "The Exodus (a traditional route)", "Exodus 12 – Numbers 33", 2012037,
     ["Rameses", "Succoth (Egypt)", "Etham", "Pi-hahiroth", "Marah", "Elim", "Sin",
      "Rephidim", "Mount Sinai", "Hazeroth", "Kadesh-barnea", "Mount Hor", "Ezion-geber", "Elath",
      (29.80, 35.32), (30.30, 35.80), (30.70, 36.00),
      "Zered",
      (31.25, 36.00),
      "Arnon", "Dibon-gad", "Mount Nebo", "Abel-shittim"]),
]


def write_routes(db, names_to_place: dict, slugs: dict, coordinates: dict) -> list:
    """Fills routes, route_stops and route_path (the line drawn: stops and the
    points between them). Returns the stops it couldn't find."""
    db.execute("CREATE TABLE IF NOT EXISTS route_path (route_id TEXT NOT NULL, position INTEGER NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, PRIMARY KEY (route_id, position)) WITHOUT ROWID")
    for table in ("routes", "route_stops", "route_path"):
        db.execute(f"DELETE FROM {table}")
    missing = []
    for sort, (route_id, title, passage, first, stops) in enumerate(ROUTES):
        db.execute("INSERT INTO routes VALUES (?, ?, ?, ?, ?)", (route_id, sort, title, passage, first))
        stop_position = 0
        for position, stop in enumerate(stops):
            if isinstance(stop, tuple):
                point = stop
            else:
                place = slugs.get(ROUTE_PLACES[stop]) if stop in ROUTE_PLACES else resolve_place(stop, names_to_place)
                if place is None or coordinates.get(place) is None:
                    missing.append(f"{title}: {stop}")
                    continue
                db.execute("INSERT INTO route_stops VALUES (?, ?, ?)", (route_id, stop_position, place))
                stop_position += 1
                point = coordinates[place]
            db.execute("INSERT INTO route_path VALUES (?, ?, ?, ?)", (route_id, position, point[0], point[1]))
    return missing


def write_routes_in(path: str) -> list:
    """Rewrites the routes in an existing Study.sqlite from its own places."""
    db = sqlite3.connect(path)
    names_to_place, slugs, coordinates = {}, {}, {}
    for pid, slug, name, lat, lon, count in db.execute(
            "SELECT id, slug, name, latitude, longitude, verse_count FROM places ORDER BY id"):
        slugs[slug] = pid
        if lat is None or lon is None:
            continue
        coordinates[pid] = (lat, lon)
        best = names_to_place.get(name.lower())
        if best is None or count > best[1]:
            names_to_place[name.lower()] = (pid, count)
    missing = write_routes(db, names_to_place, slugs, coordinates)
    if not missing:
        db.commit()
    db.close()
    return missing


def build(source: str, openbible: str) -> None:
    confidence = place_confidence(openbible)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    db = sqlite3.connect(OUTPUT)
    db.executescript(
        """
        PRAGMA page_size = 4096;
        CREATE TABLE eras (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, title TEXT NOT NULL, dated INTEGER NOT NULL, summary TEXT NOT NULL, first_verse INTEGER NOT NULL);
        CREATE TABLE people (
            id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
            also_called TEXT NOT NULL, gender TEXT NOT NULL, bio TEXT NOT NULL,
            birth_year INTEGER, death_year INTEGER, verse_count INTEGER NOT NULL,
            first_verse INTEGER, tribe TEXT NOT NULL);
        CREATE TABLE person_verses (person_id INTEGER NOT NULL, verse INTEGER NOT NULL, PRIMARY KEY (person_id, verse)) WITHOUT ROWID;
        CREATE TABLE relations (person_id INTEGER NOT NULL, kind TEXT NOT NULL, other_id INTEGER NOT NULL, PRIMARY KEY (person_id, kind, other_id)) WITHOUT ROWID;
        CREATE TABLE places (
            id INTEGER PRIMARY KEY, slug TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
            aliases TEXT NOT NULL, kind TEXT NOT NULL, latitude REAL, longitude REAL,
            precise INTEGER NOT NULL, bio TEXT NOT NULL, verse_count INTEGER NOT NULL, first_verse INTEGER,
            confidence INTEGER);  -- OpenBible.info, 0-1000; NULL when unknown
        CREATE TABLE place_verses (place_id INTEGER NOT NULL, verse INTEGER NOT NULL, PRIMARY KEY (place_id, verse)) WITHOUT ROWID;
        CREATE TABLE events (
            id INTEGER PRIMARY KEY, title TEXT NOT NULL, era TEXT NOT NULL REFERENCES eras(id),
            sort_key REAL NOT NULL, year INTEGER, first_verse INTEGER, last_verse INTEGER);
        CREATE TABLE event_verses (event_id INTEGER NOT NULL, verse INTEGER NOT NULL, PRIMARY KEY (event_id, verse)) WITHOUT ROWID;
        CREATE TABLE event_people (event_id INTEGER NOT NULL, person_id INTEGER NOT NULL, PRIMARY KEY (event_id, person_id)) WITHOUT ROWID;
        CREATE TABLE event_places (event_id INTEGER NOT NULL, place_id INTEGER NOT NULL, PRIMARY KEY (event_id, place_id)) WITHOUT ROWID;
        CREATE TABLE routes (id TEXT PRIMARY KEY, sort INTEGER NOT NULL, title TEXT NOT NULL, passage TEXT NOT NULL, first_verse INTEGER NOT NULL);
        CREATE TABLE route_stops (route_id TEXT NOT NULL, position INTEGER NOT NULL, place_id INTEGER NOT NULL, PRIMARY KEY (route_id, position)) WITHOUT ROWID;
        CREATE TABLE route_path (route_id TEXT NOT NULL, position INTEGER NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL, PRIMARY KEY (route_id, position)) WITHOUT ROWID;
        """
    )
    for sort, (era_id, title, summary, osis, chapter) in enumerate(ERAS):
        db.execute("INSERT INTO eras VALUES (?, ?, ?, ?, ?, ?)",
                   (era_id, sort, title, 0 if era_id in UNDATED_ERAS else 1, summary,
                    verse_id(OSIS_TO_NUMBER[osis], chapter, 1)))

    # People. God and the Holy Spirit are left out: they would top every
    # "people in this chapter" list, and a biography page doesn't suit them.
    people = [p for p in rows(source, "People.csv") if p["personLookup"] not in EXCLUDED_PEOPLE]
    person_ids = {p["personLookup"]: int(p["personID"]) for p in people}
    for p in people:
        pid = int(p["personID"])
        vs = verses(p["verses"])
        db.execute(
            "INSERT INTO people VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (pid, p["personLookup"], p["displayTitle"] or p["name"], other_names(p["alsoCalled"], p["displayTitle"] or p["name"]),
             p["gender"] or "", clean_text(p["dictText"]), year(p["birthYear"]), year(p["deathYear"]),
             len(vs), vs[0] if vs else None, p["memberOf"] or ""),
        )
        db.executemany("INSERT INTO person_verses VALUES (?, ?)", [(pid, v) for v in vs])
        for kind, field in [("father", "father"), ("mother", "mother"), ("partner", "partners"),
                            ("child", "children"), ("sibling", "siblings"),
                            ("sibling", "halfSiblingsSameMother"), ("sibling", "halfSiblingsSameFather")]:
            for other in slugs(p[field]):
                if other in person_ids:
                    db.execute("INSERT OR IGNORE INTO relations VALUES (?, ?, ?)", (pid, kind, person_ids[other]))

    # Places
    places = list(rows(source, "Places.csv"))
    place_ids = {p["placeLookup"]: int(p["placeID"]) for p in places}
    names_to_place = {}
    place_coordinates = {}
    for p in places:
        pid = int(p["placeID"])
        lat = number(p["openBibleLat"]) or number(p["latitude"])
        lon = number(p["openBibleLong"]) or number(p["longitude"])
        vs = verses(p["verses"])
        name = p["displayTitle"] or p["kjvName"]
        db.execute(
            "INSERT INTO places VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
            (pid, p["placeLookup"], name, p["aliases"] or "", p["featureType"] or "",
             lat, lon, 1 if (p["precision"] or "").lower() == "precise" else 0,
             clean_text(p["dictText"]), len(vs), vs[0] if vs else None, confidence(p)),
        )
        db.executemany("INSERT INTO place_verses VALUES (?, ?)", [(pid, v) for v in vs])
        if lat is not None and lon is not None:
            place_coordinates[pid] = (lat, lon)
        # Prefer the best-attested, mapped place when names repeat.
        key = name.lower()
        best = names_to_place.get(key)
        if lat is not None and (best is None or len(vs) > best[1]):
            names_to_place[key] = (pid, len(vs))

    # Events
    for e in rows(source, "Events.csv"):
        eid = int(e["eventID"])
        vs = verses(e["verses"])
        sort_book, sort_chapter = int(e["verseSort"][:2] or 1), int(e["verseSort"][2:5] or 1)
        start = year(e["startDate"])
        era = era_for_event(sort_book, sort_chapter, start)
        db.execute(
            "INSERT INTO events VALUES (?,?,?,?,?,?,?)",
            (eid, e["title"], era, number(e["sortKey"]) or 0, None if era in UNDATED_ERAS else start,
             vs[0] if vs else None, vs[-1] if vs else None),
        )
        db.executemany("INSERT INTO event_verses VALUES (?, ?)", [(eid, v) for v in vs])
        db.executemany("INSERT OR IGNORE INTO event_people VALUES (?, ?)",
                       [(eid, person_ids[s]) for s in slugs(e["participants"]) if s in person_ids])
        db.executemany("INSERT OR IGNORE INTO event_places VALUES (?, ?)",
                       [(eid, place_ids[s]) for s in slugs(e["locations"]) if s in place_ids])

    # Routes
    missing = write_routes(db, names_to_place, place_ids, place_coordinates)
    if missing:
        db.close()
        os.remove(OUTPUT)
        sys.exit("Route stops not found in the dataset:\n  " + "\n  ".join(missing))

    apply_place_names(db)
    db.executescript(
        """
        CREATE INDEX person_verses_by_verse ON person_verses (verse);
        CREATE INDEX place_verses_by_verse ON place_verses (verse);
        CREATE INDEX event_verses_by_verse ON event_verses (verse);
        CREATE INDEX events_by_sort ON events (sort_key);
        CREATE INDEX people_by_name ON people (name COLLATE NOCASE);
        CREATE INDEX places_by_name ON places (name COLLATE NOCASE);
        ANALYZE;
        """
    )
    db.commit()
    db.execute("VACUUM")
    db.close()


def resolve_place(stop: str, names_to_place: dict):
    """'Antioch (Syria)' -> the dataset's Antioch in Syria, by trying a few spellings."""
    candidates = [stop, stop.replace(" (", " of ").rstrip(")")]
    if "(" in stop:
        base, qualifier = stop[:-1].split(" (")
        candidates += [f"{base} ({qualifier})", f"{base} of {qualifier}", f"{base}, {qualifier}"]
    for name in candidates:
        found = names_to_place.get(name.lower())
        if found:
            return found[0]
    return None


if __name__ == "__main__":
    if sys.argv[1:] == ["--place-names"]:
        # Only the full place names, in the bundled database (no rebuild).
        with sqlite3.connect(OUTPUT) as database:
            print(f"{apply_place_names(database)} place names updated in {OUTPUT}")
        sys.exit(0)
    if sys.argv[1:] == ["--routes"]:
        # Only the map routes, in the bundled database (no rebuild).
        missing = write_routes_in(OUTPUT)
        if missing:
            sys.exit("Route stops not found in the bundled database:\n  " + "\n  ".join(missing))
        print(f"{len(ROUTES)} routes written to {OUTPUT}")
        sys.exit(0)
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2])
    # Spanish and Portuguese names (Tools/StudyData/translations).
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from add_study_translations import add
    add(OUTPUT)
    size = os.path.getsize(OUTPUT) / 1_000_000
    print(f"Wrote {OUTPUT} ({size:.1f} MB)")
