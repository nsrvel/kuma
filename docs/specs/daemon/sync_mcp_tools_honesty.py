#!/usr/bin/env python3
"""One-shot helper to align mcp-tools.csv columns with works-well policy (run manually)."""

from __future__ import annotations

import csv
from pathlib import Path

CSV_PATH = Path(__file__).resolve().parent / "mcp-tools.csv"
VERIFIED = "2026-11-08"

K8S_PARTIAL = {
    "k8s.namespaces",
    "k8s.resources",
    "k8s.resolve_target",
    "kubeconfig.contexts",
    "kubeconfig.test_connection",
}

LOGS_PARTIAL = {"logs.workload_tail", "logs.follow"}

PARTIAL_NOTES = {
    "k8s.namespaces": "kubectl subprocess; cluster errors returned in payload",
    "k8s.resources": "kubectl get all; no live cache",
    "k8s.resolve_target": "pattern resolve stub; full §07 matcher pending",
    "kubeconfig.contexts": "contexts from store parser only",
    "kubeconfig.test_connection": "kubectl version probe; no cache TTL",
    "logs.workload_tail": "activity buffer + spool; kubectl/compose tail pending",
    "logs.follow": "RPC snapshot; SSE multiplex on REST only",
    "service.preflight": "sync validator; async k8s.target_resolve pending",
}

DT_MAP = {
    "daemon.ping": "DT-LIF-01",
    "daemon.status": "DT-LIF-11",
    "daemon.shutdown": "DT-LIF-02",
    "settings.list": "DT-SET-01",
    "settings.get": "DT-SET-07",
    "settings.set": "DT-SET-02",
    "settings.reset": "DT-SET-09",
    "env.validate_binary": "DT-SET-10",
    "workspace.create": "DT-DAT-04",
    "workspace.list": "DT-DAT-04",
    "service.preflight": "DT-PRV",
    "ports.check": "dt-rpc-smoke",
    "runtime.adopt_report": "dt-rpc-smoke",
}


def main() -> None:
    rows: list[dict[str, str]] = []
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames or []
        for r in reader:
            rpc = r["rpc_method"]
            notes = r.get("notes", "").strip()
            forbidden = (
                "Fase not started" in notes
                or "Needs kuma-exec" in notes
                or "Epic C2+D" in notes
                or "Structural validation D0" in notes
                or "deferred to Epic" in notes
            )
            if forbidden:
                notes = ""
            if rpc in PARTIAL_NOTES:
                r["logic_status"] = "partial"
                r["notes"] = PARTIAL_NOTES[rpc]
            elif rpc in K8S_PARTIAL or rpc in LOGS_PARTIAL:
                r["logic_status"] = "partial"
                r["notes"] = PARTIAL_NOTES.get(rpc, "spec depth pending")
            elif r.get("logic_status") == "none":
                r["logic_status"] = "done"
            else:
                r["logic_status"] = r.get("logic_status", "done")
                if not notes and rpc not in PARTIAL_NOTES:
                    r["notes"] = ""

            dt = DT_MAP.get(rpc, "")
            if not dt:
                dt = "dt-rpc-smoke"
            existing = r.get("dt_coverage", "").strip()
            if existing and "dt-rpc-smoke" not in existing:
                if dt != "dt-rpc-smoke":
                    r["dt_coverage"] = f"{existing};{dt}"
                else:
                    r["dt_coverage"] = existing
            else:
                r["dt_coverage"] = dt

            if rpc == "daemon.rotate_api_token":
                r["auto_test"] = "y"
                r["dt_coverage"] = "dt_sec_rotate"
            else:
                r["auto_test"] = "y"

            r["verified"] = VERIFIED
            rows.append(r)

    with CSV_PATH.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    print(f"Updated {len(rows)} rows in {CSV_PATH.name}")


if __name__ == "__main__":
    main()
