# Daemon Spec 07: Kubernetes, Kubeconfig and Target Resolution

> **Area code:** `K8S` · **Status:** Draft for implementation · **Baseline:** Kuma 1.x (Swift)
> **Depends on:** [00 Overview and Conventions](00-overview-and-conventions.md), [01 Data Model](01-data-model.md), [02 Security and Secrets](02-security-and-secrets.md), [03 Settings and Environment](03-settings-and-environment.md), [05 Providers and Validation](05-providers-and-validation.md), [06 Execution Engine](06-execution-engine.md) · **Consumed by:** [08 Logs and Events](08-logs-and-events.md), [10 RPC Protocol](10-rpc-protocol.md), [11 CLI](11-cli.md), [12 MCP](12-mcp.md), [13 REST API](13-rest-api.md)

---

## 1. Purpose and scope

This spec owns everything required to connect Kuma to a Kubernetes cluster and run **`kubectl port-forward`** for kubernetes providers, plus kubeconfig registry CRUD, YAML context parsing, connectivity probes, target name/pattern resolution, and port-forward adoption. It is the authoritative reference for **exact `kubectl` argv**, subprocess timeouts, error text, and in-memory runtime state (`resolvedTarget`).

**In scope**

- Virtual **Default** kubeconfig and custom rows in `kube_config` ([01 §3.14.2](01-data-model.md), [01 §4.7](01-data-model.md)).
- `KubeConfigMaterializer`, `KubeConfigExecutionResolver`, `KubeConfigYAMLParser`, `KubeConnectionValidator`.
- `KubeTargetResolver`, `KubeTargetNameMatcher`, `KubeTargetNamingHints`, `KubePortForwardPlan`, `KubePortForwardAdoption`, `KubeLiveTargetDisplay`.
- RPC: `kubeconfig.*`, `k8s.resolve_target`, `k8s.namespaces`, `k8s.resources` ([00 §5.4](00-overview-and-conventions.md)).
- How kubernetes providers interact with [06 §3.9.2](06-execution-engine.md) (runner pipeline; this spec defines the algorithms 06 references).
- Workload log argv for `kubectl logs` ([08](08-logs-and-events.md); source `LiveLogSourceRunner.swift`).
- Default kubeconfig path resolution is defined in [03 §3.10.7](03-settings-and-environment.md); this spec consumes `resolved_kubeconfig_path()`.

**Out of scope**

- Provider field validation messages and `service.preflight` orchestration ([05](05-providers-and-validation.md)).
- Process registry, launch, stop, reconnect ([06](06-execution-engine.md)).
- Vault encrypt/decrypt wire rules ([02](02-security-and-secrets.md)).
- Inspector/deck UI layout ([CLIENT] rows below).

**Tags:** `[PARITY]` = 1.x behavior; `[V2-ADD]` = headless-only; `[CLIENT]` = client-only.

### 1.1 Terminology (same as [05 §1.1](05-providers-and-validation.md))

`trim-WN`, `blank`, `tilde-expand`, `Default kubeconfig id` = `00000000-0000-0000-0000-000000000001`.

---

## 2. 1.x source of truth (paths read)

| Path | Role |
|------|------|
| `Kuma/Core/Kubernetes/KubeConfigYAMLParser.swift` | Line-based `current-context` / `contexts` / `resolveContextName` |
| `Kuma/Core/Kubernetes/KubeConnectionValidator.swift` | `kubectl version` probe + in-memory cache |
| `Kuma/Core/Kubernetes/KubeTargetResolver.swift` | Target discovery and `kind/name` |
| `Kuma/Core/Kubernetes/KubeTargetNameMatcher.swift` | Pattern / replica pod matching |
| `Kuma/Core/Kubernetes/KubeTargetNamingHints.swift` | Deployment-style pod stem heuristic |
| `Kuma/Core/Kubernetes/KubePortForwardPlan.swift` | Port-forward argv |
| `Kuma/Core/Kubernetes/KubePortForwardAdoption.swift` | Adopt external `kubectl port-forward` |
| `Kuma/Core/Kubernetes/KubeConfigMaterializer.swift` | Filesystem path for `--kubeconfig` |
| `Kuma/Core/Kubernetes/KubeConfigExecutionResolver.swift` | Path + context for a provider |
| `Kuma/Core/Kubernetes/KubeLiveTargetDisplay.swift` | Ephemeral resolved pod/service name |
| `Kuma/Core/Execution/Runners/KubernetesRunner.swift` | Start/stop orchestration |
| `Kuma/Domain/Models/KubeConfig.swift` | Domain model, `defaultID`, `resolvedPlainYAML()` |
| `Kuma/Core/Database/Records/KubeConfig+Record.swift` | SQLite mapping |
| `Kuma/Core/Database/Repositories/KubeConfigRepository.swift` | CRUD |
| `Kuma/Domain/Enums/KubeTargetType.swift` | `pod` / `service` / `deployment` |
| `Kuma/Presentation/Features/Services/ViewModels/KubeConfigViewModel.swift` | List/decrypt/save/delete/test UI logic |
| `Kuma/Presentation/Features/Services/ViewModels/ServiceInspectorViewModel+Validation.swift` | Async target probe for inspector |
| `Kuma/Presentation/Features/LiveLogs/LiveLogSourceRunner.swift` | `kubectl logs -f` argv |
| `Kuma/Core/Environment/DependencyChecker.swift` | `resolvedKubeconfigPath`, `standardKubeconfigFilePath` |
| `Kuma/Core/Execution/SubprocessWait.swift` | `KumaExecutionTimeouts.kubectlSubcommand` = 30 s |
| `Kuma/Presentation/Features/Services/Views/Forms/Kubernetes/**` | [CLIENT] forms |
| `docs/specs/06-services.md` | Kubernetes target type × pattern table |
| `KumaTests/Features/Services/KubeTargetResolverTests.swift` | K1–K6 resolution matrix |

**Cross-reference only (not duplicated):** [06 §3.9.2](06-execution-engine.md) states the runner start order; algorithms live in §3 below.

---

## 3. Normative behavior

### 3.1 Constants

| Name | Value | Source |
|------|-------|--------|
| `KubeConfig.defaultID` | `00000000-0000-0000-0000-000000000001` | `KubeConfig.swift:7` |
| Virtual Default name | `Default` | `KubeConfigViewModel.swift:99` |
| Materialized dir | `<data dir>/kubeconfigs/` | `KubeConfigMaterializer.swift:64-65` |
| Materialized file | `<dir>/<configID.uuidString>.yaml` (UPPERCASE UUID) | `KubeConfigMaterializer.swift:75` |
| Materialized dir mode | `0700` on create | `KubeConfigMaterializer.swift:69-72` |
| Materialized file mode | `0600` after write | `KubeConfigMaterializer.swift:51-54` |
| Validation temp file | `<temp>/kuma-chk-<UUID>.yaml` | `KubeConnectionValidator.swift:66` |
| `kubectl` probe timeout flag | `--request-timeout=4s` | `KubeConnectionValidator.swift:77` |
| Ephemeral `kubectl get` timeout | 30 s (`kubectlSubcommand`) | `SubprocessWait.swift:13`, `KubeTargetResolver.swift:94` |
| Logs tail | `--tail=200` | `LiveLogSourceRunner.swift:65` |
| `ps` argv for adoption | `["-p", "<pid>", "-ww", "-o", "command="]` | `KubePortForwardAdoption.swift:79` |

### 3.2 `KubeConfigYAMLParser` (line-based; not a full YAML parser)

Input: entire kubeconfig file as a string. Line splitting: `.newlines` (CR, LF, CRLF).

#### 3.2.1 `parseCurrentContext(fromYaml:) -> string?`

Scan lines in order. For each line, `trimmed = trim-WN(line)`.

- If `trimmed` does **not** start with `current-context:` → continue.
- Else split `trimmed` on `:` (Swift `components(separatedBy: ":")`).
- If fewer than 2 parts → skip line.
- Context value = `parts[1]` trim-WN, then remove all `"` and `'`.
- Return value if non-empty; else `null`.
- If no matching line → `null`.

(`KubeConfigYAMLParser.swift:5-20`)

#### 3.2.2 `parseContexts(fromYaml:) -> string[]`

State: `inContextsBlock = false`, `contexts = []`.

For each line:

1. `trimmed = trim-WN(line)`.
2. If `trimmed.starts(with: "contexts:")` → `inContextsBlock = true`; continue.
3. If `inContextsBlock`:
   - **End block:** if the line does **not** start with space or tab **and** `trimmed` contains `:` **and** `trimmed` does **not** start with `-` → break out of the loop (stop parsing contexts).
   - **Name line:** if `trimmed.starts(with: "- name:")` **or** (`trimmed.starts(with: "name:")` **and** line starts with space or tab):
     - Split on literal `name:`; if ≥2 parts, take `parts[1]` trim-WN, strip `"` and `'`.
     - If name non-empty and not already in `contexts`, append (preserve first-seen order).

Return `contexts`. (`KubeConfigYAMLParser.swift:23-51`)

#### 3.2.3 `resolveContextName(stored, in yaml) -> string?`

1. `contexts = parseContexts(fromYaml: yaml)`.
2. `storedTrimmed = trim-WN(stored ?? "")`.
3. If `storedTrimmed` non-empty **and** `contexts.contains(storedTrimmed)` → return `storedTrimmed`.
4. If `current = parseCurrentContext(fromYaml: yaml)`, `current` in `contexts` → return `current`.
5. Return `contexts.first` (may be `null`).

(`KubeConfigYAMLParser.swift:55-65`)

This is used for: provider `--context`, connection tests, and [05 §3.5.6](05-providers-and-validation.md) sanitization.

### 3.3 Plain YAML for a kubeconfig record

`resolvedPlainYAML(config)` (`KubeConfig.swift:37-43`):

1. If `sourceFilePath` trim-WN non-empty: read `tilde-expand(path)` as UTF-8; on failure return `""`.
2. Else return in-memory `configContent` (already decrypted plaintext for daemon-internal use).

For the **virtual Default**, content is loaded like `KubeConfigViewModel.fetchAndDecryptConfigs` (`:91-94`): read file at resolved path if it exists, else `""`. Displayed `sourceFilePath` = `resolvedKubeconfigPath(customPath) ?? standardKubeconfigFilePath()` (`:83-89`) even when the file is missing.

### 3.4 Kubeconfig registry list (`kubeconfig.list`)

1. Load all rows from `kube_config` ordered by `createdAt ASC` ([01 §3.11.3](01-data-model.md)).
2. **Drop** any row whose `id` equals `KubeConfig.defaultID` (`KubeConfigViewModel.swift:110`).
3. Prepend the **virtual Default** entry (never persisted):

| Field | Value |
|-------|--------|
| `id` | `00000000-0000-0000-0000-000000000001` |
| `name` | `Default` |
| `isDefault` | `true` |
| `sourceFilePath` | `resolved_kubeconfig_path() ?? standardKubeconfigFilePath()` |
| `hasContent` | `false` (wire; see [02](02-security-and-secrets.md)) |
| `createdAt` / `updatedAt` | time of the request (no row) |

4. For each DB row: map to wire shape per [01 §4.7](01-data-model.md); `isDefault = false`.

Decrypt inline `configContent` only when building internal state for `contexts` / probes; default responses use `hasContent` + `sourceFilePath` ([02 §3.11](02-security-and-secrets.md)).

### 3.5 Kubeconfig CRUD

#### 3.5.1 `kubeconfig.get`

Return one entry: virtual Default by id, or DB row. Apply redaction unless `revealSecrets: true` on allowed transport ([02](02-security-and-secrets.md)).

#### 3.5.2 `kubeconfig.create` / `kubeconfig.update`

**Id rules**

- `create`: new random UUID (not Default).
- `update`: `expectedUpdatedAt` per [01 §3.13](01-data-model.md); row must exist and not be Default.
- **Reject** `id == Default` on create/update with `KUMA_K8S_DEFAULT_IMMUTABLE`.

**Name**

- `name` trim-WN must be non-empty else `KUMA_K8S_NAME_REQUIRED`.

**Mutually exclusive content modes** (reject both non-empty inline YAML and non-empty `sourceFilePath` in one call with `KUMA_K8S_SOURCE_CONFLICT`):

| Mode | Stored `configContent` | Stored `sourceFilePath` |
|------|------------------------|-------------------------|
| File-backed | `encrypt("")` (empty plaintext) | trimmed **unexpanded** path as user entered (`KubeConfigViewModel.swift:239-240`) |
| Paste-backed | `encrypt(trimmedYAML)` | `null` (`:244-245`) |

File-backed: expanded path must exist as a file (`fileExists`); else `KUMA_K8S_FILE_NOT_FOUND`.

Paste-backed: trimmed YAML must be non-empty; else `KUMA_K8S_CONTENT_REQUIRED`.

**Update partial fields:** follow [02 §3.3](02-security-and-secrets.md) (omit = keep; non-empty `configContent` clears path; non-empty path stores `encrypt("")`).

On successful **update** or **delete** of a stored config: delete materialized file `<data dir>/kubeconfigs/<UPPERCASE-ID>.yaml` if present ([02 DEV-36(d)](02-security-and-secrets.md)).

**Encryption:** daemon encrypts on write ([02 ADD-32](02-security-and-secrets.md)); 1.x UI encrypted before repository insert (`KubeConfigViewModel.swift:225-274`).

#### 3.5.3 `kubeconfig.delete`

- If `id == Default` → `KUMA_K8S_DEFAULT_IMMUTABLE`.
- Else delete row; remove materialized file (DEV-36(d)).

1.x UI sets selection to first list entry after delete (`KubeConfigViewModel.swift:287-292`); clients may replicate.

#### 3.5.4 `kubeconfig.contexts`

Params: `kubeConfigID` (optional → Default).

1. Resolve config (virtual or DB); `yaml = resolvedPlainYAML`.
2. Result:
   - `contexts`: `parseContexts(fromYaml: yaml)`
   - `currentContext`: `parseCurrentContext(fromYaml: yaml)` (may be stale vs list; still returned as in 1.x UI `activeContextName`)

No subprocess.

### 3.6 `kubeconfig.test_connection`

Params: `kubeConfigID?`, `context?` (stored provider context string), `refresh?: bool` (default `false`).

1. Load YAML via `resolvedPlainYAML` for the config.
2. `validationContext = resolveContextName(stored: context, in: yaml)` (may be empty string).
3. Run `KubeConnectionValidator.validateConnection(configContent: yaml, context: validationContext, forceRefresh: refresh)` (§3.7).
4. Wire result: `{ reachable: bool, errorMessage: string|null, verifiedAt: ISO-8601 }` mirroring `KubeValidationResult`.

Does not mutate DB. May update the in-memory validation cache.

### 3.7 `KubeConnectionValidator` (connectivity probe + cache)

Actor singleton in 1.x (`shared`); daemon holds one cache per process.

#### 3.7.1 Cache key

`SHA-256( UTF-8 bytes of "\(trimmedContent)::\(context)" )` as lowercase hex (`KubeConnectionValidator.swift:32-35`). **`context` is the parameter passed in**, not re-trimmed for the hash input (trimming happens only when building argv).

#### 3.7.2 Algorithm `validateConnection(content, context, forceRefresh)`

1. `trimmedContent = trim-WN(content)`. If empty → return `{ reachable: false, errorMessage: "Empty kubeconfig content", verifiedAt: now }` (not cached in 1.x before return — actually it returns without caching empty content at line 45-47; **do not cache** empty content).
2. `cacheKey = computeCacheKey(...)`. If `!forceRefresh` and cache hit → return cached.
3. Resolve `kubectl` via [03 §3.10.6](03-settings-and-environment.md). If null → `{ reachable: false, errorMessage: "kubectl binary not found in system PATH" }`, **store in cache**, return.
4. Write `trimmedContent` to `kuma-chk-<UUID>.yaml` atomically; `defer` delete file (`:68-70`).
5. Before spawn: honor task cancellation → `{ reachable: false, errorMessage: "Validation cancelled" }` (not cached on cancellation path in 1.x `:117-120`).
6. **Argv** (exact order):

```
<kubectlPath>
--kubeconfig <tempFile.path>
version
--output=yaml
--request-timeout=4s
[--context <trimmedContext>]   # only if trim-WN(context) non-empty
```

Stdout and stderr merged to one pipe (`:84-86`).

7. On spawn error: `{ reachable: false, errorMessage: localizedDescription }`, cache, return.
8. Wait for exit; on cancel terminate process (`:96-101`).
9. Read merged output. **Success** iff exit code `0` **and** (output contains substring `serverVersion` **or** `gitVersion`) (`:107-108`).
10. If success → `{ reachable: true, errorMessage: null }`; else `{ reachable: false, errorMessage: "Unable to reach cluster" }`.
11. Store result in cache; return.

**User-visible probe messages** (fixed strings only on wire; kubectl stderr is never returned):

| Condition | `errorMessage` |
|-----------|----------------|
| Empty YAML | `Empty kubeconfig content` |
| No kubectl | `kubectl binary not found in system PATH` |
| Cancelled | `Validation cancelled` |
| Reachability failure | `Unable to reach cluster` |
| Spawn/other error | `error.localizedDescription` from Foundation |

#### 3.7.3 `clearCache()`

1.x exposes `clearCache()` (`:129-131`) but **has no production caller**. Daemon **MAY** call it when Default kubeconfig path settings change or a stored kubeconfig is updated/deleted [DEV-80].

### 3.8 `KubeConfigMaterializer.kubectlKubeconfigPath(for provider)`

Returns absolute path string for `kubectl --kubeconfig`, or `null` for Default when no file resolves.

Order (`KubeConfigMaterializer.swift:10-55`):

1. **Legacy** `provider.customKubeConfigPath` trim-WN non-empty: `expanded = tilde-expand`; if file exists → return `expanded` (import-only column; [01](01-data-model.md)).
2. `configID = provider.kubeConfigID ?? Default`.
3. If `configID == Default`: return `resolved_kubeconfig_path()` ([03 §3.10.7](03-settings-and-environment.md)) — may be `null`.
4. Fetch row by id; missing → throw `invalidConfiguration("Selected kubeconfig no longer exists.")`.
5. If `sourceFilePath` trim-WN non-empty:
   - `expanded = tilde-expand`; exists → return expanded.
   - Else throw `invalidConfiguration("Kubeconfig file not found at <rawPath>.")` where `<rawPath>` is the **stored unexpanded** path (`:40`).
6. Decrypt `configContent`; trim. Empty → `invalidConfiguration("Selected kubeconfig is empty.")`.
7. Write to materialized path (§3.1); return that path.

Default kubeconfig **never** uses materialized files when the user's file exists; when `resolved_kubeconfig_path()` is `null`, execution still proceeds with no `--kubeconfig` flag (kubectl default locations).

Materialization lifecycle: [02 §3.7.2](02-security-and-secrets.md).

### 3.9 `KubeConfigExecutionResolver.resolve(for provider)`

Returns `KubeExecCredentials { kubeconfigPath?, context? }`.

1. Copy provider; if `kubeConfigID == null` → set to Default (`:14-17`).
2. `kubeconfigPath = try kubectlKubeconfigPath(for:)`.
3. `yaml = loadYAML(...)`:
   - Default id: read file at `kubeconfigPath` if set; else read via `resolved_kubeconfig_path()` / settings path (`:42-56`); may be `""`.
   - Other ids: fetch row or throw `Selected kubeconfig no longer exists.`; decrypt ciphertext (`:59-62`).
4. `context = resolveContextName(stored: provider.kubeContext, in: yaml)`.
5. Return credentials (context may be `null`).

### 3.10 `KubeTargetType`

Wire/stored raw strings (`KubeTargetType.swift:3-6`):

| Raw | Label | `listResource` (`kubectl get`) | `portForwardKind` |
|-----|-------|-------------------------------|-------------------|
| `pod` | Pod | `pods` | `pod` |
| `service` | Service | `services` | `service` |
| `deployment` | Deployment | `deployments` | `deployment` |

**Decode:** `KubeTargetType(rawValue: provider.kubeTargetType ?? "") ?? .pod` (`KubeTargetResolver.swift:27`).

Read-time defaults `pod` / `usePattern true`: [01 §3.14.3](01-data-model.md).

Runtime contract summary ([`docs/specs/06-services.md`](../06-services.md)):

| Type | Pattern off | Pattern on |
|------|-------------|------------|
| Pod | `pod/<name>` verbatim | `kubectl get pods` (Running) + matcher |
| Service | `service/<name>` | `kubectl get services` + matcher |
| Deployment | `deployment/<name>` | `kubectl get deployments` + matcher |

### 3.11 `KubeTargetResolver.resolve(provider, kubectlPath, exec)`

Output: `KubeResolvedTarget { kind, name, kubectlReference = "<kind>/<name>" }`.

#### 3.11.1 Target name required

`targetName = trim-WN(provider.targetName)`. Empty → throw `invalidConfiguration("Target resource name is required (e.g. my-app-service or pod pattern).")` (`:23-25`).

#### 3.11.2 Discovery vs verbatim

`kubeTarget = decode type`; `namespace = trim-WN(provider.kubeNamespace)`.

**Run discovery** (`discoverMatchingName`) when `shouldDiscoverResources` is true (`:48-55`):

- `provider.usePattern ?? true` → **true** (nil usePattern defaults to true).
- **Or** `kubeTarget == .pod` **and** `KubeTargetNamingHints.looksLikeStableWorkloadName(targetName)` → true.

Otherwise `resolvedName = targetName` (verbatim).

#### 3.11.3 Discovery subprocess

Log line (activity / optional callback): `Discovering <displayLabel> in namespace '<nsLabel>' for '<targetPattern>'...` where `nsLabel = namespace` if non-empty else `default` (`:66-67`).

**Argv** (exact order, `EphemeralCLI`, timeout 30 s):

```
get <listResource>
```

Then for **`pod` only**:

```
--field-selector=status.phase=Running
-o name
```

For **service** and **deployment**:

```
-o name
```

Then optionally:

```
--kubeconfig <path>    # if exec.kubeconfigPath non-empty
-n <namespace>          # if namespace non-empty
--context <ctx>        # if exec.context trim-WN non-empty
```

(`KubeTargetResolver.swift:69-89`)

**Parse stdout** (`parseResourceNames`):

- Split lines on newlines; trim-WN each; drop empty.
- For each line: if contains `/`, take substring **after the last `/`**; else whole line.
- Sort lexicographically (`String` sort, `:133`).

**Empty list**

- If stderr trim-WN non-empty → `processFailed("Kubectl <listResource> discovery error: <stderr>")`.
- Else `processFailed("<emptyHint> in namespace '<nsLabel>'.")` where `emptyHint` = `No running pods found` for pod, else `No <listResource> found` (`:100-106`).

**Matching**

`KubeTargetNameMatcher.firstMatch(pattern: targetPattern, in: resourceNames, allowPodReplicaPrefix: targetType == .pod)`.

If no match → `processFailed("Found <count> <listResource> in '<nsLabel>', but none matched '<targetPattern>'. Examples: <first 3 names comma-separated>")` (`:115-117`).

On success log: `Using <portForwardKind>/<matched> for port-forward.` (`:120`).

Return `KubeResolvedTarget(kind: kubeTarget.portForwardKind, name: matched)`.

### 3.12 `KubeTargetNameMatcher.firstMatch`

Input names should already be sorted; matcher sorts again (`:15`).

Let `trimmedPattern = trim-WN(pattern)`. Empty → `null`.

**Wildcard:** if `trimmedPattern.contains("*")`:

- `cleanedPattern = trimmedPattern` with all `*` removed.
- If `cleanedPattern` empty → return first of sorted names.
- Else first name where `name.localizedCaseInsensitiveContains(cleanedPattern)` (`:16-21`).

**Exact:** first sorted name `== trimmedPattern` (`:24-25`).

**Pod replica prefix** (only if `allowPodReplicaPrefix`):

1. `workloadPattern = trimmedPattern` trimmed of leading/trailing `-` characters (`CharacterSet(charactersIn: "-")`).
2. If empty → `null`.
3. `hyphenatedPrefix = workloadPattern + "-"`; first name with `hasPrefix(hyphenatedPrefix)` (`:33-35`).
4. **Stem ambiguity:** filter pods where `replicaPodWorkloadStem(podName)` matches stem rules (`:38-47`):
   - `stem == workloadPattern`, or `stem.hasPrefix(workloadPattern) && stem.count > workloadPattern.count`.
   - Collect matches; compute set of stems; if stems.count != 1 → `null`; else return `stemMatches[0]` (first in sorted stemMatches order).

### 3.13 `KubeTargetNamingHints`

**`replicaPodWorkloadStem(podName)`** (`:5-15`): split on `-` (keep empty segments). Need ≥3 parts. Let last = `podHash`, second last = `rsHash`. Valid iff `podHash.count == 5`, `rsHash.count` in 8...10 inclusive, both all alphanumeric. Return parts `dropLast(2)` joined with `-`; else `null`.

**`looksLikeStableWorkloadName(name)`** (`:19-25`): trim-WN, trim `-` from ends; empty → false; if lowercased == `pod` → false; true iff `replicaPodWorkloadStem(name) == null`.

### 3.14 `KubePortForwardPlan.build`

After resolution, build argv for **`kubectl`** (executable separate):

**Order** (`KubePortForwardPlan.swift:17-36`):

```
port-forward
<kind>/<name>
[--kubeconfig <exec.kubeconfigPath>]     # if non-empty
<localPort>:<remotePort>                 # one arg per mapping, DB order
[-n <namespace>]                         # if provider namespace trim-WN non-empty
[--context <context>]                    # if context trim-WN non-empty (runner passes execConfig.context trimmed)
```

`localPorts = portMappings.map(localPort)`.

Full process argv = `[kubectlPath] + plan.arguments` ([06 §3.9.2](06-execution-engine.md)).

### 3.15 `KubePortForwardAdoption`

See [06 §3.9.2 step 7](06-execution-engine.md) for runner integration.

`findAdoptablePID(plan)`:

1. If `plan.localPorts` empty → `null`.
2. For each local port in order: `occupyingPIDs(port)`; if any empty → `null`.
3. `common = intersection` of all pid sets; empty → `null`.
4. For `pid` in `common.sorted()`: load command line via `ps -p pid -ww -o command=`; trim-WN; skip empty.
5. First pid where `matchesPortForward(commandLine, plan)` wins.

`matchesPortForward` (`KubePortForwardAdoption.swift:34-59`):

| Step | Rule |
|------|------|
| a | `lower(commandLine)` contains `kubectl` and `port-forward` |
| b | `commandLine` contains `plan.kubectlReference` (case-sensitive) |
| c | Every plan arg containing `:` and not starting with `-` must appear as substring in `commandLine` |
| d | If plan has `-n` or `--namespace` value `ns`: command contains `-n ns`, `-n=ns`, `--namespace ns`, `--namespace=ns`, or bare `ns` |
| e | If plan has `--context` value `c`: same pattern for `--context` / bare `c` |
| f | If plan has `--kubeconfig` value `p`: let `expanded = tilde-expand(p)`; match if command contains `expanded` **or** (basename non-empty and command contains basename); **else false** |
| g | If no `--kubeconfig` in plan → true after prior checks |

**Note:** If plan has no `-n`, namespace is **not** verified (parity, [06](06-execution-engine.md)).

### 3.16 `KubeLiveTargetDisplay` and `resolvedTarget`

In-memory map `serviceID → resolved name` (lock-protected); **never SQLite** (`KubeLiveTargetDisplay.swift:3-30`).

- `KubernetesRunner` after resolve: `setResolvedName(resolved.name, for: service.id)` (`KubernetesRunner.swift:42`).
- Activity: `Resolved target: <name>` (`:43-46`).
- On runner stop: `clear(serviceID)` (`:92-94`).
- Wire runtime field `resolvedTarget` = this name while running ([06 §3.3](06-execution-engine.md)); cleared on stop.

### 3.17 `k8s.resolve_target` [PARITY]

Read-only; same algorithm as §3.11 using supplied fields (no service start).

**Params**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `kubeConfigID` | UUID | no | null = Default |
| `kubeContext` | string | no | passed to `resolveContextName` |
| `kubeNamespace` | string | no | |
| `targetName` | string | yes | |
| `kubeTargetType` | string | no | default decode `pod` |
| `usePattern` | bool | no | default `true` when null |

**Algorithm**

1. Resolve `kubectl`; if null → `KUMA_K8S_KUBECTL_NOT_FOUND` (message matches `binaryNotFound`).
2. Build synthetic `Provider` with `type = kubernetes` and given fields.
3. `exec = KubeConfigExecutionResolver.resolve(for:)` (may throw same errors as start).
4. `resolved = KubeTargetResolver.resolve(...)`.
5. Result `{ kind, name, kubectlReference }`.

Optional `recordToActivityLog` is **not** supported (no service context).

### 3.18 `k8s.namespaces` [V2-ADD ADD-04]

Lists namespace names for UI/CLI pickers (no 1.x RPC; 1.x UI did not call `kubectl get namespaces`).

**Params:** `kubeConfigID?`, `context?` (stored string; resolved via YAML like §3.2.3).

1. Resolve `kubectl` → else `KUMA_K8S_KUBECTL_NOT_FOUND`.
2. Load YAML for config; `ctx = resolveContextName(stored: context, in: yaml)`.
3. Write temp kubeconfig with trimmed YAML (same hygiene as §3.7 / [02 §3.7.3](02-security-and-secrets.md)) **or** use materialized/path from Default/stored file when the probe used a path — **normative:** use the same temp-file approach as `test_connection` for consistency (content snapshot at call time).
4. **Argv:**

```
get namespaces
-o name
--kubeconfig <tempOrPath>
[--context <ctx>]    # if trim-WN(ctx) non-empty
```

Timeout: 30 s. Stdio: capture stderr on failure.

5. Parse like §3.11.3 (strip after last `/`, sort). Return `{ namespaces: string[] }`.

Non-zero exit or timeout → `KUMA_K8S_KUBECTL_FAILED` with message `Kubectl namespaces list error: <stderr trim>` (or timeout text).

### 3.19 `k8s.resources` [V2-ADD ADD-04]

**Params:** `kubeConfigID?`, `context?`, `namespace?`, `resourceType` (`pod`|`service`|`deployment`).

1. Map `resourceType` to `KubeTargetType`; unknown → `KUMA_DAT_INVALID_ENUM`.
2. Same credential + temp file setup as §3.18.
3. **Argv:** identical to §3.11.3 discovery (`get <listResource>`, pod Running filter + `-o name`, optional `--kubeconfig`, `-n`, `--context`).
4. Return `{ names: string[] }` (short names, sorted).

Errors mirror §3.11.3 empty-list rules with `KUMA_K8S_KUBECTL_FAILED`.

### 3.20 Workload logs argv (`kubectl logs`)

Used by `LiveLogSourceRunner.tailKube` ([08](08-logs-and-events.md)); parity reference:

1. Resolve `kubectl`; silent no-op if missing (`:57`).
2. `exec = KubeConfigExecutionResolver.resolve`; silent return on throw (`:58`).
3. `resolved = KubeTargetResolver.resolve`; silent return on throw (`:59-63`).
4. Build args (**initial** list):

```
logs
-f
--tail=200
<kind>/<name>
```

5. If `exec.kubeconfigPath` non-empty → **insert** at index 0: `--kubeconfig`, path (`:66-67`).
6. If `exec.context` trim-WN non-empty → append `--context`, ctx (`:69-70`).
7. If `provider.kubeNamespace` trim-WN non-empty → append `-n`, ns (`:72-73`).
8. `streamProcess(executable: kubectl, arguments: args, ...)` (`:75`).

**Note:** `--kubeconfig` ends up **before** `logs` after insert-at-0 (parity).

### 3.21 Kubernetes runner start (reference)

Full ordered pipeline: [06 §3.9.2](06-execution-engine.md). This spec owns steps 3–7 algorithms. Activity lines:

| When | Message |
|------|---------|
| After resolve | `Resolved target: <name>` |
| Adoption | `Adopted existing port-forward (PID <pid>)` |
| Launch | `Launching kubectl port-forward…` (U+2026) |

Binary missing: `Required binary 'kubectl' could not be located on this Mac.`

Port mappings empty: `Invalid configuration: At least one port mapping (Local:Remote) is required for Kubernetes port-forwarding.`

### 3.22 Function accountability ([CLIENT] / dead)

| Symbol | Disposition |
|--------|-------------|
| `KubeConfigViewModel` UI state, forms, pickers | [CLIENT] FEAT rows |
| `KubeConnectionValidator.clearCache` | Dead in 1.x; DEV-80 |
| `KubeTargetType.listNameJSONPath` | Unused in 1.x resolver (uses `-o name`); documented for parity |
| `KubeConfigViewModel.parseCurrentContext/parseContexts` static | Delegates to YAML parser |

---

## 4. Data shapes

### 4.1 `KubeExecCredentials` (internal / preflight)

| Field | Type | JSON (when exposed) |
|-------|------|---------------------|
| `kubeconfigPath` | string? | `kubeconfigPath` |
| `context` | string? | `context` |

### 4.2 `KubeResolvedTarget`

| Field | Type | JSON |
|-------|------|------|
| `kind` | string | `kind` |
| `name` | string | `name` |
| `kubectlReference` | string | `kubectlReference` |

### 4.3 `KubeValidationResult` / `kubeconfig.test_connection`

| Field | Type | JSON |
|-------|------|------|
| `reachable` | bool | `reachable` |
| `errorMessage` | string? | `errorMessage` |
| `verifiedAt` | timestamp | `verifiedAt` |

### 4.4 `kubeconfig.contexts` result

| Field | Type | JSON |
|-------|------|------|
| `contexts` | string[] | `contexts` |
| `currentContext` | string? | `currentContext` |

### 4.5 `k8s.namespaces` result

| Field | Type | JSON |
|-------|------|------|
| `namespaces` | string[] | `namespaces` |

### 4.6 `k8s.resources` result

| Field | Type | JSON |
|-------|------|------|
| `names` | string[] | `names` |

### 4.7 Provider kubernetes columns (reference)

See [01 §4.6](01-data-model.md) fields `kubeConfigID`, `customKubeConfigPath`, `kubeContext`, `kubeNamespace`, `targetName`, `kubeTargetType`, `usePattern`.

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-K8S-01 | [PARITY] | Virtual Default kubeconfig in list (`...0001`, name `Default`) | `KubeConfigViewModel.swift:96-104` | `kubeconfig.list`, `kubeconfig.get` |
| FEAT-K8S-02 | [PARITY] | List custom kubeconfigs from DB (exclude Default id rows) | `KubeConfigRepository.swift:21-24`, `KubeConfigViewModel.swift:108-126` | `kubeconfig.list` |
| FEAT-K8S-03 | [PARITY] | Get one kubeconfig with redaction / `revealSecrets` | `KubeConfigViewModel.swift:78-131` | `kubeconfig.get` |
| FEAT-K8S-04 | [PARITY] | Create/update file-backed kubeconfig (`encrypt("")`, store path) | `KubeConfigViewModel.swift:234-240` | `kubeconfig.create`, `kubeconfig.update` |
| FEAT-K8S-05 | [PARITY] | Create/update paste-backed kubeconfig (`encrypt(yaml)`) | `KubeConfigViewModel.swift:241-245` | `kubeconfig.create`, `kubeconfig.update` |
| FEAT-K8S-06 | [PARITY] | Delete stored kubeconfig (not Default) | `KubeConfigViewModel.swift:287-295` | `kubeconfig.delete` |
| FEAT-K8S-07 | [PARITY] | Parse context names from YAML | `KubeConfigYAMLParser.swift:23-51` | `kubeconfig.contexts` |
| FEAT-K8S-08 | [PARITY] | Parse `current-context:` line | `KubeConfigYAMLParser.swift:5-20` | `kubeconfig.contexts` |
| FEAT-K8S-09 | [PARITY] | Resolve effective `--context` from stored + YAML | `KubeConfigYAMLParser.swift:55-65` | `kubeconfig.contexts`, execution, preflight |
| FEAT-K8S-10 | [PARITY] | Cluster reachability probe + SHA-256 cache | `KubeConnectionValidator.swift:38-126` | `kubeconfig.test_connection`, `service.preflight` |
| FEAT-K8S-11 | [PARITY] | Materialize pasted kubeconfig to `<data dir>/kubeconfigs/<UUID>.yaml` | `KubeConfigMaterializer.swift:43-55` | internal; `service.start` |
| FEAT-K8S-12 | [PARITY] | Resolve `--kubeconfig` path (Default, file-backed, legacy provider path) | `KubeConfigMaterializer.swift:10-41` | internal; `service.start` |
| FEAT-K8S-13 | [PARITY] | Load exec YAML + context for provider | `KubeConfigExecutionResolver.swift:8-63` | internal; `k8s.resolve_target` |
| FEAT-K8S-14 | [PARITY] | Target resolution (verbatim vs discovery) | `KubeTargetResolver.swift:17-46` | `k8s.resolve_target`, `service.start`, preflight |
| FEAT-K8S-15 | [PARITY] | Pattern / wildcard / pod replica matching | `KubeTargetNameMatcher.swift:7-48` | same |
| FEAT-K8S-16 | [PARITY] | Stable workload name heuristic for pod discovery | `KubeTargetNamingHints.swift:3-25` | same |
| FEAT-K8S-17 | [PARITY] | Port-forward argv builder | `KubePortForwardPlan.swift:10-42` | `service.start` ([06](06-execution-engine.md)) |
| FEAT-K8S-18 | [PARITY] | Adopt matching external port-forward by PID | `KubePortForwardAdoption.swift:8-95` | `service.start` |
| FEAT-K8S-19 | [PARITY] | Ephemeral `resolvedTarget` display name | `KubeLiveTargetDisplay.swift:4-30`, `KubernetesRunner.swift:42-43` | `service.status` |
| FEAT-K8S-20 | [PARITY] | Inspector async target validation | `ServiceInspectorViewModel+Validation.swift:92-102` | `service.preflight` ([05](05-providers-and-validation.md)) |
| FEAT-K8S-21 | [V2-ADD] | List cluster namespaces (`kubectl get namespaces`) | ADD-04 | `k8s.namespaces` |
| FEAT-K8S-22 | [V2-ADD] | List namespaced resources for picker | ADD-04 | `k8s.resources` |
| FEAT-K8S-23 | [PARITY] | Workload log streaming argv | `LiveLogSourceRunner.swift:56-75` | `logs.follow`, `logs.workload_tail` ([08](08-logs-and-events.md)) |
| FEAT-K8S-24 | [CLIENT] | Inline kubeconfig editor, file picker, connection settings views | `Presentation/.../Kubernetes/**` | - |
| FEAT-K8S-25 | [CLIENT] | Connection spinner / `connectionError` / `testConnection` button | `KubeConfigViewModel.swift:37-40,300-340` | - |
| FEAT-K8S-26 | [CLIENT] | Reload Default kubeconfig file content on selection | `KubeConfigViewModel.swift:149-165` | - |

---

## 6. Error catalog

Stable codes `KUMA_K8S_*`. User-facing text for execution errors uses `ServiceExecutionError` prefixes ([05 §3.9](05-providers-and-validation.md)).

| Code | Condition | Message (exact where fixed) |
|------|-----------|------------------------------|
| `KUMA_K8S_DEFAULT_IMMUTABLE` | create/update/delete Default id | `The default kubeconfig cannot be modified.` |
| `KUMA_K8S_NOT_FOUND` | `kubeconfig.get/update/delete` missing id | `Kubeconfig not found.` |
| `KUMA_K8S_NAME_REQUIRED` | blank name on write | `Kubeconfig name is required.` |
| `KUMA_K8S_SOURCE_CONFLICT` | both inline YAML and path in one write | `Provide either a file path or pasted YAML, not both.` |
| `KUMA_K8S_FILE_NOT_FOUND` | file-backed path not found | `Kubeconfig file not found.` |
| `KUMA_K8S_CONTENT_REQUIRED` | paste mode empty | `Kubeconfig content is required.` |
| `KUMA_K8S_KUBECTL_NOT_FOUND` | kubectl not resolved | `Required binary 'kubectl' could not be located on this Mac.` |
| `KUMA_K8S_KUBECTL_FAILED` | discovery/list subprocess failure | `Kubectl <operation> error: <detail>` or timeout message |
| `KUMA_CONFLICT_STALE` | `expectedUpdatedAt` mismatch | (global, [01](01-data-model.md)) |

**1.x configuration strings (via throws, no separate code)**

| Message body (after prefix) | Source |
|----------------------------|--------|
| `Selected kubeconfig no longer exists.` | `KubeConfigMaterializer.swift:31`, `KubeConfigExecutionResolver.swift:60` |
| `Kubeconfig file not found at <rawPath>.` | `KubeConfigMaterializer.swift:40` |
| `Selected kubeconfig is empty.` | `KubeConfigMaterializer.swift:46` |
| `Target resource name is required (e.g. my-app-service or pod pattern).` | `KubeTargetResolver.swift:24` |
| `Kubectl <listResource> discovery error: <stderr>` | `KubeTargetResolver.swift:103` |
| `No running pods found in namespace '<ns>'.` / `No <listResource> found in namespace '<ns>'.` | `:105-106` |
| `Found <n> <listResource> in '<ns>', but none matched '<pattern>'. Examples: ...` | `:115-116` |

Vault decrypt failures on inline kubeconfig: [02 §3.2.4](02-security-and-secrets.md) (`CryptoVaultError` messages).

---

## 7. Deviations

| Id | One line |
|----|----------|
| DEV-02 | Legacy `kuma.custom_kubectl_path` / kubeconfig path keys honored at runtime ([03](03-settings-and-environment.md)). |
| DEV-36 | Materialized kubeconfig permissions and delete-on-update ([02](02-security-and-secrets.md)). |
| DEV-37 | Kubeconfig decrypt failures never return ciphertext as YAML ([02](02-security-and-secrets.md)). |
| DEV-65 | Context sanitization only when patch touches kube fields and YAML has contexts ([05](05-providers-and-validation.md)). |
| DEV-78(e) | Adoption registration falls through if pid died ([06](06-execution-engine.md)). |
| DEV-79 | Runner environment includes resolved PATH ([06](06-execution-engine.md)). |
| DEV-80 | Daemon SHOULD call `clearCache` on kubeconfig writes and Default path setting changes (1.x never clears; cache grows until process exit). |
| ADD-04 | `k8s.namespaces` / `k8s.resources` RPCs for headless clients (§3.18–3.19). |

---

## 8. Invariants

| Id | Statement |
|----|-----------|
| INV-D-K8S-01 | No RPC response includes kubeconfig plaintext unless `revealSecrets` on an allowed transport ([02](02-security-and-secrets.md)). |
| INV-D-K8S-02 | No row with `id = Default` is ever inserted into `kube_config`. |
| INV-D-K8S-03 | Materialized file path for a given config UUID is stable (`<UPPERCASE-UUID>.yaml`) for port-forward adoption matching. |
| INV-D-K8S-04 | `resolvedTarget` is never persisted in `kuma.sqlite`; only in-memory / runtime wire. |
| INV-D-K8S-05 | Connection probe never returns raw kubectl stderr to clients; only fixed or localized messages (§3.7). |
| INV-D-K8S-06 | Every `kubectl get` helper uses timeout 30 s unless explicitly the 4 s `version` probe. |

---

## 9. Acceptance tests

| Id | Arrange | Assert |
|----|---------|--------|
| DT-K8S-01 | Default settings + `~/.kube/config` exists | `kubeconfig.list` first item id `...0001`, name `Default`, `isDefault=true` |
| DT-K8S-02 | Insert paste-backed config | `kubeconfig.get` has `hasContent=true`, no plaintext without reveal |
| DT-K8S-03 | YAML fixture with two contexts + `current-context` | `kubeconfig.contexts` lists both; `resolveContextName` prefers stored when valid |
| DT-K8S-04 | Mock kubectl: version stdout contains `serverVersion` | `kubeconfig.test_connection` `reachable=true`; second call hits cache unless `refresh=true` |
| DT-K8S-05 | Mock kubectl empty content | `errorMessage` = `Empty kubeconfig content` |
| DT-K8S-06 | Provider pod exact name, pattern off | `k8s.resolve_target` → `pod/<name>` without `get pods` (noop script) — **K1** |
| DT-K8S-07 | Service/deployment exact — **K2, K3** | References match tests |
| DT-K8S-08 | Service pattern `api-svc-*` — **K4** | Chooses lexicographic first match `api-svc-prod` |
| DT-K8S-09 | Pod pattern list — **K6** | |
| DT-K8S-10 | Running port-forward with matching argv | `service.start` adopts PID, activity contains `Adopted existing port-forward` |
| DT-K8S-11 | Plan with `--kubeconfig` materialized path | Adoption requires expanded path or basename in ps line |
| DT-K8S-12 | Delete kubeconfig row | Materialized `<UUID>.yaml` removed (DEV-36d) |
| DT-K8S-13 | `k8s.namespaces` with mock | Returns sorted short names |
| DT-K8S-14 | Start kubernetes service | Runtime `resolvedTarget` equals discovered pod name; cleared after stop |

---

## Open questions / residual risks

1. **`k8s.namespaces` temp file vs live file path:** §3.18 mandates temp snapshot for parity with `test_connection`; clients reading namespaces while an external process edits the on-disk Default file may see stale data until refresh (same as 1.x probe semantics).
2. **`clearCache`:** DEV-80 is SHOULD, not MUST, to avoid changing 1.x cache lifetime in minimal ports; full daemon should implement it.
3. **Relative `sourceFilePath` on kubeconfig rows:** Stored paths are unexpanded; tilde-expand at use. Relative paths depend on daemon cwd `/` ([05 §1.1](05-providers-and-validation.md)).
