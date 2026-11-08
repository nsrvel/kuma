# Daemon 2.0.0 parity readiness (gate checklist)

| Check | Status |
|-------|--------|
| `validate_mcp_tools_csv.py --strict` | 74 wired + `validate_rest_routes.py` |
| `check_traceability.py` | Registry ↔ CLI/MCP/REST surfaces |
| `cargo test --workspace` | Green |
| `cargo clippy -D warnings` | Green |
| `cargo llvm-cov --fail-under-lines 90` | CI macOS job (`--exclude kuma-cli`) |
| Swift `Kuma/` cutover | **Not in scope** until explicit gate decision |

## Phase 4 delivered

- **SEC (H):** `audit.log` JSONL + rotation, `DispatchContext` (clientKind / reveal gate), peer-uid reject audit, `daemon.status` adoptReport + `restListenAddr`.
- **Provider (I):** `KUMA_PRV_LOCKED` while running/starting/reconnecting; foreign-field subset on `provider.update`; shell/ssh preflight checks.
- **Exec (J):** `starting` / `stopping` / `reconnecting` states; compose `-f` path; k8s `KUBECONFIG` + `--context`; spool adoption count on boot.
- **Logs (K):** `LogBuffer::subscribe` + live REST logs SSE (tail snapshot + push).
- **REST/CLI (L):** HTTP status map (404/409/422 subset), `kuma workspace get-image`, `kuma kubeconfig list`, LaunchAgent install/uninstall wired.
- **Tests (M):** `dt_sec_audit`, `dt_prv_lock`, `dt_log_subscribe`.
- **Follow-up slice:** live events SSE multiplex (`EventBus::live_subscribe`); MCP `clientKind`; `runtime_process` upsert/clear on exec start/stop/restart.

## Earlier phases

- **REST:** CSV-driven [`rest_registry.rs`](../crates/kuma-daemon/src/rest_registry.rs) + fallback router (~73 routes), auth Host/Origin/revealSecrets, SSE for events + logs follow.
- **SEC at rest:** encrypt provider/kube fields; redact on wire; `get_for_exec` decrypt.
- **Exec:** auto-reconnect (3 attempts) for shell/ssh/kubernetes.
- **DataPort / CLI subset** — see prior PR #17 notes.

## Known gaps (honest vs §5 gate)

- Full §05 provider validator + DT-PRV matrix
- Supervisor / compose DEV-75 depth; boot-time PID adoption into `runtime_process` (start/stop persist pid only)
- Full spec §02 audit field catalog + token rotation SSE close
- Remaining INV-D / DT rows in 00–15

## Smoke

```bash
cd daemon && cargo test --workspace
python3 ../docs/specs/daemon/validate_mcp_tools_csv.py --strict
python3 ../docs/specs/daemon/validate_rest_routes.py
KUMA_REST=1 cargo run -p kuma-cli -- daemon run &
TOKEN=$(tr -d '\n' < "$KUMA_DATA_DIR/api-token")
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:9364/v1/daemon/ping
```
