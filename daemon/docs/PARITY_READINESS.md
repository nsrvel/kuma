# Daemon 2.0.0 parity readiness (gate checklist)

| Check | Status |
|-------|--------|
| `validate_mcp_tools_csv.py --strict` | 74 wired + `validate_rest_routes.py` |
| `check_traceability.py` | Registry ↔ CLI/MCP/REST surfaces |
| `cargo test --workspace` | Green |
| `cargo clippy -D warnings` | Green |
| `cargo llvm-cov --fail-under-lines 90` | CI macOS job (`--exclude kuma-cli`) |
| Swift `Kuma/` cutover | **Not in scope** until explicit gate decision |

## Phase 2 delivered

- **REST:** CSV-driven [`rest_registry.rs`](../crates/kuma-daemon/src/rest_registry.rs) + fallback router (~73 routes), auth Host/Origin/revealSecrets, SSE for events + logs follow.
- **SEC:** encrypt `sshPassword` / `ngrokAuthToken` + kube `configContent` at rest; redact on wire; `get_for_exec` decrypt.
- **Exec:** auto-reconnect for shell/ssh/kubernetes (3 attempts per start).
- **REST:** `GET /v1/workspaces/{id}/image` returns raw `image/png`.
- **Logs:** disk spool under runtime `logs/*.ndjson`, `logs.follow` / `workload_tail` live.
- **Exec:** run records + `workspace.delete` stops services first.
- **DataPort:** `dt_dataport` golden; factory reset preserves `master.key`.
- **CLI:** `kuma workspace list`, `kuma service start|stop`.

## Smoke

```bash
cd daemon && cargo test --workspace
python3 ../docs/specs/daemon/validate_mcp_tools_csv.py --strict
python3 ../docs/specs/daemon/validate_rest_routes.py
KUMA_REST=1 cargo run -p kuma-cli -- daemon run &
TOKEN=$(tr -d '\n' < "$KUMA_DATA_DIR/api-token")
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:9364/v1/daemon/ping
```
