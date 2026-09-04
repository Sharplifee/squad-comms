#!/usr/bin/env python3
"""Fail the build when the client calls an RPC with parameters the server
doesn't declare.

PostgREST rejects a call outright if it carries an unknown parameter, so an
extra field is not harmless — the whole call fails. And nothing catches it
before runtime: the Swift compiles, the function exists, the names are just
wrong. This shipped once already, on join_squad and create_squad, which are
the two calls the entire app depends on.

The server signatures live in EXPECTED below rather than being queried live,
so this runs in CI without credentials. When a migration changes a signature,
update it here in the same commit — that coupling is the point.
"""

import re
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent / "Sources/SquadComms/Session/Backend.swift"

EXPECTED = {
    "block_device":    {"p_blocker", "p_blocked"},
    "blocked_devices": {"p_blocker"},
    "claim_host":      {"p_squad_id", "p_device_id"},
    "create_squad":    {"p_code", "p_name", "p_device_id", "p_display_name"},
    "delete_device":   {"p_device_id"},
    "end_squad":       {"p_squad_id", "p_device_id"},
    "extend_squad":    {"p_squad_id", "p_device_id"},
    "heartbeat":       {"p_squad_id", "p_device_id"},
    "join_squad":      {"p_code", "p_device_id", "p_display_name"},
    "leave_squad":     {"p_squad_id", "p_device_id"},
    "match_contacts":  {"p_hashes"},
    "register_device": {"p_device_id", "p_display_name", "p_phone_hash",
                        "p_ghost", "p_identity"},
    "report_device":   {"p_reporter", "p_reported", "p_squad", "p_reason", "p_detail"},
    "set_ghost_mode":  {"p_device_id", "p_ghost"},
    "touch_squad":     {"p_squad_id"},
    "unblock_device":  {"p_blocker", "p_blocked"},
}


def main() -> int:
    src = BACKEND.read_text()
    problems = []

    for match in re.finditer(r'\.rpc\("([a-z_]+)"', src):
        name = match.group(1)
        if name not in EXPECTED:
            problems.append(f"UNKNOWN RPC: {name} is called but not in the expected list")
            continue
        # The params struct is declared in the same function, above the call.
        start = src.rfind("func ", 0, match.start())
        sent = set(re.findall(r"let (p_[a-z_]+):", src[start:match.start()]))
        extra = sent - EXPECTED[name]
        if extra:
            problems.append(
                f"BAD PARAM: {name} is sent {sorted(extra)}, which the server "
                f"does not declare — PostgREST will reject the whole call"
            )

    for line in problems:
        print(line)

    if problems:
        print(f"\n{len(problems)} RPC mismatch(es). These fail at runtime, not compile time.")
        return 1

    print(f"audit: {len(EXPECTED)} RPC signatures checked, client and server agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
