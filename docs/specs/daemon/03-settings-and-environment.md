# Daemon Spec 03: Settings, Environment, Dependencies and Onboarding State

> **Status:** Draft for implementation
> **Area code:** `SET`
> **Audience:** Engineers implementing the Rust daemon. This spec is normative; read [00](00-overview-and-conventions.md) first (ID schemes, RPC registry, ownership table).
> **RPC methods owned:** `settings.list`, `settings.get`, `settings.set`, `settings.reset`, `env.path`, `env.resolve_executable`, `env.validate_binary`, `env.dependencies`, `env.refresh`
> **Event produced:** `settings.changed`
> **Cross-references:** [01](01-data-model.md) (daemon-state.sqlite DDL, timestamp format), [06](06-execution-engine.md) (runners, port conflict, auto-resume algorithm), [07](07-kubernetes.md) (kubeconfig management), [09](09-dataport.md) (factory reset), [10](10-rpc-protocol.md) (wire schemas), [14](14-lifecycle-and-platform.md) (quit semantics, notifications, LaunchAgent).

---

## 1. Purpose and scope

Kuma 1.x kept every preference in `UserDefaults.standard` (domain `com.kuma.Kuma`), resolved external tools through a shell-sniffed `PATH`, and ran a dependency scan inside the onboarding wizard. The daemon replaces all of that with:

1. A **settings key/value store** in `daemon-state.sqlite` (`settings` table, DEV-11) that keeps every 1.x key name verbatim, plus a `client.` namespace for new client-only preferences.
2. A one-time **legacy import** of the 1.x `UserDefaults` plist (ADD-09).
3. The **environment layer**: login-shell `PATH` resolution, executable lookup, custom-binary validation, kubeconfig default-path resolution (path part only), real-home resolution, and the shell launch recipe used by script providers.
4. The **dependency scan** (`env.dependencies`) that the onboarding wizard and `kuma doctor`-style CLI use.
5. **Onboarding state** (completion flag) and **client prefs** persistence, with a clear daemon-versus-client split.

In scope: every key in `KumaSettingsKey`, every behavior in `Kuma/Core/Environment/*`, every Settings and Onboarding screen behavior that has a backend consequence. Out of scope: kubeconfig records and `kubectl` probing ([07](07-kubernetes.md)), runners ([06](06-execution-engine.md)), backup and factory reset ([09](09-dataport.md)), quit orchestration and notification delivery ([14](14-lifecycle-and-platform.md)).

Tags used below: **[PARITY]** exists in 1.x, **[V2-ADD]** new, **[CLIENT]** stays in the client (listed so nothing is silently dropped).

---

## 2. 1.x source of truth

All paths relative to repo root. Everything below was read in full.

| Area | Files |
|------|-------|
| Keys and helpers | `Kuma/Domain/Models/KumaSettingsKey.swift:5-78` |
| Dependency model | `Kuma/Domain/Models/SystemDependency.swift` |
| Environment | `Kuma/Core/Environment/EnvironmentPathResolver.swift`, `DependencyChecker.swift`, `KumaSettingsExecutableResolver.swift`, `KumaShellLaunchConfiguration.swift` |
| Lifecycle | `Kuma/Core/Lifecycle/AppCoordinator.swift`, `Kuma/App/AppDelegate.swift`, `Kuma/KumaApp.swift`, `Kuma/ContentView.swift:85-93`, `Kuma/App/KumaCommands.swift:53-60` |
| Settings UI | `Kuma/Presentation/Features/Settings/ViewModels/SettingsViewModel.swift`; `Views/SettingsView.swift`; `Views/Sections/Settings{General,Appearance,CLITools,TunnelingTools,PortsConnections,Data}Section.swift`; `Views/Components/{AppearanceCard,BinaryStatusBadge,SettingsDataPanelPresenter}.swift`; FormKit `KumaFilePickerField.swift`, `KumaRowPickerField.swift` |
| Onboarding UI | `Kuma/Presentation/Features/Onboarding/ViewModels/OnboardingViewModel.swift`; `Views/OnboardingWizardView.swift`; `Views/Steps/{Welcome,ContainersAndClusters,PublicTunneling,Ready}StepView.swift`; `Views/Components/DependencyStatusRowView.swift` |
| Setting consumers | `Kuma/Stores/WorkspaceStore.swift:9-20,51-60`; `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+WorkspaceLoad.swift:39-77`; `Kuma/Core/Execution/LocalPortConflictResolver.swift:44-75`; `Kuma/Core/Execution/PortConflictMessaging.swift:30-34`; `Kuma/Core/Execution/Supervision/ExecutionSupervisor.swift:283-289`; `Kuma/Core/Execution/Runners/{ShellRunner,ContainerRunner,KubernetesRunner,TunnelRunner}.swift`; `Kuma/Presentation/Features/LiveLogs/LiveLogSourceRunner.swift`; `Kuma/Core/Kubernetes/{KubeConfigMaterializer,KubeConfigExecutionResolver,KubeConnectionValidator}.swift`; `Kuma/Presentation/Features/Services/ViewModels/KubeConfigViewModel.swift:55-61,83-89,154-165`; `Kuma/Core/DataPort/DataPortService+FactoryReset.swift:8-35` |
| Project facts | `Kuma.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER = com.kuma.Kuma`, `ENABLE_APP_SANDBOX = NO`) |
| Existing docs | `docs/specs/01-onboarding.md`, `docs/specs/02-settings.md`, `docs/testing/01-onboarding-test-matrix.md`, `docs/testing/02-settings-test-matrix.md` |
| Tests (implicit requirements) | `KumaTests/Features/Settings/*` (6 files), `KumaTests/Features/Onboarding/*` (5 files) |

**Facts established from source that other specs rely on**

- The app is **not sandboxed** (`ENABLE_APP_SANDBOX = NO`), so the 1.x preferences plist is `~/Library/Preferences/com.kuma.Kuma.plist` (not under `~/Library/Containers`).
- `EnvironmentPathResolver.setCustomPaths`, `DependencyChecker.checkAll`, `DependencyChecker.isCommandInstalled`, `DependencyStatus`, `KumaSettingsKey.integer`, and `BinaryStatusBadge` (previews only) have **no production caller** in 1.x. They are dead code; the daemon keeps the semantics of `checkAll`/`isCommandInstalled` inside `env.dependencies` and does not expose `setCustomPaths` (see section 3.10.9).
- `EnvironmentPathResolver.refreshPath` has no 1.x caller; the PATH cache lived for the life of the app. `env.refresh` is the first consumer.
- `KumaSettingsKey.logRetentionLimit` and `clearLogsOnSwitch` have **no reader** in 1.x (the logs settings UI was removed; keys are only deleted by Reset Settings).

---

## 3. Normative behavior

### 3.1 Storage model

**3.1.1 Table.** All settings live in `daemon-state.sqlite` table `settings(key TEXT PRIMARY KEY, value TEXT NOT NULL, updatedAt TEXT NOT NULL)` (DDL authoritative in [01](01-data-model.md)). `meta.legacyImportDone` guards the legacy import (section 3.8).

**3.1.2 Value encoding.** `value` is **compact JSON text** of the logical value:

| Logical type | Stored text examples |
|--------------|----------------------|
| `bool` | `true`, `false` |
| `string` | `"/bin/zsh"` (JSON string, escapes per RFC 8259) |
| `stringArray` | `["0E9A...","71C2..."]` |
| `any` (`client.*`, dead keys) | any JSON value |

A row whose `value` fails to parse as JSON, or parses to a type that does not match the registry type for a registered key, MUST be treated as **absent** when reading (mirrors `defaults.object(forKey:) as? Bool` failing in 1.x, `KumaSettingsKey.swift:63-69`). The daemon never writes such rows itself.

**3.1.3 Key classes.**

| Class | Rule |
|-------|------|
| Registered key | One of the 26 keys in table 3.2. Typed and validated. |
| Client pref | Any key matching `^client\.[A-Za-z0-9_.\-]+$`. Opaque JSON value, no registry entry, never interpreted by the daemon. |
| Anything else | `settings.set` rejects with `KUMA_SET_UNKNOWN_KEY`; `settings.get` rejects with `KUMA_SET_UNKNOWN_KEY`. |

**3.1.4 `updatedAt`.** Per-key timestamp in the ISO-8601 format defined in [01](01-data-model.md), refreshed on every write. Used for `expectedUpdatedAt` (section 3.4.6).

**3.1.5 Live reads.** 1.x read `UserDefaults` at every use (no caching in any consumer). The daemon MAY cache in memory but MUST invalidate on every write/reset so that a `settings.set` is visible to the next process start, next port check, next notification decision, and next executable resolution without restart (INV-D-SET-04).

### 3.2 Settings registry (every key)

"Interp." = who interprets the value: **D** daemon (behavior depends on it), **C** client (daemon stores and relays only), **D-int** daemon-internal state (not shown in any UI).

| # | Exact key | Type | Allowed values | Default (absent) | Legacy fallback key | Interp. | UI section / label (1.x) | Side effects / consumers |
|---|-----------|------|----------------|------------------|---------------------|---------|--------------------------|--------------------------|
| 1 | `kuma.has_completed_onboarding` | bool | `true`/`false` | `false` | none | C | none (wizard "Get Started") | `false`/absent selects the onboarding phase at app launch. Written `true` by wizard completion, `false` by "re-show onboarding" and factory reset. See 3.9.1. |
| 2 | `kuma.settings.launchAtLogin` | bool | `true`/`false` | `false` | none | C | General / "Launch at Login" - "Open Kuma automatically at login." | Client registers or unregisters its login item on every change (`SMAppService.mainApp`). Not read at startup to sync with the real OS state. |
| 3 | `kuma.settings.autoResumeServices` | bool | `true`/`false` | `false` | none | D | General / "Auto-start Services" - "Resume active services when Kuma launches." | Gates auto-resume of services recorded in key 4 (3.7, [06](06-execution-engine.md)/[14](14-lifecycle-and-platform.md)). |
| 4 | `kuma.settings.activeServiceIDsBeforeQuit` | stringArray (UUIDs) | array of UUID strings, stored UPPERCASE (`UUID.uuidString`) | absent (effective `[]`) | none | D-int | none | Snapshot of running service IDs at quit; consumed and trimmed by auto-resume (3.7). |
| 5 | `kuma.settings.confirmBeforeQuit` | bool | `true`/`false` | `true` | none | C | General / "Confirm Before Quitting" - "Prompt before quitting when services are active." | Quit dialog gate (3.9.4). |
| 6 | `kuma.settings.quitBehavior` | string enum | `ask`, `stopAll`, `quitAnyway` | absent (effective `ask`) | none | C | General / "Saved Quit Preference" row ("Clear saved preference and prompt on quit." + button "Reset"), visible only when `confirmBeforeQuit` is true **and** the key is present | Remembered answer of the quit dialog (3.9.4). Any stored string other than the three values behaves as `ask`. |
| 7 | `kuma.settings.appearance` | string enum | `system`, `light`, `dark` | `system` | none | C | Appearance / cards "System Default", "Light", "Dark" | Client sets `NSApp.appearance` (`nil`, `.aqua`, `.darkAqua`). Invalid stored value behaves as `system`. |
| 8 | `kuma.settings.defaultShell` | string (path) | any string; UI offers `/bin/zsh` (Zsh), `/bin/bash` (Bash), `/opt/homebrew/bin/fish` (Fish) | `/bin/zsh` | none | D | CLI Tools / "Default Shell" - "Shell used to execute custom scripts." | Shell for script providers (3.10.8). Validated at use, not at write. |
| 9 | `kuma.settings.customKubectlPath` | string (path) | any string; `""` = unset | `""` | `kuma.custom_kubectl_path` | D | CLI Tools / "Kubectl (kubectl)" | Override for `kubectl` (3.10.6). |
| 10 | `kuma.settings.customKubeconfigPath` | string (path) | any string; `""` = unset | `""` | `kuma.custom_kubeconfig_path` | D | CLI Tools / "Default Kubeconfig" | Override for the Default kubeconfig file path (3.10.7). |
| 11 | `kuma.settings.customDockerPath` | string (path) | any string; `""` = unset | `""` | `kuma.custom_docker_path` | D | CLI Tools / "Docker (docker)" | Override for `docker`. |
| 12 | `kuma.settings.customPodmanPath` | string (path) | any string; `""` = unset | `""` | `kuma.custom_podman_path` | D | CLI Tools / "Podman (podman)" | Override for `podman`. |
| 13 | `kuma.settings.cloudflaredPath` | string (path) | any string; `""` = unset | `""` | `kuma.custom_cloudflared_path` | D | Tunneling Tools / "Cloudflare Tunnel (cloudflared)" | Override for `cloudflared`. |
| 14 | `kuma.settings.customNgrokPath` | string (path) | any string; `""` = unset | `""` | `kuma.custom_ngrok_path` | D | Tunneling Tools / "ngrok" | Override for `ngrok`. (ngrok auth token is per-provider, not a setting.) |
| 15 | `kuma.settings.notifyOnServiceFailure` | bool | `true`/`false` | `true` | `kuma.settings.notifyOnCrash` (bool) | D (decision) + C (permission, delivery) | General / "Notify on Service Failure" - "Notify when a service fails or exits unexpectedly." | Gates the `notify` event for crashes (3.7). Writing it deletes `kuma.settings.notifyOnCrash`. |
| 16 | `kuma.settings.portConflictPolicy` | string enum | `warn_and_block`, `kill_existing` | `warn_and_block` | none | D | Ports & Connections / "Port Conflict Action" - "Action when a configured port is already in use." Options "Warn & Prevent Start", "Kill Conflicting Process" | Read by port-conflict resolver (3.7). Invalid stored value behaves as `warn_and_block`. |
| 17 | `kuma.settings.logRetentionLimit` | any | no reader in 1.x | absent | none | none (dead) | none (UI removed) | Only removed by `settings.reset`. |
| 18 | `kuma.settings.clearLogsOnSwitch` | any | no reader in 1.x | absent | none | none (dead) | none (UI removed) | Only removed by `settings.reset`. |
| 19 | `kuma.selectedWorkspaceId.storage` | string (UUID) | UUID string, stored UPPERCASE | absent | none | C | none | Last selected workspace (3.9.6). |
| 20 | `kuma.custom_kubectl_path` | string | any | absent | n/a (legacy) | D (fallback read) | none | Fallback for key 9. |
| 21 | `kuma.custom_kubeconfig_path` | string | any | absent | n/a (legacy) | D | none | Fallback for key 10. |
| 22 | `kuma.custom_docker_path` | string | any | absent | n/a (legacy) | D | none | Fallback for key 11. |
| 23 | `kuma.custom_podman_path` | string | any | absent | n/a (legacy) | D | none | Fallback for key 12. |
| 24 | `kuma.custom_cloudflared_path` | string | any | absent | n/a (legacy) | D | none | Fallback for key 13. |
| 25 | `kuma.custom_ngrok_path` | string | any | absent | n/a (legacy) | D | none | Fallback for key 14. |
| 26 | `kuma.settings.notifyOnCrash` | bool | `true`/`false` | absent | n/a (legacy) | D | none | Fallback for key 15. |

Source: `KumaSettingsKey.swift:7-43` (names), `SettingsViewModel.swift:128-188` (defaults), `SettingsViewModel.swift:21-46` (enum raw values, titles), `AppDelegate.swift:10-13` (`QuitBehavior`), `WorkspaceStore.swift:9` (key 19).

**Mapping 1.x to the daemon KV.** The same strings are used as `settings.key` (no renaming). The `client.` prefix is reserved for **new** client prefs introduced in V2 (e.g. a SwiftUI client's view mode); no `client.*` key is predefined by this spec. Keys 1, 2, 5, 6, 7, 19 are *client-interpreted 1.x keys that keep their legacy names* (they are not renamed into `client.*`), so ADD-09 import is a plain copy and a V2 client reads the same rows a 1.x user had.

### 3.3 Read semantics (effective values)

These are exact ports of the three helpers in `KumaSettingsKey.swift`. "Present" means the row exists, parses, and has the registry type.

**3.3.1 `string(primary, fallback?)`** (`KumaSettingsKey.swift:46-54`):

1. If `primary` is present and `trim(value)` is non-empty, return `value`.
2. Else if `fallback` is given, present, and `trim(value)` is non-empty, return it.
3. Else return `null`.

`trim` = remove leading/trailing Unicode whitespace and newlines (`CharacterSet.whitespacesAndNewlines`). **DEV-42:** the daemon returns the **trimmed** string (1.x returned the raw string and later failed to resolve a value with a trailing newline).

**3.3.2 `bool(key, default, fallback?)`** (`KumaSettingsKey.swift:57-70`): if `key` is present (typed bool) return it; else if `fallback` present return it; else `default`. A present primary wins even when `false`.

**3.3.3 `integer(key, default)`**: dead in 1.x. Not implemented.

**3.3.4 Effective value per key** (what `settings.get`/`list` return as `effective`):

| Key | Rule |
|-----|------|
| 1, 2 | stored bool else `false` (1.x `UserDefaults.bool(forKey:)` returns `false` when absent) |
| 3 | `bool(key, false)` |
| 4 | stored array else `[]`; consumers drop items that are not valid UUIDs (`compactMap(UUID.init)`) |
| 5 | `bool(key, true)` |
| 6 | stored string if one of `ask`/`stopAll`/`quitAnyway`, else `"ask"`. `source` is `stored` if the row exists even when the value is not one of the three. |
| 7 | stored string if one of the three, else `"system"` |
| 8 | stored string else `"/bin/zsh"` (note: a stored `""` stays `""`; the shell resolver then falls back, 3.10.8) |
| 9-14 | `string(primary, legacy)` else `""` |
| 15 | `bool(primary, true, fallback: notifyOnCrash)` |
| 16 | stored string if one of the two, else `"warn_and_block"` |
| 17, 18, 19, 20-26 | stored value else `null` |

`source` field: `"stored"` if the primary row supplied the value, `"legacy"` if the fallback row supplied it, else `"default"`.

### 3.4 Write semantics (`settings.set`)

**3.4.1 Request.** `values`: object mapping key to value; `null` deletes the key (resets it to its default). Optional `strict` (bool, default `false`, ADD-40) and optional `expectedUpdatedAt` (object key to timestamp-or-null). The call is **atomic**: all keys are validated first; one SQLite transaction applies all writes; one `settings.changed` event follows (3.4.7). On any validation error nothing is written.

**3.4.2 Type coercion by registry type** (the daemon is stricter than UserDefaults but accepts the CLI/MCP spellings):

| Type | Accepted input | Stored as | Else |
|------|----------------|-----------|------|
| bool | JSON `true`/`false`; JSON numbers `0`/`1`; strings `true`,`false`,`1`,`0`,`yes`,`no` (ASCII case-insensitive) | canonical JSON bool | `KUMA_SET_INVALID_TYPE` |
| string enum | JSON string, exact case-sensitive match of an allowed value | the string | `KUMA_SET_INVALID_VALUE` |
| string (paths, shell) | JSON string | for the six tool-path keys: **trimmed** (DEV-42); for `defaultShell` and key 19: as given (key 19 normalized to UPPERCASE UUID, invalid UUID -> `KUMA_SET_INVALID_VALUE`) | `KUMA_SET_INVALID_TYPE` |
| stringArray (key 4) | JSON array of strings; each item parsed as UUID (any case); output UPPERCASE; items that are not UUIDs rejected | JSON array | `KUMA_SET_INVALID_TYPE` / `KUMA_SET_INVALID_VALUE` |
| any (keys 17, 18, `client.*`) | any JSON value | compact JSON | none (but `client.*` value text MUST be <= 65536 bytes, else `KUMA_SET_VALUE_TOO_LARGE`) |
| legacy keys 20-26 | same as their primary type | same | same |

An empty string is a valid value for the six tool-path keys (it means "unset", and with DEV-44 also deletes the legacy key). `defaultShell` accepts any string including `""` (1.x did not validate; the shell resolver falls back at use).

**3.4.3 Path validation is advisory by default [PARITY].** 1.x Settings persisted every keystroke and showed the validation message under the field (`SettingsCLIToolsSection.swift:16-36`); a persisted invalid override simply made the tool unresolvable at run time. Therefore with `strict=false` the daemon stores the value and returns, for each of the six tool-path keys present in the call, a `validation` entry (section 4.3) computed with `validateCustomBinary(path, expectedCommand)` (binaries) or the kubeconfig existence check (key 10). It never rejects.

**3.4.4 Strict mode (onboarding semantics, ADD-40).** With `strict=true`, a non-empty (after trim) value for a tool-path key is validated first; on failure the whole call fails with `KUMA_SET_PATH_INVALID`, `details.key` set, and nothing is persisted. This reproduces `OnboardingViewModel.setCustomPath` (`OnboardingViewModel.swift:186-219`):

| Key | Check | Failure message (exact) |
|-----|-------|-------------------------|
| 10 (kubeconfig) | `expandTilde(trimmed)` exists (`fileExists`, file or directory) | `Selected kubeconfig file does not exist at specified path.` |
| 9, 11, 12, 13, 14 | `validateCustomBinary(trimmed, expectedCommand)` where `expectedCommand` is `kubectl`/`docker`/`podman`/`cloudflared`/`ngrok` | `validation.errorMessage` (section 3.10.4), exactly `File does not exist at specified path`, `File is not an executable binary`, or `Selected file '<actual>' does not match expected '<expected>' binary` |

In strict mode an empty value is accepted and stored as `""` (the wizard's "clear" action stores an empty string, `OnboardingViewModel.swift:188-193`). The stored value on success is the **trimmed original text** (tilde not expanded), as in 1.x (test TC-B05 asserts the tilde form is stored).

**3.4.5 Side effects of a write (same transaction).**

| Written key | Also |
|-------------|------|
| 15 `notifyOnServiceFailure` | delete key 26 `kuma.settings.notifyOnCrash` (`SettingsViewModel.swift:115-119`) |
| 9-14 tool paths | **DEV-44:** delete the corresponding legacy key (20-25) so a blank new value cannot resurrect a stale legacy value |
| any `null` (delete) | delete only that key; for 9-15 also delete its legacy fallback key (so "reset to default" really resets) |

**3.4.6 `expectedUpdatedAt`.** For each key listed, the current row `updatedAt` MUST equal the supplied value (`null` means the row must not exist); otherwise the whole call fails with `KUMA_CONFLICT_STALE` and nothing is written. Omitted keys are last-write-wins (UserDefaults semantics).

**3.4.7 Event.** After commit the daemon emits `settings.changed` with payload (section 4.6) listing every key written or deleted (including legacy keys deleted by side effects) and `reason: "set"`. No event is emitted if the call changes nothing (all values equal to current rows and no deletions); `updatedAt` is not touched in that case.

**3.4.8 Result.** `{ "updated": [Setting...], "removed": [key...], "validation": { key: Validation } }`; `Setting` is the section 4.1 object (effective values after the write).

### 3.5 `settings.list` and `settings.get`

- `settings.list` params: optional `prefix` (string; only keys starting with it), optional `includeClient` (bool, default `true`). Result: `{ "settings": [Setting...] }` containing **every registered key (26) even when absent** (with `stored: null`, `effective` = default) in the order of table 3.2, followed by stored `client.*` rows sorted by key. This satisfies "all settings with defaults and effective values" in the registry.
- `settings.get` params: `key`. Result: one `Setting`. For an unset `client.*` key the result has `stored: null`, `effective: null`, `source: "default"` (not an error). Unknown non-client key: `KUMA_SET_UNKNOWN_KEY`.
- No secret is stored in settings (INV-D-SET-11); responses need no redaction. ([02](02-security-and-secrets.md) rules still apply to other specs.)

### 3.6 `settings.reset`

Reproduces `SettingsViewModel.resetSettingsToDefault` (`SettingsViewModel.swift:244-291`).

**3.6.1 Removed keys (exactly 22, in source order):**

```
kuma.settings.launchAtLogin
kuma.settings.autoResumeServices
kuma.settings.confirmBeforeQuit
kuma.settings.appearance
kuma.settings.defaultShell
kuma.settings.customKubectlPath
kuma.settings.customKubeconfigPath
kuma.settings.customDockerPath
kuma.settings.customPodmanPath
kuma.settings.cloudflaredPath
kuma.settings.customNgrokPath
kuma.settings.notifyOnServiceFailure
kuma.settings.notifyOnCrash
kuma.settings.portConflictPolicy
kuma.settings.logRetentionLimit
kuma.settings.clearLogsOnSwitch
kuma.custom_kubectl_path
kuma.custom_kubeconfig_path
kuma.custom_docker_path
kuma.custom_podman_path
kuma.custom_cloudflared_path
kuma.custom_ngrok_path
```

**3.6.2 NOT touched:** `kuma.has_completed_onboarding`, `kuma.settings.activeServiceIDsBeforeQuit`, `kuma.settings.quitBehavior`, `kuma.selectedWorkspaceId.storage`, all `client.*` keys, `meta.*`, and every non-settings table (workspaces, services, providers, kubeconfigs, images, secrets). Reset never stops services and never alters `kuma.sqlite`.

**3.6.3 End state.** After the call every effective value equals its default (table 3.3.4). 1.x additionally wrote the defaults back explicitly (each in-memory assignment fires `didSet`: `launchAtLogin=false`, `autoResumeServices=false`, `confirmBeforeQuit=true`, `appearance="system"`, `defaultShell="/bin/zsh"`, six paths `""`, `notifyOnServiceFailure=true`, `portConflictPolicy="warn_and_block"`, and re-deleted `notifyOnCrash`). The two end states are indistinguishable through any 1.x read path, so the daemon simply deletes the 22 rows (not a DEV; recorded here so the difference is not rediscovered).

**3.6.4 Client duties after reset.** `settings.changed` (`reason: "reset"`, `keys` = the 22 keys, always all of them even if not stored) tells clients to re-apply `launchAtLogin=false` (1.x called `SMAppService.mainApp.unregister()`) and `appearance=system` (1.x called `applyAppearance(.system)`). Result: `{ "removed": [keys that existed], "keys": [22 keys] }`.

**3.6.5 Confirmation UX [CLIENT].** Dialog title `Reset Settings?`, buttons `Reset Settings` (destructive) and `Cancel`, message `All preferences and tool paths will be reset to defaults. Workspaces and services will not be affected.`; success alert (title `Backup & Restore`) message `All preferences have been reset to defaults.`

### 3.7 Which component reads which setting, and when

Algorithms live in the referenced specs; this table fixes the **contract with this spec**.

| Key | Reader | When | 1.x source | Algorithm in |
|-----|--------|------|------------|--------------|
| `autoResumeServices` | daemon startup (was: first workspace load of the app session) | once per daemon start, after state restore | `ServicesDeckViewModel+WorkspaceLoad.swift:39-41` | [14](14-lifecycle-and-platform.md), [06](06-execution-engine.md) |
| `activeServiceIDsBeforeQuit` | same, plus writer at shutdown | write at every quit path (even when the active set is empty, 1.x overwrote with `[]`); read at auto-resume; after resume the consumer rewrites the array containing only IDs that were **not** resumed (`remaining = saved - candidates`) | `AppDelegate.swift:135-141`, `ServicesDeckViewModel+WorkspaceLoad.swift:50-77` | [14](14-lifecycle-and-platform.md) |
| `confirmBeforeQuit` | client quit dialog | on quit request | `AppDelegate.swift:40` (`bool(default: true)`, no legacy fallback) | 3.9.4, [14](14-lifecycle-and-platform.md) |
| `quitBehavior` | client quit dialog; written when "Remember this choice" is ticked | on quit request when `confirmBeforeQuit` and active services exist | `AppDelegate.swift:51-98` | 3.9.4 |
| `notifyOnServiceFailure` | daemon supervisor | each managed-process crash finalization that requests notification: `bool(notifyOnServiceFailure, true, fallback notifyOnCrash)`; false suppresses the `notify` event | `ExecutionSupervisor.swift:283-289` | [06](06-execution-engine.md), [14](14-lifecycle-and-platform.md) |
| `portConflictPolicy` | daemon port-conflict resolver and message builder | every local port bind check (kubectl and SSH port-forward); `kill_existing` = SIGTERM every occupant then wait 200 ms; `warn_and_block` = notify + fail only if an occupant is foreign | `LocalPortConflictResolver.swift:44-75`, `PortConflictMessaging.swift:30-34` | [06](06-execution-engine.md) |
| `defaultShell` | daemon shell runner | each script-provider start | `ShellRunner.swift:35` | 3.10.8 |
| tool paths (9-14) and their legacy keys | daemon runners, validators, live log source, kubeconfig materializer | each start / probe / log stream / dependency scan | see 3.10.6, 3.10.7 | 3.10 |
| `hasCompletedOnboarding`, `launchAtLogin`, `appearance`, `selectedWorkspaceId.storage` | clients only | per client | 3.9 | - |

### 3.8 Legacy import (ADD-09)

Runs **once**, during daemon startup, after `daemon-state.sqlite` is opened and migrated and **before** the RPC listeners accept connections.

**3.8.1 Trigger and idempotency.**

1. If `meta` has a row `legacyImportDone`, skip entirely.
2. Otherwise locate the plist (3.8.2) and attempt the import.
3. On completion write `meta.legacyImportDone` = ISO-8601 UTC timestamp, in the **same SQLite transaction** as the imported rows.
4. The import MUST NOT run again unless `daemon-state.sqlite` is deleted. `data.factory_reset` ([09](09-dataport.md)) MUST delete all `settings` rows but MUST NOT delete `meta.legacyImportDone` (otherwise stale 1.x defaults would reappear after a reset; INV-D-SET-07).

**3.8.2 Locating and reading UserDefaults on macOS.**

| Item | Value |
|------|-------|
| Bundle identifier | `com.kuma.Kuma` (`project.pbxproj`) |
| Plist path | `<real home>/Library/Preferences/com.kuma.Kuma.plist`, real home from `getpwuid(getuid())` (3.10.5) |
| Override | env `KUMA_LEGACY_DEFAULTS_PLIST` = absolute path (ADD-41; used by tests and by users who relocated preferences) |
| Format | Property list, **binary (`bplist00`) or XML**; a conforming reader (e.g. the Rust `plist` crate) detects both. Top level MUST be a dictionary. |
| Fresher alternative | An implementation MAY first run `/usr/bin/defaults export com.kuma.Kuma -` (XML plist on stdout) because `cfprefsd` may hold writes not yet flushed to disk while 1.x is still running; on any failure it falls back to the file. The file is the normative source. |
| Not macOS | Skip; write `legacyImportDone` (nothing to import). |

**3.8.3 Outcomes.**

| Condition | Action |
|-----------|--------|
| plist file absent | Mark done; log info `legacy import: no plist`. |
| unreadable or unparsable, or top level not a dictionary | Log warn; **do not** mark done (retry next start). Daemon starts normally. |
| parsed | Import per 3.8.4; mark done. |

**3.8.4 Which keys are imported and how.** Only keys that are in table 3.2 (rows 1-26) are considered; all other plist content (`Apple*`, `NSWindow Frame*`, `NS*`, etc.) is ignored. For each key present in the plist:

| Registry type | plist type accepted -> stored value | Otherwise |
|---------------|-------------------------------------|-----------|
| bool (keys 1, 2, 3, 5, 15, 26) | `Boolean` as is; `Integer` -> `n != 0`; `String` -> the `NSString.boolValue` rule: skip leading whitespace, optional `+`/`-`, skip leading zeros, then `true` iff the next character is one of `Y y T t 1-9`, else `false` | skip key, log warn |
| string enum (keys 6, 7, 16) | `String` whose value is allowed | skip (reads treat invalid as default anyway) |
| string (keys 8, 9-14, 20-25) | `String` verbatim (including `""`); tool-path values are trimmed (DEV-42) | skip |
| key 19 | `String` parsing as UUID -> UPPERCASE | skip |
| stringArray (key 4) | `Array` of `String`; items parsed as UUID -> UPPERCASE; non-UUID items dropped; non-array skipped | skip |
| any (keys 17, 18) | `Boolean`/`Integer`/`Real`/`String` -> JSON scalar; other plist types skipped | skip |

Rows are written with `INSERT OR IGNORE` (an existing row is never overwritten) and `updatedAt` = import time. Legacy path keys 20-25 and 26 are imported **as legacy keys** (not folded into their primary keys) so the effective-value rule (3.3) behaves exactly as in 1.x; this is what makes DEV-02 work for pre-rename installs.

**3.8.5 After import.** Emit nothing (no client is connected yet). `settings.list` shows imported keys with `source: "stored"` (or `"legacy"` for effective values supplied by legacy keys). The 1.x plist is **never modified or deleted** by the daemon (1.x may still be installed).

### 3.9 Client-interpreted behavior (kept so nothing is dropped)

Everything in this section is **[CLIENT]**. The daemon's only obligations are: store/return the values, and emit `settings.changed`.

#### 3.9.1 Onboarding completion flag and phase

- Key `kuma.has_completed_onboarding` (bool). At app launch `AppCoordinator.init` computes `hasCompleted = UserDefaults.bool(forKey:)`; `true` -> phase `mainWorkspace`, else `onboarding` (`AppCoordinator.swift:20-29`). Absent or non-boolean garbage reads as `false` (test TC-A03; for imported strings see 3.8.4 `boolValue` rule).
- `transitionTo(.mainWorkspace)` writes `true`; `transitionTo(.onboarding)` writes `false` (`AppCoordinator.swift:33-40`). `resetToOnboarding()` = `transitionTo(.onboarding)`.
- Writers in 1.x: wizard "Get Started" (via `onComplete` -> `transitionTo(.mainWorkspace)`, `KumaApp.swift:41-44`); Help menu item (`coordinator.resetToOnboarding()` then open the wizard window, `KumaCommands.swift:53-58`); Reset All Data (`resetToOnboarding()`, plus the whole preferences domain wipe, spec [09](09-dataport.md)).
- Closing the wizard window without "Get Started" leaves the flag unchanged (so the wizard shows again at next launch).
- In V2 any frontend reads/writes this key through `settings.get`/`settings.set`; the CLI treats "completed" as `effective == true`. The daemon never reads it.

#### 3.9.2 Settings screen layout and copy (SwiftUI client reference)

Window: scrollable column, max width 800, navigation title `Settings`. Section order and titles: `General` (icon `gearshape.fill`), `Appearance` (`paintbrush.fill`), `CLI Tools` (`terminal.fill`), `Tunneling Tools` (`cloud.bolt.fill`), `Ports & Connections` (`arrow.left.arrow.right`), `Data` (`internaldrive.fill`; export/import/reset-all belong to [09](09-dataport.md)); footer `Kuma v<CFBundleShortVersionString, default "1.0.0"> (<CFBundleVersion, default "1>")` (`SettingsView.swift:12-53`). Appearance section caption: `Choose an appearance theme for Kuma.`; card icons `circle.righthalf.filled` (system), `sun.max.fill` (light), `moon.fill` (dark); selection animation spring(response 0.28, damping 0.72); mini-window previews drawn client-side (`AppearanceCard.swift`).

Tool rows: caption labels `Kubectl (kubectl)`, `Default Kubeconfig`, `Docker (docker)`, `Podman (podman)`, `Cloudflare Tunnel (cloudflared)`, `ngrok`; text field plus `Browse` button; file picker filters: executables (`unixExecutable`, `executable`) for binaries, any file for kubeconfig; error text in red under the field. Default Shell row picker options = the three shells; label of an unknown stored shell is shown as `Zsh` (`titleResolver { (DefaultShell(rawValue:) ?? .zsh).label }`) while the raw value is still listed as an extra option.

#### 3.9.3 Auto-fill of detected paths (CLI Tools and Tunneling Tools sections)

When a tool section appears (`.task`), the client resolves tools with the **pure PATH** lookup (no settings override) and:

1. Sets each field's placeholder to the detected path, else `Not detected`; for kubeconfig the placeholder is `~/.kube/config` if `isKubeconfigPresent()` (no custom path argument) else `Not detected`.
2. **Persists** the detected value into the setting if the field is currently blank (after trim): `kubectl`, `docker`, `podman` (`SettingsCLIToolsSection.swift:135-163`), `cloudflared`, `ngrok` (`SettingsTunnelingToolsSection.swift:74-89`); kubeconfig is filled with the literal string `~/.kube/config` when present. The VM `didSet` writes it, so merely opening Settings freezes the detected path.

Daemon mapping: client calls `env.resolve_executable` (`applySettings: false`) per tool and `env.dependencies` for kubeconfig presence, then `settings.set`. The daemon MUST NOT auto-fill by itself (headless users keep PATH-following behavior). `BinaryStatusBadge` (`Available` green / `Not Found` red-80%) exists only in previews.

#### 3.9.4 Quit flow (`AppDelegate.applicationShouldTerminate`)

Daemon-side shutdown semantics are in [14](14-lifecycle-and-platform.md); the setting-dependent decision table:

| `confirmBeforeQuit` | active services | `quitBehavior` | Result |
|---------------------|-----------------|----------------|--------|
| `false` or no active | any | any | Snapshot IDs (`activeServiceIDsBeforeQuit`), quit immediately (no dialog) |
| `true` | >= 1 | `stopAll` | Snapshot, stop all, quit |
| `true` | >= 1 | `quitAnyway` | Snapshot, quit |
| `true` | >= 1 | `ask` or absent or invalid | Show dialog |

`activeIDs` = running IDs from the process registry, or, when that is empty, from the UI state store (`AppDelegate.swift:41-44`). Dialog (alert style warning): title `Processes are still running`; text `<n> service(s) are currently running. Stop everything before quitting, or quit anyway?`; buttons `Stop All & Quit`, `Quit Anyway`, `Cancel`; suppression checkbox `Remember this choice`. First button + checkbox writes `quitBehavior = stopAll`; second + checkbox writes `quitBehavior = quitAnyway`; Cancel aborts quit and never persists. The snapshot is written for stop-all and quit-anyway, not for Cancel. The `Saved Quit Preference` row's `Reset` button deletes `quitBehavior` (`settings.set` with `null`).

#### 3.9.5 Notification permission flow (`requestNotificationAuthorization`, `SettingsViewModel.swift:218-240`)

Triggered only when `notifyOnServiceFailure` changes to `true` (`SettingsGeneralSection.swift:35-41,82-91`). Returns `true` when the "Notification Permission Required" alert must be shown.

| OS authorization status | Effect on `notifyOnServiceFailure` | Returns |
|-------------------------|-----------------------------------|---------|
| `notDetermined` in a test host | set `false` | `true` |
| `notDetermined` (normal) | request authorization; set to `granted` | `!granted` |
| `denied` | set `false` | `true` |
| `authorized`, `provisional`, `ephemeral` | set `true` | `false` |
| unknown future status | unchanged | `false` |

Alert: title `Notification Permission Required`, message `Kuma needs permission to send notifications. Please allow it in macOS System Settings.`, buttons `Open System Settings` (opens `x-apple.systempreferences:com.apple.preference.notifications`) and `Cancel`. At app launch the app also requests authorization once when status is `notDetermined` (`AppDelegate.swift:31-35`). Turning the toggle off never prompts. In V2 the client performs the prompt and writes the outcome with `settings.set`.

#### 3.9.6 Selected workspace

Key `kuma.selectedWorkspaceId.storage` holds `workspace.id.uuidString`. Written on every assignment of a non-nil `selectedWorkspaceId` (never cleared when it becomes `nil`, `WorkspaceStore.swift:15-20`). On load, if the stored string parses as a UUID **and** that workspace exists, it is selected; otherwise the first workspace (`WorkspaceStore.swift:51-60`). After a workspace delete that removed the selected one the store selects `workspaces.first`. The daemon only stores/returns the value; workspace existence is the client's check (workspace deletion in [04](04-workspaces-groups-services.md) does not rewrite this key).

#### 3.9.7 Launch at login

Every change of `launchAtLogin` writes the key and calls `SMAppService.mainApp.register()` / `.unregister()`; failures are logged, never surfaced (`SettingsViewModel.swift:192-202`). Initialization does not reconcile the stored value with the real login-item state. [CLIENT]. The daemon's own LaunchAgent is specified in [14](14-lifecycle-and-platform.md) and is independent of this key.

#### 3.9.8 Onboarding wizard (UI contract, [CLIENT])

| Item | Value |
|------|-------|
| Window | `Window("Welcome to Kuma", id: "onboarding")`, fixed 680 x 500, canvas background, rounded `xl`, hairline border |
| Steps (`totalSteps = 4`) | 0 Welcome, 1 Containers & Clusters, 2 Public Tunneling, 3 Ready; `currentStep` bounded `0...3` (spamming next/prev clamps) |
| Header | Back chevron button (only when `canGoPrev`; accessibility label `Previous Step`; `Esc` shortcut); 4 stepper pills (active 20 pt wide / inactive 6 pt wide, 5 pt tall) |
| Footer CTA | `Continue` on steps 0-2, `Get Started` on step 3 (default action key) |
| Transition debounce | 300 ms lock (`isTransitioning`) after each step change; spring(0.34, 0.82), opacity-only when Reduce Motion |
| Welcome copy | Hero `Your services,\none command away.`; subtitle `Orchestrate your local dev services and tunnels effortlessly on macOS without the terminal clutter.`; tags `Unified Control` (`command`), `Native` (`swift`), `Encrypted` (`lock.fill`) |
| Step 1 copy | Title `Containers & Clusters`; subtitle `CLI tools detected on your system. Only configure what you need.`; Re-scan accessibility label `Re-scan Containers and Clusters` |
| Step 2 copy | Title `Public Tunneling`; subtitle `Optional utilities to expose local services to the internet.`; Re-scan accessibility label `Re-scan Public Tunneling tools` |
| Step 3 copy | Checkmark icon `checkmark.circle.fill`; title `You're all set.`; subtitle `Kuma is ready to orchestrate your services.` |
| Re-scan link | Label `Re-scan` (icon `arrow.clockwise`), changes to `Scanning…` and disables while scanning |
| Row states | scanning: spinner and text `Checking PATH…`; found: path text (single line, middle truncation) and `Ready` with green check; missing: `Not detected` and a `Browse` button (accessibility `Browse executable for <name>`); a row with a non-empty `path` or `isInstalled` shows `Ready` |
| Browse filters | kubeconfig row: plain text, `yaml`, `yml`; others: `unixExecutable`, `executable` |
| Error alert | Title `Invalid Binary Selection`, message = the validation error, button `OK`; dismissing clears `pathValidationError` |
| Scan scheduling | On wizard appear and on step 1/2 appear call `scanDependenciesIfNeeded()` (no-op after the first scan); `Re-scan` forces a scan with an extra 200 ms sleep for tactile feedback; a new scan cancels the previous one; the result of a cancelled scan is discarded |
| Non-blocking | Navigation is allowed with zero dependencies installed |

Wizard steps, copy, animation and the 200 ms/300 ms timers are **[CLIENT]**; they are not part of the daemon.

### 3.10 Environment

#### 3.10.1 Process facts

| Fact | Definition |
|------|-----------|
| `home()` | `$HOME` if set, non-empty and absolute; else the passwd home directory. Used for tilde expansion and for the `~`-based directories in 3.10.2 (1.x: `NSHomeDirectory()`) |
| `realHome()` = `userHomePath()` | `getpwuid(getuid())->pw_dir` as a string; if unavailable, `home()` (`DependencyChecker.swift:109-113`). Used **only** for the default kubeconfig file path (3.10.7) and by the kubeconfig UI's tilde display |
| `expandTilde(p)` | `~` -> `home()`; `~/x` -> `home()/x`; `~user`/`~user/x` -> that user's passwd home when the user exists, else unchanged; any other string unchanged (1.x: `NSString.expandingTildeInPath`) |
| `isExecutableFile(p)` (resolver) | `p` exists, following symlinks, is **not** a directory, and `access(p, X_OK) == 0` (`EnvironmentPathResolver.swift:194-200`). A broken symlink is therefore "not found" |
| `trim(s)` | strip leading/trailing whitespace and newlines |

#### 3.10.2 PATH resolution (`EnvironmentPathResolver`)

`resolvePath()` returns the cached string if present; otherwise computes it as follows and caches it for the life of the process (until `env.refresh`).

**Step A: sniff.** (`EnvironmentPathResolver.swift:105-152`)

1. `shell` = env `SHELL`; if unset use `/bin/zsh`. (**DEV-43:** if `SHELL` is unset or empty use the passwd `pw_shell` before `/bin/zsh`, because a LaunchAgent has no `SHELL`.)
2. If `shell` is not an executable file (`FileManager.isExecutableFile`) use `/bin/zsh`.
3. `isFish` = last path component of the chosen shell **equals** `fish` (case-sensitive here; contrast 3.10.8 which lowercases).
4. Run the shell **non-login, non-interactive** (no `-l`, no `-i`):

| Shell | Argument vector |
|-------|-----------------|
| fish | `["-c", "echo $PATH"]` |
| anything else (zsh, bash, sh, ...) | `["-c", B]` with `B` below |

```
[ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; echo $PATH
```

5. Capture stdout (stderr captured and discarded). Wait for exit; exit status is **ignored**. **DEV-41:** stdin is `/dev/null` and the sniff is killed after 10 s; a timeout counts as failure.
6. Decode stdout as UTF-8, `trim` it. If non-empty: for fish replace every ASCII space with `:`; return it. (The whole trimmed stdout is used, including any rc-file noise or extra lines; see residual risk R1.)
7. On spawn failure, undecodable output, or empty output: return env `PATH` of the daemon process, or `""` if unset.

**Step B: combine** (`combinePaths`, lines 154-172). Build an ordered list with exact-string de-duplication. Each candidate is `trim`med; empty candidates and already-seen strings are skipped.

Order:
1. `customPaths` (always empty in 1.x; no RPC sets it)
2. components of the sniffed string, split on `:` with empty subsequences omitted
3. discovered tool directories (below)
4. the fallback list (below)

Result = the list joined with `:`.

**Discovered tool directories** (`discoverNodeAndToolDirectories`, lines 174-192), in order:

1. For every entry `E` of `home()/.nvm/versions/node` (all directory entries, hidden ones included, files included; if the directory is unreadable or absent, none): `home()/.nvm/versions/node/E/bin`. Entries are processed in **ascending byte-wise name order** (1.x order was the unspecified `FileManager` order; see R2).
2. `home()/Library/pnpm`
3. `home()/.bun/bin`
4. `home()/go/bin`

**Fallback directories** (static list, computed once per process, lines 15-28), in order:

| # | Directory |
|---|-----------|
| 1 | `/opt/homebrew/bin` |
| 2 | `/opt/homebrew/sbin` |
| 3 | `/usr/local/bin` |
| 4 | `/usr/local/sbin` |
| 5 | `/usr/bin` |
| 6 | `/bin` |
| 7 | `/usr/sbin` |
| 8 | `/sbin` |
| 9 | `home()/.rd/bin` |
| 10 | `home()/.nvm/versions/node/current/bin` |
| 11 | `home()/.cargo/bin` |
| 12 | `home()/.local/bin` |

**Concurrency.** The computation is serialized (1.x: an actor); concurrent callers wait for the single in-flight sniff and share its result.

**Refresh.** `env.refresh` clears the cache, recomputes (steps A and B) and returns the new PATH (`refreshPath`, lines 91-95). Nothing else invalidates the cache (changing `SHELL`, installing a tool, or editing `~/.zshrc` has no effect until `env.refresh` or daemon restart). `setCustomPaths` also clears the cache but is not exposed (3.10.9).

Consumers of the resolved PATH: script runner (`env["PATH"] = resolvePath()` for child processes, `ShellRunner.swift:31-33`, [06](06-execution-engine.md)), `env.resolve_executable`, dependency scan.

#### 3.10.3 `resolveExecutablePath(binaryOrPath)` (`EnvironmentPathResolver.swift:50-88`)

1. `t = trim(input)`; empty -> `null`.
2. If `t` starts with `/`: `isExecutableFile(t)` ? return `t` : `null`. **No PATH search.** The returned string is `t` unchanged (not canonicalized, symlinks not resolved).
3. Else if `t` starts with `~`: `p = expandTilde(t)`; `isExecutableFile(p)` ? return `p` : `null`.
4. Else: for each component `d` of `resolvePath()` split on `:` (empty omitted): `c = expandTilde(d) + "/" + t` (path join; a duplicate slash is collapsed); first `c` with `isExecutableFile(c)` is returned.
5. Not found: log warn `Failed to locate executable for binary: <t>` and return `null`.

#### 3.10.4 `validateCustomBinary(path, expectedCommand)` (`DependencyChecker.swift:59-88`)

Pure filesystem checks. It MUST NOT spawn any process (zero latency; INV-D-SET-13).

| Step | Condition | Result |
|------|-----------|--------|
| 1 | `t = trim(path)` empty | `empty` |
| 2 | `n = expandTilde(t)`; `n` does not exist (`fileExists`, following symlinks) | `fileNotFound` |
| 3 | `n` is a directory | `notExecutable` |
| 4 | `access(n, X_OK) != 0` | `notExecutable` |
| 5 | `lower(basename(n))` does **not contain** `lower(expectedCommand)` as a substring | `nameMismatch(expected: expectedCommand, actual: basename(n))` (original case in both) |
| 6 | otherwise | `valid(path: n)` (the tilde-expanded path; symlinks are not resolved) |

Name rule: containment, not equality or prefix (`kubectl-1.29`, `docker-desktop`, `my-ngrok` all pass; the check is applied to the symlink's own name, not its target).

Messages (`BinaryValidationResult.errorMessage`, `DependencyChecker.swift:41-52`), exact:

| Result | `isValid` | Message |
|--------|-----------|---------|
| `empty` | false | `null` |
| `valid` | true | `null` |
| `fileNotFound` | false | `File does not exist at specified path` |
| `notExecutable` | false | `File is not an executable binary` |
| `nameMismatch(expected, actual)` | false | `Selected file '<actual>' does not match expected '<expected>' binary` |

Kubeconfig field check (Settings, `SettingsCLIToolsSection.swift:22-30`): blank after trim -> no error; `expandTilde(trimmed)` does not exist -> `Configuration file does not exist at specified path`; otherwise no error. Existing directories pass (1.x only checks existence).

#### 3.10.5 `DependencyChecker` function-by-function

| 1.x function | Daemon equivalent |
|--------------|-------------------|
| `validateCustomBinary` | 3.10.4 / `env.validate_binary` |
| `isCommandInstalled(command, customPath)` | `resolvedPath(...) != null` (dead in 1.x; used inside `env.dependencies`) |
| `resolvedPath(for:customPath:)` (`:96-106`) | 3.10.6 step 1 |
| `userHomePath()` | `realHome()` (3.10.1) |
| `standardKubeconfigFilePath()` (`:117-119`) | `realHome() + "/.kube/config"` (file may not exist) |
| `isKubeconfigPresent(customPath)` | `resolvedKubeconfigPath(customPath) != null` |
| `resolvedKubeconfigPath(customPath)` (`:127-148`) | 3.10.7 |
| `checkAll(...)` / `DependencyStatus` | the `status` object of `env.dependencies` (4.5); five tool resolutions run concurrently, kubeconfig synchronously |

**`resolvedPath(command, customPath)`** exact rule (`DependencyChecker.swift:96-106`):

1. If `customPath` is non-blank after trim: `p = expandTilde(customPath)`; if `p` exists **and** `access(p, X_OK)` -> return `p`, **else return `null`. There is no fallback to PATH when a non-blank override is set and invalid.** DEV-40: additionally `null` if `p` is a directory (1.x let a directory with the x-bit through).
2. Otherwise return `resolveExecutablePath(command)` (3.10.3).

#### 3.10.6 Settings-driven executable resolution (`KumaSettingsExecutableResolver`)

`resolve(command, settingsKey)` = `resolvedPath(command, customPath: string(settingsKey))` (`KumaSettingsExecutableResolver.swift:5-8`). Mapping:

| Command | Primary key | Legacy key (DEV-02) | 1.x callers (specs that consume it) |
|---------|-------------|---------------------|-------------------------------------|
| `kubectl` | `kuma.settings.customKubectlPath` | `kuma.custom_kubectl_path` | `KubernetesRunner`, `KubeConnectionValidator`, `ServiceInspectorViewModel+Validation`, `LiveLogSourceRunner` ([06](06-execution-engine.md), [07](07-kubernetes.md), [05](05-providers-and-validation.md), [08](08-logs-and-events.md)) |
| `docker` | `kuma.settings.customDockerPath` | `kuma.custom_docker_path` | `ContainerRunner` (twice), `LiveLogSourceRunner` |
| `podman` | `kuma.settings.customPodmanPath` | `kuma.custom_podman_path` | same |
| `cloudflared` | `kuma.settings.cloudflaredPath` | `kuma.custom_cloudflared_path` | `TunnelRunner` |
| `ngrok` | `kuma.settings.customNgrokPath` | `kuma.custom_ngrok_path` | `TunnelRunner` |

**DEV-02.** 1.x called `KumaSettingsKey.string(forKey: settingsKey)` **without** a fallback key, so runtime ignored legacy keys even though the Settings UI and onboarding scan displayed them (`KumaSettingsKey.string(primary, fallbackKey: legacy)`). The daemon uses `string(primary, legacy)` (3.3.1) everywhere, so what the UI/`env.dependencies` shows is what is executed. `env.resolve_executable` with `applySettings: true` and every internal runner use this one function.

#### 3.10.7 Kubeconfig default path (path part only; records and parsing are [07](07-kubernetes.md))

`resolvedKubeconfigPath(customPath)` (`DependencyChecker.swift:127-148`):

1. `customPath` non-blank (after trim): `p = expandTilde(customPath)`; if `p` exists (any file type) return `p`. If it does not exist, **continue** (do not fail).
2. If env `KUBECONFIG` of the **daemon process** is non-empty: split on `:` (empty subsequences omitted); for each element `expandTilde(e)`; the **first that exists** is returned. (kubectl would merge all; Kuma uses only the first existing.)
3. `d = realHome() + "/.kube/config"`; if it exists return `d`.
4. Return `null`.

`customPath` for the default kubeconfig is always `string(customKubeconfigPath, legacy kuma.custom_kubeconfig_path)` (`KubeConfigMaterializer.swift:21-27`, `KubeConfigExecutionResolver.swift:47-53`, `KubeConfigViewModel.swift:55-61,154-160`). Callers in [07](07-kubernetes.md): the virtual Default kubeconfig resolves its file with this function; its displayed `sourceFilePath` is `resolved ?? standardKubeconfigFilePath()` (the standard path even when it does not exist, `KubeConfigViewModel.swift:83-89`). This spec exposes the result as `env.dependencies[kubeconfig].resolvedPath` and as the internal function `resolved_kubeconfig_path()`.

#### 3.10.8 Shell launch recipe (`KumaShellLaunchConfiguration`, used by the script runner)

**`validatedShellPath`** (`KumaShellLaunchConfiguration.swift:7-14`): `configured` = stored `defaultShell` string (no trim, no legacy) or `/bin/zsh` when absent; `expanded = expandTilde(configured)`; if `access(expanded, X_OK) == 0` (and, DEV-40, not a directory) return `expanded`; else return `/bin/zsh`. The fallback is silent (e.g. `/opt/homebrew/bin/fish` on an Intel Mac without fish runs zsh).

**`launchSpec(runCommand)`** (`:16-36`): `shellPath = validatedShellPath()`; `shellName = lower(basename(shellPath))`.

| `shellName` | executable | arguments |
|-------------|-----------|-----------|
| `fish` | `shellPath` | `["-c", "eval $argv[1]", "--", runCommand]` |
| `bash` | `shellPath` | `["-c", BASH, "--", runCommand]` |
| any other (`zsh`, `sh`, `dash`, `ksh`, ...) | `shellPath` | `["-c", ZSH, "--", runCommand]` |

`TRAP` (verbatim):

```
trap 'kill -TERM 0 2>/dev/null || true' EXIT INT TERM
```

`BASH` (verbatim, one line):

```
[ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; [ -f ~/.bashrc ] && source ~/.bashrc 2>/dev/null; trap 'kill -TERM 0 2>/dev/null || true' EXIT INT TERM; eval "$1"
```

`ZSH` (verbatim, one line):

```
[ -f ~/.zprofile ] && source ~/.zprofile 2>/dev/null; [ -f ~/.zshrc ] && source ~/.zshrc 2>/dev/null; [ -f ~/.bash_profile ] && source ~/.bash_profile 2>/dev/null; trap 'kill -TERM 0 2>/dev/null || true' EXIT INT TERM; eval "$1"
```

Notes: `$0` is `--`, `$1` is the user's command (the `eval "$1"` receives it as data, never interpolated into the bootstrap). The fish recipe has **no** teardown trap and does not source any rc file (fish reads its own config). The `kill -TERM 0` trap signals the shell's own process group on exit/INT/TERM; spec [06](06-execution-engine.md) owns process-group setup, working directory, env (PATH from 3.10.2) and stop escalation.

#### 3.10.9 Dead 1.x environment surface

| Item | Decision |
|------|----------|
| `EnvironmentPathResolver.setCustomPaths(_:)` | Not exposed. The daemon keeps `customPaths = []` internally so the combine order is unchanged. `env.path` reports `customPaths: []`. |
| `DependencyChecker.isCommandInstalled`, `checkAll`, `DependencyStatus` | Folded into `env.dependencies.status`. |
| `KumaSettingsKey.integer` | Not implemented. |
| `BinaryStatusBadge` | [CLIENT] preview only. |

### 3.11 Dependency scan (`env.dependencies`) and onboarding path setting

**3.11.1 Scan algorithm** (`OnboardingViewModel.swift:45-181`). `env.dependencies` takes no parameters (it never refreshes the PATH cache; clients call `env.refresh` first when a rescan must see new PATH entries; 1.x "Re-scan" did **not** refresh PATH either).

1. For each of the six settings keys read `custom = string(primary, legacy)` (3.3.1; the scan already honored legacy keys in 1.x).
2. Concurrently resolve `kubectl`, `docker`, `podman`, `cloudflared`, `ngrok` with `resolvedPath(command, customPath: custom)` (3.10.5).
3. `isKubeconfigPresent = resolvedKubeconfigPath(customPath: customKubeconfig) != null`.
4. Build the six dependency records of table 4.4 in this order: engines `kubectl`, `kubeconfig`, `docker`, `podman`; tunneling `cloudflared`, `ngrok`.

**3.11.2 Record contents** (exact strings):

| id | name | iconName | category | description | settingsKey | isInstalled | path |
|----|------|----------|----------|-------------|-------------|-------------|------|
| `kubectl` | `Kubernetes CLI (kubectl)` | `network` | `engine` | `Enables Kubernetes provider` | `kuma.settings.customKubectlPath` | resolved != null | resolved or `null` |
| `kubeconfig` | `Kubeconfig File` | `doc.text.fill` | `engine` | `Cluster configuration for Kubernetes` | `kuma.settings.customKubeconfigPath` | `isKubeconfigPresent` | if present: `custom` if a custom value is set (even when that file does not exist and `$KUBECONFIG`/default made it present), else the literal `~/.kube/config`; if not present `null` |
| `docker` | `Docker Engine` | `shippingbox.fill` | `engine` | `Enables Docker provider` | `kuma.settings.customDockerPath` | resolved != null | resolved or `null` |
| `podman` | `Podman Engine` | `cylinder.split.1x2.fill` | `engine` | `Enables Podman provider` | `kuma.settings.customPodmanPath` | resolved != null | resolved or `null` |
| `cloudflared` | `Cloudflare Tunnel (cloudflared)` | `cloud.bolt.fill` | `tunneling` | `Enables Tunnel via Cloudflare` | `kuma.settings.cloudflaredPath` | resolved != null | resolved or `null` |
| `ngrok` | `ngrok Tunnel` | `globe` | `tunneling` | `Enables Tunnel via ngrok` | `kuma.settings.customNgrokPath` | resolved != null | resolved or `null` |

`version` is always `null` in 1.x (never populated). The daemon adds `resolvedPath` (V2-ADD field): for binaries equal to `path`; for `kubeconfig` the real `resolvedKubeconfigPath(...)` result (not the display literal). `settingsKey` is always the **primary** key even when the value came from the legacy key.

**3.11.3 Wizard behavior mapped to daemon calls.**

| Wizard action ([CLIENT] flow) | Daemon calls |
|-------------------------------|--------------|
| Pre-scan on appear / `scanDependenciesIfNeeded()` | `env.dependencies` (client guards "only once" with `hasInitialScanned`) |
| Re-scan | `env.dependencies` (client adds the 200 ms delay; optional `env.refresh` first is a V2 choice) |
| Browse + pick path `P` for dependency `D` | `settings.set { values: { D.settingsKey: P }, strict: true }`. On `KUMA_SET_PATH_INVALID` the client shows the alert with the error message; nothing is persisted and **no re-scan** (1.x). On success the client re-scans. |
| Browse + empty path | `settings.set { values: { key: "" }, strict: true }` then re-scan (stores `""`, 1.x parity; DEV-44 makes the legacy key vanish too) |
| "Get Started" | `settings.set { values: { "kuma.has_completed_onboarding": true } }` |

In 1.x the validation `expectedCommand` for a dependency is its `id` (`DependencyChecker.validateCustomBinary(path:expectedCommand: dependency.id)`), identical to the strict-mode table in 3.4.4.

### 3.12 Linux and portable notes (short)

- **Home and user**: use `getpwuid` as on macOS; `$HOME` rules unchanged.
- **PATH sniff**: identical algorithm; `$SHELL` or passwd shell; rc files sourced by the macOS bootstrap are still the ones listed (users on Linux bash get `~/.bash_profile` and `~/.bashrc` only through the `bash` branch of 3.10.8, but the **sniff** uses the zsh-style bootstrap for every non-fish shell, as in 1.x).
- **Fallback list** stays as in 3.10.2 (macOS-only entries simply do not exist). A Linux build MAY append extra directories (`/snap/bin`, `/home/linuxbrew/.linuxbrew/bin`, `home()/.local/share/pnpm`) **after** entry 12; they MUST NOT precede any listed entry.
- **Legacy import**: skipped (no plist); `legacyImportDone` still written.
- **Tool names** keep the macOS names; `.exe` suffixes (Windows) are out of scope.
- **Launch at login / appearance / notifications UI**: client concerns.

---

## 4. Data shapes

JSON is camelCase; enum values are the exact raw strings.

### 4.1 `Setting` (item of `settings.list`/`get`, `settings.set.updated`)

| Field | Type | Optional | Default | JSON key | Notes |
|-------|------|----------|---------|----------|-------|
| key | string | no | - | `key` | exact key |
| type | `"bool"\|"string"\|"stringArray"\|"enum"\|"any"` | no | - | `type` | registry type |
| enumValues | string[] | yes | omitted | `enumValues` | for enum keys |
| interpreter | `"daemon"\|"client"\|"internal"\|"none"` | no | - | `interpreter` | table 3.2 column Interp. (D=`daemon`, C=`client`, D-int=`internal`, dead=`none`; key 15 is `daemon`) |
| stored | JSON \| null | no | `null` | `stored` | raw row value (typed), `null` when absent |
| effective | JSON \| null | no | - | `effective` | 3.3.4 |
| default | JSON \| null | no | - | `default` | default when absent (for 6 and 4 and 17-26: `null`) |
| source | `"stored"\|"legacy"\|"default"` | no | - | `source` | 3.3.4 |
| updatedAt | string \| null | no | `null` | `updatedAt` | row timestamp |

### 4.2 `settings.set` / `settings.reset`

| Request field | Type | Optional | Default | JSON key |
|---------------|------|----------|---------|----------|
| values | object key -> JSON (`null` deletes) | no | - | `values` |
| strict | bool | yes | `false` | `strict` |
| expectedUpdatedAt | object key -> string \| null | yes | omitted | `expectedUpdatedAt` |

| Result field | Type | JSON key |
|--------------|------|----------|
| updated | `Setting[]` | `updated` |
| removed | string[] | `removed` |
| validation | object key -> `Validation` | `validation` |

`settings.reset` request: no parameters. Result: `{ "removed": string[], "keys": string[22] }`.

### 4.3 `Validation` (`env.validate_binary` result; entry of `settings.set.validation`)

| Field | Type | Optional | JSON key | Notes |
|-------|------|----------|----------|-------|
| status | `"empty"\|"valid"\|"fileNotFound"\|"notExecutable"\|"nameMismatch"` | no | `status` | raw names of `BinaryValidationResult` cases |
| isValid | bool | no | `isValid` | `status == "valid"` |
| errorMessage | string \| null | no | `errorMessage` | 3.10.4 (for kubeconfig: `Configuration file does not exist at specified path`) |
| code | string \| null | no | `code` | `null`, `KUMA_ENV_FILE_NOT_FOUND`, `KUMA_ENV_NOT_EXECUTABLE`, `KUMA_ENV_NAME_MISMATCH`, `KUMA_ENV_KUBECONFIG_NOT_FOUND` |
| path | string \| null | no | `path` | expanded path when `valid` |
| expected | string \| null | no | `expected` | only for `nameMismatch` |
| actual | string \| null | no | `actual` | only for `nameMismatch` |

`env.validate_binary` params: `path` (string, required), `expectedCommand` (string, required).

### 4.4 `env.dependencies` result

```json
{
  "engines":   [ SystemDependency, SystemDependency, SystemDependency, SystemDependency ],
  "tunneling": [ SystemDependency, SystemDependency ],
  "status": { "kubectlInstalled": true, "kubeconfigExists": true, "dockerInstalled": false,
              "podmanInstalled": false, "cloudflaredInstalled": false, "ngrokInstalled": false }
}
```

`SystemDependency`:

| Field | Type | Optional | JSON key |
|-------|------|----------|----------|
| id | string | no | `id` |
| name | string | no | `name` |
| iconName | string | no | `iconName` |
| isInstalled | bool | no | `isInstalled` |
| path | string \| null | no | `path` |
| resolvedPath | string \| null | no | `resolvedPath` (V2-ADD) |
| version | string \| null | no | `version` (always `null`) |
| category | `"engine"\|"tunneling"` | no | `category` |
| description | string | no | `description` |
| settingsKey | string | no | `settingsKey` |

`status` booleans equal the six `isInstalled` values (`kubeconfigExists` = kubeconfig `isInstalled`).

### 4.5 `env.path`, `env.refresh`, `env.resolve_executable`

`env.path` params: none. Result:

| Field | Type | JSON key | Notes |
|-------|------|----------|-------|
| path | string | `path` | final colon-joined string |
| directories | `{ dir: string, source: "custom"\|"shell"\|"processEnv"\|"discovered"\|"fallback" }[]` | `directories` | same order as `path`; `shell` = from a successful sniff, `processEnv` = from the failure fallback |
| shell | `{ path: string, kind: "fish"\|"posix", sniffOk: bool }` | `shell` | shell actually used for the sniff |
| customPaths | string[] | `customPaths` | always `[]` |
| cached | bool | `cached` | `true` if served from cache |

`env.refresh`: no parameters; result is the `env.path` object after recomputation (`cached: false`).

`env.resolve_executable` params:

| Param | Type | Optional | Default | Meaning |
|-------|------|----------|---------|---------|
| command | string | no | - | name, absolute path, or `~` path |
| customPath | string | yes | omitted | if non-blank apply `resolvedPath` custom rule (3.10.5 step 1) |
| applySettings | bool | yes | `false` | when `true` and `command` is one of the five tools and `customPath` is blank, apply 3.10.6 (settings override with legacy fallback) |

Result: `{ "command": string, "path": string|null, "source": "custom"|"settings"|"absolute"|"tilde"|"path"|null }` (`source` `null` iff `path` is `null`). A blank `command` returns `path: null` (not an error, 1.x returned `nil`).

### 4.6 `settings.changed` event payload

| Field | Type | JSON key |
|-------|------|----------|
| keys | string[] | `keys` |
| reason | `"set"\|"reset"\|"import"` | `reason` |
| values | object key -> effective JSON | `values` (omitted for `reset`; for `set` the effective value after the write, `null` for deleted keys) |

`reason: "import"` is emitted by `data.import` only if [09](09-dataport.md) decides settings are part of a backup (1.x backups do not contain settings); this spec reserves the value. The legacy import (3.8) emits no event.

### 4.7 Constants

| Name | Value | Source |
|------|-------|--------|
| Bundle id | `com.kuma.Kuma` | `project.pbxproj` |
| Plist path | `~/Library/Preferences/com.kuma.Kuma.plist` | derived (non-sandboxed) |
| Fallback shell | `/bin/zsh` | `KumaShellLaunchConfiguration.swift:5`, `EnvironmentPathResolver.swift:106` |
| Sniff timeout | 10 s | DEV-41 (1.x: none) |
| `client.*` max value size | 65536 bytes | V2-ADD |
| Onboarding steps | 4 | `OnboardingViewModel.swift:20` |
| Manual re-scan delay | 200 ms | `OnboardingViewModel.swift:100-103` ([CLIENT]) |
| Step transition lock | 300 ms | `OnboardingWizardView.swift:89-95` ([CLIENT]) |
| Port conflict kill wait | 200 ms | `LocalPortConflictResolver.swift:61` ([06](06-execution-engine.md)) |
| Auto-resume start gap | 150 ms | `ServicesDeckViewModel+WorkspaceLoad.swift:74` ([14](14-lifecycle-and-platform.md)) |

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|-----------|-------------|
| FEAT-SET-01 | [PARITY] | Settings KV store with all 26 registered keys, typed read with defaults, legacy fallbacks, `source` reporting | `KumaSettingsKey.swift`, `SettingsViewModel.swift:128-188` | `settings.list`, `settings.get` |
| FEAT-SET-02 | [PARITY] | Atomic validated write (`settings.set`): type/enum coercion, `null` deletes, trim of path values, legacy-key cleanup, `settings.changed` | `SettingsViewModel.swift:56-125` | `settings.set` |
| FEAT-SET-03 | [V2-ADD] | `settings.changed` event | - | (event) |
| FEAT-SET-04 | [PARITY] | Reset Settings to Default: delete exact 22 keys, DB untouched | `SettingsViewModel.swift:244-291` | `settings.reset` |
| FEAT-SET-05 | [CLIENT] | Reset Settings confirmation dialog and success alert copy; re-apply launch-at-login and appearance on reset | `SettingsDataSection.swift:126-139` | - |
| FEAT-SET-06 | [CLIENT] | Launch at Login toggle (`kuma.settings.launchAtLogin`, SMAppService register/unregister) | `SettingsViewModel.swift:58-62,192-202` | `settings.get`, `settings.set` |
| FEAT-SET-07 | [PARITY] | Auto-start Services setting (`autoResumeServices`) and `activeServiceIDsBeforeQuit` snapshot semantics | `ServicesDeckViewModel+WorkspaceLoad.swift:39-77`, `AppDelegate.swift:135-141` | `settings.get`, `settings.set` |
| FEAT-SET-08 | [PARITY] | Notify on Service Failure setting (default true, legacy `notifyOnCrash` fallback, write deletes legacy) | `SettingsViewModel.swift:113-119,177-182`, `ExecutionSupervisor.swift:283-289` | `settings.get`, `settings.set` |
| FEAT-SET-09 | [CLIENT] | Notification permission request flow and permission alert | `SettingsViewModel.swift:218-240`, `SettingsGeneralSection.swift` | `settings.set` |
| FEAT-SET-10 | [CLIENT] | Confirm Before Quitting toggle and quit dialog (title, text, three buttons, "Remember this choice") | `AppDelegate.swift:39-103`, `SettingsGeneralSection.swift:44-50` | `settings.get`, `settings.set` |
| FEAT-SET-11 | [CLIENT] | Saved Quit Preference row and Reset button (`quitBehavior` delete) | `SettingsGeneralSection.swift:52-66` | `settings.set` |
| FEAT-SET-12 | [PARITY] | `quitBehavior` key (`ask`/`stopAll`/`quitAnyway`) storage and invalid-as-ask rule | `AppDelegate.swift:10-13,51-53` | `settings.get`, `settings.set` |
| FEAT-SET-13 | [CLIENT] | Appearance setting (`system`/`light`/`dark`), cards, `NSApp.appearance` mapping | `SettingsAppearanceSection.swift`, `AppearanceCard.swift`, `SettingsViewModel.swift:204-213` | `settings.get`, `settings.set` |
| FEAT-SET-14 | [PARITY] | Default Shell setting and shell validation fallback | `SettingsCLIToolsSection.swift:121-129`, `KumaShellLaunchConfiguration.swift:7-14` | `settings.get`, `settings.set` |
| FEAT-SET-15 | [PARITY] | Shell launch recipe (fish/bash/zsh bootstrap strings, teardown trap) | `KumaShellLaunchConfiguration.swift:16-36` | (internal, used by [06](06-execution-engine.md)) |
| FEAT-SET-16 | [PARITY] | kubectl path override | `SettingsCLIToolsSection.swift:46-61` | `settings.get`, `settings.set`, `env.resolve_executable` |
| FEAT-SET-17 | [PARITY] | Default kubeconfig path override | `SettingsCLIToolsSection.swift:66-79` | `settings.get`, `settings.set`, `env.dependencies` |
| FEAT-SET-18 | [PARITY] | Docker path override | `SettingsCLIToolsSection.swift:84-98` | `settings.get`, `settings.set`, `env.resolve_executable` |
| FEAT-SET-19 | [PARITY] | Podman path override | `SettingsCLIToolsSection.swift:103-117` | `settings.get`, `settings.set`, `env.resolve_executable` |
| FEAT-SET-20 | [PARITY] | cloudflared path override | `SettingsTunnelingToolsSection.swift:31-46` | `settings.get`, `settings.set`, `env.resolve_executable` |
| FEAT-SET-21 | [PARITY] | ngrok path override | `SettingsTunnelingToolsSection.swift:50-64` | `settings.get`, `settings.set`, `env.resolve_executable` |
| FEAT-SET-22 | [PARITY] | Port Conflict Action setting (`warn_and_block`/`kill_existing`) | `SettingsPortsConnectionsSection.swift`, `PortConflictMessaging.swift:30-34` | `settings.get`, `settings.set` |
| FEAT-SET-23 | [PARITY] | Custom-binary validation (`validateCustomBinary`, exact messages, name-contains rule) | `DependencyChecker.swift:29-88` | `env.validate_binary`, `settings.set` |
| FEAT-SET-24 | [PARITY] | Kubeconfig field validation message | `SettingsCLIToolsSection.swift:22-30` | `settings.set` (validation) |
| FEAT-SET-25 | [V2-ADD] | Strict path persistence (onboarding semantics: reject invalid, persist nothing) | `OnboardingViewModel.swift:186-219` | `settings.set` (`strict`) |
| FEAT-SET-26 | [CLIENT] | Auto-fill of detected tool paths into blank fields and "Not detected" placeholders | `SettingsCLIToolsSection.swift:135-163`, `SettingsTunnelingToolsSection.swift:74-89` | `env.resolve_executable`, `env.dependencies`, `settings.set` |
| FEAT-SET-27 | [CLIENT] | `BinaryStatusBadge` (`Available`/`Not Found`), preview-only in 1.x | `BinaryStatusBadge.swift` | - |
| FEAT-SET-28 | [PARITY] | Login-shell PATH resolution (shell sniff, fish handling, combine order, nvm/pnpm/bun/go dirs, fallback list, cache) | `EnvironmentPathResolver.swift:36-45,105-192` | `env.path` |
| FEAT-SET-29 | [PARITY] | PATH cache refresh | `EnvironmentPathResolver.swift:91-95` | `env.refresh` |
| FEAT-SET-30 | [PARITY] | Executable resolution (absolute, tilde, PATH search) | `EnvironmentPathResolver.swift:50-88` | `env.resolve_executable` |
| FEAT-SET-31 | [PARITY] | Settings-driven tool resolution with legacy keys honored (DEV-02) | `KumaSettingsExecutableResolver.swift`, `DependencyChecker.swift:96-106` | `env.resolve_executable` |
| FEAT-SET-32 | [PARITY] | Default kubeconfig path resolution (custom, first existing `$KUBECONFIG`, `~/.kube/config`) | `DependencyChecker.swift:117-148` | `env.dependencies` |
| FEAT-SET-33 | [PARITY] | Real-home resolution via `getpwuid` | `DependencyChecker.swift:109-113` | `env.dependencies` (indirect) |
| FEAT-SET-34 | [PARITY] | Dependency scan (6 records, strings, statuses, `status` summary) | `OnboardingViewModel.swift:45-181`, `DependencyChecker.swift:152-175` | `env.dependencies` |
| FEAT-SET-35 | [CLIENT] | Onboarding wizard flow (4 steps, stepper, CTA labels, copy, transitions, alert, re-scan UX) | `OnboardingWizardView.swift`, `Steps/*`, `DependencyStatusRowView.swift` | `env.dependencies`, `env.refresh` |
| FEAT-SET-36 | [PARITY] | Onboarding completion flag semantics (phase at launch, written true on Get Started, false on re-show/reset) | `AppCoordinator.swift`, `KumaCommands.swift:53-58` | `settings.get`, `settings.set` |
| FEAT-SET-37 | [CLIENT] | Help menu "show onboarding again" and onboarding window routing | `KumaCommands.swift:53-58`, `ContentView.swift:85-93` | `settings.set` |
| FEAT-SET-38 | [V2-ADD] | Legacy UserDefaults import at first start (ADD-09), idempotent via `meta.legacyImportDone` | - | (startup) `settings.list` |
| FEAT-SET-39 | [V2-ADD] | `client.*` opaque client preference namespace | - | `settings.get`, `settings.set`, `settings.list` |
| FEAT-SET-40 | [CLIENT] | Selected workspace persistence (`kuma.selectedWorkspaceId.storage`) | `WorkspaceStore.swift:9-20,51-60` | `settings.get`, `settings.set` |
| FEAT-SET-41 | [PARITY] | Dead keys `logRetentionLimit`, `clearLogsOnSwitch` accepted, stored, removed by reset | `KumaSettingsKey.swift:33-34`, `SettingsViewModel.swift:260-261` | `settings.set`, `settings.reset` |
| FEAT-SET-42 | [CLIENT] | Settings screen layout, section titles, footer version string | `SettingsView.swift`, `SettingsGeneralSection.swift`, other sections | - |
| FEAT-SET-43 | [PARITY] | `portConflictPolicy` / `notifyOnServiceFailure` / `autoResumeServices` read-at-use contract (live reads) | `LocalPortConflictResolver.swift`, `ExecutionSupervisor.swift` | `settings.set` |

Note: the Data section rows (Export Backup, Import Backup, Reset All Data) belong to [09](09-dataport.md) (FEAT-DPT-*).

---

## 6. Error catalog

| Code | Condition | Message |
|------|-----------|---------|
| `KUMA_SET_UNKNOWN_KEY` | key is neither registered nor `client.*` | `Unknown setting key '<key>'` |
| `KUMA_SET_INVALID_TYPE` | value JSON type does not match registry type | `Setting '<key>' expects <bool\|string\|array of UUID strings>` |
| `KUMA_SET_INVALID_VALUE` | enum value not allowed; UUID unparsable | `Invalid value for '<key>': expected one of <v1, v2, ...>` (enum) / `Invalid UUID for '<key>'` |
| `KUMA_SET_VALUE_TOO_LARGE` | `client.*` value text exceeds 65536 bytes | `Value for '<key>' exceeds 65536 bytes` |
| `KUMA_SET_PATH_INVALID` | `strict=true` and a tool-path value fails validation; `details.key`, `details.status` set | one of: `File does not exist at specified path`; `File is not an executable binary`; `Selected file '<actual>' does not match expected '<expected>' binary`; `Selected kubeconfig file does not exist at specified path.` |
| `KUMA_CONFLICT_STALE` | `expectedUpdatedAt` mismatch (defined globally in [00](00-overview-and-conventions.md)) | `Setting '<key>' was modified by another client` |
| `KUMA_ENV_FILE_NOT_FOUND` | `Validation.code` for `fileNotFound` (data, not an RPC error) | `File does not exist at specified path` |
| `KUMA_ENV_NOT_EXECUTABLE` | `Validation.code` for `notExecutable` | `File is not an executable binary` |
| `KUMA_ENV_NAME_MISMATCH` | `Validation.code` for `nameMismatch` | `Selected file '<actual>' does not match expected '<expected>' binary` |
| `KUMA_ENV_KUBECONFIG_NOT_FOUND` | `Validation.code` for the kubeconfig field (data) | `Configuration file does not exist at specified path` |

Notes: `env.validate_binary`, `env.resolve_executable`, `env.path`, `env.refresh` and `env.dependencies` do not fail on bad input (blank or unknown values yield `empty`/`null`); only transport and parameter-shape errors apply ([10](10-rpc-protocol.md)). Onboarding's fallback text `Selected file is not a valid executable binary for <dependency name>.` (`OnboardingViewModel.swift:206`) is unreachable in 1.x (every non-valid non-empty result has a message) and is not implemented.

---

## 7. Deviations

| ID | Summary (full text in [15](15-traceability-and-parity.md)) |
|----|-----------------------------------------------------------|
| DEV-02 | Legacy tool-path keys (`kuma.custom_*_path`) are honored at runtime by every resolver (1.x honored them only in UI and scan) |
| DEV-11 | All 1.x UserDefaults keys live in daemon KV (`daemon-state.sqlite` `settings`, same key names); see [15](15-traceability-and-parity.md) |
| DEV-40 | A custom tool path or default shell that is a directory is rejected (1.x `resolvedPath`/`validatedShellPath` accepted a directory because `isExecutableFile` is true for directories) |
| DEV-41 | PATH shell sniff has stdin `/dev/null` and a 10 s kill timeout, falling back to the daemon's `PATH` (1.x blocked indefinitely) |
| DEV-42 | Tool-path settings are trimmed on write and read (1.x stored raw text, validated trimmed, resolved untrimmed) |
| DEV-43 | When `$SHELL` is unset or empty the passwd shell is used before `/bin/zsh` (a LaunchAgent has no `SHELL`) |
| DEV-44 | Writing or deleting a tool-path setting also deletes its legacy fallback key (1.x: clearing a path with a legacy key present resurrected the legacy value) |

Additions minted here: **ADD-40** `settings.set` `strict` flag (onboarding validate-then-persist semantics); **ADD-41** `KUMA_LEGACY_DEFAULTS_PLIST` override for the legacy import location; **ADD-42** optional `kind: "kubeconfig"` on `env.validate_binary` (see Proposed RPC additions). ADD-09 (legacy import) and DEV-11 are pre-assigned.

---

## 8. Invariants

- **INV-D-SET-01** Defaults: with an empty `settings` table the effective values are exactly: `launchAtLogin=false`, `autoResumeServices=false`, `confirmBeforeQuit=true`, `appearance="system"`, `defaultShell="/bin/zsh"`, all six tool paths `""`, `notifyOnServiceFailure=true`, `portConflictPolicy="warn_and_block"`, `hasCompletedOnboarding=false`, `quitBehavior` effective `"ask"`.
- **INV-D-SET-02** Legacy precedence: a non-blank primary tool-path key always wins over its legacy key; a blank (`""` or whitespace) primary falls through to the legacy key; `notifyOnServiceFailure` present (even `false`) wins over `notifyOnCrash`.
- **INV-D-SET-03** `settings.reset` deletes exactly the 22 keys of 3.6.1 and nothing else; it never touches `kuma.sqlite`, `client.*`, onboarding flag, `quitBehavior`, `activeServiceIDsBeforeQuit`, `selectedWorkspaceId.storage`, or `meta.*`.
- **INV-D-SET-04** Every consumer observes a committed `settings.set` on its next use without daemon restart.
- **INV-D-SET-05** Validation messages are byte-exact per 3.10.4 and 3.4.4.
- **INV-D-SET-06** Legacy import never overwrites an existing row and never modifies the 1.x plist.
- **INV-D-SET-07** `meta.legacyImportDone`, once written, is never removed by any RPC (including `data.factory_reset`); the import runs at most once per `daemon-state.sqlite`.
- **INV-D-SET-08** A non-blank custom tool path that fails `exists && executable && !directory` makes resolution return `null`; it never silently falls back to PATH (so a mistyped override surfaces as "not found" rather than running a different binary).
- **INV-D-SET-09** The PATH list order is custom, sniffed, discovered, fallback, with exact-string de-duplication keeping the first occurrence.
- **INV-D-SET-10** The resolved PATH is cached after first computation and changes only through `env.refresh` or daemon restart; concurrent first calls trigger exactly one sniff process.
- **INV-D-SET-11** No setting holds a secret; settings values may appear in logs and events.
- **INV-D-SET-12** `settings.set` is atomic: either all keys apply and one event fires, or none apply.
- **INV-D-SET-13** `env.validate_binary` and the settings `validation` computation spawn no process and touch no network.
- **INV-D-SET-14** Reading an enum key with an invalid stored value yields the default (`system`, `warn_and_block`, `ask`); it never errors.
- **INV-D-SET-15** `kuma.settings.activeServiceIDsBeforeQuit` values are UPPERCASE UUID strings; consumers ignore non-UUID items.
- **INV-D-SET-16** `validateCustomBinary` name matching is case-insensitive containment of the expected command in the file's base name.

---

## 9. Acceptance tests

| ID | Arrange / Assert |
|----|------------------|
| DT-SET-01 | Fresh DB, `settings.list`: 26 registered keys returned in table order, `stored: null`, `effective` equal INV-D-SET-01, `source: "default"`. |
| DT-SET-02 | `settings.set {kuma.settings.autoResumeServices:true}` then `settings.get`: `effective true`, `source stored`, `updatedAt` non-null; `settings.changed` received once with `keys:[that key]`, `reason:"set"`. |
| DT-SET-03 | `settings.set` bool with `"yes"`, `1`, `"false"`: stored canonical JSON bools; `"maybe"` -> `KUMA_SET_INVALID_TYPE`, nothing written. |
| DT-SET-04 | `portConflictPolicy` `"kill_existing"` accepted; `"KILL_EXISTING"` and `"warn"` -> `KUMA_SET_INVALID_VALUE`. Same for `appearance` (`dark` ok, `Dark` rejected) and `quitBehavior` (`stopAll`,`quitAnyway`,`ask` ok). |
| DT-SET-05 | Batch with one valid and one invalid key: error, the valid key NOT written, no event (atomicity). |
| DT-SET-06 | `settings.set {key:null}` deletes: `settings.get` returns default with `source: "default"`; for `customKubectlPath` the legacy key row is deleted too (DEV-44). |
| DT-SET-07 | Rows `kuma.custom_kubectl_path="/opt/legacy/bin/kubectl"` only: `settings.get customKubectlPath` -> `effective` that value, `source:"legacy"`. Add primary `/usr/local/bin/kubectl` -> primary wins, `source:"stored"`. Primary `"   "` with legacy present -> legacy value. |
| DT-SET-08 | `notifyOnCrash=false` only: `notifyOnServiceFailure.effective == false`, `source:"legacy"`. Write `notifyOnServiceFailure=true`: legacy row deleted, `settings.changed.keys` contains both keys. Primary `false` + legacy `true` -> `false`. |
| DT-SET-09 | Populate all 22 reset keys plus `quitBehavior`, `activeServiceIDsBeforeQuit`, `kuma.has_completed_onboarding`, `kuma.selectedWorkspaceId.storage`, `client.x`; `settings.reset`: the 22 rows gone, the other five untouched, DB tables unchanged, event `reason:"reset"` with exactly 22 keys; effective values equal defaults. |
| DT-SET-10 | `validateCustomBinary`: executable file `kubectl` (0755) -> `valid`, `path` = expanded; non-executable (0644) -> `notExecutable` + `File is not an executable binary`; directory -> `notExecutable`; missing -> `fileNotFound` + `File does not exist at specified path`; blank/whitespace -> `empty`, `errorMessage null`. |
| DT-SET-11 | Executable named `docker` validated against `kubectl` -> `nameMismatch`, message `Selected file 'docker' does not match expected 'kubectl' binary`. Files `kubectl-1.29`, `KUBECTL`, `my-kubectl-wrapper` all `valid` for `kubectl`. |
| DT-SET-12 | Symlink named `docker` -> real executable: `valid`. Broken symlink: `fileNotFound`. Path containing spaces and UTF-8: `valid`. Tilde path `~/bin/kubectl` (file in `$HOME/bin`): `valid`, `path` expanded. Whitespace-padded path (`"  /x/docker \n"`): trimmed, `valid`. |
| DT-SET-13 | `settings.set {customDockerPath:"/nonexistent/docker"}` (non-strict): stored, `validation.status "fileNotFound"`; `env.dependencies` docker `isInstalled false` even though a real docker is on PATH (INV-D-SET-08). |
| DT-SET-14 | Same call with `strict:true`: `KUMA_SET_PATH_INVALID`, message `File does not exist at specified path`, nothing stored, no event. With a docker binary passed for `customKubectlPath` strict: message `Selected file '<name>' does not match expected 'kubectl' binary`. Kubeconfig strict with missing file: `Selected kubeconfig file does not exist at specified path.` Non-strict kubeconfig missing: `validation.errorMessage == "Configuration file does not exist at specified path"`. |
| DT-SET-15 | Strict with `"  ~/bin/kubectl "`: stored value `"~/bin/kubectl"` (trimmed, tilde preserved). Strict with `""`: accepted, stored `""`. |
| DT-SET-16 | `expectedUpdatedAt` stale -> `KUMA_CONFLICT_STALE`, nothing written; `null` expectation on an existing key -> conflict; correct value -> success. |
| DT-SET-17 | `client.view_mode` set to `{"a":1}` then get: round-trips; unknown `foo.bar` -> `KUMA_SET_UNKNOWN_KEY`; 70 KB value -> `KUMA_SET_VALUE_TOO_LARGE`. |
| DT-SET-18 | `activeServiceIDsBeforeQuit` set to lowercase UUIDs: stored UPPERCASE; array containing `"not-a-uuid"` -> `KUMA_SET_INVALID_VALUE`. `kuma.selectedWorkspaceId.storage` lowercase UUID stored uppercase. |
| DT-SET-19 | `env.resolve_executable`: `""` and `"   "` -> `null`; `/bin/sh` -> `/bin/sh` (source `absolute`); `/bin/nonexistent` -> `null` and no PATH search; `~/x` expands; bare `sh` found via PATH; bare name not found -> `null`; `customPath` non-blank invalid -> `null` even if the command is on PATH; `applySettings:true` for `kubectl` with only the legacy key set uses the legacy path (DEV-02). |
| DT-SET-20 | Directory passed as `customPath` and as `customDockerPath` -> `null` (DEV-40); `defaultShell="/usr/bin"` -> shell recipe uses `/bin/zsh`. |
| DT-SET-21 | PATH sniff (test double shell scripts via `SHELL`): zsh-style shell receives argv exactly `["-c", <ZSH-sniff bootstrap>]`; a shell named `fish` receives `["-c","echo $PATH"]` and its space-separated output becomes colon-separated. Empty output or non-spawnable shell -> daemon env PATH (or `""`). `SHELL` pointing to a non-executable -> `/bin/zsh` used. A shell that sleeps > 10 s -> killed, fallback taken (DEV-41). |
| DT-SET-22 | `env.path` ordering: sniffed `/a:/b:/a`, nvm dirs `v18.0.0`,`v20.1.0` under a temp `$HOME`: result begins `/a:/b:` then `.../v18.0.0/bin:.../v20.1.0/bin:` then `~/Library/pnpm:~/.bun/bin:~/go/bin` then the 12 fallback entries, duplicates removed (first kept), `directories[].source` labels correct. Result contains `/opt/homebrew/bin` and `/usr/local/bin` even with empty sniff. |
| DT-SET-23 | Cache: second `env.path` has `cached:true` and does not spawn a shell (counted via double); `env.refresh` spawns exactly once and returns `cached:false`; ten concurrent first calls spawn exactly one shell. |
| DT-SET-24 | `resolve_executable` PATH search order: same binary in two PATH dirs returns the first by PATH order; a directory named like the command is skipped; a non-executable file is skipped. |
| DT-SET-25 | Shell launch spec: `defaultShell=/bin/bash` -> `["-c", BASH, "--", cmd]` byte-exact; `/bin/zsh` -> ZSH string; `/bin/sh` -> ZSH string; a fish binary -> `["-c","eval $argv[1]","--",cmd]` with no trap; unexecutable configured shell -> `/bin/zsh` with ZSH string; basename comparison is lowercased (`Fish` selects the fish recipe). |
| DT-SET-26 | Kubeconfig default path: temp `$HOME` without `.kube/config` and no `KUBECONFIG`: `null`; create `$HOME/.kube/config`: found; `KUBECONFIG=/missing:/real/a:/real/b` (a and b exist): `/real/a`; custom path existing wins over both; custom path missing falls through to `KUBECONFIG`; `KUBECONFIG` with `~/k`; `realHome` comes from passwd even when `$HOME` is overridden. |
| DT-SET-27 | `env.dependencies` shape: exactly 4 engines (`kubectl`,`kubeconfig`,`docker`,`podman`) and 2 tunneling (`cloudflared`,`ngrok`) in order; names, `iconName`, `description`, `settingsKey`, `category` byte-exact per 3.11.2; `version null`; `status` mirrors `isInstalled`. |
| DT-SET-28 | `env.dependencies` kubeconfig path: no custom value and default file present -> `path "~/.kube/config"`, `resolvedPath` real; custom value set but missing and default present -> `isInstalled true`, `path` equals the custom string; nothing present -> `isInstalled false`, `path null`. Legacy-only `kuma.custom_docker_path` pointing to a valid binary -> docker `isInstalled true` with that path. |
| DT-SET-29 | Legacy import: craft a binary plist (`bplist00`) with `kuma.settings.autoResumeServices=true`, `kuma.settings.customDockerPath="/x/docker"`, `kuma.custom_kubectl_path="/y/kubectl"`, `kuma.settings.appearance="dark"`, `kuma.has_completed_onboarding=true`, `activeServiceIDsBeforeQuit=["aaaa...","junk"]`, `NSWindow Frame main=...`: after first start `settings.list` shows the known keys (array normalized to UPPERCASE, `junk` dropped), the unknown key absent, `meta.legacyImportDone` set. Same test with an XML plist. |
| DT-SET-30 | Idempotency: change `autoResumeServices` via `settings.set`, delete the plist, restart: value unchanged; edit the plist and restart: not re-imported; pre-existing row not overwritten even on first import (`INSERT OR IGNORE`). After `data.factory_reset` (rows wiped) a restart does not re-import. |
| DT-SET-31 | Import edge cases: `appearance="foo"` skipped; `launchAtLogin` as string `"YES"` -> `true`, `"corrupted_value_xyz"` -> `false`, integer `0` -> `false`; `defaultShell=""` imported as `""`; plist absent -> daemon starts, `legacyImportDone` written; corrupt plist -> daemon starts, flag NOT written, next start retries. |
| DT-SET-32 | Onboarding flag: absent -> `effective false`; set `true` via `settings.set`; `settings.reset` leaves it `true`; `data.factory_reset` removes it (effective false). Garbage stored row (`"x"` text, not JSON) reads as absent -> `false`. |
| DT-SET-33 | `settings.list` with `prefix:"client."` returns only client rows sorted; `includeClient:false` omits them. |
| DT-SET-34 | Live reads: start a script service, `settings.set defaultShell=/bin/bash`, start another: second run uses bash recipe without restart; change `portConflictPolicy` mid-run and the next port check honors it (INV-D-SET-04). |
| DT-SET-35 | `settings.set` no-op (same value) emits no event and does not change `updatedAt`. Writing `notifyOnServiceFailure` when `notifyOnCrash` exists deletes it even if the primary value is unchanged. |

---

## Proposed RPC additions

| Name | Params | Result | Rationale |
|------|--------|--------|-----------|
| `env.validate_binary` extension (not a new method) | `kind?: "binary" \| "kubeconfig"` (default `"binary"`, ADD-42) | same `Validation` object | The Settings kubeconfig field check (`Configuration file does not exist at specified path`) is the same "validate this path as I type" interaction as binaries; with `kind: "kubeconfig"` the `expectedCommand` is ignored and only `empty`/`valid`/`fileNotFound` can occur. Without this, a client can only learn the kubeconfig validity via `settings.set` (which persists). |
| `settings.set` params `strict`, `expectedUpdatedAt` | see 4.2 | see 3.4.8 | Parameter additions on an existing method, listed here so [10](10-rpc-protocol.md) includes them. |
| `settings.list` params `prefix`, `includeClient` | see 3.5 | `{ settings: Setting[] }` | Parameter additions on an existing method. |
| `env.resolve_executable` params `customPath`, `applySettings` | see 4.5 | see 4.5 | Parameter additions on an existing method. |

No new RPC method names or event names are required.

---

## Open questions / residual risks

- **R1 PATH noise**: 1.x takes the entire trimmed stdout of the sniff as PATH. An rc file that prints text (banner, `nvm` messages) corrupts the first component(s) (a component containing a newline survives trimming only at its ends). Parity kept; a hardened parser (take the last line) was not adopted because it would be an unrequested behavior change.
- **R2 nvm directory order**: 1.x iterated `FileManager.contentsOfDirectory` order (unspecified). The spec fixes ascending byte-wise order (so `v18.x` precedes `v20.x`, `v8.x` sorts after `v18.x`). If a user relies on the "newest node wins" outcome of a different order, they can set `PATH` through their shell profile (shell components precede discovered ones).
- **R3 `NSHomeDirectory()` vs `getpwuid`**: tilde/discovery use `$HOME`-first (`home()`), kubeconfig default uses passwd (`realHome()`), mirroring 1.x. The two coincide for normal logins; they differ under `sudo`/`HOME` overrides.
- **R4 `$KUBECONFIG` source**: the daemon reads its own process environment. A daemon started by a LaunchAgent lacks variables exported only in interactive shell profiles; 1.x (Finder-launched app) had the same limitation. Users may set `customKubeconfigPath`.
- **R5 `defaults export` vs plist file** (3.8.2): when 1.x was running immediately before the first daemon start, the on-disk plist can lag `cfprefsd`. The spec makes the file normative and `defaults export` optional; an implementer who wants to lose nothing should prefer `defaults export` when available.
- **R6 `NSString.boolValue` import rule** (3.8.4) is a documented approximation of Foundation's behavior for odd string values written into boolean keys; real 1.x data only ever contains booleans.
- **R7 Auto-resume scope**: 1.x resumed only services of the workspace loaded first (and only once per app session), leaving other workspaces' IDs in `activeServiceIDsBeforeQuit`. The daemon-side algorithm is owned by [14](14-lifecycle-and-platform.md)/[06](06-execution-engine.md); this spec guarantees only the key semantics (3.7).
- **R8 `settings.reset` end state** (3.6.3): the daemon deletes rows instead of re-writing explicit defaults as 1.x's `didSet` did; indistinguishable through any 1.x read path (documented to avoid re-litigation).
