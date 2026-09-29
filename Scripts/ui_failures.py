#!/usr/bin/env python3
"""Prints UI test failures from an .xcresult bundle, one line each:

    ReaderUITests/testSwitchTranslation() [iPad Pro 13-inch (M5)]: ReaderUITests.swift:101: XCTAssertTrue failed - ...

Xcode hides failure messages in the console when several simulators run at
once, so build.sh calls this after each UI test pass.
Usage: ui_failures.py path/to/Result.xcresult
"""
import json
import subprocess
import sys


def load(path, kind):
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", kind, "--path", path, "--compact"],
        capture_output=True, text=True,
    )
    if output.returncode != 0 or not output.stdout.strip():
        return None
    return json.loads(output.stdout)


def walk(node, test=None, device=None, found=None):
    found = [] if found is None else found
    kind = node.get("nodeType", "")
    name = node.get("name", "")
    if kind == "Test Case":
        test = node.get("nodeIdentifier") or name
    elif kind in ("Device", "Run Destination"):
        device = name
    elif kind == "Failure Message":
        found.append(f"{test} [{device or '?'}]: {name}")
    for child in node.get("children", []) or []:
        walk(child, test, device, found)
    return found


def main():
    path = sys.argv[1]
    tree = load(path, "tests")
    failures = []
    if tree:
        for node in tree.get("testNodes", []):
            walk(node, found=failures)
    if not failures:
        summary = load(path, "summary") or {}
        for failure in summary.get("testFailures", []):
            failures.append(f"{failure.get('testIdentifierString') or failure.get('testName')}: {failure.get('failureText')}")
    for line in dict.fromkeys(failures):  # de-duplicate, keep order
        print(line)


if __name__ == "__main__":
    main()
