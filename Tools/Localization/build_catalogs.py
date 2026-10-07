#!/usr/bin/env python3
"""Writes Genesis's String Catalogs from the Spanish in es.json.

  python3 Tools/Localization/build_catalogs.py

Extracts the strings the code uses (extract_strings.py), takes their Spanish
from Tools/Localization/es.json (English key → Spanish) and writes:
  Genesis/Resources/Localizable.xcstrings   the app
  GenesisWidgets/Localizable.xcstrings      the widgets (+ Genesis/Shared)
  GenesisWatch/, GenesisWatchWidgets/       the Apple Watch app and complication
  Genesis/Resources/InfoPlist.xcstrings     permission texts (project.yml NS…UsageDescription)

Fails, listing them, if a string has no Spanish or a translation's
placeholders (%@, %lld, %%) don't match the English. To add a language later,
add its JSON next to es.json and its code to LANGUAGES.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from extract_strings import extract  # noqa: E402

LANGUAGES = ["es"]
TARGETS = {
    "Genesis/Resources/Localizable.xcstrings": ["Genesis"],
    "GenesisWidgets/Localizable.xcstrings": ["GenesisWidgets", "Genesis/Shared"],
    "GenesisWatch/Localizable.xcstrings": ["GenesisWatch"],
    "GenesisWatchWidgets/Localizable.xcstrings": ["GenesisWatchWidgets"],
}
SPECIFIER = re.compile(r"%(?:\d+\$)?(@|lld|d|ld|f|lf)")
# Info.plist permission texts ("NS…UsageDescription: \"…\"" in project.yml)
# go into the app's InfoPlist string catalog, keyed by the Info.plist key.
INFO_PLIST_CATALOG = "Genesis/Resources/InfoPlist.xcstrings"
USAGE_LINE = re.compile(r'^\s+(NS\w+UsageDescription):\s*"((?:[^"\\]|\\.)*)"\s*$')


def placeholders(text):
    return sorted(m.group(1) for m in SPECIFIER.finditer(text)), text.count("%%")


def main():
    os.chdir(ROOT)
    translations = {lang: json.load(open(os.path.join(HERE, f"{lang}.json"), encoding="utf-8")) for lang in LANGUAGES}
    problems = []
    for path, sources in TARGETS.items():
        found = extract(sources)
        strings = {}
        for key in sorted(found):
            entry = {}
            if found[key]["comment"]:
                entry["comment"] = found[key]["comment"]
            localizations = {}
            for lang, table in translations.items():
                value = table.get(key)
                if value is None:
                    problems.append(f"no {lang}: {key!r}  ({', '.join(os.path.basename(f) for f in found[key]['files'])})")
                    continue
                if placeholders(value) != placeholders(key):
                    problems.append(f"placeholders differ ({lang}): {key!r} → {value!r}")
                    continue
                localizations[lang] = {"stringUnit": {"state": "translated", "value": value}}
            if localizations:
                entry["localizations"] = localizations
            strings[key] = entry
        catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
        with open(path, "w", encoding="utf-8") as out:
            json.dump(catalog, out, ensure_ascii=False, indent=2, sort_keys=True)
            out.write("\n")
        print(f"{path}: {len(strings)} strings")
    problems += write_info_plist_catalog(translations)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)


def write_info_plist_catalog(translations):
    """InfoPlist.xcstrings from project.yml's usage descriptions."""
    problems = []
    strings = {}
    with open("project.yml", encoding="utf-8") as spec:
        for line in spec:
            match = USAGE_LINE.match(line)
            if not match:
                continue
            key, english = match.group(1), match.group(2).replace('\\"', '"')
            localizations = {"en": {"stringUnit": {"state": "translated", "value": english}}}
            for lang, table in translations.items():
                value = table.get(english)
                if value is None:
                    problems.append(f"no {lang}: {english!r}  (project.yml {key})")
                    continue
                localizations[lang] = {"stringUnit": {"state": "translated", "value": value}}
            strings[key] = {"extractionState": "manual", "localizations": localizations}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(INFO_PLIST_CATALOG, "w", encoding="utf-8") as out:
        json.dump(catalog, out, ensure_ascii=False, indent=2, sort_keys=True)
        out.write("\n")
    print(f"{INFO_PLIST_CATALOG}: {len(strings)} strings")
    return problems


if __name__ == "__main__":
    main()
