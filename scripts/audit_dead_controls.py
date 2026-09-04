#!/usr/bin/env python3
"""Fail the build when a setting exists that nothing acts on.

This codebase has produced the same bug five separate times: a control bound
to a stored preference that no behaviour ever reads. The duck posted a
notification with no observers. Self-monitor, noise suppression, auto-pause
and auto-rewind moved sliders nothing consumed. The music choice and the
visibility picker each wrote one field while the app read a different one.

Every instance was invisible in review and invisible on device — the UI
responds, the value persists, and nothing happens. Only an audit catches it,
so the audit runs on every build rather than whenever somebody remembers.

Checks:
  1. Every field on Preferences is read somewhere outside the model file.
  2. No two enums declare the same set of case names, which is how the
     music-choice split appeared — two types for one decision.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
MODELS = SOURCES / "SquadComms" / "Models" / "Models.swift"

# Fields deliberately written but never read back by app logic.
ALLOWED_WRITE_ONLY: set[str] = set()


def swift_files() -> list[Path]:
    return sorted(SOURCES.rglob("*.swift"))


def preference_fields(text: str) -> list[str]:
    """Field names declared inside `struct Preferences`."""
    match = re.search(r"struct Preferences[^{]*\{(.*?)\n\}", text, re.S)
    if not match:
        return []
    return re.findall(r"\bvar\s+([A-Za-z_]\w*)\s*:", match.group(1))


def find_dead_preferences() -> list[str]:
    text = MODELS.read_text()
    fields = preference_fields(text)
    others = [f for f in swift_files() if f != MODELS]
    blob = "\n".join(f.read_text() for f in others)

    dead = []
    for field in fields:
        if field in ALLOWED_WRITE_ONLY:
            continue
        # A read looks like `.field` or `$prefs.field` anywhere outside Models.
        if not re.search(r"\.\s*" + re.escape(field) + r"\b", blob):
            dead.append(field)
    return dead


def find_duplicate_enums() -> list[tuple[str, str, str]]:
    """Two enums covering the same cases means two names for one decision."""
    signatures: dict[frozenset[str], list[str]] = {}
    for path in swift_files():
        for match in re.finditer(r"enum\s+(\w+)[^{]*\{(.*?)\n\}", path.read_text(), re.S):
            name, body = match.group(1), match.group(2)
            cases = set()
            for line in re.findall(r"^\s*case\s+([^\n/]+)", body, re.M):
                # `case .duck: return ...` inside a switch is not a
                # declaration. Only bare identifiers count, or the enum's
                # own switch bodies pollute every signature.
                if ":" in line and not re.match(r"^[\w\s,]+:\s*\w+\s*$", line):
                    continue
                for part in line.split(","):
                    part = part.strip().split("(")[0].split("=")[0].strip()
                    if part and re.fullmatch(r"[a-zA-Z_]\w*", part):
                        cases.add(part)
            if len(cases) >= 3:
                signatures.setdefault(frozenset(cases), []).append(name)

    clashes = []
    for cases, names in signatures.items():
        if len(names) > 1:
            clashes.append((names[0], names[1], ", ".join(sorted(cases))))
    return clashes


# Views that are entry points and so have no in-project reference.
ROOT_VIEWS = {"RootView", "SquadCommsApp", "LineLiveActivity", "SquadCommsWidgetBundle"}


def find_orphan_views() -> list[str]:
    """SwiftUI views that exist but are never placed anywhere.

    Two of these shipped in one commit — a nearby panel and a ribbon, both
    written, both compiled, neither ever mounted, while an older inline copy
    kept rendering. Dead UI is worse than dead settings: it looks like the
    feature exists when you read the code.
    """
    declared: dict[str, Path] = {}
    for path in swift_files():
        for match in re.finditer(r"\bstruct\s+(\w+)\s*:\s*[^{\n]*\bView\b", path.read_text()):
            declared[match.group(1)] = path

    orphans = []
    for name, home in declared.items():
        if name in ROOT_VIEWS:
            continue
        used = False
        for path in swift_files():
            text = path.read_text()
            if path == home:
                # A view referencing only itself is still unused.
                text = re.sub(r"\bstruct\s+" + re.escape(name) + r"\b", "", text)
            if re.search(r"\b" + re.escape(name) + r"\s*\(", text):
                used = True
                break
        if not used:
            orphans.append(f"{name} ({home.relative_to(ROOT)})")
    return sorted(orphans)


# Called by the system, not by us.
DELEGATE_METHODS = {
    "centralManagerDidUpdateState", "centralManager",
    "peripheralManagerDidUpdateState", "peripheralManager",
    "perform", "application", "room", "body", "makeBody",
}


def find_uncalled_methods() -> list[str]:
    """Non-private methods in the session and audio layers that nothing calls.

    This is the third shape of the same bug. Private lines had earcons,
    reliable routing and ducking, and no gesture left to trigger them.
    Push-to-talk had no button. registerSelf was never called, so contact
    matching could never find anybody. The audio session was never
    deactivated, so music stayed ducked after leaving.

    Every one of them compiled, shipped, and did nothing.
    """
    layers = [f for f in swift_files()
              if "/Session/" in str(f) or "/Audio/" in str(f)]
    texts = {f: f.read_text() for f in swift_files()}

    uncalled = []
    for path in layers:
        for match in re.finditer(r"^\s{4}(?!private)(?:@MainActor\s+)?func\s+(\w+)",
                                 texts[path], re.M):
            name = match.group(1)
            if name in DELEGATE_METHODS:
                continue
            uses = 0
            for other, text in texts.items():
                body = text
                if other == path:
                    body = re.sub(r"func\s+" + re.escape(name) + r"\b", "", body)
                uses += len(re.findall(r"[.\s]" + re.escape(name) + r"\s*\(", body))
            if uses == 0:
                uncalled.append(f"{name} ({path.relative_to(ROOT)})")
    return sorted(uncalled)


def main() -> int:
    problems = 0

    dead = find_dead_preferences()
    if dead:
        problems += len(dead)
        print("DEAD SETTINGS — stored but nothing reads them:")
        for field in dead:
            print(f"  Preferences.{field}")
        print("  A control bound to these would move and do nothing.")
        print("  Either wire it to behaviour, or delete the field.\n")

    orphans = find_orphan_views()
    if orphans:
        problems += len(orphans)
        print("ORPHAN VIEWS — declared but never placed on screen:")
        for orphan in orphans:
            print(f"  {orphan}")
        print("  Dead UI reads as a working feature. Mount it or delete it.\n")

    uncalled = find_uncalled_methods()
    if uncalled:
        problems += len(uncalled)
        print("UNCALLED METHODS — behaviour nothing can reach:")
        for method in uncalled:
            print(f"  {method}")
        print("  A feature with no caller ships as dead code that reads as done.\n")

    clashes = find_duplicate_enums()
    if clashes:
        problems += len(clashes)
        print("DUPLICATE ENUMS — two names for one decision:")
        for first, second, cases in clashes:
            print(f"  {first} and {second} both cover: {cases}")
        print("  This is how a control ends up writing one and the app")
        print("  reading the other. Collapse to one.\n")

    if problems:
        print(f"{problems} problem(s). See scripts/audit_dead_controls.py.")
        return 1

    print("No dead settings, no orphan views, no uncalled methods, no duplicate enums.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
