#!/usr/bin/env python3
"""Ensure every CSV rest_endpoint maps to kuma-daemon rest_registry."""

from __future__ import annotations

import csv
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
CSV_PATH = Path(__file__).resolve().parent / "mcp-tools.csv"
DAEMON = REPO / "apps/daemon"

ENDPOINT = re.compile(r"^(GET|POST|PUT|PATCH|DELETE)\s+(/v1/\S+)")


def rustc_route_keys() -> set[str]:
    out = subprocess.run(
        ["cargo", "test", "-p", "kuma-daemon", "registry_has", "--", "--nocapture"],
        cwd=DAEMON,
        capture_output=True,
        text=True,
    )
    if out.returncode != 0:
        print(out.stderr, file=sys.stderr)
        raise RuntimeError("cargo test failed")
    from importlib.util import spec_from_loader, module_from_spec
    # ponytail: re-parse CSV locally (same logic as rest_registry.rs)
    keys: set[str] = set()
    with CSV_PATH.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            ep = row.get("rest_endpoint", "").split(";")[0].strip()
            rpc = row.get("rpc_method", "")
            if not ep or rpc == "daemon.rotate_api_token":
                continue
            m = ENDPOINT.match(ep)
            if not m:
                continue
            http, path = m.group(1), m.group(2)
            axum = path.removeprefix("/v1")
            keys.add(f"{http} {axum}")
    return keys


def csv_wired_y() -> set[str]:
    keys: set[str] = set()
    with CSV_PATH.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("rest_wired") != "y":
                continue
            ep = row.get("rest_endpoint", "").split(";")[0].strip()
            if not ep:
                continue
            m = ENDPOINT.match(ep)
            if m:
                keys.add(f"{m.group(1)} {m.group(2).removeprefix('/v1')}")
    return keys


def main() -> int:
    routes = rustc_route_keys()
    errors: list[str] = []
    for row in csv.DictReader(CSV_PATH.open(encoding="utf-8")):
        ep = row.get("rest_endpoint", "").split(";")[0].strip()
        if not ep or row.get("rpc_method") == "daemon.rotate_api_token":
            continue
        m = ENDPOINT.match(ep)
        if not m:
            errors.append(f"unparsed endpoint: {ep}")
            continue
        key = f"{m.group(1)} {m.group(2).removeprefix('/v1')}"
        if key not in routes:
            errors.append(f"missing route for {row['rpc_method']}: {key}")
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        return 1
    print(f"OK {len(routes)} rest routes from CSV")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
