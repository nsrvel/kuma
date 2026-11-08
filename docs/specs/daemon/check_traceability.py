#!/usr/bin/env python3
"""Verify RPC method traceability across daemon spec documents.

The authoritative RPC name list is section 5 (subsections 5.1–5.6) of
``00-overview-and-conventions.md``. Every registered method must appear in:

- ``11-cli.md`` — Appendix A (RPC ↔ CLI)
- ``12-mcp.md`` — Appendix A (RPC | CLI | MCP tool name)
- ``13-rest-api.md`` — §10 RPC | CLI | MCP | REST mapping

When ``15-traceability-and-parity.md`` exists, its parity matrix is checked the
same way (first column = RPC method).

Usage (from repository root or any directory)::

    python3 docs/specs/daemon/check_traceability.py
    python3 docs/specs/daemon/check_traceability.py --warn-feat-parity

Exit codes:

- ``0`` — all registry methods present on CLI; all non-socket-only methods on MCP and REST
- ``1`` — one or more registry methods missing from a surface, or extra RPC
  rows not in the registry

With ``--warn-feat-parity``, emit warnings (stdout) for feature-table rows whose
tag contains ``PARITY`` (excluding ``PARITY-infra``) when listed RPC methods
are absent from any surface; warnings do not change the exit code unless a
hard error is also present.

Stdlib only; no configuration files required.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SPEC_DIR = Path(__file__).resolve().parent

# Methods in 00 §5 that MUST NOT be exposed on REST or MCP (CLI only over Unix socket).
SOCKET_ONLY: frozenset[str] = frozenset({"daemon.rotate_api_token"})
RPC_IN_BACKTICKS = re.compile(r"`([a-z][a-z0-9_]*(?:\.[a-z0-9_]*)+)`")
REGISTRY_ROW = re.compile(
    r"^\|\s*`([a-z][a-z0-9_]*(?:\.[a-z0-9_]*)+)`\s*\|"
)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def section_after_heading(text: str, heading: str) -> str:
    """Return markdown lines after ``heading`` until the next ``## `` section."""
    idx = text.find(heading)
    if idx < 0:
        return ""
    rest = text[idx + len(heading) :]
    lines: list[str] = []
    for line in rest.splitlines():
        if line.startswith("## ") and lines:
            break
        lines.append(line)
    return "\n".join(lines)


def slice_registry_block(text: str) -> str:
    start = text.find("## 5. RPC method name registry")
    if start < 0:
        return ""
    start += len("## 5. RPC method name registry")
    end = text.find("### 5.7", start)
    if end < 0:
        end = text.find("## 6.", start)
    if end < 0:
        end = len(text)
    return text[start:end]


def parse_registry(text: str) -> set[str]:
    block = slice_registry_block(text)
    methods: set[str] = set()
    for line in block.splitlines():
        m = REGISTRY_ROW.match(line.strip())
        if m:
            methods.add(m.group(1))
    return methods


def parse_markdown_table_rpc_column(text: str, section_heading: str) -> set[str]:
    block = section_after_heading(text, section_heading)
    methods: set[str] = set()
    for line in block.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        if re.match(r"^\|\s*-+\s*\|", stripped):
            continue
        m = REGISTRY_ROW.match(stripped)
        if m:
            methods.add(m.group(1))
    return methods


def parse_rest_section10(text: str) -> set[str]:
    return parse_markdown_table_rpc_column(
        text,
        "## 10. RPC | CLI | MCP | REST mapping",
    )


def parse_optional_traceability_15() -> set[str] | None:
    path = SPEC_DIR / "15-traceability-and-parity.md"
    if not path.is_file():
        return None
    text = read_text(path)
    for heading in (
        "## Appendix A — RPC",
        "## RPC traceability matrix",
        "## Traceability matrix",
    ):
        methods = parse_markdown_table_rpc_column(text, heading)
        if methods:
            return methods
    block = section_after_heading(text, "## 8. RPC wire index")
    methods: set[str] = set()
    for line in block.splitlines():
        m = REGISTRY_ROW.match(line.strip())
        if m:
            methods.add(m.group(1))
    if methods:
        return methods
    # Document points at 13 §10; no duplicate matrix required.
    return None


def expand_rpc_patterns(patterns: str, registry: set[str]) -> set[str]:
    out: set[str] = set()
    for part in re.split(r"[,;]\s*|\s+and\s+", patterns):
        part = part.strip().strip("—").strip("-").strip()
        if not part or part in ("—", "-", "all", "…", "..."):
            continue
        for match in RPC_IN_BACKTICKS.finditer(part):
            name = match.group(1)
            if name.endswith(".*"):
                prefix = name[:-2]
                out.update(m for m in registry if m.startswith(prefix + "."))
            elif "*" in name:
                continue
            else:
                out.add(name)
        if ".*" in part and not RPC_IN_BACKTICKS.search(part):
            prefix = part.replace(".*", "").strip("`")
            out.update(m for m in registry if m.startswith(prefix + "."))
    return out


def warn_feat_parity(registry: set[str], cli: set[str], mcp: set[str], rest: set[str]) -> list[str]:
    warnings: list[str] = []
    feat_row = re.compile(
        r"^\|\s*(FEAT-[A-Z0-9-]+)\s*\|\s*([^|]+)\|\s*[^|]*\|\s*[^|]*\|\s*([^|]*)\|"
    )
    for path in sorted(SPEC_DIR.glob("*.md")):
        if path.name.startswith(("00-", "10-", "11-", "12-", "13-", "15-")):
            continue
        text = read_text(path)
        for line in text.splitlines():
            m = feat_row.match(line.strip())
            if not m:
                continue
            feat_id, tag, rpc_col = m.group(1), m.group(2).strip(), m.group(3).strip()
            if "PARITY" not in tag or "PARITY-infra" in tag:
                continue
            if rpc_col in ("—", "-", ""):
                continue
            if "all" in rpc_col.lower() and "rpc" not in rpc_col.lower():
                continue
            methods = expand_rpc_patterns(rpc_col, registry)
            if not methods:
                continue
            for method in sorted(methods):
                if method not in registry:
                    continue
                missing = []
                if method not in cli:
                    missing.append("CLI")
                if method not in mcp:
                    missing.append("MCP")
                if method not in rest:
                    missing.append("REST")
                if missing:
                    warnings.append(
                        f"{path.name}: {feat_id} lists `{method}` missing {', '.join(missing)}"
                    )
    return warnings


def compare_surface(
    label: str,
    registry: set[str],
    found: set[str],
    errors: list[str],
) -> None:
    missing = sorted(registry - found)
    extra = sorted(found - registry)
    for method in missing:
        errors.append(f"{label}: missing registry RPC `{method}`")
    for method in extra:
        errors.append(f"{label}: `{method}` not in 00 §5 registry")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--warn-feat-parity",
        action="store_true",
        help="warn when PARITY-tagged FEAT rows reference RPCs missing from a surface",
    )
    args = parser.parse_args()

    overview = read_text(SPEC_DIR / "00-overview-and-conventions.md")
    registry = parse_registry(overview)
    if not registry:
        print("error: no RPC methods parsed from 00 §5 registry", file=sys.stderr)
        return 1

    cli = parse_markdown_table_rpc_column(
        read_text(SPEC_DIR / "11-cli.md"),
        "## Appendix A — RPC ↔ CLI mapping (authoritative)",
    )
    mcp = parse_markdown_table_rpc_column(
        read_text(SPEC_DIR / "12-mcp.md"),
        "## Appendix A — RPC | CLI | MCP tool name",
    )
    rest = parse_rest_section10(read_text(SPEC_DIR / "13-rest-api.md"))
    trace15 = parse_optional_traceability_15()

    errors: list[str] = []
    remote_registry = registry - SOCKET_ONLY
    compare_surface("11-cli.md Appendix A", registry, cli, errors)
    compare_surface("12-mcp.md Appendix A", remote_registry, mcp - SOCKET_ONLY, errors)
    compare_surface("13-rest-api.md §10", remote_registry, rest - SOCKET_ONLY, errors)
    if trace15 is not None:
        compare_surface("15-traceability-and-parity.md", registry, trace15, errors)

    print(f"Registry (00 §5): {len(registry)} methods")
    print(f"  CLI appendix: {len(cli)}")
    print(f"  MCP appendix: {len(mcp)}")
    print(f"  REST §10:     {len(rest)}")
    if trace15 is not None:
        print(f"  15 matrix:    {len(trace15)}")

    if args.warn_feat_parity:
        for msg in warn_feat_parity(registry, cli, mcp, rest):
            print(f"warning: {msg}")

    if errors:
        print("\nFailures:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("OK: registry RPCs traceable (CLI full set; MCP/REST exclude socket-only).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
