# Daemon 2.0.0 parity readiness (gate checklist)

| Check | Status |
|-------|--------|
| `validate_mcp_tools_csv.py --strict` | Green |
| `validate_mcp_tools_honesty.py --strict` | Green (works-well columns) |
| `check_traceability.py` | Green |
| `cargo test --workspace` | Green |
| `cargo clippy -D warnings` | Green |
| `cargo llvm-cov --fail-under-lines 67` (CI floor) | Green at ~68% lines; **target 90%** — runner/rest depth still red |
| Swift `Kuma/` cutover | Out of scope until explicit gate |

## Works-well (mcp-tools.csv)

- **`logic_status=done`:** no contradictory `notes`; gaps only on `partial` rows (k8s probe, logs workload/follow, preflight async).
- **`auto_test=y`:** every row has `dt_coverage`; registry smoke via `dt_rpc_smoke` (+ module DT tests).
- Honesty scripts: [`validate_mcp_tools_honesty.py`](../../docs/specs/daemon/validate_mcp_tools_honesty.py), column sync [`sync_mcp_tools_honesty.py`](../../docs/specs/daemon/sync_mcp_tools_honesty.py).

## Residual spec depth (partial rows in CSV)

- Full §07 k8s target matcher + connection cache
- `logs.workload_tail` kubectl/compose capture
- RPC `logs.follow` streaming (REST SSE exists)
- Full DT-PRV / DT-DPT / DT-EXE matrices vs 1.x

## Smoke

```bash
cd daemon && cargo test --workspace
python3 ../docs/specs/daemon/validate_mcp_tools_csv.py --strict
python3 ../docs/specs/daemon/validate_mcp_tools_honesty.py --strict
python3 ../docs/specs/daemon/check_traceability.py
cargo llvm-cov --all --exclude kuma-cli --summary-only --fail-under-lines 67
```
