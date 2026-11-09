# Daemon Spec 10: RPC Protocol and Method Catalog

> **Status:** Normative  
> **Audience:** Authors of `kuma-daemon`, `kuma-protocol`, CLI, MCP, and REST adapters  
> **Authority:** This file is the **single source of truth** for wire framing, JSON-RPC envelopes, application errors, and every parameter/result schema for methods in [00 §5](00-overview-and-conventions.md). Method **names** are registered only in 00; this spec defines their shapes.  
> **Scaffold:** `daemon/crates/kuma-protocol/` (`FRAMING`, `Request`/`Response`, `PROTOCOL_VERSION`), `daemon/crates/kuma-daemon/src/lib.rs` (`daemon.ping`, stub `daemon.shutdown`).

---

## 1. Purpose and scope

This spec defines how clients talk to the Kuma daemon:

1. **Transport** — Unix domain socket, NDJSON framing, connection lifecycle.
2. **Envelope** — JSON-RPC 2.0 request/response, correlation via `id`, optional `clientRequestId` for event attribution.
3. **Errors** — JSON-RPC numeric codes, stable `KUMA_*` string codes in `error.data`, redaction of secrets in messages ([02](02-security-and-secrets.md)).
4. **Versioning** — `protocolVersion`, capability negotiation on connect.
5. **Concurrency and idempotency** — `expectedUpdatedAt` optimistic tokens; methods that are safe to retry.
6. **Method catalog** — all **73** methods from [00 §5.1–5.6](00-overview-and-conventions.md), with params, results, errors, events, and FEAT cross-refs.
7. **Event stream** — `events.subscribe` / `events.unsubscribe`, replay (`sinceSeq`, ADD-07), all **13** event types from [00 §5.7](00-overview-and-conventions.md).
8. **Security** — Unix peer credentials, `revealSecrets`, REST bearer rules by reference to [02](02-security-and-secrets.md).

**Out of scope:** REST path mapping ([13](13-rest-api.md)), MCP tool names ([12](12-mcp.md)), CLI argv ([11](11-cli.md)), entity field semantics inside `Workspace` / `Service` / `Provider` ([01 §4](01-data-model.md)), business algorithms ([04](04-workspaces-groups-services.md)–[09](09-dataport.md)).

**Wire naming:** camelCase JSON keys; enum raw strings exact as 1.x; UUIDs **uppercase** on output, any case on input ([01 §3.4.5](01-data-model.md)); timestamps ISO-8601 with three fractional digits and `Z` for RPC.

---

## 2. Transport and framing

### 2.1 Transports

| Transport | Path / endpoint | Framing | Auth |
|-----------|-----------------|---------|------|
| **Unix socket (primary)** | See §2.2 | NDJSON (§2.4) | Peer UID == daemon UID; directory `0700`, socket `0600` ([02 §3.9.1](02-security-and-secrets.md)) |
| **REST + SSE/WebSocket** | Loopback only ([02 §3.9.2](02-security-and-secrets.md)) | HTTP + adapter mapping | `Authorization: Bearer` on every request (ADD-08) |
| **MCP bridge** | stdio → Unix socket | Same NDJSON on socket leg | Same as Unix; connection kind `mcp` |

The daemon core speaks **one** logical protocol: JSON-RPC objects over NDJSON. Adapters MUST NOT expose secret plaintext on REST/MCP even if the core would allow `revealSecrets` on Unix.

### 2.2 Unix socket path and runtime directory

| Item | Rule | Source |
|------|------|--------|
| Default data dir | `~/Library/Application Support/Kuma` | [00 brief](00-overview-and-conventions.md), [14 §3.2](14-lifecycle-and-platform.md) |
| Override data dir | Env `KUMA_DATA_DIR` | brief |
| Default runtime dir | `<dataDir>/run/` | [14 §3.2](14-lifecycle-and-platform.md) |
| Override runtime dir | Env `KUMA_RUNTIME_DIR` | `kuma-protocol/src/paths.rs` |
| Socket file | `<runtimeDir>/kuma-daemon.sock` | `paths.rs` `socket_path()` |
| PID file | `<runtimeDir>/kuma-daemon.pid` | `paths.rs` |
| Lock file | `<runtimeDir>/kuma-daemon.lock` | [14 §3.3](14-lifecycle-and-platform.md) |
| Spool | `<runtimeDir>/spool/` | [08 §3.2](08-logs-and-events.md), DEV-12 |

**DEV-113:** The Rust scaffold currently binds under `dirs::data_dir()/Kuma/kuma-daemon.sock` without `run/`. Implementations MUST converge on `<dataDir>/run/`; `daemon.status.runtimeDir` reports the path actually used until then.

### 2.3 Connection lifecycle

1. Client opens `SOCK_STREAM` to the socket path.
2. Server accepts; for each connection, one **reader loop** reads NDJSON lines and writes one response line per request ([`kuma-daemon/src/lib.rs`](../../daemon/crates/kuma-daemon/src/lib.rs)).
3. Multiple requests may be **pipelined** on one connection (responses MUST preserve request order per connection).
4. **Event subscriptions** are bound to the connection that called `events.subscribe`; disconnect cancels the subscription and any `logs.follow` handles ([08 §3.11.5](08-logs-and-events.md)).
5. Empty lines MUST be ignored.
6. On daemon shutdown, the socket is unlinked; in-flight requests MAY fail with I/O error on the client.

**Peer check (normative):** Before processing the first request on a new Unix connection, the daemon MUST verify the peer UID equals the daemon UID. Otherwise close the connection without processing (audit `auth` rejection per [02 §3.10](02-security-and-secrets.md)).

### 2.4 NDJSON framing

Constant `kuma_protocol::jsonrpc::FRAMING` = `"ndjson"`.

- Each **request** is one JSON object encoded UTF-8, terminated by **`\\n` (U+000A)**.
- Each **response** is one JSON object, one line, same terminator (`Response::to_line()` in `jsonrpc.rs`).
- No JSON-RPC **batch** arrays; one object per line.
- Maximum line size SHOULD be **16 MiB**; larger lines MAY be rejected with `ERR_PARSE`.

### 2.5 JSON-RPC request envelope

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `jsonrpc` | string | yes | MUST be `"2.0"` |
| `method` | string | yes | Dotted name from [00 §5](00-overview-and-conventions.md) |
| `params` | object | no | Default `{}`; MUST be object if present |
| `id` | string \| number \| null | no* | *Required for calls expecting a response; omitted only for unsupported notifications |

**Correlation id:** The `id` field is the JSON-RPC correlation handle. Clients SHOULD use monotonic integers or opaque strings. The server MUST echo `id` on the matching response. **`null` id** is reserved for parse errors where the request id could not be read.

**Client request id (event attribution):** Optional string inside `params`:

| Param | Type | JSON key | Purpose |
|-------|------|----------|---------|
| Client request id | string | `clientRequestId` | Copied to emitted event envelopes as `clientRequestId` so clients can suppress self-echoes ([08 §3.11.3](08-logs-and-events.md), [04 §3.9](04-workspaces-groups-services.md)) |

This is **not** a server-side deduplication key; the daemon does not store idempotency keys for arbitrary RPC.

**Notifications:** The daemon does not support JSON-RPC notifications (requests without `id`) for methods that return data; all catalog methods use request/response.

### 2.6 JSON-RPC response envelope

Success:

```json
{"jsonrpc":"2.0","id":1,"result":{...}}
```

Failure:

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"...","data":{"kumaCode":"KUMA_SVC_NOT_FOUND","details":{}}}}
```

| Field | Type | Notes |
|-------|------|-------|
| `jsonrpc` | string | `"2.0"` |
| `id` | same as request | |
| `result` | object | Present on success; omitted on error |
| `error` | object | Present on failure; omitted on success |

### 2.7 Event stream on the same connection

After `events.subscribe`, the server interleaves **event lines** on the same NDJSON stream. Each event line is a JSON object:

| Field | Type | JSON key |
|-------|------|----------|
| Discriminator | string | `"type": "event"` |
| Subscription | string | `subscriptionId` |
| Envelope | object | `event` — see §7 |

Event lines are **not** JSON-RPC responses (no `jsonrpc` field). Clients MUST distinguish:

- Object with `"jsonrpc":"2.0"` → RPC response.
- Object with `"type":"event"` → bus delivery.

---

## 3. Error model

### 3.1 JSON-RPC layer (transport / syntax)

| Code | Name | When | `message` (exact) |
|------|------|------|-------------------|
| `-32700` | Parse error | Invalid JSON on a line | `parse error` (scaffold) |
| `-32600` | Invalid Request | `jsonrpc` ≠ `2.0`, non-object params where object required | `jsonrpc must be 2.0` (scaffold) |
| `-32601` | Method not found | Unknown `method` | `method not found: <method>` |
| `-32602` | Invalid params | Schema validation failure (wrong type, unknown key on strict methods, missing required field) | Human-readable, no secrets |
| `-32603` | Internal error | Unexpected panic-level failure | Generic; details only in logs |

Constants in `kuma-protocol/src/jsonrpc.rs`: `ERR_PARSE`, `ERR_INVALID_REQUEST`, `ERR_METHOD_NOT_FOUND`.

### 3.2 Application layer (`error.data`)

Every application error MUST include:

| Field | Type | JSON key | Required |
|-------|------|----------|----------|
| Stable code | string | `kumaCode` | yes |
| Details | object | `details` | no |

Recommended JSON-RPC `error.code`: **`-32000 - (area ordinal)`** or a flat **`-32001`** family; adapters MAY map `kumaCode` to HTTP status ([13](13-rest-api.md)). The **`kumaCode` string is authoritative** for clients.

**Message redaction:** `error.message` and all strings inside `error.data` MUST pass **`strict`** redaction ([02 §3.12](02-security-and-secrets.md)) after the exact user-facing text is composed.

### 3.3 Global application codes (defined here)

| `kumaCode` | Condition | Exact / normative `message` |
|------------|-----------|----------------------------|
| `KUMA_CONFLICT_STALE` | `expectedUpdatedAt` mismatch on entity or settings key | Entity writes: `The record was modified by another client.` Settings ([03 §3.4.6](03-settings-and-environment.md)): `Setting '<key>' was modified by another client` |
| `KUMA_DAT_INVALID_UUID` | UUID param not 36-char hyphenated hex | `Invalid UUID: <value>` ([01](01-data-model.md)) |
| `KUMA_DAT_INVALID_TIMESTAMP` | Timestamp param not accepted | `Invalid timestamp: <value>` |
| `KUMA_DAT_INVALID_ENUM` | Unknown enum raw value | `Invalid value '<value>' for <field>` |
| `KUMA_SEC_REVEAL_FORBIDDEN` | `revealSecrets: true` on forbidden transport/kind | `Revealing secrets is only allowed over the local Unix socket.` ([02](02-security-and-secrets.md)) |
| `KUMA_SEC_TOKEN_MISSING` | REST without bearer | `Authentication required: missing bearer token.` |
| `KUMA_SEC_TOKEN_INVALID` | REST bearer mismatch | `Authentication failed: invalid bearer token.` |

Domain codes (`KUMA_SVC_*`, `KUMA_EXE_*`, `KUMA_K8S_*`, `KUMA_LOG_*`, `KUMA_DPT_*`, `KUMA_SET_*`, `KUMA_PRV_*`, `KUMA_LIF_*`, …) are listed per method in §6 and in owning specs ([04](04-workspaces-groups-services.md)–[09](09-dataport.md)).

### 3.4 Partial update and unknown keys

For `*.update` methods ([04 §3.1](04-workspaces-groups-services.md)):

- Absent key → unchanged.
- Explicit JSON `null` → clear optional field.
- Unknown keys → `-32602` invalid params.

### 3.5 Failures vs normal results

- `service.preflight` NEVER returns configuration issues as RPC errors; issues appear in `result.issues` ([05 §3.8](05-providers-and-validation.md)).
- `service.stop` is **infallible on the wire** (always returns `state: stopped`) ([06](06-execution-engine.md) INV-D-EXE-15).

---

## 4. Versioning and capability negotiation

### 4.1 Protocol version

| Constant | Value (current scaffold) | Location |
|----------|--------------------------|----------|
| `PROTOCOL_VERSION` | `"0.1"` | `kuma-protocol/src/lib.rs` |

`daemon.ping` and `daemon.status` return `protocolVersion`. Clients SHOULD compare after connect:

1. If server version **major** differs from client expectation → stop and prompt upgrade.
2. Minor/patch differences → continue; unknown methods return `-32601`.

There is **no** separate capability bitmap in v0.1; optional methods are implied by daemon version and presence in this catalog.

### 4.2 Connection kind (proposed extension)

On **`daemon.ping`** only, optional param ([02 Proposed](02-security-and-secrets.md)):

| Param | Values | Default |
|-------|--------|---------|
| `clientKind` | `cli`, `app`, `mcp`, `rest` | `cli` |

Result echoes `clientKind`. Rules:

- Declaring `mcp` or `rest` on a connection is **sticky**; later ping cannot upgrade to `cli`/`app` for `revealSecrets`.
- Governs `revealSecrets` eligibility and audit `transport` attribution.

### 4.3 Entity and backup formats

- RPC entity shapes track [01 §4](01-data-model.md) and migration level of `kuma.sqlite`.
- Export/import JSON backup `version` field is owned by [09](09-dataport.md) (constant `1`); independent of `PROTOCOL_VERSION`.

---

## 5. Concurrency tokens and idempotent methods

### 5.1 Optimistic concurrency (`expectedUpdatedAt`)

Optional on mutating calls ([00 brief](00-overview-and-conventions.md), [01 §3.13](01-data-model.md)):

| Methods accepting token | Token names row |
|-------------------------|-----------------|
| `workspace.update`, `workspace.set_image`, `workspace.clear_image` | workspace |
| `group.update` | group |
| `service.update`, `service.set_starred`, `service.set_disabled`, `service.switch_provider` | service |
| `provider.add`, `provider.update`, `provider.delete` | **service** (parent) |
| `settings.set` | per-key map in `expectedUpdatedAt` object ([03 §3.4.6](03-settings-and-environment.md)) |

Comparison uses **millisecond** epoch parsed from ISO timestamp strings. Mismatch → `KUMA_CONFLICT_STALE`, no write. Absent token → last-write-wins (1.x parity).

### 5.2 Behavioral idempotency (safe retry)

| Method | Idempotent behavior |
|--------|---------------------|
| `daemon.ping`, `daemon.status` | No side effects |
| `daemon.shutdown` | Second call while shutting down → `{accepted: true}` ([14 §3.6](14-lifecycle-and-platform.md)) |
| `service.start` | Active workload → success with `alreadyRunning: true`, no state change ([06 §3.6](06-execution-engine.md)) |
| `service.stop` | Always runs stop pipeline; already stopped → stable `stopped` |
| `service.restart` | Not idempotent (stop+start) |
| `events.unsubscribe` | Unknown id → success |
| `settings.reset` | Repeat → same end state |
| `logs.clear` | Cleared buffer stays cleared |
| Read methods (`*.list`, `*.get`, `*.status*`, `env.*`, `ports.check`, …) | Pure reads |

**No server-side idempotency-key store:** Repeating `service.create` creates duplicate rows unless the client uses `expectedUpdatedAt` on a follow-up update.

### 5.3 Serialization (GR-03)

State-changing calls on the same **entity id** MUST be serialized by the daemon ([00 §8 GR-03](00-overview-and-conventions.md)). Execution per-service **Lane** FIFO is defined in [06 §3.5.4](06-execution-engine.md) (`service.start` / `stop` / `restart`).

---

## 6. Method catalog

Registry authority: [00 §5](00-overview-and-conventions.md). **Count: 74 methods** (73 on REST/MCP; `daemon.rotate_api_token` is Unix-socket-only).

Legend for subsections:

- **Params / Result** — JSON object shapes; entity types → [01 §4](01-data-model.md).
- **Errors** — primary `kumaCode` values; `…` = see owning spec.
- **Idempotent** — see §5.2.
- **Events** — emitted after successful commit unless noted.
- **Cross-ref** — FEAT ids (representative) and normative behavior spec.

Common optional params on many methods:

| Param | Type | Methods |
|-------|------|---------|
| `revealSecrets` | bool, default `false` | `service.get`, `service.list`, `provider.list`, `provider.add`, `provider.update`, `kubeconfig.list`, `kubeconfig.get`, `kubeconfig.create`, `kubeconfig.update` — [02 §3.11](02-security-and-secrets.md) |
| `clientRequestId` | string | All mutating methods (recommended) |

---

### 6.1 Daemon and settings (12 methods)

#### 6.1.1 `daemon.ping`

| | |
|--|--|
| **Tag** | PARITY-infra |
| **Params** | `{}` or `{ "clientKind"?: "cli"\|"app"\|"mcp"\|"rest" }` ([02 proposed](02-security-and-secrets.md)) |
| **Result** | `{ "pong": true, "protocolVersion": "0.1", "clientKind"?: string }` |
| **Errors** | — |
| **Idempotent** | Yes |
| **Events** | — |
| **FEAT** | FEAT-LIF-02, FEAT-LIF-04 |
| **Spec** | [14 §3.4](14-lifecycle-and-platform.md), scaffold `lib.rs:91-96` |

#### 6.1.2 `daemon.status`

| | |
|--|--|
| **Tag** | ADD-06 |
| **Params** | `{}` |
| **Result** | `{ version, protocolVersion, uptimeSecs, dataDir, runtimeDir, socketPath, dbPath, daemonStatePath, schemaMigrations[], workspaceCount, serviceCount, runningServices[{serviceID, serviceName, mode, pid?}], legacyAppRunning, adoptReport?, instanceId }` — [14 §4.1](14-lifecycle-and-platform.md) |
| **Errors** | — |
| **Idempotent** | Yes |
| **Events** | — |
| **FEAT** | FEAT-LIF-03, FEAT-LIF-05, FEAT-LIF-24 |
| **Spec** | [14 §3.5](14-lifecycle-and-platform.md) |

#### 6.1.3 `daemon.shutdown`

| | |
|--|--|
| **Tag** | ADD-06 |
| **Params** | `{ "stopServices"?: bool (default false), "composeDown"?: bool (default true when stopping) }` |
| **Result** | `{ "accepted": true }` (async shutdown) |
| **Errors** | `KUMA_LIF_SHUTDOWN_IN_PROGRESS` (optional) |
| **Idempotent** | Yes while shutting down |
| **Events** | `daemon.shutting_down` before stop work |
| **FEAT** | FEAT-LIF-06, FEAT-LIF-07 |
| **Spec** | [14 §3.6](14-lifecycle-and-platform.md) |

#### 6.1.4 `settings.list`

| | |
|--|--|
| **Params** | `{ "prefix"?: string, "includeClient"?: bool (default true) }` |
| **Result** | `{ "settings": Setting[] }` — all 26 registered keys + `client.*` rows ([03 §3.5](03-settings-and-environment.md), §4.1) |
| **Errors** | — |
| **Idempotent** | Yes |
| **Events** | — |
| **FEAT** | FEAT-SET-* |
| **Spec** | [03 §3.5](03-settings-and-environment.md) |

#### 6.1.5 `settings.get`

| | |
|--|--|
| **Params** | `{ "key": string }` |
| **Result** | `Setting` |
| **Errors** | `KUMA_SET_UNKNOWN_KEY` (unknown non-`client.*` key) |
| **Idempotent** | Yes |
| **Events** | — |
| **Spec** | [03 §3.5](03-settings-and-environment.md) |

#### 6.1.6 `settings.set`

| | |
|--|--|
| **Params** | `{ "values": object, "strict"?: bool, "expectedUpdatedAt"?: object }` ([03 §4.2](03-settings-and-environment.md)) |
| **Result** | `{ "updated": Setting[], "removed": string[], "validation": object }` |
| **Errors** | `KUMA_SET_*`, `KUMA_CONFLICT_STALE` |
| **Idempotent** | No |
| **Events** | `settings.changed` `{ reason: "set", keys, values? }` |
| **Spec** | [03 §3.4](03-settings-and-environment.md) |

#### 6.1.7 `settings.reset`

| | |
|--|--|
| **Params** | `{}` |
| **Result** | `{ "removed": string[], "keys": string[22] }` |
| **Errors** | — |
| **Idempotent** | Yes |
| **Events** | `settings.changed` `{ reason: "reset", keys: all 22 }` |
| **Spec** | [03 §3.6](03-settings-and-environment.md) |

#### 6.1.8 `env.path` / `env.refresh` / `env.resolve_executable` / `env.validate_binary` / `env.dependencies`

| Method | Params | Result |
|--------|--------|--------|
| `env.path` | `{}` | `{ path, directories[], shell, customPaths, cached }` ([03 §4.5](03-settings-and-environment.md)) |
| `env.refresh` | `{}` | Same as `env.path` with `cached: false` |
| `env.resolve_executable` | `{ "command": string }` | `{ command, path, source }` |
| `env.validate_binary` | `{ path, expectedCommand }` | `Validation` ([03 §4.3](03-settings-and-environment.md)) |
| `env.dependencies` | `{}` | `{ engines[], tunneling[], status{} }` ([03 §4.4](03-settings-and-environment.md)) |

All read-only; no RPC errors on bad paths (empty/invalid → valid JSON with nulls). **FEAT-SET-***. **Spec** [03 §3.10–3.11](03-settings-and-environment.md).

---

### 6.2 Workspaces, groups, services, providers (31 methods)

Entity shapes: `Workspace`, `ServiceGroup`, `Service`, `Provider`, `ServicePortMapping`, `ServiceListItem` — [01 §4](01-data-model.md), request tables [04 §4.2–4.5](04-workspaces-groups-services.md).

#### 6.2.1 Workspace (10)

| Method | Params | Result | Errors | Events | FEAT |
|--------|--------|--------|--------|--------|------|
| `workspace.list` | none | `{workspaces[]}` | — | — | FEAT-WS-01 |
| `workspace.get` | `{id}` | `{workspace}` | `KUMA_WS_NOT_FOUND` | — | FEAT-WS-02 |
| `workspace.create` | `{name?, imageBase64?}` | `{workspace}` | validation | `workspace.changed` created | FEAT-WS-03 |
| `workspace.update` | `{id, name?, imageBase64?, clearImage?, expectedUpdatedAt?}` | `{workspace}` | `KUMA_WS_*`, stale | `workspace.changed` updated | FEAT-WS-04 |
| `workspace.delete` | `{id}` | `{deleted, nextWorkspaceId}` | never-zero | `workspace.changed` deleted | FEAT-WS-05, DEV-03 stop services |
| `workspace.reorder` | `{workspaceIDs[]}` **or** `{fromIndex, toIndex}` | `{workspaces[]}` | invalid | `workspace.changed` reordered | FEAT-WS-07 |
| `workspace.set_image` | `{id, imageBase64, expectedUpdatedAt?}` | `{workspace}` | stale | `workspace.changed` image | FEAT-WS-09 |
| `workspace.clear_image` | `{id, expectedUpdatedAt?}` | `{workspace}` | stale | `workspace.changed` image | FEAT-WS-10 |
| `workspace.get_image` | `{id, size?}` default 128, clamp 1–1024 | `{hasImage, mimeType?, imageBase64?, width?, height?}` | not found | — | FEAT-WS-11 |

Normative behavior: [04 §3.2–3.4](04-workspaces-groups-services.md).

#### 6.2.2 Group (5)

| Method | Params | Result | Errors | Events |
|--------|--------|--------|--------|--------|
| `group.list` | `{workspaceID}` | `{groups[]}` | — (unknown ws → `[]`) | — |
| `group.create` | `{workspaceID, name?}` | `{group}` | ws missing | `group.changed` created |
| `group.update` | `{id, name, expectedUpdatedAt?}` | `{group}` | `KUMA_GRP_NOT_FOUND`, stale | updated |
| `group.delete` | `{id}` | `{deleted: true}` | not found | deleted |
| `group.reorder` | `{workspaceID, groupIDs[]}` permutation | `{groups[]}` | `KUMA_GRP_REORDER_INVALID` | reordered |

FEAT: FEAT-GRP-*. Spec: [04 §3.3](04-workspaces-groups-services.md).

#### 6.2.3 Service (11)

| Method | Params | Result | Errors | Events |
|--------|--------|--------|--------|--------|
| `service.list` | `{workspaceID, search?, starredOnly?, groupID?, statuses?, providers?, sort?}` | `{items[], totalCount}` | — | — |
| `service.get` | `{id}` | `{service, providers[], portMappings[], activeProviderID?, runtime, liveTarget?}` | `KUMA_SVC_NOT_FOUND` | — |
| `service.create` | `{workspaceID, name, …, provider, ports?}` | as `service.get` | `KUMA_PRV_*`, `KUMA_SVC_*` | `service.created` |
| `service.update` | `{id, name?, description?, icon?, colorHex?, groupIDs?, expectedUpdatedAt?}` | `{service}` | stale, not found | `service.updated` |
| `service.delete` | `{id}` | `{deleted: true}` | not found | `service.deleted`; stops first DEV-14 | 
| `service.duplicate` | `{id}` | as `service.get` (new id) | source missing | `service.created` |
| `service.set_starred` | `{id, starred?, expectedUpdatedAt?}` toggle if absent | `{service}` | not found | `service.updated` |
| `service.set_disabled` | `{id, disabled, expectedUpdatedAt?}` | `{service}` | not found | `service.updated`; stops if disabling |
| `service.set_groups` | `{id, groupIDs[]}` | `{id, groupIDs[]}` | DEV-54 | `service.updated` memberships |
| `service.toggle_group` | `{id, groupID}` | `{id, groupIDs[]}` | svc/grp missing | `service.updated` memberships |
| `service.switch_provider` | `{id, providerID, expectedUpdatedAt?}` | `{service, activeProviderID, changed, restart{}}` | stale | `service.updated`; may stop/start |

Deck filter semantics: [04 §3.7–3.8](04-workspaces-groups-services.md). FEAT: FEAT-SVC-*.

#### 6.2.4 Provider (5)

| Method | Params | Result | Errors | Events |
|--------|--------|--------|--------|--------|
| `provider.list` | `{serviceID}` | `{providers[], activeProviderID?}` | svc missing | — |
| `provider.add` | `{serviceID, provider{}, expectedUpdatedAt?}` | `{provider, service, activeProviderID}` | validation | `service.updated` providers |
| `provider.update` | `{id, …fields, expectedUpdatedAt?}` | `{provider}` | `KUMA_SVC_PROVIDER_NOT_FOUND` | `service.updated` providers |
| `provider.delete` | `{id, expectedUpdatedAt?}` | `{deleted, activeProviderID?}` | not found | `service.updated` |
| `provider.set_ports` | `{serviceID, providerID, ports[]}` | `{portMappings[]}` | validation | `service.updated` ports |

Provider field matrix: [05](05-providers-and-validation.md). FEAT: FEAT-PRV-* / FEAT-SVC-*.

---

### 6.3 Validation and execution (10 methods)

#### 6.3.1 `service.preflight` (ADD-01)

| | |
|--|--|
| **Params** | `{ serviceID, providerID?, probe?: true, refresh?: false, recordToActivityLog?: false }` |
| **Result** | `{ serviceID, providerID, providerType, serviceDisabled, ok, probed, issues[], kubernetes? }` — [05 §4.3](05-providers-and-validation.md) |
| **Errors** | `KUMA_SVC_NOT_FOUND`, `KUMA_PRV_PROVIDER_NOT_FOUND` only |
| **Idempotent** | Read-only |
| **Events** | Optional `[CONFIG]` lines → `service.log_line` when `recordToActivityLog` |
| **FEAT** | FEAT-PRV-31, ADD-01 |
| **Spec** | [05 §3.8](05-providers-and-validation.md) |

#### 6.3.2 `service.start`

| | |
|--|--|
| **Params** | `{ serviceID }` |
| **Result** | `{ serviceID, state, pid?, alreadyRunning }` — [06 §4.1](06-execution-engine.md) |
| **Errors** | `KUMA_EXE_*` (disabled, port, config, binary, …); port → `details.portConflict: true` |
| **Idempotent** | Yes when already running |
| **Events** | `service.state_changed`, activity `service.log_line`, maybe `notify` |
| **FEAT** | FEAT-EXE-09 |
| **Spec** | [06 §3.6](06-execution-engine.md) |

#### 6.3.3 `service.stop`

| | |
|--|--|
| **Params** | `{ serviceID }` |
| **Result** | `{ serviceID, state: "stopped", forced: bool }` |
| **Errors** | none (infallible) |
| **Idempotent** | Yes |
| **Events** | `service.state_changed` |
| **Spec** | [06 §3.7](06-execution-engine.md) |

#### 6.3.4 `service.restart`

| | |
|--|--|
| **Params** | `{ serviceID }` |
| **Result** | start result + `{ restarted: true }` |
| **Errors** | same as start after stop |
| **Idempotent** | No |
| **Spec** | [06 §3.7](06-execution-engine.md) (300 ms delay) |

#### 6.3.5 `service.start_all` / `service.stop_all`

| | |
|--|--|
| **Params** | Same filters as `service.list` + optional `serviceIDs[]` — [06 §3.8](06-execution-engine.md) |
| **Result start** | `{ results[], started, skipped, failed }` |
| **Result stop** | `{ results[], stopped, skipped }` |
| **Errors** | per-target failures embedded in `results` |
| **Events** | batched `service.state_changed` |
| **FEAT** | FEAT-EXE-14 |
| **Spec** | [06 §3.8](06-execution-engine.md) |

#### 6.3.6 `service.status` / `service.statuses`

| | |
|--|--|
| **Params** | `{ serviceID }` / `{ serviceIDs?: UUID[] }` (omit = all) |
| **Result** | `ServiceRuntimeState` wire table [06 §3.3](06-execution-engine.md) |
| **Errors** | unknown id → empty/default runtime |
| **Idempotent** | Yes |
| **FEAT** | FEAT-EXE-05 |
| **Spec** | [06 §4.4](06-execution-engine.md) |

#### 6.3.7 `ports.check` (ADD-02)

| | |
|--|--|
| **Params** | `{ port: 1–65535, excludingServiceID?: UUID }` |
| **Result** | `{ port, occupants[], foreignOccupants[], effectivePolicy, wouldBlockStart }` — [06 §3.13.4](06-execution-engine.md) |
| **Errors** | invalid port → `-32602` |
| **Idempotent** | Yes |
| **FEAT** | FEAT-EXE-32, ADD-02 |

#### 6.3.8 `runtime.adopt_report` (ADD-03)

| | |
|--|--|
| **Params** | `{}` |
| **Result** | `{ completedAt, entries[{serviceID, serviceName, mode, outcome, reason?}] }` — [06 §3.11.3](06-execution-engine.md) |
| **Errors** | — |
| **Idempotent** | Yes (snapshot of last boot pass) |
| **FEAT** | FEAT-LIF-09, ADD-03 |

---

### 6.4 Kubernetes (10 methods)

Kubeconfig wire objects: [07 §4](07-kubernetes.md). Default virtual id `00000000-0000-0000-0000-000000000001`.

| Method | Params | Result | Errors | Events |
|--------|--------|--------|--------|--------|
| `kubeconfig.list` | `{}` | `{ kubeconfigs[] }` incl. Default | — | — |
| `kubeconfig.get` | `{ id }` | Kubeconfig DTO + `hasContent` / paths | `KUMA_K8S_NOT_FOUND` | — |
| `kubeconfig.create` | fields per [07 §3.5.2](07-kubernetes.md) | `{ kubeconfig }` | validation | `kubeconfig.changed` created |
| `kubeconfig.update` | `{ id, … }` | `{ kubeconfig }` | not found, Default rules | updated |
| `kubeconfig.delete` | `{ id }` | `{ deleted: true }` | cannot delete Default | deleted |
| `kubeconfig.contexts` | `{ kubeConfigID? }` | `{ contexts[], currentContext? }` | — | — |
| `kubeconfig.test_connection` | `{ kubeConfigID?, context?, refresh? }` | `{ reachable, errorMessage?, verifiedAt }` | — | — |
| `k8s.resolve_target` | `{ serviceID \| provider fields… }` per [07 §3.17](07-kubernetes.md) | `{ kind, name, kubectlReference }` | resolution failures | — |
| `k8s.namespaces` | `{ kubeConfigID?, context? }` (ADD-04) | `{ namespaces[] }` | kubectl errors | — |
| `k8s.resources` | `{ kubeConfigID?, context?, namespace?, resourceType }` | `{ resources[] }` | — | — |

**FEAT:** FEAT-K8S-01 … FEAT-K8S-22. **Spec:** [07](07-kubernetes.md).

---

### 6.5 Logs and events RPC (6 methods)

| Method | Params | Result | Errors | Events |
|--------|--------|--------|--------|--------|
| `logs.tail` | `{ serviceID, sinceRevision?: u64 }` | `{ serviceID, revision, lines[], didTrimToMaxLines }` | `KUMA_SVC_NOT_FOUND` | — |
| `logs.clear` | `{ serviceID }` | `{ cleared: true }` | not found | — |
| `logs.workload_tail` | `{ serviceID, maxLines? }` default 200 | `{ serviceID, text, truncated }` | `KUMA_LOG_WORKLOAD_UNAVAILABLE` | — |
| `logs.follow` | `{ serviceID, subscriptionID?, stop?: bool }` | `{ serviceID, following: bool }` | follow conflicts | streams `service.log_line` workload |
| `events.subscribe` | `{ topics?, sinceSeq? }` | `{ subscriptionId, replayFromSeq, replayTruncated }` + stream | — | see §7 |
| `events.unsubscribe` | `{ subscriptionId }` | `{ unsubscribed: true }` | — | — |

Activity line shape: [08 §4.1](08-logs-and-events.md). **FEAT:** FEAT-LOG-*. **Spec:** [08 §3.7–3.11](08-logs-and-events.md).

---

### 6.6 DataPort (5 methods)

| Method | Params | Result | Errors | Events |
|--------|--------|--------|--------|--------|
| `data.export` | `{ scope: "all" \| {workspaceId} \| {serviceId} }` | `{ jsonBase64, suggestedFileName }` | export failures | — |
| `data.export_service_json` | `{ serviceId }` | `{ json: string }` SingleServiceExport | not found | — |
| `data.import_preview` | `{ json \| jsonBase64, mode, targetWorkspaceID? }` | preview rows ([09 §3.11](09-dataport.md)) | parse errors | — |
| `data.import` | `{ strategy, selectedWorkspaceIds, selectedServiceIds, resolvedNames?, targetWorkspaceId? }` | `{ imported: { workspaces, services, providers } }` | `KUMA_DPT_*` | `data.imported`, `settings.changed`? |
| `data.factory_reset` | `{ stopServices?: true }` | `{ reset: true }` | wipe failures | `data.reset` |

Secrets in preview/import results masked ([02](02-security-and-secrets.md)). Export bytes contain ciphertext as 1.x. **FEAT:** FEAT-DPT-*. **Spec:** [09](09-dataport.md).

---

### 6.7 Method index (quick reference)

| § | Methods |
|---|---------|
| 6.1 | `daemon.ping`, `daemon.status`, `daemon.shutdown`, `settings.list`, `settings.get`, `settings.set`, `settings.reset`, `env.path`, `env.resolve_executable`, `env.validate_binary`, `env.dependencies`, `env.refresh` |
| 6.2 | all `workspace.*`, `group.*`, `service.*`, `provider.*` (31) |
| 6.3 | `service.preflight`, `service.start`, `service.stop`, `service.restart`, `service.start_all`, `service.stop_all`, `service.status`, `service.statuses`, `ports.check`, `runtime.adopt_report` |
| 6.4 | all `kubeconfig.*`, `k8s.*` |
| 6.5 | `logs.tail`, `logs.clear`, `logs.workload_tail`, `logs.follow`, `events.subscribe`, `events.unsubscribe` |
| 6.6 | `data.export`, `data.export_service_json`, `data.import_preview`, `data.import`, `data.factory_reset` |

**Total: 74 methods** (73 exposed on REST/MCP).

---

## 7. Event stream and subscriptions

### 7.1 Registry (13 event names)

Authoritative list: [00 §5.7](00-overview-and-conventions.md).

| # | Event |
|---|-------|
| 1 | `service.state_changed` |
| 2 | `service.log_line` |
| 3 | `service.created` |
| 4 | `service.updated` |
| 5 | `service.deleted` |
| 6 | `group.changed` |
| 7 | `workspace.changed` |
| 8 | `kubeconfig.changed` |
| 9 | `settings.changed` |
| 10 | `notify` |
| 11 | `data.imported` |
| 12 | `data.reset` |
| 13 | `daemon.shutting_down` |

User said "event type count" - I'll report 13 accurately.

### 7.2 Sequence numbers and replay (ADD-07)

| Constant | Value | Spec |
|----------|-------|------|
| `EVENT_REPLAY_CAPACITY` | `10000` | [08 §3.11.2](08-logs-and-events.md) |
| `meta.eventSeq` | persisted u64 | [01](01-data-model.md) |

Rules:

1. Each event gets `seq = previous + 1` before delivery.
2. Persist `meta.eventSeq` to the same value before fan-out.
3. Store payload in `daemon-state.sqlite` `event_replay` table ([08 §3.11.2](08-logs-and-events.md)).
4. Trim rows with `seq <= lastSeq - EVENT_REPLAY_CAPACITY`.

### 7.3 `events.subscribe`

**Params:**

| Field | Type | Default |
|-------|------|---------|
| `topics` | string[] | all registered events |
| `sinceSeq` | u64 | `0` |

**Immediate result:** `{ subscriptionId, replayFromSeq, replayTruncated }`

- Replay: all stored events with `seq > sinceSeq`, ascending, then live.
- If `sinceSeq` older than retained window → start at oldest retained seq, `replayTruncated: true`.

**Stream:** NDJSON lines `{ type: "event", subscriptionId, event: Envelope }`.

### 7.4 `events.unsubscribe`

Params: `{ subscriptionId }`. Idempotent. Cancels `logs.follow` for that subscription.

### 7.5 Event envelope (all types)

| Field | JSON key | Type |
|-------|----------|------|
| Sequence | `seq` | u64 |
| Name | `event` | string |
| Payload | `payload` | object |
| Emitted at | `emittedAt` | ISO-8601 ms UTC |
| Origin | `origin` | string optional |
| Client request id | `clientRequestId` | string optional |

### 7.6 Payload schemas (complete)

#### `service.state_changed`

`{ serviceID, state, pid?, exitCode?, reconnectAttempt?, reconnectMax?, lastFailure?, startedAt?, mode? }` — [06 §3.4.4](06-execution-engine.md), [08 §3.12](08-logs-and-events.md).

#### `service.log_line`

`{ serviceID, lineId, revision, kind: "system"|"workload", category?, text, timestamp }` — redacted per profile.

#### `service.created`

`{ serviceID, workspaceID }`

#### `service.updated`

`{ serviceID, workspaceID, changed: string[] }` — subset of `service`, `providers`, `ports`, `memberships`, `activeProvider`.

#### `service.deleted`

`{ serviceID, workspaceID }` — buffer cleared.

#### `group.changed`

`{ workspaceID, groupID?, change: "created"|"updated"|"deleted"|"reordered" }`

#### `workspace.changed`

`{ workspaceID?, change, changed?, nextWorkspaceId? }`

#### `kubeconfig.changed`

`{ kubeconfigID, change }` — Default id never `deleted`.

#### `settings.changed`

`{ keys[], reason: "set"|"reset"|"import", values? }` — omit `values` on reset.

#### `notify`

`{ kind: "serviceCrash"|"healthCheckFailed"|"portCollision"|"custom", title, body, playSound?, serviceName?, reason?, targetUrl?, port?, collidingService? }` — exact strings [08 §3.12](08-logs-and-events.md), DEV-13 health.

#### `data.imported`

`{ strategy, workspaceCount, serviceCount }`

#### `data.reset`

`{}`

#### `daemon.shutting_down`

`{ stopServices?, composeDown? }` — [14 §3.8.1](14-lifecycle-and-platform.md)

---

## 8. Security on the wire

Normative detail: [02 Security and Secrets](02-security-and-secrets.md). This section states RPC-facing rules only.

### 8.1 Unix socket (local trusted)

- Directory mode **0700**, socket **0600**, owned by daemon uid.
- Peer uid MUST match daemon uid (including rejecting root unless same uid).
- Only this transport MAY honor `revealSecrets: true` for connection kinds `cli` and `app`.
- No bearer token on the socket; filesystem + peer check is authentication.

### 8.2 Secret fields in responses

Default: no `sshPassword`, `ngrokAuthToken`, kubeconfig plaintext; use `sshPasswordSet`, `ngrokAuthTokenSet`, `hasContent`, `sourceFilePath` ([02 §3.11](02-security-and-secrets.md)).

`revealSecrets: true` on allowed methods + allowed connection → include plaintext fields.

**Events always masked** — `revealSecrets` does not apply to events.

### 8.3 REST (ADD-08)

- Loopback bind; `Authorization: Bearer <token>` every request; token never in URL.
- `revealSecrets` always refused → `KUMA_SEC_REVEAL_FORBIDDEN`.
- Adapter marks transport `rest`.

### 8.4 MCP

- Bridge over Unix same uid; kind `mcp`.
- MUST NOT send `revealSecrets`; daemon refuses if sent.

### 8.5 Audit

Mutating RPCs and secret-bearing reads logged to `<dataDir>/audit.log` ([02 §3.10](02-security-and-secrets.md)). `daemon.ping`, `daemon.status`, reads without reveal exempt.

---

## 9. Invariants, acceptance tests, proposed RPC

### 9.1 Invariants (RPC area)

| Id | Statement |
|----|-----------|
| INV-D-RPC-01 | Every line on the Unix socket is exactly one JSON value + `\n`. |
| INV-D-RPC-02 | Every method in [00 §5](00-overview-and-conventions.md) appears in §6 with params and result. |
| INV-D-RPC-03 | `error.data.kumaCode` is present on all application errors. |
| INV-D-RPC-04 | Event `seq` strictly increases and matches `meta.eventSeq` after each emit ([08 INV-D-LOG-08](08-logs-and-events.md)). |
| INV-D-RPC-05 | No secret material in RPC errors, events, or default responses (GR-04). |

### 9.2 Acceptance tests (representative)

| Id | Arrange | Assert |
|----|---------|--------|
| DT-RPC-01 | NDJSON `daemon.ping` id=1 | Response line parses; `pong`, `protocolVersion` |
| DT-RPC-02 | Unknown method | `-32601`, id echoed |
| DT-RPC-03 | Invalid JSON line | `-32700`, id null |
| DT-RPC-04 | `events.subscribe` `sinceSeq=N` | Replayed seq strictly increasing |
| DT-RPC-05 | `revealSecrets` on REST adapter | `KUMA_SEC_REVEAL_FORBIDDEN` |
| DT-RPC-06 | Stale `expectedUpdatedAt` on `service.update` | `KUMA_CONFLICT_STALE`, no DB change |
| DT-RPC-07 | `service.start` twice while running | Second `alreadyRunning: true` |

Full matrices: [15](15-traceability-and-parity.md), per-area `DT-*` in specs 01–09, 14.

### 9.3 Parameter extensions (not new methods)

Registry includes **`daemon.rotate_api_token`** in [00 §5.1](00-overview-and-conventions.md) (socket-only; not on REST/MCP).

| Extension | Notes |
|-----------|--------|
| `daemon.ping.clientKind` | Connection kind ([02](02-security-and-secrets.md)). |
| `revealSecrets` | On listed read/write kube/provider/service methods ([02](02-security-and-secrets.md)). |

### 9.4 Open questions / residual risks

1. **Scaffold socket path (DEV-113)** — clients must tolerate `runtimeDir` from `daemon.status` until `run/` layout ships.
2. **Replay truncation** — clients with stale `sinceSeq` miss events except `replayTruncated` flag ([08](08-logs-and-events.md)).
3. **Pipelining vs ordering** — adapters assuming strict global ordering across connections are incorrect; only per-connection order is guaranteed.

---

## Appendix A — Wire type references

| Type | Document |
|------|----------|
| `Workspace`, `Service`, `Provider`, … | [01 §4](01-data-model.md) |
| `Setting`, `Validation` | [03 §4](03-settings-and-environment.md) |
| `ServiceListItem`, deck filters | [04 §3.7](04-workspaces-groups-services.md) |
| `Issue`, preflight, provider create | [05 §4](05-providers-and-validation.md) |
| `ServiceRuntimeState`, start/stop results | [06 §4](06-execution-engine.md) |
| Kube DTOs | [07 §4](07-kubernetes.md) |
| `ActivityLine`, event payloads | [08 §4](08-logs-and-events.md) |
| Import preview rows | [09 §4.7](09-dataport.md) |
| `daemon.status` | [14 §4.1](14-lifecycle-and-platform.md) |

---

## Appendix B — Features table (RPC protocol)

| FEAT id | Tag | Description | RPC |
|---------|-----|-------------|-----|
| FEAT-RPC-01 | [V2-ADD] | NDJSON JSON-RPC 2.0 on Unix socket | transport |
| FEAT-RPC-02 | [V2-ADD] | Stable `kumaCode` in error.data | §3 |
| FEAT-RPC-03 | [V2-ADD] | Full method catalog (74 registry methods) | §6 |
| FEAT-RPC-04 | [V2-ADD] | Event bus with seq replay ADD-07 | §7 |
| FEAT-RPC-05 | [V2-ADD] | `expectedUpdatedAt` concurrency | §5 |
| FEAT-RPC-06 | [V2-ADD] | `clientRequestId` → event attribution | §2.5 |

---

## Appendix C — Error catalog (protocol layer)

| `kumaCode` | Condition | Message |
|------------|-----------|---------|
| `KUMA_CONFLICT_STALE` | §5.1 | §3.3 |
| `KUMA_DAT_INVALID_UUID` | Bad UUID param | §3.3 |
| `KUMA_DAT_INVALID_TIMESTAMP` | Bad timestamp | §3.3 |
| `KUMA_DAT_INVALID_ENUM` | Bad enum | §3.3 |
| `KUMA_SEC_REVEAL_FORBIDDEN` | reveal on wrong transport | §3.3 |
| `KUMA_SEC_TOKEN_MISSING` | REST auth | §3.3 |
| `KUMA_SEC_TOKEN_INVALID` | REST auth | §3.3 |

Domain errors: see §6 per method and owning spec §6.

---

## Appendix D — 1.x source of truth (scaffold)

| Path | Relevance |
|------|-----------|
| `daemon/crates/kuma-protocol/src/jsonrpc.rs` | NDJSON, Request/Response, error constants |
| `daemon/crates/kuma-protocol/src/paths.rs` | Socket path, `KUMA_RUNTIME_DIR` |
| `daemon/crates/kuma-protocol/src/lib.rs` | `PROTOCOL_VERSION` |
| `daemon/crates/kuma-daemon/src/lib.rs` | Accept loop, `daemon.ping`, stub shutdown |
| `daemon/kuma/src/main.rs` | CLI entry (`kuma daemon run`) — no ping CLI yet |

---

*End of spec 10. Method count: **73**. Event types: **13** (00 §5.7).*
