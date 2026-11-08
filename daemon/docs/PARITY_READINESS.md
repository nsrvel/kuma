# Daemon 2.0.0 parity readiness (gate checklist)

| Check | Status |
|-------|--------|
| `validate_mcp_tools_csv.py --strict` | 74 wired + `validate_rest_routes.py` |
| `check_traceability.py` | Registry ↔ CLI/MCP/REST surfaces |
| `cargo test --workspace` | Green |
| `cargo clippy -D warnings` | Green |
| `cargo llvm-cov --fail-under-lines 90` | CI macOS job (`--exclude kuma-cli`) |
| Swift `Kuma/` cutover | **Not in scope** until explicit gate decision |

## Phases 5–12 delivered (this stack)

- **Provider (5):** `configuration_issues`, `display_name` / compose image extract, URL normalize, source conflict + exclusivity, port applicability, expanded preflight.
- **Exec (6):** `StateSupervisor` debounce → `service.state_changed`, boot `adopt_candidates`, `runtime_process` delete on stop, adoption report detail.
- **Runners (7):** DEV-75 ephemeral compose path, compose down on stop, existing k8s/ssh/tunnel/pollers.
- **SEC (8):** `token.rotated` audit, REST epoch closes SSE, corrupt `master.key` recovery, Unix-only rotate.
- **K8s (9):** `k8s.*` kubectl subprocess handlers (existing crate).
- **Logs/events (10):** workload spool tail, live events test, REST SSE token epoch.
- **Surfaces (12):** `kuma service preflight`, `kuma runtime adopt-report`.

## Known gaps (honest vs full §5 matrix)

- Full DT-PRV / DT-EXE / DT-SEC row coverage (hundreds of spec rows; subset covered by `dt_*` tests).
- Full `ExecutionSupervisor` 500ms max-wait + compose stack adoption (§3.9).
- REST `events/ws` optional route; RPC `logs.follow` streaming subscription id.
- DataPort DT-DPT full matrix.
- Swift client cutover.

## Smoke

```bash
cd daemon && cargo test --workspace
python3 ../docs/specs/daemon/validate_mcp_tools_csv.py --strict
python3 ../docs/specs/daemon/validate_rest_routes.py
python3 ../docs/specs/daemon/check_traceability.py
KUMA_REST=1 cargo run -p kuma-cli -- daemon run &
TOKEN=$(tr -d '\n' < "$KUMA_DATA_DIR/api-token")
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:9364/v1/daemon/ping
```
