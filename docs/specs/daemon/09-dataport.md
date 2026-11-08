# Daemon Spec 09: DataPort (Backup, Import, Export, Factory Reset)

> **Area code:** `DPT` · **Status:** Draft for implementation · **Baseline:** Kuma 1.x (Swift)
> **Depends on:** [00 Overview and Conventions](00-overview-and-conventions.md), [01 Data Model](01-data-model.md), [02 Security and Secrets](02-security-and-secrets.md), [03 Settings and Environment](03-settings-and-environment.md), [04 Workspaces, Groups, Services](04-workspaces-groups-services.md), [06 Execution Engine](06-execution-engine.md), [08 Logs and Events](08-logs-and-events.md)
> **Consumed by:** [10](10-rpc-protocol.md), [11](11-cli.md), [12](12-mcp.md), [13](13-rest-api.md), [15](15-traceability-and-parity.md)

---

## 1. Purpose and scope

This spec defines every **daemon-owned** behavior of Kuma DataPort: the backup JSON schema (version 1), polymorphic ingestion, scoped export, import strategies (`preserveOrMerge`, `reassignIDs`), selective import, workspace-scoped re-ID import, conflict renaming, kubeconfig and secret handling on the wire, preview computation for clients, and factory reset orchestration.

Out of scope (referenced, not re-specified): entity column semantics and SQLite DDL ([01](01-data-model.md)); vault algorithm and redaction ([02](02-security-and-secrets.md)); workspace avatar resize rules on import ([04](04-workspaces-groups-services.md) §3.3); process stop escalation details ([06](06-execution-engine.md)); save/open panels, sheets, drag overlay, relaunch shell script ([CLIENT]).

The daemon is the **only** writer of `kuma.sqlite` rows during import/export/reset. Clients call the RPC methods in [00 §5.6](00-overview-and-conventions.md).

---

## 2. 1.x source of truth (paths read)

| Path | Used for |
|------|----------|
| `Kuma/Core/DataPort/DataPortService.swift` | `currentVersion`, `DataPortError` |
| `Kuma/Core/DataPort/DataPortService+BackupModels.swift` | `KumaBackup`, `SingleServiceExport`, export DTOs, `category`, `resolvedTarget`, compose image extract |
| `Kuma/Core/DataPort/DataPortService+ImportExport.swift` | Scopes, strategies, wrap/parse/encode/decode, `backupDateString` |
| `Kuma/Core/DataPort/DataPortService+FactoryReset.swift` | `resetAllAppStorage`, `relaunchApp` |
| `Kuma/Core/Database/Repositories/DataPortRepository.swift` | `exportData`, `importData` routing |
| `Kuma/Core/Database/Repositories/DataPortRepository+Export.swift` | `exportAll`, `exportWorkspace`, `exportSingleServiceBackup`, `exportSingleServiceJSON`, port/provider export resolution |
| `Kuma/Core/Database/Repositories/DataPortRepository+Import.swift` | `importAll`, `importSelective`, `importIntoWorkspace` |
| `Kuma/Core/Database/Repositories/DataPortRepository+Mapping.swift` | `toExportProvider`, `fromExportProvider`, `importKubeConfigs`, `collectReferencedKubeConfigIDs` |
| `Kuma/Core/Database/AppDatabase.swift:62-75` | `wipeAndResetDatabase` |
| `Kuma/Presentation/Features/Settings/Views/Sections/SettingsDataSection.swift` | Settings export/import/reset entry points, filename pattern |
| `Kuma/Presentation/Features/Services/Views/Deck/ServicesDeckView+DataPort.swift` | Workspace export/import filenames, `parseAnyBackup` on workspace import |
| `Kuma/ContentView.swift:31-74` | Window drop → `parseAnyBackup`, selective import |
| `Kuma/Presentation/Features/DataPort/Models/ImportPreviewModels.swift` | Preview row shapes |
| `Kuma/Presentation/Features/DataPort/Views/ImportPreviewSheet.swift` | Full import preview row build |
| `Kuma/Presentation/Features/DataPort/Views/WorkspaceImportPreviewSheet.swift` | Workspace import preview, conflict rename |
| `Kuma/Presentation/Features/Services/ViewModels/ServicesDeckViewModel+ServiceActions.swift:175-187` | Copy Config → `exportSingleServiceJSON` |
| `docs/samples/Kuma-Screenshot-Demo.json` | Ground-truth v1 backup example |
| `docs/specs/05-data-port.md`, `docs/testing/05-data-port-test-matrix.md` | Feature intent and test matrix |
| `KumaTests/Harness/DataPortTestHarness.swift`, `KumaTests/Features/DataPort/*.swift` | Implicit requirements (TC-A01..F05, B07/B07b, A07) |

---

## 3. Normative behavior

### 3.0 Global rules

1. **Serialization.** All DataPort RPC handlers that mutate the DB run on the single database writer ([01 GR-03](01-data-model.md)). Concurrent exports are read-only and MUST be safe in parallel (TC-D05).
2. **UUIDs.** Backup JSON may contain any-case UUID strings; the daemon normalizes to uppercase in SQLite ([01 §3.4.1](01-data-model.md)).
3. **Dates in backup JSON.** Encoder/decoder use Foundation `.iso8601` (`DataPortService+ImportExport.swift:64-71,82-90`): typically `YYYY-MM-DDTHH:MM:SSZ` without fractional seconds in emitted files; decoding accepts ISO-8601 variants Swift accepts.
4. **Secrets on the wire.** RPC responses from this area MUST NOT include `sshPassword`, `ngrokAuthToken`, kubeconfig plaintext, or vault ciphertext in preview/import result objects ([02 §3.8](02-security-and-secrets.md)). Export bytes (`data.export`, file download) contain ciphertext as stored in backups (parity with 1.x JSON export).
5. **Events.** After a successful commit: `data.imported` ([08](08-logs-and-events.md)); after factory reset: `data.reset`. Emit after commit, never inside a transaction.

### 3.1 Constants

| Name | Value | Source |
|------|-------|--------|
| `BACKUP_CURRENT_VERSION` | `1` | `DataPortService.swift:7` |
| `BACKUP_FILENAME_DATE_FORMAT` | `yyyy-MM-dd` (local calendar of encoder process) | `DataPortService+ImportExport.swift:95-98` |
| `SETTINGS_EXPORT_FILENAME` | `kuma-backup-<date>.json` | `SettingsDataSection.swift:157` |
| `WORKSPACE_EXPORT_FILENAME` | `<sanitized-workspace-name>-services-<date>.json` where sanitized = lowercase name, spaces → `-` | `ServicesDeckView+DataPort.swift:7-10` |
| `IMPORT_CONFLICT_SUFFIX` | ` (Imported)` appended as `"\(name) (Imported)"` | `WorkspaceImportPreviewSheet.swift:100-102`, spec 05 INV-DP-06 |
| `IMPORT_KUBECONFIG_DEFAULT_NAME` | `Imported` when backup name absent/blank | `DataPortRepository+Mapping.swift:32` |
| `PORT_IMPORT_PROTOCOL` | `TCP` (hardcoded on import INSERT) | `DataPortRepository+Import.swift:97` |
| `KUBECONFIG_DEFAULT_ID` | `00000000-0000-0000-0000-000000000001` (never imported from backup) | `DataPortRepository+Mapping.swift:11`, [01](01-data-model.md) |
| `JSON_ENCODE_OPTIONS` | `prettyPrinted`, `sortedKeys` | `DataPortService+ImportExport.swift:65,84` |
| `NSError_DOMAIN` | `lokastudio.kuma.dataport` | `DataPortRepository+Export.swift:15,274` |
| `NSError_NOT_FOUND` | code `404`, message `Service <uuid> not found.` | `DataPortRepository+Export.swift:15` |
| `NSError_ENCODE_FAIL` | code `500`, message `Failed to encode service JSON.` | `DataPortRepository+Export.swift:312` |

### 3.2 Backup schema version guard

After JSON decodes into `KumaBackup`, if `version > BACKUP_CURRENT_VERSION` the daemon MUST fail with `DataPortError`-equivalent `KUMA_DPT_UNSUPPORTED_VERSION` and message exactly:

`The backup file was created by a newer version of Kuma (Backup v<backup>, App v<current>). Please update Kuma.`

(`DataPortService.swift:14-15`, TC-B01). Backups with `version <= current` are accepted (including older `0` if present in wild files; 1.x always writes `1`).

### 3.3 Polymorphic ingestion (`parseAnyBackup`)

Algorithm (`DataPortService+ImportExport.swift:48-57`):

1. If `decodeBackup(from:)` succeeds → return that `KumaBackup`.
2. Else if `decodeSingleService(from:)` succeeds → return `wrapSingleService(single, targetWorkspaceID:)`.
3. Else re-run `decodeBackup` and throw its error (JSON or version error).

`wrapSingleService` (`:18-45`): copies service/providers/ports/kubeConfigs; if `targetWorkspaceID` is provided, sets `ExportService.workspaceID` to it; `workspaces`, `workspaceImages`, `groups` are empty/`nil`.

**Every daemon import entry path** MUST use this algorithm (DEV-04). 1.x Settings import used `decodeBackup` only (`SettingsDataSection.swift:191`), rejecting single-service JSON.

### 3.4 Encode/decode helpers

| Function | Input/Output | Notes |
|----------|--------------|-------|
| `encodeBackup` | `KumaBackup` → UTF-8 JSON `Data` | ISO8601 dates, pretty+s sorted keys |
| `decodeBackup` | `Data` → `KumaBackup` | Version guard §3.2 |
| `encodeSingleService` | `SingleServiceExport` → `Data` | Same encoder settings |
| `decodeSingleService` | `Data` → `SingleServiceExport` | `kubeConfigs` key optional, default `[]` (`BackupModels.swift:112`) |
| `backupDateString` | → `yyyy-MM-dd` for today | Used in suggested filenames (ADD-102) |

`KumaBackup.id` (computed, not in JSON): `"\(version)_\(exportedAt.timeIntervalSince1970)_\(workspaces.count)"` (`BackupModels.swift:7`).

### 3.5 Export scopes (`DataPortScope`)

Router (`DataPortRepository.swift:25-33`):

| Scope | Method | Result shape |
|-------|--------|----------------|
| `.all` | `exportAll` | Full DB graph |
| `.workspace(id)` | `exportWorkspace` | One workspace row, its groups, services in workspace, related providers/ports/memberships |
| `.service(id)` | `exportSingleServiceBackup` | One service + providers + ports + referenced kubeconfigs; **empty** workspaces/groups/images |

Missing service on `.service` → `KUMA_DPT_SERVICE_NOT_FOUND` (404 message above).

#### 3.5.1 `exportAll` / `exportWorkspace` relational read

Inside one read transaction (`+Export.swift:59-110,140-210`):

- Workspaces: all (ordered `sortOrder ASC, createdAt ASC`) or filtered by id.
- Groups: all ordered, or filtered by `workspaceID`.
- Services: all `createdAt ASC`, or filtered by `workspaceID`.
- Providers: for selected services, `createdAt ASC`.
- Port mappings: all rows for selected services.
- Memberships: build `groupIDs` per service from `service_group_membership`.

**Port export normalization** (legacy NULL `providerID` rows, v5 backfill behavior):

For each `portMapping` row, compute `associatedProviderID`:

1. Start with `pm.serviceID ?? pm.id` (Swift fallback when `serviceID` null in model).
2. If `serviceID` resolves to a service in the export set: if `service.activeProviderID` set → use it; else first provider of that service by export order.

Emit `ExportPortMapping` with `providerID: pm.providerID ?? associatedProviderID`.

Single-service export uses `p.providerID ?? svc.activeProviderID ?? svc.id` (`+Export.swift:35,294`).

#### 3.5.2 Workspace images

Outside the DB read (`+Export.swift:113-120,213-218`): for each exported workspace with `imagePath`, if `WorkspaceImageStore.loadBase64Image` succeeds, set `workspaceImages[workspace.id.uuidString] = base64`. If map empty → JSON field omitted (`nil`).

#### 3.5.3 Kubeconfig export

`collectReferencedKubeConfigIDs`: all non-default `kubeConfigID` from export providers (`Mapping.swift:5-7`).

For each id, load row; emit `ExportKubeConfig` with `encryptedConfigContent` = SQLite `configContent` (ciphertext), `path` = `sourceFilePath` (`+Export.swift:251-258`). Missing DB row → skip (no error).

Provider export encrypts non-empty `sshPassword` / `ngrokAuthToken` via `CredentialProtector.encryptForStorage` (`Mapping.swift:42-55`); failure aborts export ([02](02-security-and-secrets.md)).

#### 3.5.4 `exportSingleServiceJSON`

Same row collection as `.service` backup, then wrap `SingleServiceExport` and `encodeSingleService`; UTF-8 string (`+Export.swift:265-314`). Used by `data.export_service_json` (Copy Config).

### 3.6 Import strategies

| Strategy | 1.x entry | Daemon RPC | Engine |
|----------|-----------|------------|--------|
| `preserveOrMerge` | Settings/DnD full restore, `importAll` | `data.import` with strategy + full selection | `importAll` |
| `reassignIDs(targetWorkspaceID)` | Deck import, paste service | `data.import` with strategy + service selection + `resolvedNames` | `importIntoWorkspace` then `importAll` on synthetic backup |

`importData` router (`DataPortRepository.swift:37-44`): `preserveOrMerge` → `importAll`; `reassignIDs` → `importIntoWorkspace` with **all** service ids in backup (1.x quirk, DEV-105 when combined with selective UI).

### 3.7 `importAll` (atomic write)

Phases (`+Import.swift:6-105`):

**Phase A — images (before transaction):** For each workspace in backup, if `workspaceImages[ws.id.uuidString]` present, `saveBase64Image` → managed filename; store in `resolvedImagePaths[ws.id]`.

**Phase B — single write transaction:**

1. `importKubeConfigs(backup.kubeConfigs)` — see §3.7.1.
2. For each workspace in backup: save with `imagePath` replaced when resolved.
3. If `backup.groups != nil`: save each group (`save` upsert).
4. For each `ExportService`: build `Service` with `isDisabled ?? false`, `isStarred ?? false`, `groupIDs` from array; `save`; for each `groupID` in array insert membership row.
5. For each `ExportProvider`: `fromExportProvider` → `save`.
6. For each `ExportPortMapping`: resolve `targetServiceID`:
   - If `providerID` maps via `providerToServiceMap` → that service.
   - Else if `providerID` is itself a service id in backup → use as service id (legacy orphan mapping).
   - If resolved: `INSERT ... ON CONFLICT(id) DO UPDATE` with `protocolType = TCP`, `providerID` = export provider id string.

Log info: counts of workspaces/services/providers (`:104`).

**Not performed:** deleting existing rows not mentioned in backup (merge/upsert semantics). Stale services remain unless overwritten by same id.

#### 3.7.1 `importKubeConfigs`

For each entry (`Mapping.swift:9-39`):

- Skip `id == KUBECONFIG_DEFAULT_ID`.
- Trim cipher and path; skip if both empty.
- Upsert: name defaults to `Imported`; empty cipher stored as `""`; empty path → SQL NULL.
- `createdAt`/`updatedAt` from backup or `Date()` now.

#### 3.7.2 `fromExportProvider` secrets

If `sshPassword` / `ngrokAuthToken` non-empty: try `CryptoVault.decrypt`; on failure treat value as legacy plaintext; store decrypted/plain in `Provider` model so `save` re-encrypts ([02 FEAT-SEC-11](02-security-and-secrets.md)).

Category: `ExportProvider.category` switch (`BackupModels.swift:213-224`) — unknown type string → `docker` (parity TC-A06).

### 3.8 `importSelective`

Filter backup (`+Import.swift:109-141`):

- Workspaces: id in `selectedWorkspaceIDs`.
- Services: id in `selectedServiceIDs`.
- Providers: `serviceID` in filtered services.
- Port mappings: `providerID` in filtered provider ids **or** in filtered service ids.
- Kubeconfigs: referenced by filtered providers.
- Groups: if `g.workspaceID` present → must be in selected workspaces; **if `workspaceID` nil → include** (1.x quirk, DEV-105).

Then `importAll(filteredBackup)`.

### 3.9 `importIntoWorkspace` (reassign IDs)

Input: `targetWorkspaceID`, backup, `selectedServiceIDs`, optional `resolvedNames: [UUID:String]`.

**DEV-01 fix (daemon):** Build maps in this order:

1. Filter services to selected ids; assign `serviceIDMap[old] = UUID()` for each.
2. Filter providers for those services; assign `providerIDMap[old] = UUID()` for each.
3. Build `newServices` with new ids, `workspaceID = targetWorkspaceID`, name from `resolvedNames[id] ?? name`, and **`activeProviderID = oldActive.flatMap { providerIDMap[$0] }`** (1.x built services before populating `providerIDMap`, leaving active always `nil`, `+Import.swift:158-170`).
4. Remap providers with new ids and `serviceID` from map.
5. Remap port mappings: new port id; `providerID` from `providerIDMap` or `serviceIDMap` fallback (`:223-238`).
6. Filter kubeconfigs to referenced ids.
7. Synthetic backup with empty workspaces/images, optional groups copied verbatim, remapped entities → `importAll`.

Group memberships in backup still reference **old** group UUIDs; groups are imported as-is when present (may reference other workspaces' groups — parity).

### 3.10 Name conflict detection

Case-insensitive: `existingNames.contains(service.name.lowercased())` (`WorkspaceImportPreviewSheet.swift:100`).

When conflict: preview shows `hasConflict: true`; import uses resolved name `"\(name) (Imported)"` via `resolvedNames` from client or daemon preview (TC-B05, B06).

Daemon `data.import_preview` MUST compute the same `resolvedNames` for workspace-scoped previews (ADD-100).

### 3.11 Import preview (`data.import_preview`)

Params (normative for [10](10-rpc-protocol.md)):

- `json`: UTF-8 backup bytes **or** base64 of same.
- `mode`: `full` | `workspace` (requires `targetWorkspaceID`).
- Optional `targetWorkspaceID` for polymorphic wrap of single-service files.

Steps:

1. Parse with `parseAnyBackup(from:targetWorkspaceID:)` (§3.3).
2. Load current DB: workspace ids, and for `workspace` mode service names in target workspace (lowercased set).
3. Build rows mirroring 1.x UI:

**Full mode** (`ImportPreviewSheet.buildRows`): per service — workspace name from map or `"Default Workspace"`, workspace id from service or first backup workspace or random placeholder, `isExistingWorkspace` if id in DB, first provider by `serviceID`, category/target from `ExportProvider`, ports where `providerID` matches provider or service id.

**Workspace mode** (`WorkspaceImportPreviewSheet.buildRows`): same per service but conflict detection against target workspace names; populate `resolvedNames` for conflicts.

Response MUST NOT include secret fields; may include `provider.type`, labels, ports, flags, `hasConflict`, `suggestedName`.

Default selection: all rows selected (1.x `onAppear` sets all ids selected).

### 3.12 RPC mapping

| RPC | Behavior |
|-----|----------|
| `data.export` | Param `scope`: `all` \| `{workspaceId}` \| `{serviceId}`. Result: `{ jsonBase64, suggestedFileName }` using §3.1 filename rules. |
| `data.export_service_json` | Param `serviceId`. Result `{ json }` string (SingleServiceExport). |
| `data.import_preview` | §3.11. |
| `data.import` | Parse backup; params: `strategy`, `selectedWorkspaceIds`, `selectedServiceIds`, optional `resolvedNames`, optional `targetWorkspaceId` for reassign. Route §3.6–3.9. On success `{ imported: { workspaces, services, providers } }` counts. |
| `data.factory_reset` | §3.13. Optional `stopServices` default true. |

Concurrent `data.export` calls MUST return identical JSON for unchanged DB (TC-D05).

### 3.13 Factory reset (`data.factory_reset`)

1.x order (`DataPortService+FactoryReset.swift:8-36`, [01 §3.9](01-data-model.md)):

1. **Stop all services** — 1.x: `ProcessRegistry.shared.terminateAll()` (SIGTERM, ~200ms). **Daemon (DEV-102):** stop every operational service via [06](06-execution-engine.md) with full signal escalation and wait; clear runtime registry and activity buffers ([08](08-logs-and-events.md)).
2. **Settings** — 1.x: `removePersistentDomain` for bundle id (or test key subset). **Daemon (DEV-101):** delete all rows from `daemon-state.sqlite` `settings` except keys prefixed `client.` MAY be preserved only if product decision matches [03](03-settings-and-environment.md); default: wipe all settings keys and re-seed defaults on next read.
3. **`wipeAndResetDatabase`** — delete all user tables except `grdb_migrations`, insert one default workspace ([01 §3.9](01-data-model.md)).
4. **Images** — clear image memory cache; delete entire `Workspaces/Images` directory tree.

**Not deleted:** `master.key`, `kubeconfigs/*.yaml` materializations ([02 §3.2.1](02-security-and-secrets.md), [01 §3.9](01-data-model.md)).

Emit `data.reset`. `[CLIENT]` `relaunchApp` shell spawn (`FactoryReset.swift:40-63`) is not invoked by the daemon.

Testing hook: when `XCTestConfigurationFilePath` set, 1.x only clears known settings keys (`:14-26`); daemon tests SHOULD use isolated data dirs instead.

### 3.14 ExportProvider preview helpers (non-persisted)

`category` type aliases: `kube_port_forward`/`kubernetes` → kubernetes; `http_check`/`httpCheck`; `process_monitor`/`processMonitor`; default unknown → docker (`BackupModels.swift:213-224`).

`resolvedTarget` for preview display only — algorithms in `BackupModels.swift:227-279`, `extractComposeImage` `:281-300` (TC-E05). Not stored in SQLite.

### 3.15 Function accountability ([CLIENT] / dead)

| Symbol | Disposition |
|--------|-------------|
| `DataPortService.relaunchApp` | [CLIENT] |
| Import/export UI views under `Presentation/Features/DataPort/**` | [CLIENT] |
| `SettingsDataSection` panels/alerts | [CLIENT] except strings copied into RPC error messages |
| `DataPortRepository.exportAll/importAll` public legacy | PARITY aliases of scoped API |

---

## 4. Data shapes

### 4.1 `KumaBackup` (full backup JSON root)

| Field | Type | Optional | Default if omitted | JSON key |
|-------|------|----------|-------------------|----------|
| version | int | no | — | `version` |
| exportedAt | date (ISO8601) | no | — | `exportedAt` |
| workspaces | [Workspace] | no | `[]` | `workspaces` |
| workspaceImages | map string→string | yes | omit | `workspaceImages` (keys: workspace UUID string, values: base64 PNG) |
| groups | [ServiceGroup] | yes | omit / null | `groups` |
| services | [ExportService] | no | `[]` | `services` |
| providers | [ExportProvider] | no | `[]` | `providers` |
| portMappings | [ExportPortMapping] | no | `[]` | `portMappings` |
| kubeConfigs | [ExportKubeConfig] | no | `[]` | `kubeConfigs` |

`Workspace` and `ServiceGroup` use the same JSON keys as entity Codable in [01](01-data-model.md) (`id`, `name`, `imagePath`, `sortOrder`, `createdAt`, `updatedAt`; group adds `workspaceID`).

### 4.2 `SingleServiceExport`

| Field | Type | Optional | JSON key |
|-------|------|----------|----------|
| version | int | no | `version` |
| exportedAt | date | no | `exportedAt` |
| service | ExportService | no | `service` |
| providers | [ExportProvider] | no | `providers` |
| portMappings | [ExportPortMapping] | no | `portMappings` |
| kubeConfigs | [ExportKubeConfig] | yes (decode default `[]`) | `kubeConfigs` |

No `workspaces` key — detection distinguishes from full backup.

### 4.3 `ExportService`

| Field | Type | Optional | Default on decode | JSON key |
|-------|------|----------|-------------------|----------|
| id | UUID | no | new UUID in init only | `id` |
| name | string | no | — | `name` |
| icon | string | yes | null | `icon` |
| colorHex | string | yes | null | `colorHex` |
| description | string | yes | null | `description` |
| activeProviderID | UUID | yes | null | `activeProviderID` |
| workspaceID | UUID | yes | null | `workspaceID` |
| groupIDs | [UUID] | yes | null | `groupIDs` |
| isDisabled | bool | yes | false in init | `isDisabled` |
| isStarred | bool | yes | false in init | `isStarred` |

### 4.4 `ExportProvider`

| Field | Type | Optional | JSON key |
|-------|------|----------|----------|
| id | UUID | no | `id` |
| serviceID | UUID | no | `serviceID` |
| type | string | no | `type` (provider category raw or legacy alias) |
| label | string | yes | `label` |
| kubeConfigID | UUID | yes | `kubeConfigID` |
| customKubeConfigPath | string | yes | `customKubeConfigPath` |
| kubeContext | string | yes | `kubeContext` |
| kubeNamespace | string | yes | `kubeNamespace` |
| targetName | string | yes | `targetName` |
| kubeTargetType | string | yes | `kubeTargetType` |
| usePattern | bool | yes | `usePattern` |
| yamlConfig | string | yes | `yamlConfig` |
| composeFilePath | string | yes | `composeFilePath` |
| initialScript | string | yes | `initialScript` |
| initialScriptPath | string | yes | `initialScriptPath` |
| runCommand | string | yes | `runCommand` |
| workingDirectory | string | yes | `workingDirectory` |
| sshHost | string | yes | `sshHost` |
| sshUser | string | yes | `sshUser` |
| sshPort | int | yes | `sshPort` |
| sshKeyPath | string | yes | `sshKeyPath` |
| sshPassword | string | yes | `sshPassword` (vault ciphertext or legacy) |
| httpCheckUrl | string | yes | `httpCheckUrl` |
| httpCheckInterval | int | yes | `httpCheckInterval` |
| tunnelType | string | yes | `tunnelType` |
| tunnelTargetUrl | string | yes | `tunnelTargetUrl` |
| ngrokAuthToken | string | yes | `ngrokAuthToken` (vault ciphertext or legacy) |
| monitorProcessName | string | yes | `monitorProcessName` |
| monitorInterval | int | yes | `monitorInterval` |
| autoReconnect | bool | yes | `autoReconnect` |

### 4.5 `ExportPortMapping`

| Field | Type | Optional | JSON key | Notes |
|-------|------|----------|----------|-------|
| id | UUID | no | `id` | |
| providerID | UUID | no | `providerID` | May reference service id in legacy backups |
| localPort | int | no | `localPort` | |
| remotePort | int | no | `remotePort` | |
| protocolType | — | — | *(absent)* | Import always writes `TCP` |

### 4.6 `ExportKubeConfig`

| Field | Type | Optional | JSON key | SQLite mapping |
|-------|------|----------|----------|----------------|
| id | UUID | no | `id` | `kube_config.id` |
| name | string | yes | `name` | `name` |
| path | string | yes | `path` | `sourceFilePath` |
| encryptedConfigContent | string | yes | `encryptedConfigContent` | `configContent` |
| createdAt | date | yes | `createdAt` | `createdAt` |
| updatedAt | date | yes | `updatedAt` | `updatedAt` |

Example without inline cipher: `docs/samples/Kuma-Screenshot-Demo.json` (`path` only).

### 4.7 Preview DTO (`ImportPreviewRow` — wire shape for ADD-100)

| Field | Type | Description |
|-------|------|-------------|
| serviceId | UUID | Backup service id |
| serviceName | string | Original name |
| suggestedName | string | After conflict rename |
| hasConflict | bool | |
| workspaceId | UUID | Resolved workspace for row |
| workspaceName | string | |
| isExistingWorkspace | bool | Full import only |
| providerCategory | string | Raw category |
| target | string | `resolvedTarget` |
| portMappings | [{localPort, remotePort}] | No secrets |

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-DPT-01 | [PARITY] | Backup format version constant `1` | `DataPortService.swift:7` | `data.export`, `data.import` |
| FEAT-DPT-02 | [PARITY] | `KumaBackup` unified payload | `BackupModels.swift:6-38` | `data.export`, `data.import`, `data.import_preview` |
| FEAT-DPT-03 | [PARITY] | `SingleServiceExport` clipboard format | `BackupModels.swift:78-114` | `data.export_service_json`, `data.import_preview`, `data.import` |
| FEAT-DPT-04 | [PARITY] | JSON encode/decode full backup | `ImportExport.swift:62-78` | `data.export`, `data.import` |
| FEAT-DPT-05 | [PARITY] | JSON encode/decode single service | `ImportExport.swift:81-91` | `data.export_service_json` |
| FEAT-DPT-06 | [PARITY] | Polymorphic `parseAnyBackup` | `ImportExport.swift:48-57` | `data.import_preview`, `data.import` |
| FEAT-DPT-07 | [PARITY] | `wrapSingleService` with optional workspace override | `ImportExport.swift:18-45` | `data.import_preview`, `data.import` |
| FEAT-DPT-08 | [PARITY] | Backup filename date suffix `yyyy-MM-dd` | `ImportExport.swift:95-98` | `data.export` |
| FEAT-DPT-09 | [PARITY] | Reject future backup version | `DataPortService.swift:9-16` | `data.import_preview`, `data.import` |
| FEAT-DPT-10 | [PARITY] | Export all data | `+Export.swift:57-135` | `data.export` |
| FEAT-DPT-11 | [PARITY] | Export one workspace | `+Export.swift:139-234` | `data.export` |
| FEAT-DPT-12 | [PARITY] | Export one service as `KumaBackup` slice | `+Export.swift:6-52` | `data.export` |
| FEAT-DPT-13 | [PARITY] | Export single service JSON string (Copy Config) | `+Export.swift:265-314`, deck actions | `data.export_service_json` |
| FEAT-DPT-14 | [PARITY] | Embed workspace avatars as base64 map | `+Export.swift:113-120` | `data.export` |
| FEAT-DPT-15 | [PARITY] | Export referenced kubeconfigs only | `Mapping.swift:5-7`, `+Export.swift:239-262` | `data.export`, `data.export_service_json` |
| FEAT-DPT-16 | [PARITY] | Port `providerID` normalization on export | `+Export.swift:91-107` | `data.export` |
| FEAT-DPT-17 | [PARITY] | Full import upsert transaction | `+Import.swift:6-105` | `data.import` |
| FEAT-DPT-18 | [PARITY] | Selective import filter | `+Import.swift:109-141` | `data.import` |
| FEAT-DPT-19 | [PARITY] | Re-ID import into workspace | `+Import.swift:144-257` | `data.import` |
| FEAT-DPT-20 | [PARITY] | Strategy router `importData` | `DataPortRepository.swift:37-44` | `data.import` |
| FEAT-DPT-21 | [PARITY] | Encrypt provider secrets on export | `Mapping.swift:42-55` | `data.export`, `data.export_service_json` |
| FEAT-DPT-22 | [PARITY] | Decrypt/fallback/re-encrypt on import | `Mapping.swift:91-137` | `data.import` |
| FEAT-DPT-23 | [PARITY] | Kubeconfig upsert on import | `Mapping.swift:9-39` | `data.import` |
| FEAT-DPT-24 | [PARITY] | Port mapping service resolution + TCP protocol | `+Import.swift:70-101` | `data.import` |
| FEAT-DPT-25 | [CLIENT] | Atomic file write on export | `SettingsDataSection.swift:170`, deck export | - |
| FEAT-DPT-26 | [PARITY] | Factory reset storage wipe sequence | `FactoryReset.swift:8-36` | `data.factory_reset` |
| FEAT-DPT-27 | [PARITY] | Case-insensitive name conflict → ` (Imported)` | `WorkspaceImportPreviewSheet.swift:100-102` | `data.import_preview`, `data.import` |
| FEAT-DPT-28 | [PARITY] | Legacy provider `type` string aliases | `BackupModels.swift:213-224` | `data.import` |
| FEAT-DPT-29 | [PARITY] | Preview target string `resolvedTarget` | `BackupModels.swift:227-300` | `data.import_preview` |
| FEAT-DPT-30 | [V2-ADD] | Server-side import preview rows | UI sheets | `data.import_preview` |
| FEAT-DPT-31 | [CLIENT] | Import preview sheets (master-detail) | `ImportPreviewSheet`, `WorkspaceImportPreviewSheet` | - |
| FEAT-DPT-32 | [CLIENT] | Settings Data section export/import/reset UX | `SettingsDataSection.swift` | `data.export`, `data.import`, `data.factory_reset` |
| FEAT-DPT-33 | [CLIENT] | Deck toolbar workspace export/import | `ServicesDeckView+DataPort.swift` | `data.export`, `data.import` |
| FEAT-DPT-34 | [CLIENT] | Window JSON drop target | `ContentView.swift:31-74` | `data.import_preview`, `data.import` |
| FEAT-DPT-35 | [CLIENT] | Relaunch app after reset | `FactoryReset.swift:40-63` | - |
| FEAT-DPT-36 | [PARITY] | Post-import / post-reset events | implied | `data.import`, `data.factory_reset` |

---

## 6. Error catalog

| Code | Condition | Message (exact when from 1.x) |
|------|-----------|--------------------------------|
| `KUMA_DPT_UNSUPPORTED_VERSION` | `version > BACKUP_CURRENT_VERSION` | `The backup file was created by a newer version of Kuma (Backup v<backup>, App v<current>). Please update Kuma.` |
| `KUMA_DPT_SERVICE_NOT_FOUND` | Export scope `.service` unknown id | `Service <UUID> not found.` |
| `KUMA_DPT_ENCODE_FAILED` | UTF-8 string from single export fails | `Failed to encode service JSON.` |
| `KUMA_DPT_INVALID_JSON` | `parseAnyBackup` final decode failure | Propagate JSONDecoder localized description (Swift parity) |
| `KUMA_DPT_IMPORT_FAILED` | SQLite constraint / IO inside import transaction | `Failed to import backup: <detail>` (Settings alert pattern, `SettingsDataSection.swift:219`) |
| `KUMA_DPT_EXPORT_FAILED` | Vault encrypt failure during export | Map from [02](02-security-and-secrets.md) `KUMA_SEC_*` |
| `KUMA_DPT_WIPE_FAILED` | `wipeAndResetDatabase` failure | `Failed to reset database: <detail>` ([01](01-data-model.md) `KUMA_DAT_WIPE_FAILED`) |
| `KUMA_DPT_WORKSPACE_NOT_FOUND` | `reassignIDs` target workspace missing | `Workspace not found: <id>` (reuse `KUMA_WS_NOT_FOUND` or alias) |

---

## 7. Deviations

| ID | Summary |
|----|---------|
| DEV-01 (pre-assigned) | `importIntoWorkspace` remaps `activeProviderID` through `providerIDMap` after the map is populated (1.x always imported `nil`). §3.9 step 3. |
| DEV-04 (pre-assigned) | All import paths use `parseAnyBackup` (Settings import accepts single-service JSON). §3.3. |
| DEV-05 (pre-assigned) | Selective import group filter: nil `workspaceID` groups no longer always pass; `reassignIDs` path respects selected service ids only. §3.8, DEV-105. |
| DEV-101 | Factory reset clears `daemon-state.sqlite` settings KV instead of macOS UserDefaults (`DEV-11`). §3.13 step 2. |
| DEV-102 | Factory reset stops services with full escalation ([06](06-execution-engine.md)) instead of SIGTERM-only `terminateAll`. §3.13 step 1. |
| DEV-105 | `importSelective` group filter restricted to selected workspaces; `importData(reassignIDs)` does not import unselected services when the client passes a subset (deck/workspace UI). §3.6, §3.8. |
| ADD-100 | `data.import_preview` returns structured preview rows (ADD in spec 09 range). §3.11. |
| ADD-101 | Factory reset purges runtime process registry, activity logs, and emits `data.reset`. §3.13. |
| ADD-102 | `data.export` returns `suggestedFileName` using §3.1 patterns. §3.12. |

---

## 8. Invariants

| ID | Statement |
|----|-----------|
| INV-D-DPT-01 | Every import/export mutation uses the in-memory `KumaBackup` representation (single-service wrapped before import). |
| INV-D-DPT-02 | `importAll` persists workspaces, groups, services, providers, memberships, ports, and kubeconfigs in one SQLite write transaction. |
| INV-D-DPT-03 | Failed import transactions leave the database unchanged (TC-C08). |
| INV-D-DPT-04 | Export with scope `.workspace(W)` never includes services whose `workspaceID != W`. |
| INV-D-DPT-05 | Export with scope `.service(S)` never includes other services' rows. |
| INV-D-DPT-06 | Default kubeconfig id is never inserted from backup. |
| INV-D-DPT-07 | Imported port rows always have `protocolType = TCP` in SQLite. |
| INV-D-DPT-08 | After factory reset, exactly one workspace exists and `master.key` / `kubeconfigs/` remain on disk. |
| INV-D-DPT-09 | Preview and RPC list responses never contain cleartext or ciphertext secrets. |
| INV-D-DPT-10 | `version` in emitted exports equals `BACKUP_CURRENT_VERSION`. |

---

## 9. Acceptance tests

Mapped from `docs/testing/05-data-port-test-matrix.md` and `KumaTests/Features/DataPort/*`.

| ID | Arrange | Assert |
|----|---------|--------|
| DT-DPT-01 | Default `KumaBackup()` | `version==1`, empty arrays, nil optionals, valid `exportedAt` (TC-A01) |
| DT-DPT-02 | Backup with fixed `exportedAt`, 2 workspaces | `id == "1_<epoch>_2"` (TC-A02) |
| DT-DPT-03 | `backupDateString` | Matches `^\d{4}-\d{2}-\d{2}$` (TC-A03) |
| DT-DPT-04 | `wrapSingleService` with target WS | One service, providers/ports preserved, `workspaceID` set (TC-A04) |
| DT-DPT-05 | Each legacy `type` string in TC-A06 | Maps to expected category; unknown → docker |
| DT-DPT-06 | Decode `docs/samples/Kuma-Screenshot-Demo.json` | `version==1`, 1 ws, 8 services, 8 provider types (TC-A07) |
| DT-DPT-07 | Backup `version:999` | `KUMA_DPT_UNSUPPORTED_VERSION` (TC-B01) |
| DT-DPT-08 | `parseAnyBackup` on full and single JSON | Full unchanged; single wrapped (TC-B02, B03) |
| DT-DPT-09 | Non-JSON bytes | Throws decode error, no crash (TC-B04) |
| DT-DPT-10 | Import with name collision in target WS | `suggestedName` ends with ` (Imported)` case-insensitive (TC-B05, B06) |
| DT-DPT-11 | Seed full graph; `data.export` all | All entities and relations present (TC-C01) |
| DT-DPT-12 | Two workspaces; export one | No leakage (TC-C02) |
| DT-DPT-13 | Export single service id | Exactly one service (TC-C03) |
| DT-DPT-14 | Import full backup into empty DB | All tables populated (TC-C04) |
| DT-DPT-15 | `reassignIDs` import | New service/provider ids; active provider remapped (TC-C05, DEV-01) |
| DT-DPT-16 | Selective import subset | Only chosen ws/services (TC-C06) |
| DT-DPT-17 | Export bytes round-trip | Atomic write semantics optional; decode equals (TC-C07) |
| DT-DPT-18 | Inject failure mid-import | Full rollback (TC-C08) |
| DT-DPT-19 | Compare export via all entry points | Provider/port payloads match (TC-C09) |
| DT-DPT-20 | Copy Config JSON → import workspace | Same rows as full restore (TC-C10, E06) |
| DT-DPT-21 | Running service; factory reset | All processes stopped (TC-D01, DEV-102) |
| DT-DPT-22 | Factory reset after seed | One default workspace; user data gone (TC-D02) |
| DT-DPT-23 | Custom settings; factory reset | Settings KV defaults restored (TC-D03, DEV-101) |
| DT-DPT-24 | Avatar on disk; factory reset | Images dir empty (TC-D04) |
| DT-DPT-25 | Five parallel `data.export` all | All succeed, identical JSON (TC-D05) |
| DT-DPT-26 | Export missing service id | `KUMA_DPT_SERVICE_NOT_FOUND` (TC-E01) |
| DT-DPT-27 | Import backup with nil `groups`/images | Succeeds (TC-E02) |
| DT-DPT-28 | Service without providers | Row saved, `activeProviderID` null (TC-E03) |
| DT-DPT-29 | Port maps to provider id | One port row linked (TC-E04) |
| DT-DPT-30 | Docker yaml `image: docker.io/library/redis:alpine` | Preview target `redis:alpine` (TC-E05) |
| DT-DPT-31 | Kubeconfig ciphertext in backup JSON | Round-trip field `encryptedConfigContent` (TC-B07) |
| DT-DPT-32 | Kubeconfig path-only entry | Round-trip `path` (TC-B07b) |

---

## Proposed RPC additions

None. Methods are registered in [00 §5.6](00-overview-and-conventions.md). [10](10-rpc-protocol.md) should define param/result schemas for `data.import_preview` rows (§4.7) and `data.import` selection fields.

---

## Open questions / residual risks

1. **Settings in backups.** 1.x JSON never includes UserDefaults; daemon reset clears KV ([03](03-settings-and-environment.md)). Import does not restore tool paths unless a future schema adds them.
2. **Group import with reassignIDs.** Copying `backup.groups` verbatim can create groups tied to other workspace ids while services land in target workspace — parity with 1.x; clients may omit groups from scoped exports.
3. **ISO8601 fractional seconds.** Swift backup files often omit milliseconds; RPC wire uses ms for entity timestamps ([01 §3.4.5](01-data-model.md)) — only `exportedAt` in backup JSON uses ISO8601 without ms requirement.
4. **`importAll` merge.** Re-importing the same UUID overwrites rows but never deletes removed entities from a partial backup; clients must factory-reset or delete manually for a true replace.
5. **Image import failure.** If base64 decode fails, 1.x skips image silently (`saveBase64Image` nil); workspace imports without avatar — document same behavior.
