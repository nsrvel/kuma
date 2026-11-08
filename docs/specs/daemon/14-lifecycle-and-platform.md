# Daemon Spec 14: Lifecycle and Platform

> **Status:** Draft for implementation  
> **Area code:** `LIF`  
> **Audience:** Engineers implementing daemon startup/shutdown, macOS integration, and V2 client lifecycle. Read [00](00-overview-and-conventions.md) first.  
> **RPC methods owned:** `daemon.ping`, `daemon.status`, `daemon.shutdown`  
> **Events produced:** `daemon.shutting_down`, `notify` (payload contract for client delivery)  
> **Cross-references:** [01](01-data-model.md) (paths, `meta.instanceId`), [03](03-settings-and-environment.md) (quit/auto-resume settings), [06](06-execution-engine.md) (shutdown primitives 3.10.9, adoption 3.11, spool DEV-12), [02](02-security-and-secrets.md) (runtime permissions 3.13), [09](09-dataport.md) (factory reset stop), [10](10-rpc-protocol.md) (wire schemas), [07-kuma-daemon.md](../07-kuma-daemon.md) (process model).

---

## 1. Purpose and scope

This spec defines how the Rust daemon **starts**, **runs**, and **stops**; how it enforces **one instance per user**; how **`daemon.ping` / `daemon.status` / `daemon.shutdown`** behave; how **LaunchAgent** install/uninstall works; how **1.x app lifecycle** maps to daemon versus **client** responsibilities in V2; how **`notify`** events replace direct `UNUserNotificationCenter` calls from the execution engine; and how **`kuma`** is **packaged, signed, and released** alongside `Kuma.app`.

In scope: every behavior in `AppDelegate.swift`, `KumaApp.swift`, `SingleInstanceGuard.swift`, `AppCoordinator.swift`, `SystemNotificationCenter.swift`, `RunSpool.purgeAll`, quit-related settings consumption, `daemon/kuma` CLI lifecycle subcommands, `Kuma.entitlements`, `Scripts/*.sh`, `.github/workflows/*` as they affect the daemon binary, and scaffold code in `daemon/crates/kuma-daemon/src/lib.rs` and `daemon/crates/kuma-protocol/src/paths.rs`.

Out of scope: runner algorithms ([06](06-execution-engine.md)), settings registry details ([03](03-settings-and-environment.md)), RPC framing ([10](10-rpc-protocol.md)), SwiftUI chrome ([00 §6](00-overview-and-conventions.md)).

Tags: **[PARITY]** (1.x behavior reproduced or explicitly delegated), **[V2-ADD]**, **[CLIENT]**.

---

## 2. 1.x source of truth

All paths relative to repo root unless noted.

| Area | Files (read in full or cited sections) |
|------|----------------------------------------|
| App entry & scenes | `Kuma/KumaApp.swift:4-50` |
| Quit & notifications delegate | `Kuma/App/AppDelegate.swift:6-143` |
| Single instance | `Kuma/Core/Lifecycle/SingleInstanceGuard.swift:6-54` |
| Onboarding phase | `Kuma/Core/Lifecycle/AppCoordinator.swift:5-47`, `Kuma/ContentView.swift:89-93` |
| System notifications | `Kuma/Core/Notifications/SystemNotificationCenter.swift:5-95` |
| Teardown & registry | `Kuma/Core/Execution/Supervision/ExecutionSupervisor.swift:305-316`, `Kuma/Core/Execution/ProcessRegistry.swift:12-27,401-435` |
| Spool purge at launch | `Kuma/Core/Execution/Supervision/RunSpool.swift:7-41` |
| Auto-resume after quit | `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+WorkspaceLoad.swift:39-77` |
| Notification emitters | `ExecutionSupervisor.swift:283-296`, `LocalPortConflictResolver.swift:44-75` |
| Settings keys | `Kuma/Domain/Models/KumaSettingsKey.swift:7-14` |
| Launch at login (app) | `Kuma/Presentation/Features/Settings/ViewModels/SettingsViewModel.swift:58-62,192-202` |
| Entitlements | `Kuma/Kuma.entitlements:1-12` |
| Release scripts | `Scripts/make-dmg.sh`, `Scripts/mac-sign-app.sh`, `Scripts/import-codesign-cert.sh`, `Scripts/mac-notarize-dmg.sh` |
| CI | `.github/workflows/daemon-ci.yml`, `.github/workflows/release.yml`, `.github/workflows/ci.yml` |
| Daemon scaffold | `daemon/kuma/src/main.rs`, `daemon/crates/kuma-daemon/src/lib.rs`, `daemon/crates/kuma-protocol/src/paths.rs`, `daemon/crates/kuma-protocol/src/lib.rs:8` |
| Docs | `docs/specs/00-app.md`, `docs/specs/07-kuma-daemon.md`, `docs/specs/daemon/06-execution-engine.md` §3.10.9 |
| Tests | `KumaTests/Features/App/SingleInstanceGuardTests.swift`, `AppCoordinatorTests.swift`, `LifecycleTeardownTests.swift`, `AppThemeAndNotificationTests.swift` |

**Project constants (verified in source)**

| Name | Value | Source |
|------|-------|--------|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.kuma.Kuma` | `Kuma.xcodeproj/project.pbxproj` (cited in [03](03-settings-and-environment.md)) |
| Logger subsystem (not bundle id) | `lokastudio.kuma` | `AppDelegate.swift:8`, `SingleInstanceGuard.swift:6` |
| Default main window size | 1100 × 750 | `KumaApp.swift:32` |
| Onboarding window title | `Welcome to Kuma` | `KumaApp.swift:41` |
| Quit dialog title | `Processes are still running` | `AppDelegate.swift:72` |
| Quit dialog body template | `<n> service(s) are currently running. Stop everything before quitting, or quit anyway?` | `AppDelegate.swift:73` |
| Quit dialog buttons (order) | `Stop All & Quit`, `Quit Anyway`, `Cancel` | `AppDelegate.swift:75-77` |
| Suppression checkbox | `Remember this choice` | `AppDelegate.swift:79` |
| `QuitBehavior` raw values | `ask`, `stopAll`, `quitAnyway` | `AppDelegate.swift:10-13` |
| Teardown watchdog | `0.3` s then `exit(0)` | `AppDelegate.swift:111-113` |
| `terminateAll` grace | 2 × 100 ms (`usleep(100_000)`) | `ProcessRegistry.swift:408-413` |
| 1.x spool directory | `$TMPDIR/kuma-run/` | `RunSpool.swift:8-9` |
| Spool file name | `<UUID>.out` (UUID = `uuidString`, uppercase) | `RunSpool.swift:14-15` |
| Auto-resume stagger | 150 ms between starts | `ServicesDeckViewModel+WorkspaceLoad.swift:75` |
| `PROTOCOL_VERSION` (scaffold) | `0.1` | `daemon/crates/kuma-protocol/src/lib.rs:8` |
| Default socket file name (scaffold) | `kuma-daemon.sock` | `daemon/crates/kuma-protocol/src/paths.rs:11-12` |
| Default pid file name (scaffold) | `kuma-daemon.pid` | `daemon/crates/kuma-protocol/src/paths.rs:15-16` |

---

## 3. Normative behavior

### 3.1 Data and runtime directories

| Concept | Default path | Override env | Mode |
|---------|--------------|--------------|------|
| Data dir | `~/Library/Application Support/Kuma` | `KUMA_DATA_DIR` (replaces entire `Kuma` folder) | `0700` ([02](02-security-and-secrets.md) 3.13) |
| Runtime dir | `<data dir>/run/` | `KUMA_RUNTIME_DIR` | `0700` |
| Unix socket | `<runtime dir>/kuma-daemon.sock` | (via runtime dir) | `0600` |
| PID file | `<runtime dir>/kuma-daemon.pid` | (via runtime dir) | `0600` |
| Instance lock | `<runtime dir>/kuma-daemon.lock` | (via runtime dir) | `0600` (exclusive `flock`) |
| Spool dir | `<runtime dir>/spool/` | (via runtime dir) | `0700` / files `0600` (DEV-12) |

**DEV-113:** The current Rust scaffold places the socket directly under the data dir (`paths.rs` uses `dirs::data_dir()/Kuma` without `run/`). Implementations MUST converge on `<data>/run/` as above; until then, `daemon.status.runtimeDir` reports the path actually in use.

At daemon start the process **`chdir`s to the user's real home** (passwd / `HOME`, same rules as [03](03-settings-and-environment.md) 3.10) so relative paths in provider configs match 1.x app behavior ([06](06-execution-engine.md) shell runner cwd note).

### 3.2 Daemon startup sequence (ordered)

The daemon MUST perform these steps once per process, in order. Failure before step 10 is fatal (log, non-zero exit). Steps after the RPC listener is up run concurrently with request handling.

| Step | Action | 1.x analogue |
|------|--------|--------------|
| S1 | Parse env (`KUMA_DATA_DIR`, `KUMA_RUNTIME_DIR`); create data + runtime dirs with modes | App creates Application Support on first DB open |
| S2 | Acquire **exclusive** lock on `kuma-daemon.lock` (non-blocking); if held, goto S2b | N/A (app uses bundle-id single instance) |
| S2b | If lock held: connect to socket, call `daemon.ping`; on success exit **0** with message `already running`; on failure treat lock as stale, remove lock/socket/pid and retry S2 | N/A |
| S3 | Write current pid to `kuma-daemon.pid` | N/A |
| S4 | Remove stale socket file if present (no peer check — ponytail in scaffold) | N/A |
| S5 | Bind Unix listener on `kuma-daemon.sock` | N/A |
| S6 | Open `kuma.sqlite` (GR-02), `daemon-state.sqlite`, run legacy UserDefaults import if `meta.legacyImportDone` absent (ADD-09) | App DB + UserDefaults |
| S7 | Load or create `master.key` ([02](02-security-and-secrets.md)) | `CryptoVault` at app init ([00-app.md](00-app.md)) |
| S8 | **`purge_stale_spool`**: delete files in `<runtime>/spool/` whose `serviceID` is **not** referenced by a `runtime_process` row **and** not currently registered in memory (DEV-12; replaces 1.x `RunSpool.purgeAll()` which deleted **all** spool files at every app launch, `RunSpool.swift:37-40`, `KumaApp.swift:24`) | `RunSpool.purgeAll()` |
| S9 | Sweep `<runtime>/tmp/` validator scratch (`kuma-chk-*.yaml`) older than 24 h | N/A |
| S10 | **`adopt_orphans`**: for each `runtime_process` row, run adoption pipeline ([06](06-execution-engine.md) 3.11); populate `runtime.adopt_report` (ADD-03) | 1.x had no persistence across quit |
| S11 | Start execution supervisor loops (compose poll, poller loop, debounced publish) | In-process in 1.x app |
| S12 | Register `SIGINT`/`SIGTERM` → initiate **normal shutdown** (§3.5) | N/A |
| S13 | Accept JSON-RPC connections | N/A |

After S11, if `kuma.settings.autoResumeServices` is effective-true ([03](03-settings-and-environment.md)), the daemon **does not** auto-start services at boot (1.x auto-resume runs in the **client** on first workspace load, `ServicesDeckViewModel+WorkspaceLoad.swift:39-77`). The daemon only persists `kuma.settings.activeServiceIDsBeforeQuit` and exposes state via `service.statuses`; **clients** perform resume RPCs (FEAT-LIF-18).

### 3.3 Daemon single instance

**Intent:** One daemon per macOS user session, matching [07-kuma-daemon.md](../07-kuma-daemon.md) §4.4 (same intent as `SingleInstanceGuard` for the GUI, `SingleInstanceGuard.swift:8-31`).

Algorithm: **S2 / S2b** (lock + ping). The daemon MUST NOT use `NSRunningApplication` or bundle identifiers.

**Contrast with 1.x app ([CLIENT]):** `SingleInstanceGuard.activateExistingInstanceIfRunning()` lists `NSRunningApplication.runningApplications(withBundleIdentifier:)`, activates the other instance, returns `true`; `AppDelegate` then `NSApp.terminate(nil)` on the next main-queue turn (`AppDelegate.swift:19-25`). Bypass when `XCTestConfigurationFilePath`, `XCTestSessionIdentifier`, `XCTestBundlePath`, `NSClassFromString("XCTestCase")`, `.xctest` bundle, **`KUMA_UNIT_TESTS`**, or **`isDebuggerAttached`** (`P_TRACED` via `sysctl`, `SingleInstanceGuard.swift:13-21,37-53`).

### 3.4 RPC: `daemon.ping`

**Tag:** PARITY-infra ([00 §5.1](00-overview-and-conventions.md)).

| Property | Rule |
|----------|------|
| Idempotent | Yes; no side effects |
| Auth | Same as any RPC (Unix: uid peer; REST: bearer when enabled) |
| Params | `{}` or optional `clientKind` per [02](02-security-and-secrets.md) proposed extension (`cli`, `app`, `mcp`, `rest`; default `cli`) |
| Result | `{ "pong": true, "protocolVersion": "<PROTOCOL_VERSION>" }` plus echoed `clientKind` when sent |
| `PROTOCOL_VERSION` | Exact string in `kuma_protocol::PROTOCOL_VERSION` (currently `"0.1"`) |

Scaffold: `daemon/crates/kuma-daemon/src/lib.rs:91-96`.

Clients SHOULD call `daemon.ping` after connect before other traffic. CLI smoke tests use NDJSON one line per request ([10](10-rpc-protocol.md)).

### 3.5 RPC: `daemon.status`

**Tag:** ADD-06.

| Property | Rule |
|----------|------|
| Idempotent | Yes |
| Params | `{}` |
| Result | Object below (§4.1) |

Computed at call time. MUST NOT include secrets (GR-04). Running-service entries use redacted argv ([02](02-security-and-secrets.md) 3.12.2).

### 3.6 RPC: `daemon.shutdown`

**Tag:** ADD-06.

| Property | Rule |
|----------|------|
| Params | `{ "stopServices"?: boolean, "composeDown"?: boolean }` |
| Defaults | `stopServices`: **false**; `composeDown`: **true** when stopping |
| Immediate result | `{ "accepted": true }` — shutdown continues asynchronously |
| Ordering | Emit event `daemon.shutting_down` (§3.8) to all subscribers **before** stopping services |
| `stopServices: true` | Call `stop_all_services(compose_down: composeDown)` ([06](06-execution-engine.md) 3.10.9 item 1, DEV-08, DEV-73) |
| `stopServices: false` | Call `detach_all()` (3.10.9 item 2) |
| After work | Close listeners, drop lock, remove socket + pid file, exit **0** |
| Concurrent calls | Second call while shutting down: idempotent `{ "accepted": true }` |
| Ctrl+C / SIGTERM on daemon | Same as `stopServices: false` unless env `KUMA_SHUTDOWN_STOP_SERVICES=1` is set (ADD-117, for integration tests) |

**Not logged** in audit ([02](02-security-and-secrets.md) 3.10): only the mutating entry is logged; ping/status exempt.

Scaffold accepts shutdown and returns `{ "accepted": true }` without stopping services (`lib.rs:98`).

### 3.7 Normal daemon shutdown (non-RPC)

Triggered by: `daemon.shutdown` completion path, SIGINT/SIGTERM handler (§3.6), or `LaunchAgent` `SIGTERM` on logout.

Uses **`detach_all()`** unless the RPC explicitly requested `stopServices: true`. Children keep running (DEV-10, DEV-111).

### 3.8 Events

#### 3.8.1 `daemon.shutting_down`

Registered in [00 §5.7](00-overview-and-conventions.md).

| Field | Type | JSON key | Content |
|-------|------|----------|---------|
| Stop services flag | boolean | `stopServices` | Echo of RPC param |
| Compose down flag | boolean | `composeDown` | Echo when stopping |

Payload is not redacted (no secret fields).

#### 3.8.2 `notify` (daemon → client delivery)

The daemon MUST emit `notify` when 1.x would call `SystemNotificationCenter.shared.send`, with **`playSound`** implied true unless the setting disables failure notifications.

| `notify.kind` | When | Title (exact) | Body template (exact) | 1.x source |
|---------------|------|---------------|----------------------|------------|
| `serviceCrash` | Unexpected exit when `notifyOnServiceFailure` effective-true | `Service Crashed` | `“<name>” stopped unexpectedly: <reason>` if reason set, else `“<name>” has terminated unexpectedly.` | `SystemNotificationCenter.swift:61-65`, `ExecutionSupervisor.swift:291-295` |
| `healthCheckFailed` | Health poller transition to failed (DEV-13) | `Health Check Failed` | `“<name>” at <url> is not responding.` | `SystemNotificationCenter.swift:67-69` (1.x dead code path) |
| `portCollision` | Port conflict policy `warn_and_block` blocks start | `Port Conflict Detected` | `Port <port> is already in use by “<collidingService>”.` | `SystemNotificationCenter.swift:71-73`, `LocalPortConflictResolver.swift:69` |
| `custom` | Reserved | `<title>` | `<body>` | `SystemNotificationCenter.swift:75-77` |

Daemon applies **`strict` redaction** to free-text fields before emit ([02](02-security-and-secrets.md) 3.12.2).

**[CLIENT] delivery:** Map `notify` to `UNUserNotificationCenter` using the same title/body strings; request authorization when `.notDetermined` (`SystemNotificationCenter.swift:46-56`); skip entirely when `SingleInstanceGuard.isTestingEnvironment` equivalent (`KUMA_UNIT_TESTS` / test RPC flag); foreground presentation `[.banner, .sound, .badge]` (`AppDelegate.swift:125-130`). Optional sound uses client `KumaSoundManager` ([CLIENT], [00-app.md](00-app.md) INV-APP-06).

### 3.9 Quit ownership: 1.x monolith vs V2 split

#### 3.9.1 Active service set for quit dialog

When the **1.x app** handles `applicationShouldTerminate` (`AppDelegate.swift:39-43`):

```
registryIDs = ProcessRegistry.activeRunningServiceIDs
storeIDs = serviceStateStore?.activeServiceIDs ?? []
activeIDs = registryIDs.isEmpty ? storeIDs : registryIDs
```

V2 **client** MUST compute the same UX input via `service.statuses` (operational services) preferring live runtime over deck store state.

#### 3.9.2 Confirm-before-quit gate

| Condition | 1.x behavior | V2 client | V2 daemon |
|-----------|--------------|-----------|-----------|
| `confirmBeforeQuit` effective-false **or** `activeIDs` empty | Snapshot IDs to `kuma.settings.activeServiceIDsBeforeQuit`, terminate app | Close UI; **do not** call `daemon.shutdown {stopServices:true}` | Keeps running |
| `quitBehavior == stopAll` (stored) | Snapshot, `performTeardownAndQuit` → `stopAll` + `terminateAllAsync`, `terminateLater` | Snapshot via `settings.set`, `daemon.shutdown {stopServices:true}`, then quit client | Stops or detaches per RPC |
| `quitBehavior == quitAnyway` | Snapshot, `terminateNow` (no modal) | Close client without stopping daemon | Services keep running (DEV-111) |
| `quitBehavior == ask` (default) | Modal (§3.9.3) | Same strings/buttons | Unchanged |

**1.x nuance:** `applicationWillTerminate` **always** schedules `ExecutionSupervisor.stopAll()` + `terminateAllAsync()` (`AppDelegate.swift:117-122`), so **every** app exit path ultimately stops subprocesses in the monolith—even `quitAnyway`—after snapshotting for auto-resume on next launch. V2 **intentionally** separates client exit from daemon lifecycle (DEV-111).

#### 3.9.3 Quit modal copy (1.x exact)

| Element | Text |
|---------|------|
| `messageText` | `Processes are still running` |
| `informativeText` | `<count> service(s) are currently running. Stop everything before quitting, or quit anyway?` |
| Button 0 | `Stop All & Quit` → remember → `quitBehavior=stopAll` |
| Button 1 | `Quit Anyway` → remember → `quitBehavior=quitAnyway` |
| Button 2 | `Cancel` → `terminateCancel` |
| Suppression | `Remember this choice` |

Settings UI to clear remembered behavior: [03](03-settings-and-environment.md) key `kuma.settings.quitBehavior`.

#### 3.9.4 `performTeardownAndQuit` watchdog

After `stopAll` + `terminateAllAsync`, reply `terminateLater` with `reply(toApplicationShouldTerminate: true)`; schedule `exit(0)` after **0.3** s if still stuck (`AppDelegate.swift:105-114`). V2 client SHOULD use a similar timeout waiting for `daemon.shutdown` completion event or RPC session drop.

#### 3.9.5 Auto-resume snapshot

`snapshotActiveIDs` writes UUID strings to `kuma.settings.activeServiceIDsBeforeQuit` (`AppDelegate.swift:135-137`). On next workspace load, if `autoResumeServices` is true, client starts each intersection of snapshot and deck ([03](03-settings-and-environment.md) 3.7, FEAT-LIF-18).

### 3.10 1.x hook → V2 owner map

| 1.x hook | Location | V2 owner | Notes |
|----------|----------|----------|-------|
| Second app instance activate + exit | `SingleInstanceGuard`, `AppDelegate` | **[CLIENT]** for GUI; **daemon** lock+ping for `kuma` | Bundle id `com.kuma.Kuma` |
| Notification permission prompt | `AppDelegate.applicationDidFinishLaunching` | **[CLIENT]** | Daemon emits `notify` only |
| `RunSpool.purgeAll` on main window appear | `KumaApp.swift:24` | **daemon** S8 | DEV-12 selective purge |
| `bindExecutionSupervisor` / live state | `KumaApp.swift:26` | **daemon** + client via `events.subscribe` | |
| `AutoReconnectCoordinator.configure` | `KumaApp.swift:28` | **daemon** ([06](06-execution-engine.md) 3.12) | |
| `KumaLogFont.registerBundledFonts` | `KumaApp.swift:20` | **[CLIENT]** | |
| `SystemActivityLogRecording.install` | `KumaApp.swift:21` | **[CLIENT]** bridge to RPC/events | |
| Onboarding phase / `hasCompletedOnboarding` | `AppCoordinator`, `ContentView` | **[CLIENT]** UI; **daemon** stores key | [03](03-settings-and-environment.md) |
| Quit dialog + teardown | `AppDelegate` | **[CLIENT]** dialog; **daemon** `daemon.shutdown` | DEV-111 |
| `applicationWillTerminate` stopAll | `AppDelegate` | **daemon** only when RPC asks | 1.x always stopAll |
| `userNotificationCenter` foreground | `AppDelegate` | **[CLIENT]** | |
| `launchAtLogin` SMAppService | `SettingsViewModel` | **[CLIENT]** for **app** login item | Separate from daemon LaunchAgent (FEAT-LIF-12) |
| Process registry / execution | In-app | **daemon** | |
| `CryptoVault` / `master.key` | App | **daemon** (DEV-09) | |
| Factory reset stop-all | DataPort | **daemon** `data.factory_reset` + `stop_all_services` | [09](09-dataport.md) |

### 3.11 LaunchAgent (`kuma daemon install` / `uninstall`)

**Tag:** ADD-110.

| Item | Value |
|------|-------|
| Plist path | `~/Library/LaunchAgents/com.kuma.daemon.plist` |
| Label | `com.kuma.daemon` |
| `ProgramArguments` | `[ "<absolute-path-to-kuma-binary>", "daemon", "run" ]` |
| `RunAtLoad` | `true` |
| `KeepAlive` | `false` (do not respawn on crash by default; ADD-111 optional `KeepAlive` only after explicit `kuma daemon install --keep-alive`) |
| `StandardOutPath` / `StandardErrorPath` | Optional: `<runtime>/launchd.out.log` / `.err.log` |
| `EnvironmentVariables` | MAY set `KUMA_DATA_DIR` / `KUMA_RUNTIME_DIR`; MUST NOT set secrets |

**`kuma daemon install`:** Resolve binary path (`current_exe canonicalize`), write plist, `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.kuma.daemon.plist` (or `load` on older macOS). Idempotent overwrite.

**`kuma daemon uninstall`:** `launchctl bootout gui/$UID/com.kuma.daemon`, remove plist, optionally send `daemon.shutdown {stopServices:false}` if socket responds.

**Independence:** `kuma.settings.launchAtLogin` registers **`SMAppService.mainApp`** for **Kuma.app** only ([03](03-settings-and-environment.md)); it does **not** install `com.kuma.daemon`. A future integrated installer MAY register both under explicit user consent (ADD-118).

Scaffold: `daemon/kuma/src/main.rs:42-44` bails not implemented — implement per this section.

### 3.12 Packaging, signing, and CI

#### 3.12.1 Kuma.app (1.x ship path)

| Step | Script / workflow | Behavior |
|------|-------------------|----------|
| Release build | `Scripts/make-dmg.sh` | `xcodebuild` Release → optional `mac-sign-app.sh` → DMG → optional `mac-notarize-dmg.sh` |
| Sign identity | env `MACOS_SIGN_IDENTITY` | Developer ID Application; hardened runtime `--options runtime --timestamp` |
| Entitlements | `Kuma/Kuma.entitlements` | Hardened runtime flags only (`cs.allow-jit` false, etc.); **no** app sandbox |
| Ad-hoc | absent `MACOS_SIGN_IDENTITY` | `codesign --force --deep --sign -` |
| CI release | `.github/workflows/release.yml` | Tag `v*` → import cert if `ENABLE_RELEASE_CODESIGN` → `make-dmg.sh` → GitHub Release |
| Maintainer docs | `README.md` §Signed & notarized releases | Secrets table |

#### 3.12.2 `kuma` daemon binary (V2)

| Requirement | Rule |
|-------------|------|
| CI | `.github/workflows/daemon-ci.yml`: `cargo fmt`, `clippy -D warnings`, `test` on `macos-15`, path filter `daemon/**` |
| Ship channel | Release tarball or Homebrew cask **TBD**; not embedded in DMG until integration phase ([07-kuma-daemon.md](../07-kuma-daemon.md) §5) |
| Signing | When distributed standalone, sign with the **same Developer ID team** as `Kuma.app` for Gatekeeper ([07](../07-kuma-daemon.md) §7, ADD-119) |
| Entitlements | No Keychain access group required (DEV-09 `master.key` file); hardened runtime recommended |

**ADD-119:** Release workflow gains an optional job building signed `kuma` zip when `ENABLE_DAEMON_RELEASE=true` (not required for parity gate).

### 3.13 Client app startup (V2 target, normative for parity planning)

When the Swift UI becomes a daemon client:

1. **[CLIENT]** `SingleInstanceGuard` for the app bundle (unchanged).
2. **[CLIENT]** Ensure daemon running: try `daemon.ping`; on failure run `launchctl kickstart -k gui/$UID/com.kuma.daemon` or spawn `kuma daemon run` in dev.
3. **[CLIENT]** `events.subscribe` for deck/logs/notifications.
4. **[CLIENT]** Onboarding/main phase from `settings.get` `kuma.has_completed_onboarding`.
5. **[CLIENT]** Auto-resume via `service.start` loop (§3.9.5), not daemon boot.

---

## 4. Data shapes

### 4.1 `daemon.status` result

| Field | Type | Optional? | Default | JSON key |
|-------|------|-----------|---------|----------|
| Daemon version | string | no | crate/package version | `version` |
| Protocol version | string | no | `PROTOCOL_VERSION` | `protocolVersion` |
| Uptime seconds | number | no | 0 at start | `uptimeSecs` |
| Data directory | string | no | resolved path | `dataDir` |
| Runtime directory | string | no | resolved path | `runtimeDir` |
| Socket path | string | no | | `socketPath` |
| DB path | string | no | `<dataDir>/kuma.sqlite` | `dbPath` |
| Daemon-state path | string | no | | `daemonStatePath` |
| Schema migrations applied | string[] | no | [] | `schemaMigrations` |
| Workspace count | integer | no | 0 | `workspaceCount` |
| Service count | integer | no | 0 | `serviceCount` |
| Running services | array | no | [] | `runningServices` |
| → service id | UUID string | no | | `serviceID` |
| → name | string | no | | `serviceName` |
| → mode | string enum | no | | `mode` |
| → pid | integer | yes | null | `pid` |
| 1.x app running advisory | boolean | no | false | `legacyAppRunning` |
| Last adoption report | object | yes | null | `adoptReport` |
| Instance id | UUID string | no | from `meta.instanceId` | `instanceId` |

`legacyAppRunning`: true when a process matches ADD-22 detection ([01](01-data-model.md) 3.12).

### 4.2 `daemon.ping` result

| Field | Type | JSON key |
|-------|------|----------|
| Pong flag | boolean | `pong` |
| Protocol version | string | `protocolVersion` |
| Client kind echo | string | `clientKind` |

### 4.3 `daemon.shutdown` params / result

| Field | Type | Optional? | JSON key |
|-------|------|-----------|----------|
| Stop services | boolean | yes (default false) | `stopServices` |
| Compose down | boolean | yes (default true when stopping) | `composeDown` |
| Accepted | boolean | no (result) | `accepted` |

### 4.4 `notify` event payload (subset)

| Field | Type | JSON key |
|-------|------|----------|
| Kind | string enum | `kind` |
| Service name | string | `serviceName` |
| Reason | string | `reason` |
| Target URL | string | `targetUrl` |
| Port | integer | `port` |
| Colliding service | string | `collidingService` |
| Custom title | string | `title` |
| Custom body | string | `body` |

Only fields relevant to `kind` are present.

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-LIF-01 | [V2-ADD] | Daemon data/runtime dir layout and env overrides | brief §Global | - |
| FEAT-LIF-02 | [V2-ADD] | Single-instance lock + stale recovery + ping probe | vs `SingleInstanceGuard` | `daemon.ping` |
| FEAT-LIF-03 | [V2-ADD] | Ordered daemon startup (DB, vault, spool purge, adoption) | `KumaApp` + DB init | `daemon.status` |
| FEAT-LIF-04 | [PARITY-infra] | Liveness ping + protocol version | scaffold `lib.rs` | `daemon.ping` |
| FEAT-LIF-05 | [V2-ADD] | Rich status (paths, counts, running set, adopt report) | ADD-06 | `daemon.status` |
| FEAT-LIF-06 | [V2-ADD] | Graceful shutdown RPC with stop vs detach | ADD-06, [06](06-execution-engine.md) 3.10.9 | `daemon.shutdown` |
| FEAT-LIF-07 | [V2-ADD] | `daemon.shutting_down` event | ADD-06 | `events.subscribe` |
| FEAT-LIF-08 | [V2-ADD] | Stale spool purge at daemon start (keep adopted/running) | `RunSpool.purgeAll` | - |
| FEAT-LIF-09 | [V2-ADD] | Orphan adoption at daemon start | DEV-10, ADD-03 | `runtime.adopt_report` |
| FEAT-LIF-10 | [PARITY] | Emit `notify` for crash / port / health (health DEV-13) | `SystemNotificationCenter`, supervisor | `events.subscribe` |
| FEAT-LIF-11 | [CLIENT] | Deliver macOS notifications + permission + foreground banner | `AppDelegate`, `SystemNotificationCenter` | - |
| FEAT-LIF-12 | [CLIENT] | Launch Kuma.app at login (`SMAppService`) | `SettingsViewModel.swift:192-202` | `settings.set` |
| FEAT-LIF-13 | [V2-ADD] | Launch **daemon** at login (LaunchAgent) | ADD-110 | `kuma daemon install` |
| FEAT-LIF-14 | [CLIENT] | GUI single-instance guard | `SingleInstanceGuard.swift` | - |
| FEAT-LIF-15 | [CLIENT] | Onboarding vs main workspace phase | `AppCoordinator.swift` | `settings.get` / `settings.set` |
| FEAT-LIF-16 | [CLIENT] | Quit confirmation dialog + remembered `quitBehavior` | `AppDelegate.swift:39-102` | `settings.get` / `settings.set` |
| FEAT-LIF-17 | [CLIENT] | Snapshot `activeServiceIDsBeforeQuit` on quit | `AppDelegate.swift:135-137` | `settings.set` |
| FEAT-LIF-18 | [PARITY] | Auto-resume services on client load after quit | `ServicesDeckViewModel+WorkspaceLoad.swift:50-77` | `service.start` |
| FEAT-LIF-19 | [PARITY] | Stop-all on intentional quit (1.x monolith) | `ExecutionSupervisor.stopAll`, `AppDelegate` | `daemon.shutdown` `{stopServices:true}` |
| FEAT-LIF-20 | [CLIENT] | Main window default size 1100×750, onboarding window | `KumaApp.swift:32-49` | - |
| FEAT-LIF-21 | [CLIENT] | Bundled fonts + activity log font | `KumaApp.swift:20`, tests TC-H04 | - |
| FEAT-LIF-22 | [CLIENT] | Custom notification sound sync (`~/Library/Sounds/`) | [00-app.md](00-app.md) INV-APP-06 | - |
| FEAT-LIF-23 | [PARITY-infra] | SIGINT/SIGTERM daemon handler → detach | scaffold `lib.rs:23-26` | - |
| FEAT-LIF-24 | [V2-ADD] | Detect coexisting 1.x app (advisory) | [01](01-data-model.md) ADD-22 | `daemon.status` |
| FEAT-LIF-25 | [V2-ADD] | Daemon CI on push/PR | `.github/workflows/daemon-ci.yml` | - |
| FEAT-LIF-26 | [V2-ADD] | Documented signed/notarized app release path | `Scripts/*`, `release.yml`, README | - |

---

## 6. Error catalog

| Code | Condition | Message (exact if from 1.x) |
|------|-----------|------------------------------|
| `KUMA_LIF_ALREADY_RUNNING` | Second daemon start; peer responded to ping | `Kuma daemon is already running` |
| `KUMA_LIF_LOCK_FAILED` | Cannot acquire `kuma-daemon.lock` and ping failed for other reason | `Could not acquire daemon lock: <os error>` |
| `KUMA_LIF_BIND_FAILED` | Unix bind failed after cleanup | `Could not bind socket: <path>` |
| `KUMA_LIF_NOT_RUNNING` | CLI install/uninstall/status-local when no daemon | `Kuma daemon is not running` |
| `KUMA_LIF_SHUTDOWN_IN_PROGRESS` | Optional: RPC rejected mid-shutdown (if implemented) | `Daemon is shutting down` |

1.x quit path has no stable error strings; dialog is AppKit modal only.

---

## 7. Deviations

| Id | One-line summary |
|----|------------------|
| DEV-08 | Full process-tree signal escalation on stop (not 1.x `terminateAll` SIGTERM-only ~200 ms) — invoked via `daemon.shutdown {stopServices:true}` |
| DEV-10 | Persist `runtime_process`; adopt on daemon start; detach leaves children running |
| DEV-11 | All 1.x UserDefaults keys → daemon settings KV (quit snapshot keys included; [03](03-settings-and-environment.md)) |
| DEV-12 | Spool under `<runtime>/spool/`; selective purge at start |
| DEV-73 | Split shutdown primitives `stop_all_services` / `detach_all` ([06](06-execution-engine.md) 3.10.9) |
| DEV-110 | Daemon single-instance uses lock file + `daemon.ping`, not AppKit bundle id |
| DEV-111 | Closing V2 client does not stop services; 1.x `applicationWillTerminate` always `stopAll` |
| DEV-112 | Normal daemon exit uses `detach_all` (services survive); 1.x quit kills subprocesses |
| DEV-113 | Runtime dir canonical `<data>/run/`; scaffold may still use flat data dir until migrated |
| DEV-114 | Health-check macOS notification emitted as `notify` (DEV-13) though 1.x Swift path was unused |
| DEV-115 | Auto-resume stays client-driven RPC loop; daemon does not start services at S11 |

**Additions (this spec’s range 110–119):**

| Id | One-line summary |
|----|------------------|
| ADD-110 | `kuma daemon install` / `uninstall` LaunchAgent `com.kuma.daemon` |
| ADD-111 | Optional `kuma daemon install --keep-alive` sets LaunchAgent `KeepAlive` true |
| ADD-112 | LaunchAgent stdout/stderr log files under runtime dir |
| ADD-113 | `daemon.status` exposes `instanceId`, `adoptReport`, `legacyAppRunning` |
| ADD-114 | Wire `notify.kind` enum for client notification mapping |
| ADD-115 | `meta.instanceId` regenerated on each daemon process start (event seq continuity per [08](08-logs-and-events.md)) |
| ADD-116 | CLI `kuma daemon status` prints JSON from `daemon.status` (see [11](11-cli.md)) |
| ADD-117 | Env `KUMA_SHUTDOWN_STOP_SERVICES=1` makes SIGTERM stop services (tests only) |
| ADD-118 | Document dual login items: app `SMAppService` vs daemon LaunchAgent |
| ADD-119 | Optional signed standalone `kuma` release artifact in CI |

---

## 8. Invariants

| Id | Statement |
|----|-----------|
| INV-D-LIF-01 | At most one live daemon per user holds `kuma-daemon.lock` and serves `kuma-daemon.sock`. |
| INV-D-LIF-02 | After `detach_all` shutdown, every previously running workload process still exists in the process table unless the user sent `stopServices: true`. |
| INV-D-LIF-03 | `daemon.ping` never mutates persisted state. |
| INV-D-LIF-04 | `notify` payloads never contain secrets after redaction (GR-04). |
| INV-D-LIF-05 | Spool purge at start never deletes `<spool>/<serviceID>.out` when a `runtime_process` row exists for that `serviceID`. |
| INV-D-LIF-06 | Socket and runtime dir are user-only (`0700` dir, `0600` socket). |
| INV-D-LIF-07 | `protocolVersion` in ping/status matches the compiled `PROTOCOL_VERSION` constant. |
| INV-D-LIF-08 | LaunchAgent `ProgramArguments[0]` is an absolute path to the `kuma` binary that was used for `install`. |

---

## 9. Acceptance tests

| Id | Arrange | Assert |
|----|---------|--------|
| DT-LIF-01 | Start daemon fresh | `daemon.ping` → `pong:true`, `protocolVersion` matches constant |
| DT-LIF-02 | Start second daemon same user | Exit non-zero or `KUMA_LIF_ALREADY_RUNNING`; first still pings |
| DT-LIF-03 | Delete lock, leave stale socket, start | S2b removes stale files and binds |
| DT-LIF-04 | Running service + daemon restart | Adoption restores running state; spool file retained (DEV-10) |
| DT-LIF-05 | Orphan spool file, no DB row | S8 deletes orphan spool file |
| DT-LIF-06 | `daemon.shutdown` `{stopServices:false}` with running service | Process still alive; socket gone; row persists |
| DT-LIF-07 | `daemon.shutdown` `{stopServices:true}` | All services stopped per 3.10.9; rows cleared |
| DT-LIF-08 | Subscribe + shutdown | Receive `daemon.shutting_down` before listener closes |
| DT-LIF-09 | Force service crash with notify enabled | `notify` kind `serviceCrash`, title `Service Crashed` |
| DT-LIF-10 | Port conflict warn policy | `notify` kind `portCollision`, title `Port Conflict Detected` |
| DT-LIF-11 | `daemon.status` | Fields §4.1 present; paths exist; counts match DB |
| DT-LIF-12 | `kuma daemon install` then logout/login | Daemon auto-starts (LaunchAgent) |
| DT-LIF-13 | `kuma daemon uninstall` | Plist removed; bootout succeeds |
| DT-LIF-14 | Client mapping test (future) | Quit dialog strings match §3.9.3 |
| DT-LIF-15 | `cargo test` daemon-ci workflow | fmt, clippy, tests green on macOS |

---

## Proposed RPC additions

None. `daemon.ping` / `daemon.status` / `daemon.shutdown` are in [00 §5.1](00-overview-and-conventions.md). Optional `clientKind` on ping is proposed in [02](02-security-and-secrets.md), not a new method.

---

## Open questions / residual risks

1. **Integrated ship model:** Whether future DMG embeds signed `kuma` and runs `daemon install` on first launch is product decision (ADD-119 documents CI-only path).
2. **KeepAlive policy:** Crash-loop respawn defaults off; ops may want `--keep-alive` documented in user-facing CLI help.
3. **Stale socket without lock:** Current scaffold removes socket blindly (`lib.rs:51-55`); production should combine lock + ping (S2b) to avoid racing a live daemon.
