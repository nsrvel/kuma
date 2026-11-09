#!/usr/bin/env python3
"""Cross-check mcp-tools.csv against kuma-application dispatch wiring.

Exit 0 when every wired method has rpc_status=done (or partial where noted) and
every rpc_status=done row is actually wired.

Usage:
    python3 docs/specs/daemon/validate_mcp_tools_csv.py
    python3 docs/specs/daemon/validate_mcp_tools_csv.py --strict
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
DISPATCH = REPO / "daemon/crates/kuma-application/src/dispatch.rs"
METHODS = REPO / "daemon/crates/kuma-protocol/src/methods.rs"
CSV_PATH = Path(__file__).resolve().parent / "mcp-tools.csv"

CONST_USE = re.compile(r"methods::([A-Z0-9_]+)")
CONST_DEF = re.compile(r'^pub const ([A-Z0-9_]+): &str = "([^"]+)";', re.MULTILINE)

PARTIAL_RPC = frozenset(
    {
        "daemon.status",
        "daemon.shutdown",
        "service.list",
        "service.create",
        "service.get",
        "service.update",
        "service.delete",
        "service.duplicate",
        "service.set_starred",
        "service.set_disabled",
        "service.set_groups",
        "service.toggle_group",
        "service.switch_provider",
        "service.preflight",
        "events.subscribe",
        "k8s.namespaces",
        "k8s.resources",
        "logs.follow",
    }
)


def load_const_to_method() -> dict[str, str]:
    text = METHODS.read_text(encoding="utf-8")
    return {m.group(1): m.group(2) for m in CONST_DEF.finditer(text)}


def wired_methods() -> set[str]:
    text = DISPATCH.read_text(encoding="utf-8")
    mapping = load_const_to_method()
    out: set[str] = set()
    for m in CONST_USE.finditer(text):
        name = m.group(1)
        if name in mapping:
            out.add(mapping[name])
    return out


def load_csv() -> list[dict[str, str]]:
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail if rpc_status=done but logic_status=partial without allowed list",
    )
    args = parser.parse_args()

    wired = wired_methods()
    rows = load_csv()
    errors: list[str] = []

    done_in_csv = {r["rpc_method"] for r in rows if r.get("rpc_status") == "done"}

    for m in sorted(wired):
        if m not in done_in_csv:
            errors.append(f"wired but csv rpc_status!=done: {m}")

    for r in rows:
        rpc = r["rpc_method"]
        status = r.get("rpc_status", "none")
        logic = r.get("logic_status", "none")
        if status == "done" and rpc not in wired:
            errors.append(f"csv done but not wired: {rpc}")
        if args.strict and status == "done" and logic == "partial" and rpc not in PARTIAL_RPC:
            errors.append(f"done+partial not allowed: {rpc}")

    if args.strict:
        try:
            import subprocess

            proc = subprocess.run(
                [sys.executable, str(CSV_PATH.parent / "validate_rest_routes.py")],
                cwd=REPO,
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0:
                errors.append(proc.stderr.strip() or "validate_rest_routes failed")
        except OSError as e:
            errors.append(f"validate_rest_routes: {e}")

    if errors:
        print("validate_mcp_tools_csv: FAIL", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        print(f"\nwired={len(wired)} done_rows={len(done_in_csv)}", file=sys.stderr)
        return 1

    print(f"OK wired={len(wired)} csv_done={len(done_in_csv)} rows={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
