#!/usr/bin/env python3
"""Reads the .xcloc folders written by `xcodebuild -exportLocalizations` and
prints each string that has no Spanish yet, one per line:

    Localizable.xcstrings | GenesisWidgets | "Next reminder %@" | comment

Used by Scripts/localization_check.sh.
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def main(root):
    for xliff in sorted(glob.glob(os.path.join(root, "*.xcloc", "Localized Contents", "*.xliff"))):
        tree = ET.parse(xliff)
        for file in tree.getroot().findall("x:file", NS):
            original = file.get("original", "")
            # Only the app's own strings: skip Info.plist names and packages.
            if not original.endswith(".xcstrings"):
                continue
            for unit in file.iter("{urn:oasis:names:tc:xliff:document:1.2}trans-unit"):
                source = unit.find("x:source", NS)
                target = unit.find("x:target", NS)
                note = unit.find("x:note", NS)
                state = target.get("state") if target is not None else None
                if target is None or not (target.text or "").strip() or state in ("new", "needs-translation"):
                    text = (source.text or "") if source is not None else unit.get("id", "")
                    comment = (note.text or "").strip() if note is not None else ""
                    print(f'{original} | "{text}" | {comment}'.replace("\n", "\\n"))


if __name__ == "__main__":
    main(sys.argv[1])
