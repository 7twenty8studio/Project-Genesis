#!/usr/bin/env python3
"""Prints UI test failures from an .xcresult bundle, one line each:

    ReaderUITests/testSwitchTranslation() [iPad Pro 13-inch (M5)]: ReaderUITests.swift:101: XCTAssertTrue failed - ...

Xcode hides failure messages in the console when several simulators run at
once, so build.sh calls this after each UI test pass.

When a pass fails without any failed check (the test runner or the app
crashed, a simulator wouldn't boot, the run was cut short), it prints the
run-level errors instead, so the failures file is never empty.
Usage: ui_failures.py path/to/Result.xcresult
"""
import json
import subprocess
import sys


def run(args):
    try:
        output = subprocess.run(["xcrun", "xcresulttool", *args], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return None
    if output.returncode != 0 or not output.stdout.strip():
        return None
    try:
        return json.loads(output.stdout)
    except json.JSONDecodeError:
        return None


def load(path, kind):
    return run(["get", "test-results", kind, "--path", path, "--compact"])


def walk(node, test=None, device=None, found=None, silent=None):
    found = [] if found is None else found
    silent = [] if silent is None else silent
    kind = node.get("nodeType", "")
    name = node.get("name", "")
    if kind == "Test Case":
        test = node.get("nodeIdentifier") or name
    elif kind in ("Device", "Run Destination"):
        device = name
    elif kind == "Failure Message":
        found.append(f"{test} [{device or '?'}]: {name}")
    children = node.get("children", []) or []
    for child in children:
        walk(child, test, device, found, silent)
    # A test case marked failed with no message (a crash can do this).
    if kind == "Test Case" and node.get("result") == "Failed" \
            and not any(c.get("nodeType") == "Failure Message" for c in children):
        silent.append(f"{test} [{device or '?'}]: failed with no message (crash or timeout?)")
    return found, silent


def legacy_errors(path):
    """Run-level errors ("Test runner never began executing tests", "Early
    unexpected exit…") live in the action results of the older format."""
    root = run(["get", "object", "--legacy", "--path", path, "--format", "json"])
    if not root:
        return []
    found = []
    for action in (root.get("actions", {}) or {}).get("_values", []) or []:
        for key in ("actionResult", "buildResult"):
            issues = (action.get(key, {}) or {}).get("issues", {}) or {}
            for summary in (issues.get("errorSummaries", {}) or {}).get("_values", []) or []:
                message = (summary.get("message", {}) or {}).get("_value", "")
                if message:
                    found.append(f"Run error: {message}")
    return found


def main():
    path = sys.argv[1]
    tree = load(path, "tests")
    failures, silent = [], []
    if tree:
        for node in tree.get("testNodes", []):
            walk(node, found=failures, silent=silent)
    summary = load(path, "summary") or {}
    if not failures:
        for failure in summary.get("testFailures", []) or []:
            failures.append(f"{failure.get('testIdentifierString') or failure.get('testName')}: {failure.get('failureText')}")
    failures += silent
    if not failures:
        failures += legacy_errors(path)
        build = run(["get", "build-results", "--path", path, "--compact"]) or {}
        for error in build.get("errors", []) or []:
            failures.append(f"Run error: {error.get('message') or error}")
        if summary:
            failures.append(
                "Result: {} · {} passed, {} failed, {} skipped of {}".format(
                    summary.get("result", "?"), summary.get("passedTests", "?"),
                    summary.get("failedTests", "?"), summary.get("skippedTests", "?"),
                    summary.get("totalTestCount", "?"),
                )
            )
        elif not tree:
            failures.append("No test results were written: the run stopped before any test started.")
    for line in dict.fromkeys(failures):  # de-duplicate, keep order
        print(line)


if __name__ == "__main__":
    main()
