# MCP tools checklist (`mcp-tools.csv`)

Catalog of planned MCP tools and their RPC/REST mapping. **Status columns track the Rust V2 daemon** (`daemon/`), not the Swift 1.x app.

## How to read status columns

| Column | Values | Meaning |
|--------|--------|---------|
| `rpc_status` | `none` \| `partial` \| `done` | Is the JSON-RPC method wired in `kuma-application` dispatch and returning real data? |
| `logic_status` | `none` \| `partial` \| `done` | Business/storage logic exists even if RPC is missing (e.g. validators in `kuma-store`). |
| `dt_coverage` | IDs or empty | Acceptance tests that exist and pass in `cargo test` (semicolon-separated). |
| `auto_test` | `y` \| `n` \| `partial` | Covered by automated tests (unit, integration, or store tests). |
| `manual_smoke` | `y` \| `n` \| `—` | Known good via Unix socket / client smoke (not necessarily automated). |
| `mcp_wired` | `y` \| `n` | `kuma mcp` exposes this tool (post parity gate). |
| `rest_wired` | `y` \| `n` | REST adapter implemented. |
| `cli_wired` | `y` \| `n` | Dedicated `kuma …` subcommand (not just raw JSON-RPC). |
| `verified` | ISO date | Last row review against codebase/tests. |
| `notes` | text | Gaps, partial behavior, phase tags. |

**Works-well gate:** `logic_status=done` requires honest `notes` (no placeholder “Fase not started”), `auto_test=y` requires `dt_coverage`, and `python3 docs/specs/daemon/validate_mcp_tools_honesty.py --strict` must pass. Bulk column sync: `python3 docs/specs/daemon/sync_mcp_tools_honesty.py`.

**Update this file** when a phase lands (change `rpc_status` / tests, bump `verified`).

Quick verify:

```bash
cd daemon && cargo test --workspace
```

Implemented RPC methods today: see `daemon/crates/kuma-application/src/dispatch.rs`.
