# Daemon Spec 11: `kuma` CLI

> **Status:** Draft for implementation  
> **Area codes:** `CLI` (surface), consumes `RPC` ([10](10-rpc-protocol.md))  
> **Audience:** Engineers implementing `daemon/kuma/` and `daemon/crates/kuma-client/`  
> **Depends on:** [00](00-overview-and-conventions.md) (RPC registry §5, GR-05), [02](02-security-and-secrets.md) (`revealSecrets`), [10](10-rpc-protocol.md) (wire schemas — authoritative when present; until then infer from feature specs 01–09, 14)  
> **Cross-references:** [12](12-mcp.md) (`kuma mcp`), [14](14-lifecycle-and-platform.md) (`daemon run`, LaunchAgent, paths), [07-kuma-daemon.md](../07-kuma-daemon.md) (architecture)

---

## 1. Purpose and scope

This spec defines the user-facing **`kuma`** binary: subcommand tree, flags that map to JSON-RPC `params`, stdout/stderr conventions, process exit codes, and environment variables used to locate the daemon socket. Every RPC method in [00 §5](00-overview-and-conventions.md) MUST have exactly one CLI leaf command documented in §3.7 and Appendix A, except where §3.8 lists an explicit transport exception.

In scope:

- Client commands that call the daemon over the Unix socket ([10](10-rpc-protocol.md) NDJSON JSON-RPC).
- **`kuma daemon run`** (foreground server; does not use the client transport).
- **`kuma daemon install` / `uninstall`** (LaunchAgent; see [14 §3.11](14-lifecycle-and-platform.md)).
- **`kuma mcp`** entry stub (implementation normative in [12](12-mcp.md)).

Out of scope: RPC handler logic (feature specs 01–09, 14), MCP wire details ([12](12-mcp.md)), REST ([13](13-rest-api.md)), SwiftUI ([00 §6](00-overview-and-conventions.md)).

Tags: **[PARITY]** (1.x had no CLI; each command maps a 1.x UI or menu action), **[V2-ADD]**, **[CLIENT]**.

---

## 2. 1.x source of truth

Kuma 1.x had **no** standalone CLI. Behavior is defined by the RPC catalog (parity with Swift app actions) and the Rust scaffold:

| Topic | Path |
|-------|------|
| Binary name, top-level subcommands | `daemon/kuma/src/main.rs:5-31` |
| `daemon run` | `daemon/kuma/src/main.rs:40-41`, `daemon/crates/kuma-daemon/src/lib.rs` |
| Socket/runtime paths (scaffold) | `daemon/crates/kuma-protocol/src/paths.rs:4-17` |
| JSON-RPC framing constant | `daemon/crates/kuma-protocol/src/jsonrpc.rs:5-6` |
| Implemented RPC method constants (partial) | `daemon/crates/kuma-protocol/src/jsonrpc.rs:8-11` |
| Dev README command table | `daemon/README.md:35-41` |
| LaunchAgent / lifecycle CLI | [14](14-lifecycle-and-platform.md) §3.11, ADD-110–ADD-116 |
| Menu/shortcut analogues | [04](04-workspaces-groups-services.md) §2 (`KumaCommands.swift`, deck actions) |

**Scaffold constants (verified)**

| Name | Value | Source |
|------|-------|--------|
| Binary `name` (clap) | `kuma` | `main.rs:6` |
| Default log filter directive | `kuma=info` | `main.rs:36` |
| NDJSON framing label | `ndjson` | `jsonrpc.rs:6` |
| Default socket file | `kuma-daemon.sock` under runtime dir | `paths.rs:11-12` |
| Runtime override env | `KUMA_RUNTIME_DIR` | `paths.rs:4-7` |
| Default runtime parent (scaffold) | `~/Library/Application Support/Kuma` | `paths.rs:19-22` |

**Target paths (normative; DEV-113 until scaffold converges):** data dir `KUMA_DATA_DIR` → `~/Library/Application Support/Kuma`; runtime dir `KUMA_RUNTIME_DIR` → `<data>/run/`; socket `<runtime>/kuma-daemon.sock` ([14 §3.1](14-lifecycle-and-platform.md)).

---

## 3. Normative behavior

### 3.1 Invocation shape

```text
kuma [GLOBAL OPTIONS] <command> [<subcommand> ...] [COMMAND OPTIONS] [ARGS]
```

- **Global options** apply to all **client** subcommands (everything except `daemon run`, `daemon install`, `daemon uninstall`). They MUST appear before the subcommand name.
- **Command options** map to RPC `params` (§3.5). Unknown flags → exit **2** with usage on stderr.
- The CLI MUST NOT introduce RPC method names that are absent from [00 §5](00-overview-and-conventions.md).

### 3.2 Subcommand tree (1:1 with RPC catalog)

Legend: `(RPC)` = single JSON-RPC call; `(local)` = no RPC.

```text
kuma
├── daemon
│   ├── run                          (local — foreground server)
│   ├── install [--keep-alive]       (local — LaunchAgent, ADD-110/111)
│   ├── uninstall                    (local — LaunchAgent)
│   ├── ping                         → daemon.ping
│   ├── status                       → daemon.status
│   └── shutdown                     → daemon.shutdown
├── mcp                              (local stdio MCP bridge — see [12](12-mcp.md))
├── settings
│   ├── list                         → settings.list
│   ├── get                          → settings.get
│   ├── set                          → settings.set
│   └── reset                        → settings.reset
├── env
│   ├── path                         → env.path
│   ├── resolve-executable           → env.resolve_executable
│   ├── validate-binary              → env.validate_binary
│   ├── dependencies                 → env.dependencies
│   └── refresh                      → env.refresh
├── workspace
│   ├── list | get | create | update | delete | reorder
│   ├── set-image | clear-image | get-image
│   └── (each leaf → workspace.*)
├── group
│   ├── list | create | update | delete | reorder
│   └── (each leaf → group.*)
├── service
│   ├── list | get | create | update | delete | duplicate
│   ├── set-starred | set-disabled | set-groups | toggle-group | switch-provider
│   ├── preflight | start | stop | restart | start-all | stop-all
│   ├── status | statuses
│   └── (each leaf → service.* / service.preflight)
├── provider
│   ├── list | add | update | delete | set-ports
│   └── (each leaf → provider.*)
├── ports
│   └── check                          → ports.check
├── runtime
│   └── adopt-report                   → runtime.adopt_report
├── kubeconfig
│   ├── list | get | create | update | delete
│   ├── contexts | test-connection
│   └── (each leaf → kubeconfig.*)
├── k8s
│   ├── resolve-target | namespaces | resources
│   └── (each leaf → k8s.*)
├── logs
│   ├── tail | clear | workload-tail | follow
│   └── (each leaf → logs.*)
├── events
│   ├── subscribe                      → events.subscribe (+ stream)
│   └── unsubscribe                    → events.unsubscribe
└── data
    ├── export | export-service-json | import-preview | import | factory-reset
    └── (each leaf → data.*)
```

**Kebab-case rule:** RPC segment after the dot uses kebab-case in the CLI path (`set_image` → `set-image`, `start_all` → `start-all`, `export_service_json` → `export-service-json`, `test_connection` → `test-connection`, `workload_tail` → `workload-tail`, `adopt_report` → `adopt-report`, `resolve_target` → `resolve-target`).

### 3.3 Global client options

| Flag | Env | JSON / RPC | Description |
|------|-----|------------|-------------|
| `--json` | — | — | Machine output (§3.6). Mutually exclusive with human table mode. |
| `--socket PATH` | `KUMA_SOCKET` | — | Unix socket path. Precedence: flag > `KUMA_SOCKET` > default from runtime dir (ADD-125). |
| `--reveal-secrets` | — | `revealSecrets: true` on eligible reads | Same-uid Unix client only ([02](02-security-and-secrets.md)); ignored with warning if not same uid. |
| `--timeout DURATION` | `KUMA_RPC_TIMEOUT` | — | Per-RPC wait (default `60s`; `logs.workload_tail` uses RPC default 60s from [08](08-logs-and-events.md)). |
| `--params-file PATH` | — | Merged into `params` | JSON object merged last; keys MUST be camelCase as on the wire. For large writes (`provider.update`, `data.import`). |

**Connection resolution (ordered):**

1. `--socket` if set.
2. Else `KUMA_SOCKET` if set (ADD-125).
3. Else `socket_path()` from `KUMA_RUNTIME_DIR` or default data/runtime layout ([14 §3.1](14-lifecycle-and-platform.md)).
4. Connect failure → exit **3**, stderr message `Kuma daemon is not running` (`KUMA_LIF_NOT_RUNNING` when RPC layer applies) or `Could not connect to daemon socket: <path>`.

**Other env (daemon server / data, not socket override):**

| Variable | Used by | Purpose |
|----------|---------|---------|
| `KUMA_DATA_DIR` | `daemon run`, imports | Data directory ([00 brief](00-overview-and-conventions.md)) |
| `KUMA_RUNTIME_DIR` | `daemon run`, default socket | Runtime dir ([14 §3.1](14-lifecycle-and-platform.md)) |
| `RUST_LOG` | All | Tracing filter ([`EnvFilter`](https://docs.rs/tracing-subscriber)); default `kuma=info` on server |

### 3.4 Common param flags

Unless a command defines overrides, UUID/id flags use `--id`, `--workspace-id`, `--service-id`, `--group-id`, `--provider-id`, `--kube-config-id` (wire: `kubeConfigID`), `--subscription-id` (wire: `subscriptionId` on unsubscribe).

| Flag | Wire key | Notes |
|------|----------|-------|
| `--expected-updated-at ISO8601` | `expectedUpdatedAt` | Optimistic concurrency ([04 §3.0](04-workspaces-groups-services.md)); mismatch → `KUMA_CONFLICT_STALE`, exit **1**. |
| `--name TEXT` | `name` | Trimmed per owning spec |
| `--file PATH` | (varies) | Binary/file payload where spec defines (`imageBase64` from file, export output path, import backup path) |

Repeated flags: `--service-id` may repeat where RPC accepts `serviceIDs[]` (`service.statuses`, bulk filters).

Boolean RPC params: `--starred`, `--disabled`, `--stop-services`, `--compose-down`, `--refresh`, etc. use clap `ArgAction::SetTrue` (absent = omit key from params).

### 3.5 RPC request execution

1. Build `params` from flags + optional `--params-file`.
2. Open Unix stream socket; write one NDJSON line: `{"jsonrpc":"2.0","method":"<rpc>","params":{...},"id":1}\n` ([10](10-rpc-protocol.md)).
3. Read lines until a response with matching `id` (or error). For streaming commands (§3.8), read until subscription ends or process interrupted.
4. Map JSON-RPC `error` to stderr + exit **1**; include `error.data.code` when present (`KUMA_*`).

**Notification requests:** The CLI MUST NOT send JSON-RPC notifications; every invocation uses a request `id`.

### 3.6 stdout, stderr, and human output

| Mode | stdout | stderr |
|------|--------|--------|
| `--json` (default for scripting) | On success: **only** the RPC `result` object as compact JSON + `\n`. On failure: **only** `{"error":{"code":...,"message":...,"data":...}}` + `\n` (CLI convention FEAT-CLI-03). | Human-readable hint optional; MUST NOT contain secrets. |
| Human (default TTY) | Formatted tables or key-value blocks (FEAT-CLI-02). Lists use column headers derived from result keys. UUIDs uppercase. Durations humanized. | Errors: `<KUMA_CODE>: <message>` one line. |
| `--json` + non-TTY | Same as `--json`. | Same; no color. |

**Human table rules:**

- `*.list` / deck: columns `ID`, `Name`, … per DTO ([04](04-workspaces-groups-services.md)).
- `service.status` / `service.statuses`: runtime columns from [06](06-execution-engine.md) §3.3 wire table.
- `settings.list`: `Key`, `Value`, `Source`, `Default`.
- `env.dependencies`: one row per dependency with `Found`, `Path`, `Version`.
- Empty lists: print header + `(empty)` row, exit **0**.

**Binary payloads:** `workspace.get-image` human mode writes raw PNG bytes to stdout; `--json` base64-encodes in result JSON per [10](10-rpc-protocol.md). `data.export` human mode writes file to `--out` (required in human mode).

### 3.7 Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (RPC `result` present; streaming command ended cleanly) |
| 1 | RPC application error (`error.data.code` / `KUMA_*`), daemon returned JSON-RPC error, or `daemon run` fatal startup |
| 2 | CLI usage, unknown flag, invalid flag combination, invalid UUID locally |
| 3 | Cannot connect to daemon (socket missing / refused) |
| 130 | SIGINT (128+2) — user cancelled streaming (`events subscribe`, `logs follow`) |

LaunchAgent subcommands use **1** when plist write or `launchctl` fails; see [14](14-lifecycle-and-platform.md).

### 3.8 Transport exceptions (GR-05)

| RPC | CLI command | Behavior |
|-----|-------------|----------|
| `events.subscribe` | `kuma events subscribe` | Long-lived: after subscribe result, print each event as one NDJSON line on stdout (`--json`) or `topic: payload` human lines. SIGINT → `events.unsubscribe` best-effort then exit 130. |
| `logs.follow` | `kuma logs follow` | Requires active subscription on same connection or prior `events subscribe` in process ([08](08-logs-and-events.md)); streams `service.log_line` workload events. |
| `daemon.ping` | `kuma daemon ping` | Also used internally by second-instance guard ([14 §3.3](14-lifecycle-and-platform.md)). |

All other registry methods use request/response single shot.

### 3.8.1 Socket-only RPCs (no REST/MCP)

| RPC | CLI command | Behavior |
|-----|-------------|----------|
| `daemon.rotate_api_token` | `kuma daemon rotate-api-token` | Same single-shot RPC as §3.5; MUST use Unix socket (`clientKind` `cli` or `app`). Refused on REST/MCP with `KUMA_SEC_LOCAL_ONLY` ([02](02-security-and-secrets.md)). |

### 3.9 `kuma daemon run` (local)

- MUST NOT require a running daemon or socket connection.
- Binds listener, serves RPC catalog ([14 §3.2](14-lifecycle-and-platform.md) startup).
- Foreground: blocks until shutdown; exit **0** on clean shutdown, **1** on startup failure (`KUMA_LIF_*`).
- Logs to stderr via `tracing` (not JSON-RPC).

**Scaffold today:** `Install` / `Uninstall` bail with message referencing `docs/specs/07-kuma-daemon.md` (`main.rs:42-44`) — implementation MUST match [14 §3.11](14-lifecycle-and-platform.md).

### 3.10 `kuma mcp` (stub)

- Declared in `main.rs:19-20,46-48` as not implemented until parity milestone.
- Normative behavior: [12](12-mcp.md). Entry point only; no duplicate tool list here.

### 3.11 Per-command param flags (summary)

Parameter schemas are authoritative in [10](10-rpc-protocol.md). Until published, feature specs define params; the CLI MUST expose the wire keys as flags below.

#### Daemon RPC

| CLI | RPC | Flags |
|-----|-----|-------|
| `daemon ping` | `daemon.ping` | `--client-kind cli\|app\|mcp\|rest` (optional, [14 §3.4](14-lifecycle-and-platform.md)) |
| `daemon status` | `daemon.status` | — |
| `daemon shutdown` | `daemon.shutdown` | `--stop-services`, `--compose-down` |
| `daemon rotate-api-token` | `daemon.rotate_api_token` | — (socket-only; §3.8.1) |

#### Settings / env

| CLI | RPC | Flags |
|-----|-----|-------|
| `settings get` | `settings.get` | `--key` (required) |
| `settings set` | `settings.set` | `--key` + `--value`, or repeated `--set key=value`, or `--params-file` |
| `settings reset` | `settings.reset` | — |
| `env resolve-executable` | `env.resolve_executable` | `--name`, `--cwd` |
| `env validate-binary` | `env.validate_binary` | `--path`, `--kind` |
| `env dependencies` | `env.dependencies` | — |

#### Workspace / group

| CLI | RPC | Notable flags |
|-----|-----|---------------|
| `workspace get` | `workspace.get` | `--id` |
| `workspace create` | `workspace.create` | `--name`, `--image-file` (→ `imageBase64`) |
| `workspace update` | `workspace.update` | `--id`, `--name`, `--image-file`, `--clear-image`, `--expected-updated-at` |
| `workspace delete` | `workspace.delete` | `--id` |
| `workspace reorder` | `workspace.reorder` | `--workspace-id`… (permutation) **or** `--from-index` + `--to-index` |
| `workspace set-image` | `workspace.set_image` | `--id`, `--image-file`, `--expected-updated-at` |
| `workspace clear-image` | `workspace.clear_image` | `--id`, `--expected-updated-at` |
| `workspace get-image` | `workspace.get_image` | `--id`, `--size`, `--out` (human file) |
| `group list` | `group.list` | `--workspace-id` |
| `group create` | `group.create` | `--workspace-id`, `--name` |
| `group update` | `group.update` | `--id`, `--name`, `--expected-updated-at` |
| `group delete` | `group.delete` | `--id` |
| `group reorder` | `group.reorder` | `--workspace-id`, `--group-id`… |

#### Service / provider / execution

| CLI | RPC | Notable flags |
|-----|-----|---------------|
| `service list` | `service.list` | `--workspace-id`, `--search`, `--starred-only`, `--group-id`, `--status` (repeat), `--provider` (repeat), `--sort` |
| `service create` | `service.create` | `--workspace-id`, `--name`, `--params-file` (full create payload) |
| `service update` | `service.update` | `--id`, field flags / `--params-file`, `--expected-updated-at` |
| `service duplicate` | `service.duplicate` | `--id` |
| `service set-starred` | `service.set_starred` | `--id`, `--starred` or `--toggle` |
| `service set-disabled` | `service.set_disabled` | `--id`, `--disabled`, `--expected-updated-at` |
| `service set-groups` | `service.set_groups` | `--id`, `--group-id`… |
| `service toggle-group` | `service.toggle_group` | `--id`, `--group-id` |
| `service switch-provider` | `service.switch_provider` | `--id`, `--provider-id`, `--expected-updated-at` |
| `service preflight` | `service.preflight` | `--id` |
| `service start` / `stop` / `restart` | `service.start` etc. | `--id` |
| `service start-all` | `service.start_all` | Same filters as `service list` + optional `--service-id`… |
| `service stop-all` | `service.stop_all` | Same filter set |
| `service status` | `service.status` | `--id` |
| `service statuses` | `service.statuses` | optional repeated `--service-id` |
| `provider list` | `provider.list` | `--service-id` |
| `provider add` | `provider.add` | `--service-id`, `--type`, `--params-file`, `--expected-updated-at` |
| `provider update` | `provider.update` | `--id`, `--params-file`, `--expected-updated-at` |
| `provider delete` | `provider.delete` | `--id`, `--expected-updated-at` |
| `provider set-ports` | `provider.set_ports` | `--provider-id`, `--params-file` (port array) |

#### Ports / runtime / k8s / logs / events / data

| CLI | RPC | Notable flags |
|-----|-----|---------------|
| `ports check` | `ports.check` | `--port`, `--excluding-service-id` |
| `runtime adopt-report` | `runtime.adopt_report` | — |
| `kubeconfig get` | `kubeconfig.get` | `--id`, `--reveal-secrets` |
| `kubeconfig create` | `kubeconfig.create` | `--name`, `--file` or `--content`, `--params-file` |
| `kubeconfig contexts` | `kubeconfig.contexts` | `--kube-config-id`, `--refresh` |
| `kubeconfig test-connection` | `kubeconfig.test_connection` | `--kube-config-id`, `--context`, `--refresh` |
| `k8s resolve-target` | `k8s.resolve_target` | pattern flags per [07](07-kubernetes.md) |
| `k8s namespaces` | `k8s.namespaces` | `--kube-config-id`, `--context` |
| `k8s resources` | `k8s.resources` | `--resource-type pod\|service\|deployment`, `--namespace`, … |
| `logs tail` | `logs.tail` | `--service-id`, `--max-lines` |
| `logs clear` | `logs.clear` | `--service-id` |
| `logs workload-tail` | `logs.workload_tail` | `--service-id`, `--max-lines` |
| `logs follow` | `logs.follow` | `--service-id`, `--subscription-id` |
| `events subscribe` | `events.subscribe` | `--topic`…, `--since-seq` |
| `events unsubscribe` | `events.unsubscribe` | `--subscription-id` |
| `data export` | `data.export` | scope flags per [09](09-dataport.md), `--out` |
| `data export-service-json` | `data.export_service_json` | `--service-id` |
| `data import-preview` | `data.import_preview` | `--file` |
| `data import` | `data.import` | `--file`, strategy/selection via `--params-file` |
| `data factory-reset` | `data.factory_reset` | confirmation flag `--yes` (CLI guard, FEAT-CLI-15) |

---

## 4. Data shapes

### 4.1 CLI error envelope (`--json` failure)

| Field | Type | Optional? | JSON key | Default |
|-------|------|-----------|----------|---------|
| `code` | int | no | `error.code` | JSON-RPC code |
| `message` | string | no | `error.message` | RPC message |
| `kumaCode` | string | yes | `error.data.code` | e.g. `KUMA_SVC_NOT_FOUND` |
| `details` | object | yes | `error.data.details` | per RPC |

### 4.2 Connection config (internal)

| Field | Type | Source |
|-------|------|--------|
| `socketPath` | string | §3.3 resolution |
| `timeoutMs` | int | `--timeout` / `KUMA_RPC_TIMEOUT` |
| `revealSecrets` | bool | `--reveal-secrets` |

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-CLI-01 | V2-ADD | Binary `kuma` with clap subcommands | — (new) | — |
| FEAT-CLI-02 | V2-ADD | Human table/text stdout for TTY | — | all read/list RPCs |
| FEAT-CLI-03 | V2-ADD | `--json` result-only stdout | — | all RPCs |
| FEAT-CLI-04 | V2-ADD | `KUMA_SOCKET` / `--socket` override | — | — |
| FEAT-CLI-05 | V2-ADD | `--reveal-secrets` on eligible reads | — | `kubeconfig.get`, `service.get`, … ([02](02-security-and-secrets.md)) |
| FEAT-CLI-06 | V2-ADD | `--expected-updated-at` on versioned writes | — | per [04 §3.0](04-workspaces-groups-services.md) |
| FEAT-CLI-07 | V2-ADD | `kuma daemon run` foreground server | — | — |
| FEAT-CLI-08 | V2-ADD | `kuma daemon install` / `uninstall` | Settings launch-at-login (client) | — |
| FEAT-CLI-09 | V2-ADD | `kuma daemon status` → `daemon.status` | — | `daemon.status` |
| FEAT-CLI-10 | V2-ADD | `kuma daemon ping` / `shutdown` | — | `daemon.ping`, `daemon.shutdown` |
| FEAT-CLI-11 | V2-ADD | Workspace/group/service/provider CLI tree | Deck + sidebar + inspector | `workspace.*`, `group.*`, `service.*`, `provider.*` |
| FEAT-CLI-12 | V2-ADD | Execution CLI (`start`, bulk, status) | Execution menu | `service.start`, …, `service.statuses` |
| FEAT-CLI-13 | V2-ADD | Settings/env CLI | Settings panes | `settings.*`, `env.*` |
| FEAT-CLI-14 | V2-ADD | K8s/kubeconfig CLI | Kube UI | `kubeconfig.*`, `k8s.*` |
| FEAT-CLI-15 | V2-ADD | DataPort CLI + `factory-reset --yes` | Settings backup | `data.*` |
| FEAT-CLI-16 | V2-ADD | Logs/events streaming commands | Log panels | `logs.*`, `events.*` |
| FEAT-CLI-17 | V2-ADD | `ports check`, `runtime adopt-report` | — | `ports.check`, `runtime.adopt_report` |
| FEAT-CLI-18 | V2-ADD | `kuma mcp` stub entry | — | — ([12](12-mcp.md)) |
| FEAT-CLI-19 | CLIENT | Window layout, animations, pasteboard | SwiftUI | — |

---

## 6. Error catalog

| ERR code | Condition | Message (exact or pattern) |
|----------|-----------|----------------------------|
| `KUMA_CLI_USAGE` | clap parse failure | clap usage text on stderr |
| `KUMA_CLI_INVALID_UUID` | local UUID parse | `Invalid UUID: <input>` |
| `KUMA_CLI_CONNECT` | socket connect fail | `Could not connect to daemon socket: <path>` |
| `KUMA_CLI_PARAMS_FILE` | bad `--params-file` JSON | `Invalid params file: <detail>` |
| `KUMA_LIF_NOT_RUNNING` | status/install against down daemon | `Kuma daemon is not running` ([14](14-lifecycle-and-platform.md)) |
| (RPC) | handler errors | pass through `error.data.code` / message unchanged |

---

## 7. Deviations

| Id | Summary |
|----|---------|
| DEV-113 | Scaffold socket under data dir without `run/`; CLI MUST follow resolved path from `daemon.status.runtimeDir` when debugging ([14](14-lifecycle-and-platform.md)) |
| ADD-125 | `KUMA_SOCKET` explicit socket path override for CLI/MCP clients |
| ADD-126 | `--json` error envelope includes structured `error.data` when daemon provides it |
| ADD-122 | `data factory-reset` requires `--yes` (CLI-only guard; RPC unchanged) |

No new RPC methods in this spec.

---

## 8. Invariants

| Id | Statement |
|----|-----------|
| INV-D-CLI-01 | Every RPC in [00 §5](00-overview-and-conventions.md) has exactly one documented CLI leaf in Appendix A, except §3.8 streaming pairing. |
| INV-D-CLI-02 | CLI MUST NOT emit secret fields on stdout/stderr unless `--reveal-secrets` and same-uid Unix peer ([02](02-security-and-secrets.md)). |
| INV-D-CLI-03 | `--json` stdout MUST contain valid JSON only (one value per invocation for non-streaming commands). |
| INV-D-CLI-04 | `kuma daemon run` MUST NOT dial the client socket to serve its own RPC. |
| INV-D-CLI-05 | Wire param keys sent by the CLI MUST use camelCase identical to Swift Codable ([00 brief](00-overview-and-conventions.md)). |

---

## 9. Acceptance tests

| Id | Arrange | Assert |
|----|---------|--------|
| DT-CLI-01 | Daemon up; `kuma daemon ping --json` | Exit 0; stdout JSON with ping result; method `daemon.ping` |
| DT-CLI-02 | Daemon down | `kuma workspace list` exit 3; stderr connect message |
| DT-CLI-03 | `KUMA_SOCKET` points at test socket | Client connects without `--socket` |
| DT-CLI-04 | `kuma workspace list` human TTY | Table header + rows; no JSON |
| DT-CLI-05 | Unknown service id `--json` | Exit 1; `KUMA_SVC_NOT_FOUND` in envelope |
| DT-CLI-06 | `kuma daemon run` + second terminal RPC | `workspace.list` succeeds |
| DT-CLI-07 | `events subscribe --json` + start service | At least one NDJSON event line on stdout |
| DT-CLI-08 | `data factory-reset` without `--yes` | Exit 2; no RPC call |
| DT-CLI-09 | `check_traceability.py` | Every RPC row in Appendix A present in 00 §5 |

---

## Appendix A — RPC ↔ CLI mapping (authoritative)

| RPC method | CLI command |
|------------|-------------|
| `daemon.ping` | `kuma daemon ping` |
| `daemon.status` | `kuma daemon status` |
| `daemon.shutdown` | `kuma daemon shutdown` |
| `daemon.rotate_api_token` | `kuma daemon rotate-api-token` |
| `settings.list` | `kuma settings list` |
| `settings.get` | `kuma settings get` |
| `settings.set` | `kuma settings set` |
| `settings.reset` | `kuma settings reset` |
| `env.path` | `kuma env path` |
| `env.resolve_executable` | `kuma env resolve-executable` |
| `env.validate_binary` | `kuma env validate-binary` |
| `env.dependencies` | `kuma env dependencies` |
| `env.refresh` | `kuma env refresh` |
| `workspace.list` | `kuma workspace list` |
| `workspace.get` | `kuma workspace get` |
| `workspace.create` | `kuma workspace create` |
| `workspace.update` | `kuma workspace update` |
| `workspace.delete` | `kuma workspace delete` |
| `workspace.reorder` | `kuma workspace reorder` |
| `workspace.set_image` | `kuma workspace set-image` |
| `workspace.clear_image` | `kuma workspace clear-image` |
| `workspace.get_image` | `kuma workspace get-image` |
| `group.list` | `kuma group list` |
| `group.create` | `kuma group create` |
| `group.update` | `kuma group update` |
| `group.delete` | `kuma group delete` |
| `group.reorder` | `kuma group reorder` |
| `service.list` | `kuma service list` |
| `service.get` | `kuma service get` |
| `service.create` | `kuma service create` |
| `service.update` | `kuma service update` |
| `service.delete` | `kuma service delete` |
| `service.duplicate` | `kuma service duplicate` |
| `service.set_starred` | `kuma service set-starred` |
| `service.set_disabled` | `kuma service set-disabled` |
| `service.set_groups` | `kuma service set-groups` |
| `service.toggle_group` | `kuma service toggle-group` |
| `service.switch_provider` | `kuma service switch-provider` |
| `provider.list` | `kuma provider list` |
| `provider.add` | `kuma provider add` |
| `provider.update` | `kuma provider update` |
| `provider.delete` | `kuma provider delete` |
| `provider.set_ports` | `kuma provider set-ports` |
| `service.preflight` | `kuma service preflight` |
| `service.start` | `kuma service start` |
| `service.stop` | `kuma service stop` |
| `service.restart` | `kuma service restart` |
| `service.start_all` | `kuma service start-all` |
| `service.stop_all` | `kuma service stop-all` |
| `service.status` | `kuma service status` |
| `service.statuses` | `kuma service statuses` |
| `ports.check` | `kuma ports check` |
| `runtime.adopt_report` | `kuma runtime adopt-report` |
| `kubeconfig.list` | `kuma kubeconfig list` |
| `kubeconfig.get` | `kuma kubeconfig get` |
| `kubeconfig.create` | `kuma kubeconfig create` |
| `kubeconfig.update` | `kuma kubeconfig update` |
| `kubeconfig.delete` | `kuma kubeconfig delete` |
| `kubeconfig.contexts` | `kuma kubeconfig contexts` |
| `kubeconfig.test_connection` | `kuma kubeconfig test-connection` |
| `k8s.resolve_target` | `kuma k8s resolve-target` |
| `k8s.namespaces` | `kuma k8s namespaces` |
| `k8s.resources` | `kuma k8s resources` |
| `logs.tail` | `kuma logs tail` |
| `logs.clear` | `kuma logs clear` |
| `logs.workload_tail` | `kuma logs workload-tail` |
| `events.subscribe` | `kuma events subscribe` |
| `events.unsubscribe` | `kuma events unsubscribe` |
| `logs.follow` | `kuma logs follow` |
| `data.export` | `kuma data export` |
| `data.export_service_json` | `kuma data export-service-json` |
| `data.import_preview` | `kuma data import-preview` |
| `data.import` | `kuma data import` |
| `data.factory_reset` | `kuma data factory-reset` |

**Row count:** 74 (matches [00 §5](00-overview-and-conventions.md); includes socket-only `daemon.rotate_api_token`).

---

## Open questions / residual risks

- **10-rpc-protocol.md** not yet checked in: flag-level detail may need adjustment when §10 publishes without changing RPC names.
- **Human column sets** for wide DTOs (`service.get`) may truncate in TTY; `--json` remains canonical for scripts.
