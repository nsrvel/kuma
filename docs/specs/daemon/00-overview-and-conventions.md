# Daemon Spec 00: Overview and Conventions

> **Status:** Draft for implementation  
> **Audience:** Engineers implementing the Rust daemon (`daemon/`), CLI, MCP and REST adapters from these specs alone.  
> **Baseline:** Kuma 1.x (Swift, `Kuma/`) behavior at the time of writing. 1.x sources are **read-only** during daemon development.  
> **Architecture overview:** [`../07-kuma-daemon.md`](../07-kuma-daemon.md) (process model, naming, repository layout). This folder is the detailed, per-feature contract.

---

## 1. What this spec set is

A complete, normative description of every capability Kuma 1.x offers, re-expressed as a headless daemon with one RPC surface. The daemon is the **only** owner of database, execution engine, process registry, log spool and secrets. Every frontend (SwiftUI app later, `kuma` CLI, `kuma mcp`, REST/WebSocket adapter) is a client that can only call the RPC catalog in [10](10-rpc-protocol.md).

Implementation is "complete" (the parity gate) when every `[PARITY]` feature below is implemented, every invariant holds, and the acceptance tests in [15](15-traceability-and-parity.md) pass.

### 1.1 File index

| File | Topic |
|------|-------|
| [00](00-overview-and-conventions.md) | This file: IDs, conventions, RPC name registry, glossary |
| [01](01-data-model.md) | Entities, enums, SQLite schema, migrations |
| [02](02-security-and-secrets.md) | Vault, encrypted fields, transport security |
| [03](03-settings-and-environment.md) | Settings keys, PATH/tool resolution, dependency check, onboarding state |
| [04](04-workspaces-groups-services.md) | Workspace/group/service/provider CRUD, deck query, image store |
| [05](05-providers-and-validation.md) | Provider fields, create rules, configuration validator, URL normalization |
| [06](06-execution-engine.md) | Runners, supervisor, registry, reconnect, port conflict, compose |
| [07](07-kubernetes.md) | Kubeconfig, targets, port-forward, adoption, discovery |
| [08](08-logs-and-events.md) | Spool, activity log, event bus, workload logs |
| [09](09-dataport.md) | Backup/import/export, factory reset |
| [10](10-rpc-protocol.md) | Wire protocol and full method catalog (single source of truth) |
| [11](11-cli.md) | `kuma` CLI mapping |
| [12](12-mcp.md) | MCP tools/resources mapping |
| [13](13-rest-api.md) | REST + WebSocket/SSE mapping |
| [14](14-lifecycle-and-platform.md) | Startup/shutdown, LaunchAgent, quit semantics, notifications |
| [15](15-traceability-and-parity.md) | Master matrix, deviations, invariants, acceptance tests |
| [15-appendix](15-appendix-file-coverage.md) | Coverage of all 302 Swift files |
| `check_traceability.py` | Runnable completeness check |
| `export_mcp_tools_csv.py` | Regenerate `mcp-tools.csv` (MCP tools + REST endpoints) |
| `mcp-tools.csv` | Full RPC catalog (74 rows) + V2 implementation checklist; legend in [mcp-tools.README.md](mcp-tools.README.md) |
| `mcp-tools-audit.md` | One-by-one RPC ↔ MCP ↔ REST checklist (74 rows) |

---

## 2. Normative language and style

- **MUST / MUST NOT / SHOULD / MAY** are used in the RFC 2119 sense.
- Constants (timeouts, limits, regexes, argv) are **exact**. If a value is stated, the daemon MUST use it unless a `DEV-xx` entry says otherwise.
- Persisted strings (enum raw values, JSON keys, setting keys) are **exact and case-sensitive**.
- Where 1.x had a quirk that this spec changes, the behavior is stated normatively and cross-referenced to a `DEV-xx` entry in [15](15-traceability-and-parity.md).

---

## 3. Identifier schemes

| Prefix | Meaning | Example |
|--------|---------|---------|
| `FEAT-<AREA>-<NN>` | A user-visible capability (unit of parity) | `FEAT-SVC-07` |
| `INV-D-<AREA>-<NN>` | Daemon invariant (must always hold) | `INV-D-EXE-03` |
| `DEV-<NN>` | Deliberate deviation from 1.x behavior | `DEV-04` |
| `ADD-<NN>` | `[V2-ADD]` capability not in 1.x UI | `ADD-02` |
| `DT-<AREA>-<NN>` | Daemon acceptance test | `DT-EXE-12` |
| `ERR` code | Stable string error identifier `KUMA_<AREA>_<NAME>` | `KUMA_SVC_NOT_FOUND` |
| RPC method | Lowercase dotted `namespace.verb[_noun]` | `service.start` |
| Event | Lowercase dotted, defined in [08](08-logs-and-events.md) | `service.state_changed` |

### 3.1 Area codes

| Code | Area | Owning spec |
|------|------|-------------|
| `DAT` | Data model and persistence | 01 |
| `SEC` | Security and secrets | 02 |
| `SET` | Settings, environment, dependencies, onboarding state | 03 |
| `WS` | Workspaces and image store | 04 |
| `GRP` | Service groups | 04 |
| `SVC` | Services and deck | 04 |
| `PRV` | Providers, validation, URL normalization | 05 |
| `EXE` | Execution engine | 06 |
| `K8S` | Kubernetes and kubeconfig | 07 |
| `LOG` | Logs and events | 08 |
| `DPT` | DataPort | 09 |
| `LIF` | Lifecycle and platform | 14 |
| `RPC` | Protocol | 10 |
| `CLI` / `MCP` / `API` | Surfaces | 11 / 12 / 13 |

### 3.2 Feature tags

- **`[PARITY]`** - exists in 1.x; part of the completion gate.
- **`[V2-ADD]`** - new in V2 (needed for headless/agent completeness); MUST be specified and implemented but does not block the parity gate.
- **`[CLIENT]`** - stays in the client; listed only so nothing is silently dropped. The daemon provides data/events but no behavior.

---

## 4. Required section template for every feature spec (01-09, 14)

Each spec MUST contain, in this order:

1. **Purpose and scope**
2. **1.x source of truth** - list of Swift files read (paths).
3. **Normative behavior** - algorithms, state machines, exact constants, argv, regexes, messages.
4. **Data shapes** - field tables with types, optionality, defaults, JSON key names.
5. **Features table** - `FEAT id | tag | description | 1.x source | RPC methods`.
6. **Error catalog** - `ERR code | condition | message (exact 1.x text if it exists)`.
7. **Deviations** - each `DEV-xx` that touches this area (id + one line; full text in 15).
8. **Invariants** - `INV-D-*` list.
9. **Acceptance tests** - `DT-*` list (what to assert, not code).

A spec MUST NOT define RPC method names that are absent from the registry in section 5. Needed additions go in a `Proposed RPC additions` subsection and are merged into the registry by the spec 10 author.

---

## 5. RPC method name registry (authoritative list of names)

Parameter and result schemas live in [10](10-rpc-protocol.md). Every method listed here MUST appear in 10, 11 (CLI), 12 (MCP), 13 (REST) and 15 (matrix); `check_traceability.py` enforces this.

### 5.1 Daemon and settings

| Method | Tag | Purpose | Spec |
|--------|-----|---------|------|
| `daemon.ping` | PARITY-infra | Liveness + protocol version | 10, 14 |
| `daemon.status` | ADD | Version, uptime, db path, counts, running services | 14 |
| `daemon.shutdown` | ADD | Graceful stop (optional stop services) | 14 |
| `daemon.rotate_api_token` | V2-ADD | Rotate REST bearer token file (Unix socket only; [02](02-security-and-secrets.md) ADD-31) | 02, 10 |
| `settings.list` | PARITY | All settings with defaults and effective values | 03 |
| `settings.get` | PARITY | One setting | 03 |
| `settings.set` | PARITY | Set one or many settings (validated) | 03 |
| `settings.reset` | PARITY | Reset preferences to defaults (DB untouched) | 03 |
| `env.path` | PARITY | Resolved PATH string and sources | 03 |
| `env.resolve_executable` | PARITY | Resolve a command name or path to executable | 03 |
| `env.validate_binary` | PARITY | `DependencyChecker.validateCustomBinary` | 03 |
| `env.dependencies` | PARITY | Scan kubectl/kubeconfig/docker/podman/cloudflared/ngrok | 03 |
| `env.refresh` | PARITY | Drop PATH cache and re-resolve | 03 |

### 5.2 Workspaces, groups, services

| Method | Tag | Purpose | Spec |
|--------|-----|---------|------|
| `workspace.list` | PARITY | Ordered workspaces | 04 |
| `workspace.get` | PARITY | One workspace | 04 |
| `workspace.create` | PARITY | Create (optional image) | 04 |
| `workspace.update` | PARITY | Rename / change image | 04 |
| `workspace.delete` | PARITY | Delete with cascade (stops services first, DEV) | 04 |
| `workspace.reorder` | PARITY | Persist new order | 04 |
| `workspace.set_image` | PARITY | Set avatar from bytes | 04 |
| `workspace.clear_image` | PARITY | Remove avatar | 04 |
| `workspace.get_image` | PARITY | Fetch avatar bytes (optional thumbnail size) | 04 |
| `group.list` | PARITY | Groups of a workspace | 04 |
| `group.create` | PARITY | Create group | 04 |
| `group.update` | PARITY | Rename group | 04 |
| `group.delete` | PARITY | Delete group (services stay) | 04 |
| `group.reorder` | PARITY | Persist new order | 04 |
| `service.list` | PARITY | Deck items with filter/sort/search | 04 |
| `service.get` | PARITY | Service detail (providers, ports, groups) | 04 |
| `service.create` | PARITY | Create service (+ default provider, ports, groups, star) | 04, 05 |
| `service.update` | PARITY | Update service metadata (versioned) | 04 |
| `service.delete` | PARITY | Delete service | 04 |
| `service.duplicate` | PARITY | Duplicate with "(Copy)" | 04 |
| `service.set_starred` | PARITY | Star/unstar (explicit value or toggle) | 04 |
| `service.set_disabled` | PARITY | Enable/disable | 04 |
| `service.set_groups` | PARITY | Replace group membership | 04 |
| `service.toggle_group` | PARITY | Toggle one group membership | 04 |
| `service.switch_provider` | PARITY | Change active provider (stop/restart semantics) | 04, 06 |
| `provider.list` | PARITY | Providers of a service | 04 |
| `provider.add` | PARITY | Add provider | 04 |
| `provider.update` | PARITY | Update provider config (versioned) | 04, 05 |
| `provider.delete` | PARITY | Delete provider (repoint active) | 04 |
| `provider.set_ports` | PARITY | Replace port mappings for a provider | 04 |

### 5.3 Validation and execution

| Method | Tag | Purpose | Spec |
|--------|-----|---------|------|
| `service.preflight` | ADD | Run `ServiceConfigurationValidator` (+ async k8s target probe) | 05 |
| `service.start` | PARITY | Start (idempotent) | 06 |
| `service.stop` | PARITY | Stop (coalesced) | 06 |
| `service.restart` | PARITY | Stop, 300 ms, start | 06 |
| `service.start_all` | PARITY | Bulk start by workspace/filter/group | 06 |
| `service.stop_all` | PARITY | Bulk stop | 06 |
| `service.status` | PARITY | Runtime state for one service | 06 |
| `service.statuses` | PARITY | Runtime state for many/all services | 06 |
| `ports.check` | ADD | Who occupies a local port, policy outcome | 06 |
| `runtime.adopt_report` | ADD | Result of last orphan adoption pass | 06 |

### 5.4 Kubernetes

| Method | Tag | Purpose | Spec |
|--------|-----|---------|------|
| `kubeconfig.list` | PARITY | Registered kubeconfigs (+ virtual Default) | 07 |
| `kubeconfig.get` | PARITY | One kubeconfig (content decrypted on request) | 07 |
| `kubeconfig.create` | PARITY | Register file-backed or pasted kubeconfig | 07 |
| `kubeconfig.update` | PARITY | Update | 07 |
| `kubeconfig.delete` | PARITY | Delete (not Default) | 07 |
| `kubeconfig.contexts` | PARITY | Parse contexts + current context | 07 |
| `kubeconfig.test_connection` | PARITY | `kubectl version` probe with cache | 07 |
| `k8s.resolve_target` | PARITY | Resolve pattern to concrete resource | 07 |
| `k8s.namespaces` | ADD | List namespaces | 07 |
| `k8s.resources` | ADD | List pods/services/deployments | 07 |

### 5.5 Logs and events

| Method | Tag | Purpose | Spec |
|--------|-----|---------|------|
| `logs.tail` | PARITY | Activity-log buffer for a service | 08 |
| `logs.clear` | PARITY | Clear buffer | 08 |
| `logs.workload_tail` | ADD | One-shot workload logs (`kubectl logs`, compose logs, spool) | 08 |
| `events.subscribe` | PARITY-infra | Subscribe to event topics (with replay) | 08, 10 |
| `events.unsubscribe` | PARITY-infra | Cancel subscription | 08, 10 |
| `logs.follow` | ADD | Streaming workload logs via subscription | 08 |

### 5.6 DataPort

| Method | Tag | Purpose | Spec |
|--------|-----|---------|------|
| `data.export` | PARITY | Export all / workspace / service | 09 |
| `data.export_service_json` | PARITY | Single-service JSON ("Copy Config") | 09 |
| `data.import_preview` | PARITY | Parse any backup (full or single) into a summary | 09 |
| `data.import` | PARITY | Import with strategy and selection | 09 |
| `data.factory_reset` | PARITY | Stop everything, wipe DB/prefs/images | 09 |

**Surface note:** `daemon.rotate_api_token` is in the registry above but MUST NOT appear on REST or MCP ([02 §3.9](02-security-and-secrets.md)); CLI maps it in [11 §3.8.1](11-cli.md).

### 5.7 Event registry (names only; payloads in 08)

`service.state_changed`, `service.log_line`, `service.created`, `service.updated`, `service.deleted`, `group.changed`, `workspace.changed`, `kubeconfig.changed`, `settings.changed`, `notify`, `data.imported`, `data.reset`, `daemon.shutting_down`.

---

## 6. Daemon vs client responsibility

| Concern | Owner |
|---------|-------|
| Database, migrations, repositories, validation, business rules | Daemon |
| Process spawn/supervise/adopt/stop, compose, pollers, port conflict | Daemon |
| Secrets, kubeconfig materialization, PATH/tool resolution | Daemon |
| Log capture, spool, activity buffer, event fan-out | Daemon |
| Backup parsing, import/export, factory reset | Daemon |
| Deck filter/sort/search semantics | Daemon (`service.list`) |
| Windows, sheets, animations, haptics, sound playback, drag and drop, pasteboard | Client |
| macOS notifications UI, quit confirmation dialog, launch-at-login registration, appearance (`NSAppearance`) | Client (daemon emits events / stores prefs) |
| Selected workspace, view mode, sidebar expansion, onboarding completion flag | Client preference, **stored in the daemon settings KV** under `client.*` so any frontend shares it (see [03](03-settings-and-environment.md)) |

---

## 7. Glossary

| Term | Meaning |
|------|---------|
| Service | A named unit in a workspace with one or more providers; one is *active* |
| Provider | Runner configuration: one of 8 categories (`ProviderCategory`) |
| Deck | The workspace service list (cards/table) |
| Spool | On-disk capture of a managed process's stdout/stderr |
| Activity log | Per-service system log (`[KUMA]`, `[FAILURE]`, ...) distinct from workload logs |
| Managed process | OS process spawned and owned by the daemon |
| Adoption | Taking ownership of an already-running external process/stack |
| Poller | Daemon-internal loop for health check and process monitor providers |
| Default kubeconfig | Virtual kubeconfig `00000000-0000-0000-0000-000000000001` |

---

## 8. Global requirements

- **GR-01** The daemon MUST NOT depend on any 1.x Swift code at runtime.
- **GR-02** The daemon MUST be able to open a 1.x `kuma.sqlite` (see [01](01-data-model.md)).
- **GR-03** All state-changing RPC calls MUST be serialized per entity and idempotent where stated.
- **GR-04** No secret (password, token, kubeconfig content, master key) may appear in logs, events, or error messages.
- **GR-05** Every RPC method MUST be reachable from CLI, MCP and REST (exceptions: streaming-only transports are listed explicitly in 11-13).
