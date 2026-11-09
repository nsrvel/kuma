#!/usr/bin/env python3
"""Generate mcp-tools.csv from daemon specs (00 purpose, 12 MCP names, 13 REST).

Usage (repo root or any cwd)::

    python3 docs/specs/daemon/export_mcp_tools_csv.py
    python3 docs/specs/daemon/export_mcp_tools_csv.py -o /tmp/out.csv

Stdlib only. Regenerate after changing 12 Appendix A or 13 §10.

Output: one row per **00 §5** RPC (74). Column ``surface`` is ``mcp,rest,cli`` or ``cli_only``
(socket-only RPCs have empty ``mcp_tool`` / ``rest_endpoint``).

Implementation checklist columns (``rpc_status`` … ``notes``) are **preserved** from the
existing output file when present; see ``mcp-tools.README.md``.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

SPEC_DIR = Path(__file__).resolve().parent

SOCKET_ONLY: frozenset[str] = frozenset({"daemon.rotate_api_token"})

REGISTRY_ROW = re.compile(
    r"^\|\s*`([a-z][a-z0-9_]*(?:\.[a-z0-9_]*)+)`\s*\|\s*[^|]*\|\s*([^|]+)\|"
)
APPENDIX_ROW = re.compile(
    r"^\|\s*`([a-z][a-z0-9_]*(?:\.[a-z0-9_]*)+)`\s*\|\s*[^|]*\|\s*([^|]+?)\s*\|"
)
REST_ROW = re.compile(
    r"^\|\s*`([a-z][a-z0-9_]*(?:\.[a-z0-9_]*)+)`\s*\|\s*[^|]*\|\s*[^|]*\|\s*([^|]+?)\s*\|"
)

CATALOG_FIELDS = ["module", "surface", "mcp_tool", "description", "rest_endpoint", "rpc_method"]

STATUS_FIELDS = [
    "rpc_status",
    "logic_status",
    "dt_coverage",
    "auto_test",
    "manual_smoke",
    "mcp_wired",
    "rest_wired",
    "cli_wired",
    "verified",
    "notes",
]

DEFAULT_STATUS: dict[str, str] = {
    "rpc_status": "none",
    "logic_status": "none",
    "dt_coverage": "",
    "auto_test": "n",
    "manual_smoke": "—",
    "mcp_wired": "n",
    "rest_wired": "n",
    "cli_wired": "n",
    "verified": "",
    "notes": "",
}


def load_status_by_rpc(path: Path) -> dict[str, dict[str, str]]:
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            return {}
        out: dict[str, dict[str, str]] = {}
        for row in reader:
            rpc = row.get("rpc_method", "")
            if not rpc:
                continue
            out[rpc] = {k: row.get(k, "") for k in STATUS_FIELDS if k in row}
        return out


MODULE_LABELS: dict[str, str] = {
    "daemon": "Daemon",
    "settings": "Settings",
    "env": "Environment",
    "workspace": "Workspace",
    "group": "Group",
    "service": "Service",
    "provider": "Provider",
    "ports": "Execution",
    "runtime": "Execution",
    "kubeconfig": "Kubernetes",
    "k8s": "Kubernetes",
    "logs": "Logs",
    "events": "Events",
    "data": "DataPort",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def slice_registry_block(text: str) -> str:
    start = text.find("## 5. RPC method name registry")
    if start < 0:
        return ""
    start += len("## 5. RPC method name registry")
    end = text.find("### 5.7", start)
    if end < 0:
        end = text.find("## 6.", start)
    return text[start:end] if end >= 0 else text[start:]


def parse_purposes(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in slice_registry_block(text).splitlines():
        m = REGISTRY_ROW.match(line.strip())
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def section_after_heading(text: str, heading: str) -> str:
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


def parse_mcp_appendix(text: str) -> dict[str, str]:
    block = section_after_heading(text, "## Appendix A — RPC | CLI | MCP tool name")
    out: dict[str, str] = {}
    for line in block.splitlines():
        m = APPENDIX_ROW.match(line.strip())
        if not m:
            continue
        rpc, tool = m.group(1), m.group(2).strip()
        if tool.startswith("—") or tool.startswith("-"):
            continue
        if "`" in tool:
            tool = tool.strip("`")
        out[rpc] = tool
    return out


def parse_rest_mapping(text: str) -> dict[str, str]:
    block = section_after_heading(text, "## 10. RPC | CLI | MCP | REST mapping")
    out: dict[str, str] = {}
    for line in block.splitlines():
        m = REST_ROW.match(line.strip())
        if not m:
            continue
        rpc, rest = m.group(1), m.group(2).strip()
        rest = rest.replace("`", "")
        if rest.startswith("—") or "not exposed" in rest.lower():
            rest = ""
        out[rpc] = rest
    return out


def strip_md(text: str) -> str:
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    return text.strip()


def module_for(rpc: str) -> str:
    prefix = rpc.split(".", 1)[0]
    return MODULE_LABELS.get(prefix, prefix.capitalize())


def build_rows() -> list[dict[str, str]]:
    purposes = parse_purposes(read_text(SPEC_DIR / "00-overview-and-conventions.md"))
    mcp = parse_mcp_appendix(read_text(SPEC_DIR / "12-mcp.md"))
    rest = parse_rest_mapping(read_text(SPEC_DIR / "13-rest-api.md"))

    rows: list[dict[str, str]] = []
    for rpc in sorted(purposes.keys()):
        if rpc in SOCKET_ONLY:
            rows.append(
                {
                    "module": module_for(rpc),
                    "surface": "cli_only",
                    "mcp_tool": "",
                    "description": strip_md(purposes.get(rpc, "")),
                    "rest_endpoint": "",
                    "rpc_method": rpc,
                }
            )
            continue
        tool = mcp.get(rpc, "")
        if not tool:
            raise ValueError(f"missing MCP tool in 12 Appendix A for registry RPC {rpc!r}")
        rows.append(
            {
                "module": module_for(rpc),
                "surface": "mcp,rest,cli",
                "rpc_method": rpc,
                "mcp_tool": tool,
                "description": strip_md(purposes.get(rpc, "")),
                "rest_endpoint": rest.get(rpc, ""),
            }
        )
    rows.sort(key=lambda r: (r["module"], r["rpc_method"]))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=SPEC_DIR / "mcp-tools.csv",
        help="Output CSV path (default: docs/specs/daemon/mcp-tools.csv)",
    )
    args = parser.parse_args()

    try:
        rows = build_rows()
    except ValueError as exc:
        print(f"error: {exc}", file=__import__("sys").stderr)
        return 1

    text00 = read_text(SPEC_DIR / "00-overview-and-conventions.md")
    registry = set(parse_purposes(text00))
    csv_rpc = {r["rpc_method"] for r in rows}
    if csv_rpc != registry:
        missing = sorted(registry - csv_rpc)
        extra = sorted(csv_rpc - registry)
        print("error: CSV/registry mismatch", file=__import__("sys").stderr)
        if missing:
            print("  missing from CSV:", missing, file=__import__("sys").stderr)
        if extra:
            print("  extra in CSV:", extra, file=__import__("sys").stderr)
        return 1

    mcp_rows = sum(1 for r in rows if r["surface"] == "mcp,rest,cli")
    cli_only = len(rows) - mcp_rows

    args.output.parent.mkdir(parents=True, exist_ok=True)
    preserved = load_status_by_rpc(args.output)
    fieldnames = CATALOG_FIELDS + STATUS_FIELDS
    for row in rows:
        rpc = row["rpc_method"]
        status = {**DEFAULT_STATUS, **preserved.get(rpc, {})}
        if not status.get("verified") and rpc in preserved:
            status["verified"] = preserved[rpc].get("verified", "")
        row.update(status)

    with args.output.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    print(
        f"Wrote {len(rows)} rows to {args.output} "
        f"({mcp_rows} mcp,rest,cli + {cli_only} cli_only)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
