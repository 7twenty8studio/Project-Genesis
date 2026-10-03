#!/usr/bin/env python3
"""Lists the user-facing strings in Genesis's Swift code, keyed the way Xcode
keys a String Catalog ("\\(count) verses" becomes "%lld verses").

Xcode extracts strings itself when it builds; this script exists because
development happens on a machine without Xcode. It is a close approximation:
Scripts/localization_check.sh on the Mac lists anything it missed (via
xcodebuild -exportLocalizations), and those are added by hand.

Usage:
  python3 Tools/Localization/extract_strings.py Genesis > build/strings-app.json
  python3 Tools/Localization/extract_strings.py GenesisWidgets Genesis/Shared > build/strings-widgets.json

Prints {key: {"comment": ..., "files": [...]}}.
"""
import json
import os
import re
import sys

# Calls whose first argument (or the named argument) is a LocalizedStringKey.
KEY_CALLS = [
    "Text", "Button", "Label", "Toggle", "Picker", "Section", "Menu", "TextField",
    "SecureField", "Link", "LabeledContent", "ContentUnavailableView", "Stepper",
    "DatePicker", "Tab", "ProgressView", "GroupBox", "DisclosureGroup", "NavigationLink",
    ".navigationTitle", ".alert", ".confirmationDialog", ".help", ".accessibilityLabel",
    ".accessibilityHint", ".accessibilityValue", ".configurationDisplayName", ".description",
    ".navigationSubtitle", ".badge",
]
# .searchable(prompt:), control(label:), .accessibilityAction(named:)
NAMED_KEY_ARGS = ["prompt:", "label:", "named:"]

STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"')

INT_HINTS = re.compile(
    r"(count|Count|total|Total|number|Number|days|Days|minutes|limit|Limit|percent|remaining|shown|"
    r"chapter|Chapter|verse\b|streak|Streak|year|Year|completed|Completed|notes|prayers|"
    r"aiRequestsPerDay|referenceCount|memberCount|readCount|dayNumber|Chapters|\bn\b|index|rank|"
    r"ofDays|dayCount|longestStreak|booksCompleted|chapterTotal|\bday\b|behind|Voices|Minutes|Finished|^Int\(|\breviewed\b|\bdue\b|\bmemorised\b|maximumVerses)"
)


def specifier(expression: str, in_text: bool) -> str:
    e = expression.strip()
    if e.startswith("Int("):
        return "%lld"
    if e.startswith("String("):
        return "%@"
    if ".formatted(" in e or "description" in e or "name" in e.lower() or "title" in e.lower() \
            or e.startswith('"') or "Label" in e or "label" in e or "abbreviation" in e:
        return "%@"
    if re.fullmatch(r"[\w.]+\s*[-+*/%]\s*[\w.]+", e) or re.fullmatch(r"\d+", e):
        return "%lld"
    if "," in e and in_text:  # Text("\(date, style: .relative)") / format:
        return "%@"
    if INT_HINTS.search(e):
        return "%lld"
    return "%@"


def unescape(body: str) -> str:
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n == "u" and body[i + 2:i + 3] == "{":
                end = body.index("}", i)
                out.append(chr(int(body[i + 3:end], 16)))
                i = end + 1
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def key_for(literal: str, in_text: bool) -> str:
    """Turns a Swift literal (with quotes) into a catalog key."""
    body = literal[1:-1]
    parts = []
    i = 0
    while i < len(body):
        if body.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(body) and depth:
                if body[j] == "(":
                    depth += 1
                elif body[j] == ")":
                    depth -= 1
                elif body[j] == '"':  # skip nested string literals
                    k = j + 1
                    while k < len(body) and body[k] != '"':
                        k += 2 if body[k] == "\\" else 1
                    j = k
                j += 1
            parts.append(("arg", body[i + 2:j - 1]))
            i = j
        else:
            j = body.find("\\(", i)
            j = len(body) if j < 0 else j
            parts.append(("text", body[i:j]))
            i = j
    key = ""
    for kind, value in parts:
        if kind == "arg":
            key += specifier(value, in_text)
        else:
            key += unescape(value).replace("%", "%%")
    return key


def matching_paren(source: str, start: int) -> int:
    depth = 0
    i = start
    while i < len(source):
        c = source[i]
        if c == '"':
            m = STRING_LITERAL.match(source, i)
            if m:
                i = m.end()
                continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return len(source)


def first_argument(source: str, open_index: int) -> str:
    """The text of the first argument of a call starting at `(`."""
    depth = 0
    i = open_index + 1
    while i < len(source):
        c = source[i]
        if c == '"':
            m = STRING_LITERAL.match(source, i)
            if m:
                i = m.end()
                continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        i += 1
    return source[open_index + 1:i]


def top_level_literals(expression: str):
    """String literals in an expression that aren't inside a nested call
    (so `x ?? String(localized: "…")` contributes nothing here). After `??`
    a literal is a plain String (`Text(name ?? "…")`), so it isn't a key."""
    if "??" in expression:
        expression = expression.split("??")[0]
    depth = 0
    i = 0
    while i < len(expression):
        c = expression[i]
        if c == '"':
            m = STRING_LITERAL.match(expression, i)
            if m:
                if depth == 0:
                    yield m.group(0)
                i = m.end()
                continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        i += 1


def is_plain_identifier_literal(key: str) -> bool:
    # SF Symbols, identifiers and the like never appear as keys in these calls,
    # but empty strings and pure punctuation/numbers shouldn't be translated.
    return not re.search(r"[A-Za-z]", key)


def extract(paths):
    found = {}

    def add(key, comment, path):
        if is_plain_identifier_literal(key.replace("%lld", "").replace("%@", "")):
            return
        entry = found.setdefault(key, {"comment": None, "files": []})
        if comment and not entry["comment"]:
            entry["comment"] = comment
        if path not in entry["files"]:
            entry["files"].append(path)

    files = []
    for root in paths:
        if os.path.isfile(root):
            files.append(root)
        for dirpath, _, names in os.walk(root):
            files += [os.path.join(dirpath, n) for n in names if n.endswith(".swift")]
    for path in sorted(set(files)):
        if path.endswith("UITestingOptions.swift"):
            continue
        source = open(path, encoding="utf-8").read()
        # Strip line comments (but not "//" inside strings, e.g. URLs).
        lines = []
        for line in source.split("\n"):
            out, i, in_str = "", 0, False
            while i < len(line):
                if line[i] == '"' and (i == 0 or line[i - 1] != "\\"):
                    in_str = not in_str
                if not in_str and line.startswith("//", i):
                    break
                out += line[i]
                i += 1
            lines.append(out)
        source = "\n".join(lines)

        # String(localized: "…", comment: "…")
        for m in re.finditer(r"String\(localized:\s*", source):
            lit = STRING_LITERAL.match(source, m.end())
            if not lit:
                continue
            call_end = matching_paren(source, m.start() + len("String"))
            call = source[m.start():call_end]
            comment = re.search(r'comment:\s*("(?:[^"\\]|\\.)*")', call)
            add(key_for(lit.group(0), False), unescape(comment.group(1)[1:-1]) if comment else None, path)

        for name in KEY_CALLS:
            pattern = (re.escape(name) if name.startswith(".") else r"(?<![\w.])" + re.escape(name)) + r"\("
            for m in re.finditer(pattern, source):
                open_index = m.end() - 1
                arg = first_argument(source, open_index)
                if arg.strip().startswith("verbatim:"):
                    continue
                # Named first arguments like Text("…", comment:) are fine; skip
                # calls whose first argument is labelled with something else.
                label = re.match(r"\s*(\w+):", arg)
                if label and label.group(1) not in ("title", "titleKey"):
                    continue
                for lit in top_level_literals(arg):
                    add(key_for(lit, True), None, path)
        # InsightsView.stat(value, "label", symbol): the label is the second argument.
        for m in re.finditer(r"(?<![\w.])stat\([^,()]*(?:\([^()]*\))?[^,()]*,\s*", source):
            lit = STRING_LITERAL.match(source, m.end())
            if lit:
                add(key_for(lit.group(0), True), None, path)
        for named in NAMED_KEY_ARGS:
            for m in re.finditer(re.escape(named) + r"\s*", source):
                lit = STRING_LITERAL.match(source, m.end())
                if lit:
                    add(key_for(lit.group(0), True), None, path)
    return found


if __name__ == "__main__":
    print(json.dumps(extract(sys.argv[1:]), indent=1, ensure_ascii=False, sort_keys=True))
