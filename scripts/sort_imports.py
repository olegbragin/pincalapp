#!/usr/bin/env python3
"""Group imports as: system modules first, then application modules.

SwiftFormat cannot do this. Its `--import-grouping` only accepts alpha,
access-control, length, testable-first and testable-last, and every one of them
collapses the import block into a single alphabetical run - deleting the blank
line that separates the groups. Apple's `swift-format` does not reorder imports
at all. So .swiftformat disables `sortImports` and `blankLinesBetweenImports` to
keep its hands off the import block, and this script owns it instead.

Resulting layout, each group alphabetical and all groups adjacent, so the order
carries the grouping:

    import Foundation
    import SwiftUI
    import CoreDomain
    import DSKit
    @testable import SingleCalendarFeatureTests

`@testable` imports are kept in their own trailing position, which is the usual
convention for keeping the module under test visually separate.

Idempotent: running it on an already-grouped file is a no-op.

Usage:
    python3 scripts/sort_imports.py [--check] [paths...]
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

# Apple / SDK modules. Anything listed here sorts into the first group.
# Kept deliberately broad so a newly added framework classifies correctly
# without needing a code change.
SYSTEM_MODULES = frozenset("""
Foundation Swift SwiftUI UIKit AppKit Combine CoreData CoreGraphics CoreLocation
CoreText CryptoKit Dispatch FoundationNetworking FoundationXML
OSLog UniformTypeIdentifiers Observation Regex SwiftData SwiftRegex
UIKitUI CoreTransferable WidgetKit Charts MetricKit NaturalLanguage
Security AuthenticationServices Crypto SwiftOnoneSupport
XCTest Testing os simctl
""".split())

IMPORT_RE = re.compile(r"^(@testable\s+)?import\s+([A-Za-z0-9_.]+)\s*$")
DIRECTIVE_RE = re.compile(r"^\s*#(if|else|elseif|endif)\b")
COMMENT_RE = re.compile(r"^\s*//")
TOOLS_VERSION_RE = re.compile(r"^\s*//\s*swift-tools-version\s*:")


def local_modules(repo_root: pathlib.Path) -> set[str]:
    """First-party module names, discovered from Packages/ plus the app target."""
    names = set()
    packages = repo_root / "Packages"
    if packages.is_dir():
        for child in packages.iterdir():
            # Only a directory that actually declares a library product counts;
            # a plain folder of tooling would otherwise become a module name.
            if child.is_dir() and (child / "Package.swift").is_file():
                names.add(child.name)
    names.add("PinCalApp")
    return names


def classify(module: str, local: set[str]) -> str:
    root = module.split(".")[0]
    if root in SYSTEM_MODULES:
        return "system"
    if root in local:
        return "application"
    # Third-party dependencies are not system code, and this project treats
    # them as application-level. Change here if you ever want them in their own
    # group - it is a three-line edit.
    return "application"


def collect(lines: list[str]) -> tuple[int, int] | None:
    """Locate the import block. Returns (start, end) line indices, or None."""
    start = None
    for i, line in enumerate(lines):
        if IMPORT_RE.match(line):
            start = i
            break
        # A leading file-header comment or blank lines may precede the imports.
        if COMMENT_RE.match(line) or not line.strip():
            continue
        return None  # real code before any import; not a plain header

    if start is None:
        return None

    # Walk forward over imports, interleaved comments and blank lines, but stop
    # at the LAST import. Comments and blanks after that point belong to the
    # declaration that follows, not to the import block - consuming them would
    # swallow the file's first doc comment and make the block unrenderable.
    end = start
    last_import_end = start + 1
    for i in range(start, len(lines)):
        line = lines[i]
        if IMPORT_RE.match(line):
            end = i + 1
            last_import_end = i + 1
            continue
        if COMMENT_RE.match(line) or not line.strip():
            end = i + 1
            continue
        break

    # The span must end at the last import. `end` may sit past it when the file
    # has a blank line and a doc comment immediately after the imports; those
    # belong to the next declaration and must stay outside the block.
    return (start, last_import_end)


def render(block: list[str], local: set[str]) -> str | None:
    """Return the regrouped import block, or None if it should be left alone."""
    if any(DIRECTIVE_RE.match(line) for line in block):
        # Conditional compilation around imports changes which modules are
        # visible per configuration; regrouping could silently drop one.
        return None

    # An import carries any comment block that sits directly above it, so a
    # "why this import" note travels with its import instead of detaching.
    entries: list[tuple[str, str | None, str, str]] = []
    pending: list[str] = []
    for line in block:
        stripped = line.strip()
        if not stripped:
            pending.clear()
            continue
        if COMMENT_RE.match(line):
            pending.append(line.rstrip())
            continue
        m = IMPORT_RE.match(line)
        if not m:
            return None
        testable = (m.group(1) or "").strip()
        module = m.group(2)
        entries.append((classify(module, local), testable, module, "\n".join(pending)))
        pending.clear()
    if pending:
        return None  # trailing comment with no import to attach to

    if not entries:
        return None

    groups: dict[tuple[str, int], list[str]] = {}
    for kind, testable, module, comment in entries:
        # Non-testable entries first, testable in their own trailing group.
        order = 1 if testable else 0
        key = (kind, order)
        body = f"import {module}" if not testable else f"{testable} import {module}"
        groups.setdefault(key, []).append(f"{comment}\n{body}" if comment else body)

    # system -> application -> @testable
    rank = {("system", 0): 0, ("application", 0): 1, ("system", 1): 2, ("application", 1): 3}
    chunks = []
    for key in sorted(groups, key=lambda k: rank.get(k, 99)):
        # Sort on the module name, ignoring any leading comment lines.
        chunks.append("\n".join(sorted(groups[key], key=lambda s: s.split("import ")[-1].lower())))
    # Groups are adjacent, not separated by a blank line: system modules first,
    # then application modules, as one contiguous block. The ORDER carries the
    # grouping; a blank line would make it a formatting decision a reviewer has
    # to defend rather than a convention that just reads correctly.
    return "\n".join(chunks) + "\n"


def process(path: pathlib.Path, local: set[str], check: bool) -> bool:
    original = path.read_text(encoding="utf-8")
    lines = original.split("\n")
    span = collect(lines)
    if span is None:
        return False
    start, last = span

    # `// swift-tools-version:` is only valid as the FIRST line of a manifest,
    # and it sits immediately above the import block. If it were carried along
    # with its import it could land on line 3, which SPM rejects. Every
    # Package.swift here has a single import so it cannot move today, but that
    # is luck rather than design - so bail out explicitly.
    for i in range(start - 1, -1, -1):
        line = lines[i]
        if TOOLS_VERSION_RE.match(line):
            return False
        if not COMMENT_RE.match(line):
            break

    # Trim trailing blank lines inside the span so we control the separators.
    end = last
    while end > start and not lines[end - 1].strip():
        end -= 1

    block = lines[start:end]
    new_block = render(block, local)
    if new_block is None:
        return False

    # Everything after the block: drop its leading blank lines, because
    # new_block already ends with a newline and the separator blank line is
    # added here. Without this, a file whose imports are followed by
    # "<blank><doc comment>" would come out with two blank lines.
    rest = lines[last:]
    while rest and not rest[0].strip():
        rest.pop(0)

    candidate = "\n".join(lines[:start]) + "\n" + new_block
    if rest:
        # one newline closes the last import, one more is the blank separator
        candidate += "\n" + "\n".join(rest)

    if candidate == original:
        return False
    if check:
        print(f"{path}: imports are not grouped")
        return True
    path.write_text(candidate, encoding="utf-8")
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="report files needing changes instead of rewriting them")
    ap.add_argument("paths", nargs="*", default=["."])
    args = ap.parse_args()

    repo_root = pathlib.Path(__file__).resolve().parent.parent
    local = local_modules(repo_root)

    changed = []
    for raw in args.paths:
        root = pathlib.Path(raw)
        if root.is_file():
            candidates = [root]
        else:
            candidates = sorted(root.rglob("*.swift"))
        for path in candidates:
            parts = set(path.parts)
            if ".build" in parts or "generated" in parts:
                continue
            if path.name == "LocalizedStringKeyExtension.swift":
                continue  # regenerated by the build; grouping it is churn
            if process(path, local, args.check):
                changed.append(path)

    verb = "would regroup" if args.check else "regrouped"
    print(f"{verb} {len(changed)} file(s)")
    return 1 if (args.check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
