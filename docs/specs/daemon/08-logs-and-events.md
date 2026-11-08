# Daemon Spec 08: Logs, Spool, Activity Buffer and Event Bus

> **Status:** Draft for implementation  
> **Areas:** `LOG` (logs and events)  
> **Depends on:** [00](00-overview-and-conventions.md) (IDs, RPC/event registry), [01](01-data-model.md) (`meta.eventSeq`), [02](02-security-and-secrets.md) (redaction profiles), [06](06-execution-engine.md) (spool open, `lastFailure` tail, activity lines at start/stop/crash, `service.state_changed` fields, `notify` triggers)  
> **Cooperates with:** [04](04-workspaces-groups-services.md) (entity mutation events, minimum payloads), [03](03-settings-and-environment.md) (`settings.changed`, `notifyOnServiceFailure`), [05](05-providers-and-validation.md) (`[CONFIG]` lines from preflight), [09](09-dataport.md) (`data.imported`, `data.reset`), [14](14-lifecycle-and-platform.md) (`daemon.shutting_down`), [07](07-kubernetes.md) (`kubeconfig.changed`), [10](10-rpc-protocol.md) (wire schemas)

---

## 1. Purpose and scope

This spec defines every daemon-owned behavior that 1.x implemented through `RunSpool`, the `SystemActivityLogRecording` / `LiveLogSession` pipeline, `LiveLogSourceRunner` (workload tail commands), macOS `SystemNotificationCenter` alerts (replaced by the `notify` event), and the ad-hoc `NotificationCenter` posts that become the RPC event bus.

In scope:

- On-disk **run spool** for managed-process stdout/stderr ([DEV-12](06-execution-engine.md), [DEV-70](06-execution-engine.md)).
- In-memory **activity log buffer** per service (system messages: `[KUMA]`, `[FAILURE]`, `[CONFIG]`, `[HEALTH]`, `[MONITOR]`, raw lines) with retention rules (**DEV-07**).
- **ANSI sanitization** before any activity line is stored or sent on the wire.
- RPC **`logs.tail`**, **`logs.clear`**, **`logs.workload_tail`**, **`logs.follow`**.
- **Event bus**: monotonic **`seq`**, **`events.subscribe`** / **`events.unsubscribe`**, replay via **`sinceSeq`**, and **full payload schemas** for every name in [00 §5.7](00-overview-and-conventions.md).
- **`service.log_line`** streaming for activity and workload text (headless clients; 1.x used in-process `LiveLogSession` only).

Out of scope: process spawn and spool fd wiring ([06](06-execution-engine.md)); redaction regex tables ([02](02-security-and-secrets.md)); entity CRUD ([04](04-workspaces-groups-services.md)); SwiftUI log console, coalesced NSTextView flush, toolbar clear/download ([CLIENT], see §3.15).

---

## 2. 1.x source of truth (paths read)

| Topic | Files (repo-relative) |
|-------|------------------------|
| Spool | `Kuma/Core/Execution/Supervision/RunSpool.swift` |
| Activity recording API | `Kuma/Core/Execution/Logging/SystemActivityLogRecording.swift` |
| Log line model (legacy) | `Kuma/Core/Execution/Logging/LiveLogEntry.swift` |
| ANSI sanitizer | `Kuma/Core/Execution/Logging/ANSISanitizer.swift` |
| Activity buffer | `Kuma/Presentation/Features/LiveLogs/LiveLogSession.swift` |
| Bridge | `Kuma/Presentation/Features/LiveLogs/LiveLogRecordingBridge.swift` |
| Engine emitters | `Kuma/Presentation/Features/LiveLogs/LiveLogSystemEmitter.swift` |
| Workload tail | `Kuma/Presentation/Features/LiveLogs/LiveLogSourceRunner.swift` |
| Categories / display | `Kuma/Presentation/Features/LiveLogs/ActivityLogFormatting.swift`, `ActivityLogStyle.swift` |
| macOS notifications | `Kuma/Core/Notifications/SystemNotificationCenter.swift` |
| Notification names | `Kuma/Core/Notifications/Notification+Kuma.swift`, `ServiceStateNotification.swift` |
| Spool purge at launch | `Kuma/KumaApp.swift:23-25` |
| Inspector console | `Kuma/Presentation/Features/Services/Views/Inspector/Components/InspectorLiveConsoleView.swift` |
| Tests | `KumaTests/Features/Services/LiveLogSessionTests.swift` |
| Docs / matrix | `docs/specs/06-services.md` (live logs section), `docs/testing/06-services-test-matrix.md` (TC-L*) |

Execution engine call sites for activity lines are enumerated in [06](06-execution-engine.md); this spec owns **how** those calls affect storage and events.

---

## 3. Normative behavior

### 3.1 Constants

| Name | Value | Source / note |
|------|-------|----------------|
| `SPOOL_DIR` | `<runtime dir>/spool` | DEV-12; 1.x: `$TMPDIR/kuma-run` (`RunSpool.swift:7-11`) |
| `SPOOL_FILE_NAME` | `<SERVICE_ID_UPPER>.out` | DEV-12; 1.x: `<uuidString>.out` lowercase (`RunSpool.swift:14-16`) |
| `SPOOL_DIR_MODE` | `0700` | [02 §3.13](02-security-and-secrets.md) |
| `SPOOL_FILE_MODE` | `0600` | DEV-12; 1.x open `0o644` (`RunSpool.swift:20-28`) |
| `SPOOL_MAX_BYTES` | `8388608` (8 MiB) | `RunSpool.swift:5`, DEV-70 |
| `SPOOL_KEEP_BYTES` | `4194304` (4 MiB) | DEV-70 ([06](06-execution-engine.md)) |
| `SPOOL_TAIL_BYTES` | `4096` | `RunSpool.tail` default (`RunSpool.swift:43`) |
| `SPOOL_TAIL_LINES` | `8` | `RunSpool.swift:50`, [06](06-execution-engine.md) |
| `SPOOL_MAINTENANCE_INTERVAL` | `5 s` | DEV-70 per live spool ([06](06-execution-engine.md)) |
| `ACTIVITY_MAX_LINES` | `1000` | `LiveLogSession.swift:18` (TC-L10) |
| `ACTIVITY_MAX_SERVICES` | `50` | `LiveLogSession.swift:20` (TC-L21) |
| `WORKLOAD_TAIL_LINES` | `200` | `LiveLogSourceRunner.swift:52`, `:65` |
| `WORKLOAD_SPOOL_POLL` | `200 ms` | `LiveLogSourceRunner.swift:42` |
| `WORKLOAD_IDLE_POLL` | `500 ms` | `LiveLogSourceRunner.swift:26` |
| `EVENT_REPLAY_CAPACITY` | `10000` | ADD-07; events with `seq <= lastSeq - capacity` are not replayable |
| `EVENT_SEQ_META_KEY` | `eventSeq` | [01](01-data-model.md) `meta` table |
| `ANSI_REGEX` | see §3.5 | `ANSISanitizer.swift:12` |

### 3.2 Run spool (on disk)

#### 3.2.1 Layout and permissions

The daemon MUST create `<runtime dir>/spool` with mode `0700`. Each managed process writes merged stdout/stderr to `<runtime dir>/spool/<SERVICE_ID_UPPER>.out` opened with `O_WRONLY | O_CREAT | O_APPEND` and mode `0600`. The file is **not** truncated at open ([06](06-execution-engine.md) §3.10.1). Open failure message (exact): `Cannot open run spool '<path>': <os error text>`.

1.x used `RunSpool.directoryURL()` → `NSTemporaryDirectory()/kuma-run/` and filename `serviceID.uuidString` (any case Swift emits) with mode `0644` (**DEV-12**).

#### 3.2.2 `RunSpool` operations (parity reference)

| 1.x API | Behavior | Daemon |
|---------|----------|--------|
| `prepare(for:)` | `O_TRUNC` create | **Not used** by the execution engine in 1.x production path; daemon MUST NOT call truncate-at-prepare for running services. |
| `openAppendFD(for:)` | append + `truncateIfNeeded` at open | Same open flags; run DEV-70 maintenance (§3.2.4). |
| `remove(for:)` | delete file | Called when run ends ([06](06-execution-engine.md)). |
| `purgeAll()` | delete all files in spool dir | Called at app launch (`KumaApp.swift:24`); daemon at startup with **DEV-12** rules below. |
| `tail(for:maxBytes:)` | last 4096 bytes, UTF-8 decode or `""`, split `\n` keeping empties, last 8 lines, trim WS | Used for `lastFailure`; see [06](06-execution-engine.md) DEV-70 empty-tail rule. |

#### 3.2.3 Startup purge (**DEV-12**)

On daemon start, before adoption completes, the daemon MUST delete spool files **only** when **no** `runtime_process` row exists for that `serviceID` (same uppercase id as the filename stem). Spool files for adopted or running services MUST be retained so workload tail and `lastFailure` remain valid.

1.x `purgeAll()` deleted unconditionally at every app launch (except test host).

#### 3.2.4 Size cap (**DEV-70**)

When `size > SPOOL_MAX_BYTES`, keep the newest `SPOOL_KEEP_BYTES` starting at a line boundary ([06](06-execution-engine.md)). Apply at open (`truncateIfNeeded`, `RunSpool.swift:53-63`) **and** on a **5 s** tick per active spool.

**DEV-91:** Any consumer tailing the spool file (`logs.workload_tail`, `logs.follow` spool mode) MUST, on each read, if `file_size < last_offset`, reset `last_offset = 0` and re-read from the start (truncate/shrink race).

#### 3.2.5 Raw bytes on disk

Spool bytes are **never** redacted on disk ([02](02-security-and-secrets.md) DEV-38). Sanitization and `strict`/`workload` redaction apply only when bytes are exposed via RPC or events.

### 3.3 Activity log buffer (in memory)

The daemon maintains `activity_buffers: Map<serviceID, Buffer>` where each `Buffer` holds ordered lines, a monotonic `revision`, capture state, trim flag, and LRU touch time. This replaces 1.x `LiveLogSession.shared` (`LiveLogSession.swift`).

#### 3.3.1 Line model

Each stored line (`ActivityLine`):

| Field | Semantics |
|-------|-----------|
| `id` | New random UUID per line; stable for the life of the line in the buffer (TC-L11). |
| `text` | Sanitized (§3.5), single logical line (no embedded `\n` after split). |
| `timestamp` | UTC instant when appended. |
| `kind` | `system` for all activity-buffer lines in 1.x (`LiveLogLineKind.system`). |
| `category` | `ActivityLogCategory` (§3.6). |

Wire JSON uses camelCase keys in §4.

#### 3.3.2 Capture lifecycle

| Method | 1.x | Daemon |
|--------|-----|--------|
| `beginRun(serviceID)` | Clears buffer, sets capturing, clears trim notice and last failure dedupe (`LiveLogSession.swift:77-86`) | Identical. Invoked from start pipeline ([06](06-execution-engine.md)). |
| `endCapture(serviceID)` | Stops appending; keeps lines (`:88-91`, TC-L13, TC-L20) | Identical. |
| `clear(serviceID)` | Removes buffer and all metadata (`:93-100`) | Identical; also invoked by `logs.clear` and LRU eviction victim. |
| `ensureCapturing(serviceID)` | Enables capture without clear (`:132-141`) | Used by failure/config paths. |

**DEV-07:** The activity buffer MUST NOT be cleared when a client closes a log view or unsubscribes from log events. Retention ends only on `begin_run` (new run), `logs.clear`, service deletion ([04](04-workspaces-groups-services.md)), or LRU eviction of an untouched service buffer. This supersedes the prose in `docs/specs/06-services.md` ("Closing the panel … clears") which described 1.x **client** teardown (TC-L14 simulates `stop + clear` in the **client**); the daemon obeys **tests** TC-L13, TC-L14's *daemon-side* expectation that `endCapture` alone does not clear.

#### 3.3.3 Append rules

1. **`emit(serviceID, message)`** — If not capturing, drop. Else append one or more lines with prefix `[KUMA] ` + message (`LiveLogSession.swift:115-118`). Split sanitized text on `\n`, omitting empty segments after sanitize (`:222-231`).

2. **`emitBatch(serviceID, messages)`** — Same as repeated `emit` (`:120-125`, TC-L22).

3. **`emitRawLine(serviceID, message)`** — No `[KUMA]` prefix (`:127-130`). Used for `[HEALTH] …`, `[MONITOR] …`.

4. **`recordFailure(serviceID, message)`** (`recordBannerFailure`) — Trim message; dedupe by full trimmed text (`:144-161`, TC-L18). First line `[FAILURE] <first line>`, continuation lines `  <line>` (two ASCII spaces). If buffer already contains `[KUMA] Start failed: <trimmed>` identical to what would be added, skip duplicate (TC-L23). Does not require prior `beginRun` (`ensureCapturing`).

5. **`recordConfigurationIssues(serviceID, messages)`** — Trim/filter empty; each blocking message becomes `[CONFIG] <message>` if not already present in buffer (`:163-174`). Does not require capturing beforehand.

6. **Preflight / validation** — When blocking issues are recorded with `recordToActivityLog`, also `emit` `[KUMA] Start blocked: fix configuration issues above.` (`ServiceInspectorViewModel+Validation.swift:57-61`, [05](05-providers-and-validation.md)).

#### 3.3.4 Ring buffer and trim notice

When a service buffer exceeds `ACTIVITY_MAX_LINES`, keep the last `ACTIVITY_MAX_LINES` lines and set `didTrimToMaxLines = true` (`LiveLogSession.swift:237-240`, TC-L10). `logs.tail` exposes this flag; clearing trim notice is **[CLIENT]** (`acknowledgeTrimNotice`).

#### 3.3.5 LRU across services

When a new service needs a slot and `activity_buffers.len >= ACTIVITY_MAX_SERVICES`, evict the service with oldest `lastTouchedAt` via full `clear(serviceID)` (`LiveLogSession.swift:196-205`, TC-L21). `markRecentlyUsed(serviceID)` updates touch time (inspector `onAppear`, `LiveLogSession.swift:64-67`).

#### 3.3.6 Redaction before store

Every `text` field MUST pass [02](02-security-and-secrets.md) **`strict`** redaction **after** ANSI sanitization and **before** buffer insert and **`service.log_line`** emission.

#### 3.3.7 Revision

Each mutation that changes the line list increments `revision` (`bumpRevision`, `LiveLogSession.swift:212-214`). Unchanged revision allows clients to skip redraws (TC-L11).

### 3.4 Recording backend mapping

1.x `SystemActivityLogRecordingBackend` (`SystemActivityLogRecording.swift:4-12`) maps 1:1 to daemon internal calls:

| Backend method | Daemon internal |
|----------------|-----------------|
| `beginRun` | `activity_begin_run` |
| `endCapture` | `activity_end_capture` |
| `emit` | `activity_emit` |
| `emitBatch` | `activity_emit_batch` |
| `emitRawLine` | `activity_emit_raw` |
| `recordFailure` | `activity_record_failure` |
| `recordConfigurationIssues` | `activity_record_config` |

`LiveLogSystemEmitter` and `LiveLogRecordingBridge` are thin forwards; the daemon implements the semantics in §3.3 directly inside the execution engine and validation paths.

### 3.5 `ANSISanitizer`

Before any activity line is stored or sent on the wire as a **`system`** line:

1. Replace `\r\n` → `\n`, then every `\r` → `\n` (`ANSISanitizer.swift:24-25`).
2. If no U+001B byte remains, return the string.
3. Otherwise remove all matches of this **exact** regular expression (Rust/PCRE compatible; 1.x `NSRegularExpression`):

```text
\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\].*?(?:\x07|\x1B\\))
```

Source: `ANSISanitizer.swift:12` (Swift raw string `#"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\].*?(?:\x07|\x1B\\))"#`).

Replacement: empty string. Test vector (TC-L03): input `\u{001B}[32mSUCCESS\u{001B}[0m: done.` → `SUCCESS: done.`

**Workload** bytes from spool/kubectl/docker use **`workload`** redaction ([02](02-security-and-secrets.md)); ANSI stripping for workload is **recommended** but not required for spool disk bytes.

### 3.6 `ActivityLogCategory`

String enum on the wire; inferred when not explicitly set (`ActivityLogFormatting.swift:12-19`):

| Prefix / rule | Category |
|---------------|----------|
| `[KUMA] ` | `kuma` |
| `[FAILURE] ` | `failure` |
| `[CONFIG] ` | `config` |
| `[HEALTH] ` | `health` |
| `[MONITOR] ` | `monitor` |
| starts with two spaces `  ` | `failureContinuation` |
| else | `raw` |

Explicit categories on `recordFailure` / `recordConfigurationIssues` override inference.

Display stripping for **[CLIENT]** (`ActivityLogFormatting.displayMessage`): remove category prefix or trim continuation spaces (`ActivityLogFormatting.swift:34-50`, TC-L26). Time format **`HH:mm:ss`** local (`ActivityLogFormatting.swift:24-27`).

### 3.7 RPC `logs.tail`

**Tag:** [PARITY] (replaces reading `LiveLogSession.snapshot`).

| Param | Type | Optional | Default |
|-------|------|----------|---------|
| `serviceID` | UUID string | no | — |
| `sinceRevision` | u64 | yes | `0` — return full buffer when omitted or `0` |

**Result:**

| Field | Type | Meaning |
|-------|------|---------|
| `serviceID` | string | uppercase canonical |
| `revision` | u64 | current buffer revision |
| `lines` | `ActivityLine[]` | lines with `revision > sinceRevision`, or all lines if `sinceRevision == 0` |
| `didTrimToMaxLines` | bool | trim notice flag |

Missing service (no row in DB): `KUMA_SVC_NOT_FOUND` ([04](04-workspaces-groups-services.md)). An unknown service with no buffer yet returns `{ revision: 0, lines: [], didTrimToMaxLines: false }`.

### 3.8 RPC `logs.clear`

**Tag:** [PARITY]

Params: `{ serviceID }`. Clears the activity buffer via `clear(serviceID)` (§3.3.2). Does not delete spool files. Does not emit `service.log_line`. Emits no entity event.

Errors: `KUMA_SVC_NOT_FOUND` if the service row does not exist.

### 3.9 RPC `logs.workload_tail` (**ADD-05**)

One-shot fetch of **workload** output (not activity buffer). Params: `{ serviceID, maxLines? }` default `maxLines = WORKLOAD_TAIL_LINES` (200).

Algorithm mirrors `LiveLogSourceRunner.run` without `-f` / follow loop (`LiveLogSourceRunner.swift:6-76`):

| Active provider `type` | Command |
|------------------------|---------|
| `kubernetes` | `kubectl logs --tail=<maxLines> <ref>` plus `--kubeconfig`, `--context`, `-n` when set ([06](06-execution-engine.md), [07](07-kubernetes.md)) |
| `docker`, `podman` | `<binary> compose -p <project> -f <file> logs --tail=<maxLines>` |
| `shell`, `ssh`, `tunnel` | Read spool file from offset 0; return tail semantics: last `maxLines` lines decoded UTF-8 lossily |
| `httpCheck`, `processMonitor` | Empty string result `{ text: "" }` |

Apply **`workload`** redaction to returned text. Timeout for subprocess: **60 s** (ADD-05; 1.x had no RPC). Errors: `KUMA_SVC_NOT_FOUND`, `KUMA_EXE_NO_ACTIVE_PROVIDER`, `KUMA_LOG_WORKLOAD_UNAVAILABLE` when binary missing or target unresolved.

Result: `{ serviceID, text, truncated: bool }` where `truncated` is true when spool or CLI output exceeded internal safety cap (`262144` bytes, ADD-05).

### 3.10 RPC `logs.follow` (**ADD-05**)

Params: `{ serviceID, subscriptionID? }`. Creates or replaces a **follow handle** tied to the caller's `events.subscribe` session (same transport connection). While active, the daemon streams **`service.log_line`** events with `"kind":"workload"` using the same provider branching as §3.9 but with:

- Kubernetes: `kubectl logs -f --tail=200 …` (`LiveLogSourceRunner.swift:65`)
- Compose: `compose … logs -f --tail=200` (`:52-53`)
- Shell/SSH/tunnel: spool poll every **200 ms** (`:30-43`)
- Health/monitor: no output; idle poll **500 ms** until cancelled

Chunks split on `\n` (keep partial line in buffer). Each complete line → one `service.log_line` with **`workload`** redaction. Cancel when: `logs.follow` stop parameter, `events.unsubscribe`, transport disconnect, or service stops (same as 1.x stopping workload stream when service stops — engine `end_capture` does not cancel follow; **stop** ends follow).

Result on start: `{ serviceID, following: true }`.

### 3.11 Event bus (**ADD-07**)

#### 3.11.1 Sequence numbers

- Every emitted event receives `seq = previous + 1` (u64, no gaps except crash before persist).
- After assigning `seq`, persist `meta.eventSeq` to the same value before delivering to subscribers ([01](01-data-model.md)).
- **`sinceSeq`**: on `events.subscribe`, replay all stored events with `seq > sinceSeq` in ascending order, then live stream.

#### 3.11.2 Replay store

Table in `daemon-state.sqlite` (owned by this spec):

```sql
CREATE TABLE event_replay (
  seq INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  payload TEXT NOT NULL,
  emittedAt TEXT NOT NULL
);
```

Retention: delete rows with `seq <= lastSeq - EVENT_REPLAY_CAPACITY` after each insert. Subscribers passing `sinceSeq` older than the oldest retained row receive events starting at the oldest available seq (document in response `replayTruncated: true`).

#### 3.11.3 Envelope (all events)

Every delivered message (replay and live):

| Field | Type | JSON key | Notes |
|-------|------|----------|-------|
| Sequence | u64 | `seq` | monotonic |
| Name | string | `event` | [00 §5.7](00-overview-and-conventions.md) |
| Payload | object | `payload` | per §3.12 |
| Emitted at | timestamp | `emittedAt` | ISO-8601 ms UTC |
| Origin | string | `origin` | optional: `daemon`, `rpc`, `execution`, … |
| Client request id | string | `clientRequestId` | optional; copied from RPC when the emitting call carried one ([04](04-workspaces-groups-services.md) §3.9) |

#### 3.11.4 `events.subscribe`

Params:

| Param | Type | Optional | Default |
|-------|------|----------|---------|
| `topics` | string[] | yes | all registered events |
| `sinceSeq` | u64 | yes | `0` |

Result: `{ subscriptionId, replayFromSeq, replayTruncated }` then stream envelopes until `events.unsubscribe`.

#### 3.11.5 `events.unsubscribe`

Params: `{ subscriptionId }`. Idempotent. Cancels `logs.follow` handles bound to that subscription.

#### 3.11.6 Emission ordering

- Entity mutation events ([04](04-workspaces-groups-services.md)): after SQLite commit, order as listed per RPC table.
- `service.state_changed`: debounced batch per [06 §3.4.4](06-execution-engine.md); each flushed event gets its own `seq`.
- `service.log_line`: `seq` assigned per line; may interleave with other events.

### 3.12 Event payload schemas (complete registry)

Payloads are JSON objects (camelCase). Secrets always masked ([02](02-security-and-secrets.md)). UUIDs uppercase.

#### `service.state_changed`

Owned by [06 §3.4.4](06-execution-engine.md); repeated here for a single reference:

| Field | Type | Optional |
|-------|------|----------|
| `serviceID` | string | no |
| `state` | `ServiceState` enum string | no |
| `pid` | int | yes |
| `exitCode` | int | yes (when `crashed`) |
| `reconnectAttempt`, `reconnectMax` | int | yes (when `reconnecting`) |
| `lastFailure` | string | yes |
| `startedAt` | timestamp | yes |
| `mode` | `managedProcess` \| `composeStack` \| `poller` | yes |

#### `service.log_line`

| Field | Type | Optional |
|-------|------|----------|
| `serviceID` | string | no |
| `lineId` | string (UUID) | no |
| `revision` | u64 | no |
| `kind` | `system` \| `workload` | no |
| `category` | ActivityLogCategory | yes (omit when `workload`) |
| `text` | string | no |
| `timestamp` | timestamp | no |

Emitted on each activity buffer append (`kind: system`) and each workload follow line (`kind: workload`).

#### `service.created`

| Field | Type |
|-------|------|
| `serviceID` | string |
| `workspaceID` | string |

([04 §3.9](04-workspaces-groups-services.md))

#### `service.updated`

| Field | Type |
|-------|------|
| `serviceID` | string |
| `workspaceID` | string |
| `changed` | string[] — subset of `service`, `providers`, `ports`, `memberships`, `activeProvider` |

#### `service.deleted`

| Field | Type |
|-------|------|
| `serviceID` | string |
| `workspaceID` | string |

Side effect: `activity_clear(serviceID)` before or with emission.

#### `group.changed`

| Field | Type | Optional |
|-------|------|----------|
| `workspaceID` | string | no |
| `groupID` | string | yes (absent on full reorder) |
| `change` | `created` \| `updated` \| `deleted` \| `reordered` | no |

#### `workspace.changed`

| Field | Type | Optional |
|-------|------|----------|
| `workspaceID` | string | yes when `change: reordered` lists many |
| `change` | `created` \| `updated` \| `deleted` \| `reordered` | no |
| `changed` | string[] | yes — e.g. `["image"]` |
| `nextWorkspaceId` | string | yes — after delete of selected workspace |

#### `kubeconfig.changed`

| Field | Type |
|-------|------|
| `kubeconfigID` | string |
| `change` | `created` \| `updated` \| `deleted` |

Default virtual id `00000000-0000-0000-0000-000000000001` never emits `deleted`.

#### `settings.changed`

| Field | Type | Optional |
|-------|------|----------|
| `keys` | string[] | no |
| `reason` | `set` \| `reset` \| `import` | no |
| `values` | object | yes — omitted on `reset` |

([03 §4.6](03-settings-and-environment.md))

#### `notify`

Maps 1.x `SystemNotificationCenter.send` (`SystemNotificationCenter.swift:38-78`) to a headless payload. The **client** may still render macOS notifications from this event.

| Field | Type | Optional |
|-------|------|----------|
| `kind` | `serviceCrash` \| `healthCheckFailed` \| `portCollision` \| `custom` | no |
| `title` | string | no |
| `body` | string | no |
| `playSound` | bool | yes — default `true` in 1.x |

Kind-specific fields (also embedded in `title`/`body` as in 1.x):

| kind | Extra fields | Exact title | Exact body pattern |
|------|--------------|-------------|-------------------|
| `serviceCrash` | `serviceName`, `reason?` | `Service Crashed` | With reason: `“<serviceName>” stopped unexpectedly: <reason>`; else: `“<serviceName>” has terminated unexpectedly.` |
| `healthCheckFailed` | `serviceName`, `targetUrl` | `Health Check Failed` | `“<serviceName>” at <targetUrl> is not responding.` (**DEV-13** — 1.x posted locally but health runner did not call `send` in all builds; daemon MUST emit on transition) |
| `portCollision` | `port` (int), `collidingService` | `Port Conflict Detected` | `Port <port> is already in use by “<collidingService>”.` |
| `custom` | — | from caller | from caller |

Curly quotes in bodies are U+201C and U+201D as in `SystemNotificationCenter.swift:63-73`.

**Gating:** `serviceCrash` and `healthCheckFailed` honor effective `notifyOnServiceFailure` ([03](03-settings-and-environment.md), `ExecutionSupervisor.swift:284-289`). `portCollision` is not gated. 1.x testing host skips delivery (`SystemNotificationCenter.swift:42-44`); daemon always emits the event (clients ignore in tests).

Trigger summary ([06](06-execution-engine.md)): managed crash T13, reconnect exhausted T18, health poller enter `crashed` T20; **not** compose poll T19.

#### `data.imported`

| Field | Type |
|-------|------|
| `strategy` | string | import strategy enum from [09](09-dataport.md) |
| `workspaceCount` | int |
| `serviceCount` | int |

Emitted once after successful `data.import`.

#### `data.reset`

| Field | Type |
|-------|------|
| (empty object) | — |

Emitted after successful `data.factory_reset` ([09](09-dataport.md)).

#### `daemon.shutting_down`

| Field | Type | Optional |
|-------|------|----------|
| `stopServices` | bool | yes — from `daemon.shutdown` param |

([14](14-lifecycle-and-platform.md), ADD-06)

### 3.13 `LiveLogEntry` (legacy struct)

`LiveLogEntry.swift` defined a separate struct with `level: "INFO"` and localized time string; **not** used by `LiveLogSession`. The daemon MUST NOT expose this shape on the wire. Activity lines use §3.3.1 / §4.

### 3.14 `service.log_line` vs activity buffer

Clients MAY use either `logs.tail` (poll by `sinceRevision`) or `service.log_line` (push). Both carry the same sanitized `text` for `system` lines. **`logs.tail`** is authoritative for full buffer sync; events can be lossy if the client is disconnected beyond `EVENT_REPLAY_CAPACITY`.

### 3.15 Client-only behavior (`[CLIENT]`)

| Capability | Source |
|------------|--------|
| Log panel open/close gating of `LiveLogSourceRunner` | `docs/specs/06-services.md` |
| ~30 Hz coalesced UI flush | TC-L12, TC-E03 |
| Toolbar clear display (local only in superseded TC-E02) | test matrix |
| Trim notice UI + acknowledge | `LiveLogSession.acknowledgeTrimNotice` |
| `ActivityLogDisplay` SwiftUI colors | `ActivityLogStyle.swift` |
| Download via `NSSavePanel` | 06-services.md |
| macOS notification permission and `UNUserNotificationCenter` | `SystemNotificationCenter` — replaced by `notify` event in V2 |
| `KumaServiceNotification.postServiceUpdated` source keys | replaced by `clientRequestId` / `origin` on events ([04](04-workspaces-groups-services.md)) |
| Panel teardown clearing client buffer | TC-L14 — **not** daemon behavior under DEV-07 |

---

## 4. Data shapes

### 4.1 `ActivityLine` (wire)

| Field | Type | Optional? | Default | JSON key |
|-------|------|-----------|---------|----------|
| id | string (UUID) | no | new UUID | `id` |
| text | string | no | — | `text` |
| timestamp | timestamp | no | now | `timestamp` |
| kind | string enum | no | `system` | `kind` |
| category | string enum | yes | inferred | `category` |

### 4.2 `logs.tail` result

| Field | Type | JSON key |
|-------|------|----------|
| serviceID | string | `serviceID` |
| revision | u64 | `revision` |
| lines | ActivityLine[] | `lines` |
| didTrimToMaxLines | bool | `didTrimToMaxLines` |

### 4.3 `logs.workload_tail` result

| Field | Type | JSON key |
|-------|------|----------|
| serviceID | string | `serviceID` |
| text | string | `text` |
| truncated | bool | `truncated` |

### 4.4 Event envelope

See §3.11.3.

### 4.5 `ActivityLogCategory` enum (wire)

`kuma`, `failure`, `failureContinuation`, `config`, `health`, `monitor`, `raw` — exact raw strings (`ActivityLogFormatting.swift:3-10`).

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC / event |
|---------|-----|-------------|------------|-------------|
| FEAT-LOG-01 | [PARITY] | Run spool directory and per-service `.out` append capture | `RunSpool.swift` | (internal, [06](06-execution-engine.md)) |
| FEAT-LOG-02 | [PARITY] | Spool tail helper (4096 bytes, 8 lines) for `lastFailure` | `RunSpool.swift:43-51` | (internal) |
| FEAT-LOG-03 | [PARITY] | Spool remove on run end | `ExecutionSupervisor` + `RunSpool.remove` | (internal) |
| FEAT-LOG-04 | [DEV] | Spool under `<runtime>/spool`, mode `0600`, selective startup purge | DEV-12 | (internal) |
| FEAT-LOG-05 | [DEV] | Spool size maintenance 8 MiB / keep 4 MiB | DEV-70, `RunSpool.swift:5,53-63` | (internal) |
| FEAT-LOG-06 | [PARITY] | `begin_run` clears buffer and enables capture | `LiveLogSession.swift:77-86` | via [06](06-execution-engine.md) |
| FEAT-LOG-07 | [PARITY] | `end_capture` stops append, retains lines | `LiveLogSession.swift:88-91` | (internal) |
| FEAT-LOG-08 | [DEV] | Buffer retained until `logs.clear` or `begin_run` (not client disconnect) | DEV-07, TC-L13/L14 | `logs.tail`, `logs.clear` |
| FEAT-LOG-09 | [PARITY] | `[KUMA]` prefixed `emit` / batch | `LiveLogSession.swift:115-125` | `service.log_line` |
| FEAT-LOG-10 | [PARITY] | Raw health/monitor lines | `emitRawLine`, `ExecutionSupervisor.swift:474-501` | `service.log_line` |
| FEAT-LOG-11 | [PARITY] | Multiline failure recording + dedupe | `LiveLogSession.swift:144-161`, TC-L18/L23 | `service.log_line` |
| FEAT-LOG-12 | [PARITY] | Configuration issue lines + start blocked line | `LiveLogSession.swift:163-174`, `+Validation.swift:52-61` | `service.log_line`, `service.preflight` |
| FEAT-LOG-13 | [PARITY] | 1000-line ring per service + trim flag | TC-L10 | `logs.tail` |
| FEAT-LOG-14 | [PARITY] | LRU 50 service buffers | TC-L21 | (internal) |
| FEAT-LOG-15 | [PARITY] | ANSI sanitize on activity lines | `ANSISanitizer.swift`, TC-L03 | (internal) |
| FEAT-LOG-16 | [PARITY] | Activity log categories + inference | `ActivityLogFormatting.swift:3-19` | `logs.tail`, `service.log_line` |
| FEAT-LOG-17 | [PARITY] | Per-service isolation | TC-L17 | `logs.tail` |
| FEAT-LOG-18 | [PARITY] | Emit requires active capture (except failure/config paths) | TC-L15 | (internal) |
| FEAT-LOG-19 | [PARITY] | `logs.tail` / buffer read by revision | `LiveLogSession.snapshot` | `logs.tail` |
| FEAT-LOG-20 | [PARITY] | `logs.clear` | `LiveLogSession.clear` | `logs.clear` |
| FEAT-LOG-21 | [V2-ADD] | One-shot workload logs | `LiveLogSourceRunner.swift` | `logs.workload_tail` (ADD-05) |
| FEAT-LOG-22 | [V2-ADD] | Streaming workload logs | `LiveLogSourceRunner.swift` | `logs.follow`, `service.log_line` (ADD-05) |
| FEAT-LOG-23 | [V2-ADD] | Event seq + replay | — | `events.subscribe`, `sinceSeq` (ADD-07) |
| FEAT-LOG-24 | [V2-ADD] | `events.unsubscribe` | — | `events.unsubscribe` |
| FEAT-LOG-25 | [V2-ADD] | Push activity lines | — | `service.log_line` |
| FEAT-LOG-26 | [V2-ADD] | Full registry payload schemas | NotificationCenter + supervisor | all §3.12 events |
| FEAT-LOG-27 | [DEV] | `notify` event for crashes, health, port conflict | `SystemNotificationCenter.swift`, DEV-13 | `notify` |
| FEAT-LOG-28 | [CLIENT] | HH:mm:ss row timestamps and prefix stripping UI | `ActivityLogFormatting.swift` | — |
| FEAT-LOG-29 | [CLIENT] | Log console empty state copy | `InspectorLiveConsoleView.swift:33-37` | — |
| FEAT-LOG-30 | [CLIENT] | SwiftUI category colors | `ActivityLogStyle.swift` | — |
| FEAT-LOG-31 | [CLIENT] | 30 Hz NSTextView coalesce | TC-L12, TC-L11 | — |

---

## 6. Error catalog

| Code | Condition | Message (exact when from 1.x) |
|------|-----------|-------------------------------|
| `KUMA_LOG_WORKLOAD_UNAVAILABLE` | `logs.workload_tail` / `logs.follow` cannot resolve binary, compose context, or kube target | `Workload logs are not available for this service.` |
| `KUMA_LOG_FOLLOW_ACTIVE` | Second `logs.follow` on same service from another subscription without replacing | `A workload log follow is already active for this service.` |
| `KUMA_LOG_SUBSCRIPTION_NOT_FOUND` | `events.unsubscribe` unknown id | `Event subscription '<id>' was not found.` |
| `KUMA_SVC_NOT_FOUND` | Unknown `serviceID` on `logs.*` | `Service '<UUID UPPER>' was not found.` ([06](06-execution-engine.md)) |

Protocol errors (`invalid params`) are owned by [10](10-rpc-protocol.md).

---

## 7. Deviations

| Id | Summary |
|----|---------|
| **DEV-07** | Activity buffer retained until `logs.clear` or `begin_run`; not cleared on client panel close ([§3.3.2](#332-capture-lifecycle)). |
| **DEV-12** | Spool path and permissions; selective purge at daemon start ([§3.2](#32-run-spool-on-disk)). |
| **DEV-13** | Emit `notify` `healthCheckFailed` on health poll transition ([§3.12 `notify`](#notify)). |
| **DEV-38** | Workload log exposure uses `workload` redaction; spool stays raw ([02](02-security-and-secrets.md)). |
| **DEV-70** | Active spool truncation maintenance ([§3.2.4](#324-size-cap-dev-70)). |
| **DEV-91** | Spool tail followers re-seek when file shrinks ([§3.2.4](#324-size-cap-dev-70)). |
| **ADD-05** | `logs.workload_tail`, `logs.follow` ([§3.9–3.10](#39-rpc-logsworkload_tail-add-05)). |
| **ADD-07** | Event `seq`, replay store, `sinceSeq` ([§3.11](#311-event-bus-add-07)). |

---

## 8. Invariants

| Id | Statement |
|----|-----------|
| **INV-D-LOG-01** | For each service, activity line `revision` strictly increases on any line-list mutation. |
| **INV-D-LOG-02** | While not capturing, `emit` / `emitBatch` / `emitRawLine` append nothing (TC-L15, TC-L20). |
| **INV-D-LOG-03** | After `end_capture`, previously stored lines remain until `clear`, `begin_run`, delete, or LRU eviction (TC-L13). |
| **INV-D-LOG-04** | Buffer line count per service never exceeds `ACTIVITY_MAX_LINES`. |
| **INV-D-LOG-05** | At most `ACTIVITY_MAX_SERVICES` non-empty buffers without eviction (TC-L21). |
| **INV-D-LOG-06** | Every activity `text` field is ANSI-sanitized (§3.5) and `strict`-redacted before storage or `service.log_line`. |
| **INV-D-LOG-07** | Spool files for services with a `runtime_process` row survive daemon restart (DEV-12). |
| **INV-D-LOG-08** | Event `seq` is strictly increasing and equals persisted `meta.eventSeq` after each emit. |
| **INV-D-LOG-09** | No secret material from [02](02-security-and-secrets.md) appears in activity lines, `service.log_line`, or `notify` bodies (GR-04). |
| **INV-D-LOG-10** | `service.deleted` clears the activity buffer for that id. |

---

## 9. Acceptance tests

| Id | Arrange | Assert |
|----|---------|--------|
| **DT-LOG-01** | TC-L03 colored string through sanitize | Output `SUCCESS: done.` |
| **DT-LOG-02** | TC-L14: `begin_run`, emit, `begin_run` again | One line `[KUMA] second` |
| **DT-LOG-03** | TC-L13: emit, `end_capture`, emit again | First line kept; second dropped |
| **DT-LOG-04** | TC-L15: emit without `begin_run` | Empty buffer |
| **DT-LOG-05** | TC-L17: two services interleaved `begin_run` | Isolated buffers; second `begin_run` on A clears A only |
| **DT-LOG-06** | TC-L18/L25: multiline failure | `[FAILURE]` + continuation categories |
| **DT-LOG-07** | TC-L10: 1100 emits | Exactly 1000 lines; trim flag set |
| **DT-LOG-08** | TC-L21: max 2 services, touch order | LRU victim buffer empty |
| **DT-LOG-09** | `logs.clear` after lines | `logs.tail` empty; revision reset |
| **DT-LOG-10** | DEV-07: client `events.unsubscribe` only | `logs.tail` still returns lines |
| **DT-LOG-11** | Spool truncate while `logs.follow` tailing | After shrink, follower receives tail from new content (DEV-91) |
| **DT-LOG-12** | `events.subscribe` with `sinceSeq=N` | Receives events `N+1…` in order |
| **DT-LOG-13** | Managed crash with `notifyOnServiceFailure=true` | `notify` `serviceCrash` with exact title/body |
| **DT-LOG-14** | Health poller fail transition | `notify` `healthCheckFailed` (DEV-13) |
| **DT-LOG-15** | Compose stack poll empty | `crashed` without `notify` (T19) |
| **DT-LOG-16** | DT-SEC-36 known secret in start failure | Activity line shows `***` |
| **DT-LOG-17** | Startup with orphan spool + `runtime_process` row | Spool file not deleted (DEV-12) |
| **DT-LOG-18** | `service.deleted` event | Buffer absent on next `logs.tail` |

---

## Open questions / residual risks

1. **Replay truncation:** Clients that reconnect with a stale `sinceSeq` miss events silently except for `replayTruncated`; document in client UX.
2. **Event store growth:** `EVENT_REPLAY_CAPACITY` bounds SQLite; very chatty `service.log_line` workloads could push entity events out of replay — prefer separate subscription for high-volume log lines.
3. **1.x spool purge:** Unconditional purge at launch could delete evidence for processes that outlived the app; DEV-12 fixes this for the daemon only.
4. **UTF-8 spool tail:** Invalid UTF-8 in the last 4096 bytes yields empty decode in 1.x (`RunSpool.swift:48`); DEV-70 in [06](06-execution-engine.md) uses lossy decode for `lastFailure` — activity buffer uses sanitized UTF-8 strings only.

---

## Proposed RPC additions

None. All methods used are in [00 §5.5](00-overview-and-conventions.md).
