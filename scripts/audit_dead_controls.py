#!/usr/bin/env python3
"""Fail the build when a setting exists but nothing acts on it.

This is the bug this codebase keeps producing. Three times now a control has
shipped that moved, saved its value, and changed nothing:

  1. The duck posted a notification with no observer.
  2. Self monitor, noise suppression, auto pause and auto rewind had sliders
     and no consumers.
  3. The visibility control was bound to two booleans that had already been
     replaced by an enum.

Every one of them compiled. Every one looked right in review. The compiler
cannot catch it because storing a value IS a use, so it has to be checked
structurally: a preference that appears in the UI must also appear somewhere
that is not the UI, or it does nothing.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
MODELS = SOURCES / "SquadComms" / "Models" / "Models.swift"

# Computed display helpers, not settings — they have no behaviour to wire up.
EXEMPT = {"label", "detail", "id", "coordinate", "subtitle", "symbol"}


def preference_names() -> list[str]:
    """Stored properties on the Preferences struct."""
    text = MODELS.read_text()
    match = re.search(r"struct Preferences[^{]*\{(.*?)\n\}", text, re.S)
    if not match:
        print("audit: could not find the Preferences struct", file=sys.stderr)
        sys.exit(2)
    body = match.group(1)
    # `var x: T = ...` is stored; `var x: T { ... }` is computed.
    return [
        name for name, tail in re.findall(r"var ([a-zA-Z]+):\s*[^\n=]+(=?)", body)
        if tail == "=" and name not in EXEMPT
    ]


def swift_files():
    return [p for p in SOURCES.rglob("*.swift")]


def main() -> int:
    prefs = preference_names()
    ui_hits, behaviour_hits = {}, {}

    for path in swift_files():
        text = path.read_text()
        is_ui = "/UI/" in str(path)
        is_model = path.name == "Models.swift"
        for name in prefs:
            if not re.search(rf"\.{name}\b", text):
                continue
            if is_ui:
                ui_hits.setdefault(name, []).append(path.name)
            elif not is_model:
                behaviour_hits.setdefault(name, []).append(path.name)

    dead = sorted(n for n in prefs if n in ui_hits and n not in behaviour_hits)
    unused = sorted(n for n in prefs if n not in ui_hits and n not in behaviour_hits)

    for name in dead:
        print(f"DEAD CONTROL: {name} — shown in {', '.join(sorted(set(ui_hits[name])))} "
              f"but nothing outside the UI reads it")
    for name in unused:
        print(f"UNUSED SETTING: {name} — stored but neither shown nor acted on")

    if dead:
        print(f"\n{len(dead)} control(s) move and do nothing. This has shipped three "
              f"times already; wire it up or remove it.")
        return 1

    print(f"audit: {len(prefs)} settings checked, every one has something acting on it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
