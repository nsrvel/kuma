# Daemon Spec 13: REST API

> **Status:** Draft for implementation  
> **Area code:** `API` (REST adapter; feature ids `FEAT-API-NN`)  
> **Depends on:** [00 Overview and Conventions](00-overview-and-conventions.md) (RPC registry §5, events §5.7, GR-05), [02 Security and Secrets](02-security-and-secrets.md) (REST auth §3.9.2, redaction, `revealSecrets`), [10 RPC Protocol](10-rpc-protocol.md) (parameter/result schemas), [11 CLI](11-cli.md), [12 MCP](12-mcp.md)  
> **Behavior owned elsewhere:** business rules in [03](03-settings-and-environment.md)–[09](09-dataport.md), [14](14-lifecycle-and-platform.md); wire semantics in [10](10-rpc-protocol.md).

---

## 1. Purpose and scope

This spec defines the **HTTP/1.1 REST adapter** that exposes every RPC method in [00 §5](00-overview-and-conventions.md) as one or more HTTP routes. The REST surface is a **thin transport**: each handler validates auth, maps HTTP to an internal RPC call with `transport: rest`, and returns the RPC result shape unchanged (JSON keys, enum strings, UUID casing).

In scope:

- Base URL, versioning, request/response envelopes, and HTTP status mapping.
- **Resource-oriented routes** (verbs + paths) with a **1:1** mapping to RPC method names (§3.6, §10).
- Authentication: **local loopback bearer token** ([ADD-08](02-security-and-secrets.md), [02 §3.9.2](02-security-and-secrets.md)); optional **future mTLS** profile (§3.2.2, not enabled in V2 loopback mode).
- Binary responses (workspace avatar, backup export).
- **Server-Sent Events (SSE)** for `events.subscribe` and `logs.follow` ([V2-ADD], [ADD-07](08-logs-and-events.md)); optional **WebSocket** upgrade for the same streams ([V2-ADD], [ADD-121](#7-deviations)).

Out of scope: RPC parameter semantics (see owning feature specs + [10](10-rpc-protocol.md)); Unix socket JSON-RPC ([10](10-rpc-protocol.md)); MCP stdio bridge ([12](12-mcp.md)); SwiftUI ([CLIENT]).

**1.x baseline:** Kuma 1.x had **no** HTTP listener. The REST adapter is entirely **[V2-ADD]**; parity features are reached through RPC equivalence, not through reproducing a legacy HTTP API.

---

## 2. 1.x source of truth (paths read)

| Path | Relevance |
|------|-----------|
| (none for HTTP) | No REST server in 1.x |
| `docs/specs/07-kuma-daemon.md` | Client-only architecture; daemon as sole owner |
| `docs/specs/daemon/00-overview-and-conventions.md` | RPC catalog, GR-05, area `API` |
| `docs/specs/daemon/02-security-and-secrets.md` | REST bind, bearer, Host/Origin, audit |
| `docs/specs/daemon/08-logs-and-events.md` | `events.subscribe`, `logs.follow`, replay |
| `docs/specs/daemon/14-lifecycle-and-platform.md` | `daemon.ping`, `daemon.status`, `daemon.shutdown` |
| Feature specs [04](04-workspaces-groups-services.md)–[09](09-dataport.md) | RPC behavior referenced by routes |

---

## 3. Normative behavior

### 3.1 Listener and base URL

| Name | Value | Notes |
|------|-------|-------|
| `REST_DEFAULT_BIND` | `127.0.0.1` | [02 §3.9.2](02-security-and-secrets.md); `::1` MAY be added |
| `REST_DEFAULT_PORT` | `9364` | [ADD-120](#7-deviations); override `KUMA_REST_PORT` |
| `REST_ENABLED` | listener starts when `KUMA_REST=1` or `kuma daemon run --rest` | [ADD-120](#7-deviations) |
| `REST_API_PREFIX` | `/v1` | All routes below are relative to this prefix |
| `REST_BASE_URL` | `http://127.0.0.1:<port>/v1` | No TLS on loopback in V2 |

The REST listener MUST start **after** step S5 (Unix socket) and **before** or with step S13 ([14 §3.2](14-lifecycle-and-platform.md)). `daemon.status` MUST include `restListenAddr` when enabled (see [14](14-lifecycle-and-platform.md) §4.1).

Every response MUST include `Cache-Control: no-store` and `X-Content-Type-Options: nosniff` ([02 §3.9.2](02-security-and-secrets.md)).

### 3.2 Authentication and transport trust

#### 3.2.1 Bearer token (normative V2)

REST auth is defined entirely in [02 §3.9.2](02-security-and-secrets.md). Summary (non-normative if it conflicts with 02):

1. Every request, including `GET`, SSE, and WebSocket upgrade, MUST send `Authorization: Bearer <token>` read from `<data dir>/api-token` ([ADD-08](02-security-and-secrets.md)).
2. `Host` validation and `Origin` rejection apply before routing (02 §3.9.2 items 4–5).
3. The adapter MUST register connection kind `rest`; `revealSecrets: true` in query or body MUST be rejected with `KUMA_SEC_REVEAL_FORBIDDEN` (HTTP 403) without invoking the handler ([02 §3.11](02-security-and-secrets.md)).
4. `daemon.rotate_api_token` and any socket-only RPC MUST NOT be exposed over REST ([02](02-security-and-secrets.md) `KUMA_SEC_LOCAL_ONLY`).

#### 3.2.2 Optional mTLS profile ([V2-ADD], not active in loopback V2)

[02 §3.9.2](02-security-and-secrets.md) states V2 loopback REST has **no TLS**. When a future build enables TLS on the REST listener ([ADD-120](#7-deviations) `tls`), the daemon MAY authenticate clients with **mutual TLS** instead of the bearer token:

| Mode | When | Client auth |
|------|------|-------------|
| `loopback-bearer` | Default; bind `127.0.0.1` / `::1` | Bearer file `api-token` (02 §3.9.2) |
| `tls-mtls` | Non-loopback or explicit `KUMA_REST_TLS=1` | Client certificate verified against a daemon-trusted CA; **no** bearer required on that listener |

Rules for `tls-mtls` (reserved; implement when TLS bind is shipped):

- Server certificate MUST include `127.0.0.1` / `localhost` SANs when still loopback-only.
- Failed handshake MUST NOT fall back to bearer on the same port.
- Audit log `kind: auth`, `transport: rest`, `reason: mtls` on failure.
- All other redaction and `revealSecrets` rules unchanged.

Until `tls-mtls` is implemented, implementations MUST use **loopback-bearer** only.

### 3.3 Request and response mapping

#### 3.3.1 JSON bodies

- **Content-Type:** `application/json; charset=utf-8` for request bodies unless noted.
- **Body shape:** For POST/PATCH/PUT routes, the JSON object MUST match the RPC **params** object in [10](10-rpc-protocol.md) for that method, except:
  - Path parameters (`workspaceId`, `serviceId`, …) MUST NOT be duplicated in the body unless the RPC schema also requires them (then they MUST match).
  - Query parameters MAY supply RPC params when the table in §3.6 marks **Query** (e.g. `service.list` filters).
- **Success body:** The HTTP response body MUST be the RPC **result** object only (not wrapped in `{ "result": … }`). Exception: streaming endpoints (§3.5).
- **UUIDs:** Accept any case in paths and JSON; emit uppercase in JSON responses ([04 §3.0](04-workspaces-groups-services.md)).
- **`expectedUpdatedAt`:** Optional on mutating routes that support optimistic concurrency; same semantics as RPC ([00](00-overview-and-conventions.md)).

#### 3.3.2 Idempotency

HTTP idempotency follows the underlying RPC method (e.g. `GET`, `DELETE` where RPC is idempotent; `POST …/start` follows `service.start`).

#### 3.3.3 Binary and large payloads

| Route pattern | Response `Content-Type` | Body |
|---------------|-------------------------|------|
| `GET …/workspaces/{id}/image` | `image/png` | Raw PNG bytes ([04](04-workspaces-groups-services.md)) |
| `POST /data/export` | `application/json` | Backup JSON bytes (same as RPC `data.export` result field `data` or file-oriented download — see §3.6 DataPort) |
| `GET …/services/{id}/export-json` | `application/json` | Single-service export JSON |

Upload workspace image: `PUT …/image` with `Content-Type: image/png` or JSON `{ "base64": "…" }` if RPC allows both ([10](10-rpc-protocol.md)).

Import preview/import: `Content-Type: application/json` body = backup JSON object **or** `multipart/form-data` with part `file` (implementation MUST support JSON; multipart [V2-ADD] convenience).

### 3.4 Error envelope and HTTP status

Failed requests return JSON:

```json
{
  "error": {
    "code": "KUMA_SVC_NOT_FOUND",
    "message": "Service '…' was not found."
  }
}
```

| Condition | HTTP status |
|-----------|-------------|
| Malformed JSON, unknown query key | 400 |
| `KUMA_SEC_TOKEN_MISSING` / `KUMA_SEC_TOKEN_INVALID` | 401 |
| `KUMA_SEC_HOST_FORBIDDEN`, `KUMA_SEC_ORIGIN_FORBIDDEN`, `KUMA_SEC_REVEAL_FORBIDDEN`, `KUMA_SEC_LOCAL_ONLY` | 403 |
| Entity / subscription not found (`*_NOT_FOUND`, `KUMA_LOG_SUBSCRIPTION_NOT_FOUND`) | 404 |
| `KUMA_CONFLICT_STALE`, port conflict block, validation conflicts | 409 |
| Other `KUMA_*` business errors | 422 |
| Unexpected daemon fault | 500 |

Messages MUST match the error catalog in the owning spec ([04](04-workspaces-groups-services.md)–[09](09-dataport.md), [02](02-security-and-secrets.md)). Security errors use exact strings from [02 §6](02-security-and-secrets.md).

### 3.5 Streaming ([V2-ADD])

#### 3.5.1 Server-Sent Events (primary)

| RPC | HTTP | Stream |
|-----|------|--------|
| `events.subscribe` | `GET /events/stream` | SSE |
| `logs.follow` | `GET /services/{serviceId}/logs/workload/stream` | SSE |

**Request**

- Same auth headers as §3.2.1.
- `Accept: text/event-stream`.
- Query params mirror RPC params: `sinceSeq`, `topics` (repeatable or comma-separated), `subscriptionId` (optional).

**Response**

- `Content-Type: text/event-stream; charset=utf-8`.
- First event: optional comment line `: connected` then an `event: ready` with JSON data `{ "subscriptionId", "replayFromSeq", "replayTruncated" }` matching RPC subscribe result ([08 §3.11.4](08-logs-and-events.md)).
- Each bus event: `event: kuma` (or named `event: <topic>`) with `data: <single-line JSON envelope>` containing `seq`, `name`, `payload`, `ts` per [08](08-logs-and-events.md).
- Activity/workload log lines use the same envelope as RPC `service.log_line`.
- Heartbeat: comment `: ping` every **30 s** if no traffic.
- Client closes TCP to unsubscribe; server MAY also accept `DELETE /events/subscriptions/{subscriptionId}` ([ADD-07](08-logs-and-events.md)).

#### 3.5.2 WebSocket (optional)

When compiled with feature `rest-ws` ([ADD-121](#7-deviations)):

- `GET /events/ws` and `GET /services/{serviceId}/logs/workload/ws` with `Upgrade: websocket`, same query params as SSE.
- After upgrade, server sends JSON text frames (one envelope per frame), same schema as SSE `data`.
- Close **1008** on token rotation ([02 §3.9.2](02-security-and-secrets.md)).
- If WebSocket is not enabled, `GET …/ws` returns **501** with `KUMA_API_STREAM_UNSUPPORTED`: `Streaming transport WebSocket is not enabled on this daemon.`

`events.unsubscribe` over REST: `DELETE /events/subscriptions/{subscriptionId}` → RPC `events.unsubscribe`.

### 3.6 OpenAPI-style route tables (by resource group)

Legend: **Params** = RPC params not carried in path; **Result** = RPC result schema in [10](10-rpc-protocol.md). **Auth** = Bearer §3.2.1 on every row.

#### 3.6.1 Daemon lifecycle and environment

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `GET` | `/daemon/ping` | `daemon.ping` | Query: `clientKind?` | `{ pong, protocolVersion, … }` | 200 |
| `GET` | `/daemon/status` | `daemon.status` | — | Status object ([14 §4.1](14-lifecycle-and-platform.md)) | 200 |
| `POST` | `/daemon/shutdown` | `daemon.shutdown` | Body: `stopServices?`, `composeDown?` | `{ accepted: true }` | 202 |
| `GET` | `/settings` | `settings.list` | — | Settings list | 200 |
| `GET` | `/settings/{key}` | `settings.get` | Path: setting key | One setting | 200 |
| `PUT` | `/settings` | `settings.set` | Body: key/value map | Set result | 200 |
| `POST` | `/settings/reset` | `settings.reset` | — | Reset result | 200 |
| `GET` | `/env/path` | `env.path` | — | PATH resolution | 200 |
| `POST` | `/env/resolve-executable` | `env.resolve_executable` | Body: `name`, `customPath?` | Resolution | 200 |
| `POST` | `/env/validate-binary` | `env.validate_binary` | Body: per RPC | Validation | 200 |
| `GET` | `/env/dependencies` | `env.dependencies` | — | Dependency scan | 200 |
| `POST` | `/env/refresh` | `env.refresh` | — | New PATH | 200 |

#### 3.6.2 Workspaces

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `GET` | `/workspaces` | `workspace.list` | — | `{ workspaces: [...] }` | 200 |
| `GET` | `/workspaces/{workspaceId}` | `workspace.get` | — | Workspace | 200 |
| `POST` | `/workspaces` | `workspace.create` | Body: create fields | Workspace | 201 |
| `PATCH` | `/workspaces/{workspaceId}` | `workspace.update` | Body + `expectedUpdatedAt?` | Workspace | 200 |
| `DELETE` | `/workspaces/{workspaceId}` | `workspace.delete` | — | Delete result | 200 |
| `PUT` | `/workspaces/order` | `workspace.reorder` | Body: `workspaceIds` | Reorder result | 200 |
| `PUT` | `/workspaces/{workspaceId}/image` | `workspace.set_image` | Body: bytes/base64 | Image meta | 200 |
| `DELETE` | `/workspaces/{workspaceId}/image` | `workspace.clear_image` | `expectedUpdatedAt?` | Workspace | 200 |
| `GET` | `/workspaces/{workspaceId}/image` | `workspace.get_image` | Query: `size?` | PNG bytes | 200 |

#### 3.6.3 Groups

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `GET` | `/workspaces/{workspaceId}/groups` | `group.list` | — | `{ groups: [...] }` | 200 |
| `POST` | `/workspaces/{workspaceId}/groups` | `group.create` | Body: name, … | Group | 201 |
| `PATCH` | `/groups/{groupId}` | `group.update` | Body + `expectedUpdatedAt?` | Group | 200 |
| `DELETE` | `/groups/{groupId}` | `group.delete` | — | Delete result | 200 |
| `PUT` | `/workspaces/{workspaceId}/groups/order` | `group.reorder` | Body: `groupIds` | Reorder result | 200 |

#### 3.6.4 Services, providers, deck

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `GET` | `/services` | `service.list` | Query: `workspaceId`, filters, sort, search per [04](04-workspaces-groups-services.md) | Deck result | 200 |
| `GET` | `/services/{serviceId}` | `service.get` | — | Service detail | 200 |
| `POST` | `/workspaces/{workspaceId}/services` | `service.create` | Body: create payload | Service | 201 |
| `PATCH` | `/services/{serviceId}` | `service.update` | Body + `expectedUpdatedAt?` | Service | 200 |
| `DELETE` | `/services/{serviceId}` | `service.delete` | — | Delete result | 200 |
| `POST` | `/services/{serviceId}/duplicate` | `service.duplicate` | — | Service | 201 |
| `PUT` | `/services/{serviceId}/starred` | `service.set_starred` | Body: `starred?` (toggle if omitted) | Service | 200 |
| `PUT` | `/services/{serviceId}/disabled` | `service.set_disabled` | Body: `disabled` | Service | 200 |
| `PUT` | `/services/{serviceId}/groups` | `service.set_groups` | Body: `groupIds` | Service | 200 |
| `POST` | `/services/{serviceId}/groups/{groupId}/toggle` | `service.toggle_group` | — | Service | 200 |
| `POST` | `/services/{serviceId}/switch-provider` | `service.switch_provider` | Body: `providerId`, `expectedUpdatedAt?` | Switch result | 200 |
| `GET` | `/services/{serviceId}/providers` | `provider.list` | — | Providers | 200 |
| `POST` | `/services/{serviceId}/providers` | `provider.add` | Body: provider | Provider | 201 |
| `PATCH` | `/providers/{providerId}` | `provider.update` | Body + `expectedUpdatedAt?` | Provider | 200 |
| `DELETE` | `/providers/{providerId}` | `provider.delete` | — | Delete result | 200 |
| `PUT` | `/providers/{providerId}/ports` | `provider.set_ports` | Body: port mappings | Provider ports | 200 |

#### 3.6.5 Execution and runtime

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `POST` | `/services/{serviceId}/preflight` | `service.preflight` | Body: options per [05](05-providers-and-validation.md) | Preflight result | 200 |
| `POST` | `/services/{serviceId}/start` | `service.start` | Body: start options per [06](06-execution-engine.md) | Start result | 200 |
| `POST` | `/services/{serviceId}/stop` | `service.stop` | Body: stop options | Stop result | 200 |
| `POST` | `/services/{serviceId}/restart` | `service.restart` | Body: options | Restart result | 200 |
| `POST` | `/services/start-all` | `service.start_all` | Body: filter | Bulk result | 200 |
| `POST` | `/services/stop-all` | `service.stop_all` | Body: filter | Bulk result | 200 |
| `GET` | `/services/{serviceId}/status` | `service.status` | — | Runtime status | 200 |
| `GET` | `/services/statuses` | `service.statuses` | Query: `serviceIds?`, `workspaceId?` | Status map | 200 |
| `POST` | `/ports/check` | `ports.check` | Body: port, policy context | Check result | 200 |
| `GET` | `/runtime/adopt-report` | `runtime.adopt_report` | — | Adoption report | 200 |

#### 3.6.6 Kubernetes

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `GET` | `/kubeconfigs` | `kubeconfig.list` | — | List | 200 |
| `GET` | `/kubeconfigs/{kubeconfigId}` | `kubeconfig.get` | Query: no secrets; never `revealSecrets` | Kubeconfig DTO | 200 |
| `POST` | `/kubeconfigs` | `kubeconfig.create` | Body: create | Kubeconfig | 201 |
| `PATCH` | `/kubeconfigs/{kubeconfigId}` | `kubeconfig.update` | Body | Kubeconfig | 200 |
| `DELETE` | `/kubeconfigs/{kubeconfigId}` | `kubeconfig.delete` | — | Delete result | 200 |
| `GET` | `/kubeconfigs/{kubeconfigId}/contexts` | `kubeconfig.contexts` | — | Contexts | 200 |
| `POST` | `/kubeconfigs/{kubeconfigId}/test-connection` | `kubeconfig.test_connection` | Body: options | Test result | 200 |
| `POST` | `/k8s/resolve-target` | `k8s.resolve_target` | Body: pattern, kubeconfig, context | Target | 200 |
| `GET` | `/k8s/namespaces` | `k8s.namespaces` | Query: `kubeconfigId`, `context` | Namespaces | 200 |
| `GET` | `/k8s/resources` | `k8s.resources` | Query: `kubeconfigId`, `context`, `namespace`, `kind` | Resources | 200 |

#### 3.6.7 Logs and events

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `GET` | `/services/{serviceId}/logs/activity` | `logs.tail` | Query: `limit?`, `sinceRevision?` | Activity lines | 200 |
| `DELETE` | `/services/{serviceId}/logs/activity` | `logs.clear` | — | Clear result | 200 |
| `GET` | `/services/{serviceId}/logs/workload` | `logs.workload_tail` | Query: tail options | Workload lines | 200 |
| `GET` | `/services/{serviceId}/logs/workload/stream` | `logs.follow` | Query: follow options | SSE stream | 200 |
| `GET` | `/events/stream` | `events.subscribe` | Query: `sinceSeq?`, `topics?` | SSE stream | 200 |
| `DELETE` | `/events/subscriptions/{subscriptionId}` | `events.unsubscribe` | — | Unsubscribe result | 200 |
| `GET` | `/events/ws` | `events.subscribe` | Same as stream | WebSocket | 101 |
| `GET` | `/services/{serviceId}/logs/workload/ws` | `logs.follow` | Same as stream | WebSocket | 101 |

#### 3.6.8 DataPort

| Method | Path | RPC | Params | Success | HTTP |
|--------|------|-----|--------|---------|------|
| `POST` | `/data/export` | `data.export` | Body: scope options | JSON backup (download) | 200 |
| `GET` | `/services/{serviceId}/export-json` | `data.export_service_json` | — | JSON | 200 |
| `POST` | `/data/import/preview` | `data.import_preview` | Body: backup JSON | Preview | 200 |
| `POST` | `/data/import` | `data.import` | Body: import request | Import result | 200 |
| `POST` | `/data/factory-reset` | `data.factory_reset` | Body: confirm flags | Reset result | 200 |

---

## 4. Data shapes

### 4.1 REST-specific fields

| Field | Type | Where | Description |
|-------|------|-------|-------------|
| `error.code` | string | Error body | Stable `KUMA_*` code |
| `error.message` | string | Error body | Exact user-facing message |
| `restListenAddr` | string | `daemon.status` | e.g. `127.0.0.1:9364` when REST enabled |

All success payloads otherwise match [10](10-rpc-protocol.md) result tables.

### 4.2 SSE frame

| Field | Type | JSON key | Description |
|-------|------|----------|-------------|
| Event seq | integer | `seq` | Bus sequence ([08](08-logs-and-events.md)) |
| Name | string | `name` | Event name from [00 §5.7](00-overview-and-conventions.md) |
| Payload | object | `payload` | Per [08](08-logs-and-events.md) |
| Timestamp | string | `ts` | ISO-8601 UTC |

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-API-01 | [V2-ADD] | REST listener on loopback with `/v1` prefix (ADD-120) | — | (infra) |
| FEAT-API-02 | [V2-ADD] | Map RPC errors to HTTP status + JSON envelope | — | (infra) |
| FEAT-API-03 | [V2-ADD] | Bearer auth on every route ([ADD-08](02-security-and-secrets.md), 02 §3.9.2) | — | all |
| FEAT-API-04 | [V2-ADD] | Refuse `revealSecrets` over REST | — | all reads |
| FEAT-API-05 | [V2-ADD] | Daemon lifecycle routes (`ping`, `status`, `shutdown`) | — | `daemon.*` |
| FEAT-API-06 | [V2-ADD] | Settings and environment routes | — | `settings.*`, `env.*` |
| FEAT-API-07 | [V2-ADD] | Workspace and avatar routes | — | `workspace.*` |
| FEAT-API-08 | [V2-ADD] | Group routes | — | `group.*` |
| FEAT-API-09 | [V2-ADD] | Service, deck, provider routes | — | `service.*`, `provider.*` (CRUD) |
| FEAT-API-10 | [V2-ADD] | Execution routes (start/stop/restart/bulk/status/preflight/ports) | — | `service.start`…`service.preflight`, `ports.check`, `runtime.adopt_report` |
| FEAT-API-11 | [V2-ADD] | Kubernetes routes | — | `kubeconfig.*`, `k8s.*` |
| FEAT-API-12 | [V2-ADD] | Activity and workload log routes | — | `logs.tail`, `logs.clear`, `logs.workload_tail` |
| FEAT-API-13 | [V2-ADD] | SSE event stream with replay ([ADD-07](08-logs-and-events.md)) | — | `events.subscribe`, `events.unsubscribe` |
| FEAT-API-14 | [V2-ADD] | SSE workload log follow | — | `logs.follow` |
| FEAT-API-15 | [V2-ADD] | Optional WebSocket streams ([ADD-121](#7-deviations)) | — | `events.subscribe`, `logs.follow` |
| FEAT-API-16 | [V2-ADD] | DataPort routes (export/import/reset) | — | `data.*` |
| FEAT-API-17 | [V2-ADD] | Reserved mTLS auth profile when TLS enabled ([ADD-120](#7-deviations)) | — | (infra) |

---

## 6. Error catalog

| Code | Condition | Message (exact) |
|------|-----------|-----------------|
| `KUMA_API_UNKNOWN_ROUTE` | No route matches method + path | `No REST route matches this request.` |
| `KUMA_API_METHOD_NOT_ALLOWED` | Path exists but verb wrong | `HTTP method not allowed for this resource.` |
| `KUMA_API_STREAM_UNSUPPORTED` | WebSocket requested but disabled | `Streaming transport WebSocket is not enabled on this daemon.` |
| `KUMA_API_BODY_REQUIRED` | POST/PATCH/PUT with required body missing | `Request body is required.` |

All other codes are defined in feature specs and [02](02-security-and-secrets.md); REST MUST reuse them verbatim.

---

## 7. Deviations

| Id | Summary |
|----|---------|
| ADD-120 | REST default port `9364`, enable via `KUMA_REST=1` / `--rest`; optional future `KUMA_REST_TLS` + mTLS profile (§3.2.2). |
| ADD-121 | Optional WebSocket parallel to SSE for `events.subscribe` and `logs.follow`; SSE remains the required transport. |
| DEV-120 | REST adapter strips `revealSecrets` query parameter before RPC dispatch and returns 403 if `true`. |

Cross-cutting: [ADD-08](02-security-and-secrets.md) bearer auth; [ADD-07](08-logs-and-events.md) event replay on subscribe.

---

## 8. Invariants

| Id | Statement |
|----|-----------|
| INV-D-API-01 | Every RPC method in [00 §5](00-overview-and-conventions.md) has exactly one primary REST mapping row in §10 unless listed as socket-only (`daemon.rotate_api_token`) or streaming-only exception (none). |
| INV-D-API-02 | Successful JSON responses use the same keys and values as the RPC result for that method ([10](10-rpc-protocol.md)). |
| INV-D-API-03 | REST never returns plaintext secrets ([02](02-security-and-secrets.md) GR-04, §3.11). |
| INV-D-API-04 | All REST handlers run with transport kind `rest` in the audit log ([02 §3.10](02-security-and-secrets.md)). |
| INV-D-API-05 | SSE replay ordering matches `events.subscribe` over the socket ([08](08-logs-and-events.md)). |

---

## 9. Acceptance tests

| Id | Arrange | Assert |
|----|---------|--------|
| DT-API-01 | Enable REST; `GET /v1/daemon/ping` with valid bearer + Host | 200, same body as RPC `daemon.ping` |
| DT-API-02 | Call each §10 row sample route (smoke) | Same result as RPC via Unix socket for shared fixture |
| DT-API-03 | `revealSecrets=true` query on `GET /v1/services/{id}` | 403 `KUMA_SEC_REVEAL_FORBIDDEN` |
| DT-API-04 | `GET /v1/events/stream?sinceSeq=N` | Replay then live; seq monotonic |
| DT-API-05 | Missing bearer | 401 `KUMA_SEC_TOKEN_MISSING` |
| DT-API-06 | `GET /v1/workspaces/{id}/image` | `Content-Type: image/png`, bytes match RPC |
| DT-API-07 | WebSocket disabled, `GET /v1/events/ws` | 501 `KUMA_API_STREAM_UNSUPPORTED` |
| DT-API-08 | `PATCH /v1/services/{id}` with stale `expectedUpdatedAt` | 409 `KUMA_CONFLICT_STALE` |

---

## 10. RPC | CLI | MCP | REST mapping

CLI and MCP columns name the **planned** surface in [11](11-cli.md) and [12](12-mcp.md). Until those specs land, treat them as normative targets for [GR-05](00-overview-and-conventions.md).

| RPC method | CLI ([11](11-cli.md)) | MCP ([12](12-mcp.md)) | REST |
|------------|----------------------|------------------------|------|
| `daemon.ping` | `kuma daemon ping` | `daemon_ping` | `GET /v1/daemon/ping` |
| `daemon.status` | `kuma daemon status` | `daemon_status` | `GET /v1/daemon/status` |
| `daemon.shutdown` | `kuma daemon shutdown` | `daemon_shutdown` | `POST /v1/daemon/shutdown` |
| `daemon.rotate_api_token` | `kuma daemon rotate-api-token` | — | — (not exposed; `KUMA_SEC_LOCAL_ONLY`) |
| `settings.list` | `kuma settings list` | `settings_list` | `GET /v1/settings` |
| `settings.get` | `kuma settings get <key>` | `settings_get` | `GET /v1/settings/{key}` |
| `settings.set` | `kuma settings set …` | `settings_set` | `PUT /v1/settings` |
| `settings.reset` | `kuma settings reset` | `settings_reset` | `POST /v1/settings/reset` |
| `env.path` | `kuma env path` | `env_path` | `GET /v1/env/path` |
| `env.resolve_executable` | `kuma env which …` | `env_resolve_executable` | `POST /v1/env/resolve-executable` |
| `env.validate_binary` | `kuma env validate …` | `env_validate_binary` | `POST /v1/env/validate-binary` |
| `env.dependencies` | `kuma env deps` | `env_dependencies` | `GET /v1/env/dependencies` |
| `env.refresh` | `kuma env refresh` | `env_refresh` | `POST /v1/env/refresh` |
| `workspace.list` | `kuma workspace list` | `workspace_list` | `GET /v1/workspaces` |
| `workspace.get` | `kuma workspace get …` | `workspace_get` | `GET /v1/workspaces/{workspaceId}` |
| `workspace.create` | `kuma workspace create …` | `workspace_create` | `POST /v1/workspaces` |
| `workspace.update` | `kuma workspace rename …` | `workspace_update` | `PATCH /v1/workspaces/{workspaceId}` |
| `workspace.delete` | `kuma workspace delete …` | `workspace_delete` | `DELETE /v1/workspaces/{workspaceId}` |
| `workspace.reorder` | `kuma workspace reorder …` | `workspace_reorder` | `PUT /v1/workspaces/order` |
| `workspace.set_image` | `kuma workspace image set …` | `workspace_set_image` | `PUT /v1/workspaces/{workspaceId}/image` |
| `workspace.clear_image` | `kuma workspace image clear …` | `workspace_clear_image` | `DELETE /v1/workspaces/{workspaceId}/image` |
| `workspace.get_image` | `kuma workspace image get …` | `workspace_get_image` | `GET /v1/workspaces/{workspaceId}/image` |
| `group.list` | `kuma group list …` | `group_list` | `GET /v1/workspaces/{workspaceId}/groups` |
| `group.create` | `kuma group create …` | `group_create` | `POST /v1/workspaces/{workspaceId}/groups` |
| `group.update` | `kuma group rename …` | `group_update` | `PATCH /v1/groups/{groupId}` |
| `group.delete` | `kuma group delete …` | `group_delete` | `DELETE /v1/groups/{groupId}` |
| `group.reorder` | `kuma group reorder …` | `group_reorder` | `PUT /v1/workspaces/{workspaceId}/groups/order` |
| `service.list` | `kuma service list …` | `service_list` | `GET /v1/services` |
| `service.get` | `kuma service get …` | `service_get` | `GET /v1/services/{serviceId}` |
| `service.create` | `kuma service create …` | `service_create` | `POST /v1/workspaces/{workspaceId}/services` |
| `service.update` | `kuma service update …` | `service_update` | `PATCH /v1/services/{serviceId}` |
| `service.delete` | `kuma service delete …` | `service_delete` | `DELETE /v1/services/{serviceId}` |
| `service.duplicate` | `kuma service duplicate …` | `service_duplicate` | `POST /v1/services/{serviceId}/duplicate` |
| `service.set_starred` | `kuma service star …` | `service_set_starred` | `PUT /v1/services/{serviceId}/starred` |
| `service.set_disabled` | `kuma service disable …` | `service_set_disabled` | `PUT /v1/services/{serviceId}/disabled` |
| `service.set_groups` | `kuma service groups set …` | `service_set_groups` | `PUT /v1/services/{serviceId}/groups` |
| `service.toggle_group` | `kuma service groups toggle …` | `service_toggle_group` | `POST /v1/services/{serviceId}/groups/{groupId}/toggle` |
| `service.switch_provider` | `kuma service provider switch …` | `service_switch_provider` | `POST /v1/services/{serviceId}/switch-provider` |
| `provider.list` | `kuma provider list …` | `provider_list` | `GET /v1/services/{serviceId}/providers` |
| `provider.add` | `kuma provider add …` | `provider_add` | `POST /v1/services/{serviceId}/providers` |
| `provider.update` | `kuma provider update …` | `provider_update` | `PATCH /v1/providers/{providerId}` |
| `provider.delete` | `kuma provider delete …` | `provider_delete` | `DELETE /v1/providers/{providerId}` |
| `provider.set_ports` | `kuma provider ports set …` | `provider_set_ports` | `PUT /v1/providers/{providerId}/ports` |
| `service.preflight` | `kuma service preflight …` | `service_preflight` | `POST /v1/services/{serviceId}/preflight` |
| `service.start` | `kuma service start …` | `service_start` | `POST /v1/services/{serviceId}/start` |
| `service.stop` | `kuma service stop …` | `service_stop` | `POST /v1/services/{serviceId}/stop` |
| `service.restart` | `kuma service restart …` | `service_restart` | `POST /v1/services/{serviceId}/restart` |
| `service.start_all` | `kuma service start-all …` | `service_start_all` | `POST /v1/services/start-all` |
| `service.stop_all` | `kuma service stop-all …` | `service_stop_all` | `POST /v1/services/stop-all` |
| `service.status` | `kuma service status …` | `service_status` | `GET /v1/services/{serviceId}/status` |
| `service.statuses` | `kuma service statuses …` | `service_statuses` | `GET /v1/services/statuses` |
| `ports.check` | `kuma ports check …` | `ports_check` | `POST /v1/ports/check` |
| `runtime.adopt_report` | `kuma runtime adopt-report` | `runtime_adopt_report` | `GET /v1/runtime/adopt-report` |
| `kubeconfig.list` | `kuma kubeconfig list` | `kubeconfig_list` | `GET /v1/kubeconfigs` |
| `kubeconfig.get` | `kuma kubeconfig get …` | `kubeconfig_get` | `GET /v1/kubeconfigs/{kubeconfigId}` |
| `kubeconfig.create` | `kuma kubeconfig create …` | `kubeconfig_create` | `POST /v1/kubeconfigs` |
| `kubeconfig.update` | `kuma kubeconfig update …` | `kubeconfig_update` | `PATCH /v1/kubeconfigs/{kubeconfigId}` |
| `kubeconfig.delete` | `kuma kubeconfig delete …` | `kubeconfig_delete` | `DELETE /v1/kubeconfigs/{kubeconfigId}` |
| `kubeconfig.contexts` | `kuma kubeconfig contexts …` | `kubeconfig_contexts` | `GET /v1/kubeconfigs/{kubeconfigId}/contexts` |
| `kubeconfig.test_connection` | `kuma kubeconfig test …` | `kubeconfig_test_connection` | `POST /v1/kubeconfigs/{kubeconfigId}/test-connection` |
| `k8s.resolve_target` | `kuma k8s resolve …` | `k8s_resolve_target` | `POST /v1/k8s/resolve-target` |
| `k8s.namespaces` | `kuma k8s namespaces …` | `k8s_namespaces` | `GET /v1/k8s/namespaces` |
| `k8s.resources` | `kuma k8s resources …` | `k8s_resources` | `GET /v1/k8s/resources` |
| `logs.tail` | `kuma logs tail …` | `logs_tail` | `GET /v1/services/{serviceId}/logs/activity` |
| `logs.clear` | `kuma logs clear …` | `logs_clear` | `DELETE /v1/services/{serviceId}/logs/activity` |
| `logs.workload_tail` | `kuma logs workload …` | `logs_workload_tail` | `GET /v1/services/{serviceId}/logs/workload` |
| `logs.follow` | `kuma logs follow …` | `logs_follow` | `GET /v1/services/{serviceId}/logs/workload/stream` (SSE) |
| `events.subscribe` | `kuma events watch …` | `events_subscribe` | `GET /v1/events/stream` (SSE); optional `GET /v1/events/ws` |
| `events.unsubscribe` | (close watch / cancel) | `events_unsubscribe` | `DELETE /v1/events/subscriptions/{subscriptionId}` |
| `data.export` | `kuma data export …` | `data_export` | `POST /v1/data/export` |
| `data.export_service_json` | `kuma service export …` | `data_export_service_json` | `GET /v1/services/{serviceId}/export-json` |
| `data.import_preview` | `kuma data import preview …` | `data_import_preview` | `POST /v1/data/import/preview` |
| `data.import` | `kuma data import …` | `data_import` | `POST /v1/data/import` |
| `data.factory_reset` | `kuma data reset …` | `data_factory_reset` | `POST /v1/data/factory-reset` |

---

## Proposed RPC additions

None. This spec consumes the registry in [00 §5](00-overview-and-conventions.md) only.

---

## Open questions / residual risks

1. **Default REST port:** `9364` is new ([ADD-120]); confirm no conflict with common local services in user environments.
2. **CLI/MCP names:** Placeholders in §10 until [11](11-cli.md) and [12](12-mcp.md) are published; `check_traceability.py` should key off RPC + REST columns first.
3. **Multipart import:** Optional convenience; if omitted in v1, JSON-only import remains sufficient for GR-05.
