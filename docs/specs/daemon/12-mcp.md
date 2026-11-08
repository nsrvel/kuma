# Daemon Spec 12: `kuma mcp` (Model Context Protocol)

> **Status:** Draft for implementation  
> **Area codes:** `MCP` (surface), consumes `RPC` ([10](10-rpc-protocol.md))  
> **Audience:** Engineers implementing MCP on top of `kuma-client` and the RPC catalog  
> **Depends on:** [00](00-overview-and-conventions.md) (RPC registry §5, GR-05), [02](02-security-and-secrets.md) (no secrets over MCP), [11](11-cli.md) (CLI parity), [10](10-rpc-protocol.md) (wire schemas)  
> **Cross-references:** [08](08-logs-and-events.md) (events, `logs.follow`), [14](14-lifecycle-and-platform.md) (daemon lifecycle)

---

## 1. Purpose and scope

This spec defines the **`kuma mcp`** subcommand: an MCP server that exposes **tools** mapped 1:1 to JSON-RPC methods in [00 §5](00-overview-and-conventions.md), optional **resources** for read-only snapshots, **stdio** transport, and error mapping consistent with the CLI and daemon.

In scope:

- Process model: MCP host launches `kuma mcp`; server speaks MCP over stdin/stdout; connects to the running daemon via Unix socket (same resolution as [11 §3.3](11-cli.md)).
- Tool naming, input JSON Schema shapes (mirroring RPC `params`), result mapping (RPC `result` → tool content).
- Parity table: RPC | CLI | MCP tool name (Appendix A). Spreadsheet export: [mcp-tools.csv](mcp-tools.csv) (regenerate via [export_mcp_tools_csv.py](export_mcp_tools_csv.py); checklist columns documented in [mcp-tools.README.md](mcp-tools.README.md)).

Out of scope: REST ([13](13-rest-api.md)), SwiftUI, MCP host configuration (Cursor, Claude Desktop). Implementation crate (`rmcp` or equivalent) is an implementation choice; behavior is normative here.

**Entry stub (scaffold):** `daemon/kuma/src/main.rs:19-20,46-48` exits with `` `kuma mcp` not implemented yet `` until parity gate; this spec is the target contract.

Tags: **[V2-ADD]** (MCP did not exist in 1.x), **[PARITY]** (each tool mirrors a 1.x capability via RPC).

---

## 2. 1.x source of truth

| Topic | Path |
|-------|------|
| MCP subcommand declaration | `daemon/kuma/src/main.rs:19-20,46-48` |
| Planned stack note | `docs/plans/2026-11-02-kuma-daemon-implementation.md:9` (`rmcp` milestone) |
| RPC catalog | [00 §5](00-overview-and-conventions.md) |
| CLI parity reference | [11](11-cli.md) Appendix A |
| Secret redaction rule | [02](02-security-and-secrets.md), brief GR-04 |
| Event streaming | [08](08-logs-and-events.md) §3.6 |

1.x had no MCP server; tools correspond to app actions reachable only through the daemon RPC surface.

---

## 3. Normative behavior

### 3.1 Launch and transport

1. Host executes: `kuma mcp` with **no arguments** (global client flags from [11](11-cli.md) MAY be supported: `--socket`, env `KUMA_SOCKET`, `KUMA_RUNTIME_DIR` for default path only).
2. MCP **stdio** transport: JSON-RPC messages per [Model Context Protocol](https://modelcontextprotocol.io/) on **stdin** / **stdout**.
3. **stderr** MUST be used only for `tracing` logs (`RUST_LOG`); MUST NOT interleave with MCP frames on stdout.
4. On startup the server MUST connect to the daemon socket; if connection fails, respond to MCP `initialize` with a server error and exit process **1** (same as CLI exit **3** semantics, FEAT-MCP-02).
5. The MCP process MUST NOT call `daemon.shutdown` unless a dedicated tool is invoked by the host (`kuma_daemon_shutdown`).

### 3.2 Daemon bridge

- Each tool call: build JSON-RPC request `{ "jsonrpc":"2.0", "method": "<rpc>", "params": <tool arguments>, "id": N }`, send NDJSON line on Unix socket ([10](10-rpc-protocol.md)).
- Map RPC `result` → MCP tool result `content[]` with `type: "text"` and body = compact JSON string of the result object (FEAT-MCP-04).
- Map RPC `error` → MCP tool error (§3.5).
- **`revealSecrets`:** MCP MUST NOT set `revealSecrets: true` on any call ([02](02-security-and-secrets.md)); kubeconfig/password fields remain redacted booleans/paths.

### 3.3 Tool naming convention

**Rule:** `kuma_` + RPC method with `.` replaced by `_` (snake_case segments).

| RPC | MCP tool name |
|-----|---------------|
| `daemon.ping` | `kuma_daemon_ping` |
| `workspace.set_image` | `kuma_workspace_set_image` |
| `service.start_all` | `kuma_service_start_all` |
| `kubeconfig.test_connection` | `kuma_kubeconfig_test_connection` |
| `logs.workload_tail` | `kuma_logs_workload_tail` |
| `data.export_service_json` | `kuma_data_export_service_json` |

Tool **display titles** (optional): Title Case with spaces replacing underscores after prefix, e.g. `Kuma Service Start`.

**Catalog size:** Exactly **73** tools — one per RPC in [00 §5](00-overview-and-conventions.md). No additional tools without a registry change in 00/10.

### 3.4 Tool input schema

- Each tool's `inputSchema` is the JSON Schema for RPC `params` defined in [10](10-rpc-protocol.md) (object type; `additionalProperties: false` where 10 specifies).
- Property names MUST be **camelCase** on the wire (same as CLI `--params-file`).
- Optional fields match RPC optionality; required fields match RPC required params.
- UUID arguments: JSON strings; daemon accepts any case; tools SHOULD document uppercase canonical form in descriptions.

### 3.5 Error mapping

| Layer | Mapping |
|-------|---------|
| JSON-RPC `error.code` | MCP `isError: true` tool result or protocol error per host |
| JSON-RPC `error.message` | Primary human text in tool result |
| JSON-RPC `error.data.code` (`KUMA_*`) | Duplicate in structured field `kumaCode` inside JSON text body |
| JSON-RPC `error.data.details` | Pass through in JSON text body |
| MCP client timeout | `KUMA_MCP_TIMEOUT` message: `MCP tool timed out waiting for daemon` |
| Method not found (daemon) | Should not occur if versions match; surface as `KUMA_RPC_METHOD_NOT_FOUND` |

**Parity with CLI:** Same daemon errors as [11 §3.5](11-cli.md); MCP does not redefine messages.

### 3.6 Streaming and long-running RPCs

| RPC | MCP exposure |
|-----|----------------|
| `events.subscribe` | Tool `kuma_events_subscribe` returns `{ subscriptionId, ... }` once. Further events are **not** MCP notifications in v1; host must poll via resources (§3.7) or use CLI `kuma events subscribe` (FEAT-MCP-08). |
| `logs.follow` | Tool `kuma_logs_follow` starts follow handle; stream delivery same limitation as subscribe — document in tool description. |
| `events.unsubscribe` | Tool `kuma_events_unsubscribe` |

**GR-05 exception (explicit):** Full event streaming over MCP MAY be added in a future spec revision via MCP notifications; v1 tools return single-shot RPC results only except where RPC itself is single-shot.

### 3.7 Resources (optional read-only)

Resources give hosts cached reads without inventing new RPCs. URI scheme: `kuma://<path>`.

| URI | MIME | Source RPC | Refresh |
|-----|------|------------|---------|
| `kuma://daemon/status` | `application/json` | `daemon.status` | read handler calls RPC each `resources/read` |
| `kuma://settings` | `application/json` | `settings.list` | same |
| `kuma://workspaces` | `application/json` | `workspace.list` | same |
| `kuma://env/dependencies` | `application/json` | `env.dependencies` | same |

Resources MUST NOT include secret material ([02](02-security-and-secrets.md)). No resource wraps `kubeconfig.get` with content.

**List:** MCP `resources/list` returns the four URIs above (FEAT-MCP-06). Additional resources require a spec amendment, not ad hoc URIs.

### 3.8 Capabilities advertisement

MCP `initialize` response capabilities:

- `tools`: list of 73 tools (lazy list OK after `tools/list`).
- `resources`: subscribed if §3.7 implemented.
- No `prompts` in v1.

### 3.9 Versioning

- `serverInfo.name`: `kuma-mcp`
- `serverInfo.version`: same as daemon app version from `daemon.status` when available, else crate version.
- Protocol version: MCP host negotiation; daemon JSON-RPC protocol version from `daemon.ping` (`protocolVersion`, [14 §3.4](14-lifecycle-and-platform.md)).

### 3.10 Parity with CLI

For every RPC, Appendix A gives CLI path ([11](11-cli.md)) and MCP tool name. Arguments accepted by CLI flags MUST be accepted as tool JSON properties with identical keys. CLI-only guards (`data factory-reset --yes`) have **no** MCP equivalent — the tool `kuma_data_factory_reset` requires explicit `confirm: true` bool param in tool input (mirrors CLI guard, ADD-123).

---

## 4. Data shapes

### 4.1 Tool result text body (success)

| Field | Type | JSON key | Notes |
|-------|------|----------|-------|
| (root) | object | — | Exact RPC `result` object serialized |

### 4.2 Tool result text body (error)

| Field | Type | JSON key | Notes |
|-------|------|----------|-------|
| `kumaCode` | string | `kumaCode` | From `error.data.code` |
| `message` | string | `message` | RPC error message |
| `details` | object | `details` | Optional |

### 4.3 Resource read body

| Field | Type | Notes |
|-------|------|-------|
| contents | array | MCP `contents[].text` = RPC result JSON |

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-MCP-01 | V2-ADD | `kuma mcp` stdio MCP server | — | — |
| FEAT-MCP-02 | V2-ADD | Connect to Unix socket via `KUMA_SOCKET` / default | — | — |
| FEAT-MCP-03 | V2-ADD | 73 tools = RPC catalog | — | all [00 §5](00-overview-and-conventions.md) |
| FEAT-MCP-04 | V2-ADD | Tool results = JSON text of RPC result | — | all |
| FEAT-MCP-05 | V2-ADD | No `revealSecrets` on MCP | — | read methods |
| FEAT-MCP-06 | V2-ADD | Resources `kuma://daemon/status`, settings, workspaces, env | — | `daemon.status`, `settings.list`, `workspace.list`, `env.dependencies` |
| FEAT-MCP-07 | V2-ADD | Error mapping to `kumaCode` + message | — | all |
| FEAT-MCP-08 | V2-ADD | Document streaming limits for subscribe/follow | — | `events.subscribe`, `logs.follow` |
| FEAT-MCP-09 | V2-ADD | `kuma_data_factory_reset` requires `confirm: true` | — | `data.factory_reset` |

---

## 6. Error catalog

| ERR code | Condition | Message |
|----------|-----------|---------|
| `KUMA_MCP_CONNECT` | Socket connect failure | `Could not connect to daemon socket: <path>` |
| `KUMA_MCP_TIMEOUT` | Tool RPC exceeded timeout | `MCP tool timed out waiting for daemon` |
| `KUMA_MCP_PROTOCOL` | Invalid MCP frame on stdin | `Invalid MCP message: <detail>` |
| `KUMA_MCP_CONFIRM` | `kuma_data_factory_reset` without `confirm: true` | `Factory reset requires confirm: true` |
| (RPC) | Daemon handler | Pass through `KUMA_*` from RPC |

---

## 7. Deviations

| Id | Summary |
|----|---------|
| ADD-123 | MCP `kuma_data_factory_reset` requires JSON param `confirm: true` (parallel to CLI `--yes`) |
| ADD-124 | MCP v1 does not stream events as MCP notifications; polling/resources only |

No new RPC methods.

---

## 8. Invariants

| Id | Statement |
|----|-----------|
| INV-D-MCP-01 | Tool count = RPC count in [00 §5](00-overview-and-conventions.md) (73). |
| INV-D-MCP-02 | Every tool name is derivable by the §3.3 rule from its RPC method. |
| INV-D-MCP-03 | MCP MUST NOT expose secrets beyond redacted RPC responses. |
| INV-D-MCP-04 | stdout is exclusively MCP protocol bytes; logs go to stderr. |
| INV-D-MCP-05 | Appendix A row count equals Appendix A in [11](11-cli.md). |

---

## 9. Acceptance tests

| Id | Arrange | Assert |
|----|---------|--------|
| DT-MCP-01 | Daemon up; host sends MCP `initialize` | Capabilities include tools |
| DT-MCP-02 | `tools/list` | Exactly 73 tools; names match Appendix A |
| DT-MCP-03 | Call `kuma_daemon_ping` with `{}` | Success JSON contains ping fields |
| DT-MCP-04 | Call `kuma_workspace_list` | Same result as CLI `kuma workspace list --json` |
| DT-MCP-05 | Daemon down | `initialize` or first tool fails connect |
| DT-MCP-06 | `resources/read` `kuma://daemon/status` | JSON matches `daemon.status` |
| DT-MCP-07 | `kuma_kubeconfig_get` without secrets | No plaintext kubeconfig in text body |
| DT-MCP-08 | `kuma_data_factory_reset` `{ }` | `KUMA_MCP_CONFIRM`; no wipe |
| DT-MCP-09 | `check_traceability.py` | MCP column populated for all RPC rows |

---

## Appendix A — RPC | CLI | MCP tool name

| RPC method | CLI command | MCP tool name |
|------------|-------------|---------------|
| `daemon.ping` | `kuma daemon ping` | `kuma_daemon_ping` |
| `daemon.status` | `kuma daemon status` | `kuma_daemon_status` |
| `daemon.shutdown` | `kuma daemon shutdown` | `kuma_daemon_shutdown` |
| `daemon.rotate_api_token` | `kuma daemon rotate-api-token` | — (no MCP tool; socket-only) |
| `settings.list` | `kuma settings list` | `kuma_settings_list` |
| `settings.get` | `kuma settings get` | `kuma_settings_get` |
| `settings.set` | `kuma settings set` | `kuma_settings_set` |
| `settings.reset` | `kuma settings reset` | `kuma_settings_reset` |
| `env.path` | `kuma env path` | `kuma_env_path` |
| `env.resolve_executable` | `kuma env resolve-executable` | `kuma_env_resolve_executable` |
| `env.validate_binary` | `kuma env validate-binary` | `kuma_env_validate_binary` |
| `env.dependencies` | `kuma env dependencies` | `kuma_env_dependencies` |
| `env.refresh` | `kuma env refresh` | `kuma_env_refresh` |
| `workspace.list` | `kuma workspace list` | `kuma_workspace_list` |
| `workspace.get` | `kuma workspace get` | `kuma_workspace_get` |
| `workspace.create` | `kuma workspace create` | `kuma_workspace_create` |
| `workspace.update` | `kuma workspace update` | `kuma_workspace_update` |
| `workspace.delete` | `kuma workspace delete` | `kuma_workspace_delete` |
| `workspace.reorder` | `kuma workspace reorder` | `kuma_workspace_reorder` |
| `workspace.set_image` | `kuma workspace set-image` | `kuma_workspace_set_image` |
| `workspace.clear_image` | `kuma workspace clear-image` | `kuma_workspace_clear_image` |
| `workspace.get_image` | `kuma workspace get-image` | `kuma_workspace_get_image` |
| `group.list` | `kuma group list` | `kuma_group_list` |
| `group.create` | `kuma group create` | `kuma_group_create` |
| `group.update` | `kuma group update` | `kuma_group_update` |
| `group.delete` | `kuma group delete` | `kuma_group_delete` |
| `group.reorder` | `kuma group reorder` | `kuma_group_reorder` |
| `service.list` | `kuma service list` | `kuma_service_list` |
| `service.get` | `kuma service get` | `kuma_service_get` |
| `service.create` | `kuma service create` | `kuma_service_create` |
| `service.update` | `kuma service update` | `kuma_service_update` |
| `service.delete` | `kuma service delete` | `kuma_service_delete` |
| `service.duplicate` | `kuma service duplicate` | `kuma_service_duplicate` |
| `service.set_starred` | `kuma service set-starred` | `kuma_service_set_starred` |
| `service.set_disabled` | `kuma service set-disabled` | `kuma_service_set_disabled` |
| `service.set_groups` | `kuma service set-groups` | `kuma_service_set_groups` |
| `service.toggle_group` | `kuma service toggle-group` | `kuma_service_toggle_group` |
| `service.switch_provider` | `kuma service switch-provider` | `kuma_service_switch_provider` |
| `provider.list` | `kuma provider list` | `kuma_provider_list` |
| `provider.add` | `kuma provider add` | `kuma_provider_add` |
| `provider.update` | `kuma provider update` | `kuma_provider_update` |
| `provider.delete` | `kuma provider delete` | `kuma_provider_delete` |
| `provider.set_ports` | `kuma provider set-ports` | `kuma_provider_set_ports` |
| `service.preflight` | `kuma service preflight` | `kuma_service_preflight` |
| `service.start` | `kuma service start` | `kuma_service_start` |
| `service.stop` | `kuma service stop` | `kuma_service_stop` |
| `service.restart` | `kuma service restart` | `kuma_service_restart` |
| `service.start_all` | `kuma service start-all` | `kuma_service_start_all` |
| `service.stop_all` | `kuma service stop-all` | `kuma_service_stop_all` |
| `service.status` | `kuma service status` | `kuma_service_status` |
| `service.statuses` | `kuma service statuses` | `kuma_service_statuses` |
| `ports.check` | `kuma ports check` | `kuma_ports_check` |
| `runtime.adopt_report` | `kuma runtime adopt-report` | `kuma_runtime_adopt_report` |
| `kubeconfig.list` | `kuma kubeconfig list` | `kuma_kubeconfig_list` |
| `kubeconfig.get` | `kuma kubeconfig get` | `kuma_kubeconfig_get` |
| `kubeconfig.create` | `kuma kubeconfig create` | `kuma_kubeconfig_create` |
| `kubeconfig.update` | `kuma kubeconfig update` | `kuma_kubeconfig_update` |
| `kubeconfig.delete` | `kuma kubeconfig delete` | `kuma_kubeconfig_delete` |
| `kubeconfig.contexts` | `kuma kubeconfig contexts` | `kuma_kubeconfig_contexts` |
| `kubeconfig.test_connection` | `kuma kubeconfig test-connection` | `kuma_kubeconfig_test_connection` |
| `k8s.resolve_target` | `kuma k8s resolve-target` | `kuma_k8s_resolve_target` |
| `k8s.namespaces` | `kuma k8s namespaces` | `kuma_k8s_namespaces` |
| `k8s.resources` | `kuma k8s resources` | `kuma_k8s_resources` |
| `logs.tail` | `kuma logs tail` | `kuma_logs_tail` |
| `logs.clear` | `kuma logs clear` | `kuma_logs_clear` |
| `logs.workload_tail` | `kuma logs workload-tail` | `kuma_logs_workload_tail` |
| `events.subscribe` | `kuma events subscribe` | `kuma_events_subscribe` |
| `events.unsubscribe` | `kuma events unsubscribe` | `kuma_events_unsubscribe` |
| `logs.follow` | `kuma logs follow` | `kuma_logs_follow` |
| `data.export` | `kuma data export` | `kuma_data_export` |
| `data.export_service_json` | `kuma data export-service-json` | `kuma_data_export_service_json` |
| `data.import_preview` | `kuma data import-preview` | `kuma_data_import_preview` |
| `data.import` | `kuma data import` | `kuma_data_import` |
| `data.factory_reset` | `kuma data factory-reset` | `kuma_data_factory_reset` |

**Row count:** 74 RPC rows (73 invokable MCP tools; `daemon.rotate_api_token` has no tool per [02 §3.9](02-security-and-secrets.md)).

---

## Open questions / residual risks

- MCP **notifications** for `events.subscribe` / `logs.follow` are deferred (ADD-124); agents may need CLI streaming until a v2 MCP streaming spec exists.
- **10-rpc-protocol.md** JSON Schemas should be generated into MCP `inputSchema` automatically to avoid drift.
