# Daemon Spec 05: Providers, Validation and URL Normalization

> **Area code:** `PRV` · **Status:** Draft for implementation · **Baseline:** Kuma 1.x (Swift)
> **Depends on:** [00 Overview and Conventions](00-overview-and-conventions.md), [01 Data Model](01-data-model.md), [02 Security and Secrets](02-security-and-secrets.md), [03 Settings and Environment](03-settings-and-environment.md) · **Consumed by:** [04](04-workspaces-groups-services.md), [06](06-execution-engine.md), [07](07-kubernetes.md), [08](08-logs-and-events.md), [10](10-rpc-protocol.md), [11](11-cli.md), [12](12-mcp.md), [13](13-rest-api.md)

---

## 1. Purpose and scope

This spec is the contract for **what a provider configuration means, which values are legal, which are defaulted, what blocks a start, and how user-typed URLs are normalized**. It covers:

1. The eight provider categories (`kubernetes`, `docker`, `podman`, `shell`, `ssh`, `httpCheck`, `tunnel`, `processMonitor`): which `Provider` fields apply, required versus optional, defaults at create/save, fallbacks at display/run time, and mutual-exclusivity rules (compose path vs YAML, script path vs inline, SSH key vs password).
2. The derived members `displayName`, `resolvedTarget` (card string) and `isAutoReconnectEnabled`, with the exact per-category algorithms.
3. The rules the daemon applies on `service.create` (the `CreateServicePayloadBuilder` logic, form validity, port-row rules, creation defaults) and on `provider.add`, `provider.update`, `provider.set_ports`, `provider.delete` (label rules, writable fields per category, type-change semantics, the running lock). CRUD orchestration, events and the `expectedUpdatedAt` handling stay in [04](04-workspaces-groups-services.md); this spec owns the **validation and normalization content** of those calls.
4. `ServiceConfigurationValidator`: every rule (code, category, condition, exact message, severity), the context inputs, and the new RPC `service.preflight` [V2-ADD ADD-01] that computes the context server-side (including the Kubernetes connection probe and target resolution).
5. The two message sets (validator messages versus runner `Invalid configuration: <msg>` messages) and which surface shows which.
6. `URLNormalizer`: the full algorithm, every branch, the exact URL validity predicate (derived from Foundation `URL(string:)` and verified against it), and a ground-truth case table.
7. [CLIENT] hints (placeholders, labels, banner aggregation text, form layout) listed so nothing is silently dropped.

Out of scope (owned elsewhere): the `Provider` column list and storage formats ([01](01-data-model.md)); secret encryption and wire redaction ([02](02-security-and-secrets.md)); how runners launch processes, the `ServiceExecutionError` runtime flow, auto-reconnect policy and interval floors ([06](06-execution-engine.md)); kubeconfig storage, `kubectl` argv, the connection probe and target discovery ([07](07-kubernetes.md)); log buffer mechanics ([08](08-logs-and-events.md)); service/group CRUD, `service.switch_provider`, `service.update` ([04](04-workspaces-groups-services.md)).

### 1.1 Conventions used in this spec

| Term | Definition |
|------|------------|
| trim-W | Swift `CharacterSet.whitespaces` (U+0009 and the Unicode `Zs` separators); not newlines. Used only by `resolvedTarget`. |
| trim-WN | Swift `CharacterSet.whitespacesAndNewlines` = Unicode `White_Space` (U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000). Equals Rust `str::trim()`. Every "trimmed" in this spec without qualifier means trim-WN. |
| blank | NULL or empty after trim-WN. |
| swift-int | Swift `Int(String)`: optional single leading `+` or `-`, then one or more ASCII digits `0-9`, no whitespace, no separators, must fit in a signed 64-bit integer; otherwise absent. `Int("+80")` is 80, `Int("-0")` is 0, `Int("٣٠٠٠")` is absent. |
| tilde-expand | `NSString.expandingTildeInPath`: `~` or a leading `~/` is replaced by the home directory of the daemon's user; `~user` or `~user/<rest>` by that user's home (unknown user: unchanged); a path not starting with `~` is unchanged (relative paths stay relative). |
| path base | Relative paths are resolved against the process working directory. The daemon MUST `chdir("/")` at startup ([14](14-lifecycle-and-platform.md)) so a relative path behaves as in the GUI-launched 1.x app (cwd `/`). |
| file exists / dir exists | `FileManager.fileExists(atPath:)` after tilde-expand (follows symlinks). "is file" additionally requires not-a-directory; "is dir" requires a directory. |
| Default kubeconfig | UUID `00000000-0000-0000-0000-000000000001` ([01 §3.14.2](01-data-model.md)). `kubeConfigID` NULL means Default. |
| issue | `{code, message, severity}` as in §4.3. |

---

## 2. 1.x source of truth (paths read)

| Path | Used for |
|------|----------|
| `Kuma/Domain/Models/Provider.swift`, `Provider+KubernetesDefaults.swift` | Fields, `displayName` (`:124-129`), `resolvedTarget` (`:132-193`), `extractComposeImage` (`:198-224`), `isAutoReconnectEnabled` (`:120`), `withKubernetesDefaults` |
| `Kuma/Domain/Enums/ProviderCategory.swift` | Raw values, `sidebarLabel`, `supportsAutoReconnect` (`:37-44`) |
| `Kuma/Core/Configuration/ServiceConfigurationValidator.swift` (290 lines), `ConfigurationIssue.swift` | Every validator rule (`issues` `:34-69`, `portIssues` `:77-121`, `kubernetesIssues` `:124-155`, `composeIssues` `:159-200`, `shellIssues` `:204-218`, `sshIssues` `:222-252`, health/tunnel/monitor `:256-289`) |
| `Kuma/Lib/URLNormalizer.swift` (102 lines) | Normalization (`normalize` `:22-56`, `fixMalformedScheme` `:60-77`, `isLocalhostOrLoopback` `:80-90`, `isValidURL` `:92-101`) |
| `Kuma/Core/Execution/Compose/ComposeStackResolver.swift` | Path-first resolution, ephemeral YAML file side effect, `configuredWorkingDirectory` (`:11-57`) |
| `Kuma/Core/Execution/ServiceExecutionEngine.swift:5-30`, `Runners/{Shell,SSHTunnel,Tunnel,HealthCheck,ProcessMonitor,Kubernetes,Container}Runner.swift`, `Kuma/Core/Kubernetes/{KubeTargetResolver,KubeConfigMaterializer,KubeConfigExecutionResolver}.swift` | Runner-side `invalidConfiguration` strings and runtime defaults |
| `Kuma/Presentation/Features/Services/Views/CreateService/**` (`Components/CreateServicePayloadBuilder.swift`, `+ComposeDraft.swift`, `CreateServiceDraftInputs.swift`, `CreateServiceSaving.swift`, `CreateServiceCreationDefaults.swift`, `CreateServiceSheet*.swift`, `CreateServiceFillDetailsStepView.swift`, `CreateServiceProviderStepView.swift`, `Components/CreateServiceContextualFormView.swift`) | Create payload, form validity, creation defaults, placeholders |
| `Kuma/Presentation/Features/Services/Models/{ServiceInspectorDrafts,ProviderSSHAuth}.swift` | Draft defaults, SSH auth normalization |
| `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+{Validation,AutoSave,Providers,Loading,Execution}.swift`, `KubeConfigViewModel.swift` | When validation runs, context construction, commit semantics, provider add/update/delete/switch, context sanitization |
| `Kuma/Presentation/Features/Services/Views/Forms/**`, `Views/Inspector/**` (`ServiceInspectorView`, `ServiceProvidersSectionView`, `Components/{InspectorConfigFormStack,InspectorFormSections,InspectorRemoteAndNetworkFormSections,InspectorKubernetesFormSection,InspectorComposeFormSection,InspectorRunningBanner,ProviderItemRowView,ServiceProvidersListView,ServiceProvidersInlineFormView}.swift`, `InspectorOptionsSection.swift`), `Components/FormKit/KumaPortMappingEditor.swift`, `KumaSourceField.swift` | Field bindings and normalization, lock rule, option rows, [CLIENT] strings |
| `Kuma/Presentation/Features/LiveLogs/{LiveLogSession,LiveLogSystemEmitter,LiveLogRecordingBridge}.swift` | Configuration-issue log lines |
| `KumaTests/Features/Services/{ServiceConfigurationValidatorTests,URLNormalizerTests,ServicesValidationAndSecurityTests,ServicesInitialStateTests}.swift` | Implicit requirements (TC-U01..U08, TC-B05a/b/c, TC-B08, TC-RUN04, TC-A02) |
| `docs/specs/06-services.md`, `docs/testing/06-services-test-matrix.md` | Feature intent |
| Probe harness (copy of `URLNormalizer.swift` compiled with `swiftc` on macOS, plus a 320,000-string differential fuzz of `URL(string:)`) | Ground truth for §3.10 (every row of the case table and the validity predicate was produced by the real Foundation implementation) |

---

## 3. Normative behavior

### 3.1 Category capability matrix

`ProviderCategory` raw values and order of declaration: `docker`, `kubernetes`, `podman`, `shell`, `ssh`, `httpCheck`, `tunnel`, `processMonitor` ([01 §3.18.1](01-data-model.md)). The wire accepts exactly these strings; any other is `KUMA_DAT_INVALID_ENUM`.

| `type` | `sidebarLabel` | Has port mappings | `supportsAutoReconnect` | Create requires (§3.6.3) | Start requires (validator, §3.7) |
|--------|----------------|-------------------|--------------------------|--------------------------|----------------------------------|
| `kubernetes` | Kubernetes | yes | yes | kubeconfig, context, target, ≥1 complete port row | kubeconfig, context, target, ≥1 complete port row, reachable cluster, resolvable target |
| `docker` | Docker | no | no | compose file path or compose YAML | compose file path or YAML (file must exist when a path is set) |
| `podman` | Podman | no | no | same as docker | same as docker |
| `shell` | Shell | no | yes | run command | run command |
| `ssh` | SSH | yes | yes | host, user | host, user, ≥1 complete port row, key path (key auth) or password (password auth) |
| `httpCheck` | Health Check | no | no | URL | URL that `URLNormalizer` accepts |
| `tunnel` | Tunnel | no | no | target | target; ngrok engine additionally needs an auth token |
| `processMonitor` | Process Monitor | no | no | process name | process name |

Port mappings exist only for `kubernetes` and `ssh` (`CreateServicePayloadBuilder.swift:78-92`, `ServiceConfigurationValidator.swift:78`). The data model stores mappings per provider regardless of type ([01 §3.11.2](01-data-model.md)); a provider whose type was switched keeps its old rows.

### 3.2 Derived members (computed by the daemon, never stored, never accepted on input)

#### 3.2.1 `isAutoReconnectEnabled`

`(autoReconnect == true) && type.supportsAutoReconnect` (`Provider.swift:120`). The column `autoReconnect` is always written as a non-NULL boolean by the inspector toggle (`InspectorOptionsSection.swift:50-57`); the Swift optional is `nil` only for freshly constructed in-memory values and is stored as `false` ([01 §4.4](01-data-model.md)).

#### 3.2.2 `displayName`

`label` if it is non-NULL and `label.trimmingCharacters(in: .whitespaces)` (trim-W) is non-empty — the returned value is the **untrimmed** label; otherwise `type.sidebarLabel` (`Provider.swift:124-129`).

#### 3.2.3 `resolvedTarget` (card string)

Per `type` (`Provider.swift:132-193`). The same function feeds the deck item ([01 §3.14.1](01-data-model.md)); it is restated here because it depends on category semantics.

| `type` | Algorithm (first match wins) |
|--------|------------------------------|
| `docker` | (1) `composeFilePath` trim-WN non-empty → `Docker: <lastPathComponent(trimmed path)>`. (2) else `yamlConfig` non-NULL and `extractComposeImage(yamlConfig)` non-NULL → `Docker: <image>`. (3) else `label` non-NULL and non-empty (no trimming, no trim check) → `Docker: <label>`. (4) else `Docker`. |
| `podman` | Same as docker with prefix `Podman: ` and fallback `Podman`. |
| `kubernetes` | `targetName` trim-W non-empty → `k8s: <targetName trimmed W>`; else `Kubernetes`. |
| `shell` | `runCommand` trim-W non-empty → the **trimmed** command (the whole command, not just its first word); else `Shell script`. |
| `ssh` | `SSH: <sshUser ?? "root">@<sshHost ?? "localhost">:<sshPort ?? 22>`. `??` applies to NULL only: an empty string is kept (`SSH: @:22` is possible). |
| `httpCheck` | `httpCheckUrl` trim-W non-empty → `HTTP: <trimmed url>` (the raw typed URL, not the normalized one); else `HTTP Check`. |
| `tunnel` | `<(tunnelType ?? "cloudflare").capitalized> Tunnel -> <tunnelTargetUrl ?? "8080">`. `capitalized`: first letter of each word uppercased, the rest lowercased (`cloudflare` → `Cloudflare`, `NGROK` → `Ngrok`). An empty `tunnelTargetUrl` is kept (`Cloudflare Tunnel -> `). |
| `processMonitor` | `monitorProcessName` trim-W non-empty → `Monitor: <trimmed name>`; else `Process Monitor`. |

`lastPathComponent` follows `NSString`: trailing `/` ignored, text after the last `/`; `"/"` → `"/"`; `""` → `""`.

`extractComposeImage(yaml)` (`Provider.swift:198-224`): split on Unicode newlines (`\n`, `\r`, `\r\n`, U+0085, U+2028, U+2029); for each line: trim-W (indentation is removed, so `    image: x` matches); if the trimmed line **starts with** `image:` (a list item such as `- image: x` does not match): `raw` = text after `image:` trimmed-W; `cleaned` = `raw` with every leading and trailing `"` and `'` character removed; strip exactly one prefix in this precedence: `docker.io/library/`, else `docker.io/`, else `library/`; if `cleaned` is non-empty return it (first match wins; an empty result continues with the next line); no match → none.

Examples (`ServicesInitialStateTests` TC-A02 and derived): `composeFilePath="/srv/app/docker-compose.yml"` → `Docker: docker-compose.yml`; yaml containing `  image: "docker.io/library/redis:7"` → `Docker: redis:7`; yaml `image: docker.io/bitnami/redis` → `Docker: bitnami/redis`; `image: library/nginx` → `Docker: nginx`; kubernetes `targetName="  api-0 "` → `k8s: api-0`; ssh with all NULL → `SSH: root@localhost:22`; tunnel with NULL type and target → `Cloudflare Tunnel -> 8080`.

### 3.3 Per-category provider configuration semantics

Column key: **Create** = rule in `service.create` (§3.6); **Preflight** = validator code (§3.7); **Run** = what the runner does with the stored value when `service.start` runs ([06](06-execution-engine.md)); **Default** = value used when the stored column is NULL. "Display default" means a UI display fallback that is **not persisted** until the field is edited. Write normalization of `provider.update` is in §3.5.2.

#### 3.3.1 `kubernetes`

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `kubeConfigID` | Absent or null → stored as the explicit Default id `00000000-0000-0000-0000-000000000001` (the create sheet always preselects a concrete config, `CreateServiceSheet+KubeStep.swift`). An id that is not Default and not in `kube_config` → `KUMA_PRV_CREATE_INVALID` (`Select a kubeconfig.`) [DEV-61]. | `k8s.kubeconfig` when the effective id is not resolvable [DEV-61] | `Selected kubeconfig no longer exists.` if dangling ([07](07-kubernetes.md)) | NULL ≡ Default kubeconfig |
| `customKubeConfigPath` | not accepted on create | not checked | honored first by the runtime ([07](07-kubernetes.md)) | NULL; legacy, import-only; not writable by `provider.update` |
| `kubeContext` | **Required**, non-blank (`isFormValid`); stored trimmed | `k8s.context` when the sanitized context is empty | passed as `--context` when non-blank | NULL |
| `kubeNamespace` | optional; stored trimmed (see CR-TRIM) | none | `-n` omitted when blank; discovery log label `default` | NULL |
| `targetName` | **Required**, non-blank | `k8s.target` | `Target resource name is required (e.g. my-app-service or pod pattern).` | NULL |
| `kubeTargetType` | draft raw value, default `pod`; **written for every category on create**, not only kubernetes (parity quirk, `CreateServicePayloadBuilder.swift:56`) | none | decode `KubeTargetType(rawValue: x ?? "") ?? .pod` | NULL → `pod` (`withKubernetesDefaults`, §3.4) |
| `usePattern` | draft bool, default `true`; **written for every category on create** (`:57`) | none | `?? true` | NULL → `true` |
| `autoReconnect` | stored `false` | none | `Auto Reconnect` option, ≤3 retries ([06](06-execution-engine.md)) | `false` |
| ports (`portMapping`) | ≥1 complete row (see §3.6.4) | `ports.*` | `At least one port mapping (Local:Remote) is required for Kubernetes port-forwarding.` | none |

#### 3.3.2 `docker` and `podman` (compose)

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `composeFilePath` | stored trimmed, NULL if the trimmed text is empty | `compose.missing` (both sources blank), `compose.invalid` (file missing or a directory) | file must be a regular file, else `Compose file not found: <rawPath>` | NULL |
| `yamlConfig` | stored **as typed** (not trimmed), NULL iff the text is the empty string | counts as a source only if non-blank | used only when `composeFilePath` is blank; the **trimmed** YAML is written to `<tmp>/kuma-compose-<serviceID>/docker-compose.kuma.yml` (06) | NULL |
| `initialScript` | stored as typed, NULL iff empty | not checked | pre-run inline script ([06](06-execution-engine.md)) | NULL |
| `initialScriptPath` | stored trimmed, NULL if empty | `compose.startup_script` when set and not an existing regular file | `Startup script file not found: <rawPath>` | NULL |
| `workingDirectory` | not accepted on create (the create form has no such field); writable later by `provider.update` | `compose.working_dir` when set and not an existing directory | honored only if the directory exists; a missing directory is **silently ignored** (falls back to the compose file's directory or the temp folder), `ComposeStackResolver.swift:47-57` | NULL; no 1.x form field, importable/API-only |
| `autoReconnect` | stored `false` | none | not supported (`isAutoReconnectEnabled` is false even if the column is true) | `false` |

Path takes precedence over YAML at run time (`ComposeStackResolver.swift:15-23`); the write rule that keeps only one of them is §3.5.3. `docker` and `podman` are identical in rules; they differ only in the binary the runner uses and in [CLIENT] placeholders.

#### 3.3.3 `shell`

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `runCommand` | **Required**, non-blank; stored trimmed | `shell.command` | `No shell command specified.` | NULL |
| `workingDirectory` | optional; stored trimmed, NULL if empty | `shell.working_dir` when set and not an existing directory | `Working directory does not exist: '<rawDir>'` | NULL |
| `autoReconnect` | stored `false` | none | supported | `false` |

#### 3.3.4 `ssh`

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `sshHost` | **Required**, non-blank; stored trimmed | `ssh.host` | `SSH Host is not configured.` | NULL (display `localhost` in the card) |
| `sshUser` | **Required**, non-blank; stored trimmed | `ssh.user` | not required: `user = sshUser?.trimmed ?? NSUserName()` (the current macOS login name; NULL only) | NULL (card shows `root`; runtime uses the login name) |
| `sshPort` | `swift-int(trimmed text)`, else `22`; always written for ssh | not checked | `provider.sshPort ?? 22` | NULL → 22; **no range check** (parity; see R-03 in the residual risks) |
| `sshAuthType` (API field, not a column) | `key` (default) or `password`; selects which of the next two columns is stored [ADD-60] | selects the rule branch (§3.7) | n/a | inferred, §3.5.4 |
| `sshKeyPath` | stored only when auth is `key`: absent → `~/.ssh/id_ed25519` (create-form default), explicit text → trimmed, empty → NULL | `ssh.key` (blank), `ssh.key_missing` (path does not exist) | `SSH private key file not found: '<keyPath>'`; only consulted when no password is stored | NULL (display default `~/.ssh/id_ed25519`, not persisted) |
| `sshPassword` | stored only when auth is `password` and non-empty (trimmed); a secret (cipher at rest, [02](02-security-and-secrets.md)) | `ssh.password` (blank) | password wins over key when both exist | NULL |
| `autoReconnect` | stored `false` | none | supported | `false` |
| ports | not required at create (`isFormValid` accepts zero rows); partial rows rejected | `ports.*` (≥1 complete row at start) | `At least one port mapping (Local:Remote) is required for SSH tunneling.` | none |

#### 3.3.5 `httpCheck`

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `httpCheckUrl` | **Required**, non-blank. Stored as `URLNormalizer.normalize(raw) ?? raw.trimmed` (`CreateServicePayloadBuilder.swift:97-99`): a normalizable URL is stored in normalized form, an un-normalizable one is stored trimmed. | `health.url` (blank), `health.url_invalid` (`URLNormalizer.normalize` returns none) | normalized again at start; `Health Check Target URL is not specified.` / `Invalid Health Check URL: '<rawUrl>'.` | NULL |
| `httpCheckInterval` | integer seconds, default `5`; the create form offers 5, 10, 30, 60 (§3.4); the API accepts any integer and stores it unchanged | not checked | `max(httpCheckInterval ?? 10, 3)` | NULL → UI display `5s`, runner `10` (parity inconsistency, R-04) |

`provider.update` stores `httpCheckUrl` **raw as typed** (the inspector never calls `URLNormalizer`; `InspectorRemoteAndNetworkFormSections.swift:66-69`). Only create normalizes at write time.

#### 3.3.6 `tunnel`

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `tunnelType` | engine raw value, always written for tunnel: `cloudflare` (default) or `ngrok` | `ngrok` check uses `lowercased()` of the stored text | `lowercased()`; `ngrok` → ngrok, anything else → cloudflare | NULL → `cloudflare` |
| `tunnelTargetUrl` | **Required**, non-blank; draft default `http://localhost:3000`; stored trimmed (**not** normalized) | `tunnel.target` (blank) | normalized at start with `URLNormalizer.normalize(raw, defaultToHttps: false) ?? "http://localhost:3000"`; blank → `Tunnel target (port or local URL) is required.` | NULL (card shows `8080`; UI field display default `http://localhost:3000`) |
| `ngrokAuthToken` | stored only when engine is `ngrok` and the trimmed token is non-empty; a secret | `tunnel.ngrok_token` when engine is ngrok and token blank | optional at run time (`--authtoken` only if present) | NULL |

#### 3.3.7 `processMonitor`

| Field | Create | Preflight | Run | Default |
|-------|--------|-----------|-----|---------|
| `monitorProcessName` | **Required**, non-blank; stored trimmed | `monitor.process` | `Process name to monitor is required.` | NULL |
| `monitorInterval` | integer seconds, default `5`; any integer accepted and stored unchanged | not checked | `max(monitorInterval ?? 5, 2)` | NULL → `5` |

### 3.4 Defaults master table

| Default | Value | Where applied | Persisted? | Source |
|---------|-------|---------------|-----------|--------|
| `kubeTargetType` | `pod` | `withKubernetesDefaults` on kubernetes providers when NULL or empty; create draft; read decode fallback for NULL/empty/unknown | persisted on `provider.add`/`provider.update` of a kubernetes provider ([01 §3.14.3](01-data-model.md)); unknown non-empty text is **not** rewritten | `Provider+KubernetesDefaults.swift`, `ServiceInspectorDrafts.swift:30` |
| `usePattern` | `true` | same | same | same |
| `sshPort` | `22` | create (`?? 22` on bad text), inspector setter `Int($0) ?? 22`, display, runner | create: yes; display/runner: no | `CreateServicePayloadBuilder.swift:66`, `InspectorRemoteAndNetworkFormSections.swift:34-37`, `SSHTunnelRunner.swift:31` |
| `sshUser` | login name (`NSUserName()`) | runner only when NULL; the create form requires a user | no | `SSHTunnelRunner.swift:30` |
| `sshKeyPath` | `~/.ssh/id_ed25519` | create form default; `ProviderSSHAuth.applyAuthTypeChange(.key)` when blank; display | create and auth-switch: yes; display: no | `ServiceInspectorDrafts.swift:84`, `ProviderSSHAuth.swift:15-18`, `InspectorRemoteAndNetworkFormSections.swift:51` |
| `sshAuthType` | `key` | create draft; inference when no password stored | n/a (not a column) | `ServiceInspectorDrafts.swift:83` |
| `tunnelType` | `cloudflare` | create draft, display, runner, validator, `resolvedTarget` | create: yes; others: no | `ServiceInspectorDrafts.swift:112` |
| `tunnelTargetUrl` | `http://localhost:3000` | create draft; inspector display; runner fallback only when `normalize` fails | create: yes; display: no | `ServiceInspectorDrafts.swift:113`, `TunnelRunner.swift:24` |
| `httpCheckInterval` | `5` (create draft, UI display) / `10` (runner when NULL) | | create: yes | `ServiceInspectorDrafts.swift:100`, `HealthCheckRunner.swift:17` |
| `monitorInterval` | `5` (create, display, runner) | | create: yes | `ServiceInspectorDrafts.swift:127`, `ProcessMonitorRunner.swift:14` |
| Interval options | 5, 10, 30, 60 (`fast`, `standard`, `relaxed`, `slow`; titles `5s`, `10s`, `30s`, `60s`) | UI picker; display fallback `HealthCheckIntervalOption(rawValue: x ?? 5) ?? .fast` | the column keeps any integer | [01 §3.18.7](01-data-model.md) |
| `autoReconnect` | `false` | all creates | yes (`false`, never NULL) | [01 §4.4](01-data-model.md) |
| `kubeConfigID` | Default id | create (explicit), read (NULL ≡ Default) | create: yes (explicit id) | §3.3.1 |
| `kubeNamespace` label | `default` | discovery log text only | no | `KubeTargetResolver.swift:65` |
| `isDisabled` | `false` | create | yes | `ServiceInspectorDrafts.swift:10` |

### 3.5 Provider write rules (`provider.add`, `provider.update`, `provider.delete`, type change)

#### 3.5.1 `provider.add` (`ServiceProvidersSectionView.swift:119-146`, `ServiceInspectorViewModel+Providers.swift:58-96`)

1. Params: `serviceID`, `type`, optional `label`, optionally the category fields of §3.5.2 (an API convenience; the 1.x inline form creates a **bare** provider with only `type` and `label`).
2. `label` rule: trimmed; empty after trim → NULL. No maximum length, no uniqueness constraint (two providers may share a label or type).
3. The new provider gets a random UUID, `createdAt = updatedAt = now`, all other columns NULL, `autoReconnect = false`. For `type == kubernetes` the daemon persists `kubeTargetType = "pod"` and `usePattern = true` ([01 §3.14.3](01-data-model.md); 1.x persisted them at the first autosave commit, so the observable result is identical).
4. SSH: when the call carries SSH fields, §3.5.4 normalization applies; a bare ssh provider stores `sshPort = NULL`, no key, no password.
5. The new provider becomes the service's `activeProviderID` and `service.updatedAt` is bumped (`+Providers.swift:58-67`, `:85-91`). It starts with **no** port mappings (the inspector shows one empty draft row for kubernetes/ssh; nothing is persisted until a complete row is committed).
6. Running lock (§3.5.7) applies.
7. A service may hold any number of providers, including several of the same type.

#### 3.5.2 `provider.update`: writable fields and normalization

Wire semantics (all categories): key absent = unchanged; `null` = clear to NULL; a value = set. Secrets follow [02 §3.4](02-security-and-secrets.md) (absent keep; `null` or `""` clear; non-empty encrypt). `id`, `serviceID`, `createdAt`, `updatedAt`, the derived members and the response-only booleans `sshPasswordSet` / `ngrokAuthTokenSet` are never writable. `updatedAt` follows [01 DEV-22](01-data-model.md); provider and service `updatedAt` are both bumped (parity with `commitChanges`, `+AutoSave.swift:43-90`, which writes both).

Writable fields per resulting category and the **inspector normalization** the daemon MUST apply (parity, because `resolvedTarget` and runners distinguish `""` from NULL):

| Field | Category | A supplied `""` becomes | Other normalization |
|-------|----------|--------------------------|---------------------|
| `label` | all | NULL | trimmed first (§3.5.1) |
| `type` | all | n/a | §3.5.5 |
| `autoReconnect` | kubernetes, ssh, shell | n/a (boolean) | stored non-NULL boolean |
| `kubeConfigID` | kubernetes | n/a | UUID or null (null = Default); unknown non-Default id rejected `KUMA_PRV_KUBECONFIG_NOT_FOUND`; §3.5.6 |
| `kubeContext` | kubernetes | NULL | §3.5.6 |
| `kubeNamespace` | kubernetes | NULL | none |
| `targetName` | kubernetes | NULL | none |
| `kubeTargetType` | kubernetes | stored `""` is rewritten to `pod` by the kubernetes defaults | raw text stored |
| `usePattern` | kubernetes | n/a (boolean) | |
| `yamlConfig` | docker, podman | NULL | §3.5.3 |
| `composeFilePath` | docker, podman | NULL | trimmed; §3.5.3 |
| `initialScript` | docker, podman | NULL | §3.5.3 |
| `initialScriptPath` | docker, podman | NULL | trimmed; §3.5.3 |
| `workingDirectory` | docker, podman, shell | NULL | none (not trimmed) |
| `runCommand` | shell | **kept as `""`** | none (not trimmed) |
| `sshHost` | ssh | NULL | none |
| `sshUser` | ssh | NULL | none |
| `sshPort` | ssh | n/a (integer) | integer or null; no range check |
| `sshKeyPath` | ssh | **kept as `""`** | §3.5.4 |
| `sshPassword` | ssh | NULL (secret clear) | §3.5.4 |
| `httpCheckUrl` | httpCheck | **kept as `""`** | raw, **not** URL-normalized |
| `httpCheckInterval` | httpCheck | n/a (integer) | any integer, unchanged |
| `tunnelType` | tunnel | **kept as `""`** | raw text (UI writes `cloudflare` or `ngrok`) |
| `tunnelTargetUrl` | tunnel | **kept as `""`** | raw, not normalized |
| `ngrokAuthToken` | tunnel | NULL (secret clear) | |
| `monitorProcessName` | processMonitor | **kept as `""`** | none |
| `monitorInterval` | processMonitor | n/a (integer) | any integer, unchanged |

Foreign-field rule [DEV-64]: a field that does not apply to the **resulting** category (the `type` after the patch) is rejected with `KUMA_PRV_FIELD_NOT_APPLICABLE` unless its value equals the stored value (so a client may echo a full provider back unchanged). `customKubeConfigPath` is applicable to no writer: echo-equal is tolerated, any change is rejected. Columns of other categories that already hold data are **retained and ignored**, never nulled (1.x never cleared them; [01 §4.4](01-data-model.md)).

After applying the patch, the daemon runs, in this order: §3.5.3 exclusivity, §3.5.4 SSH normalization (ssh only), §3.5.6 kubernetes context sanitization (kubernetes only), the kubernetes defaults (kubernetes only), then persists. A `provider.update` that only echoes unchanged values still bumps `updatedAt` (1.x autosave behavior) unless spec 04 specifies a no-op shortcut; this spec does not.

Running lock (§3.5.7) applies. All of this is atomic: any rejection leaves the row unchanged.

#### 3.5.3 Mutual exclusivity of sources

Compose (docker/podman), `ComposeSettingsView.swift:51-77`:

- Setting `composeFilePath` to a value that is non-empty after trim stores the **trimmed** value and, if `yamlConfig` is non-empty (raw, untrimmed check), clears `yamlConfig` to NULL.
- Setting `yamlConfig` to a value that is non-blank (trim-WN non-empty) and `composeFilePath` is non-empty clears `composeFilePath` to NULL.
- Setting `composeFilePath` to blank, or `yamlConfig` to blank, clears **nothing else**.

Startup script (`InitialScriptSettingsView.swift:43-68`): identical, with `initialScriptPath` ↔ `initialScript`.

If one `provider.update` (or `provider.add`) call carries **both** sources of a pair as non-blank values, the daemon rejects it with `KUMA_PRV_SOURCE_CONFLICT` instead of choosing silently (the UI sets them one at a time) [DEV-64]. A stored provider that already has both (legacy/import) stays valid; the runtime precedence is path over YAML for compose; for the startup script the runner takes the path when set (06).

#### 3.5.4 SSH key versus password (`ProviderSSHAuth.swift`) [ADD-60]

`sshAuthType` is not a column. The daemon accepts an optional param `sshAuthType` (`"key"` or `"password"`) on `service.create` (nested provider), `provider.add`, `provider.update`; invalid text is `KUMA_DAT_INVALID_ENUM`.

Algorithms (1.x names in parentheses):

- `inferredAuthType(provider)`: `password` if the **decrypted** `sshPassword` trimmed is non-empty, else `key`. An undecryptable ciphertext counts as no password ([02](02-security-and-secrets.md)).
- Auth-type change (`applyAuthTypeChange`): to `key` → `sshPassword := NULL`, and if `sshKeyPath` is blank → `sshKeyPath := "~/.ssh/id_ed25519"`; to `password` → `sshKeyPath := NULL`.
- Persist normalization (`normalizeForPersistence`, applied on **every** inspector commit of an ssh provider, `+AutoSave.swift:49-51`): effective type `key` → `sshPassword := NULL`; `password` → `sshKeyPath := NULL`. It does **not** fill a default key path.

Daemon resolution of the effective auth type for `provider.add`/`provider.update` of an ssh provider (the final type is ssh):

1. If `sshAuthType` is supplied, it is used. If it differs from the inferred type of the stored provider, the auth-type-change rule runs first, then the patch fields are applied on top.
2. Else, if the patch sets `sshPassword` to a non-blank value and **not** `sshKeyPath` to a non-blank value → `password`. If it sets `sshKeyPath` non-blank and not a non-blank password → `key`. If it sets both non-blank → `KUMA_PRV_SSH_AUTH_CONFLICT`.
3. Else the type is inferred from the stored provider (after the patch).
4. Then persist normalization runs.

`service.create` with an ssh provider: `sshAuthType` default `key`. `key` stores `sshKeyPath` (absent → `~/.ssh/id_ed25519`; present → trimmed; empty → NULL) and `sshPassword := NULL`. `password` stores the trimmed `sshPassword` (only when non-empty) and `sshKeyPath := NULL`. A key path supplied together with `password` auth (or a password with `key` auth) is ignored (`CreateServicePayloadBuilder.swift:26-32, 67-68`).

The validator and preflight use the inferred type (§3.7, TC-RUN04): a stored password makes `ssh.password` the active rule and the key rules inactive; otherwise the key rules apply.

#### 3.5.5 Provider type change (inline form edit, `ServiceProvidersSectionView.swift:133-145`)

The inline "Edit Provider" form changes only `label` and `type` (`updated.label = label; updated.type = formType; updated.updatedAt = Date()`). **No field is migrated, cleared or defaulted by the type change**; all 32 columns keep their values. Consequences the daemon MUST preserve:

- A `provider.update` with `type` changes only the category; the card string and validation immediately follow the new category over the old columns (for example `kubernetes` → `shell`: `resolvedTarget` becomes `Shell script` because `runCommand` is NULL, and the validator reports `shell.command`).
- Defaults of the new category are **not** applied by a type change, except the kubernetes defaults (`kubeTargetType`/`usePattern`) when the new type is `kubernetes` (rule §3.4).
- The service's port mappings of the provider stay attached (the rows are keyed by `providerID`); for a non-port category they are ignored by the validator and by `resolvedTarget`.
- The change is **not** a restart; the running lock (§3.5.7) forbids it while operational.
- The `provider.update` patch that includes `type` is validated against the **new** type for foreign fields (§3.5.2).

#### 3.5.6 Kubernetes context sanitization (`KubeConfigViewModel.swift:135-147`, `+AutoSave.swift:52-55`, `InspectorKubernetesFormSection.swift:22-30,52-58`)

`resolveContextName(stored, yaml)` (07 owns the YAML parser): `stored` if it is present in the kubeconfig's context names; else the kubeconfig's `current-context` if present in the names; else the first context name; else none. `sanitizedProviderContext(stored)` = that name, or NULL when none.

In 1.x the inspector rewrites `provider.kubeContext` with the sanitized value whenever the kubeconfig selection changes, the context list reloads, and on every commit. The daemon applies it on `provider.update` of a kubernetes provider **only when the patch contains `kubeConfigID` or `kubeContext`**, and **only when the effective kubeconfig yields at least one context**; when it yields none (unreadable, empty, no contexts) the stored/supplied value is kept [DEV-65]. The effective kubeconfig is the patch's `kubeConfigID`, else the stored one, else Default.

#### 3.5.7 Running lock [DEV-63]

1.x disables every provider edit control while `isLocked = service.isDisabled || execution.isOperational || state == .starting` (`ServiceInspectorView.swift:39`), and hides provider edit/delete/select in `ProviderItemRowView.swift:73-87` and the add button (`helpWhenDisabled: "Stop service to add providers"`). `isOperational` is true for `running`, `starting`, `reconnecting` (`ServiceExecutionState.swift:16-23`); `stopping`, `idle`, `crashed`, `failed` are not.

The daemon enforces the **safety part** server-side: while the service's execution state is `running`, `starting` or `reconnecting`, `provider.add`, `provider.update`, `provider.delete`, `provider.set_ports` fail with `KUMA_PRV_LOCKED` (message `Settings are read-only while active.`). A `stopping` service is editable. A **disabled** service is editable through the API (the 1.x lock on disabled services is a UI affordance; disabling is reversible and does not touch a live process). `service.switch_provider` is **not** locked (the deck switches providers on a running service by stopping, switching and restarting, `+Providers.swift:4-55`; owned by 04/06).

#### 3.5.8 `provider.delete` and the last provider

- The delete confirmation in 1.x reads `‘<displayName>’ and its settings will be deleted.` ([CLIENT]).
- The inspector offers Delete only when `providers.count > 1` (`ServiceProvidersListView.swift:38`); the daemon enforces this: deleting the only provider of a service fails with `KUMA_PRV_LAST_PROVIDER` [DEV-63]. (A service without providers can still exist through imports; the validator then reports `provider.missing`.)
- If the deleted provider was active, `activeProviderID := first remaining provider by createdAt` ([01 §3.11.1](01-data-model.md)). Port mappings cascade ([01 §3.11.5](01-data-model.md)).
- The running lock applies (a running service keeps its provider).

### 3.6 `service.create`: provider payload and form validity

#### 3.6.1 Creation defaults (`CreateServiceSaving.swift:30-57`, `CreateServiceCreationDefaults.swift`)

- `starOnCreate` (default false) → `service.isStarred = true`.
- `initialGroupID` (default none) → `service.groupIDs = [initialGroupID]`.
- `isDisabled` from the general draft (default `false`; the create form has no disable toggle).
- The service and its provider are inserted in one transaction via `insertService(service, defaultProvider:, portMappings:)`; `insertService` forces the mapping's `serviceID` and a default `providerID` ([04](04-workspaces-groups-services.md)). `service.activeProviderID` stays NULL on create (the first provider is the effective active one, [01 §3.11.1](01-data-model.md)).
- `name` trimmed; `description` trimmed, NULL if empty.
- The create form's pre-selected category is `kubernetes` [CLIENT]. The sheet's default port rows is one empty row [CLIENT]; the daemon receives only the rows the client sends.

#### 3.6.2 Field mapping per category (`CreateServicePayloadBuilder.buildPayload`, `:7-95`, `+ComposeDraft.swift:4-24`)

Rule **CR-TRIM**: a text field is stored as NULL when the **untrimmed** input is the empty string; otherwise as the trimmed text (a whitespace-only input therefore stores `""`, not NULL — unreachable for required fields because `isFormValid` rejects blanks first).

| Column | Stored value |
|--------|--------------|
| `type` | selected category |
| `kubeConfigID` | kubernetes: the selected id (Default when absent); other categories NULL |
| `kubeContext`, `kubeNamespace`, `targetName` | kubernetes: CR-TRIM; others NULL |
| `kubeTargetType`, `usePattern` | **all categories**: draft raw value (default `pod` / `true`) |
| `yamlConfig`, `initialScript` | docker/podman: as typed, NULL iff empty (**not** trimmed); others NULL |
| `composeFilePath`, `initialScriptPath` | docker/podman: trimmed, NULL if the trimmed text is empty; others NULL |
| `runCommand`, `workingDirectory` | shell: CR-TRIM; others NULL |
| `sshHost`, `sshUser` | ssh: CR-TRIM; others NULL |
| `sshPort` | ssh: `swift-int(trimmed text) ?? 22`; others NULL |
| `sshKeyPath` | ssh with `key`: trimmed text if the text is non-empty (default `~/.ssh/id_ed25519`), else NULL; others NULL |
| `sshPassword` | ssh with `password`: trimmed text if non-empty, else NULL; others NULL |
| `httpCheckUrl` | httpCheck: if the untrimmed text is non-empty: `normalize(text) ?? text.trimmed`; else NULL |
| `httpCheckInterval` | httpCheck: the interval (default 5); others NULL |
| `tunnelType` | tunnel: engine raw value (default `cloudflare`); others NULL |
| `tunnelTargetUrl` | tunnel: CR-TRIM (default text `http://localhost:3000`); others NULL |
| `ngrokAuthToken` | tunnel with engine `ngrok` and a trimmed token non-empty: the trimmed token; else NULL |
| `monitorProcessName` | processMonitor: CR-TRIM; others NULL |
| `monitorInterval` | processMonitor: the interval (default 5); others NULL |
| `label`, `customKubeConfigPath` | NULL |
| `autoReconnect` | `false` |

Port mappings are built for **kubernetes and ssh only**: each row with `swift-int(local)` and `swift-int(remote)` both present and both `> 0` becomes a mapping `{id: rowID, serviceID, providerID, localPort, remotePort, protocolType: "TCP"}`; all other rows are dropped silently (`:78-92`). No upper bound and no duplicate check is applied here; `isFormValid` (below) is the gate. For other categories the list is empty.

Quirk (not reproduced by the daemon, listed for [CLIENT] authors): `buildPayload` runs `Int(item.local)` on the **untrimmed** string, so `" 80"` passes `isFormValid` (which trims) and is then dropped by `buildPayload`. The wire carries integers, so this cannot occur through the API.

#### 3.6.3 Form validity (`isFormValid`, `CreateServicePayloadBuilder.swift:101-145`) and daemon enforcement

The daemon MUST evaluate these rules on `service.create` and reject the call with `KUMA_PRV_CREATE_INVALID` (details: the ordered list of failing issues `{field, message}`; the top-level message is the first issue's message) [DEV-62 for the port part]. 1.x only disabled the Create button; the messages below reuse the validator wording where the rule exists there, and are daemon-defined only for the service name.

Order: name, port rows, category rule.

| # | Rule | Field | Message |
|---|------|-------|---------|
| 1 | `name` trimmed is non-empty | `name` | `Service name is required.` |
| 2 | kubernetes/ssh: every port row that is not blank/blank is complete (both parse as integers in 1–65535) | `ports` | `Port row <N>: enter local and remote ports (1–65535).` (N = 1-based index of the first offending row; one issue per offending row) |
| 3 | kubernetes: `kubeConfigID` resolves (§3.3.1) | `kubeConfigID` | `Select a kubeconfig.` |
| 4 | kubernetes: `kubeContext` non-blank | `kubeContext` | `Select a Kubernetes context.` |
| 5 | kubernetes: `targetName` non-blank | `targetName` | `Enter a target name (pod, service, or pattern).` |
| 6 | kubernetes: at least one complete port row | `ports` | `Add at least one complete port mapping (local and remote).` |
| 7 | docker/podman: `yamlConfig` non-blank **or** `composeFilePath` non-blank | `composeFilePath` | `Choose a compose file or paste compose YAML.` |
| 8 | shell: `runCommand` non-blank | `runCommand` | `Enter a shell command to run.` |
| 9 | ssh: `sshHost` non-blank | `sshHost` | `SSH host is required.` |
| 10 | ssh: `sshUser` non-blank | `sshUser` | `SSH user is required.` |
| 11 | httpCheck: `httpCheckUrl` non-blank | `httpCheckUrl` | `Health check URL is required.` |
| 12 | tunnel: `tunnelTargetUrl` non-blank (an absent value defaults to `http://localhost:3000` before this check) | `tunnelTargetUrl` | `Tunnel target (port or URL) is required.` |
| 13 | processMonitor: `monitorProcessName` non-blank | `monitorProcessName` | `Process name to monitor is required.` |

Deliberately **not** checked at create (parity): the URL's validity (an un-normalizable health URL is stored trimmed and blocks only at start), duplicate local ports (`ports.duplicate_local` blocks at start), ssh ports being present, ssh auth credentials, kubeconfig connectivity, context existence, file existence of paths, the ngrok token, interval values, `sshPort` range.

Port rows for categories other than kubernetes/ssh are rejected with `KUMA_PRV_PORTS_NOT_APPLICABLE` (`Port mappings apply only to Kubernetes and SSH providers.`) [DEV-62]; 1.x dropped them silently. Port values are integers on the wire; a value outside 1–65535 is row-invalid (rule 2) and message `Port row <N>: enter local and remote ports (1–65535).` applies.

#### 3.6.4 Port-row rules (shared by create, inspector commit, `provider.set_ports`, validator)

- A row has `local` and `remote`. **Blank row**: both blank after trim → ignored everywhere (not an error, not persisted).
- **Complete row**: both parse as swift-int and each is in `1...65535`. Everything else non-blank is an **invalid row**.
- Inspector commit (`+AutoSave.swift:57-68`) persists only rows with both integers `> 0` (no upper bound) and `protocolType: "TCP"`, replacing the provider's rows (`savePortMappings` delete-by-(serviceID, providerID) then insert; a duplicate row id inside one batch gets a fresh UUID, [01 §3.11.4](01-data-model.md)), and **only when the ports were touched**. Invalid/partial rows are dropped silently by 1.x.
- Daemon `provider.set_ports` and the create path: rows arrive as integers; they must all be complete (rule 2 of §3.6.3 with the same message and `KUMA_PRV_PORT_INVALID`), the provider's type must be kubernetes or ssh unless the list is empty, and the lock applies [DEV-62, DEV-63]. Duplicate local ports are accepted by the write and reported by preflight (parity: 1.x let the user type them and blocked at start).
- The client editor [CLIENT]: placeholders `Local` / `Remote`; per-row red outline when the field is non-empty and not an integer in 1–65535; banner title `Invalid Port Number`, message `Port must be a valid integer between 1 and 65535.`; "Add port mapping" link (disabled help `Stop service to edit ports`); the minus button removes the row, or empties it when it is the only row; at least one (empty) row is always shown.

### 3.7 `ServiceConfigurationValidator`

`issues(service, provider, context) -> [ConfigurationIssue]` (`ServiceConfigurationValidator.swift:34-69`). It is **pure** apart from the filesystem existence checks and tilde expansion; it has no other side effect in the daemon [DEV-60].

#### 3.7.1 Context inputs (`ServiceConfigurationValidationContext`, `:3-29`)

| Field | Type | Default | Meaning | Daemon source (preflight, §3.8) |
|-------|------|---------|---------|----------------------------------|
| `sshAuthType` | `key` / `password` | `key` | Which ssh credential rule runs | inferred (§3.5.4) |
| `ports` | rows of `{local, remote}` strings | `[]` | Port rows | the persisted mappings of the provider ([01 §3.11.2](01-data-model.md), explicit provider id), each as decimal strings, in `rowid` order |
| `kubeConfigID` | UUID? | none | Selected kubeconfig | effective id (provider's, else Default) if resolvable, else none |
| `kubeContext` | string? | none | Sanitized context | §3.5.6 `resolveContextName`, empty → none |
| `kubeConnectionError` | string? | none | Last connection probe error | probe result |
| `kubeIsConnecting` | bool | `false` | Probe in flight | always `false` in the daemon (the probe is awaited) |
| `kubeAsyncMessage` | string? | none | Target-resolution failure text | phase 2 of §3.8 |

#### 3.7.2 Algorithm

1. If `service.isDisabled` → return `[]` (a disabled service is never validated; `hasBlockingIssues([])` is false).
2. If `provider` is none → return `[provider.missing]`.
3. Append the port issues (§3.7.4; non-empty only for kubernetes and ssh).
4. Append the category issues (`kubernetes` §3.7.5, `docker`/`podman` §3.7.6, `shell` §3.7.7, `ssh` §3.7.8, `httpCheck` §3.7.9, `tunnel` §3.7.10, `processMonitor` §3.7.11).
5. If `provider.type == kubernetes` and `kubeAsyncMessage` trimmed is non-empty → append `k8s.target_resolve` with the **trimmed** message (`:62-66`).
6. Return the list in that order. Codes are unique within a result.

`hasBlockingIssues(issues)` = any issue with severity `blocking` (`:71-73`). `ConfigurationIssue` has `code`, `message`, `severity` (`blocking` or `warning`; default `blocking`), identity = `code` (`ConfigurationIssue.swift`). **Every rule below emits `blocking`; no rule emits `warning` in 1.x**; the enum value exists for forward use and the wire keeps both strings.

#### 3.7.3 Short-circuit and provider rows

| Code | Category | Condition | Exact message | Severity |
|------|----------|-----------|---------------|----------|
| (none: empty list) | all | `service.isDisabled` | — | — |
| `provider.missing` | all | no provider (service without providers, `:39-41`) | `Add a provider before starting this service.` | blocking |

#### 3.7.4 Port rules (`portIssues`, `:77-121`; kubernetes and ssh only)

Rows are trimmed first. Evaluation:

| Code | Category | Condition | Exact message | Severity |
|------|----------|-----------|---------------|----------|
| `ports.invalid_row_<i>` (`<i>` is the **0-based** index among all rows, blank rows counted) | kubernetes, ssh | row not blank/blank and not complete (§3.6.4) | `Port row <i+1>: enter local and remote ports (1–65535).` (en dash U+2013) | blocking |
| `ports.required` | kubernetes, ssh | zero complete rows; **returns immediately** (no duplicate check follows) | `Add at least one complete port mapping (local and remote).` | blocking |
| `ports.duplicate_local` | kubernetes, ssh | at least two complete rows share the same local port (`Set` count differs) | `Each local port must be unique.` | blocking |

Invalid-row issues are emitted first (in row order), then `ports.required` or `ports.duplicate_local`. A complete row such as `"+80"`/`"80"` passes (swift-int). Remote ports may repeat.

#### 3.7.5 Kubernetes (`kubernetesIssues`, `:124-155`)

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `k8s.kubeconfig` | `context.kubeConfigID` is none | `Select a kubeconfig.` | blocking |
| `k8s.context` | `context.kubeContext` trimmed is empty | `Select a Kubernetes context.` | blocking |
| `k8s.target` | `provider.targetName` trimmed is empty | `Enter a target name (pod, service, or pattern).` | blocking |
| `k8s.unreachable` | `kubeIsConnecting` is false **and** `kubeConnectionError` trimmed is non-empty (the issue message **is** the trimmed error text) | `<connection error text>` (default probe text `Unable to reach cluster`; other texts in [07](07-kubernetes.md): `Empty kubeconfig content`, `kubectl binary not found in system PATH`, `Validation cancelled`, kubectl stderr) | blocking |
| `k8s.target_resolve` | appended by step 5 of §3.7.2 | the trimmed async text (see §3.8.3 for the texts) | blocking |

When `kubeIsConnecting` is true the function returns **before** the `k8s.unreachable` check (so the three required-field issues may be present but never `k8s.unreachable`).

#### 3.7.6 Docker and Podman (`composeIssues`, `:159-200`)

Let `hasPath` = `composeFilePath` non-blank, `hasYAML` = `yamlConfig` non-blank.

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `compose.missing` | `!hasPath && !hasYAML` — **returns immediately** (the startup-script and working-directory rules below do not run) | `Choose a compose file or paste compose YAML.` | blocking |
| `compose.invalid` | `ComposeStackResolver.resolve` throws. With `hasPath`: the trimmed path, tilde-expanded, is not an existing regular file → message is the error description `Invalid configuration: Compose file not found: <rawPath>` (`<rawPath>` = trimmed, **not** expanded; note the `Invalid configuration: ` prefix is part of this validator message). With only `hasYAML`: resolution succeeds unless the temp write fails (`Execution failed: Failed to write compose YAML: <error>`) — the daemon does not write the file at preflight [DEV-60], so this branch never fires | `Invalid configuration: Compose file not found: <rawPath>` | blocking |
| `compose.startup_script` | `initialScriptPath` trimmed non-empty and (not exists, or is a directory) | `Startup script file not found: <rawPath>` | blocking |
| `compose.working_dir` | `workingDirectory` trimmed non-empty and (not exists, or not a directory) | `Working directory does not exist: <rawDir>` | blocking |

`compose.invalid` + `compose.startup_script` + `compose.working_dir` can co-occur. The inline `initialScript` is never checked. When `hasPath` is true the YAML is irrelevant (path wins).

#### 3.7.7 Shell (`shellIssues`, `:204-218`)

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `shell.command` | `runCommand` trimmed empty | `Enter a shell command to run.` | blocking |
| `shell.working_dir` | `workingDirectory` trimmed non-empty and (not exists, or not a directory) | `Working directory does not exist: <rawDir>` | blocking |

#### 3.7.8 SSH (`sshIssues`, `:222-252`)

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `ssh.host` | `sshHost` trimmed empty | `SSH host is required.` | blocking |
| `ssh.user` | `sshUser` trimmed empty | `SSH user is required.` | blocking |
| `ssh.password` | `context.sshAuthType == password` and `sshPassword` (decrypted) trimmed empty | `SSH password is required.` | blocking |
| `ssh.key` | `sshAuthType == key` and `sshKeyPath` trimmed empty | `SSH private key path is required.` | blocking |
| `ssh.key_missing` | `sshAuthType == key`, key path non-empty and the tilde-expanded path does not exist (a directory counts as existing) | `SSH private key file not found: <keyPath>` (`<keyPath>` = trimmed, not expanded) | blocking |

Order: host, user, then the auth-branch issues. Only one auth branch runs.

#### 3.7.9 Health check (`healthCheckIssues`, `:256-264`)

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `health.url` | `httpCheckUrl` trimmed empty (returns) | `Health check URL is required.` | blocking |
| `health.url_invalid` | `URLNormalizer.normalize(trimmed)` is none (default `defaultToHttps: true`) | `Health check URL is not valid.` | blocking |

#### 3.7.10 Tunnel (`tunnelIssues`, `:267-281`)

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `tunnel.target` | `tunnelTargetUrl` trimmed empty | `Tunnel target (port or URL) is required.` | blocking |
| `tunnel.ngrok_token` | `(tunnelType ?? "cloudflare").lowercased() == "ngrok"` and `ngrokAuthToken` (decrypted) trimmed empty | `Ngrok auth token is required.` | blocking |

The target is not run through `URLNormalizer` by the validator. Engine text other than `ngrok` (any case) is the cloudflare path.

#### 3.7.11 Process monitor (`processMonitorIssues`, `:283-289`)

| Code | Condition | Exact message | Severity |
|------|-----------|---------------|----------|
| `monitor.process` | `monitorProcessName` trimmed empty | `Process name to monitor is required.` | blocking |

#### 3.7.12 Where the validator runs in 1.x (parity facts)

- Only the **inspector Start button** (and a provider switch of a running service from the inspector) runs it (`+Execution.swift:21-26`, `+Providers.swift:34-37`). `canStartService` itself checks only: not loading, service not disabled, active provider exists (`+Validation.swift:5-9`). The deck, bulk start and auto-resume start paths call the runners directly and **never** run the validator.
- Editing any field clears the shown issues (`scheduleAutoSave`, `+AutoSave.swift:22-24`); the inspector re-validates only when the user starts.
- Therefore `service.start` MUST NOT run the validator (INV-D-PRV-03). Clients that want inspector behavior call `service.preflight` and then `service.start`.

### 3.8 `service.preflight` [V2-ADD ADD-01]

Read-only RPC that returns what the inspector's Start button would have computed. Params and result are in §4.3.

#### 3.8.1 Algorithm

1. Load the service (`KUMA_SVC_NOT_FOUND` from [04](04-workspaces-groups-services.md) if absent). Choose the provider: `providerID` if supplied (must belong to the service, else `KUMA_PRV_PROVIDER_NOT_FOUND`); else the effective active provider ([01 §3.11.1](01-data-model.md)); if the service has none, the provider is none and `provider.missing` results.
2. If `service.isDisabled`: result `{ok: true, serviceDisabled: true, issues: []}`; stop.
3. Build the context (§3.7.1): `ports` from the persisted mappings of the chosen provider; `sshAuthType` inferred; for kubernetes, the effective kubeconfig and sanitized context (§3.5.6), probe error per step 4; `kubeIsConnecting = false`.
4. **Kubernetes probe** (only when type is kubernetes, `probe` is true and the kubeconfig resolved): run the same operation as `kubeconfig.test_connection` ([07](07-kubernetes.md): `kubectl --kubeconfig <tmp> version --output=yaml --request-timeout=4s [--context X]`, success = exit 0 and output contains `serverVersion` or `gitVersion`; cache key `sha256(content::context)`; `refresh: true` bypasses the cache). `kubeConnectionError = null` when reachable, else `errorMessage ?? "Unable to reach cluster"`.
5. **Phase 1:** `issues1 = ServiceConfigurationValidator.issues(...)` with `kubeAsyncMessage = null`. If any issue is blocking, or the provider is not kubernetes, or `probe` is false, return `issues1`.
6. **Phase 2 (kubernetes only):** resolve the kubectl binary through the settings resolver ([03](03-settings-and-environment.md)); if absent, `asyncMessage = "Required binary 'kubectl' could not be located on this Mac."`. Else `KubeConfigExecutionResolver.resolve` for a copy of the provider with the sanitized `kubeConfigID`/`kubeContext`, then `KubeTargetResolver.resolve` (it runs `kubectl get <resource>` only when pattern matching is on or the pod name looks like a stable workload name, [07](07-kubernetes.md)). Any thrown error → `asyncMessage` = its description; success → `asyncMessage = null` and the resolved `{kind, name}` is reported in `kubernetes.target`.
7. `issues2 = validator.issues(...)` with `kubeAsyncMessage = asyncMessage`; return it.
8. `ok` = no blocking issue. `probed` = true iff steps 4 or 6 executed.
9. If `recordToActivityLog` is true and any blocking issue exists: for each blocking issue message (trimmed, non-empty) append the log line `[CONFIG] <message>` to the service's activity buffer unless an identical line already exists in it, then always append `[KUMA] Start blocked: fix configuration issues above.` (`+Validation.swift:52-61`, `LiveLogSession.swift:164-174`; mechanics and the `config` category are owned by [08](08-logs-and-events.md)).

Preflight performs **no database write**, no file write (no compose YAML temp file, DEV-60), starts no process, and does not change `updatedAt` or any state. The kubeconfig probe cache MAY be updated (it is a cache, not state).

#### 3.8.2 Issue `field` mapping [V2-ADD]

`field` is the JSON key of the provider column the client should highlight (`null` when none).

| Code | `field` |
|------|---------|
| `provider.missing` | `null` |
| `ports.invalid_row_<i>`, `ports.required`, `ports.duplicate_local` | `ports` |
| `k8s.kubeconfig`, `k8s.unreachable` | `kubeConfigID` |
| `k8s.context` | `kubeContext` |
| `k8s.target`, `k8s.target_resolve` | `targetName` |
| `compose.missing` | `composeFilePath` |
| `compose.invalid` | `composeFilePath` |
| `compose.startup_script` | `initialScriptPath` |
| `compose.working_dir`, `shell.working_dir` | `workingDirectory` |
| `shell.command` | `runCommand` |
| `ssh.host` | `sshHost` |
| `ssh.user` | `sshUser` |
| `ssh.password` | `sshPassword` |
| `ssh.key`, `ssh.key_missing` | `sshKeyPath` |
| `health.url`, `health.url_invalid` | `httpCheckUrl` |
| `tunnel.target` | `tunnelTargetUrl` |
| `tunnel.ngrok_token` | `ngrokAuthToken` |
| `monitor.process` | `monitorProcessName` |

#### 3.8.3 Texts of `k8s.target_resolve` (message = the error description)

| Cause | Message |
|-------|---------|
| `kubectl` not found | `Required binary 'kubectl' could not be located on this Mac.` |
| Dangling kubeconfig (cannot occur after `k8s.kubeconfig` blocks) | `Invalid configuration: Selected kubeconfig no longer exists.` |
| Kubeconfig file missing / empty | `Invalid configuration: Kubeconfig file not found at <rawPath>.` / `Invalid configuration: Selected kubeconfig is empty.` |
| Pattern discovery: stderr non-empty | `Execution failed: Kubectl <pods|services|deployments> discovery error: <stderr>` |
| Pattern discovery: nothing listed | `Execution failed: No running pods found in namespace '<ns or default>'.` (pod) / `Execution failed: No <services|deployments> found in namespace '<ns or default>'.` |
| Nothing matched | `Execution failed: Found <N> <resource> in '<ns or default>', but none matched '<targetName>'. Examples: <first 3 names, comma separated>` |

(Exact discovery behavior, argv and timeouts: [07](07-kubernetes.md); `KubeTargetResolver.swift:23-25,100-118`.)

### 3.9 Message sets and which surface shows which

Two sets exist for the same underlying problems. **Set A** is the validator text (returned by `service.preflight`). **Set B** is the runner `ServiceExecutionError.invalidConfiguration(msg)` text, whose user-facing description is `Invalid configuration: <msg>` (`ServiceExecutionEngine.swift:19-20`); it is what `service.start` (and deck/bulk/auto-resume starts) report as the failure message. Other descriptions in the same enum: `processFailed(reason)` → `Execution failed: <reason>`; `binaryNotFound(name)` → `Required binary '<name>' could not be located on this Mac.`; `noActiveProvider` → `No active runner provider is configured for this service.`

| Problem | Set A (preflight) | Set B (`service.start` error text) |
|---------|-------------------|-------------------------------------|
| No provider | `provider.missing`: `Add a provider before starting this service.` | `No active runner provider is configured for this service.` |
| k8s: no kubectl | `k8s.target_resolve`: `Required binary 'kubectl' could not be located on this Mac.` | same text (`binaryNotFound`) |
| k8s: no port rows | `ports.required`: `Add at least one complete port mapping (local and remote).` | `Invalid configuration: At least one port mapping (Local:Remote) is required for Kubernetes port-forwarding.` |
| k8s: blank target | `k8s.target`: `Enter a target name (pod, service, or pattern).` | `Invalid configuration: Target resource name is required (e.g. my-app-service or pod pattern).` |
| k8s: dangling kubeconfig | `k8s.kubeconfig`: `Select a kubeconfig.` | `Invalid configuration: Selected kubeconfig no longer exists.` |
| k8s: file/empty kubeconfig | not a validator rule (appears via `k8s.target_resolve`) | `Invalid configuration: Kubeconfig file not found at <rawPath>.` / `Invalid configuration: Selected kubeconfig is empty.` |
| compose: nothing set | `compose.missing`: `Choose a compose file or paste compose YAML.` | `Invalid configuration: No compose file or YAML configured` |
| compose: path missing | `compose.invalid`: `Invalid configuration: Compose file not found: <rawPath>` | `Invalid configuration: Compose file not found: <rawPath>` |
| compose: script path missing | `compose.startup_script`: `Startup script file not found: <rawPath>` | `Invalid configuration: Startup script file not found: <rawPath>` |
| compose: working dir missing | `compose.working_dir`: `Working directory does not exist: <rawDir>` | not an error: the directory is ignored |
| docker/podman binary | not checked | `Required binary '<docker or podman>' could not be located on this Mac.` |
| shell: blank command | `shell.command`: `Enter a shell command to run.` | `Invalid configuration: No shell command specified.` |
| shell: working dir | `shell.working_dir`: `Working directory does not exist: <rawDir>` | `Invalid configuration: Working directory does not exist: '<rawDir>'` |
| ssh: host | `ssh.host`: `SSH host is required.` | `Invalid configuration: SSH Host is not configured.` |
| ssh: user | `ssh.user`: `SSH user is required.` | none (defaults to the login name) |
| ssh: password auth, blank | `ssh.password`: `SSH password is required.` | none (no credential flags; `ssh` prompts/fails at run) |
| ssh: key auth, blank | `ssh.key`: `SSH private key path is required.` | none |
| ssh: key file missing | `ssh.key_missing`: `SSH private key file not found: <keyPath>` | `Invalid configuration: SSH private key file not found: '<keyPath>'` |
| ssh: no ports | `ports.required` | `Invalid configuration: At least one port mapping (Local:Remote) is required for SSH tunneling.` |
| health: blank | `health.url`: `Health check URL is required.` | `Invalid configuration: Health Check Target URL is not specified.` |
| health: not normalizable | `health.url_invalid`: `Health check URL is not valid.` | `Invalid configuration: Invalid Health Check URL: '<rawUrl>'.` |
| tunnel: blank target | `tunnel.target`: `Tunnel target (port or URL) is required.` | `Invalid configuration: Tunnel target (port or local URL) is required.` |
| tunnel: ngrok token | `tunnel.ngrok_token`: `Ngrok auth token is required.` | not required |
| tunnel: binary | not checked | `Required binary 'cloudflared' could not be located on this Mac.` (cloudflare) / `Required binary 'ngrok' could not be located on this Mac.` (ngrok) |
| monitor: blank name | `monitor.process`: `Process name to monitor is required.` | `Invalid configuration: Process name to monitor is required.` |

Surfaces: `service.preflight` returns set A only. `service.start`, `service.start_all`, auto-resume and a provider switch of a running service from the deck return set B (as the failure message / `KUMA_EXE_*` code owned by [06](06-execution-engine.md)). The inspector uses set A before its own start, then set B is reachable only if the runner still fails.

#### 3.9.1 [CLIENT] hints for the inspector banner

- Banner (service stopped with at least one blocking issue): title `Can't start yet` (straight apostrophe), subtitle = first blocking message; if there are N additional blocking issues the subtitle is `<first.message> (+N more)` (`InspectorRunningBanner.swift:30-36,94`). Other banner texts: running `Settings are read-only while active.`, starting `Bringing the runner online.`.
- The live-console view receives all blocking messages (`blockingConfigurationMessages`).
- Start is disabled by the client when the daemon reports no active provider or a disabled service (`canStartService`, `+Validation.swift:5-9`).

### 3.10 `URLNormalizer`

Used by: create-time health URL storage (§3.3.5), validator `health.url_invalid`, `HealthCheckRunner` (default `defaultToHttps: true`), `TunnelRunner` (`defaultToHttps: false`, fallback `http://localhost:3000`). The daemon exposes it only through those paths (there is no standalone RPC). Pure function, no I/O.

#### 3.10.1 `normalize(raw, defaultToHttps = true) -> String?`

1. `s = trim-WN(raw)`. If empty → none.
2. **Quotes:** if (`s` starts with `"` and ends with `"`) or (starts with `'` and ends with `'`) — a single-character `"` or `'` satisfies both tests — then `s = s` without its first and last character, `s = trim-WN(s)`; if empty → none. Only one layer is stripped. A string that starts with a quote but does not end with the same quote is untouched.
3. **Case 1, pure port:** `p = s` without one leading `:` if `s` starts with `:`, else `s`. If `swift-int(p)` exists and `0 < n <= 65535` → return `http://localhost:<n>` (decimal, no leading zeros, `+` and leading zeros removed: `+80` → 80, `03000` → 3000). Otherwise continue (`:0`, `65536`, `-5`, `0` fall through).
4. **Case 2, has scheme:** if `lowercase(s)` starts with `http://` or `https://` → return `s` if `isValidURL(s)` else none. The returned string is `s` **verbatim** (original casing of scheme and host, not re-serialized).
5. **Case 3, malformed scheme:** `fix(s)`: with `lower = lowercase(s)` test in order: starts with `http:/` (and not `http://`) → `http://` + `s` minus its first 6 characters; starts with `https:/` (not `https://`) → `https://` + `s` minus its first 7 characters; starts with `http//` → `http://` + `s` minus first 6; starts with `https//` → `https://` + `s` minus first 7; else no fix. The remainder keeps its original casing; the scheme is written lowercase. (The "already http://" test at the top of `fixMalformedScheme` is unreachable after step 4.) If a fix exists → return it if `isValidURL` else none (a fix **ends** the algorithm; there is no fallthrough).
6. **Case 4, no scheme:** `isLocal(s)`: `lower = lowercase(s)`; `hostPart` = the first non-empty segment of `lower` split on `/` (empty segments omitted; empty string if none); `host` = the first non-empty segment of `hostPart` split on `:` (empty segments omitted; empty if none). `isLocal` = `host` equals `localhost`, `127.0.0.1`, `0.0.0.0` or `::1`, or ends with `.local`. Note: the split is on `/` and `:` only (not `?`, `#`, `@`), `::1` and `[::1]:8080` therefore never match (their first `:`-segment is `1` and `[`), and `user@localhost` is not local.
   `scheme = "http://"` if `isLocal` or `defaultToHttps == false`, else `"https://"`; `candidate = scheme + s`; return `candidate` if `isValidURL(candidate)` else none.

Notable consequences (all verified): `ftp://x.com` → `https://ftp://x.com` (the `ftp` is treated as a host); `http:` → `https://http:`; `http:x.com` → none; `file:///tmp/x` → `https://file:///tmp/x`; the returned string preserves the user's text byte for byte after the prefix (spaces in paths stay).

#### 3.10.2 `isValidURL(candidate)`: exact predicate

1:1 reimplementation of `URL(string:)` + `scheme in {http, https}` + `host` non-empty. `candidate` always starts, case-insensitively, with `http://` or `https://` when called from `normalize`. Let `rest` be the text after `://`.

1. **Authority** = `rest` up to (not including) the first `/`, `?` or `#` (or the end). Path, query and fragment (the remainder) are **not validated at all**: any characters (spaces, controls, non-ASCII, `\`, malformed `%`) are accepted.
2. If the authority contains `@`, `hostport` = the text after the **last** `@` (the userinfo before it is **not validated**: any characters, including controls); else `hostport` = the authority.
3. If `hostport` is empty → invalid.
4. **Bracketed host** (`hostport` starts with `[`): it must contain `]`; `lit` = the text between `[` and the first `]`; `after` = the text after that `]`. `lit` must be non-empty. The part of `lit` **before its first `%`** (all of `lit` when it has no `%`) must contain none of the forbidden characters F (below); the part from the first `%` on (a zone id) is unrestricted. `lit` is **not** checked to be an IP address (`[zz]`, `[1::2::3]`, `[v1.x]` are valid). `after` must be empty, or `:` followed by zero or more ASCII digits.
5. **Plain host:** if `hostport` contains more than one `:` → invalid. If it contains one `:` the text before is `host`, the text after is `port`, and `port` must be zero or more ASCII digits `0-9` (**empty is allowed**; any number of digits; **no range check**: `:99999` and `:0` and `:999999999999` are valid; `+`, `-`, spaces, Unicode digits are invalid). `host` must be non-empty.
6. **Host characters:** let F be: ASCII control characters U+0000–U+001F, U+0020 space, U+007F, and the characters `"` `<` `>` `[` `\` `]` `^` `` ` `` `{` `|` `}`. Every ASCII character not in F is allowed in a host, including `!` `$` `&` `'` `(` `)` `*` `+` `,` `;` `=` `-` `.` `_` `~` letters, digits. `%` is allowed only as a percent-escape `%HH` (two hex digits); the host is percent-decoded and the resulting bytes must be valid UTF-8 (`%a1` alone is invalid; `%41` → `A` valid; `%00` valid; `%zz` and a trailing `%4` invalid). A decoded character is **not** re-checked against F (`a%2Fb.com` is valid).
7. **Non-ASCII hosts** (any non-ASCII character in `host`): valid iff UTS #46 IDNA processing to ASCII succeeds (non-transitional, `CheckHyphens` on, no STD3 rules, no DNS length checks); in practice: a label starting or ending with `-` fails (`-é.com`, `é-.com`, `a.é-`), an empty non-final label fails (`é..com`, `.é`), a single trailing dot is allowed (`é.`, `日本.`), a label starting with `xn--` plus non-ASCII fails, a leading combining mark fails, U+FFFD fails; `é.com`, `日本.jp`, `ß.com`, `é--a.com`, `é_a.com`, `exämple.com`, zero-width characters (U+200B, U+00AD) are accepted. Fullwidth forms are mapped (`ａ.com` valid). Residual divergence risk is recorded as R-05 in the residual risks; the acceptance corpus pins the cases listed above. An ASCII-only host never goes through IDNA (`xn--.com`, `a..com`, `-.com`, `-`, `_` are valid).
8. The scheme test is implied (`http`/`https` only). The result is true iff all checks pass.

#### 3.10.3 `URLNormalizerTests` (verbatim expectations)

| Test | Input | Expected |
|------|-------|----------|
| TC-U01 | `google.com` | `https://google.com` |
| TC-U02 | `http.google.com` | `https://http.google.com` |
| TC-U03 | `http://google.com/search?q=kuma` | `http://google.com/search?q=kuma` |
| TC-U03 | `https://google.com/healthz` | `https://google.com/healthz` |
| TC-U04 | `localhost:3000/api` | `http://localhost:3000/api` |
| TC-U04 | `127.0.0.1:8080/health` | `http://127.0.0.1:8080/health` |
| TC-U04 | `0.0.0.0:5000` | `http://0.0.0.0:5000` |
| TC-U05 | `3000` | `http://localhost:3000` |
| TC-U05 | `:8080` | `http://localhost:8080` |
| TC-U06 | `http:/google.com` | `http://google.com` |
| TC-U06 | `https//api.example.com` | `https://api.example.com` |
| TC-U07 | `"  google.com  "` (with the double quotes) | `https://google.com` |
| TC-U07 | `'localhost:4000'` | `http://localhost:4000` |
| TC-U08 | empty string | none |
| TC-U08 | `   ` | none |
| TC-U08 | `://` | none |

#### 3.10.4 Ground-truth table (real Foundation output; `https` = default, `no-https` = `defaultToHttps: false`)

"none" = `nil`. Where the two columns are equal only one is shown.

| Input | `normalize` (https) | `normalize` (no-https) |
|-------|---------------------|-------------------------|
| `google.com` | `https://google.com` | `http://google.com` |
| `http.google.com` | `https://http.google.com` | `http://http.google.com` |
| `localhost` / `localhost/` | `http://localhost` / `http://localhost/` | same |
| `LOCALHOST:3000` | `http://LOCALHOST:3000` | same |
| `host.local`, `host.local:8080/x`, `myhost.LOCAL` | `http://host.local`, `http://host.local:8080/x`, `http://myhost.LOCAL` | same |
| `10.0.0.5`, `10.0.0.5:8080`, `192.168.1.1/health` | `https://10.0.0.5`, `https://10.0.0.5:8080`, `https://192.168.1.1/health` | `http://10.0.0.5`, `http://10.0.0.5:8080`, `http://192.168.1.1/health` |
| `foo` | `https://foo` | `http://foo` |
| `x.com?q=1`, `x.com#frag`, `x.com:80` | `https://x.com?q=1`, `https://x.com#frag`, `https://x.com:80` | `http://x.com?q=1`, `http://x.com#frag`, `http://x.com:80` |
| `user:pw@host.com` | `https://user:pw@host.com` | `http://user:pw@host.com` |
| `http://user:pw@host.com` | same (returned verbatim) | same |
| `HTTP://Google.com` | `HTTP://Google.com` | same |
| `Http:/google.com` | `http://google.com` | same |
| `HTTPS//x.com` | `https://x.com` | same |
| `http//x.com` | `http://x.com` | same |
| `0` | `https://0` | `http://0` |
| `65535` | `http://localhost:65535` | same |
| `65536` | `https://65536` | `http://65536` |
| `-5` | `https://-5` | `http://-5` |
| `+80` | `http://localhost:80` | same |
| `03000`, `  3000  `, `"3000"` | `http://localhost:3000` | same |
| `:0` | none | none |
| `::1` | none | none |
| `[::1]:8080` | `https://[::1]:8080` | `http://[::1]:8080` |
| `http://[::1]:80` | same | same |
| `http://`, `https://`, `http://:80`, `http:///path` | none | none |
| `http:/`, `https:/`, `http//`, `https//` | none | none |
| `http:` | `https://http:` | `http://http:` |
| `http:x.com` | none | none |
| `ftp://x.com` | `https://ftp://x.com` | `http://ftp://x.com` |
| `ftp.example.com` | `https://ftp.example.com` | `http://ftp.example.com` |
| `file:///tmp/x` | `https://file:///tmp/x` | `http://file:///tmp/x` |
| `tcp://x.com` | `https://tcp://x.com` | `http://tcp://x.com` |
| `a b.com`, `http://a b.com`, `exa mple.com/path` | none | none |
| `google.com/a b` | `https://google.com/a b` | `http://google.com/a b` |
| `google.com/路径` | `https://google.com/路径` | `http://google.com/路径` |
| `https://göögle.com` | same | same |
| `http://google.com:99999` | same | same |
| `google.com:99999` | `https://google.com:99999` | `http://google.com:99999` |
| `foo:bar`, `localhost:abc`, `http://x.com:abc` | none | none |
| `a..b`, `-.com` | `https://a..b`, `https://-.com` | `http://a..b`, `http://-.com` |
| `x_y.com` | `https://x_y.com` | `http://x_y.com` |
| `http://x_y.com` | same | same |
| `http://%zz.com` | none | none |
| `ex%20ample.com` | `https://ex%20ample.com` | `http://ex%20ample.com` |
| `x.com/%zz` | `https://x.com/%zz` | `http://x.com/%zz` |
| `"  google.com  "` | `https://google.com` | `http://google.com` |
| `'localhost:4000'` | `http://localhost:4000` | same |
| `""` (two double quotes), `''`, `"`, `'` | none | none |
| `"google.com`, `google.com"` | none | none |
| `/path`, `?q=1`, `#x` | none | none |
| `http://x.com` + newline + `foo` | none | none |
| empty, `   `, `://` | none | none |

Additional validity rows for `isValidURL` (prefix `https://`; `ok` = valid): `a.com:` ok; `a.com:0` ok; `a.com:65536` ok; `a.com:999999999999` ok; `a.com:-1` no; `a.com:+1` no; `a.com: 80` no; `a.com:٨٠` no; `[::1]` ok; `[::1` no; `::1]` no; `[]` no; `[::1]x` no; `[::1]:80x` no; `[::1]:` ok; `[zz]` ok; `[1::2::3]` ok; `[::1%25en0]` ok; `1.2.3.4.5` ok; `999.999.999.999` ok; `a.com\path` no; `a.com/a\b` ok; `a@b@c.com` ok (host `c.com`); `@a.com` ok; `a.com@` no; `[::1]@a.com` ok; `u@[::1]:80` ok; `.com` ok; `a.` ok; `.` ok; `a.com..` ok; `a..com` ok; `a.com:80:80` no; `a.com/%` ok; `%41.com` ok; `a%41.com` ok; `a.com%2Fb` ok; `%00.com` ok; `https:a.com` no; `https:/a.com` no; `https:///a.com` no; `?q` no; `#f` no; `a.com/ ` (trailing space inside the path) ok; `a b` no; `a!b.com`, `a$b&c'd(e)f*g+h,i;j=k.com`, `a~b.com`, `a_b.com` ok.

### 3.11 [CLIENT] hints (not daemon behavior; listed so nothing is dropped)

Provider cards in the create sheet (`CreateServiceProviderStepView.swift:23-37`): heading `Select Provider`, subtitle `Choose how this service will run`; cards in this order with title and description: Kubernetes `Port-forward service pods`; Docker `Container & service daemon`; Podman `Podman container daemon`; Shell `Local CLI shell daemon`; SSH `Remote SSH host runner`; Health Check `Ping endpoint health`; Tunnel `Cloudflare / Ngrok tunnel`; Process Monitor `Track OS process state`. Buttons `Cancel`, `Continue`.

Service name placeholder per category (`CreateServiceFillDetailsStepView.swift:98-108`): kubernetes `PostgreSQL Database`; docker and podman `Redis Cache`; shell `Frontend Dev Server`; ssh `Staging Bastion Tunnel`; httpCheck `Auth Service Health`; tunnel `Webhook Public Tunnel`; processMonitor `Redis Server Monitor`. Inspector name placeholder `Postgres DB` (subtitle `Service name and purpose`); description label `Description` with placeholder `Purpose or notes`.

Form labels and placeholders: General `Service Name`; Kubernetes sections `Kube Config` (empty list text `No kubeconfigs registered.`, action `Add Kubeconfig`, new-config name placeholder `Staging Cluster`, status chips `Connecting…` / `Unreachable` / `Connected`), `Cluster Connection` (`Context`, `Namespace` placeholder `staging`), `Target Resource` (`Target Type`, `Pattern Matching`, `Target Name`, running text `Active target: <name>`, hint `Try Deployment or Service as target type if start fails.`); Compose `Compose File` (docker file prompt `~/path/to/docker-compose.yml`, podman `~/path/to/compose.yml`; docker editor placeholder `version: '3.8'\nservices:\n  web:\n    image: nginx:alpine\n    ports:\n      - "80:80"`, podman `version: '3.8'\nservices:\n  app:\n    image: quay.io/podman/hello\n    ports:\n      - "8080:8080"`); `Startup Script` (tab `Paste Script`, file prompt `/path/to/script.sh`, editor placeholder `#!/bin/bash` + newline); Shell section `Shell Command` (`Working Directory` placeholder `~/path/to/project`, `Run Command` placeholder `npm run dev`); SSH section `SSH Connection` (`Remote Host` placeholder `bastion.company.com`, `Port` placeholder `22`, `SSH User` placeholder `ubuntu`, `Authentication`, `Private Key Path` placeholder `~/.ssh/id_ed25519`, `SSH Password` placeholder `••••••••••••`); Health section `Health Check` (`Target URL` placeholder `https://api.example.com/health`, `Polling Interval` help `Frequency of health check requests.`); Tunnel section `Public Tunnel` (`Tunnel Engine` options `Cloudflare Tunnel` / `Ngrok Tunnel`, `Target URL or Port` placeholder `http://localhost:3000`, `Ngrok Auth Token` placeholder `Uses ngrok config if empty`); Process section `Process Monitor` (`Process Name` placeholder `redis-server`, `Polling Interval`).

Provider list (inspector): inline form heading `New Provider` / `Edit Provider`, field `Provider Type` (help `Select runtime engine.`, options are the categories by `sidebarLabel`), `Custom Label (Optional)` placeholder `Staging`; add form opens with type `docker` and an empty label; edit form pre-fills the current label and type; empty state `No providers configured.` with `Add Provider` (help `Add new provider`, disabled help `Stop service to add providers`); row shows `displayName`, `resolvedTarget` and an `Active` chip; context menu `Edit` / `Delete` (Delete only when more than one provider); dialog `Delete Provider?` with message `‘<displayName or "This provider">’ and its settings will be deleted.`; an open inline form closes when the service becomes locked.

Options section (`InspectorOptionsSection.swift`): `Auto Reconnect` (help `Up to 3 retries after disconnect.`, shown only when the active provider's category supports it, disabled when locked), `Disable Service` (help `Excluded from bulk actions.`, disabled while the service is operational), `Delete Service` (`Permanent removal.`, disabled while operational; dialog `Delete Service?`, message `‘<service name or "Service">’ and its configurations will be permanently deleted.`).

Auto-save: edits are debounced 800 ms then committed (`+AutoSave.swift:30`); leaving the inspector flushes a pending save; autosave is a [CLIENT] concern: the daemon receives discrete `provider.update` calls.

---

## 4. Data shapes

### 4.1 Provider category fields in requests

Wire keys are the `Provider` JSON keys of [01 §4.4](01-data-model.md). This spec adds only the following non-column params.

| Name | Type | Optional | Default | Applies to | Notes |
|------|------|----------|---------|------------|-------|
| `sshAuthType` | string `"key"` or `"password"` | yes | `key` on create; inferred on update (§3.5.4) | `service.create` provider, `provider.add`, `provider.update` | [ADD-60]; never stored, never returned |
| `ports` (create only) | array of `{id?, local, remote}` integers | yes | `[]` | `service.create` (kubernetes, ssh) | `id` optional (UUID; generated when absent); `protocolType` is always `TCP` |

### 4.2 Provider create payload (nested in `service.create`; field rules §3.6.2)

| Field | Type | Optional | Default | JSON key |
|-------|------|----------|---------|----------|
| category | `ProviderCategory` string | no | none | `type` |
| per-category fields | as in §3.3 | per category | per §3.3 | the `Provider` keys |
| ports | array | yes | `[]` | `ports` |
| ssh auth | string | yes | `key` | `sshAuthType` |

### 4.3 `service.preflight`

Params:

| Field | Type | Optional | Default | JSON key | Notes |
|-------|------|----------|---------|----------|-------|
| service | UUID | no | none | `serviceID` | |
| provider | UUID | yes | effective active provider | `providerID` | must belong to the service |
| probe | bool | yes | `true` | `probe` | `false` skips the kubernetes connection probe and target resolution (only the synchronous rules run; `probed` is false) |
| refresh | bool | yes | `false` | `refresh` | bypass the connection-probe cache |
| record | bool | yes | `false` | `recordToActivityLog` | §3.8.1 step 9 |

Result:

| Field | Type | Optional | JSON key | Notes |
|-------|------|----------|----------|-------|
| service | UUID (uppercase) | no | `serviceID` | |
| provider | UUID or null | no | `providerID` | null when the service has no provider |
| type | `ProviderCategory` string or null | no | `providerType` | |
| disabled | bool | no | `serviceDisabled` | true → `issues` is empty |
| ok | bool | no | `ok` | no blocking issue |
| probed | bool | no | `probed` | |
| issues | array of Issue | no | `issues` | order as §3.7.2 |
| kubernetes | object | yes | `kubernetes` | present for kubernetes providers: `{ "kubeConfigID": UUID or null, "kubeContext": string or null, "reachable": bool or null, "target": { "kind": string, "name": string } or null }`; `reachable` null when not probed; `target` null unless resolution succeeded |

Issue:

| Field | Type | Optional | JSON key | Notes |
|-------|------|----------|----------|-------|
| code | string | no | `code` | §3.7 |
| message | string | no | `message` | exact set A text |
| severity | string `"blocking"` or `"warning"` | no | `severity` | always `blocking` in 1.x |
| field | string | yes (null) | `field` | §3.8.2 [V2-ADD] |

### 4.4 `KUMA_PRV_CREATE_INVALID` details

`details.issues`: array of `{ "field": string, "message": string }` in the order of §3.6.3.

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-PRV-01 | PARITY | Eight provider categories with capability matrix (ports for kubernetes/ssh, auto reconnect for kubernetes/ssh/shell) | `ProviderCategory.swift`, `CreateServicePayloadBuilder.swift:78-92` | `service.create`, `provider.add`, `provider.update` |
| FEAT-PRV-02 | PARITY | `displayName`, `resolvedTarget` card strings per category incl. compose image extraction, `isAutoReconnectEnabled` | `Provider.swift:120-224` | `service.get`, `service.list`, `provider.list` |
| FEAT-PRV-03 | PARITY | Kubernetes provider semantics: kubeconfig (NULL = Default), required context/target/ports, defaults `pod`/`true`, namespace optional | `Provider+KubernetesDefaults.swift`, `ServiceInspectorDrafts.swift`, `ServiceConfigurationValidator.swift:124-155` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-04 | PARITY | Docker/Podman compose semantics: path or YAML, startup script path or inline, working directory, path wins at run time | `ComposeStackResolver.swift`, `ComposeSettingsView.swift`, `InitialScriptSettingsView.swift` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-05 | PARITY | Shell provider: command required, optional working directory, auto reconnect | `ShellRunner.swift`, validator `:204-218` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-06 | PARITY | SSH provider: host/user required, port default 22, user fallback to login name at run time, key default `~/.ssh/id_ed25519`, ports | `SSHTunnelRunner.swift`, `ServiceInspectorDrafts.swift:71-92` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-07 | PARITY | HTTP health-check provider: URL normalized at create, interval options 5/10/30/60 | `CreateServicePayloadBuilder.swift:97-99`, `HealthCheckSettingsView.swift` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-08 | PARITY | Tunnel provider: engine `cloudflare`/`ngrok`, default target `http://localhost:3000`, ngrok token rule | `TunnelRunner.swift`, `TunnelSettingsView.swift` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-09 | PARITY | Process-monitor provider: process name required, interval default 5 | `ProcessMonitorRunner.swift`, `ProcessMonitorSettingsView.swift` | `service.create`, `provider.update`, `service.preflight` |
| FEAT-PRV-10 | PARITY | Defaults master table: persisted versus display-only defaults, interval option set | §3.4 sources | `service.create`, `provider.add`, `provider.update` |
| FEAT-PRV-11 | PARITY | Create payload mapping per category (CR-TRIM, `kubeTargetType`/`usePattern` for all categories, secrets only for the matching auth/engine) | `CreateServicePayloadBuilder.swift:7-95` | `service.create` |
| FEAT-PRV-12 | PARITY / V2-ADD | Create form validity rules enforced server-side with a message list | `CreateServicePayloadBuilder.swift:101-145` | `service.create` |
| FEAT-PRV-13 | PARITY / V2-ADD | Port-row rules: blank rows ignored, complete rows 1–65535, partial rows invalid; server-side range validation | `ServiceConfigurationValidator.swift:77-121`, `+AutoSave.swift:57-68` | `service.create`, `provider.set_ports`, `service.preflight` |
| FEAT-PRV-14 | PARITY | Creation defaults: star on create, initial group, disabled flag, default kubeconfig id, name/description trimming | `CreateServiceSaving.swift`, `CreateServiceCreationDefaults.swift` | `service.create` |
| FEAT-PRV-15 | CLIENT | Create-sheet provider cards, per-category name placeholders, field labels and placeholders | `CreateServiceProviderStepView.swift`, `CreateServiceFillDetailsStepView.swift`, `Views/Forms/**` | - |
| FEAT-PRV-16 | PARITY | `provider.add`: label trim rule, bare provider, becomes active, kubernetes defaults persisted | `ServiceProvidersSectionView.swift:133-146`, `+Providers.swift:58-96` | `provider.add` |
| FEAT-PRV-17 | PARITY | `provider.update` writable fields per category with exact empty-string normalization; foreign-field rejection | `InspectorRemoteAndNetworkFormSections.swift`, `InspectorKubernetesFormSection.swift`, `+AutoSave.swift` | `provider.update` |
| FEAT-PRV-18 | PARITY | Provider type change does not migrate fields; card/validation follow the new type | `ServiceProvidersSectionView.swift:133-145` | `provider.update` |
| FEAT-PRV-19 | PARITY | Compose path vs YAML and script path vs inline mutual exclusivity (last set wins; conflict in one call rejected) | `ComposeSettingsView.swift:51-77`, `InitialScriptSettingsView.swift:43-68` | `provider.update`, `provider.add` |
| FEAT-PRV-20 | PARITY / V2-ADD | SSH key vs password normalization (`ProviderSSHAuth`), `sshAuthType` param, inference | `ProviderSSHAuth.swift` | `service.create`, `provider.add`, `provider.update` |
| FEAT-PRV-21 | PARITY | Kubernetes context sanitization against the kubeconfig's contexts | `KubeConfigViewModel.swift:135-147`, `+AutoSave.swift:52-55` | `provider.update` |
| FEAT-PRV-22 | PARITY / V2-ADD | Running lock for provider edits (server-enforced), disabled-service edits allowed | `ServiceInspectorView.swift:39`, `ProviderItemRowView.swift:73-87` | `provider.add`, `provider.update`, `provider.delete`, `provider.set_ports` |
| FEAT-PRV-23 | PARITY / V2-ADD | Last provider of a service cannot be deleted; active provider repointed | `ServiceProvidersListView.swift:38`, `+Providers.swift:111-131` | `provider.delete` |
| FEAT-PRV-24 | PARITY | Validator short-circuit for disabled services and `provider.missing` | `ServiceConfigurationValidator.swift:34-42` | `service.preflight` |
| FEAT-PRV-25 | PARITY | Validator port rules (`ports.invalid_row_N`, `ports.required`, `ports.duplicate_local`) | `:77-121` | `service.preflight` |
| FEAT-PRV-26 | PARITY | Validator kubernetes rules (`k8s.kubeconfig`, `k8s.context`, `k8s.target`, `k8s.unreachable`, `k8s.target_resolve`) | `:124-155`, `:62-66` | `service.preflight` |
| FEAT-PRV-27 | PARITY | Validator compose rules (`compose.missing`, `compose.invalid`, `compose.startup_script`, `compose.working_dir`) | `:159-200` | `service.preflight` |
| FEAT-PRV-28 | PARITY | Validator shell rules (`shell.command`, `shell.working_dir`) | `:204-218` | `service.preflight` |
| FEAT-PRV-29 | PARITY | Validator ssh rules (`ssh.host`, `ssh.user`, `ssh.password`, `ssh.key`, `ssh.key_missing`) | `:222-252` | `service.preflight` |
| FEAT-PRV-30 | PARITY | Validator health, tunnel, monitor rules | `:256-289` | `service.preflight` |
| FEAT-PRV-31 | V2-ADD | `service.preflight`: server-side context, two-phase kubernetes probe, result shape, `field`, `probe`/`refresh` params | `+Validation.swift:16-103` | `service.preflight`, `kubeconfig.test_connection` |
| FEAT-PRV-32 | PARITY | Validator versus runner message sets and the surface that shows each; start paths never run the validator | `ServiceExecutionEngine.swift:19-24`, runners | `service.preflight`, `service.start` |
| FEAT-PRV-33 | PARITY / V2-ADD | Blocking issues recorded to the activity log (`[CONFIG] <message>`, `[KUMA] Start blocked: fix configuration issues above.`) | `+Validation.swift:52-61`, `LiveLogSession.swift:164-174` | `service.preflight` |
| FEAT-PRV-34 | CLIENT | Inspector banner aggregation `Can't start yet` and `(+N more)` | `InspectorRunningBanner.swift:30-36,94` | - |
| FEAT-PRV-35 | PARITY | `URLNormalizer.normalize` algorithm with every branch and the verified validity predicate | `URLNormalizer.swift` | `service.create`, `service.preflight`, `service.start` |
| FEAT-PRV-36 | PARITY | Health URL normalization at create; raw storage at update; re-normalization at validation and start | `CreateServicePayloadBuilder.swift:97-99`, `HealthCheckRunner.swift:15-16` | `service.create`, `provider.update` |
| FEAT-PRV-37 | CLIENT | Provider list inline form, delete dialog, options section texts, port editor texts | §3.11 | - |

---

## 6. Error catalog

Provider/service not-found, conflict and generic errors are owned by [04](04-workspaces-groups-services.md) (`KUMA_SVC_NOT_FOUND`) and [10](10-rpc-protocol.md) (`KUMA_CONFLICT_STALE`); enum/UUID errors by [01](01-data-model.md).

| Code | Condition | Message |
|------|-----------|---------|
| `KUMA_PRV_CREATE_INVALID` | `service.create` fails the form-validity rules (§3.6.3) | the first failing issue message (for example `Enter a shell command to run.`); `details.issues` lists all |
| `KUMA_PRV_PORT_INVALID` | `provider.set_ports` row not complete (a field missing, not an integer, or outside 1–65535) | `Port row <N>: enter local and remote ports (1–65535).` |
| `KUMA_PRV_PORTS_NOT_APPLICABLE` | non-empty port list for a provider whose type is not `kubernetes`/`ssh` (create or `provider.set_ports`) | `Port mappings apply only to Kubernetes and SSH providers.` |
| `KUMA_PRV_LOCKED` | `provider.add`/`update`/`delete`/`set_ports` while the service is `running`, `starting` or `reconnecting` | `Settings are read-only while active.` |
| `KUMA_PRV_LAST_PROVIDER` | `provider.delete` of the only provider of a service | `A service must keep at least one provider.` |
| `KUMA_PRV_FIELD_NOT_APPLICABLE` | `provider.add`/`update` sets a field that does not apply to the resulting category and differs from the stored value | `Field '<field>' does not apply to provider type '<type>'.` |
| `KUMA_PRV_SOURCE_CONFLICT` | one call sets both `composeFilePath` and `yamlConfig` (or both `initialScriptPath` and `initialScript`) to non-blank values | `Set either a compose file path or compose YAML, not both.` / `Set either a startup script path or an inline script, not both.` |
| `KUMA_PRV_SSH_AUTH_CONFLICT` | one call sets both `sshPassword` and `sshKeyPath` non-blank without `sshAuthType` | `Provide either an SSH password or a private key path, not both.` |
| `KUMA_PRV_KUBECONFIG_NOT_FOUND` | `kubeConfigID` that is neither the Default id nor a row of `kube_config` (on `provider.add`/`update`; on create it is reported as `KUMA_PRV_CREATE_INVALID` with `Select a kubeconfig.`) | `Kubeconfig '<id>' was not found.` |
| `KUMA_PRV_PROVIDER_NOT_FOUND` | `service.preflight` `providerID` not among the service's providers (spec 04's `provider.*` methods SHOULD reuse this code for an unknown provider id) | `Provider '<id>' was not found for this service.` |

`service.preflight` never returns a validation failure as an error: configuration problems are normal results (`ok: false`, `issues`).

---

## 7. Deviations

| ID | Summary (full text in [15](15-traceability-and-parity.md)) |
|----|-----------------------------------------------------------|
| DEV-60 | The validator/preflight resolves compose YAML without writing the ephemeral `docker-compose.kuma.yml` (1.x `ComposeStackResolver.resolve` wrote it as a side effect of validation). |
| DEV-61 | A dangling kubeconfig id is reported as `k8s.kubeconfig` at preflight and rejected at create/update (the 1.x inspector silently re-selected another config in its picker). |
| DEV-62 | Port rows are validated server-side (complete, 1–65535, only for kubernetes/ssh) on `service.create` and `provider.set_ports`; 1.x validated only in the UI and persisted/dropped rows silently. |
| DEV-63 | UI-only guards become server-enforced: the running lock for provider add/update/delete/set_ports and the "last provider cannot be deleted" rule. |
| DEV-64 | `provider.update`/`provider.add` reject fields that do not apply to the resulting category (unless equal to stored) and reject setting both sources of the compose/script/ssh-credential pairs in one call (the UI set fields one at a time). |
| DEV-65 | Kubernetes context sanitization runs only when the patch touches `kubeConfigID` or `kubeContext`, and only when the kubeconfig yields at least one context (1.x re-sanitized on every commit and cleared the context when none were found). |
| ADD-60 | `sshAuthType` param (`key`/`password`) and patch-driven inference on `service.create`, `provider.add`, `provider.update` (1.x kept it as inspector state). |
| (existing) ADD-01 | `service.preflight` (this spec defines params, result, `field`, `probe`, `refresh`, `recordToActivityLog`). |
| (existing) DEV-22 | `updatedAt` is `max(now, previous + 1 ms)` on every provider/service write ([01](01-data-model.md)). |

---

## 8. Invariants

| ID | Statement |
|----|-----------|
| INV-D-PRV-01 | `ServiceConfigurationValidator.issues` is deterministic for a fixed `(service, provider, context, filesystem)` and has no side effect (no file or database write). |
| INV-D-PRV-02 | A disabled service yields an empty issue list from the validator and `ok: true, serviceDisabled: true` from `service.preflight`. |
| INV-D-PRV-03 | `service.start`, `service.start_all` and auto-resume never run the validator; their failure texts are the set B runner messages. |
| INV-D-PRV-04 | Within one preflight result issue codes are unique, and the order is: provider, ports, category rules, `k8s.target_resolve`. |
| INV-D-PRV-05 | Every validator rule emits severity `blocking`; the daemon never invents a `warning`. |
| INV-D-PRV-06 | The daemon never nulls or rewrites columns of other categories on `provider.update`, type change or `provider.add` (retained and ignored). |
| INV-D-PRV-07 | After any successful write that sets a non-blank compose path, `yamlConfig` is NULL; after any successful write that sets a non-blank `yamlConfig`, `composeFilePath` is NULL; same for the startup script pair. |
| INV-D-PRV-08 | After any successful write of an ssh provider, at most one of `sshPassword` and `sshKeyPath` is non-NULL. |
| INV-D-PRV-09 | After `provider.add`/`provider.update` of a kubernetes provider, `kubeTargetType` is non-NULL, non-empty and `usePattern` is non-NULL. |
| INV-D-PRV-10 | `autoReconnect` is written as a non-NULL boolean; `isAutoReconnectEnabled` is false for categories other than kubernetes, ssh, shell regardless of the column. |
| INV-D-PRV-11 | A stored label is never blank: `provider.add`/`update` trim it and map empty to NULL. |
| INV-D-PRV-12 | Port mappings written through the API satisfy `1 <= localPort, remotePort <= 65535` and belong to a kubernetes or ssh provider. |
| INV-D-PRV-13 | While a service is `running`, `starting` or `reconnecting`, no `provider.*` write succeeds. |
| INV-D-PRV-14 | A service always keeps at least one provider through `provider.delete`. |
| INV-D-PRV-15 | `service.preflight` performs no database write, starts no process, changes no `updatedAt`, and never includes secrets in its result or issue messages. |
| INV-D-PRV-16 | `URLNormalizer.normalize` never panics, runs in time linear in the input, and is idempotent (`normalize(normalize(x)) == normalize(x)` when the first result is non-none). |
| INV-D-PRV-17 | `URLNormalizer.normalize` returns either none or a string whose `isValidURL` is true; it returns the user's text verbatim after the (re)built scheme prefix. |
| INV-D-PRV-18 | Stored interval values (`httpCheckInterval`, `monitorInterval`) are never coerced to the 5/10/30/60 set; runner floors apply at run time only. |
| INV-D-PRV-19 | `resolvedTarget` and `displayName` are pure functions of the stored provider columns and never include secrets. |
| INV-D-PRV-20 | The path base for relative validator/runner paths is `/` (the daemon's working directory). |

---

## 9. Acceptance tests

| ID | Arrange → Assert |
|----|------------------|
| DT-PRV-01 | For each of the eight types: `supportsAutoReconnect` true only for kubernetes, ssh, shell; a docker provider with `autoReconnect = true` has `isAutoReconnectEnabled == false` |
| DT-PRV-02 | `label="  Staging "` → `displayName == "  Staging "`; `label="   "` → `displayName` = `sidebarLabel`; `label` NULL → `sidebarLabel` (`Health Check` for `httpCheck`) |
| DT-PRV-03 | `resolvedTarget` table: docker with path `/srv/app/docker-compose.yml` → `Docker: docker-compose.yml`; docker with yaml `image: "docker.io/library/redis:7"` → `Docker: redis:7`; `image: docker.io/bitnami/redis` → `Docker: bitnami/redis`; `image: library/nginx` → `Docker: nginx`; docker with `- image: x` only and label `Cache` → `Docker: Cache`; docker empty → `Docker`; podman empty → `Podman`; kubernetes `targetName="  api-0 "` → `k8s: api-0`, empty → `Kubernetes`; shell `"  npm run dev  "` → `npm run dev`; ssh all NULL → `SSH: root@localhost:22`; ssh user `""` host `h` port 2200 → `SSH: @h:2200`; httpCheck `https://a.io/h` → `HTTP: https://a.io/h`; tunnel NULL/NULL → `Cloudflare Tunnel -> 8080`; tunnel type `NGROK`, target `""` → `Ngrok Tunnel -> `; processMonitor `redis-server` → `Monitor: redis-server` |
| DT-PRV-04 | `extractComposeImage`: `image:` lines with quotes, prefixes `docker.io/library/` / `docker.io/` / `library/`; an empty `image:` line followed by `image: x` → `x`; CRLF and U+2028 line separators split; a `- image: x` line does not match |
| DT-PRV-05 | `provider.add` and `provider.update` of a kubernetes provider persist `kubeTargetType="pod"` and `usePattern=true` when NULL; a stored unknown `kubeTargetType="statefulset"` is **not** rewritten but behaves as `pod` |
| DT-PRV-06 | `service.create` kubernetes (TC-B08): valid with context `staging`, target `redis`, one row 6379→6379; each of: blank context, blank target, no complete row, row `70000`→`80` → `KUMA_PRV_CREATE_INVALID` with the messages of §3.6.3 in order |
| DT-PRV-07 | `service.create` docker: empty both → `Choose a compose file or paste compose YAML.`; whitespace-only YAML → same; path only OK; YAML only OK; `yamlConfig` stored un-trimmed, `composeFilePath` stored trimmed |
| DT-PRV-08 | `service.create` ssh: host and user required; zero port rows accepted; `sshPort` absent → 22; auth default `key` stores `~/.ssh/id_ed25519` and NULL password; `password` auth with `"  pw "` stores `pw` and NULL key path; key path supplied with `password` auth is ignored |
| DT-PRV-09 | `service.create` httpCheck: `localhost:3000/` stores `http://localhost:3000/`; `a b.com` stores `a b.com`; `httpCheckInterval` default 5; interval `7` stored as 7 |
| DT-PRV-10 | `service.create` tunnel: absent engine stores `cloudflare`, absent target `http://localhost:3000`; engine `ngrok` with token `" tok "` stores `tok`; engine `cloudflare` with a token stores NULL token; target stored trimmed and **not** normalized (`3000` stays `3000`) |
| DT-PRV-11 | `service.create` processMonitor: interval default 5; name trimmed |
| DT-PRV-12 | For every category the created provider has `kubeTargetType = "pod"` and `usePattern = true` (parity quirk), `autoReconnect = false`, `label` NULL |
| DT-PRV-13 | `service.create` kubernetes without `kubeConfigID` stores `00000000-0000-0000-0000-000000000001`; with an unknown id → `KUMA_PRV_CREATE_INVALID` `Select a kubeconfig.` |
| DT-PRV-14 | Ports: rows blank/blank ignored; `local=0`, `remote=80`, `local=80,remote=65536` rejected with `Port row <N>: enter local and remote ports (1–65535).`; duplicate local ports accepted by create and by `provider.set_ports`, reported by preflight as `ports.duplicate_local` |
| DT-PRV-15 | Ports on a docker/shell/httpCheck/tunnel/processMonitor provider (create or `provider.set_ports`) → `KUMA_PRV_PORTS_NOT_APPLICABLE`; an empty list is accepted |
| DT-PRV-16 | `service.create` with `starOnCreate`/`initialGroupID` semantics ([04](04-workspaces-groups-services.md) params) → `isStarred == true`, `groupIDs == [initialGroupID]`, `activeProviderID` NULL, name trimmed, description whitespace → NULL |
| DT-PRV-17 | `provider.add` with label `"  Staging  "` → stored `Staging`; label `"   "` → NULL; the new provider is active, `service.updatedAt` increased, no port mappings, type kubernetes has defaults; two providers of the same type and label allowed |
| DT-PRV-18 | `provider.update`: echoing the full stored provider unchanged succeeds; setting `sshHost` on a shell provider → `KUMA_PRV_FIELD_NOT_APPLICABLE`; including `type: "ssh"` in the same patch makes it valid; unrelated stored foreign columns remain after the update |
| DT-PRV-19 | Compose exclusivity: set `composeFilePath="/a.yml"` on a provider with YAML → YAML NULL; set `yamlConfig="x: 1"` on a provider with a path → path NULL; set `composeFilePath=""` → YAML kept; both non-blank in one call → `KUMA_PRV_SOURCE_CONFLICT`; same four checks for the startup script pair |
| DT-PRV-20 | SSH normalization: `sshAuthType=password` clears key path; switching to `key` clears the password and fills `~/.ssh/id_ed25519` when blank; patch `{sshKeyPath:"/k"}` on a provider with a stored password infers `key` and clears the password; patch with both non-blank and no type → `KUMA_PRV_SSH_AUTH_CONFLICT`; empty `sshPassword` clears it (`sshPasswordSet` false) |
| DT-PRV-21 | Context sanitization with a kubeconfig whose contexts are `staging`, `prod` and `current-context: staging` (TC-B05a/b): stored `docker-desktop` → `staging`; stored `prod` → `prod`; kubeconfig with no contexts → stored value kept; patch touching only `targetName` does not re-sanitize |
| DT-PRV-22 | Lock: service `running`, `starting`, `reconnecting` → `provider.add/update/delete/set_ports` → `KUMA_PRV_LOCKED`; `stopping` and `idle` succeed; disabled idle service succeeds |
| DT-PRV-23 | `provider.delete` of the only provider → `KUMA_PRV_LAST_PROVIDER`; deleting the active one of two repoints `activeProviderID` to the remaining provider |
| DT-PRV-24 | Disabled service with an empty shell provider → `issues == []`, `ok == true`, `serviceDisabled == true`; enabled service without providers → exactly `provider.missing` with `Add a provider before starting this service.` |
| DT-PRV-25 | Ports validator: rows `["", ""]` only → `ports.required`; rows `[("80","x")]` → `ports.invalid_row_0` then `ports.required`; rows `[("","")("90","90")("90","91")]` → `ports.duplicate_local` and no invalid row; `("+80","80")` complete; rows `[("0","80")]` → `ports.invalid_row_0`; invalid index counts blank rows (`[("",""),("x","1")]` → `ports.invalid_row_1` with `Port row 2: enter local and remote ports (1–65535).`) |
| DT-PRV-26 | Kubernetes validator (`ServiceConfigurationValidatorTests`): empty provider and one blank row → codes include `k8s.kubeconfig`, `k8s.context`, `k8s.target`, `ports.required`; `kubeConnectionError="The cluster is not reachable."` → `k8s.unreachable` with that message and blocking; with `kubeIsConnecting=true` no `k8s.unreachable`; error text with surrounding whitespace is trimmed; `kubeAsyncMessage` → `k8s.target_resolve` last |
| DT-PRV-27 | Compose validator: nothing set → only `compose.missing`; path to a missing file → `compose.invalid` with `Invalid configuration: Compose file not found: <rawPath>` plus (if set) `compose.startup_script` and `compose.working_dir`; path to a directory → `compose.invalid`; YAML only → no `compose.invalid` and **no file is created** under the temp directory (DEV-60); tilde path expands to the home directory |
| DT-PRV-28 | Shell validator (`testShellCommand`): empty → `shell.command`; working directory that is a file → `shell.working_dir` `Working directory does not exist: <rawDir>` |
| DT-PRV-29 | SSH validator: empty host/user → `ssh.host`, `ssh.user`; with a stored password the inferred type is password → `ssh.password` not emitted and key rules skipped; no password and blank key → `ssh.key`; key path to a missing file → `ssh.key_missing` with the raw path; key path that is a directory → no `ssh.key_missing` |
| DT-PRV-30 | Health validator: blank → `health.url`; `a b.com` → `health.url_invalid`; `localhost:3000` → none; tunnel validator: blank target → `tunnel.target`; engine `NGROK` with blank token → `tunnel.ngrok_token`; engine `wireguard` with blank token → none; monitor blank → `monitor.process` |
| DT-PRV-31 | `service.preflight` shape: kubernetes provider with a fake `kubectl` that counts invocations: sync-blocking config → result contains only sync issues, `probed` false for resolution, `kubectl` invoked 0 times for target discovery; valid config + reachable + target found → `ok == true`, `kubernetes.reachable == true`, `kubernetes.target == {kind:"pod", name:"<resolved>"}`; discovery failure → `k8s.target_resolve` with the §3.8.3 text (`Execution failed: <reason>`); missing `kubectl` → `k8s.target_resolve` `Required binary 'kubectl' could not be located on this Mac.`; each issue carries `field` per §3.8.2 |
| DT-PRV-32 | `probe: false` on a kubernetes provider → no kubectl process, `probed == false`, `k8s.unreachable` absent; `refresh: true` re-runs the probe despite a cached result |
| DT-PRV-33 | Preflight is read-only: DB file hash and every `updatedAt` unchanged, no `kuma-compose-*` directory created, no process spawned (other than the kubectl probe), repeated calls identical |
| DT-PRV-34 | `service.start` on a shell service with a blank command fails with `Invalid configuration: No shell command specified.` (set B), not the validator text; `service.preflight` on the same service returns `Enter a shell command to run.` (set A) |
| DT-PRV-35 | `recordToActivityLog: true` with two blocking issues appends two `[CONFIG] <message>` lines (no duplicates on a second call) and then `[KUMA] Start blocked: fix configuration issues above.` each call |
| DT-PRV-36 | `URLNormalizerTests` TC-U01..U08 (§3.10.3) pass exactly |
| DT-PRV-37 | Corpus test: every row of §3.10.4 and the additional validity rows produce the stated output for both `defaultToHttps` values |
| DT-PRV-38 | Differential property test against the predicate of §3.10.2: random ASCII strings over the alphabet `h a . : / @ [ ] % 4 1 # ? space \ 0 9 - _ x f ^ ` { | } " < > ~ ! $ & ' ( ) * + , ; =` prefixed `https://` classify identically to a reference implementation derived from the rules (the 1.x reference produced 0 mismatches over 320,000 samples) |
| DT-PRV-39 | Idempotence: for every non-none output `o` of the corpus, `normalize(o) == o` for both flags |
| DT-PRV-40 | Trim semantics: inputs with U+00A0, U+2003, U+3000, U+0085 around names/URLs/paths are treated as blank-trimmed; U+200B is not trimmed |
| DT-PRV-41 | Relative-path base: a relative `composeFilePath` is resolved against `/`; `~/x` against the daemon user's home; `~root/x` against root's home |
| DT-PRV-42 | Type change: `provider.update {type:"shell"}` on a kubernetes provider keeps all kubernetes columns and port mappings, `resolvedTarget == "Shell script"`, preflight reports `shell.command` and no `ports.*` or `k8s.*` issues |
| DT-PRV-43 | Normalization table of §3.5.2: `runCommand=""` stays `""` (card `Shell script`), `sshHost=""` becomes NULL (card `localhost`), `tunnelTargetUrl=""` stays `""` (card `Cloudflare Tunnel -> `), `ngrokAuthToken=""` clears, `httpCheckUrl="localhost:3000"` stays raw (not normalized), `label="  "` becomes NULL |
| DT-PRV-44 | Auto reconnect: `provider.update {autoReconnect:true}` on kubernetes/ssh/shell stores a boolean; on docker → `KUMA_PRV_FIELD_NOT_APPLICABLE`; the stored column of an old docker provider that holds true is retained |
| DT-PRV-45 | Secrets: preflight results for an ssh provider with `sshAuthType=password` and a password never contain the password; `provider.update` responses carry `sshPasswordSet` and never `sshPassword`; `ssh.password` message is exactly `SSH password is required.` |
| DT-PRV-46 | Interval storage: `httpCheckInterval=7` and `monitorInterval=0` are stored unchanged; a NULL health interval displays 5 in the client contract but the runner uses 10 (documented in §3.3.5) |
| DT-PRV-47 | Dangling kubeconfig: provider with `kubeConfigID` set to an unknown UUID → preflight `k8s.kubeconfig` and no probe; `provider.update` with that id → `KUMA_PRV_KUBECONFIG_NOT_FOUND` |
| DT-PRV-48 | Source-conflict edge: patch with `composeFilePath="a.yml"` and `yamlConfig=""` succeeds (blank is not a conflict) and leaves YAML NULL |

---

## Proposed RPC additions

None. No method outside the registry in [00 §5](00-overview-and-conventions.md) is needed. Spec 10 MUST add the following **parameters** to existing methods: `sshAuthType` and `ports[]` on the `service.create` provider object, `sshAuthType` on `provider.add` and `provider.update`, and the `service.preflight` params/result of §4.3.

## Open questions / residual risks

- **R-01 Default kubeconfig on create.** The create sheet stores an explicit concrete `kubeConfigID`; I chose to store the explicit Default id when the API omits it (parity with a sheet that preselects the first/Default config) rather than NULL. Both mean the same at run time; only the stored value differs.
- **R-02 Ngrok token.** The validator (`tunnel.ngrok_token`) blocks the inspector start without a token while the form placeholder says `Uses ngrok config if empty` and the runner treats the token as optional. I kept both (parity); a client using `service.start` directly can run ngrok with its local config.
- **R-03 `sshPort` has no range check** anywhere in 1.x (`Int($0) ?? 22`, `?? 22`); I kept parity. A value such as `0` or `99999` is stored and fails when `ssh` runs.
- **R-04 Health interval display versus run time.** A NULL `httpCheckInterval` displays `5s` but the runner polls every 10 s (`max(x ?? 10, 3)`); a NULL `monitorInterval` is 5 in both. Kept (parity); creates always write an explicit value.
- **R-05 Non-ASCII host validity** (§3.10.2 item 7) is specified through UTS #46 behavior observed on macOS; rare inputs (unassigned code points, unusual joiners, malformed `%` next to non-ASCII characters such as `é%0éa4`) may still differ between Foundation and the Rust IDNA crate. The ASCII predicate was verified exactly (0 mismatches in 320,000 fuzz samples); the listed non-ASCII cases are pinned by DT-PRV-37.
- **R-06 Validator context in 1.x is GUI state.** `kubeIsConnecting`, `kubeConnectionError` and the draft rows are inspector state; preflight derives them from persisted data and an awaited probe, so a draft the user typed but not yet saved is invisible to the daemon (clients save first, as autosave does after 800 ms).
- **R-07 `ports.invalid_row_<i>` over persisted rows.** 1.x inspector persisted rows up to any positive integer and dropped partial rows, so persisted rows above 65535 (legacy data) are reported as invalid rows by preflight with 0-based indices over persisted rows (not over any client draft).
- **R-08 Locked states.** I lock `running`, `starting`, `reconnecting` (= `isOperational`) but not `stopping`, matching `isLocked` (the 1.x lock also includes disabled services, which I leave editable through the API, DEV-63).
- **R-09 Create-time messages.** The `KUMA_PRV_CREATE_INVALID` texts reuse validator wording; only `Service name is required.` and the `KUMA_PRV_*` texts of §6 for new conditions are daemon-defined because 1.x had no message for them.
