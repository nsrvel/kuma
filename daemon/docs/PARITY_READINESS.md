# Daemon 2.0.0 parity readiness (gate checklist)

| Check | Status |
|-------|--------|
| `validate_mcp_tools_csv.py --strict` | Green |
| `validate_mcp_tools_honesty.py --strict` | Green |
| `check_traceability.py` | Green |
| `cargo test --workspace` | Green |
| `cargo clippy -D warnings` | Green |
| `cargo llvm-cov --fail-under-lines 72` (CI milestone) | Target **90%** — runner/service store depth next |
| Swift `Kuma/` cutover | Out of scope until explicit gate |

## Works-well (mcp-tools.csv)

- **`logic_status=partial` (4):** `k8s.namespaces`, `k8s.resources`, `logs.follow`, `service.preflight`
- **`auto_test=y`:** smoke + module DT (`dt_kube`, `dt_log_workload`, `dt_prv_delete`, …)

## Residual spec depth

- Live k8s discovery cache; RPC `logs.follow` event multiplex
- `service.preflight` async `k8s.target_resolve`
- Line coverage push to **90%** (`runner.rs`, `service/mod.rs`, `rest.rs` SSE)

## Smoke

```bash
cd daemon && cargo test --workspace
python3 ../docs/specs/daemon/validate_mcp_tools_csv.py --strict
python3 ../docs/specs/daemon/validate_mcp_tools_honesty.py --strict
python3 ../docs/specs/daemon/check_traceability.py
cargo llvm-cov --all --exclude kuma-cli --summary-only --fail-under-lines 72
```
