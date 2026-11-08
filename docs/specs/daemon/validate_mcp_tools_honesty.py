#!/usr/bin/env python3
"""Ensure mcp-tools.csv status columns are internally consistent (works-well gate).

Usage:
    python3 docs/specs/daemon/validate_mcp_tools_honesty.py
    python3 docs/specs/daemon/validate_mcp_tools_honesty.py --strict
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

CSV_PATH = Path(__file__).resolve().parent / "mcp-tools.csv"

DONE_FORBIDDEN_NOTES = re.compile(
    r"Fase not started|Needs kuma-exec|Epic C2\+D data layer RPC|"
    r"deferred to Epic|Structural validation D0",
    re.IGNORECASE,
)

# Rows allowed logic_status=done with empty dt_coverage when auto_test=y (smoke-tested).
AUTO_TEST_ALLOW_EMPTY_DT = frozenset(
    {
        "daemon.ping",
        "daemon.status",
        "daemon.shutdown",
        "daemon.rotate_api_token",
    }
)

# Methods covered by dt_rpc_smoke.rs (dt_coverage tag).
SMOKE_DT = "dt-rpc-smoke"


def load_csv() -> list[dict[str, str]]:
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail on warnings (default: fail on errors only)",
    )
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    rows = load_csv()

    for r in rows:
        rpc = r.get("rpc_method", "")
        logic = r.get("logic_status", "none")
        notes = r.get("notes", "").strip()
        auto = r.get("auto_test", "n")
        dt = r.get("dt_coverage", "").strip()

        if logic == "done" and notes and DONE_FORBIDDEN_NOTES.search(notes):
            errors.append(f"{rpc}: logic_status=done but notes contradict: {notes[:60]}")

        if logic == "partial" and not notes:
            errors.append(f"{rpc}: logic_status=partial requires non-empty notes")

        if logic not in ("none", "partial", "done"):
            errors.append(f"{rpc}: unknown logic_status={logic}")

        if auto == "y" and not dt and rpc not in AUTO_TEST_ALLOW_EMPTY_DT:
            errors.append(f"{rpc}: auto_test=y requires dt_coverage")

        rpc_status = r.get("rpc_status", "")
        if rpc_status == "done" and logic == "none":
            warnings.append(f"{rpc}: rpc done but logic none")

    if warnings and args.strict:
        errors.extend(warnings)
    elif warnings:
        for w in warnings:
            print(f"WARN {w}")

    if errors:
        print("validate_mcp_tools_honesty: FAIL", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"OK honesty rows={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
