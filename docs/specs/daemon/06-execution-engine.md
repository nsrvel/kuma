# 06 - Execution Engine (area `EXE`)

Status: normative. Area code `EXE`, owning RPC methods `service.start`, `service.stop`, `service.restart`, `service.start_all`, `service.stop_all`, `service.status`, `service.statuses`, `ports.check`, `runtime.adopt_report`. Deviation / addition ids owned by this spec: **70-79**. Conventions (IDs, tags, wire rules) are defined in [00](00-overview-and-conventions.md); the persisted `runtime_process` table in [01](01-data-model.md) 3.10; secrets, askpass and redaction in [02](02-security-and-secrets.md); PATH, executable resolution and the shell launch recipe in [03](03-settings-and-environment.md).

---

## 1. Purpose and scope

The execution engine is the part of the Rust daemon that turns a stored service (one active provider of one of eight categories) into a running workload and supervises it: it spawns and stops managed processes, runs `docker|podman compose` stacks, polls HTTP health checks and process monitors, applies the port-conflict policy, reconnects dropped tunnels, captures crash detail, persists what it runs so a daemon restart can adopt it, and publishes an authoritative runtime state for every service.

In Kuma 1.x this logic lived in the Swift app (`Kuma/Core/Execution/**`), and the **authoritative state was split**: `ExecutionSupervisor` held records, but the visible state (`starting`, `stopping`, the 6x50 ms "did it survive" grace, the `lastFailure` banner, the disabled gate, bulk ordering, auto-resume) lived in `ServiceStateStore` and the deck/inspector view models. The daemon makes the engine the single source of truth: clients render what the daemon publishes and never infer state.

In scope:

- Runner routing, the `ServiceRunner` contract, `ExecutionMode`, `ExecutionHandle` (3.2).
- `ServiceState` / `ServiceExecutionState` and their wire mapping (3.3), the authoritative state machine, publication and race guards (3.4, 3.5).
- Start, stop, restart, bulk start/stop, disabled semantics, provider switching (3.6-3.8).
- The seven runners, exact argv and messages (3.9).
- `ProcessRegistry` equivalent: spawn, spool, process groups, escalation, tree termination, exit decisions, adoption of external pids, shutdown primitives (3.10).
- Persistence and orphan adoption across daemon restarts, `runtime.adopt_report` (3.11) - DEV-10 / ADD-03.
- Auto-reconnect (3.12), port conflicts and `ports.check` (3.13), subprocess helpers (3.14), auto-resume and the active-ID snapshot (3.15).
- Notifications, `lastFailure` strings, activity-log lines, constants, test harness notes (3.16-3.19).

Out of scope (owned elsewhere, referenced by number):

| Topic | Owner |
|-------|-------|
| Service/provider CRUD, `service.set_disabled`, `service.switch_provider` RPC bodies, filter semantics of `service.list` | [04](04-workspaces-groups-services.md) |
| Provider validation, `service.preflight` (ADD-01), `URLNormalizer` | [05](05-providers-and-validation.md) |
| Kubeconfig materialization, `KubeConfigExecutionResolver`, `KubeTargetResolver` (kind/name resolution, `kubectl get` helpers) | [07](07-kubernetes.md) |
| Activity-log buffer storage, `logs.*`, `service.log_line`, event bus, `service.state_changed` envelope (seq), `notify` envelope | [08](08-logs-and-events.md) |
| Daemon boot order, `daemon.shutdown`, quit dialog, launch-at-login, socket/PID lock | [14](14-lifecycle-and-platform.md) |
| Factory reset orchestration | [09](09-dataport.md) |

Everything the Swift app did on the main actor for presentation (pills, spinners, alerts, haptics, `NotificationCenter` posts, `SyncedServiceRuntime`) is `[CLIENT]` and listed in the features table so nothing is silently dropped.

---

## 2. 1.x source of truth

All paths relative to `Kuma/` (repository subfolder). Every file below was read in full.

**Core/Execution**

| File | Role |
|------|------|
| `Core/Execution/ServiceExecutionEngine.swift` | Orchestrator, `ServiceExecutionError`, runner routing, stop and force release |
| `Core/Execution/Supervision/ExecutionSupervisor.swift` | Records, publication, compose poll, health/process pollers, crash finalization |
| `Core/Execution/Supervision/ExecutionModels.swift` | `ExecutionMode`, `ExecutionRecord`, `ExecutionHandle` |
| `Core/Execution/ProcessRegistry.swift` | Spawn, spool fds, process group, adoption, stop escalation, `terminateAll` |
| `Core/Execution/ProcessLaunching.swift` | `ProcessLaunching` protocol |
| `Core/Execution/ProcessTreeTerminator.swift` | Descendant snapshot and deepest-first signalling |
| `Core/Execution/SubprocessWait.swift` | `KumaExecutionTimeouts`, bounded waits |
| `Core/Execution/LocalPortConflictResolver.swift`, `PortConflictMessaging.swift` | `lsof` occupancy, policy, messages |
| `Core/Execution/ServiceExecutionStateSync.swift`, `ServiceStartSupport.swift`, `ServiceStopSupport.swift`, `ServiceStopGate.swift`, `ServiceStartFailurePresenter.swift` | Start/stop support shared by deck, inspector, reconnect |
| `Core/Execution/Supervision/AutoReconnectCoordinator.swift`, `AutoReconnectPolicy.swift` | Reconnect loop |
| `Core/Execution/Supervision/RunSpool.swift` | Spool file |
| `Core/Execution/Subprocess/EphemeralCLI.swift` | Short-lived CLI runner |
| `Core/Execution/Compose/ComposeCLI.swift`, `ComposeStackContext.swift`, `ComposeStackResolver.swift`, `ComposeStackRuntime.swift` | Compose plumbing |
| `Core/Execution/Logging/ANSISanitizer.swift`, `LiveLogEntry.swift`, `SystemActivityLogRecording.swift` | Activity-log recording protocol (buffer behavior in [08](08-logs-and-events.md)) |
| `Core/Execution/Runners/ServiceRunnerProtocol.swift`, `ShellRunner.swift`, `KubernetesRunner.swift`, `ContainerRunner.swift`, `SSHTunnelRunner.swift`, `TunnelRunner.swift`, `HealthCheckRunner.swift`, `ProcessMonitorRunner.swift` | The runners |

**Other 1.x files consulted**: `Domain/Enums/ServiceEnums.swift`, `Domain/Enums/ProviderCategory.swift`, `Domain/Models/Provider.swift` (`isAutoReconnectEnabled`), `Stores/ServiceStateStore.swift`, `Stores/ServiceStateStore+Supervisor.swift`, `Core/Notifications/ServiceStateNotification.swift`, `Core/Notifications/SystemNotificationCenter.swift`, `Core/Kubernetes/KubePortForwardPlan.swift`, `KubePortForwardAdoption.swift`, `KubeTargetResolver.swift`, `KubeConfigExecutionResolver.swift`, `KubeLiveTargetDisplay.swift`, `Lib/URLNormalizer.swift`, `Presentation/Features/LiveLogs/LiveLogSystemEmitter.swift`, `LiveLogSession.swift`, `LiveLogRecordingBridge.swift`, `Presentation/Features/Services/ViewModels/ServicesDeckViewModel+ExecutionActions.swift`, `+WorkspaceLoad.swift`, `+ServiceActions.swift`, `+Filtering.swift`, `ServiceInspectorViewModel+Execution.swift`, `+Providers.swift`, `App/AppDelegate.swift`, `Core/Database/Repositories/ServiceRepository+CRUD.swift` (`fetchPortMappings`).

**Docs**: `docs/specs/06-services.md`, `docs/specs/00-app.md` (INV-APP-03), `docs/testing/06-services-test-matrix.md`, `docs/testing/00-app-test-matrix.md`.

**Tests read** (implicit requirements carried into 3.x / 9): `KumaTests/Features/Services/RunnersExecutionTests`, `ExecutionSupervisorTests`, `AutoReconnectTests`, `PortConflictAlertTests`, `ServicesRuntimeAndExecutionTests` (Runtime.D03-D10), `SettingsAndLifecycleTests`, `LifecycleTeardownTests`, and the harness files `RecordingProcessLaunching`, `RecordingComposeCLI`, `ProcessTestSupport`.

---

## 3. Normative behavior

### 3.1 Architecture and concurrency model

The daemon runs these cooperating components inside one async runtime (Tokio). Names are descriptive; the implementation is free to choose module layout.

| Component | Responsibility | 1.x counterpart |
|-----------|----------------|-----------------|
| **Engine** | Entry points `start`, `stop`, `restart`, bulk, status; provider selection; runner dispatch | `ServiceExecutionEngine` |
| **Lane** | One FIFO operation queue per service id (3.5); serializes start/stop/restart and cancels in-flight starts | `ServiceStopGate` + client store guards |
| **Supervisor** | In-memory runtime record per service, state machine, coalesced publication, compose poll loop, poller loop | `ExecutionSupervisor` |
| **Process table** | Managed and adopted OS processes, spool, escalation, tree termination, exit hook | `ProcessRegistry` |
| **Runners** | Seven provider-specific start/stop routines (3.9) | `Runners/*` |
| **Reconnect coordinator** | Backoff loop that re-enters the start pipeline (3.12) | `AutoReconnectCoordinator` |
| **Adoption** | Persist `runtime_process`, adopt orphans at boot (3.11) | new (DEV-10, ADD-03) |
| **Port resolver** | `lsof` occupancy and policy (3.13) | `LocalPortConflictResolver` |

Rules:

1. **Single writer per service.** Only the Lane worker of a service, the process-exit hook of that service's current run, the reconnect task of that service, and the poller/compose loops (for their own mode) mutate that service's runtime record. All of them go through `Supervisor::apply(serviceID, runId, change)`; a change carrying a stale `runId` (3.4.3) is dropped.
2. **No global lock held across an await.** The record map is a `Mutex<HashMap<ServiceId, Record>>` (or equivalent) held only for the synchronous read-modify-write.
3. **All blocking OS calls** (`waitpid`, `proc_listallpids`, directory walks) run on the blocking pool; the async runtime is never blocked (PROC-04 in 1.x).
4. **Service id canonical form**: UPPERCASE hyphenated UUID everywhere on the wire, in `runtime_process.serviceID`, in spool/askpass/compose directory names. Input accepts any case.
5. Time: wall-clock for `startedAt` (ISO-8601 `YYYY-MM-DDTHH:MM:SS.sssZ`); monotonic clock for every delay, timeout and debounce below (so tests can pause time).

### 3.2 Runner routing, contract, modes, handles

**Routing** (`ServiceExecutionEngine.swift:159-169`, `Runners/*`). The active provider's `type` (`ProviderCategory` raw value, [01](01-data-model.md) 3.18.1) selects the runner and execution mode:

| `provider.type` | Runner | `ExecutionMode` | Process kind | Auto-reconnect eligible (`ProviderCategory.supportsAutoReconnect`, `ProviderCategory.swift:37-44`) |
|-----------------|--------|-----------------|--------------|-----|
| `shell` | Shell | `managedProcess` | long-lived managed process | yes |
| `kubernetes` | Kubernetes | `managedProcess` | `kubectl port-forward` (or adopted external) | yes |
| `ssh` | SSH | `managedProcess` | `/usr/bin/ssh` tunnel | yes |
| `tunnel` | Tunnel | `managedProcess` | `cloudflared` or `ngrok` | **no** |
| `docker`, `podman` | Container | `composeStack` | ephemeral compose CLI; stack registered | no |
| `httpCheck` | Health | `poller` | none (supervisor poller) | no |
| `processMonitor` | Monitor | `poller` | none (supervisor poller) | no |

Reconnect is enabled for a run iff `provider.autoReconnect == true` **and** the type is `kubernetes`, `ssh` or `shell` (`Provider.swift:120-122`). The provider consulted at reconnect time is the service's **current** active provider (3.12).

**Contract** (`ServiceRunnerProtocol.swift`). Rust trait, all methods async:

```
trait ServiceRunner: Send + Sync {
    async fn start(&self, ctx: &StartCtx, service: &Service, provider: &Provider) -> Result<(), ExeError>;
    async fn stop(&self, service_id: ServiceId);          // infallible, best effort, idempotent
    async fn is_running(&self, service_id: ServiceId) -> bool;
}
```

`StartCtx` carries the run id, a cancellation token (3.5), the `origin` (`user`, `bulk`, `autoReconnect`, `autoResume`, `restart`, `providerSwitch`) and the activity-log sink. `start` returns once the workload is **registered** (process spawned, stack up and verified, poller registered), never when it is "healthy". `stop` never returns an error; failures are logged.

**Handles** (`ExecutionModels.swift:60-65`). A runner registers exactly one handle with the supervisor:

| Handle | Fields | Resulting record |
|--------|--------|------------------|
| `managedProcess` | `serviceID, serviceName, pid, startedAt` | `mode=managedProcess, state=running, pid, startedAt` |
| `composeStack` | `serviceID, serviceName, context` | `mode=composeStack, state=running, startedAt=now` |
| `pollerHealth` | `serviceID, serviceName, url, intervalSeconds` | `mode=poller, state=running, startedAt=now` |
| `pollerProcess` | `serviceID, serviceName, processName, intervalSeconds` | `mode=poller, state=running, startedAt=now` |

Registering a handle replaces any previous record of the service (the new record has no `lastFailure`, no `exitCode`, no reconnect fields). Registering also writes the `runtime_process` row (3.11.1).

**`isOperational(serviceID)`** (`ExecutionSupervisor.swift:58-65`): true iff the record state is `running`, `starting` or `reconnecting`, **or** the process table has a live process (managed `isRunning` / adopted pid alive) for the service. **`hasActiveWorkload`** (`:67-78`): true iff the process table has a live process, or the record state is `running` or `starting`; `reconnecting`, `stopping`, `stopped`, `crashed`, or no record are false (so a start during reconnect backoff is allowed and cancels the loop, 3.12).

### 3.3 State enums and the wire runtime object

**`ServiceState`** (6 values, raw strings): `stopped`, `starting`, `running`, `stopping`, `reconnecting`, `crashed` ([01](01-data-model.md) 3.18.2). Titles: `Stopped`, `Starting`, `Running`, `Stopping`, `Reconnecting`, `Crashed`.

**`ServiceExecutionState`** (1.x, never persisted; [01](01-data-model.md) 3.18.3) maps from a record (`ExecutionModels.swift:45-57`):

| `ServiceState` | `ServiceExecutionState` | `isLoading` | `statusTitle` |
|----------------|-------------------------|-------------|---------------|
| `stopped` | `idle` | false | `Stopped` |
| `starting` | `starting` | true | `Starting` |
| `running` | `running(pid: record.pid ?? 0)` | false | `Running` |
| `stopping` | `stopping` | true | `Stopping` |
| `reconnecting` | `reconnecting(attempt: record.reconnectAttempt ?? 1, maxAttempts: record.reconnectMax ?? 3)` | true | `Reconnecting (<attempt>/<max>)` |
| `crashed` | `crashed(exitCode: record.exitCode ?? 1)` | false | `Crashed` |

`ServiceExecutionState.failed(reason:)` (title `Failed`, legacy `crashed`) is **never produced** by any 1.x code path; the daemon has no `failed` state. Failures are `crashed` plus `lastFailure`.

**Wire runtime object** (result of `service.status`, element of `service.statuses`; a strict superset of the 1.x `ServiceRuntimeState` keys `status`/`isLoading`/`statusTitle` of [01](01-data-model.md) 4.9, under the daemon's wire names):

| Field | Type | Null when | Notes |
|-------|------|-----------|-------|
| `serviceID` | string (UUID upper) | never | |
| `state` | `ServiceState` string | never | the 1.x `status` |
| `isLoading` | bool | never | `state` in `starting`, `stopping`, `reconnecting` |
| `statusTitle` | string | never | table above |
| `mode` | `managedProcess`\|`composeStack`\|`poller` | the service has never run since daemon start and nothing was adopted | retained after stop (1.x `unregister` keeps the mode) |
| `pid` | int | no pid (compose, health poller, not running, or `starting`) | 1.x encoded "no pid" as `0`; the wire uses `null`. For the process monitor poller it is the matched pid |
| `exitCode` | int | state is not `crashed` | `crashed` always has one; never `0` (3.4.2) |
| `reconnectAttempt` | int | state is not `reconnecting` | 1-based |
| `reconnectMax` | int | state is not `reconnecting` | 3 |
| `lastFailure` | string | no failure text | see 3.4.2; redacted `strict` ([02](02-security-and-secrets.md) 3.12.2) |
| `startedAt` | timestamp | state is `stopped` after a clean stop, or never ran | the start time of the current or last run |
| `resolvedTarget` | string | not a running Kubernetes service | `KubeLiveTargetDisplay` equivalent: the resolved `name` of 3.9.2 step 5, cleared on stop/exit (`KubernetesRunner.swift:42-43, 92-95`, `ExecutionSupervisor.swift:171`) |

`service.state_changed` carries the nine fields `serviceID, state, pid, exitCode, reconnectAttempt, reconnectMax, lastFailure, startedAt, mode` (3.4.4). `isLoading`, `statusTitle`, `resolvedTarget` are derived/read-only and appear only in `service.status` results.

### 3.4 Authoritative state machine

#### 3.4.1 Record

```
Record {
  serviceID, serviceName,
  state: ServiceState,                 // default stopped when absent
  mode: Option<ExecutionMode>,
  pid: Option<i32>, exitCode: Option<i32>,
  startedAt: Option<Instant+WallTime>, lastFailure: Option<String>,
  reconnectAttempt: Option<u32>, reconnectMax: Option<u32>,
  resolvedTarget: Option<String>,
  runId: u64,                          // incremented by every start pipeline entry (user or reconnect attempt) and every adoption
  providerCategory: Option<ProviderCategory>,   // the provider type of the run (3.7 step 6)
}
```

A service with no record behaves as `stopped` with all optionals null.

#### 3.4.2 Transition table (normative)

"Publish" = enqueue a `service.state_changed` (3.4.4). "Immediate" bypasses the 100 ms debounce (DEV-74).

| # | From | Trigger | To | Record effects | Publication |
|---|------|---------|----|----------------|-------------|
| T1 | `stopped`, `crashed`, none | accepted start (3.6 after step 4) | `starting` | clear `exitCode`, `lastFailure`, `reconnect*`, `pid`; `runId += 1` | Immediate |
| T2 | `reconnecting` | accepted user/bulk start | `starting` | as T1; reconnect loop cancelled (3.12) | Immediate |
| T3 | `running`, `starting` | start | unchanged | none (idempotent no-op, 3.6 step 1) | none |
| T4 | `stopping` | start | unchanged until stop completes | start waits in the Lane (3.5) | none |
| T5 | `starting` | runner registered a handle | `running` | `pid` (managed) or null, `startedAt` = spawn time (managed) or now (others), `mode` | debounced |
| T6 | `starting` | runner start failed or was cancelled (3.6 step 8) | `crashed` | `exitCode=1`, `lastFailure=<error description>` (cancelled start: state returns to the pre-stop value via T10, no `crashed`) | Immediate |
| T7 | `running`, `starting`, `reconnecting` | accepted stop (3.7 step 1) | `stopping` | none | Immediate |
| T8 | `crashed`, `stopped`, none | accepted stop | unchanged during the pipeline (stale-`stopping` guard G4) | none | none |
| T9 | `stopping` (or T8 states) | stop pipeline finished or force-released (3.7) | `stopped` | `exitCode=null`, `lastFailure=null`, `pid=null`, `reconnect*=null`, `resolvedTarget=null`; `mode`, `startedAt` per 3.3 (startedAt null) | Immediate |
| T10 | `starting` | start cancelled by a stop | `stopping` (T7) then T9 | | Immediate |
| T11 | `running` (managed) | process exit, `intentionalStop=false`, provider reconnect-eligible (3.12) | `reconnecting` | `reconnectAttempt=1`, `reconnectMax=3`, `pid=null`, `exitCode=null`, `lastFailure=null` (any exit code, **including 0**) | debounced |
| T12 | `running` (managed) | process exit, not intentional, no reconnect, exit code `0` | `stopped` | as T9 | debounced |
| T13 | `running` (managed) | process exit, not intentional, no reconnect, exit code `!= 0` | `crashed` | `exitCode=N`, `lastFailure=<spool tail or null>`, `pid=null`; `notify` `serviceCrash` (3.16) | debounced |
| T14 | `running` (managed) | process exit, `intentionalStop=true` | `stopped` after the stop pipeline (T9) | | via T9 |
| T15 | `reconnecting` | next attempt begins (loop iteration `n`, `n <= 3`) | `reconnecting` | `reconnectAttempt=n` | debounced |
| T16 | `reconnecting` | attempt's start succeeds (handle registered) | `running` | T5 effects; session counter reset | debounced |
| T17 | `reconnecting` | attempt's start fails | `reconnecting` | unchanged (loop continues) | none |
| T18 | `reconnecting` | iteration 4 (attempts exhausted) | `crashed` | `exitCode = (lastExitCode == 0 ? 1 : lastExitCode)`, `lastFailure="Auto reconnect failed after 3 attempts"`; `notify` `serviceCrash` | debounced |
| T19 | `running` (compose) | compose poll finds no running containers | `crashed` | `exitCode=1`, `lastFailure="Compose stack no longer has running containers"`; stack removed from the poll set (runner context kept for stop); **no** `notify` | debounced |
| T20 | `running`, `crashed` (health poller) | poll result | `running` (HTTP 200-399) / `crashed` (otherwise) | `crashed`: `exitCode=1`, `lastFailure="Health check failed"`; `running`: both null; `notify` `healthCheckFailed` on entering `crashed` (DEV-13, 3.9.6) | debounced |
| T21 | `running`, `stopped` (process-monitor poller) | poll result | `running` (match, `pid`=match) / `stopped` (no match, `pid=null`) | `exitCode`, `lastFailure` stay null; the poller stays registered while `stopped` | debounced |
| T22 | any | adoption at boot finds a live verified process / stack / poller (3.11.3) | `running` (or `reconnecting` for a resumed reconnect) | `runId += 1`, `startedAt` from the row | Immediate |
| T23 | `starting`, `running`, `reconnecting` | stop pipeline exceeds 90 s | `stopped` after force release | | Immediate |

`exitCode` of `crashed` is never `0`: a crash finalization with `exitCode == 0` records `1` (`ExecutionSupervisor.swift:279`). `lastFailure` is non-null **only** while the state is `crashed` (plus the transient `reconnecting` text-free state); every transition into `stopped`, `starting`, `running` clears it (matches the combined 1.x record and `ServiceStateStore.applyLastFailure` behavior, `ServiceStateStore+Supervisor.swift:27-37`).

Process exit with a poller or compose record: not applicable (no managed process).

#### 3.4.3 Race-guard rules (carried from the 1.x store tests Runtime.D03-D10)

In 1.x these were client-side filters (`ServiceStateNotification.executionState`, `ServiceStateStore.refreshProcessStates`, `shouldIgnoreSupervisorTransitionDuringReconnect`). With a single daemon writer they become engine rules; each has an invariant (INV-D-EXE-05..09) and a test (DT-EXE-07..11).

| Rule | Statement | 1.x origin |
|------|-----------|------------|
| G1 (D07) | A `running` update without a pid keeps the last known pid. Wire: `pid` is always present when known; a record never loses its pid while `running` | `ServiceStateNotification.swift:50-53` |
| G2 (D09b) | A `stopped` produced by teardown of a *previous* run is ignored while a new start is `starting`. Mechanism: every exit hook, poll result and reconnect tick carries the `runId` it was created for; `apply` drops it when `runId != record.runId` | `ServiceStateNotification.swift:33-37` |
| G3 (D09c) | `stopped` after a stop clears `stopping` and `running` to `stopped` | `:33-37` |
| G4 (D09e) | `stopping` is never published for a service already `stopped`, `crashed`, or with no record (stale `stopping` is ignored) | `:62-68` |
| G5 (D09d) | A late `running` (poller result, delayed adoption, delayed register) is ignored while the state is `stopping` | `:41-48` |
| G6 (D08) | A `crashed` update without an exit code keeps the existing exit code, else `1` | `:69-76` |
| G7 (D10) | Publishing the identical record twice produces one event (dedupe against the last published value) | `ServiceStateStore.swift:62-68` |
| G8 | While `reconnecting`, `stopped`/`starting` produced by the exiting run's late events are ignored; only the reconnect task, a user stop or a user start may leave `reconnecting` | `ServiceStateStore+Supervisor.swift:49-62` |
| G9 (D03) | Background refreshes (compose poll, poller tick, adoption) never overwrite an in-flight `starting` or `stopping` with `stopped`/`running` | `ServiceStateStore.swift:96-122` |

#### 3.4.4 Publication

1. **Snapshot model.** The supervisor keeps `records` and a map `published` (the last published public tuple per service).
2. **Debounce.** After any record change the supervisor (re)arms a one-shot timer of **100 ms** (`ExecutionSupervisor.swift:332-342`: each change cancels and re-arms, i.e. trailing-edge). When it fires, for every service whose public tuple differs from `published` it emits one `service.state_changed` event, in ascending `serviceID` order, then updates `published`. DEV-74: the timer has a **maximum wait of 500 ms** from the first un-flushed change (1.x could starve under constant change), and transitions marked "Immediate" in 3.4.2 flush at once (together with any other pending changes).
3. **Public tuple** = `(state, pid, exitCode, reconnectAttempt, reconnectMax, lastFailure, startedAt, mode)`.
4. **Payload** (`service.state_changed`, camelCase; envelope and `seq` per [08](08-logs-and-events.md)):

| Field | Type | Null when |
|-------|------|-----------|
| `serviceID` | string | never |
| `state` | `ServiceState` | never |
| `pid` | int | no pid |
| `exitCode` | int | not `crashed` |
| `reconnectAttempt`, `reconnectMax` | int | not `reconnecting` |
| `lastFailure` | string | no failure |
| `startedAt` | timestamp | clean `stopped` or never ran |
| `mode` | string | never ran |

5. **Initial state for new subscribers**: the event bus (ADD-07, [08](08-logs-and-events.md)) replays by `seq`; a subscriber that needs the full picture calls `service.statuses` (never debounced; it reads live records).
6. `service.status` / `service.statuses` always read live records, so they can be ahead of the last event by up to 100 ms (500 ms worst case).
7. Services removed from the database (`service.deleted`) get their record dropped after the stop pipeline of DEV-14; a final `stopped` event is published first.

### 3.5 Lane semantics (ordering of start, stop, restart)

1.x had no server-side ordering: UI guards prevented double actions and `ServiceStopGate` only coalesced concurrent stops (`ServiceStopGate.swift:4-18`). Headless callers (CLI, REST, MCP, bulk) can race, so the daemon defines a per-service Lane (DEV-74).

1. **Queue**: FIFO of operations `start`, `stop`, `restart`; one worker per service; operations of different services run concurrently.
2. **start** while the current or a queued operation is a `start`: joins it (receives the same result). While state is `running`: returns immediately (3.6 step 1). Otherwise appended.
3. **stop** while a `stop` is current or queued: joins it and receives its result (the `ServiceStopGate` behavior: all callers await one pipeline run). Otherwise: (a) the current `start`/`restart` (if any) has its cancellation token fired (3.6 step 7a: every ephemeral subprocess it owns is killed, pending waits abort); (b) queued-but-not-started `start`/`restart` operations complete with `KUMA_EXE_START_CANCELLED`; (c) the stop is appended and runs after the cancelled operation unwinds. A stop therefore always wins over a start that was requested earlier.
4. **restart** is one operation: `stop pipeline` (coalescing with a concurrent stop), sleep **300 ms**, `start pipeline`. A `stop` arriving during the sleep or the start part cancels the remainder (`KUMA_EXE_START_CANCELLED`).
5. The reconnect task (3.12) enqueues its attempts as `start` operations with `origin=autoReconnect`; a user `stop` cancels the task first (3.7 step 2), a user `start` supersedes it (T2).
6. The Lane never holds a lock while an RPC waits: callers await a completion handle; client disconnect does not cancel the operation (it finishes and publishes state).

### 3.6 Start pipeline (`service.start`, `ServiceExecutionEngine.start`, `ServiceStartSupport.start`)

Input: `serviceID`. Origin metadata (`user`, `bulk`, `restart`, `providerSwitch`, `autoResume`, `autoReconnect`) does not change the pipeline except where stated.

1. **Guard / idempotency** (`ServiceExecutionEngine.swift:67-72`). If `hasActiveWorkload(serviceID)` (3.2) -> return success immediately with `{serviceID, state:<current>, pid, alreadyRunning:true}`; no state change, no activity-log line, no `runtime_process` write.
2. **Fetch service**. Missing -> `KUMA_EXE_SERVICE_NOT_FOUND`, message `Service '<UUID upper>' was not found.`; no state change (`ServiceExecutionEngine.swift:73-75`).
3. **Disabled gate** (DEV-71). If `service.isDisabled == true` -> `KUMA_EXE_SERVICE_DISABLED`, no state change, no lastFailure, no activity lines. (1.x enforced this only by hiding the button, `ServiceInspectorViewModel+Validation.swift:7`, `ServicesDeckViewModel+ExecutionActions.swift:40`.)
4. **Select provider** (`:75-80`): `providers = fetchProviders(serviceID)` ordered `createdAt ASC` ([01](01-data-model.md) 3.11); `provider = providers.first(where: id == service.activeProviderID) ?? providers.first`. None -> `KUMA_EXE_NO_ACTIVE_PROVIDER` (state: T1 then T6, i.e. `crashed`, `exitCode=1`, `lastFailure` = message; 1.x set `crashed(1)` for this case through `ServiceStartSupport.applyUserStartFailure`).
5. **T1** `starting` (Immediate). `runId += 1`; record `providerCategory = provider.type`; `serviceName = service.name`.
6. **Activity log**: `begin_run(serviceID)` (clears the buffer and enables capture, [08](08-logs-and-events.md); DEV-07 says nothing else clears it) then `emit` the line `Starting "<service.name>" (<provider.type rawValue>)` (straight double quotes, raw name, e.g. `Starting "API" (kubernetes)`, `ExecutionEngine.swift:83-88`).
7. **Run the runner** (`:90-92`) with `ctx.cancel`:
   a. `runner.start(...)` per 3.9. While awaiting, cancellation (3.5) aborts: ephemeral subprocesses are killed (SIGTERM, 500 ms, SIGKILL, 3.14), waits return `KUMA_EXE_START_CANCELLED`.
   b. On success: `AutoReconnectCoordinator.resetSession(serviceID)` (`attemptsCompleted=0`, `lastExitCode=1`, cancels a running loop task, `:30-33`).
8. **Failure** (`:93-99`): emit `Start failed: <description>` where `<description> = errorDescription` of the error (exact strings in 3.9 and 6); rethrow. The engine then applies T6: `state=crashed`, `exitCode=1`, `lastFailure=<description>`. Capture is **not** ended (1.x never called `endCapture` on a failed start; later lines are still appended). `KUMA_EXE_START_CANCELLED` is the exception: emit `Start cancelled.`, no T6.
9. **Success state**. The runner has registered a handle (T5 `running`). There is **no** grace/polling step (DEV-74: 1.x re-checked `isServiceRunning` six times at 50 ms, `ServiceExecutionStateSync.swift:11-18`, and set `crashed(1)` when the process had already exited; in the daemon the exit hook of 3.10.6 decides the final state precisely: exit 0 -> `stopped`, exit N -> `crashed(N)`).
10. **Result**: `{ serviceID, state, pid, alreadyRunning:false }` where `state`/`pid` are the live record values at response time (normally `running`).

`ServiceStartFailurePresenter` (`[CLIENT]`): the **alert** is shown by clients; the daemon provides the decision input as `error.details.portConflict = true` (3.13.4) so every client shows "Port Conflict Detected" identically.

Auto-resume and bulk start use the same pipeline (3.8, 3.15). `ServiceStartSupport.applyUserStartFailure` (set `lastFailure`, `crashed(1)`, present alert) applies to **all** origins in the daemon except `autoReconnect` (whose failures are logged `Reconnect attempt <n> failed: <description>` and keep state `reconnecting`, T17).

### 3.7 Stop pipeline (`service.stop`, `ServiceStopSupport`, `ServiceExecutionEngine.stop`, `ExecutionSupervisor.performStop`)

Input: `serviceID`. Never fails; always ends with state `stopped`.

1. **Gate / coalescing** (`ServiceStopGate`, Lane rule 3.5.3): concurrent stops of one service share one pipeline run and all return when it finishes. Mark `intentionalStop=true` on the `runtime_process` row (3.11.1) before any signal. Publish T7 `stopping` (Immediate) unless T8 applies (state `stopped`/`crashed`/none: G4).
2. **Cancel reconnect** (`performStop:320`): `AutoReconnectCoordinator.cancel(serviceID)` (cancels the task, removes the session).
3. **Total bound**: the whole body below (steps 4-7) runs under `SERVICE_STOP_TOTAL = 90 s` (`SubprocessWait.runWithinTimeout`, `ServiceStopSupport.swift:6-8`). On expiry go to step 8 (force release).
4. **Supervisor stop** (`ExecutionSupervisor.performStop`, `:318-328`): emit `Stopping service…` (U+2026 ellipsis); if the process table has a live process for the service, run the process stop (3.10.4-3.10.5: escalation, `Stopped (exit <n>).` line via the intentional-exit rule, `endCapture`); drop the compose poll entry and poller job; `end_capture`.
5. **Runner stop** (`ServiceExecutionEngine.stop:104-113`, `:141-149`): the runner used is derived from the **run's** `providerCategory` stored on the record (DEV-74(e); 1.x re-resolved the *current* active provider, which leaks a compose stack or a process when the provider was switched/edited/deleted while running). Without a record or with an unknown category all seven runners' `stop` are invoked in this order: kubernetes, shell, container (provider nil), ssh, health, tunnel, monitor. Runner stop behavior: Shell/Tunnel/Kubernetes/SSH: process stop (then k8s clears `resolvedTarget`; SSH removes the askpass dir, DEV-35); Container: 3.9.3.6; Health/Monitor: unregister the poller job.
6. **Remaining process**: if the process table still reports the service as running, run the process stop again (`:115-118`).
7. **Finish**: delete the `runtime_process` row, remove spool and askpass leftovers, set T9 (`stopped`, Immediate), return `{serviceID, state:"stopped", forced:false}`. **Ordering rule (DEV-74)**: `stopped` is published only after step 6 (1.x published `stopped` from `performStop` *before* `compose down` ran, so the UI showed `idle` while containers were still being torn down, then relied on the client `.stopping` override, `ServiceStateStore.swift:107-114`).
8. **Force release** (`ServiceExecutionEngine.forceReleaseService:121-129`, called by `ServiceStopSupport:9-11`): (a) if the run's category is `docker` or `podman`: resolve the compose context and run `down` (`context.downArguments`) with a **15 s** timeout, then the default-project teardown (3.9.3.7) regardless of binding (`ContainerRunner.forceComposeTeardown:118-125`); (b) drop the in-memory stack registration; (c) process stop; (d) supervisor `unregister(stopped)`. Result `{..., forced:true}`. The original pipeline task is cancelled; late events of it are dropped by G2.

`service.stop` on a service that is not running still executes steps 1-7 (idempotent): a `crashed` service becomes `stopped` and its `lastFailure` clears; a crashed compose service still gets `compose down` (the runner kept its context).

### 3.8 Restart, bulk, disabled, provider switch

**Restart** (`service.restart`; `ServicesDeckViewModel+ExecutionActions.swift:72-86`): Lane rule 3.5.4: stop pipeline (3.7), `sleep 300 ms` (`RESTART_DELAY`), start pipeline (3.6, origin `restart`). Result = the start result plus `restarted:true`. Restart of a service that is not running is a start. Restart of a disabled service stops it and then fails the start with `KUMA_EXE_SERVICE_DISABLED` (service ends `stopped`).

**Bulk start** (`service.start_all`; `:37-57`). Params `{workspaceID, search?, starredOnly?, groupID?, statuses?, providers?, sort?, serviceIDs?}` (the `service.list` filter parameters of [04](04-workspaces-groups-services.md) 3.8, flattened). Target set: the services of `workspaceID` selected by those filters using exactly the semantics of `service.list` (search, statuses, providers, starred-only, group, sort), intersected with `serviceIDs` when given (the 1.x target set was the deck's *filtered* list, `ServicesDeckViewModel+Filtering.swift:4-6`; the `statuses` filter evaluates against live runtime). Algorithm: compute `targets = filtered where !isDisabled && !isOperational` (in deck order = `service.list` order); for each target in order: re-check `isOperational` (skip when it became operational), run the start pipeline (origin `bulk`), record success or failure **without stopping the loop**, then sleep **150 ms** (`BULK_STAGGER`; the daemon omits the sleep after the last target). Services filtered in but excluded are reported as skipped (`reason` `disabled` or `alreadyOperational`). Result `{results:[{serviceID, serviceName, outcome:"started"|"skipped"|"failed", state, reason?, error?:{code,message}}], started, skipped, failed}`.

**Bulk stop** (`service.stop_all`; `:59-70`). Same target selection; targets = filtered services with `isOperational`. **Sequential**, in list order: for each target run the stop pipeline (3.7) (1.x awaited each, up to 90 s each; kept for parity: sequential avoids a compose-down stampede). Result `{results:[{serviceID, serviceName, outcome:"stopped"|"skipped", forced}], stopped, skipped}`. `service.stop_all` does not take the shutdown path of 3.10.9.

**Disabled semantics** (DEV-71). `service.start`, `start_all`, `restart`, auto-resume and reconnect attempts all refuse a disabled service (3.6 step 3; bulk and auto-resume skip silently). Disabling a **running** service: `service.set_disabled {isDisabled:true}` ([04](04-workspaces-groups-services.md) DEV-51) persists the flag first and then runs the stop pipeline of 3.7 and waits for it; the disabled gate (3.6 step 3) therefore rejects any start that races with that stop, and the service ends `stopped` (1.x only reset the client state to `idle` while the process kept running, `ServicesDeckViewModel+ServiceActions.swift:44-46`; the registry then re-surfaced it as running).

**Provider switch** (`service.switch_provider` is owned by 04; the 06 contract, `ServicesDeckViewModel+ServiceActions.swift:61-95`, `ServiceInspectorViewModel+Providers.swift:5-40`): `wasOperational = isOperational(serviceID)`; if true, run the stop pipeline **with the old provider's runner** (5 above); persist the new `activeProviderID` (04); if `wasOperational`, run the start pipeline (origin `providerSwitch`); if that start throws, the service ends `crashed` with the error as `lastFailure` (1.x deck: `crashed(1)`). Preflight validation (inspector `validateConfigurationForStart`) is `service.preflight` (ADD-01) and is client-driven; `service.start` itself never runs it.

---

### 3.9 Runners

Common rules: every runner receives the service and the **active provider row with decrypted secrets** ([02](02-security-and-secrets.md) 3.5/3.6); every string field below is `trim`med (whitespace and newlines) before use unless stated; "expandTilde" is `NSString.expandingTildeInPath` semantics (`~` and `~/` only, using the real home of [03](03-settings-and-environment.md) 3.10); port mappings are the **visible** mappings of [01](01-data-model.md) 3.11.2 for the active provider in `ORDER BY rowid` order; executables come from the resolvers of [03](03-settings-and-environment.md) 3.10.6 (`custom path`, legacy key per DEV-02, then PATH). All error descriptions below are the exact `ServiceExecutionError.errorDescription` (3.9.8) and are what `Start failed: <description>` and `lastFailure` contain.

#### 3.9.1 Shell runner (`ShellRunner.swift:13-58`)

1. `runCommand = trim(provider.runCommand)`; empty or null -> `invalidConfiguration("No shell command specified.")`.
2. `workingDirectory`: if `trim(provider.workingDirectory)` is non-empty: `resolved = expandTilde(raw)`; it MUST exist and be a directory, else `invalidConfiguration("Working directory does not exist: '<raw>'")` (`<raw>` is the trimmed, **unexpanded** text). Empty: no cwd (the child inherits the daemon cwd, which the daemon sets to the user's home at boot, [14](14-lifecycle-and-platform.md)).
3. Environment: the daemon environment with `PATH` replaced by the resolved PATH ([03](03-settings-and-environment.md) 3.10.2). Nothing else is added.
4. Launch spec from [03](03-settings-and-environment.md) 3.10.8 `launch_spec(runCommand)`: `executable = shellPath`, `arguments` per shell family (`["-c", <bootstrap>, "--", runCommand]`; fish `["-c", "eval $argv[1]", "--", runCommand]`). The bootstrap's `trap 'kill -TERM 0 …' EXIT INT TERM` signals the shell's **own process group**; therefore the process group MUST be the child's own (3.10.1, DEV-78(a)).
5. Activity line: `Launching shell command (cwd: <resolved>)…` when a cwd is set, else `Launching shell command…` (U+2026).
6. `launch(...)` (3.10.1). No port-conflict check for Shell.

`stop` = process stop (3.10.4). Shell has no preflight beyond steps 1-2.

#### 3.9.2 Kubernetes runner (`KubernetesRunner.swift:20-90`, `KubePortForwardPlan.swift`, `KubePortForwardAdoption.swift`)

1. `kubectl` = resolver ([03](03-settings-and-environment.md) 3.10.6); null -> `binaryNotFound("kubectl")`.
2. Visible port mappings; empty -> `invalidConfiguration("At least one port mapping (Local:Remote) is required for Kubernetes port-forwarding.")`.
3. `execConfig = KubeConfigExecutionResolver.resolve(provider)` ([07](07-kubernetes.md)): `kubeconfigPath?`, `context?`. `namespace = trim(provider.kubeNamespace)`, `context = trim(execConfig.context)`. Errors from this step and step 4 propagate unchanged with their 1.x case (`invalidConfiguration` / `processFailed`, e.g. `Selected kubeconfig no longer exists.`, `Target resource name is required (e.g. my-app-service or pod pattern).`, `Kubectl <resource> discovery error: <stderr>`, `No running pods found in namespace '<ns>'.`).
4. `resolved = KubeTargetResolver.resolve(provider, kubectl, execConfig)` ([07](07-kubernetes.md)): `kind`, `name`; `kubectlReference = "<kind>/<name>"`. Helper subprocesses use `EphemeralCLI` with the 30 s `kubectlSubcommand` timeout (3.14).
5. Set `resolvedTarget = resolved.name`; activity line `Resolved target: <name>`.
6. Build the plan (argv, **exact order**):

```
port-forward <kind>/<name>
[--kubeconfig <kubeconfigPath>]            only when execConfig.kubeconfigPath is non-empty
<local>:<remote>                           one element per mapping, mapping order
[-n <namespace>]                           only when namespace non-empty
[--context <context>]                      only when context non-empty
```
   `localPorts = mappings.map(localPort)`.
7. **Adoption of an existing port-forward** (`findAdoptablePID`): for each local port (in mapping order) call `occupyingPIDs(port)` (3.13); if **any** port has no occupant -> no adoption. `common = intersection` of all pid sets; empty -> no adoption. For `pid` in `common` ascending: `command = ps -p <pid> -ww -o command=` (trimmed, empty -> skip); first `matchesPortForward` wins. `matchesPortForward(commandLine, plan)`:
   a. `lower(commandLine)` contains `kubectl` and `port-forward`;
   b. `commandLine` contains `plan.kubectlReference` (case-sensitive);
   c. every plan argument that contains `:` and does not start with `-` is a substring of `commandLine`;
   d. if the plan has `-n <ns>`: `commandLine` contains `-n <ns>`, `-n=<ns>`, `--namespace <ns>`, `--namespace=<ns>` or (fallback) the bare `<ns>`;
   e. if the plan has `--context <c>`: same with flag `--context` (`--context <c>`, `--context=<c>`, bare `<c>`);
   f. if the plan has `--kubeconfig <p>`: `expanded = expandTilde(p)`; match iff `commandLine` contains `expanded`, or contains `basename(expanded)` (non-empty); otherwise false;
   g. otherwise true. (A plan without `-n` does not check the namespace: parity.)
   On a match: log, activity line `Adopted existing port-forward (PID <pid>)`, `adoptExternalProcess(serviceID, name, pid)` (3.10.3) and **return** (no port check, no launch). DEV-78(e): if the adoption registration finds the pid no longer alive, the runner falls through to step 8 instead of returning a "started" service with no state.
8. For each mapping in order: `ensurePortAvailable(localPort, serviceID, serviceName)` (3.13); a failure aborts the start (`portInUse`).
9. Activity line `Launching kubectl port-forward…`; launch (3.10.1) with `executable=kubectl`, argv of step 6, no cwd, environment = daemon env + PATH (DEV-79).

`stop`: process stop, then clear `resolvedTarget`. `kubectl` is expected to run until killed; there is no readiness probe: `running` means "spawned".

#### 3.9.3 Container runner (docker, podman) (`ContainerRunner.swift`, `Compose/*`)

##### 3.9.3.1 Binary and context

1. `binaryName = "docker"` for `docker`, `"podman"` for `podman`. Path from the resolver ([03](03-settings-and-environment.md) 3.10.6); null -> `binaryNotFound(binaryName)`.
2. `makeContext` (`ComposeStackResolver.swift`):
   - `configuredWorkingDirectory`: `trim(provider.workingDirectory)` non-empty, expandTilde, exists **and is a directory**; otherwise `null` (an invalid directory is silently ignored).
   - If `trim(provider.composeFilePath)` is non-empty: `expanded = expandTilde(raw)`; must exist and not be a directory, else `invalidConfiguration("Compose file not found: <raw>")`. `workingDirectory = configuredWorkingDirectory ?? dirname(expanded)`; `isEphemeralComposeFile=false`.
   - Else if `trim(provider.yamlConfig)` is non-empty: write the **trimmed** YAML text (UTF-8; `ComposeStackResolver.swift:25-39` writes the whitespace-trimmed value it tested, not the stored column text) to `docker-compose.kuma.yml`; location per DEV-75 (below); write failure -> `processFailed("Failed to write compose YAML: <os error>")`; `isEphemeralComposeFile=true`.
   - Else `invalidConfiguration("No compose file or YAML configured")`.
   - `projectName = "kuma-" + lowercase(uuid without hyphens)` (e.g. `kuma-0b1c...`); `projectBinding = kumaProject`.
3. **DEV-75 (compose YAML location, safety)**. 1.x wrote the YAML to `<workingDirectory>/docker-compose.kuma.yml` when a working directory was configured and, at teardown, **deleted the file's whole parent folder** (`ContainerRunner.swift:141-144`), i.e. the user's working directory. The daemon: the YAML is always written to `<runtime dir>/compose/<SERVICEID UPPER>/docker-compose.kuma.yml` (directory `0700`, file `0600`, created `O_EXCL` then renamed atomically); the subprocess cwd is `configuredWorkingDirectory` when set, else that directory; when `configuredWorkingDirectory` is set the compose argv gains `--project-directory <configuredWorkingDirectory>` immediately after `-p <project>` (or after `compose` for the implicit binding) so relative paths and `.env` resolve exactly as when the file lived there; teardown removes **only** `<runtime dir>/compose/<SERVICEID UPPER>/` and records it as `ephemeralDir` in the context. `composeFilePath` runs are never removed.

##### 3.9.3.2 Compose argv (`ComposeStackContext.swift`)

`binaryPath` is the executable; `P = -p <projectName>`; `F = -f <composeFilePath>`; `D = --project-directory <dir>` (DEV-75 only).

| Name | argv (`kumaProject` binding) | argv (`implicitDefault` binding) |
|------|-----------------------------|----------------------------------|
| up | `compose P [D] F up -d --remove-orphans` | `compose [D] F up -d --remove-orphans` |
| ps | `compose P [D] F ps -q --status running` | `compose [D] F ps -q --status running` |
| down | `compose P [D] F down --timeout 5 --remove-orphans` | `compose [D] F down --timeout 5 --remove-orphans` |
| `stopArguments` (`compose … stop --timeout 5`) | defined in 1.x but **never called** (dead code; not implemented) | |

Working directory of every compose subprocess: `context.workingDirectory`.

##### 3.9.3.3 Adoption of an implicit-default stack (`ComposeStackRuntime.shouldAdoptImplicitDefaultStack`)

Before running any script: `kumaIDs = ps(kumaProject)`; if non-empty -> no adoption. `implicitIDs = ps(implicitDefault)`; non-empty -> **adopt**: `context = context.adoptingImplicitDefaultProject()` (binding `implicitDefault`, same `projectName`), activity line `Adopted running compose stack (project <projectName>)`, register the stack in the runner and the supervisor (`composeStack` handle), return. `ps` is `ComposeStackRuntime.runningContainerIDs`: argv above, timeout **20 s**, separated capture; exit status `!= 0`, a timeout or a spawn failure yields `[]`; otherwise trimmed non-empty lines are the ids.

##### 3.9.3.4 Initial script (`runInitialScript:213-272`)

Runs after the adoption check and before `up`, with `cwd = context.workingDirectory`, bounded by `initialScript = 120 s`:

1. If `trim(provider.initialScriptPath)` non-empty: `expanded = expandTilde(raw)`; not an existing non-directory file -> `invalidConfiguration("Startup script file not found: <raw>")` (aborts the start). Run `/bin/sh <expanded>`.
2. Else if `trim(provider.initialScript)` non-empty: run `/bin/zsh -c <B> -- <script>` with `B = [ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; eval "$1"` (always zsh, not the configured default shell).
3. stdout and stderr are merged into a pipe and only logged at info level (never into the activity log); a **non-zero exit, a spawn failure or a timeout does not fail the start** (a timeout kills the script, logs a warning and continues with `up`). The script is `ps`-visible; its environment is the daemon environment with the DEV-79 PATH; stdin is `/dev/null` (DEV-78).

##### 3.9.3.5 `up`, verification, registration

1. Activity line `Running compose up -d (project <projectName>)`.
2. Run `up` (merged stdout+stderr, timeout **120 s**). A timeout throws `processFailed("Command timed out after 120s")`, description `Execution failed: Command timed out after 120s`. A spawn failure is, in 1.x, the raw Foundation error of `Process.run()` (not a `ServiceExecutionError`, so the description is the bare OS text without the `Execution failed:` prefix); the daemon cannot reproduce Foundation's text and uses the uniform DEV-78(g) form `Execution failed: Failed to launch '<binary>': <os error>` (3.14).
3. Exit status `!= 0`: `failure = composeFailureMessage(binaryName, context, exitCode, output)` with `trimmed = output.trim()`, `lower = lowercase(trimmed)`:
   - if `lower` contains `port is already allocated`, **or** (`lower` contains `bind for` **and** `lower` contains `failed`): `Port conflict: another process (often an existing `<binaryName> compose` from Terminal) is already using a host port. Stop that stack or change local ports. <trimmed>`;
   - else if `trimmed` non-empty: `<binaryName> compose up exited with code <exitCode>: <trimmed>`;
   - else `<binaryName> compose up exited with code <exitCode> (project <projectName>).`
   Emit `failure` with every `\n` replaced by a space as an activity line. If `isComposePortConflictMessage(failure)` (3.13.3) **and** the effective port-conflict policy is `warn_and_block`: throw `portInUse(port: 0, collidingService: "another process", startingServiceName: service.name)` (no `notify`). Otherwise throw `processFailed(failure)`.
4. Exit status `0`: verify (`composeHasRunningContainers`): up to **4** attempts of `ps` (kumaProject binding), **200 ms** sleep between attempts (none before the first); any non-empty id list passes. If none: `processFailed("Compose up succeeded for project “<projectName>” but no running containers were found. If you already started this stack in Terminal (without `-p <projectName>`), stop it there first or fix port conflicts, then start again from Kuma.")`.
5. Register the stack in the runner (`activeStacks[serviceID]`) and the supervisor handle (`composeStack`); persist the row (3.11.1).

##### 3.9.3.6 Stop (`ContainerRunner.stop:95-110`, `teardownStack:134-145`)

1. Process stop (no-op for compose; kept for parity).
2. Context: the registered context; else, in the daemon, the context persisted in `runtime_process.composeContextJSON`; else rebuild with `makeContext` from the **run's provider** (3.7 step 5; rebuilding rewrites the ephemeral YAML). Null (provider missing/binary missing) -> log a warning, skip teardown.
3. Unregister the stack.
4. `down` (argv 3.9.3.2) with timeout `composeDown = 45 s`, errors and non-zero exit ignored.
5. If `projectBinding == kumaProject`: default-project teardown (3.9.3.7).
6. If `isEphemeralComposeFile`: remove the ephemeral directory (DEV-75: `ephemeralDir` only).

Force release (3.7 step 8) uses the same `down` with timeout **15 s** and always runs 3.9.3.7 afterwards.

##### 3.9.3.7 Default-project teardown (`teardownDefaultComposeProjectIfNeeded:168-190`)

`ps -q --status running` with the **implicit** argv, timeout 15 s, separated capture; if any trimmed line is non-empty: `compose -f <file> down --timeout 5 --remove-orphans` (note: **no** `-p`, **no** `--project-directory` change beyond DEV-75's `D`), timeout `composeDown = 45 s`, output discarded. All errors ignored.

##### 3.9.3.8 Compose poll (`ExecutionSupervisor.swift:346-388`)

While at least one compose context is registered a loop runs `poll`, then sleeps **5 s**. `poll` checks each registered context sequentially with `ps` (binding of the context, 20 s timeout). If the id list is empty (including `ps` failure, timeout, or the engine being unreachable): activity line `Compose stack has no running containers`; T19 `crashed` (`exitCode=1`, `lastFailure="Compose stack no longer has running containers"`); the context is removed from the poll set (the runner keeps its own context for `stop`); `end_capture`. The result is applied only if the record still has the `runId` and `running` state it was started for (G2/G9). No `notify` is emitted for compose crashes (1.x behavior).

#### 3.9.4 SSH runner (`SSHTunnelRunner.swift:22-112`)

1. `host = trim(provider.sshHost)`; empty -> `invalidConfiguration("SSH Host is not configured.")`.
2. `user = trim(provider.sshUser)`; when null: the OS user name of the daemon (`getpwuid(getuid()).pw_name`, 1.x `NSUserName()`). (`sshUser` cannot be the empty string after provider validation, [05](05-providers-and-validation.md); a stored empty string behaves as 1.x: `@<host>`.) `port = provider.sshPort ?? 22`.
3. Visible port mappings; empty -> `invalidConfiguration("At least one port mapping (Local:Remote) is required for SSH tunneling.")`.
4. Base argv: `-N`, `-o ExitOnForwardFailure=yes`, `-o StrictHostKeyChecking=accept-new`, `-o ServerAliveInterval=15`, `-o ServerAliveCountMax=3`, `-p <port>` (each `-o` and its value are separate argv elements).
5. Credential branch (password wins over key):
   - `password = trim(provider.sshPassword)` after the read rules of [02](02-security-and-secrets.md) 3.5/3.6 (decrypt; legacy plaintext fallback; `vault:` handling; DEV-37). If non-empty: create the askpass script **exactly as [02](02-security-and-secrets.md) 3.7.1 (DEV-35)** (script emits the password verbatim, dir `<runtime dir>/askpass/<SERVICEID UPPER>/`, mode `0700`, NUL -> `invalidConfiguration("SSH password contains an unsupported character.")`); environment additions `SSH_ASKPASS=<abs script>`, `SSH_ASKPASS_REQUIRE=force`, `DISPLAY=kuma:0`; append argv `-o PreferredAuthentications=password,keyboard-interactive`, `-o PubkeyAuthentication=no`, `-o NumberOfPasswordPrompts=1`. The password never appears on argv or in the environment; the effective password is in the redaction known-set while the script exists.
   - Else if `keyPath = trim(provider.sshKeyPath)` non-empty: `vault:`-prefixed values per [02](02-security-and-secrets.md) 3.6 (decrypt failure -> `processFailed("Failed to decrypt SSH key path: <error>")`); `expanded = expandTilde(keyPath)`; if the path does not exist (`fileExists`, any type): `invalidConfiguration("SSH private key file not found: '<keyPath>'")` (`<keyPath>` is the stripped/decrypted text before tilde expansion); else append `-i <expanded>`.
   - Else: no credential flags (ssh uses agent / default keys; with no tty and stdin `/dev/null` ssh fails fast instead of prompting).
6. For each mapping append `-L <localPort>:localhost:<remotePort>`.
7. Append destination `<user>@<host>` (last element). DEV-78(f): `host` or `user` that start with `-`, are empty after trim, or contain whitespace or control characters -> `invalidConfiguration("SSH host or user contains unsupported characters.")` (prevents option injection through the destination element; 1.x passed them through).
8. `ensurePortAvailable` for each mapping in order (3.13) - **after** the askpass script was created; any failure from here on removes the askpass directory (DEV-35 "failed start after creation").
9. Launch (3.10.1): `executable=/usr/bin/ssh`, the argv above, no cwd, env = daemon env + PATH + the three askpass variables when applicable. No activity line is emitted by the runner itself.

`stop`: process stop, then remove the askpass directory (also removed on any child exit, DEV-35).

Full argv example (password auth): `-N -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p 22 -o PreferredAuthentications=password,keyboard-interactive -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 -L 5432:localhost:5432 alice@bastion.example.com`.

#### 3.9.5 Tunnel runner (`TunnelRunner.swift:14-90`)

1. `engine = lowercase(provider.tunnelType) ?? "cloudflare"` (`tunnelType` is not trimmed here); `engine == "ngrok"` -> ngrok, **anything else** (including unknown values) -> cloudflare.
2. `rawTarget = trim(provider.tunnelTargetUrl)`; empty -> `invalidConfiguration("Tunnel target (port or local URL) is required.")`.
3. `target = URLNormalizer.normalize(rawTarget, defaultToHttps: false)` ([05](05-providers-and-validation.md); e.g. `3000` -> `http://localhost:3000`, `example.local:8080` -> `http://example.local:8080`) or, when it returns null, the literal `http://localhost:3000`.
4. Cloudflare: `cloudflared` from the resolver (null -> `binaryNotFound("cloudflared")`); argv `tunnel --url <target> --no-autoupdate`.
5. ngrok: `ngrok` (null -> `binaryNotFound("ngrok")`); argv `http <target>`; if `token = trim(provider.ngrokAuthToken)` is non-empty (`vault:` handling per [02](02-security-and-secrets.md) 3.6; failure -> verbatim): append `--authtoken <token>`. The token is therefore visible in the process list (1.x behavior, kept); it is redacted everywhere the daemon records or echoes argv ([02](02-security-and-secrets.md) 3.12).
6. Launch (3.10.1): no cwd, no extra env (daemon env + PATH, DEV-79). No port check, no activity line.

Tunnel is **not** reconnect-eligible (3.2).

#### 3.9.6 Health-check poller (`HealthCheckRunner.swift`, `ExecutionSupervisor.swift:404-479`)

Start:
1. `raw = trim(provider.httpCheckUrl)`; empty -> `invalidConfiguration("Health Check Target URL is not specified.")`.
2. `normalized = URLNormalizer.normalize(raw)` (default https) and `URL(string: normalized)` must succeed, else `invalidConfiguration("Invalid Health Check URL: '<raw>'.")`.
3. `intervalSeconds = max(provider.httpCheckInterval ?? 10, 3)`.
4. Register the `pollerHealth` handle (record `running`, `mode=poller`, no pid) and the poller job; persist the row (`pollerJSON`, 3.11.1). No activity line other than the first poll's `[HEALTH]` line.

Loop (one shared loop while any job exists; **tick = 1 s**): each tick runs every job whose `nextDue <= now` (a new job is due immediately). DEV-76: jobs run **concurrently** (each at most one in-flight probe per service) instead of sequentially, so one slow probe cannot delay others.

Probe: `GET <url>` (no body, default headers, redirects followed, system trust store, cookies/cache off). DEV-06: request timeout **`HEALTH_PROBE_TIMEOUT = 5 s`** (1.x used the platform default of 60 s). Result: final status in `200...399` -> `running`; any other status, TLS/transport error or timeout -> `crashed`. Apply: record (`running`: exitCode/lastFailure null; `crashed`: `exitCode=1`, `lastFailure="Health check failed"`), `nextDue = now + intervalSeconds`, publish. Result application is guarded by a per-registration generation (DEV-76; 1.x could resurrect a stopped record when a probe finished after `stop`).

Log: the state is compared with the previously **logged** state; on change (including the very first result) emit the raw activity line (no `[KUMA]` prefix, `emit_raw_line`) `[HEALTH] <url.absoluteString> -> <running|crashed>` where `<url>` is the normalized string. DEV-13: when the new state is `crashed` and the previous logged state was `running` or absent, emit a `notify` `healthCheckFailed` (3.16) if `notifyOnServiceFailure` is effective-true.

#### 3.9.7 Process-monitor poller (`ProcessMonitorRunner.swift`, `ExecutionSupervisor.swift:481-503, 520-541`)

Start: `name = trim(provider.monitorProcessName)`; empty -> `invalidConfiguration("Process name to monitor is required.")`; `intervalSeconds = max(provider.monitorInterval ?? 5, 2)`; register `pollerProcess`.

Tick: if at least one due job is a process monitor, run **one** batched lookup `/bin/ps -axo pid=,command=` (timeout 30 s, separated capture; failure -> empty map). DEV-76: 1.x ran this `ps` every tick whenever *any* poller existed; the daemon runs it only when a process job is due. Parsing: per line, trim; split at the first space into `pid` and `command`; skip lines without a space or with a non-numeric pid. Matching: a job matches the **lowest pid** whose `command` contains `name` as a case-sensitive substring, excluding the `ps` child of this very lookup and the daemon's own pid (DEV-76; 1.x picked an arbitrary dictionary entry and could match the `ps` process or Kuma itself).

Apply: matched -> `running` with `pid`; no match -> `stopped`, `pid=null` (the job stays registered), `startedAt` preserved, `exitCode`/`lastFailure` null; `nextDue = now + intervalSeconds`. Log on change of "running" (first result included): `[MONITOR] <name> -> PID <pid>` or `[MONITOR] <name> -> not running` (raw lines).

Because a not-running monitor is `stopped` yet registered, `isOperational` is false for it while it still polls; `service.start` re-registers it and `service.stop` unregisters it (parity).

#### 3.9.8 `ServiceExecutionError` mapping

| 1.x case | `description` | Daemon code |
|----------|---------------|-------------|
| `serviceNotFound(id)` | `Service '<id>' was not found.` | `KUMA_EXE_SERVICE_NOT_FOUND` |
| `noActiveProvider` | `No active runner provider is configured for this service.` | `KUMA_EXE_NO_ACTIVE_PROVIDER` |
| `invalidConfiguration(m)` | `Invalid configuration: <m>` | `KUMA_EXE_INVALID_CONFIG` |
| `binaryNotFound(n)` | `Required binary '<n>' could not be located on this Mac.` | `KUMA_EXE_BINARY_NOT_FOUND` |
| `processFailed(r)` | `Execution failed: <r>` | `KUMA_EXE_PROCESS_FAILED` |
| `portInUse(port, colliding, name)` | `PortConflictMessaging.blockedStartMessage` (3.13.3) | `KUMA_EXE_PORT_IN_USE` |

The string `... on this Mac.` is kept verbatim on Linux (parity of text; DEV-77 does not change it).

### 3.10 Process table and launching (`ProcessRegistry`, `ProcessLaunching`, `ProcessTreeTerminator`, `RunSpool`)

#### 3.10.1 Spawn rules (`ProcessRegistry.launch:90-178`)

1. If a managed process already exists for the service: run the full process stop (3.10.4) first (`:101-103`).
2. Executable is an absolute path chosen by the runner; the launcher does no PATH search. Spawn failure: `processFailed("Failed to launch '<executable>': <os error text>")` (DEV-78(g); 1.x leaked the raw `Process.run` error text).
3. Working directory only when non-empty. Environment: when the runner passes overrides, the daemon environment with the overrides applied on top; otherwise inherited. DEV-79: `PATH` is always the resolved PATH of [03](03-settings-and-environment.md) 3.10.2 unless the runner supplied its own `PATH`.
4. **Spool and stdio** (`RunSpool.openAppendFD`): open `<runtime dir>/spool/<SERVICEID UPPER>.out` with `O_WRONLY | O_CREAT | O_APPEND`, mode **`0600`** (DEV-12 location, DEV-36 mode; 1.x: `$TMPDIR/kuma-run/<uuid>.out`, `0644`); the spool directory is `0700`. The file is **not** truncated at open. `stdout` = that fd; `stderr` = `dup(fd)` (when `dup` fails, the same fd); `stdin` = `/dev/null` (DEV-78(c); 1.x inherited the app's stdin). Open failure: `processFailed("Cannot open run spool '<path>': <os error text>")`.
5. **Process group** (DEV-78(a)): the child calls `setpgid(0, 0)` **before exec** (`CommandExt::process_group(0)`), so `pgid == pid` always. (1.x called `setpgid(pid, pid)` from the parent *after* `run()`; after the child had exec'd this fails with `EACCES` and the runner fell back to single-process signals, `ProcessRegistry.swift:136-146`, leaving the Shell trap `kill -TERM 0` free to target the app's own group.) Signal target is therefore always `processGroup(pgid)`.
6. `startedAt = now`. Register in the table (`ManagedProcess{serviceID, name, pid, pgid, startedAt}`), register the supervisor handle `managedProcess(...)` (T5), insert the `runtime_process` row (3.11.1), emit the activity line `Process running (PID <pid>)`.
7. A reaper task waits for the child on the blocking pool and, on exit, calls `handleProcessTerminated(serviceID, exitCode)` (3.10.6). Exit code = process exit status; for a child killed by a signal, the **signal number** (Foundation `terminationStatus` semantics; `ExitStatus::signal()`), e.g. `9`, `15`, `11`.
8. Returns the pid. The launcher does not wait for the process to prove it is healthy.

`ProcessLaunching` (1.x protocol) is the seam the runner tests use; the Rust equivalent is `trait ProcessSpawner { launch, stop, is_running, adopt_external }` with a recording fake (3.19).

#### 3.10.2 Descendant tree (`ProcessTreeTerminator`)

- `subtree(root)`: `root <= 1` -> empty set. Else build the parent map of **all** processes (macOS: `proc_listallpids` with a dynamically sized buffer + `proc_pidinfo(PROC_PIDTBSDINFO)` `pbi_ppid`; Linux: `/proc/<pid>/stat`, `ppid` = field 4 parsed after the last `)`); ignore pids `<= 1`; BFS from `root`; the result includes `root`. (1.x used a fixed buffer of 16 384 pids; the dynamic buffer is DEV-78(b).)
- `isAlive(pid)`: `pid > 1 && kill(pid, 0) == 0`.
- `send(signal, subtree, root)`: order = depth descending (deepest first; computed from a fresh parent map restricted to the snapshot), skipping the daemon's own pid; each `kill(pid, signal)`; errors other than `ESRCH` are logged at debug.
- `anyAlive(subtree)`: any member alive per `isAlive`.
- The subtree is **snapshotted once** at the start of a stop; descendants spawned later are reached only via the process-group signal.

#### 3.10.3 Adopted external processes (`adoptExternalProcess:180-218`)

Used by the Kubernetes runner (3.9.2 step 7) and by orphan adoption (3.11). Registration of `(serviceID, name, pid)`:

1. If a managed process exists for the service: process stop first. Cancel and drop any previous adoption of the service.
2. `pid <= 0` or not alive -> return silently (nothing registered; DEV-78(e) lets callers detect this and fall through).
3. `startedAt = now` (orphan adoption passes the persisted `startedAt`). Record `AdoptedProcess{serviceID, name, pid, startedAt}`; supervisor handle `managedProcess(pid, startedAt)`; row `adopted=1`; activity line `Process running (PID <pid>)`.
4. Monitor task: every **1 s** check liveness; when the pid is gone (or its start time differs from the recorded one, DEV-78(d): pid-reuse guard using `pidStartTimeMs` when known) call `handleAdoptedProcessExit(serviceID, exitCode: 0)` and stop monitoring. The exit code of a non-child is unobservable, so it is always `0`.
5. `handleAdoptedProcessExit`: cancel the monitor; `intentional = intentionallyStopping.remove(serviceID)`; drop the record; apply the exit decision (3.10.6) with `exitCode` as given and `intentional`.

Queries: `isRunning` = adopted pid alive, or managed child running; `snapshot` = `{pid, pgid, startedAt}` (adopted `pgid` = `pid`, the actual `getpgid` in the daemon); `serviceID(forPID)` / `serviceName(forPID)` match **only the root pid** of a managed or adopted process (descendants do not match; used by 3.13); `runningStates`, `activeRunningServiceIDs` = ids whose managed child is running or adopted pid alive.

#### 3.10.4 Stop escalation (`ProcessRegistry.stop:257-323`)

Common: `intentionallyStopping.insert(serviceID)`; update the row `intentionalStop=1` (3.11.1).

**Managed process.** `subtree = subtree(rootPid)`; `signal(s)` = send `s` to the process group `-pgid` **and** to every subtree pid deepest-first. `settled()` = child reaped **and** `!anyAlive(subtree)`.

| Step | Action | Wait |
|------|--------|------|
| 1 | `signal(SIGINT)` | poll `settled()` up to **15** times, **100 ms** apart (check, sleep; 1.5 s) |
| 2 | if not settled: `signal(SIGTERM)` | poll up to **10** times, 100 ms apart (1.0 s) |
| 3 | if not settled: `signal(SIGKILL)` | sleep **100 ms** |
| 4 | if the entry is still registered: `exitCode = child still running ? 9 : child exit status`; `handleProcessTerminated(serviceID, exitCode)` | |

Worst case 2.6 s. Log lines (info/warn/error) are daemon logs, not activity lines.

**Adopted process.** `subtree(pid)`; `send(SIGINT, subtree)` deepest first; poll up to **15** x **100 ms** until `!alive(pid) && !anyAlive(subtree)`; if still alive: `send(SIGTERM)`, sleep **300 ms**; if still alive: `send(SIGKILL)` (no wait after); then `handleAdoptedProcessExit(serviceID, exitCode: 15)` (the code is `SIGTERM`'s number, whatever the real outcome). Worst case 1.8 s.

DEV-78(b): never signal pid `<= 1`, the daemon's own pid or pgid; before signalling any pid that the daemon did **not** spawn in this process (adopted external, orphan-adopted, `kill_existing` occupants) verify the owner uid equals the daemon uid.

#### 3.10.5 `intentionalStop`

`intentionallyStopping` is a set of service ids. It is inserted at the start of 3.10.4, consumed (removed) exactly once by the exit decision of that run (3.10.6), and mirrored to the row column `intentionalStop` so that a daemon restart during a stop completes the stop at adoption (3.11.3). A fresh launch/adoption clears it.

#### 3.10.6 Exit decision table (`handleManagedProcessExit`, `ExecutionSupervisor.swift:163-222`)

Input: `serviceID, serviceName, exitCode, intentionalStop`. Steps in order:

| # | Condition | Actions | Result |
|---|-----------|---------|--------|
| 1 | always | `failureTail = (!intentionalStop && exitCode != 0) ? spoolTail(serviceID) : null`; remove the spool file; clear `resolvedTarget`; delete the askpass dir (SSH, DEV-35) | |
| 2 | `intentionalStop` | emit `Stopped (exit <exitCode>).`; cancel reconnect; record `stopped` (`exitCode`, `lastFailure` null, `startedAt` kept until T9); `end_capture` | T14 |
| 3 | provider reconnect-eligible (3.12 `handleUnexpectedExit` returns true) | start the reconnect loop; **no** exit line, no crash notification; the row is kept with `reconnectAttempt` (3.11.1) | T11 |
| 4 | `exitCode == 0` | emit `Stopped (exit 0).`; record `stopped`; `end_capture` | T12 |
| 5 | otherwise | emit the crash batch (3.17: `Crashed (exit <n>).` then each non-empty line of `failureTail`); `finalizeManagedProcessCrash(exitCode, failure: failureTail, notify: true)` (T13: `crashed`, `exitCode = exitCode == 0 ? 1 : exitCode`, `lastFailure = failureTail`, `notify` per 3.16); `end_capture` | T13 |

Step 3 applies **to every non-intentional exit including exit code 0**. The exit is ignored (no record change) when the process table no longer holds the entry (already handled by a forced stop, 3.7 step 8) or when `runId` is stale (G2).

#### 3.10.7 Spool tail (`RunSpool.tail:43-51`)

`spoolTail(serviceID)`: file missing or empty -> `null`. Else read the **last 4096 bytes**, decode as UTF-8 **lossily** (DEV-70: 1.x returned an empty string when the 4096-byte cut split a multi-byte character, producing an empty non-null `lastFailure`), split on `\n` **keeping empty subsequences**, take the **last 8** elements, join with `\n`, trim whitespace/newlines. A final empty result is treated as `null` (DEV-70). Consequence kept from 1.x: a file ending in `\n` counts the trailing empty element, so at most 7 real lines survive. The tail is then redacted with `strict` before it is stored as `lastFailure` or sent anywhere ([02](02-security-and-secrets.md) 3.12.2).

DEV-70 (spool cap): 1.x defined `maxSpoolBytes = 8 MiB` and truncated to the newest 4 MiB, but only at **open** time (`truncateIfNeeded` runs in `openAppendFD`), where the file almost never exists, so the cap was inert and a long-running chatty process could fill the disk. The daemon keeps the open-time rule and adds a maintenance tick every **5 s** per live spool: if `size > SPOOL_MAX_BYTES (8 MiB)` it keeps the newest `SPOOL_KEEP_BYTES (4 MiB)` starting at a line boundary: read the tail, open a second descriptor without `O_APPEND`, `ftruncate(0)`, write the tail at offset 0 (the child keeps appending through its `O_APPEND` descriptor; a few bytes written between read and truncate can be lost: documented ceiling, `ponytail:` upgrade path = rotating pair of files). Consumers of the spool ([08](08-logs-and-events.md)) MUST re-seek to 0 when `size < lastOffset`.

#### 3.10.8 Process queries used by runners

`serviceID(forPID)`, `serviceName(forPID)` (3.13), `isRunning` (3.2), `getSnapshot` (3.10.3). `ProcessRegistry.activeRunningServiceIDs` (static cached copy for the AppDelegate, `:12-27`) is `[CLIENT]`-era plumbing: the daemon computes the active set on demand (3.15.2).

#### 3.10.9 Shutdown primitives and `terminateAll` (DEV-08, DEV-73)

1.x `terminateAll` (`:401-431`): `SIGTERM` to each managed **group**, up to 2 x 100 ms wait, `SIGKILL` stragglers, `SIGTERM` (pid only) to adopted pids, forget everything, **no** supervisor update, **no** compose `down`; `ExecutionSupervisor.stopAll` (`:305-316`) stopped every record sequentially through `performStop` (no compose `down`, because it bypassed the runners) and then called `terminateAll`. DEV-08 replaces the SIGTERM-only path with full escalation on the process tree; DEV-73 defines the two daemon primitives (the RPC that triggers them is `daemon.shutdown`, [14](14-lifecycle-and-platform.md)):

1. **`stop_all_services(compose_down: bool)`** - used by `daemon.shutdown {stopServices:true}` and by factory reset ([09](09-dataport.md)). Algorithm: cancel every reconnect task; collect all services with a record in `starting|running|reconnecting|stopping`, a live process-table entry, or a persisted `runtime_process` row; run the **stop pipeline of 3.7 for all of them concurrently** (each with its own 90 s bound and the escalation of 3.10.4, so processes take at most 2.6 s each); wall-clock bound for the whole call `SHUTDOWN_STOP_BOUND = 60 s` (`compose down` is 45 s per stack, run in parallel); after the bound the remaining services are force-released (3.7 step 8, bounded 20 s total). Returns when every row is deleted. When `compose_down = false` (callers that want containers to survive) compose stacks are only unregistered (their rows deleted, containers left running).
2. **`detach_all()`** - used by `daemon.shutdown {stopServices:false}` and normal daemon exit: stop all loops (pollers, compose poll, reconnect, adopted monitors), flush the debounced publication, remove askpass directories, **leave every child process running** and **keep every `runtime_process` row and spool file** so the next boot adopts them (3.11). Children are in their own process groups and write to spool files (not pipes), so the daemon's exit sends them no signal and cannot cause `SIGPIPE`.
3. **Crash of the daemon** (SIGKILL, power loss): children survive for the same reason; rows persist; the next boot adopts them.

---

### 3.11 Persistence and orphan adoption (DEV-10, ADD-03)

1.x kept all runtime state in memory (`ExecutionSupervisor.records`, `ProcessRegistry` entries, runner-local compose contexts) and called `ProcessRegistry.terminateAll` on app quit (`AppDelegate.swift:120-121`), so nothing survived a restart. DEV-10 persists every active run to `daemon-state.sqlite` `runtime_process` ([01](01-data-model.md) 3.10) and re-attaches at daemon boot; ADD-03 exposes the last pass through `runtime.adopt_report`.

#### 3.11.1 Row lifecycle (writes and deletes)

| Event | Row effects |
|-------|-------------|
| Handle registered (T5), managed spawn, external adoption, compose stack up, poller registered | **UPSERT** full row: `mode`, `pid`/`pgid`/`pidStartTimeMs`/`executable`/`argvJSON` (managed only), `composeContextJSON` or `pollerJSON`, `startedAt`, `adopted=0` unless adoption, `intentionalStop=0`, `reconnectAttempt=null`, `lastFailure=null`, `updatedAt=now` |
| Stop pipeline step 1 begins | `intentionalStop=1`, `updatedAt` |
| Reconnect state (T11, T15) | `reconnectAttempt`, `pid=null`, clear failure fields |
| Managed crash / reconnect exhausted | `lastFailure` set when the supervisor stores failure text (redacted per [02](02-security-and-secrets.md)); row **kept** until stop completes |
| Stop pipeline step 7 success | **DELETE** row |
| `detach_all` (3.10.9) | row **kept** unchanged (children left running) |
| Factory reset ([09](09-dataport.md)) | all rows deleted |
| Service deleted (DEV-14) after stop | row deleted with stop |

`argvJSON` stores the argv actually passed to `exec` (secrets redacted per [02](02-security-and-secrets.md) ADD-33 before persist). `composeContextJSON` is the wire form of `ComposeStackContext` plus `ephemeralDir` (absolute path, DEV-75) when `isEphemeralComposeFile`. `pollerJSON`:

| Field | Type | When |
|-------|------|------|
| `kind` | `"health"` \| `"process"` | always |
| `url` | string | `health` |
| `processName` | string | `process` |
| `intervalSeconds` | int | always |
| `serviceName` | string | always (display at adoption) |

#### 3.11.2 Boot adoption pass

Runs once per daemon start after `kuma.sqlite` is opened and settings imported, **before** auto-resume (3.15) and before accepting RPC that starts services. For each `runtime_process` row in arbitrary order:

1. Load the service from `kuma.sqlite`. Missing service → delete row, spool/askpass/compose ephemeral dir best-effort removed; report `outcome:"removed", reason:"service_deleted"`.
2. **`intentionalStop == 1`** → run the stop pipeline (3.7) to finish an in-flight user stop that was interrupted by daemon exit; report `outcome:"stopped"`.
3. **`mode == managedProcess`** with non-null `pid`:
   - Verify `pid > 1`, same `pidStartTimeMs` as OS when recorded, process alive, uid equals daemon uid (DEV-78(b)).
   - Success → `adoptExternalProcess` or re-register managed child per whether `adopted==1`; restore supervisor record `running`, `runId += 1`; if `reconnectAttempt` was non-null, enter `reconnecting` with that attempt and resume the reconnect loop (3.12); report `outcome:"adopted"`.
   - Failure (dead pid, reuse, wrong user) → delete row and report `outcome:"removed", reason:"pid_stale"`; do **not** kill unrelated processes.
4. **`mode == composeStack`** → parse `composeContextJSON`; if `composeHasRunningContainers` (3.9.3.5 step 4, single `ps` attempt) → register stack + supervisor + poll set; else delete row, report `outcome:"removed", reason:"compose_not_running"`.
5. **`mode == poller`** → parse `pollerJSON`; re-register poller job and supervisor handle `running`; report `outcome:"adopted"`.

Spool files at `<runtime dir>/spool/<SERVICEID>.out` are reused when present (DEV-12: boot purge MUST NOT delete spool for any `serviceID` still listed in `runtime_process`).

The pass stores the structured result in memory for `runtime.adopt_report` (no RPC side effect).

#### 3.11.3 `runtime.adopt_report` (ADD-03)

Params: none. Result:

| Field | Type | Notes |
|-------|------|-------|
| `completedAt` | timestamp | end of the last boot pass |
| `entries` | array | one element per row touched |

Entry: `{ serviceID, serviceName, mode, outcome, reason? }` where `outcome` is `adopted` \| `stopped` \| `removed` \| `failed`; `reason` is `service_deleted` \| `pid_stale` \| `compose_not_running` \| `parse_error` \| null.

---

### 3.12 Auto-reconnect

Eligibility: §3.2 (`provider.autoReconnect == true` and type `kubernetes`, `ssh`, or `shell`). On unexpected managed exit (3.10.6 step 3), `AutoReconnectCoordinator` runs (`AutoReconnectCoordinator.swift:47-128`, `AutoReconnectPolicy.swift:4-14`).

**Policy**

| Attempt `n` (1-based) | Backoff before start try | Published state |
|----------------------|---------------------------|-----------------|
| 1 | **2 s** | `reconnecting`, `reconnectAttempt=1`, `reconnectMax=3` |
| 2 | **5 s** | `reconnecting`, attempt `2` |
| 3 | **10 s** | `reconnecting`, attempt `3` |
| 4 (loop exit) | — | T18 `crashed`, `lastFailure="Auto reconnect failed after 3 attempts"` |

Activity: before each attempt after backoff, `Reconnecting (attempt <n>/3)…` (`ExecutionSupervisor.swift:241-244`, U+2026 ellipsis). Failed attempt: `Reconnect attempt <n> failed: <errorDescription>` (`AutoReconnectCoordinator.swift:120-123`); state stays `reconnecting` (T17). Success → T16, `resetSession`. Exhausted → activity `Auto reconnect exhausted` then crash batch (3.17) with detail equal to `lastFailure` (`ExecutionSupervisor.swift:248-263`).

Each attempt calls the same start pipeline as manual start with `origin=autoReconnect` (3.6; disabled services fail the gate silently in the loop). User `stop` cancels the task (3.7 step 2); user `start` supersedes (T2). Provider at reconnect time is the service's **current** active provider (`AutoReconnectCoordinator.swift:53-56`).

---

### 3.13 Port conflicts and `ports.check` (ADD-02)

Occupancy: `/usr/sbin/lsof -ti :<port>` (`LocalPortConflictResolver.swift:16-41`); stdout split on newlines; pids `<= 0` and the daemon's own pid excluded; spawn/`lsof` failure → treat as empty (start may still fail at bind time).

**Policy** (`KumaSettingsKey.portConflictPolicy`, default `warn_and_block`, [03](03-settings-and-environment.md)): read at each check.

| Policy | Behavior |
|--------|----------|
| `warn_and_block` | Foreign occupants (pid not owned by `startingServiceID` via `ProcessRegistry.serviceID(forPID:)`) → `notify` kind `portCollision` (3.16), throw `portInUse` with `PortConflictMessaging.blockedStartMessage` |
| `kill_existing` | `SIGTERM` each foreign pid, sleep **200 ms**, proceed (DEV-78(b): uid check on each pid) |

Compose `up` failures use `PortConflictMessaging.isComposePortConflictMessage` (3.13.3): when true and effective policy is `warn_and_block`, throw `portInUse(port: 0, collidingService: "another process", …)` (`ContainerRunner` parity, 3.9.3.5).

#### 3.13.3 Messages (exact)

| Use | Text |
|-----|------|
| Alert title ([CLIENT]) | `Port Conflict Detected` |
| Blocked start (`port > 0`) | `Port <port> is in use by <collidingService>. Cannot start “<startingServiceName>” (policy: Warn & Prevent Start).` |
| Blocked start (compose, `port == 0`) | `A host port is in use by <collidingService>. Cannot start “<startingServiceName>” (policy: Warn & Prevent Start).` |
| Notification body | `Port <port> is already in use by “<collidingService>”.` |
| Colliding label fallback | `PID <pid>` (`LocalPortConflictResolver.swift:89-93`) |

Wire: `service.start` errors of code `KUMA_EXE_PORT_IN_USE` include `details.portConflict: true` for clients.

#### 3.13.4 `ports.check`

Params: `{ port: int (1–65535), excludingServiceID?: UUID }`. Result:

| Field | Type | Notes |
|-------|------|-------|
| `port` | int | echo |
| `occupants` | `{ pid, label }[]` | `label` = registered service name or `PID <pid>` |
| `foreignOccupants` | same shape | after excluding `excludingServiceID` owner |
| `effectivePolicy` | `kill_existing` \| `warn_and_block` | |
| `wouldBlockStart` | bool | true iff policy is `warn_and_block` and `foreignOccupants` non-empty |

Does not mutate processes. Idempotent read.

---

### 3.14 Subprocess helpers and timeouts

**`EphemeralCLI.run`** (`EphemeralCLI.swift:22-112`): short-lived processes only; never `ProcessRegistry`. Modes `merged`, `captureSeparated`, `discard`. On timeout: `terminate`, then `processFailed("Command timed out after <Int(timeout)>s")` → user message `Execution failed: Command timed out after <n>s`.

**Cancellation kill** (start pipeline abort, `SubprocessWait.swift:80-86`): `SIGTERM`, **500 ms**, `SIGKILL`.

| Name | Seconds | 1.x source | Used for |
|------|---------|------------|----------|
| `composeDown` | 45 | `KumaExecutionTimeouts.composeDown` | compose `down`, default-project teardown |
| `composeDownForce` | 15 | force release (3.7 step 8) | |
| `composeUp` | 120 | `ContainerRunner.swift:283-289` | `compose up`, inline compose timeout message |
| `initialScript` | 120 | `KumaExecutionTimeouts.initialScript` | pre-`up` script |
| `composePs` | 20 | `ComposeStackRuntime.swift:16` | `ps -q --status running` |
| `implicitPsTeardown` | 15 | `ContainerRunner.swift:168-190` | implicit `ps` before default down |
| `kubectlSubcommand` | 30 | `KumaExecutionTimeouts.kubectlSubcommand` | kubectl helpers, **`/bin/ps` batch for monitor** (1.x reused this constant, `ExecutionSupervisor.swift:522-526`) |
| `serviceStopTotal` | 90 | `ServiceStopSupport.swift:6-8` | entire stop pipeline |
| `healthProbe` | 5 | DEV-06 | HTTP health GET |
| `stopEscalationManaged` | 2.6 | §3.10.4 | SIGINT/TERM/KILL polls |
| `stopEscalationAdopted` | 1.8 | §3.10.4 | adopted stop |
| `killExistingGrace` | 0.2 | `LocalPortConflictResolver.swift:62` | after SIGTERM occupants |
| `cancelSubprocess` | 0.5 | `SubprocessWait.swift:83` | ephemeral cancel |
| `restartDelay` | 0.3 | §3.8 | between stop and start |
| `bulkStagger` | 0.15 | §3.8 | between bulk starts |
| `autoResumeStagger` | 0.15 | `+WorkspaceLoad.swift:75` | between auto-resume starts |
| `composeVerifyRetry` | 0.2 × 4 | §3.9.3.5 | sleep between `ps` attempts |
| `publicationDebounce` | 0.1 | `ExecutionSupervisor.swift:332-342` | state event coalescing |
| `publicationMaxWait` | 0.5 | DEV-74 | debounce ceiling |
| `composePollInterval` | 5 | §3.9.3.8 | compose stack poll |
| `pollerTick` | 1 | §3.9.6–3.9.7 | health/monitor scheduler |
| `adoptedMonitorInterval` | 1 | §3.10.3 | external pid liveness |
| `spoolMaintainInterval` | 5 | DEV-70 | spool size maintenance |
| `SHUTDOWN_STOP_BOUND` | 60 | §3.10.9 | parallel stop_all_services wall |
| `forceReleaseCompose` | 20 | §3.10.9 | post-bound force slice |

---

### 3.15 Auto-resume and active-ID snapshot

**Setting**: effective `kuma.settings.autoResumeServices` ([03](03-settings-and-environment.md) 3.3.4, default `false`).

**Snapshot key** `kuma.settings.activeServiceIDsBeforeQuit` ([03](03-settings-and-environment.md) 3.3.4 item 4): UPPERCASE UUID strings.

**Writer (DEV-72)**. 1.x wrote the snapshot only from `AppDelegate` quit paths using `ProcessRegistry.activeRunningServiceIDs` when non-empty else client `activeServiceIDs` (`AppDelegate.swift:41-43,135-137`). The daemon writes the same key on every **`detach_all`** and on graceful shutdown **before** stopping children: the set of service ids where `isOperational(serviceID)` is true, serialized UPPERCASE. Empty set writes `[]` (1.x overwrote with empty array).

**Consumer (auto-resume)**. Once per daemon start, after adoption (3.11), if auto-resume is effective:

1. Read the string array; parse UUIDs (ignore invalid entries per INV-D-SET-15).
2. For each id in stored order: load service; skip if missing, `isDisabled`, or `isOperational`; else run start pipeline with `origin=autoResume` (failures apply T6 except bulk-like continue).
3. Sleep **150 ms** between starts (`autoResumeStagger`; omit after last).
4. Rewrite the setting to `remaining = savedUUIDs − { ids that were candidates and attempted in step 2 }` (`+WorkspaceLoad.swift:58-59` parity).

**DEV-72 scope**: 1.x ran step 2 only on the **first workspace load** of the UI session and only for snapshots intersecting that workspace's deck (`+WorkspaceLoad.swift:39-55`). The daemon runs step 2 **once at boot** for every saved id cluster-wide (ids in other workspaces are started too if still enabled). Remaining-id trimming is unchanged.

---

### 3.16 Notifications and `lastFailure`

#### 3.16.1 Daemon `notify` events ([00](00-overview-and-conventions.md) 5.7)

Clients map these to OS notifications ([CLIENT] permission UI). Payload: `{ kind, serviceID, serviceName, … }`.

| kind | When | Extra fields | 1.x UI text (for parity) |
|------|------|--------------|-------------------------|
| `serviceCrash` | T13, T18; `notify:true`; effective `notifyOnServiceFailure` (legacy fallback `notifyOnCrash`, `ExecutionSupervisor.swift:284-296`) | `reason` string or null | Title `Service Crashed`; body `“<name>” stopped unexpectedly: <reason>` or `“<name>” has terminated unexpectedly.` |
| `healthCheckFailed` | DEV-13: health poller transition to `crashed` from `running`/absent logged state | `targetUrl` | Title `Health Check Failed`; body `“<name>” at <url> is not responding.` |
| `portCollision` | `warn_and_block` port check before throw | `port`, `collidingService` | Title `Port Conflict Detected`; body `Port <port> is already in use by “<colliding>”.` |

Compose T19 and monitor `stopped` emit **no** `notify`. Intentional stop emits none.

#### 3.16.2 `lastFailure` on wire (`service.status`, `service.state_changed`)

Stored redacted (`strict`). Cleared on every transition to `stopped`, `starting`, or `running` (§3.4.2). Non-null only while `crashed` (and transiently during start failure before T6 settles).

| Source | Exact `lastFailure` value |
|--------|---------------------------|
| Start pipeline T6 | `errorDescription` of the thrown error (§3.9.8, including `Start failed:` prefix **not** included — only the description part) |
| Managed crash T13 | Spool tail after §3.10.7 processing, or null if tail empty |
| Reconnect exhausted T18 | `Auto reconnect failed after 3 attempts` (`ExecutionSupervisor.swift:253`, `AutoReconnectPolicy.maxAttempts == 3`) |
| Compose poll T19 | `Compose stack no longer has running containers` |
| Health poller T20 | `Health check failed` |
| Process monitor | always null |
| `noActiveProvider` / config errors | same string as thrown |

---

### 3.17 Activity log line templates

Lines go through the activity-log sink ([08](08-logs-and-events.md)) unless marked **raw**. Placeholders: `<name>` service name; `<type>` provider raw value; `<pid>` decimal; `<n>` attempt or exit code; `<description>` error text; `<projectName>` compose project; ellipses are U+2026.

| Template | When |
|----------|------|
| `Starting "<name>" (<type>)` | start step 6 (`ServiceExecutionEngine.swift:85-87`) |
| `Start failed: <description>` | start failure (`:96`) |
| `Start cancelled.` | cancelled start (§3.5) |
| `Stopping service…` | stop step 4 (`ExecutionSupervisor.swift:319`) |
| `Process running (PID <pid>)` | managed spawn or adoption (`ProcessRegistry.swift:163,205`) |
| `Stopped (exit <code>).` | intentional stop exit (`ExecutionSupervisor.swift:174`) |
| `Stopped (exit 0).` | clean unexpected exit (`:198`) |
| `Crashed (exit <code>).` | crash batch first line (`:510`) |
| `<non-empty lines of failure tail>` | crash batch following lines (`:512-514`) |
| `Launching shell command…` | shell, no cwd (`ShellRunner.swift:43`) |
| `Launching shell command (cwd: <path>)…` | shell with cwd (`:38-40`) |
| `Resolved target: <name>` | kubernetes step 5 (`KubernetesRunner.swift:43`) |
| `Adopted existing port-forward (PID <pid>)` | k8s adoption (`:60`) |
| `Launching kubectl port-forward…` | k8s launch (`:80`) |
| `Adopted running compose stack (project <projectName>)` | compose adoption (`ContainerRunner.swift:44-46`) |
| `Running compose up -d (project <projectName>)` | compose up (`:57`) |
| `<compose failure one line>` | compose up error, newlines → space (`:70`) |
| `Compose stack has no running containers` | compose poll (`ExecutionSupervisor.swift:362-363`) |
| `Reconnecting (attempt <n>/3)…` | reconnect attempt (`:241-244`) |
| `Reconnect attempt <n> failed: <description>` | reconnect failure (`AutoReconnectCoordinator.swift:122`) |
| `Auto reconnect exhausted` | reconnect give-up (`ExecutionSupervisor.swift:254`) |
| **raw** `[HEALTH] <url> -> running` or `… -> crashed` | health poller state change (`:474-476`) |
| **raw** `[MONITOR] <name> -> PID <pid>` or `… -> not running` | monitor state change (`:498-500`) |

---

### 3.18 Constants table

| Name | Value | Source |
|------|-------|--------|
| `AutoReconnectPolicy.maxAttempts` | 3 | `AutoReconnectPolicy.swift:4` |
| Reconnect backoff attempt 1 / 2 / default | 2 s / 5 s / 10 s | `AutoReconnectPolicy.swift:10-12` |
| `RunSpool.maxSpoolBytes` | 8 MiB | `RunSpool.swift:5` |
| Spool tail read / line count | 4096 bytes / 8 lines | `RunSpool.swift:43-50`, §3.10.7 |
| Spool file mode (1.x) / daemon | 0644 / **0600** | `RunSpool.swift:27`, DEV-36 |
| `lsof` argv | `-ti :<port>` | `LocalPortConflictResolver.swift:19` |
| Health interval floor | 3 s | §3.9.6 |
| Monitor interval floor | 2 s | §3.9.7 |
| HTTP success status | 200–399 inclusive | `ExecutionSupervisor.swift:452` |
| Compose `down --timeout` | 5 s | §3.9.3.2 |
| Project name prefix | `kuma-` + 32 hex | `ComposeStackContext.swift:52-54` |
| SSH defaults | port 22, alive 15 / max 3 | §3.9.4 |
| Tunnel default engine | `cloudflare` | §3.9.5 |
| `RESTART_DELAY` | 300 ms | §3.8 |
| `BULK_STAGGER` | 150 ms | §3.8 |
| Lane debounce / max | 100 ms / 500 ms | §3.4.4, DEV-74 |
| Grace poll removed | 6 × 50 ms | DEV-74 (was `ServiceExecutionStateSync.swift:11-18`) |

---

### 3.19 Rust harness notes

Port 1.x test seams without running real binaries:

| 1.x type | Role | Rust equivalent |
|----------|------|-----------------|
| `RecordingProcessLaunching` | Captures last launch argv/executable/cwd; fake pid `42424` | `FakeProcessSpawner` recording `LaunchRecord` |
| `RecordingComposeCLI` | Records compose invocations | `FakeComposeRunner` |
| `ProcessLaunching` / `ProcessRegistryLauncher` | Runner → registry spawn | `ProcessSpawner` trait |
| `ProcessTestSupport.resetProcessWorld` | `stopAll` + `terminateAll` between tests | test fixture `reset_execution_world()` |
| `AutoReconnectCoordinator.resetForTests` | cancel sessions | call in same reset |

Integration tests SHOULD use the fakes for TC-D05/D06/D08 patterns (`docs/testing/06-services-test-matrix.md`). Time-based behavior (debounce, reconnect backoff, pollers) MUST use a fake clock hook (monotonic §3.1 rule 5).

---

## 4. Data shapes

### 4.1 `service.start`

Params: `{ serviceID: UUID }`. Result:

| Field | Type | Optional | JSON key | Notes |
|-------|------|----------|----------|-------|
| serviceID | UUID upper | no | `serviceID` | |
| state | ServiceState | no | `state` | live at return |
| pid | int | yes | `pid` | null when none |
| alreadyRunning | bool | no | `alreadyRunning` | §3.6 step 1 |

Errors: §6. `portInUse` includes `details.portConflict: true`.

### 4.2 `service.stop` / `service.restart`

Stop result: `{ serviceID, state: "stopped", forced: bool }`. Restart: start result plus `restarted: true`.

### 4.3 `service.start_all` / `service.stop_all`

Start-all result: `{ results: StartAllEntry[], started, skipped, failed }` where `StartAllEntry` = `{ serviceID, serviceName, outcome: "started"|"skipped"|"failed", state?, reason?, error? }`; `reason` for skipped: `disabled` \| `alreadyOperational`. Stop-all: `{ results: { serviceID, serviceName, outcome: "stopped"|"skipped", forced? }[], stopped, skipped }`.

Filter params: §3.8 (same keys as `service.list` in [04](04-workspaces-groups-services.md)).

### 4.4 `service.status` / `service.statuses`

Params: `{ serviceID }` / `{ serviceIDs?: UUID[] }` (omit = all services with any record or historical mode). Result object: §3.3 wire runtime table (includes `isLoading`, `statusTitle`, `resolvedTarget`).

### 4.5 `ports.check`

§3.13.4.

### 4.6 `runtime.adopt_report`

§3.11.3.

### 4.7 `composeContextJSON` (persisted)

| Field | Type | JSON key |
|-------|------|----------|
| serviceID | UUID upper | `serviceID` |
| binaryPath | string | `binaryPath` |
| composeFilePath | string | `composeFilePath` |
| workingDirectory | string | `workingDirectory` |
| projectName | string | `projectName` |
| isEphemeralComposeFile | bool | `isEphemeralComposeFile` |
| projectBinding | `kumaProject` \| `implicitDefault` | `projectBinding` |
| ephemeralDir | string | `ephemeralDir` | optional; DEV-75 |

### 4.8 `service.state_changed` payload

§3.4.4 (nine fields).

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-EXE-01 | PARITY | Runner routing for eight provider types and three execution modes | `ServiceExecutionEngine.swift:159-169` | `service.start`, `service.stop` |
| FEAT-EXE-02 | PARITY | `ServiceRunner` start/stop/is_running contract | `ServiceRunnerProtocol.swift` | `service.start`, `service.stop` |
| FEAT-EXE-03 | PARITY | Supervisor handles (`managedProcess`, `composeStack`, poller variants) | `ExecutionModels.swift` | `service.start` |
| FEAT-EXE-04 | PARITY | `isOperational` / `hasActiveWorkload` gates | `ExecutionSupervisor.swift:58-78` | `service.start`, `service.start_all` |
| FEAT-EXE-05 | PARITY | Six-state machine and `ServiceExecutionState` titles | `ServiceStateStore`, `ExecutionModels.swift` | `service.status`, events |
| FEAT-EXE-06 | PARITY / DEV-74 | Authoritative state machine with race guards G1–G9 | `ServiceStateNotification.swift`, tests Runtime.D03-D10 | all execution RPC |
| FEAT-EXE-07 | PARITY / DEV-74 | Debounced `service.state_changed` (+500 ms max wait, immediate transitions) | `ExecutionSupervisor.swift:332-342` | `events.subscribe` |
| FEAT-EXE-08 | V2-ADD / DEV-74 | Per-service Lane FIFO (start join, stop wins, restart 300 ms) | `ServiceStopGate.swift` | `service.start`, `service.stop`, `service.restart` |
| FEAT-EXE-09 | PARITY | Start pipeline idempotency, provider pick, activity log begin | `ServiceExecutionEngine.swift:67-99` | `service.start` |
| FEAT-EXE-10 | PARITY / DEV-71 | Server-side disabled gate | UI only in 1.x | `service.start`, `service.restart`, `service.start_all` |
| FEAT-EXE-11 | PARITY | Stop pipeline coalescing, 90 s bound, force release | `ServiceStopSupport.swift`, `ServiceExecutionEngine.forceReleaseService` | `service.stop` |
| FEAT-EXE-12 | PARITY / DEV-74 | Stop uses run's `providerCategory`; compose down after `stopped` publish | `ServiceExecutionEngine.stop` | `service.stop` |
| FEAT-EXE-13 | PARITY | Restart = stop + delay + start | `ServicesDeckViewModel+ExecutionActions.swift:72-86` | `service.restart` |
| FEAT-EXE-14 | PARITY | Bulk start/stop with deck filters and 150 ms stagger | `+ExecutionActions.swift:37-70` | `service.start_all`, `service.stop_all` |
| FEAT-EXE-15 | PARITY / DEV-71 | Disable running service stops workload | `+ServiceActions.swift:44-46` | `service.set_disabled` ([04](04-workspaces-groups-services.md)) |
| FEAT-EXE-16 | PARITY | Provider switch stop/start contract | `+ServiceActions.swift:61-95` | `service.switch_provider` ([04](04-workspaces-groups-services.md)) |
| FEAT-EXE-17 | PARITY | Shell runner | `ShellRunner.swift` | `service.start` |
| FEAT-EXE-18 | PARITY | Kubernetes runner with adoption | `KubernetesRunner.swift` | `service.start` |
| FEAT-EXE-19 | PARITY / DEV-75 | Container compose runner | `ContainerRunner.swift` | `service.start` |
| FEAT-EXE-20 | PARITY | SSH tunnel runner + askpass | `SSHTunnelRunner.swift` | `service.start` |
| FEAT-EXE-21 | PARITY | Tunnel runner (cloudflare/ngrok) | `TunnelRunner.swift` | `service.start` |
| FEAT-EXE-22 | PARITY / DEV-06 | Health-check poller | `HealthCheckRunner.swift`, `ExecutionSupervisor.swift:445-478` | `service.start` |
| FEAT-EXE-23 | PARITY | Process-monitor poller (`stopped` while polling) | `ProcessMonitorRunner.swift` | `service.start` |
| FEAT-EXE-24 | PARITY | `ServiceExecutionError` message set | `ServiceExecutionEngine.swift:5-32` | `service.start` |
| FEAT-EXE-25 | PARITY | Process spawn, spool, process group, reaper | `ProcessRegistry.swift:90-178` | `service.start` |
| FEAT-EXE-26 | PARITY | Stop escalation managed/adopted | `ProcessRegistry.swift:257-323` | `service.stop` |
| FEAT-EXE-27 | PARITY | Process tree termination | `ProcessTreeTerminator.swift` | `service.stop` |
| FEAT-EXE-28 | PARITY | External/adopted pid monitoring | `ProcessRegistry.swift:180-218` | `service.start` |
| FEAT-EXE-29 | PARITY | Spool tail for crash `lastFailure` | `RunSpool.swift:43-51` | `service.status` |
| FEAT-EXE-30 | PARITY / DEV-70 | Spool size cap 8 MiB → keep 4 MiB (+ active maintenance) | `RunSpool.swift:5,53-62` | — |
| FEAT-EXE-31 | PARITY | Auto-reconnect 2/5/10 s, max 3 | `AutoReconnectPolicy.swift`, `AutoReconnectCoordinator.swift` | — |
| FEAT-EXE-32 | PARITY | Port conflict policy + lsof occupancy | `LocalPortConflictResolver.swift` | `service.start` |
| FEAT-EXE-33 | V2-ADD | `ports.check` read-only occupancy | ADD-02 | `ports.check` |
| FEAT-EXE-34 | PARITY | EphemeralCLI timeouts | `EphemeralCLI.swift`, `KumaExecutionTimeouts` | `service.start`, `service.preflight` ([05](05-providers-and-validation.md)) |
| FEAT-EXE-35 | PARITY / DEV-72 | Auto-resume + `activeServiceIDsBeforeQuit` snapshot | `+WorkspaceLoad.swift:39-77`, `AppDelegate.swift:135-141` | `settings.get` ([03](03-settings-and-environment.md)) |
| FEAT-EXE-36 | PARITY | OS notification text parity via `notify` event | `SystemNotificationCenter.swift:60-77` | `events.subscribe` |
| FEAT-EXE-37 | PARITY / DEV-13 | `healthCheckFailed` notify on poll transition | dead code in 1.x | `events.subscribe` |
| FEAT-EXE-38 | PARITY | Compose stack poll crash | `ExecutionSupervisor.swift:346-388` | — |
| FEAT-EXE-39 | PARITY / DEV-08 | Shutdown `stop_all_services` / `detach_all` | `ProcessRegistry.terminateAll`, `ExecutionSupervisor.stopAll` | `daemon.shutdown` ([14](14-lifecycle-and-platform.md)) |
| FEAT-EXE-40 | V2-ADD / DEV-10 | Persist `runtime_process` + boot adoption | ADD-03, brief | `runtime.adopt_report` |
| FEAT-EXE-41 | PARITY | `service.status` / `service.statuses` live read | `ServiceStateStore` | `service.status`, `service.statuses` |
| FEAT-EXE-42 | CLIENT | Start-failure alert / port conflict UI | `ServiceStartFailurePresenter.swift` | - |
| FEAT-EXE-43 | CLIENT | Post-start 6×50 ms grace removed (DEV-74) | `ServiceExecutionStateSync.swift` | - |
| FEAT-EXE-44 | CLIENT | Deck/inspector pills, spinners, haptics | view models | - |
| FEAT-EXE-45 | CLIENT | macOS notification permission | `SystemNotificationCenter.requestAuthorization` | - |
| FEAT-EXE-46 | PARITY | `resolvedTarget` on kubernetes wire | `KubernetesRunner.swift`, supervisor | `service.status` |
| FEAT-EXE-47 | PARITY | Activity log line templates | §3.17 sources | `service.log_line` ([08](08-logs-and-events.md)) |
| FEAT-EXE-48 | PARITY | `notifyOnServiceFailure` gating | `ExecutionSupervisor.swift:284-289` | `settings.get` |

---

## 6. Error catalog

| Code | Condition | Message (exact when fixed) |
|------|-----------|----------------------------|
| `KUMA_EXE_SERVICE_NOT_FOUND` | unknown `serviceID` | `Service '<UUID>' was not found.` |
| `KUMA_EXE_NO_ACTIVE_PROVIDER` | no provider row | `No active runner provider is configured for this service.` |
| `KUMA_EXE_INVALID_CONFIG` | `invalidConfiguration` | `Invalid configuration: <m>` |
| `KUMA_EXE_BINARY_NOT_FOUND` | resolver miss | `Required binary '<n>' could not be located on this Mac.` |
| `KUMA_EXE_PROCESS_FAILED` | `processFailed` | `Execution failed: <r>` |
| `KUMA_EXE_PORT_IN_USE` | `portInUse` | §3.13.3 blocked message |
| `KUMA_EXE_SERVICE_DISABLED` | DEV-71 disabled start | `Service is disabled.` |
| `KUMA_EXE_START_CANCELLED` | Lane cancelled start/restart | `Start was cancelled because the service is stopping.` |

Generic RPC errors (`KUMA_CONFLICT_STALE`, invalid UUID) per [10](10-rpc-protocol.md).

---

## 7. Deviations

| ID | Summary |
|----|---------|
| DEV-70 | Spool tail uses lossy UTF-8; empty tail → null `lastFailure`; active 8 MiB→4 MiB spool maintenance |
| DEV-71 | Disabled services rejected at `service.start` / reconnect / auto-resume; disabling stops running workload |
| DEV-72 | Snapshot `activeServiceIDsBeforeQuit` on daemon detach; auto-resume at boot for all saved ids (not first workspace only) |
| DEV-73 | `stop_all_services` / `detach_all` replace `terminateAll` + `stopAll` (§3.10.9) |
| DEV-74 | Lane ordering; publication 500 ms max; no post-start grace poll; stop publish after compose down; stop uses stored provider category |
| DEV-75 | Ephemeral compose YAML under `<runtime>/compose/<SERVICEID>/` only |
| DEV-76 | Health probes concurrent; monitor `ps` only when due; lowest pid match excluding daemon/ps child |
| DEV-77 | Keep `… on this Mac.` wording on non-macOS hosts |
| DEV-78 | Process group before exec; dynamic pid buffer; stdin null; spawn error shape; pid reuse guard; k8s adoption alive check; SSH destination validation; uid check before signalling foreign pids |
| DEV-79 | Inject resolved PATH on all managed launches |
| (existing) DEV-10 | Persist and adopt `runtime_process` (§3.11) |
| (existing) DEV-06 | Health probe 5 s timeout (§3.9.6) |
| (existing) DEV-08 | Full stop escalation on shutdown (§3.10.9) |
| (existing) DEV-12 | Spool under runtime dir; boot purge preserves adopted spools |
| (existing) DEV-13 | Emit `healthCheckFailed` notify (§3.16) |
| (existing) DEV-14 | `service.delete` stops first ([04](04-workspaces-groups-services.md)) |
| (existing) ADD-02 | `ports.check` (§3.13.4) |
| (existing) ADD-03 | Adoption report RPC (§3.11.3) |

---

## 8. Invariants

| ID | Statement |
|----|-----------|
| INV-D-EXE-01 | At most one `runtime_process` row per `serviceID`. |
| INV-D-EXE-02 | When state is `crashed`, `exitCode` is non-null and never `0`. |
| INV-D-EXE-03 | When state is not `reconnecting`, `reconnectAttempt` and `reconnectMax` are null on the wire. |
| INV-D-EXE-04 | `lastFailure` is non-null only while state is `crashed` (except transient internal start failure before T6 completes). |
| INV-D-EXE-05 | G1: `running` retains last known `pid` on updates that omit pid. |
| INV-D-EXE-06 | G2: stale `runId` updates are dropped. |
| INV-D-EXE-07 | G4: no `stopping` publish from `stopped`/`crashed`/absent record. |
| INV-D-EXE-08 | G5: no `running` publish while `stopping`. |
| INV-D-EXE-09 | G7: identical public tuples emit at most one consecutive `service.state_changed`. |
| INV-D-EXE-10 | G8–G9: background polls never clobber in-flight `starting`/`stopping`. |
| INV-D-EXE-11 | Stop pipeline always ends with `stopped` and deleted `runtime_process` row unless `detach_all`. |
| INV-D-EXE-12 | Auto-reconnect attempts ≤ 3 per unexpected exit session. |
| INV-D-EXE-13 | `ports.check` never sends signals. |
| INV-D-EXE-14 | Persisted `argvJSON` / `lastFailure` never contain raw secrets ([02](02-security-and-secrets.md)). |
| INV-D-EXE-15 | `service.stop` is infallible on the wire (always returns stopped). |

---

## 9. Acceptance tests

| ID | Arrange → Assert |
|----|------------------|
| DT-EXE-01 | Start shell echo → `running`, spool created, activity `Starting…` then `Process running`; stop → `stopped`, row deleted |
| DT-EXE-02 | Start while `running` → `alreadyRunning:true`, no duplicate process |
| DT-EXE-03 | Disabled service start → `KUMA_EXE_SERVICE_DISABLED`, state unchanged |
| DT-EXE-04 | No provider → `KUMA_EXE_NO_ACTIVE_PROVIDER`, T6 `crashed` with message as `lastFailure` |
| DT-EXE-05 | Port held by foreign pid, `warn_and_block` → `KUMA_EXE_PORT_IN_USE`, `details.portConflict`, `notify` portCollision |
| DT-EXE-06 | `kill_existing` policy → foreign pid terminated, start succeeds |
| DT-EXE-07 | G1: poller sets `running` without pid after managed run → wire pid unchanged |
| DT-EXE-08 | G2: exit hook with old `runId` after new start → ignored |
| DT-EXE-09 | G4: stop when already `stopped` → no `stopping` event |
| DT-EXE-10 | G7: duplicate identical state change → one event |
| DT-EXE-11 | Reconnect: kill managed shell with autoReconnect → `reconnecting` 1/3, backoffs 2/5/10 s (fake clock), success on attempt 2 → `running` |
| DT-EXE-12 | Reconnect exhausted → `crashed`, `lastFailure` exact `Auto reconnect failed after 3 attempts`, lines `Auto reconnect exhausted` + `Crashed (exit …).` |
| DT-EXE-13 | Health poller: server returns 500 → `crashed`, `lastFailure` `Health check failed`, `[HEALTH] … -> crashed`, one `healthCheckFailed` notify |
| DT-EXE-14 | Compose poll empty `ps` → T19 message, no notify |
| DT-EXE-15 | `detach_all` leaves row + child alive; next boot adoption → `running`, `runtime.adopt_report` entry `adopted` |
| DT-EXE-16 | `intentionalStop` row at boot → stop pipeline completes, row deleted |
| DT-EXE-17 | Auto-resume: save two ids, boot with setting true → both start attempts, remaining key trimmed; disabled id skipped |
| DT-EXE-18 | `ports.check` with occupant → labels and `wouldBlockStart` match policy |
| DT-EXE-19 | Bulk start 3 services → order preserved, 150 ms gaps, failures don't abort loop |
| DT-EXE-20 | Provider switch while running → old runner stopped, new provider started |
| DT-EXE-21 | Spool tail: file with invalid UTF-8 at 4096 boundary → `lastFailure` null or text, never empty string sent as non-null (DEV-70) |
| DT-EXE-22 | Lane: concurrent start+stop → final `stopped`, cancelled start `KUMA_EXE_START_CANCELLED` |

---

## Open questions / residual risks

- **R1** `kill_existing` vs root-owned occupants: uid check may skip pids the user expected killed; start may still fail at bind.
- **R2** Spool truncate during active append may lose a few bytes (§3.10.7 `ponytail:` note).
- **R3** Auto-resume at boot for ids whose workspace was deleted on another machine may attempt start and fail (trimming behavior matches 1.x remaining-key logic).
- **R4** Linux `lsof` path may differ from `/usr/sbin/lsof`; daemon packaging must ship or configure the same argv semantics.
