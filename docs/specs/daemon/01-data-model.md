# Daemon Spec 01: Data Model and Persistence

> **Area code:** `DAT` · **Status:** Draft for implementation · **Baseline:** Kuma 1.x (Swift) `kuma.sqlite` schema v1..v8 (GRDB)
> **Depends on:** [00 Overview and Conventions](00-overview-and-conventions.md) · **Consumed by:** [02](02-security-and-secrets.md), [03](03-settings-and-environment.md), [04](04-workspaces-groups-services.md), [05](05-providers-and-validation.md), [06](06-execution-engine.md), [07](07-kubernetes.md), [08](08-logs-and-events.md), [09](09-dataport.md), [10](10-rpc-protocol.md), [14](14-lifecycle-and-platform.md)

---

## 1. Purpose and scope

This spec is the contract for **what is stored, in which file, in which exact bytes**, and which pure data rules (active provider, port visibility, cascade, ordering) the Rust daemon applies on top of it. It covers:

1. Every domain entity and read model, with field tables (type, optional, default, SQLite column, JSON key) and an explicit list of fields that are **not** persisted.
2. Every enum with exact raw values, legacy aliases and decode fallbacks.
3. The final SQLite DDL of 1.x `kuma.sqlite` after migrations `v1..v8`, the exact effect of each migration, GRDB bookkeeping (`grdb_migrations`), pragmas, file paths, wipe/reset semantics.
4. The exact storage format of UUIDs, dates and booleans as written by GRDB records in 1.x, and the format the daemon MUST read and write.
5. The daemon-owned `daemon-state.sqlite` DDL (`settings`, `runtime_process`, `meta`), authoritative for all other specs.
6. Deterministic ID helpers (`UUID.stable`, provider stable IDs, sidebar node IDs).
7. The JSON wire shapes (camelCase) that [10](10-rpc-protocol.md) reuses, and the `expectedUpdatedAt` concurrency token.

Out of scope (owned elsewhere): encryption algorithm details and secret redaction on the wire ([02](02-security-and-secrets.md)); validation rules for provider configuration ([05](05-providers-and-validation.md)); settings key semantics ([03](03-settings-and-environment.md)); CRUD orchestration ([04](04-workspaces-groups-services.md)); backup JSON ([09](09-dataport.md)).

**Global compatibility rule (GR-02):** the daemon MUST be able to open a 1.x `kuma.sqlite` in place, and a database first created by the daemon MUST be openable by 1.x (same `grdb_migrations` identifiers, byte-identical schema). The daemon MUST NOT add migrations, tables, columns, indexes or triggers to `kuma.sqlite`.

---

## 2. 1.x source of truth (paths read)

| Path | Used for |
|------|----------|
| `Kuma/Domain/Models/Workspace.swift`, `ServiceGroup.swift`, `Service.swift`, `Provider.swift`, `Provider+KubernetesDefaults.swift`, `ServicePortMapping.swift`, `KubeConfig.swift`, `ServiceDeckItem.swift`, `ServiceRuntimeState.swift`, `SystemDependency.swift`, `KumaSettingsKey.swift` | Entities, read models, setting key names |
| `Kuma/Domain/Enums/ProviderCategory.swift`, `ServiceEnums.swift`, `ServiceExecutionState.swift`, `KubeTargetType.swift` | Enums |
| `Kuma/Core/Database/AppDatabase.swift` | Paths, pragmas, migrations v1..v8, seed, `wipeAndResetDatabase`, DEBUG erase flag |
| `Kuma/Core/Database/Records/{Workspace,ServiceGroup,ServiceGroupMembershipRecord,Service,Provider,ServicePortMapping,KubeConfig}+Record.swift` | Column mapping, UUID/date/bool encoding, decode fallbacks |
| `Kuma/Core/Database/Repositories/{ServiceRepository,ServiceRepository+CRUD,ServiceRepository+DeckItems,WorkspaceRepository,ServiceGroupRepository,KubeConfigRepository,DataPortRepository+Mapping}.swift` | Ordering, active-provider and port-visibility rules, write semantics, upserts |
| `Kuma/Lib/Extensions/UUID+Stable.swift`, `Kuma/Lib/URLNormalizer.swift` (field context only: `httpCheckUrl`, `tunnelTargetUrl`) | Stable IDs |
| `Kuma/Core/Storage/WorkspaceImageStore.swift` | Image directory and file naming only |
| `Kuma/Core/Security/{CryptoVault,CredentialProtector}.swift`, `Kuma/Core/Kubernetes/{KubeConfigMaterializer,KubeConfigExecutionResolver}.swift`, `Kuma/Presentation/Features/Services/ViewModels/KubeConfigViewModel.swift` | Which columns hold ciphertext; default kubeconfig; materialized files |
| `Kuma/Core/DataPort/DataPortService+FactoryReset.swift`, `DataPortService+BackupModels.swift` (legacy type aliases) | Wipe orchestration; provider type aliases |
| `Kuma/Presentation/Features/Services/Views/Forms/HealthCheck/HealthCheckSettingsView.swift`, `.../Tunnel/TunnelSettingsView.swift`, `Kuma/Presentation/Features/Settings/ViewModels/SettingsViewModel.swift`, `Kuma/App/AppDelegate.swift` | `HealthCheckIntervalOption`, `TunnelEngineOption`, `PortConflictPolicy`, `QuitBehavior` |
| `Kuma/Stores/WorkspaceStore.swift`, `Kuma/Presentation/Features/Sidebar/ViewModels/SidebarViewModel+Groups.swift` | Sort-order, default-name constants |
| `Kuma/Core/Lifecycle/SingleInstanceGuard.swift` | Bundle id used for 1.x single-instance detection |
| `docs/specs/03-workspace.md`, `docs/specs/04-sidebar.md`, `docs/testing/*` | Invariants |
| `KumaTests/Harness/ServicesTestHarness.swift`, `KumaTests/Features/{Services,Workspace,Sidebar}/*Persistence*.swift`, `ServicesInitialStateTests.swift` | Harness schema (a **subset**, see 3.5.3) and implicit invariants |
| GRDB checkout `0d8cf958b4b66a0473ec6e6986eb9da462171da9` (`Kuma.xcodeproj/.../Package.resolved`): `GRDB/Core/Support/Foundation/{Date,DatabaseDateComponents,SQLiteDateParser}.swift`, `GRDB/Core/Support/StandardLibrary/StandardLibrary.swift`, `GRDB/Migration/{DatabaseMigrator,Migration}.swift` | Exact date/bool encoding, migrator semantics |
| A real 1.x database (`~/Library/Application Support/Kuma/kuma.sqlite`, copied and inspected with `sqlite3 .schema`, `typeof()`; no user rows quoted) | Ground truth for the final DDL, `grdb_migrations` content, journal mode, `DATETIME` text sample |

---

## 3. Normative behavior

### 3.1 Files and paths

Data dir default: `~/Library/Application Support/Kuma` (1.x: `applicationSupportDirectory` + `Kuma`, `Kuma/Core/Database/AppDatabase.swift:16-23`). Override: env `KUMA_DATA_DIR` (replaces the whole `.../Kuma` directory). The directory is created (`create_dir_all`) if absent.

| Item | Path (relative to data dir) | Owner | 1.x source | Notes |
|------|------------------------------|-------|------------|-------|
| Main database | `kuma.sqlite` (+ `kuma.sqlite-wal`, `kuma.sqlite-shm`) | shared with 1.x | `AppDatabase.swift:26` | WAL mode. Never deleted by the daemon except via factory-reset rules in [09](09-dataport.md). |
| Daemon database | `daemon-state.sqlite` (+ `-wal`, `-shm`) | daemon only | brief | Section 3.10. |
| Master key | `master.key` | [02](02-security-and-secrets.md) | `CryptoVault.swift:41-83` | Exactly 32 raw bytes, file mode `0600`; data dir mode `0700` when created by 1.x. |
| Materialized kubeconfigs | `kubeconfigs/<UPPERCASE-UUID>.yaml` | [07](07-kubernetes.md) | `KubeConfigMaterializer.swift:64-79` | Dir mode `0700`, files `0600`. Not touched by `wipeAndResetDatabase`. |
| Workspace avatars | `Workspaces/Images/<UPPERCASE-WORKSPACE-UUID>.png` | [04](04-workspaces-groups-services.md) | `WorkspaceImageStore.swift:27-45,53-54` | `workspace.imagePath` stores either the bare file name `<UUID>.png` or (legacy) an absolute path (`resolveURL`: a value starting with `/` is used as-is, otherwise joined to the images dir, `WorkspaceImageStore.swift:182-187`). |
| Runtime dir | `$KUMA_RUNTIME_DIR` or `run/` | [14](14-lifecycle-and-platform.md) | brief | Socket, pid, lock, spool. Not part of the data model. |

Other files that 1.x may leave in the data dir (for example `debug-*.log`) are ignored.

The 1.x process falls back to the temp directory only for the *images* dir on failure (`WorkspaceImageStore.swift:43-45`); the database path has no fallback (a failure is a `fatalError`, `AppDatabase.swift:39`). The daemon MUST NOT fall back: failure to open the DB is `KUMA_DAT_DB_OPEN_FAILED`.

### 3.2 Opening an existing or new database (algorithm)

Input: `<data dir>/kuma.sqlite`. Steps, in order:

1. **Ensure directory.** Create the data dir (and `Workspaces/Images` lazily, not at DB open).
2. **Open** with SQLite in WAL mode (3.3). If the file exists but is not a SQLite database or cannot be opened: `KUMA_DAT_DB_OPEN_FAILED`; the daemon MUST NOT delete, truncate or recreate the file.
3. **Coexistence probe** (3.12): non-fatal, logs a warning when a 1.x instance is running.
4. **Read bookkeeping.** `SELECT identifier FROM grdb_migrations` if the table exists (GRDB `appliedIdentifiers`, `DatabaseMigrator.swift:508-519`); otherwise the empty set. The known list is, in registration order:
   `v1_production_schema`, `v2_service_groups`, `v3_service_group_memberships`, `v4_provider_custom_kubeconfig`, `v5_port_mapping_provider`, `v6_provider_compose_and_script_paths`, `v7_kube_config_source_path`, `v8_provider_auto_reconnect`.
5. **Refuse unknown newer schema.** If the applied set contains any identifier **not** in the known list (GRDB `hasBeenSuperseded`): fail with `KUMA_DAT_SCHEMA_TOO_NEW`, perform **no write** of any kind, and do not start the RPC server (exit per [14](14-lifecycle-and-platform.md)). (1.x release builds would silently continue; see ADD-21.)
6. **Backup before first write** (ADD-20): if any known migration is pending and the DB file already contained user tables (applied set non-empty), copy the database to `kuma.sqlite.pre-migrate-<unix seconds>.bak` using the SQLite online backup API (or `VACUUM INTO`), never a raw file copy while WAL is active. Failure: `KUMA_DAT_BACKUP_FAILED` and abort. In addition the daemon SHOULD create `kuma.sqlite.pre-daemon.bak` once, if absent, before its very first write to a DB that was created by 1.x (i.e. whose `workspace` rows exist and `daemon-state.sqlite` has no `meta.instanceId` yet).
7. **Migrate.** Run every known migration whose identifier is **not** in the applied set, in registration order, each as in 3.6. (GRDB selects by set membership, not by prefix, `DatabaseMigrator.swift:569-590`; the daemon MUST do the same.) Create `grdb_migrations` first with exactly `CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)` (`DatabaseMigrator.swift:616`) so that on a fresh file it is the first `sqlite_master` entry.
8. **Never-zero workspaces** (3.8): if `SELECT COUNT(*) FROM workspace` is 0, insert the default workspace.
9. Ready. The writer connection is single and serialized; readers may be pooled.

A fresh daemon-created database is simply steps 4 to 8 with an empty file: it ends with exactly the eight identifiers in `grdb_migrations`, the final schema of 3.5 (byte-identical `sql`, same object order), and one seeded workspace.

### 3.3 Connection settings (pragmas)

| Pragma | Value | Source | Rule |
|--------|-------|--------|------|
| `journal_mode` | `WAL` | `config.journalMode = .wal` (`AppDatabase.swift:29`); real DB reports `wal` | MUST set on open. Persistent in the file. |
| `foreign_keys` | `ON` on **every** connection | `config.prepareDatabase { PRAGMA foreign_keys = ON }` (`AppDatabase.swift:31-33`) | MUST. Cascade behavior (3.11.5) depends on it. |
| `synchronous` | not set by 1.x (SQLite default) | - | Daemon SHOULD leave the default (`FULL`). |
| `busy_timeout` | 1.x: not set (GRDB default is immediate `SQLITE_BUSY`) | - | Daemon MUST set `5000` ms (`DB_BUSY_TIMEOUT_MS`, ADD-22) because a 1.x app may be writing concurrently. |
| `user_version`, `application_id` | `0`, `0` in a real 1.x DB | observed | MUST NOT be changed. |
| `page_size` / `encoding` | `4096` / `UTF-8` in a real 1.x DB | observed | A fresh daemon DB SHOULD use the SQLite defaults (same values). |
| `wal_checkpoint` | not used by 1.x | - | On graceful shutdown the daemon SHOULD run `PRAGMA wal_checkpoint(TRUNCATE)`. |

Each migration runs with `PRAGMA foreign_keys = OFF`, inside `BEGIN IMMEDIATE`, followed by `PRAGMA foreign_key_check` (any violation rolls back and fails, GRDB "deferred" mode, `Migration.swift:79-109`), then `PRAGMA foreign_keys = ON`. The identifier row is inserted in the same transaction as the migration body (`Migration.swift:111-114`). If `foreign_keys` is already off for the connection GRDB runs the body in a plain immediate transaction; the daemon MUST always use the disable/check/enable sequence.

### 3.4 Storage formats (exact)

All values below were verified in the GRDB sources at the pinned revision and against a real 1.x database file.

#### 3.4.1 UUID columns

- Every UUID column (`id`, `serviceID`, `workspaceID`, `groupID`, `providerID`, `activeProviderID`, `kubeConfigID`) has declared type `TEXT`.
- **Write:** `UUID.uuidString`, i.e. **36 characters, UPPERCASE hex, hyphenated 8-4-4-4-12** (example from a real DB: `F874297A-4994-4BF7-A7B4-041D80989622`). Every record's `encode` uses `id.uuidString` (`Workspace+Record.swift:29-34`, etc.). The daemon MUST write exactly this form. The fixed default kubeconfig ID is `00000000-0000-0000-0000-000000000001`.
- **Lookup:** 1.x queries by exact string equality with the uppercase form (`fetchOne(db, key: id.uuidString)`, `Column("serviceID") == id.uuidString`). The daemon MUST normalize every UUID received on any API to uppercase before comparing or storing. Input on the wire accepts any case (lower, upper, mixed); output is always uppercase.
- **Accepted syntax:** Foundation `UUID(uuidString:)` accepts only the 36-char hyphenated hex form (case-insensitive). The daemon accepts the same and rejects braces, no-hyphen and other forms with `KUMA_DAT_INVALID_UUID`.
- **Read fallbacks in 1.x (and daemon behavior):**

| Column kind | 1.x behavior when the text is not a valid UUID | Daemon behavior |
|-------------|-----------------------------------------------|-----------------|
| Required primary key `id` (workspace, service, provider, group, portMapping, kube_config) | `UUID(uuidString:) ?? UUID()`: a **fresh random UUID per read** (row becomes unaddressable) | **DEV-20:** the row is skipped in every list/query result and a warning is logged once per row id text. No random IDs are ever generated for reads. |
| Required FK `serviceID` of provider and of membership, `groupID` of membership | same random fallback | DEV-20: row skipped. |
| Optional UUID (`service.workspaceID`, `service.activeProviderID`, `provider.kubeConfigID`, `portMapping.serviceID`, `portMapping.providerID`, `service_group.workspaceID`) | `flatMap(UUID.init)` gives `nil` | Same: `null`. |

(Note `service.workspaceID` is `NOT NULL` in the DB but optional in the Swift model; a non-UUID text decodes to `nil` in 1.x. In the daemon such a service is returned with `workspaceID: null` and does not appear in any workspace deck.)

#### 3.4.2 `DATETIME` columns (`createdAt`, `updatedAt`)

- Declared type `DATETIME` (NUMERIC affinity), values stored as **TEXT**. Real DB sample: `typeof(createdAt) = text`, value `2026-11-01 23:36:30.921`.
- **Write (GRDB `Date.databaseValue`, `Date.swift:55-59,160-166`):** `DateFormatter` with `dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"`, `locale = en_US_POSIX`, `timeZone = UTC (secondsFromGMT 0)`. Result: `YYYY-MM-DD HH:MM:SS.mmm`, **space separator, exactly 3 fractional digits, no timezone suffix, UTC.** The daemon MUST write exactly this form (sub-millisecond precision is truncated; do not round up across a second boundary).
- **Read (`Date.fromDatabaseValue` → `SQLiteDateParser`, `SQLiteDateParser.swift`):** the daemon MUST accept all of:
  - `YYYY-MM-DD` (midnight UTC);
  - `YYYY-MM-DD HH:MM`, `YYYY-MM-DD HH:MM:SS`, `YYYY-MM-DD HH:MM:SS.S`, `.SS`, `.SSS` (more than 3 fractional digits: extra digits ignored/truncated);
  - the same with `T` instead of the space;
  - an optional timezone suffix after the time: `Z`, `+HH:MM`, `-HH:MM` (offset is applied; result is a UTC instant);
  - a numeric (INTEGER/REAL) storage class: Unix seconds since 1970-01-01T00:00:00Z (fractional allowed).
  - Time-only strings (`HH:MM[:SS[.SSS]]`) are **not** dates (1.x: decode failure).
- Migration `v3` writes `datetime('now')` (format `YYYY-MM-DD HH:MM:SS`, UTC, no milliseconds) into `service_group_membership.createdAt`; such values exist in real DBs and MUST parse.
- **Unparsable value (DEV-21):** 1.x traps (non-optional `Date` conversion failure is a fatal error in GRDB `Row` subscripts). The daemon MUST NOT crash: it substitutes `1970-01-01T00:00:00.000Z`, logs a warning with table and row id, and continues. Rewriting the row writes a valid value.
- All timestamps inside one daemon operation use a single `now` captured at operation start (millisecond truncation).

#### 3.4.3 Boolean columns

- Declared `BOOLEAN` (NUMERIC affinity). **Write:** integer `1` / `0` (GRDB `Bool.databaseValue`, `StandardLibrary.swift`). `service.isDisabled`, `service.isStarred`, `provider.autoReconnect` are `NOT NULL DEFAULT 0`; `provider.usePattern` is nullable (`NULL` = unset).
- **Read:** an integer or real is `true` iff non-zero; `NULL` is "absent" (`nil` for optional fields). `service.isStarred` additionally defaults to `false` when `NULL` (`Service+Record.swift:21`).
- `provider.autoReconnect` is **always written non-null** (`autoReconnect ?? false`, `Provider+Record.swift:148`), although the Swift property is `Bool?`. On read `NULL` cannot occur (column is `NOT NULL`).

#### 3.4.4 Integers, text, NULL

- Integer columns (`sortOrder`, `sshPort`, `httpCheckInterval`, `monitorInterval`, `localPort`, `remotePort`) are SQLite `INTEGER`. A required integer that is not an INTEGER (or an integral REAL) is a decode failure: 1.x traps; daemon returns `KUMA_DAT_ROW_DECODE` for the request and logs the row (DEV-21). Optional integer columns decode a non-integer to `null`.
- Text is UTF-8, stored verbatim (no trimming, no normalization) except where a rule below says otherwise. Empty string and `NULL` are distinct in storage; many consumers treat them equivalently (see 3.14).
- Optional Swift properties are written as SQL `NULL` when `nil`; the daemon MUST write `NULL`, never an empty string, for an absent optional value.

#### 3.4.5 Wire formats (reused by [10](10-rpc-protocol.md))

| Kind | Wire format | Input tolerance |
|------|-------------|-----------------|
| UUID | uppercase canonical string | any case |
| Timestamp | ISO-8601 UTC with exactly three fractional digits and `Z`: `YYYY-MM-DDTHH:MM:SS.sssZ` (e.g. `2026-11-01T23:36:30.921Z`) | `YYYY-MM-DDTHH:MM:SS[.f{1,9}]` followed by `Z` or `±HH:MM`; also the SQLite text form of 3.4.2 (treated as UTC) |
| Bool | JSON `true`/`false` | JSON booleans only |
| Absent optional | field omitted **or** `null` on input; on output the field is omitted when `null` for entity objects (matches Swift synthesized `Codable`, which omits `nil` optionals) except where a table marks "always present" |
| Sets (`groupIDs`) | JSON array of uppercase UUID strings, sorted ascending (DEV-23) | any order, duplicates ignored |

1.x backups (`.iso8601` strategy, `DataPortService+ImportExport.swift:64,71`) use `YYYY-MM-DDTHH:MM:SSZ` without milliseconds; [09](09-dataport.md) owns that format. For the RPC wire the millisecond form is used because the `updatedAt` value doubles as the concurrency token (3.13).

### 3.5 Final SQLite schema of `kuma.sqlite` (after v1..v8)

#### 3.5.1 Exact `sqlite_master` content, in creation order

This listing is the output of `sqlite3 kuma.sqlite .schema` on a real 1.x database. Whitespace and quoting are part of the contract (see 3.5.2).

```sql
CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
CREATE TABLE "workspace" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "imagePath" TEXT, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "kube_config" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "configContent" TEXT NOT NULL, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "sourceFilePath" TEXT);
CREATE TABLE "service" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "icon" TEXT, "colorHex" TEXT, "description" TEXT, "activeProviderID" TEXT, "isDisabled" BOOLEAN NOT NULL DEFAULT 0, "isStarred" BOOLEAN NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "groupID" TEXT REFERENCES "service_group"("id") ON DELETE SET NULL);
CREATE TABLE "provider" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "type" TEXT NOT NULL, "label" TEXT, "kubeConfigID" TEXT, "kubeContext" TEXT, "kubeNamespace" TEXT, "targetName" TEXT, "kubeTargetType" TEXT, "usePattern" BOOLEAN, "yamlConfig" TEXT, "initialScript" TEXT, "runCommand" TEXT, "workingDirectory" TEXT, "sshHost" TEXT, "sshUser" TEXT, "sshPort" INTEGER, "sshKeyPath" TEXT, "sshPassword" TEXT, "httpCheckUrl" TEXT, "httpCheckInterval" INTEGER, "tunnelType" TEXT, "tunnelTargetUrl" TEXT, "ngrokAuthToken" TEXT, "monitorProcessName" TEXT, "monitorInterval" INTEGER, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL, "customKubeConfigPath" TEXT, "composeFilePath" TEXT, "initialScriptPath" TEXT, "autoReconnect" BOOLEAN NOT NULL DEFAULT 0);
CREATE TABLE "portMapping" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "localPort" INTEGER NOT NULL, "remotePort" INTEGER NOT NULL, "protocolType" TEXT NOT NULL DEFAULT 'TCP', "providerID" TEXT REFERENCES "provider"("id") ON DELETE CASCADE);
CREATE INDEX "idx_service_workspace" ON "service"("workspaceID", "createdAt");
CREATE INDEX "idx_provider_service" ON "provider"("serviceID");
CREATE INDEX "idx_port_service" ON "portMapping"("serviceID");
CREATE TABLE "service_group" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE INDEX "idx_group_workspace" ON "service_group"("workspaceID", "sortOrder");
CREATE TABLE "service_group_membership" ("serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "groupID" TEXT NOT NULL REFERENCES "service_group"("id") ON DELETE CASCADE, "createdAt" DATETIME NOT NULL, PRIMARY KEY ("serviceID", "groupID"));
CREATE INDEX "idx_membership_group" ON "service_group_membership"("groupID", "serviceID");
CREATE INDEX "idx_port_provider" ON "portMapping"("providerID");
```

Implicit objects `sqlite_autoindex_<table>_1` (one per `TEXT PRIMARY KEY` table and the composite PK of `service_group_membership`, plus `grdb_migrations`) have `sql IS NULL` and are not listed. There are no triggers, views, `AUTOINCREMENT`/`sqlite_sequence`, `CHECK`, `UNIQUE` (other than primary keys) or `COLLATE` clauses.

Observation worth knowing: `provider.createdAt/updatedAt` sit **before** the columns added by v4/v6/v8 (`customKubeConfigPath`, `composeFilePath`, `initialScriptPath`, `autoReconnect`), `kube_config.sourceFilePath` is the last column, `service.groupID` is the last column, `portMapping.providerID` is the last column. Code MUST address columns by name, never by position.

#### 3.5.2 Why byte-identity matters (DEBUG erase caveat)

In **DEBUG builds of 1.x** `migrator.eraseDatabaseOnSchemaChange = true` (`AppDatabase.swift:82-85`). At every launch GRDB (`DatabaseMigrator.hasSchemaChanges`, `DatabaseMigrator.swift:420-482`) does two checks and **erases the whole database** (`Database.erase()`, all data lost) when either is true:

1. `grdb_migrations` contains an identifier that the 1.x binary does not register (for example a hypothetical `v9_...`);
2. the user part of `sqlite_master` (type, name, tbl_name, sql; internal `sqlite_*` and `grdb_*` objects excluded) of the live DB differs from the one produced by a temp DB migrated by the 1.x code up to the same level.

Consequences for the daemon (normative):
- The daemon MUST NOT add, rename or alter any schema object, and MUST NOT register any extra migration identifier in `kuma.sqlite`.
- A fresh daemon DB MUST be produced by replaying the **migration statements of 3.6 in order** (not by executing the final DDL in one shot), because `ALTER TABLE ... ADD COLUMN` rewrites the stored `sql` text and object order must match.
- A 1.x **Release** build never erases (the flag is compiled out) and ignores unknown identifiers; a 1.x **Debug** build pointed at the same data dir is a data-loss hazard for any deviation. This is called out in the coexistence rule (3.12).

#### 3.5.3 Test harness schema is a subset

`KumaTests/Harness/ServicesTestHarness.swift:23-156` re-registers v1..v8 but (a) omits the three v1 indexes, `idx_group_workspace`, `idx_membership_group`, `idx_port_provider`, (b) omits the v3 `INSERT OR IGNORE` data migration and the v5 backfill, (c) seeds a workspace named `Default Workspace` manually instead of the v1 seed. `AppDatabase.swift` is authoritative; the harness MUST NOT be used as a schema reference.

### 3.6 Migrations (name and exact effect)

Each migration below lists the statements GRDB emits. The daemon MUST execute these statements (text identical to the quoted SQL) per 3.3 (FK off, immediate transaction, `foreign_key_check`, FK on, identifier row inserted last in the same transaction).

#### v1 `v1_production_schema` (`AppDatabase.swift:87-197`)

Creates, in this order: `workspace`, `kube_config`, `service`, `provider`, `portMapping` (DDL exactly as the **v1-time** definitions, i.e. the 3.5.1 statements **without** the later-added columns), then the three indexes, then seeds the starter workspace.

```sql
CREATE TABLE "workspace" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "imagePath" TEXT, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "kube_config" ("id" TEXT PRIMARY KEY, "name" TEXT NOT NULL, "configContent" TEXT NOT NULL, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "service" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "icon" TEXT, "colorHex" TEXT, "description" TEXT, "activeProviderID" TEXT, "isDisabled" BOOLEAN NOT NULL DEFAULT 0, "isStarred" BOOLEAN NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "provider" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "type" TEXT NOT NULL, "label" TEXT, "kubeConfigID" TEXT, "kubeContext" TEXT, "kubeNamespace" TEXT, "targetName" TEXT, "kubeTargetType" TEXT, "usePattern" BOOLEAN, "yamlConfig" TEXT, "initialScript" TEXT, "runCommand" TEXT, "workingDirectory" TEXT, "sshHost" TEXT, "sshUser" TEXT, "sshPort" INTEGER, "sshKeyPath" TEXT, "sshPassword" TEXT, "httpCheckUrl" TEXT, "httpCheckInterval" INTEGER, "tunnelType" TEXT, "tunnelTargetUrl" TEXT, "ngrokAuthToken" TEXT, "monitorProcessName" TEXT, "monitorInterval" INTEGER, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
CREATE TABLE "portMapping" ("id" TEXT PRIMARY KEY, "serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "localPort" INTEGER NOT NULL, "remotePort" INTEGER NOT NULL, "protocolType" TEXT NOT NULL DEFAULT 'TCP');
CREATE INDEX "idx_service_workspace" ON "service"("workspaceID", "createdAt");
CREATE INDEX "idx_provider_service" ON "provider"("serviceID");
CREATE INDEX "idx_port_service" ON "portMapping"("serviceID");
```

Seed (`AppDatabase.swift:181-196`):

```sql
INSERT INTO workspace (id, name, imagePath, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
```

with arguments `[<new random UUID, uppercase>, <default workspace name, 3.8>, NULL, 0, <now, 3.4.2 format>, <now>]`. The seed runs only when v1 itself runs, i.e. on an empty database.

#### v2 `v2_service_groups` (`AppDatabase.swift:199-217`)

```sql
CREATE TABLE "service_group" ("id" TEXT PRIMARY KEY, "workspaceID" TEXT NOT NULL REFERENCES "workspace"("id") ON DELETE CASCADE, "name" TEXT NOT NULL, "sortOrder" INTEGER NOT NULL DEFAULT 0, "createdAt" DATETIME NOT NULL, "updatedAt" DATETIME NOT NULL);
ALTER TABLE "service" ADD COLUMN "groupID" TEXT REFERENCES "service_group"("id") ON DELETE SET NULL;
CREATE INDEX "idx_group_workspace" ON "service_group"("workspaceID", "sortOrder");
```

`service.groupID` is the **legacy single-group column**. After v3 it is dead (3.11.6).

#### v3 `v3_service_group_memberships` (`AppDatabase.swift:219-238`)

```sql
CREATE TABLE "service_group_membership" ("serviceID" TEXT NOT NULL REFERENCES "service"("id") ON DELETE CASCADE, "groupID" TEXT NOT NULL REFERENCES "service_group"("id") ON DELETE CASCADE, "createdAt" DATETIME NOT NULL, PRIMARY KEY ("serviceID", "groupID"));
INSERT OR IGNORE INTO service_group_membership (serviceID, groupID, createdAt)
    SELECT id, groupID, datetime('now')
    FROM service
    WHERE groupID IS NOT NULL AND groupID != '';
CREATE INDEX "idx_membership_group" ON "service_group_membership"("groupID", "serviceID");
```

Data migration: every service with a non-empty legacy `groupID` gets one membership row; `createdAt` = SQLite `datetime('now')` (UTC, `YYYY-MM-DD HH:MM:SS`, no milliseconds). `OR IGNORE` skips duplicates. The legacy `service.groupID` values are **left in place**.

#### v4 `v4_provider_custom_kubeconfig` (`AppDatabase.swift:240-245`)

```sql
ALTER TABLE "provider" ADD COLUMN "customKubeConfigPath" TEXT;
```

#### v5 `v5_port_mapping_provider` (`AppDatabase.swift:247-274`)

```sql
ALTER TABLE "portMapping" ADD COLUMN "providerID" TEXT REFERENCES "provider"("id") ON DELETE CASCADE;
```

then **backfill**: `SELECT id, serviceID FROM portMapping WHERE providerID IS NULL`; for each row execute

```sql
SELECT COALESCE(
    (SELECT activeProviderID FROM service WHERE id = ?),
    (SELECT id FROM provider WHERE serviceID = ? ORDER BY createdAt ASC LIMIT 1)
)
```

with arguments `[serviceID, serviceID]`; if the result is non-NULL: `UPDATE portMapping SET providerID = ? WHERE id = ?` with `[providerID, portMappingID]`. Rows whose service has neither an `activeProviderID` nor any provider stay `providerID IS NULL` ("legacy" mappings, see 3.11.2). Note the backfill can assign an `activeProviderID` that points to a missing provider; the FK is then violated and the migration's `foreign_key_check` would fail; this cannot occur in 1.x data created through the app (active provider is always a real provider), and if it occurs the daemon fails with `KUMA_DAT_MIGRATION_FAILED` leaving the DB untouched (transaction rolled back). Then:

```sql
CREATE INDEX "idx_port_provider" ON "portMapping"("providerID");
```

#### v6 `v6_provider_compose_and_script_paths` (`AppDatabase.swift:276-281`)

```sql
ALTER TABLE "provider" ADD COLUMN "composeFilePath" TEXT;
ALTER TABLE "provider" ADD COLUMN "initialScriptPath" TEXT;
```

#### v7 `v7_kube_config_source_path` (`AppDatabase.swift:283-287`)

```sql
ALTER TABLE "kube_config" ADD COLUMN "sourceFilePath" TEXT;
```

#### v8 `v8_provider_auto_reconnect` (`AppDatabase.swift:289-293`)

```sql
ALTER TABLE "provider" ADD COLUMN "autoReconnect" BOOLEAN NOT NULL DEFAULT 0;
```

#### Migration summary

| # | Identifier | Adds |
|---|------------|------|
| 1 | `v1_production_schema` | `workspace`, `kube_config`, `service`, `provider`, `portMapping`, 3 indexes, default workspace seed |
| 2 | `v2_service_groups` | `service_group`, `service.groupID` (legacy), `idx_group_workspace` |
| 3 | `v3_service_group_memberships` | `service_group_membership`, data migration from `service.groupID`, `idx_membership_group` |
| 4 | `v4_provider_custom_kubeconfig` | `provider.customKubeConfigPath` |
| 5 | `v5_port_mapping_provider` | `portMapping.providerID` (+ backfill), `idx_port_provider` |
| 6 | `v6_provider_compose_and_script_paths` | `provider.composeFilePath`, `provider.initialScriptPath` |
| 7 | `v7_kube_config_source_path` | `kube_config.sourceFilePath` |
| 8 | `v8_provider_auto_reconnect` | `provider.autoReconnect` |

### 3.7 `grdb_migrations` bookkeeping

- Table: `CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)` (no quoting; created by `CREATE TABLE IF NOT EXISTS` before any migration).
- One row per applied identifier; the real DB lists the eight identifiers in registration order (rowid order). The daemon inserts with `INSERT INTO grdb_migrations (identifier) VALUES (?)`.
- A DB the daemon creates MUST end with exactly those eight rows, no more (INV-D-DAT-01), so 1.x (Release and Debug) opens it.
- The daemon MUST NOT use `merged` migrations or delete identifiers.

### 3.8 Seeded default workspace and the never-zero rule

- **Name** (`Workspace.defaultName`, `Workspace.swift:44-50`): take the macOS **full user name** (`NSFullUserName()`); if empty use the login name (`NSUserName()`); take the first whitespace-separated word (`split(separator: " ").first`, fallback `"User"`); uppercase its first character and keep the rest unchanged; append `'s Space`. Examples: `Putra Dwi` → `Putra's Space`; empty full name and login `root` → `Root's Space`. Daemon equivalent: `getpwuid_r(getuid())`: `pw_gecos` up to the first comma if non-empty, else `pw_name`; same word/capitalization rule. If the daemon runs as a different uid than the GUI user, it uses its own uid (documented limitation).
- **Fields:** random UUID, `imagePath` NULL, `sortOrder` 0, `createdAt = updatedAt = now`.
- **When:** (a) by migration v1 on an empty DB (3.6), (b) at DB open if the `workspace` table has zero rows (1.x `WorkspaceStore.loadFromDatabase` does this on app start: `WorkspaceStore.swift:61-68`; the daemon owns it now), (c) at the end of `wipeAndResetDatabase` (3.9).
- **Never zero:** deleting the last remaining workspace is forbidden (`WorkspaceStore.deleteWorkspace` guard `workspaces.count > 1`, `WorkspaceStore.swift:160-163`; `docs/specs/03-workspace.md` invariant 1). The daemon enforces it in the storage layer: `workspace.delete` of the sole workspace fails (error owned by [04](04-workspaces-groups-services.md)).

### 3.9 `wipeAndResetDatabase` semantics (`AppDatabase.swift:62-75`)

In one write transaction:

1. `PRAGMA foreign_keys = OFF` (note: SQLite ignores this pragma inside a transaction, so FKs remain ON; the observable result is identical because parents cascade).
2. List tables: `SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'` and run `DELETE FROM <table>` for each.
3. `PRAGMA foreign_keys = ON`.
4. Insert a **new** default workspace (`Workspace.defaultWorkspace`: a fresh random UUID and current name per 3.8, not the old one).

Effect: all rows of `workspace`, `kube_config`, `service`, `provider`, `portMapping`, `service_group`, `service_group_membership` are gone; schema and `grdb_migrations` rows are preserved; exactly one workspace exists afterwards. 1.x wraps the call in `try?` and logs `Database wiped and reset to factory defaults` (info) on success (`AppDatabase.swift:74`); the daemon MUST surface failures as `KUMA_DAT_WIPE_FAILED`.

Not touched by this function (1.x factory reset, `DataPortService+FactoryReset.swift:8-37`, orchestrated in [09](09-dataport.md)): `master.key`, `kubeconfigs/*.yaml` materializations, `daemon-state.sqlite`. The reset itself, in 1.x order: terminate all running services, wipe UserDefaults, `wipeAndResetDatabase()`, clear image cache and delete the whole `Workspaces/Images` directory.

### 3.10 `daemon-state.sqlite` (authoritative DDL, daemon-owned)

Separate file `<data dir>/daemon-state.sqlite`, WAL, `foreign_keys=ON`, `busy_timeout=5000`. It is never opened by 1.x. Created on first start with exactly:

```sql
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updatedAt TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS runtime_process (serviceID TEXT PRIMARY KEY, mode TEXT NOT NULL, pid INTEGER, pgid INTEGER, pidStartTimeMs INTEGER, executable TEXT, argvJSON TEXT, composeContextJSON TEXT, pollerJSON TEXT, startedAt TEXT NOT NULL, adopted INTEGER NOT NULL DEFAULT 0, intentionalStop INTEGER NOT NULL DEFAULT 0, reconnectAttempt INTEGER, lastFailure TEXT, updatedAt TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
```

(`mode` comment from the brief: `managedProcess|composeStack|poller`.) No other tables. Timestamps in this file use the **wire format** of 3.4.5 (`YYYY-MM-DDTHH:MM:SS.sssZ`), not the GRDB text form, because the file is daemon-private. UUID text (`serviceID`) is uppercase.

| Table.column | Type | Semantics | Written when |
|--------------|------|-----------|--------------|
| `settings.key` | TEXT PK | Setting key. All 1.x UserDefaults keys keep their exact names (3.15); client prefs use prefix `client.`. | `settings.set`, `settings.reset` (delete rows), ADD-09 legacy import ([03](03-settings-and-environment.md)). |
| `settings.value` | TEXT NOT NULL | Value as text; typed encoding (bool/int/string/JSON) is defined in [03](03-settings-and-environment.md). | same |
| `settings.updatedAt` | TEXT NOT NULL | Last write time. | same |
| `runtime_process.serviceID` | TEXT PK | Service whose run is tracked (uppercase UUID). One row per service at most. | Row inserted when a run starts (see [06](06-execution-engine.md)), deleted when the run has fully ended and nothing is to be adopted. |
| `runtime_process.mode` | TEXT NOT NULL | `managedProcess`, `composeStack` or `poller`. | at run start |
| `runtime_process.pid` | INTEGER | Main OS pid (NULL for `poller`). | at spawn; updated on reconnect/respawn |
| `runtime_process.pgid` | INTEGER | Process group id used for group signalling (NULL for `poller`). | at spawn |
| `runtime_process.pidStartTimeMs` | INTEGER | OS process start time (epoch ms) used to detect pid reuse before adopting or signalling. | at spawn / adoption |
| `runtime_process.executable` | TEXT | Absolute path of the spawned binary (NULL for `poller`). | at spawn |
| `runtime_process.argvJSON` | TEXT | JSON array of argv strings (including argv[0] as executed). | at spawn |
| `runtime_process.composeContextJSON` | TEXT | JSON describing the compose project (binary, project name, file paths, working dir) for `composeStack`; NULL otherwise. Shape owned by [06](06-execution-engine.md). | at start of a compose run |
| `runtime_process.pollerJSON` | TEXT | JSON describing the poller (kind, target, interval) for `poller`; NULL otherwise. Shape owned by [06](06-execution-engine.md). | at start of a poller run |
| `runtime_process.startedAt` | TEXT NOT NULL | Time of the (first) start of this run. | at start; preserved on adoption |
| `runtime_process.adopted` | INTEGER NOT NULL DEFAULT 0 | `1` if the process was not spawned by this daemon instance but adopted at startup. | at adoption |
| `runtime_process.intentionalStop` | INTEGER NOT NULL DEFAULT 0 | `1` while a user-requested stop is in flight, so the supervisor does not reconnect/report a crash; also consulted at adoption. | set on stop request, cleared on new run |
| `runtime_process.reconnectAttempt` | INTEGER | Current auto-reconnect attempt (NULL when not reconnecting). | on each reconnect attempt |
| `runtime_process.lastFailure` | TEXT | Last failure reason text (NULL if none). Never contains secrets (GR-04). | on failure |
| `runtime_process.updatedAt` | TEXT NOT NULL | Last write time of the row. | every write |
| `meta.key` / `meta.value` | TEXT PK / TEXT NOT NULL | Key-value for daemon bookkeeping; keys below. | below |

`meta` keys (exact):

| Key | Value | Written when |
|-----|-------|--------------|
| `schemaVersion` | decimal integer; `1` for this DDL | at creation; a daemon that finds a larger value MUST refuse to start with `KUMA_DAT_SCHEMA_TOO_NEW`; migrations of this file are daemon-private and bump the value |
| `eventSeq` | decimal `u64`, the last event sequence number issued ([08](08-logs-and-events.md), ADD-07) | persisted by the event bus (cadence defined in 08) |
| `legacyImportDone` | `1` once the first-start UserDefaults import ran (ADD-09), absent before | after the import attempt completes |
| `instanceId` | random UUID (uppercase) generated at first creation, stable across restarts | at creation |

Rows in `settings` and `runtime_process` are the daemon's private state: a factory reset deletes all rows of `settings` and `runtime_process` (and keeps `meta.instanceId`, resets `meta.legacyImportDone` per [09](09-dataport.md)).

### 3.11 Data rules

#### 3.11.1 Active provider

For a service `S` with its providers ordered by `createdAt ASC, rowid ASC` (`ServiceRepository+CRUD.swift:23-26`, `+DeckItems.swift`):

```
activeProviderIDEffective(S) = S.activeProviderID ?? providers.first?.id        (NULL-coalesce only)
```

Rules, all as in 1.x:
- `service.activeProviderID` has **no foreign key**; it may dangle (for example after a provider delete the 1.x UI repoints it, but the DB does not).
- **Deck item** (`ServiceRepository+DeckItems.swift:60-85`): if `activeProviderID` is non-NULL **and** a provider with that id exists, its `type` and `resolvedTarget` are used; **else** the first provider (by `createdAt`) is used; **else** category `docker` and `resolvedTarget ""`. Provider options mark `isActive = (provider.id == (S.activeProviderID ?? providers.first?.id))`: if `activeProviderID` dangles, no option is active while the category/target fall back to the first provider.
- **Switching provider** sets `service.activeProviderID` and bumps `service.updatedAt` ([04](04-workspaces-groups-services.md), [06](06-execution-engine.md)).
- **Duplicate** maps the old active provider to the corresponding new provider id; if the old active was not found among the copied providers (including NULL/dangling) the first copied provider becomes active (`ServiceRepository+CRUD.swift:231-253`).
- **Deleting the active provider** (UI rule, `ServiceInspectorViewModel+Providers.swift:111-123`): `activeProviderID := remaining providers.first?.id` (earliest by `createdAt`, possibly NULL) and the service row is updated. The daemon MUST apply this in `provider.delete`.
- **Adding a provider** makes it active (`addProvider` sets `activeProviderID`, `ServiceInspectorViewModel+Providers.swift:58-67`).

#### 3.11.2 Port-mapping visibility (`portMappingsForActiveProvider`, `ServiceRepository+DeckItems.swift:170-185`)

Inputs: the `portMapping` rows of one service (`WHERE serviceID = S.id`), `S.id`, `activeProviderID` (effective, 3.11.1, or an explicit provider id for `fetchPortMappings(forService:providerID:)`).

```
if activeProviderID is NULL: return []
scoped      = mappings where serviceID == S.id or serviceID is NULL     // DB column is NOT NULL, so scoped == mappings
forProvider = scoped where providerID == activeProviderID
if forProvider not empty: return forProvider
legacy      = scoped where providerID is NULL
if legacy.count == scoped.count: return legacy        // ONLY when every mapping of the service is legacy (all providerID NULL); includes the empty case which yields []
return []
```

Consequences (normative, tested by `ServicesPersistenceAndSyncTests` TC-C10): each provider owns its mappings; a service with legacy (NULL `providerID`) mappings shows them for **whatever** provider is active **only while no mapping of that service has a non-NULL providerID**; a dangling active provider id yields `[]` unless all rows are legacy; `deck.localPorts = visibleMappings.map(localPort)` in storage order.

Order of the returned mappings: **no `ORDER BY`** in 1.x (SQLite returns rows through `idx_port_service`, i.e. insertion/rowid order). The daemon MUST use `ORDER BY rowid ASC` (DEV-23 clarifies the tie-break).

`fetchAllPortMappings` returns every row unfiltered (used by DataPort and conflict checks).

#### 3.11.3 Ordering rules per table (as 1.x queries)

| Table | Query context | ORDER BY (1.x) | Daemon MUST use |
|-------|---------------|----------------|-----------------|
| `workspace` | list (`WorkspaceRepository.fetchAll`, `DataPortRepository+Export.swift:60`) | `sortOrder ASC, createdAt ASC` | `sortOrder ASC, createdAt ASC, rowid ASC` |
| `service_group` | per workspace (`ServiceGroupRepository.fetchAll`); export all (`+Export.swift:61`); export per workspace (`+Export.swift:142`, `sortOrder ASC` only) | `sortOrder ASC, createdAt ASC` | `sortOrder ASC, createdAt ASC, rowid ASC` everywhere |
| `service` | per workspace (`fetchDeckItems`) | `createdAt ASC` (then the deck applies its own sort in [04](04-workspaces-groups-services.md)) | `createdAt ASC, rowid ASC` |
| `provider` | per service | `createdAt ASC` | `createdAt ASC, rowid ASC` |
| `portMapping` | per service / all | none | `rowid ASC` |
| `service_group_membership` | per service / all | none (consumers build a `Set`) | not ordered; wire output sorted (3.4.5) |
| `kube_config` | list (`KubeConfigRepository.fetchAll`) | `createdAt ASC` | `createdAt ASC, rowid ASC`; the virtual Default entry is prepended by the caller (3.14.2) |

New row ordinals: a new workspace gets `sortOrder = <current workspace count>` (`WorkspaceStore.swift:98`); a new group gets `sortOrder = (max(existing group sortOrder in the workspace) ?? 0) + 1` (so the first group of an empty workspace gets `1`, `SidebarViewModel+Groups.swift:44`). Reordering assigns contiguous `0..n-1` in the new order to **every** row of the list, and sets `updatedAt = now` on each (`WorkspaceRepository.swift:43-51`, `ServiceGroupRepository.swift:42-51`; INV-SIDEBAR-05).

#### 3.11.4 Uniqueness and limits

- **No unique constraints** except primary keys. Duplicate names are allowed for workspaces, groups, services, providers and kubeconfigs; `portMapping` has no unique `(serviceID, providerID, localPort)`; two providers may reference the same kubeconfig; several services may use the same local port (conflicts are a runtime concern, [06](06-execution-engine.md)). `service_group_membership` is unique on `(serviceID, groupID)`.
- `portMapping.id` is a global primary key: `savePortMappings` regenerates a fresh UUID for a duplicate id **within one batch** (`ServiceRepository+CRUD.swift:166-175`); an id colliding with an existing row of another provider is a primary-key constraint error (`KUMA_DAT_CONSTRAINT_VIOLATION`).
- No size limits are enforced by the schema or repositories (names, YAML, scripts are unbounded TEXT).

Constants (data layer):

| Name | Value | Source |
|------|-------|--------|
| DB file name | `kuma.sqlite` | `AppDatabase.swift:26` |
| Default kubeconfig id | `00000000-0000-0000-0000-000000000001` | `KubeConfig.swift:7` |
| Default kubeconfig name | `Default` | `KubeConfigViewModel.swift:99` |
| Default workspace name pattern | `<First>'s Space` | `Workspace.swift:44-50` |
| New workspace fallback name (blank input after trim) | `New Workspace` | `WorkspaceStore.swift:87` |
| New group default name | `New Group` | `SidebarViewModel+Groups.swift:42` |
| Group rename fallback (blank after trim) | `Untitled Group` | `SidebarViewModel+Groups.swift:72` |
| Duplicate service suffix | `<name> (Copy)` | `ServiceRepository+CRUD.swift:229` |
| Port mapping default protocol | `TCP` | `AppDatabase.swift:173`, `ServicePortMapping.swift:18` |
| Avatar max pixel size / file name | 512 px, `<UPPERCASE-UUID>.png` | `WorkspaceImageStore.swift:51-90` |
| Avatar default thumbnail size | 128 | `WorkspaceImageStore.swift:125` |
| Health check poll: UI options / fallback default | 5, 10, 30, 60 s / UI shows 5 when NULL (`InspectorRemoteAndNetworkFormSections.swift:70`) | `HealthCheckSettingsView.swift:5-10` |
| Health check runner: fallback / floor | `httpCheckInterval ?? 10`, `max(…, 3)` | `HealthCheckRunner.swift:18` (owned by [06](06-execution-engine.md)) |
| Process monitor runner: fallback / floor | `monitorInterval ?? 5`, `max(…, 2)` | `ProcessMonitorRunner.swift:14` (owned by [06](06-execution-engine.md)) |
| `DB_BUSY_TIMEOUT_MS` | 5000 | ADD-22 |

#### 3.11.5 Cascade matrix (with `foreign_keys = ON`)

Rows are the deleted entity; cells the effect on dependants.

| Deleted | `service` | `provider` | `portMapping` | `service_group` | `service_group_membership` | other |
|---------|-----------|------------|---------------|-----------------|----------------------------|-------|
| `workspace` | deleted (CASCADE on `service.workspaceID`) | deleted via service | deleted via service | deleted (CASCADE on `service_group.workspaceID`) | deleted via service and via group | avatar file `Workspaces/Images/<id>.png` is **not** deleted by the DB; the store deletes it (`WorkspaceStore.swift:165-167`) and the daemon MUST too. Running services of the workspace are stopped first (DEV-03). |
| `service` | - | deleted (CASCADE) | deleted (CASCADE via `portMapping.serviceID`) | untouched | deleted (CASCADE on `serviceID`) | running process stopped first (DEV-14) |
| `service_group` | **untouched** (services stay, INV-SIDEBAR-03); legacy `service.groupID` set to NULL (`ON DELETE SET NULL`) | untouched | untouched | - | deleted (CASCADE on `groupID`) | |
| `provider` | `activeProviderID` is **not** updated by the DB (no FK) | - | mappings with that `providerID` deleted (CASCADE) | untouched | untouched | UI/daemon rule repoints active provider (3.11.1) |
| `portMapping` | untouched | untouched | - | untouched | untouched | |
| `kube_config` | untouched | `provider.kubeConfigID` is a plain TEXT (no FK) and is **not** cleared; a provider referencing a missing config fails at start with `Selected kubeconfig no longer exists.` ([07](07-kubernetes.md)) | untouched | untouched | untouched | |

#### 3.11.6 Legacy `service.groupID`

The column exists (v2) and is **never read and never written** by 1.x after v3 (`Service+Record.swift` does not map it; `Service.update` does not include it). The daemon MUST ignore it entirely: group membership is the `service_group_membership` table only. The daemon MUST NOT write the column for rows it creates (it stays NULL) and MUST NOT clear existing values. `service.groupID` still participates in the FK `ON DELETE SET NULL` of the DB.

#### 3.11.7 Repository write semantics that are data rules

- **Insert service** (`ServiceRepository.swift` / `+CRUD.swift:105-123`): one transaction: service row; optional default provider row; each mapping gets `serviceID = service.id` and, if its `providerID` is NULL, `providerID = defaultProvider.id` (stays NULL when no default provider); one membership row per `groupID` with `createdAt = now`.
- **Update service** (`+CRUD.swift:125-136`): `UPDATE service SET` every persisted column from 4.3 (all 11, not `groupID`) `WHERE id = ?` (error if no row); then **delete all memberships of the service and re-insert** from `groupIDs` (membership `createdAt` is reset to now).
- **Toggle group membership**: delete the pair if present, else insert; returns the full resulting set. Does **not** touch `service.updatedAt`.
- **Toggle starred**: flips `isStarred` and sets `updatedAt = now`.
- **Provider insert/update**: all 32 provider columns are written from the record (`update` rewrites every column; `type` is rewritten as `ProviderCategory.rawValue`, so an unknown stored `type` that decoded to `docker` is persisted as `docker` on the next update).
- **Save port mappings** (`+CRUD.swift:158-178`): `DELETE FROM portMapping WHERE serviceID = ? AND providerID = ?`, then insert each with forced `serviceID`/`providerID` (legacy NULL-provider rows are never deleted by this call). Does not touch `provider.updatedAt`.
- **Duplicate service** (`+CRUD.swift:205-285`, single transaction): copies the service row (flags `isDisabled`/`isStarred` preserved) with new id (given), `name + " (Copy)"`, `createdAt = updatedAt = now`; copies each provider (ordered `createdAt ASC`) with a new random UUID, `serviceID` = new, `createdAt = updatedAt = now`; copies each port mapping (all of the source service, unfiltered) with a new id; its `providerID` is mapped through the provider-id map, or, if NULL/unmapped, set to the new active provider, and the mapping is **skipped** if there is no new active provider; copies memberships (new `createdAt`). Source missing: error `Source service not found` (NSError domain `lokastudio.kuma`, code 404) → mapped to `KUMA_SVC_NOT_FOUND` by [04](04-workspaces-groups-services.md).
- **DataPort upsert of `kube_config`** (`DataPortRepository+Mapping.swift:17-39`): `INSERT ... ON CONFLICT(id) DO UPDATE SET name, configContent, sourceFilePath, updatedAt` (createdAt kept), name default `Imported`, entries with the default id are skipped, entries with neither ciphertext nor path are skipped ([09](09-dataport.md)).
- **`updatedAt` policy** (DEV-22): every RPC that changes a column of a `workspace`, `service_group`, `service`, `provider` or `kube_config` row sets `updatedAt = max(now, previous updatedAt + 1 ms)`. Port-mapping and membership changes do not touch parent `updatedAt` (as in 1.x).

### 3.12 Coexistence with a running 1.x app, and opening safely

1. **Detection (ADD-22).** On start and on `daemon.status`, the daemon SHOULD detect a running 1.x GUI: a process whose bundle identifier is `com.kuma.Kuma` (`PRODUCT_BUNDLE_IDENTIFIER`, the id 1.x's `SingleInstanceGuard` uses) or whose executable is named `Kuma` inside a `Kuma.app` bundle. Detection is advisory: a warning is logged and surfaced in `daemon.status`; the daemon still starts.
2. **Why it is dangerous.** SQLite WAL permits two processes to read and write the same file, but: (a) 1.x keeps `workspaces`, `groups`, deck snapshots in memory and does not observe daemon writes until it reloads; (b) the daemon does not observe 1.x writes made in its UI; (c) both could start the same service and fight over ports/processes; (d) 1.x writes with immediate-error busy mode, so long daemon write transactions can surface "database is locked" errors in the GUI. Therefore: write transactions MUST be short (no network/process I/O inside a transaction); the daemon MUST re-read rows inside the write transaction when it relies on a previous read (optimistic concurrency uses `expectedUpdatedAt`, 3.13).
3. **Policy.** Running 1.x and the daemon concurrently is **unsupported for execution** (service start/stop) and **tolerated for data** only as long as 1.x is a **Release** build. The daemon MUST NOT be pointed at a data dir used by a **Debug** build of 1.x (3.5.2).
4. **Never mutate on refusal.** Opening failures (`KUMA_DAT_SCHEMA_TOO_NEW`, `KUMA_DAT_DB_OPEN_FAILED`) must not modify any file.
5. **Backups.** Per 3.2 step 6 (ADD-20).

### 3.13 Concurrency token `expectedUpdatedAt`

- Every mutable entity (`workspace`, `service_group`, `service`, `provider`, `kube_config`) carries `updatedAt`. Update calls ([04](04-workspaces-groups-services.md), [05](05-providers-and-validation.md), [07](07-kubernetes.md)) take an optional `expectedUpdatedAt` (the value last read, wire format 3.4.5).
- If present: the daemon compares it to the stored `updatedAt` **at millisecond precision** (both parsed to epoch milliseconds, so a seconds-precision value from a 1.x backup never matches a stored millisecond value unless the millisecond part is zero) inside the write transaction; mismatch → `KUMA_CONFLICT_STALE`, no write. If absent: last write wins (1.x behavior).
- No schema change: the token is the existing column. DEV-22 guarantees every successful update strictly increases it.
- `ServicePortMapping` and `ServiceGroupMembershipRecord` have no `updatedAt`; they are covered by their parent's token when a parent update replaces them in the same call.

### 3.14 Derived values (not stored)

#### 3.14.1 `Provider` derived members (`Provider.swift:120-224`)

These are computed by the daemon and MAY be included in responses (spec 10); clients MUST NOT send them.

- `isAutoReconnectEnabled = (autoReconnect == true) && type.supportsAutoReconnect` (`supportsAutoReconnect` is true for `kubernetes`, `ssh`, `shell`; false for `docker`, `podman`, `httpCheck`, `tunnel`, `processMonitor`, `ProviderCategory.swift:37-44`).
- `displayName = label` if `label` is non-nil and `label.trimmingCharacters(in: .whitespaces)` is non-empty (the returned value is the **untrimmed** label), else `type.sidebarLabel`.
- `resolvedTarget` (also used by the deck item), per `type`; "trim-W" is Swift `.whitespaces` (space, tab and other Unicode space separators, not newlines); "trim-WN" is `.whitespacesAndNewlines`:

| type | Result |
|------|--------|
| `docker` | (1) `composeFilePath` trim-WN non-empty → `Docker: <lastPathComponent of the trimmed path>`; (2) else `yamlConfig` non-nil and `extractComposeImage(yaml)` non-nil → `Docker: <image>`; (3) else `label` non-nil and non-empty (no trimming) → `Docker: <label>`; (4) else `Docker` |
| `podman` | same as docker with prefix `Podman: ` and fallback `Podman` |
| `kubernetes` | `targetName` trim-W non-empty → `k8s: <trimmed targetName>`, else `Kubernetes` |
| `shell` | `runCommand` trim-W non-empty → the **trimmed** command, else `Shell script` |
| `ssh` | `SSH: <sshUser ?? "root">@<sshHost ?? "localhost">:<sshPort ?? 22>` (`??` applies to NULL only; an empty string is kept) |
| `httpCheck` | `httpCheckUrl` trim-W non-empty → `HTTP: <trimmed url>`, else `HTTP Check` |
| `tunnel` | `<(tunnelType ?? "cloudflare").capitalized> Tunnel -> <tunnelTargetUrl ?? "8080">` (`capitalized` = first letter of each word uppercased, remaining letters lowercased: `cloudflare` → `Cloudflare`, `ngrok` → `Ngrok`, `NGROK` → `Ngrok`) |
| `processMonitor` | `monitorProcessName` trim-W non-empty → `Monitor: <trimmed name>`, else `Process Monitor` |

`lastPathComponent` follows `NSString`: trailing `/` characters are ignored, the text after the last `/` is returned; `"/"` → `"/"`; `""` → `""`.

`extractComposeImage(yaml)` (`Provider.swift:198-224`): split `yaml` on Unicode newlines (`\n`, `\r`, `\u{85}`, `\u{2028}`, `\u{2029}`); for each line: trim-W; if it **starts with** `image:` (so `- image: x` does not match): `raw` = text after `image:` trimmed-W; `cleaned` = `raw` with leading/trailing `"` and `'` characters removed; then strip exactly one prefix in this precedence: `docker.io/library/`, else `docker.io/`, else `library/`; if `cleaned` is non-empty return it (first match wins; an empty result continues to the next line); no match → none.

#### 3.14.2 Virtual Default kubeconfig

`KubeConfig.defaultID = 00000000-0000-0000-0000-000000000001`, name `Default`, `isDefault = true`, `sourceFilePath` = resolved kubeconfig path (setting `kuma.settings.customKubeconfigPath`, else legacy `kuma.custom_kubeconfig_path`, else `~/.kube/config`), content = that file's text (empty if unreadable). It is **never stored** in `kube_config`; DB rows with that id are ignored by the list (`KubeConfigViewModel.swift:110`), cannot be deleted (`deleteConfig` guard) and are skipped by import. `provider.kubeConfigID` NULL means Default (`KubeConfigMaterializer.swift:21`). `KubeConfig.resolvedPlainYAML()` = file content at `sourceFilePath` (tilde-expanded, trimmed non-empty) or else `configContent`. Resolution rules for kubectl are owned by [07](07-kubernetes.md).

#### 3.14.3 `withKubernetesDefaults()` (`Provider+KubernetesDefaults.swift`)

Applied on **read** by the inspector for `type == kubernetes` only: `kubeTargetType` NULL/empty → `pod`; `usePattern` NULL → `true`. It is not persisted until the provider is saved. The daemon MUST apply it in `service.get`/`provider.list` responses for kubernetes providers, and MUST persist the defaulted values on `provider.add`/`provider.update` of a kubernetes provider (as the 1.x save path does through the draft).

### 3.15 Settings key names (reference; semantics in [03](03-settings-and-environment.md))

`settings.key` values are the exact 1.x UserDefaults keys (`KumaSettingsKey.swift`):

| Constant | Key |
|----------|-----|
| `hasCompletedOnboarding` | `kuma.has_completed_onboarding` |
| `launchAtLogin` | `kuma.settings.launchAtLogin` |
| `autoResumeServices` | `kuma.settings.autoResumeServices` |
| `activeServiceIDsBeforeQuit` | `kuma.settings.activeServiceIDsBeforeQuit` |
| `confirmBeforeQuit` | `kuma.settings.confirmBeforeQuit` |
| `quitBehavior` | `kuma.settings.quitBehavior` |
| `appearance` | `kuma.settings.appearance` |
| `defaultShell` | `kuma.settings.defaultShell` |
| `customKubectlPath` | `kuma.settings.customKubectlPath` |
| `customKubeconfigPath` | `kuma.settings.customKubeconfigPath` |
| `customDockerPath` | `kuma.settings.customDockerPath` |
| `customPodmanPath` | `kuma.settings.customPodmanPath` |
| `cloudflaredPath` | `kuma.settings.cloudflaredPath` |
| `customNgrokPath` | `kuma.settings.customNgrokPath` |
| `notifyOnServiceFailure` | `kuma.settings.notifyOnServiceFailure` |
| `portConflictPolicy` | `kuma.settings.portConflictPolicy` |
| `logRetentionLimit` | `kuma.settings.logRetentionLimit` |
| `clearLogsOnSwitch` | `kuma.settings.clearLogsOnSwitch` |
| `legacyKubectlPath` | `kuma.custom_kubectl_path` |
| `legacyKubeconfigPath` | `kuma.custom_kubeconfig_path` |
| `legacyDockerPath` | `kuma.custom_docker_path` |
| `legacyPodmanPath` | `kuma.custom_podman_path` |
| `legacyCloudflaredPath` | `kuma.custom_cloudflared_path` |
| `legacyNgrokPath` | `kuma.custom_ngrok_path` |
| `legacyNotifyOnCrash` | `kuma.settings.notifyOnCrash` |
| (WorkspaceStore) selected workspace | `kuma.selectedWorkspaceId.storage` (`WorkspaceStore.swift:9`; client preference, daemon KV key under `client.` per [03](03-settings-and-environment.md)) |

Helpers (`KumaSettingsKey.string/bool/integer`, lines 46-78): `string` returns the primary key's value if non-empty after trimming whitespace/newlines, else the fallback key's value under the same rule, else `nil`; `bool` returns the stored `Bool` of the primary key, else of the fallback key, else the explicit default; `integer` returns the stored `Int` else the default. These resolution semantics are implemented in [03](03-settings-and-environment.md).

### 3.16 ID helpers

#### 3.16.1 `UUID.stable(_ string)` (`UUID+Stable.swift:6-17`)

```
digest = SHA-256(UTF-8 bytes of string)          // 32 bytes
bytes  = digest[0..16]                           // first 16 bytes, unchanged
uuid   = UUID(uuid: bytes)                       // bytes used verbatim
text   = uppercase hex of the 16 bytes grouped 8-4-4-4-12
```

**No RFC 4122 version or variant bits are set**: the result is not a valid v4/v5 UUID; bytes 6 and 8 are not masked. The daemon MUST NOT mask them.

#### 3.16.2 Provider category stable IDs (`ProviderCategory.stableID`, `ProviderCategory.swift:30-32`)

`stableID = UUID.stable("provider." + rawValue)`. Computed values (SHA-256 verified):

| Category | Seed string | Stable ID |
|----------|-------------|-----------|
| `docker` | `provider.docker` | `BE2C4979-D129-11D1-CE51-4AE361C29035` |
| `kubernetes` | `provider.kubernetes` | `F510C94B-C4E0-34C9-65DE-35ACACA9DE3C` |
| `podman` | `provider.podman` | `880C949F-4EB5-8F9E-2755-F93E840E9483` |
| `shell` | `provider.shell` | `1C3514BE-9CC0-83AE-2B4A-4EE876A837E7` |
| `ssh` | `provider.ssh` | `BCA7833B-CB5C-89E2-5F76-9A7955CBEF84` |
| `httpCheck` | `provider.httpCheck` | `92215A27-54CA-3ECD-950A-43E7A9A383FD` |
| `tunnel` | `provider.tunnel` | `8DBCA405-4B9C-C0CC-55F1-06810283C158` |
| `processMonitor` | `provider.processMonitor` | `3375ABE8-36A2-306D-9EC5-6ABF2296D596` |

#### 3.16.3 Sidebar stable node IDs ([CLIENT], listed so nothing is dropped)

| Node | Seed | ID | Source |
|------|------|----|--------|
| All Services | `all-services` | `D41F59C3-5E36-88DE-07D7-4F1E420BB7DA` | `SidebarViewModel+Groups.swift:21` |
| Starred Services | `starred-services` | `BBF96D95-4D34-C31B-5956-D8D8A280558D` | `:22` |
| Groups header | `groups` | `4ED379D4-18BB-8629-0A01-117E9CEB0DEB` | `:24` |
| Settings | `settings` | `CDE0FB0D-EC14-00C5-4A0F-7E7EAFA73624` | `:23` |
| Empty-groups placeholder | `UUID.stable(<groups node uuidString> + ".empty-placeholder")` | derived | `SidebarViewModel+FlattenedRows.swift:91` |

Rule: `selectedID` of the sidebar is either one of these fixed IDs or a `ServiceGroup.id`; a group row id is the group's real UUID, never a stable ID. These IDs are client-side and are **not** stored in `kuma.sqlite`.

### 3.17 Secrets-at-rest marker (details in [02](02-security-and-secrets.md))

| Column | Content on disk | Written by | Read behavior (1.x) |
|--------|-----------------|------------|--------------------|
| `provider.sshPassword` | NULL, or vault ciphertext `base64(nonce):base64(tag):base64(ciphertext)` (AES-256-GCM, key `master.key`) | `Provider+Record.swift:127-133`: non-empty password → ciphertext; empty/nil → NULL | non-empty text → try decrypt; **on failure the raw stored text is returned as plaintext** (`:43`) |
| `provider.ngrokAuthToken` | same format | `Provider+Record.swift:138-142` | same fallback (`:56`) |
| `kube_config.configContent` | vault ciphertext of the YAML; for file-backed configs ciphertext of the empty string (`nonce:tag:` with an empty third part) or `""` for DataPort rows lacking ciphertext | `KubeConfigViewModel.swift:239-247`; record layer stores the value as given (`KubeConfig+Record.swift:31`) | decrypted by consumers (`KubeConfigMaterializer.swift:43`, `KubeConfigExecutionResolver.swift:62`); no plaintext fallback there |
| `provider.sshKeyPath` | **plain** path text (1.x never encrypts it; the runner only honors a `vault:` prefix that nothing writes, `SSHTunnelRunner.swift:72-80`) | - | - |

The daemon MUST write ciphertext (never plaintext) to these columns and MUST read both forms (plaintext fallback is a 1.x quirk kept for old rows, see [02](02-security-and-secrets.md)). The domain structs hold plaintext in memory; wire responses redact (brief: `sshPasswordSet`, `ngrokAuthTokenSet`, `hasContent`).

### 3.18 Enums (exact raw values and fallbacks)

#### 3.18.1 `ProviderCategory` (`ProviderCategory.swift`; `String`, Codable)

| Case | Raw value (DB `provider.type`, JSON) | `sidebarLabel` | `supportsAutoReconnect` | `addTooltip` |
|------|---------------------------------------|----------------|-------------------------|--------------|
| `docker` | `docker` | `Docker` | no | `New Docker Service` |
| `kubernetes` | `kubernetes` | `Kubernetes` | yes | `New Kubernetes Service` |
| `podman` | `podman` | `Podman` | no | `New Podman Service` |
| `shell` | `shell` | `Shell` | yes | `New Shell Service` |
| `ssh` | `ssh` | `SSH` | yes | `New SSH Service` |
| `httpCheck` | `httpCheck` | `Health Check` | no | `New Health Check Service` |
| `tunnel` | `tunnel` | `Tunnel` | no | `New Tunnel Service` |
| `processMonitor` | `processMonitor` | `Process Monitor` | no | `New Process Monitor Service` |

Declaration (and `allCases`) order: `docker, kubernetes, podman, shell, ssh, httpCheck, tunnel, processMonitor`.

**Decode fallbacks:**
- **DB record** (`Provider+Record.swift:14-15`): `ProviderCategory(rawValue: type) ?? .docker`. Only the exact camelCase raw values above are recognized in the database; legacy aliases are **not** applied at the DB layer. Unknown text decodes to `docker` (and is rewritten as `docker` by the next update of that row).
- **JSON (Codable):** an unknown raw value is a decoding error in 1.x. The daemon API returns `KUMA_DAT_INVALID_ENUM` for an unknown `type` on input.
- **Backup import** (`DataPortService+BackupModels.swift:213-225`, `ExportProvider.category`), the only place with legacy aliases; unknown → `docker`:

| Backup `type` string | Category |
|----------------------|----------|
| `kube_port_forward`, `kubernetes` | `kubernetes` |
| `docker` | `docker` |
| `podman` | `podman` |
| `shell` | `shell` |
| `ssh` | `ssh` |
| `http_check`, `httpCheck` | `httpCheck` |
| `tunnel` | `tunnel` |
| `process_monitor`, `processMonitor` | `processMonitor` |
| anything else | `docker` |

#### 3.18.2 `ServiceState` (`ServiceEnums.swift`; `String`, Codable, **not persisted**)

| Case | Raw | `title` | `isOperational` | `sortPriority` |
|------|-----|---------|-----------------|----------------|
| `stopped` | `stopped` | `Stopped` | no | 5 |
| `starting` | `starting` | `Starting` | yes | 1 |
| `running` | `running` | `Running` | yes | 0 |
| `stopping` | `stopping` | `Stopping` | no | 3 |
| `reconnecting` | `reconnecting` | `Reconnecting` | yes | 2 |
| `crashed` | `crashed` | `Crashed` | no | 4 |

Declaration order: `stopped, starting, running, stopping, reconnecting, crashed`. Lower `sortPriority` sorts first.

#### 3.18.3 `ServiceExecutionState` (`ServiceExecutionState.swift`; **not persisted, not Codable**)

| Case | Payload | `legacyState` | `isLoading` | `isOperational` | `title` | `sortPriority` | `processIdentifier` |
|------|---------|---------------|-------------|-----------------|---------|----------------|---------------------|
| `idle` | - | `stopped` | no | no | `Stopped` | 6 | nil |
| `starting` | - | `starting` | yes | yes | `Starting` | 1 | nil |
| `running(pid: Int32)` | pid | `running` | no | yes | `Running` | 0 | pid |
| `stopping` | - | `stopping` | yes | no | `Stopping` | 3 | nil |
| `reconnecting(attempt: Int, maxAttempts: Int)` | attempt, max | `reconnecting` | yes | yes | `Reconnecting (<attempt>/<maxAttempts>)` | 2 | nil |
| `crashed(exitCode: Int32)` | exit code | `crashed` | no | no | `Crashed` | 4 | nil |
| `failed(reason: String)` | reason | `crashed` | no | no | `Failed` | 5 | nil |

`isReconnecting` is true only for `reconnecting`. The daemon's wire representation of runtime state is [06](06-execution-engine.md); this table fixes the mapping to `ServiceRuntimeState` (3.19.7).

#### 3.18.4 `KubeTargetType` (`KubeTargetType.swift`; `String`; stored as free text in `provider.kubeTargetType`)

| Case | Raw | `label` | `displayLabel` | `listResource` | `listNameJSONPath` | placeholder / pattern placeholder |
|------|-----|---------|----------------|----------------|--------------------|-----------------------------------|
| `pod` | `pod` | `Pod` | `pod` | `pods` | `{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}` | `postgres-pod-6f8d975b` / `postgres-pod-*` |
| `service` | `service` | `Service` | `service` | `services` | `{range .items[*]}{.metadata.name}{"\n"}{end}` | `postgres-service` / `postgres-*-svc` |
| `deployment` | `deployment` | `Deployment` | `deployment` | `deployments` | `{range .items[*]}{.metadata.name}{"\n"}{end}` | `postgres-deployment` / `postgres-*-deployment` |

`portForwardKind` = raw value (`kubectl port-forward <kind>/<name>`). Descriptions: pod `Connect to a specific pod instance or match by pattern`, service `Forward traffic to a stable Kubernetes service endpoint`, deployment `Forward traffic to a deployment resource`. **Decode fallback:** `KubeTargetType(rawValue: provider.kubeTargetType ?? "") ?? .pod` (`KubeTargetResolver.swift:27`, `InspectorKubernetesFormSection.swift:70`): NULL, empty or unknown → `pod`. The column keeps the raw text it was given. Resolution semantics: [07](07-kubernetes.md).

#### 3.18.5 `DependencyCategory` (`SystemDependency.swift:3-6`; `String`, **not persisted**)

`engine` (comment: Kubernetes, Docker, Podman), `tunneling` (Cloudflare Tunnel, ngrok). Default for `SystemDependency.category` is `engine`.

#### 3.18.6 `TunnelEngineOption` (`TunnelSettingsView.swift:5-16`; stored as `provider.tunnelType` text)

| Case | Raw | Title |
|------|-----|-------|
| `cloudflare` | `cloudflare` | `Cloudflare Tunnel` |
| `ngrok` | `ngrok` | `Ngrok Tunnel` |

**Fallbacks:** UI: `TunnelEngineOption(rawValue: tunnelType ?? "cloudflare") ?? .cloudflare` (`InspectorRemoteAndNetworkFormSections.swift:81`). Runners and validator lower-case first: `provider.tunnelType?.lowercased() ?? "cloudflare"` (`TunnelRunner.swift:18`, `ServiceConfigurationValidator.swift:273`); `Provider.resolvedTarget` uses the raw string. The column MAY hold any text; the daemon MUST store exactly what was submitted (lower-case `cloudflare`/`ngrok` from UI paths).

#### 3.18.7 `HealthCheckIntervalOption` (`HealthCheckSettingsView.swift:5-17`; `Int`, stored in `provider.httpCheckInterval` and `provider.monitorInterval`)

| Case | Raw (seconds) | Title |
|------|---------------|-------|
| `fast` | 5 | `5s` |
| `standard` | 10 | `10s` |
| `relaxed` | 30 | `30s` |
| `slow` | 60 | `60s` |

Fallbacks: `HealthCheckIntervalOption(rawValue: interval ?? 5) ?? .fast` in the UI (both providers share the enum); runners use their own defaults/floors (3.11.4). The column may hold any integer (backups, API); the daemon MUST NOT coerce stored values to the option set.

#### 3.18.8 `PortConflictPolicy` (`SettingsViewModel.swift:35-45`; reference, a setting not a column)

| Case | Raw | Title |
|------|-----|-------|
| `warnAndBlock` | `warn_and_block` | `Warn & Prevent Start` |
| `killExisting` | `kill_existing` | `Kill Conflicting Process` |

Default (and fallback for missing/unknown values): `warn_and_block` (`SettingsViewModel.swift:183-184`). Stored in settings key `kuma.settings.portConflictPolicy`.

#### 3.18.9 `QuitBehavior` (`AppDelegate.swift:10-14`; reference, a setting)

Raw values `ask`, `stopAll`, `quitAnyway`; fallback for missing/unknown: `ask` (`AppDelegate.swift:51-52`). Stored in `kuma.settings.quitBehavior`. [CLIENT] behavior; the daemon stores the key only.

#### 3.18.10 Other enums stored as settings (reference)

`KumaAppearance`: `system`, `light`, `dark` (key `kuma.settings.appearance`). `DefaultShell`: `/bin/zsh`, `/bin/bash`, `/opt/homebrew/bin/fish` (raw = path, key `kuma.settings.defaultShell`). Semantics in [03](03-settings-and-environment.md).

### 3.19 Read models

`ServiceDeckItem`, `DeckProviderOption`, `ServiceRuntimeState` and `SystemDependency` are never persisted; they are projections built on read.

#### 3.19.1 Deck item construction (`ServiceRepository+DeckItems.swift`)

For a workspace: services `WHERE workspaceID = ? ORDER BY createdAt ASC`; empty → `[]`. Per service: providers `ORDER BY createdAt ASC`; `activeProvID = service.activeProviderID ?? providers.first?.id`; `localPorts = portMappingsForActiveProvider(...).map(localPort)` (3.11.2); `groupIDs` from memberships; `category/resolvedTarget` per 3.11.1; `providerOptions` in provider order with `label = (provider.label ?? "").trimmed-WN` (empty string when unset, **never NULL**) and `isActive`; `serviceDescription = service.description`; `createdAt = service.createdAt`. `fetchDeckItem(serviceID)` produces the identical item for a single service.

#### 3.19.2 `ServiceRuntimeState` (`ServiceRuntimeState.swift`)

`status: ServiceState` (default `stopped`), `isLoading: Bool` (default false), `statusTitle: String` (default `status.title`). `ServiceRuntimeState.idle` is the shared default for unknown services. From an execution state: `status = legacyState`, `isLoading = isLoading`, `statusTitle = title` (3.18.3).

### 3.20 Behavior of every 1.x function in the data files

| Function | Disposition |
|----------|-------------|
| `AppDatabase.init()` / `init(inMemory:)` | Daemon: 3.2 (the in-memory variant is test-only; the daemon test suite uses the same replay on `:memory:`) |
| `AppDatabase.wipeAndResetDatabase()` | 3.9 |
| `AppDatabase.migrator` | 3.6; DEBUG flag 3.5.2 |
| Record `init(row:)`/`encode(to:)` ×7 | 3.4 and 4.x tables |
| `ServiceRepository` queries (`fetchService`, `fetchServiceDetail`, `fetchProviders`, `fetchPortMappings` ×2, `fetchAllPortMappings`, `fetchDeckItems`, `fetchDeckItem`, `insertService`, `updateService`, `insertProvider`, `updateProvider`, `deleteProvider`, `savePortMappings`, `toggleStarred`, `toggleGroupMembership`, `deleteService`, `duplicateService`) | 3.11 (rules) and [04](04-workspaces-groups-services.md) (RPC orchestration). `fetchServiceDetail` returns service (with `groupIDs`), providers `createdAt ASC`, and port mappings **filtered** by 3.11.2 for `activeProviderID ?? providers.first?.id`. |
| `WorkspaceRepository`, `ServiceGroupRepository` `updateSortOrders` | 3.11.3 |
| `KubeConfigRepository` (`fetchAll`, `fetch`, `insert`, `update`, `delete`) | 3.11.3, 3.14.2; `update` is `UPDATE` by PK (error when missing), `delete` ignores a missing id |
| `Provider.withKubernetesDefaults`, `isAutoReconnectEnabled`, `displayName`, `resolvedTarget`, `extractComposeImage` | 3.14 |
| `KubeConfig.resolvedPlainYAML` | 3.14.2 |
| `ServicePortMapping.displayString` = `"<localPort>:<remotePort>"` (plain decimals, no grouping) | derived, `[CLIENT]` presentation; daemon MAY include `displayString` |
| `ServiceDeckItem.toggling(starred:)` | `[CLIENT]` in-memory helper |
| `UUID.stable`, `ProviderCategory.stableID` | 3.16 |
| `KumaSettingsKey.string/bool/integer` | 3.15, [03](03-settings-and-environment.md) |
| `WorkspaceImageStore` (all methods) | paths only here (3.1); behavior in [04](04-workspaces-groups-services.md) |
| `URLNormalizer.normalize` | not a data function; applied by [05](05-providers-and-validation.md) before storing `httpCheckUrl`/`tunnelTargetUrl`; stored text is the normalized string |

---

## 4. Data shapes

JSON keys are exactly the Swift property names (camelCase), enum values are exact raw strings, UUIDs uppercase, timestamps per 3.4.5. "Persisted" says whether the field has a column. "Wire req" says whether a create/update body must include it; per-RPC rules are in [10](10-rpc-protocol.md).

### 4.1 `Workspace` (table `workspace`; `Workspace.swift`, `Workspace+Record.swift`)

| Field (JSON key) | Type | Optional | Default | SQLite column (type) | Notes |
|------------------|------|----------|---------|----------------------|-------|
| `id` | UUID | no | random | `id` TEXT PK | immutable |
| `name` | string | no | - | `name` TEXT NOT NULL | not trimmed by storage; stores trim input beforehand |
| `imagePath` | string | yes | null | `imagePath` TEXT | bare `<UUID>.png` or legacy absolute path |
| `sortOrder` | int | no | 0 | `sortOrder` INTEGER NOT NULL DEFAULT 0 | |
| `createdAt` | timestamp | no | now | `createdAt` DATETIME NOT NULL | immutable (`let`) |
| `updatedAt` | timestamp | no | now | `updatedAt` DATETIME NOT NULL | concurrency token |

JSON decode (1.x `init(from:)`, `Workspace.swift:27-36`): `id`, `name` required; `imagePath` optional; `sortOrder` default 0; `createdAt`/`updatedAt` default `now` when absent. Not persisted: nothing.

```json
{"id":"F874297A-4994-4BF7-A7B4-041D80989622","name":"Putra's Space","sortOrder":0,"createdAt":"2026-11-01T23:36:30.921Z","updatedAt":"2026-11-01T23:36:30.921Z"}
```

### 4.2 `ServiceGroup` (table `service_group`; `ServiceGroup.swift`, `ServiceGroup+Record.swift`)

| Field | Type | Optional | Default | Column | Notes |
|-------|------|----------|---------|--------|-------|
| `id` | UUID | no | random | `id` TEXT PK | |
| `name` | string | no | - | `name` TEXT NOT NULL | rename: blank after trim → `Untitled Group` |
| `workspaceID` | UUID | yes in Swift, **required by the DB** | null | `workspaceID` TEXT NOT NULL → `workspace.id` ON DELETE CASCADE | the daemon always requires it |
| `sortOrder` | int | no | 0 | `sortOrder` INTEGER NOT NULL DEFAULT 0 | |
| `createdAt` | timestamp | no | now | `createdAt` | immutable |
| `updatedAt` | timestamp | no | now | `updatedAt` | token |

JSON decode defaults identical to `Workspace` (`ServiceGroup.swift:27-36`). 

### 4.3 `Service` (table `service`; `Service.swift`, `Service+Record.swift`)

| Field | Type | Optional | Default | Column | Notes |
|-------|------|----------|---------|--------|-------|
| `id` | UUID | no | random | `id` TEXT PK | |
| `name` | string | no | - | `name` TEXT NOT NULL | |
| `icon` | string | yes | null | `icon` TEXT | |
| `colorHex` | string | yes | null | `colorHex` TEXT | |
| `description` | string | yes | null | `description` TEXT | |
| `activeProviderID` | UUID | yes | null | `activeProviderID` TEXT (no FK) | 3.11.1 |
| `workspaceID` | UUID | yes in Swift, **required by the DB** | null | `workspaceID` TEXT NOT NULL → `workspace.id` ON DELETE CASCADE | |
| `groupIDs` | set of UUID (JSON array) | no | `[]` | **not a column**: derived from `service_group_membership` | **Not persisted in `service`**; written by replacing memberships |
| `isDisabled` | bool | no | false | `isDisabled` BOOLEAN NOT NULL DEFAULT 0 | |
| `isStarred` | bool | no | false | `isStarred` BOOLEAN NOT NULL DEFAULT 0 | read: NULL → false |
| `createdAt` | timestamp | no | now | `createdAt` | |
| `updatedAt` | timestamp | no | now | `updatedAt` | token |
| (not modelled) | - | - | - | `groupID` TEXT → `service_group.id` ON DELETE SET NULL | legacy, ignored (3.11.6) |

Synthesized `Codable`: all keys above (`groupIDs` array of strings); `nil` optionals are omitted.

```json
{"id":"…","name":"Postgres","description":"dev db","activeProviderID":"…","workspaceID":"…","groupIDs":["…"],"isDisabled":false,"isStarred":true,"createdAt":"…","updatedAt":"…"}
```

### 4.4 `Provider` (table `provider`; `Provider.swift`, `Provider+Record.swift`): 32 fields

Every field is persisted (one column each). "Cipher" = column holds vault ciphertext (3.17).

| # | Field (JSON key) | Type | Optional | Default | Column (type) | Used by | Notes |
|---|------------------|------|----------|---------|----------------|---------|-------|
| 1 | `id` | UUID | no | random | `id` TEXT PK | all | |
| 2 | `serviceID` | UUID | no | - | `serviceID` TEXT NOT NULL → `service.id` ON DELETE CASCADE | all | |
| 3 | `type` | `ProviderCategory` string | no | - | `type` TEXT NOT NULL | all | unknown DB text → `docker` (3.18.1) |
| 4 | `label` | string | yes | null | `label` TEXT | all | |
| 5 | `kubeConfigID` | UUID | yes | null | `kubeConfigID` TEXT (no FK) | kubernetes | NULL = Default kubeconfig |
| 6 | `customKubeConfigPath` | string | yes | null | `customKubeConfigPath` TEXT (v4) | kubernetes | legacy, import-only; honored first at run time ([07](07-kubernetes.md)) |
| 7 | `kubeContext` | string | yes | null | `kubeContext` TEXT | kubernetes | |
| 8 | `kubeNamespace` | string | yes | null | `kubeNamespace` TEXT | kubernetes | |
| 9 | `targetName` | string | yes | null | `targetName` TEXT | kubernetes | pod/service/deployment name or pattern |
| 10 | `kubeTargetType` | string | yes | null (read default `pod`) | `kubeTargetType` TEXT | kubernetes | raw of `KubeTargetType` |
| 11 | `usePattern` | bool | yes | null (read default `true`) | `usePattern` BOOLEAN | kubernetes | |
| 12 | `yamlConfig` | string | yes | null | `yamlConfig` TEXT | docker, podman | compose YAML text |
| 13 | `composeFilePath` | string | yes | null | `composeFilePath` TEXT (v6) | docker, podman | |
| 14 | `initialScript` | string | yes | null | `initialScript` TEXT | docker/podman (and compose pre-run) | |
| 15 | `initialScriptPath` | string | yes | null | `initialScriptPath` TEXT (v6) | same | |
| 16 | `runCommand` | string | yes | null | `runCommand` TEXT | shell | |
| 17 | `workingDirectory` | string | yes | null | `workingDirectory` TEXT | shell (and compose) | |
| 18 | `sshHost` | string | yes | null | `sshHost` TEXT | ssh | |
| 19 | `sshUser` | string | yes | null | `sshUser` TEXT | ssh | |
| 20 | `sshPort` | int | yes | null | `sshPort` INTEGER | ssh | |
| 21 | `sshKeyPath` | string | yes | null | `sshKeyPath` TEXT | ssh | plain path |
| 22 | `sshPassword` | string | yes | null | `sshPassword` TEXT | ssh | **Cipher** on disk; plaintext in memory; wire: omitted, `sshPasswordSet` ([02](02-security-and-secrets.md)) |
| 23 | `httpCheckUrl` | string | yes | null | `httpCheckUrl` TEXT | httpCheck | normalized by URLNormalizer |
| 24 | `httpCheckInterval` | int (seconds) | yes | null | `httpCheckInterval` INTEGER | httpCheck | 3.18.7 |
| 25 | `tunnelType` | string | yes | null | `tunnelType` TEXT | tunnel | `cloudflare`/`ngrok` |
| 26 | `tunnelTargetUrl` | string | yes | null | `tunnelTargetUrl` TEXT | tunnel | URL or port text |
| 27 | `ngrokAuthToken` | string | yes | null | `ngrokAuthToken` TEXT | tunnel | **Cipher**; wire: omitted, `ngrokAuthTokenSet` |
| 28 | `monitorProcessName` | string | yes | null | `monitorProcessName` TEXT | processMonitor | |
| 29 | `monitorInterval` | int (seconds) | yes | null | `monitorInterval` INTEGER | processMonitor | 3.18.7 |
| 30 | `autoReconnect` | bool | yes in Swift | null (stored `false`) | `autoReconnect` BOOLEAN NOT NULL DEFAULT 0 (v8) | kubernetes, ssh, shell | always written non-null |
| 31 | `createdAt` | timestamp | no | now | `createdAt` DATETIME NOT NULL | all | orders providers |
| 32 | `updatedAt` | timestamp | no | now | `updatedAt` DATETIME NOT NULL | all | token |

Derived, **not stored** (3.14.1): `displayName`, `resolvedTarget`, `isAutoReconnectEnabled`. The columns whose values apply to a category are only meaningful for it, but **every column is read and written for every category** (a shell provider keeps whatever `sshHost` it was given); the daemon MUST NOT null out foreign-category columns on its own.

Wire addition for secrets (spec 02 owns): `sshPasswordSet: bool`, `ngrokAuthTokenSet: bool` replace the two secret keys in responses.

### 4.5 `ServicePortMapping` (table `portMapping`; `ServicePortMapping.swift`, `ServicePortMapping+Record.swift`)

Note the table name is **camelCase** `portMapping`.

| Field | Type | Optional | Default | Column | Notes |
|-------|------|----------|---------|--------|-------|
| `id` | UUID | no | random | `id` TEXT PK | globally unique |
| `serviceID` | UUID | yes in Swift, **required by the DB** | null | `serviceID` TEXT NOT NULL → `service.id` ON DELETE CASCADE | forced by repository on save |
| `providerID` | UUID | yes | null | `providerID` TEXT → `provider.id` ON DELETE CASCADE (v5) | NULL = legacy/unscoped (3.11.2) |
| `localPort` | int | no | - | `localPort` INTEGER NOT NULL | |
| `remotePort` | int | no | - | `remotePort` INTEGER NOT NULL | |
| `protocolType` | string | no | `TCP` | `protocolType` TEXT NOT NULL DEFAULT 'TCP' | UI/app only writes `TCP` |

Derived: `displayString = "<localPort>:<remotePort>"`. Port range validation is owned by [05](05-providers-and-validation.md).

### 4.6 `ServiceGroupMembership` (table `service_group_membership`; `ServiceGroupMembershipRecord.swift`; record only, not Codable)

| Field | Type | Optional | Default | Column |
|-------|------|----------|---------|--------|
| `serviceID` | UUID | no | - | `serviceID` TEXT NOT NULL → `service.id` ON DELETE CASCADE, PK part |
| `groupID` | UUID | no | - | `groupID` TEXT NOT NULL → `service_group.id` ON DELETE CASCADE, PK part |
| `createdAt` | timestamp | no | now | `createdAt` DATETIME NOT NULL |

Not exposed as a wire entity: surfaces as `Service.groupIDs`.

### 4.7 `KubeConfig` (table `kube_config`; `KubeConfig.swift`, `KubeConfig+Record.swift`)

| Field | Type | Optional | Default | Column | Notes |
|-------|------|----------|---------|--------|-------|
| `id` | UUID | no | random | `id` TEXT PK | `00000000-0000-0000-0000-000000000001` is reserved for the virtual Default |
| `name` | string | no | - | `name` TEXT NOT NULL | |
| `configContent` | string | no | - | `configContent` TEXT NOT NULL | **Cipher** on disk (3.17); plaintext YAML in memory; wire: omitted, replaced by `hasContent` |
| `sourceFilePath` | string | yes | null | `sourceFilePath` TEXT (v7) | when set (trimmed non-empty) the file on disk wins over `configContent` |
| `isDefault` | bool | no | false | **not persisted** | `true` only for the virtual Default entry (the record initializer never sets it) |
| `createdAt` | timestamp | no | now | `createdAt` DATETIME NOT NULL | |
| `updatedAt` | timestamp | no | now | `updatedAt` DATETIME NOT NULL | token |

Wire: `{id, name, sourceFilePath?, hasContent, isDefault, createdAt, updatedAt}`; for the virtual Default the timestamps are the time of the request (it has no row). Not persisted: `isDefault`.

### 4.8 `ServiceDeckItem` and `DeckProviderOption` (read model; `ServiceDeckItem.swift`; not Codable in 1.x, wire keys = property names)

| Field | Type | Optional | Default (init) | Source |
|-------|------|----------|----------------|--------|
| `id` | UUID | no | - | `service.id` |
| `name` | string | no | - | `service.name` |
| `groupIDs` | array of UUID (sorted) | no | `[]` | memberships |
| `isDisabled` | bool | no | false | `service.isDisabled` |
| `isStarred` | bool | no | false | `service.isStarred` |
| `activeProviderCategory` | `ProviderCategory` | no | `docker` | 3.11.1 |
| `resolvedTarget` | string | no | `""` | 3.14.1 |
| `serviceDescription` | string | yes | null | `service.description` |
| `localPorts` | array of int | no | `[]` | 3.11.2 |
| `providerOptions` | array of `DeckProviderOption` | no | `[]` | providers in `createdAt` order |
| `createdAt` | timestamp | no | now | `service.createdAt` |

`DeckProviderOption`: `id` (UUID), `category` (`ProviderCategory`), `label` (string, raw trimmed, `""` when unset), `isActive` (bool).

### 4.9 `ServiceRuntimeState` (read model; `ServiceRuntimeState.swift`; not persisted)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `status` | `ServiceState` string | `stopped` | |
| `isLoading` | bool | false | |
| `statusTitle` | string | `status.title` | e.g. `Reconnecting (2/5)` when produced from an execution state |

The runtime wire object of [06](06-execution-engine.md) is a superset (adds pid, timestamps); these three keys keep their names.

### 4.10 `SystemDependency` (read model; `SystemDependency.swift`; not persisted; produced by `env.dependencies`, [03](03-settings-and-environment.md))

| Field | Type | Optional | Default | Notes |
|-------|------|----------|---------|-------|
| `id` | string | no | - | e.g. `docker` |
| `name` | string | no | - | |
| `iconName` | string | no | - | `[CLIENT]` presentation hint |
| `isInstalled` | bool | no | - | |
| `path` | string | yes | null | resolved binary path |
| `version` | string | yes | null | |
| `category` | `DependencyCategory` (`engine`/`tunneling`) | no | `engine` | |
| `description` | string | no | `""` | |
| `settingsKey` | string | no | `""` | the settings key that overrides the path |

### 4.11 Wire envelopes (conventions reused by 10)

- Entity objects use the key sets above. Lists are JSON arrays in the order of 3.11.3.
- `service.get` (spec 04) composes `{service, providers[], portMappings[], activeProviderID}` where `portMappings` is already filtered by 3.11.2 and `activeProviderID` is the **effective** one (`service.activeProviderID ?? providers.first?.id`, possibly null), matching `fetchServiceDetail` (`ServiceRepository+CRUD.swift:18-43`).
- Update requests carry the entity fields to change plus optional `expectedUpdatedAt` (timestamp, 3.13); responses return the entity with the new `updatedAt`.

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-DAT-01 | [PARITY] | Open an existing 1.x `kuma.sqlite` in place (WAL, FKs on) without altering its schema | `AppDatabase.swift:12-41` | `daemon.status` |
| FEAT-DAT-02 | [PARITY] | Create a fresh `kuma.sqlite` by replaying migrations v1..v8 and registering the same `grdb_migrations` identifiers | `AppDatabase.swift:78-296` | - |
| FEAT-DAT-03 | [PARITY] | Apply pending migrations (including v3 membership data migration and v5 `providerID` backfill) | `AppDatabase.swift:219-274` | - |
| FEAT-DAT-04 | [PARITY] | Seed the default workspace (`<First>'s Space`) on an empty DB | `AppDatabase.swift:181-196`, `Workspace.swift:44-55` | `workspace.list` |
| FEAT-DAT-05 | [PARITY] | Never-zero workspaces: reseed when the table is empty; forbid deleting the last | `WorkspaceStore.swift:61-68,160-163` | `workspace.list`, `workspace.delete` |
| FEAT-DAT-06 | [PARITY] | Storage codec: uppercase UUID text, `yyyy-MM-dd HH:mm:ss.SSS` UTC dates, 0/1 booleans, tolerant reads | `*+Record.swift`, GRDB `Date.swift` | all |
| FEAT-DAT-07 | [PARITY] | Wipe all user tables and reseed one workspace (`wipeAndResetDatabase`) | `AppDatabase.swift:62-75` | `data.factory_reset` |
| FEAT-DAT-08 | [PARITY] | Active provider resolution (`activeProviderID ?? earliest by createdAt`) | `ServiceRepository+DeckItems.swift`, `+CRUD.swift` | `service.get`, `service.list`, `service.switch_provider` |
| FEAT-DAT-09 | [PARITY] | Port-mapping visibility per active provider incl. legacy NULL-provider rule | `ServiceRepository+DeckItems.swift:170-185` | `service.get`, `service.list`, `provider.set_ports` |
| FEAT-DAT-10 | [PARITY] | Cascade-delete matrix (workspace, service, group, provider) | `AppDatabase.swift` FKs | `workspace.delete`, `service.delete`, `group.delete`, `provider.delete` |
| FEAT-DAT-11 | [PARITY] | Deterministic ordering of workspaces, groups, services, providers, kubeconfigs, ports | repositories | `workspace.list`, `group.list`, `service.list`, `provider.list`, `kubeconfig.list` |
| FEAT-DAT-12 | [PARITY] | Many-to-many group membership table; legacy `service.groupID` ignored | `AppDatabase.swift:219-238`, `Service+Record.swift` | `service.set_groups`, `service.toggle_group` |
| FEAT-DAT-13 | [PARITY] | Provider category decode fallback (unknown → docker) and legacy backup type aliases | `Provider+Record.swift:15`, `DataPortService+BackupModels.swift:213-225` | `provider.add`, `provider.update`, `data.import` |
| FEAT-DAT-14 | [PARITY] | Kubernetes read-time defaults (`kubeTargetType=pod`, `usePattern=true`) | `Provider+KubernetesDefaults.swift` | `service.get`, `provider.list`, `provider.add`, `provider.update` |
| FEAT-DAT-15 | [PARITY] | Derived provider values: `resolvedTarget`, `displayName`, `isAutoReconnectEnabled` | `Provider.swift:120-224` | `service.get`, `service.list`, `provider.list` |
| FEAT-DAT-16 | [PARITY] | Deck item read model (category, target, local ports, provider options, groupIDs) | `ServiceDeckItem.swift`, `+DeckItems.swift` | `service.list`, `service.get` |
| FEAT-DAT-17 | [PARITY] | Virtual Default kubeconfig (`...0001`), never stored, not deletable | `KubeConfig.swift:7`, `KubeConfigViewModel.swift:96-110` | `kubeconfig.list`, `kubeconfig.get`, `kubeconfig.delete` |
| FEAT-DAT-18 | [PARITY] | Secrets-at-rest columns marker (`sshPassword`, `ngrokAuthToken`, `kube_config.configContent` hold vault ciphertext); detail in 02 | `Provider+Record.swift`, `KubeConfigViewModel.swift` | `provider.add`, `provider.update`, `kubeconfig.create` |
| FEAT-DAT-19 | [PARITY] | Stable IDs: `UUID.stable` (SHA-256 first 16 bytes, no version bits) and provider category stable IDs | `UUID+Stable.swift`, `ProviderCategory.swift:30` | - |
| FEAT-DAT-20 | [CLIENT] | Sidebar fixed node IDs `all-services`, `starred-services`, `groups`, `settings` | `SidebarViewModel+Groups.swift:21-24` | - |
| FEAT-DAT-21 | [PARITY] | Enum catalogue with exact raw values (ProviderCategory, ServiceState, KubeTargetType, TunnelEngineOption, HealthCheckIntervalOption, PortConflictPolicy, QuitBehavior, DependencyCategory) | `Domain/Enums/*`, settings/UI files | `service.get`, `settings.get` |
| FEAT-DAT-22 | [PARITY] | Port-conflict and quit-behavior setting values stored by exact raw string | `SettingsViewModel.swift:35-45`, `AppDelegate.swift:10-14` | `settings.get`, `settings.set` |
| FEAT-DAT-23 | [V2-ADD] | `daemon-state.sqlite` with `settings`, `runtime_process`, `meta` | brief | `settings.list`, `settings.set`, `runtime.adopt_report` |
| FEAT-DAT-24 | [V2-ADD] | `expectedUpdatedAt` optimistic concurrency token on updates, strictly increasing `updatedAt` | brief | `workspace.update`, `group.update`, `service.update`, `provider.update`, `kubeconfig.update` |
| FEAT-DAT-25 | [V2-ADD] | Refuse unknown newer schema; pre-migration backup copy; busy timeout; 1.x coexistence warning | ADD-20/21/22 | `daemon.status` |
| FEAT-DAT-26 | [PARITY] | Workspace avatar storage naming (`Workspaces/Images/<UUID>.png`, bare file name or legacy absolute path in `imagePath`) | `WorkspaceImageStore.swift` | `workspace.get_image`, `workspace.set_image`, `workspace.clear_image` |
| FEAT-DAT-27 | [PARITY] | Default/fallback naming constants (`New Workspace`, `New Group`, `Untitled Group`, ` (Copy)`) | `WorkspaceStore.swift:87`, `SidebarViewModel+Groups.swift:42,72`, `ServiceRepository+CRUD.swift:229` | `workspace.create`, `group.create`, `group.update`, `service.duplicate` |
| FEAT-DAT-28 | [V2-ADD] | Tolerant row decoding (invalid UUID ids skipped, unparsable dates → epoch) instead of crash/random IDs | DEV-20/21 | all list methods |

---

## 6. Error catalog

| Code | Condition | Message |
|------|-----------|---------|
| `KUMA_DAT_DB_OPEN_FAILED` | File cannot be opened/created, is not a SQLite DB, or pragma setup fails | `Failed to initialize SQLite database: <detail>` (1.x `fatalError` text, `AppDatabase.swift:39`) |
| `KUMA_DAT_SCHEMA_TOO_NEW` | `grdb_migrations` contains an identifier outside the known list, or `daemon-state.sqlite` `meta.schemaVersion` is larger than supported | `Database was migrated by a newer version (unknown migration: <identifier>). Refusing to open.` |
| `KUMA_DAT_MIGRATION_FAILED` | A migration statement or its foreign-key check fails (transaction rolled back) | `Migration <identifier> failed: <detail>` |
| `KUMA_DAT_BACKUP_FAILED` | Pre-migration backup could not be written | `Could not create database backup before migration: <detail>` |
| `KUMA_DAT_WIPE_FAILED` | `wipeAndResetDatabase` fails | `Failed to reset database: <detail>` (1.x swallowed the error with `try?`) |
| `KUMA_DAT_ROW_DECODE` | A required column is not decodable (non-integer where INTEGER is required, NULL in a NOT NULL column) for the requested row | `Stored row in <table> could not be decoded: <column>` |
| `KUMA_DAT_INVALID_UUID` | A UUID received on the API is not the 36-char hyphenated hex form | `Invalid UUID: <value>` |
| `KUMA_DAT_INVALID_TIMESTAMP` | A timestamp received on the API is not ISO-8601 / the accepted forms of 3.4.5 | `Invalid timestamp: <value>` |
| `KUMA_DAT_INVALID_ENUM` | An enum value received on the API is not a known raw value (for example provider `type`) | `Invalid value '<value>' for <field>` |
| `KUMA_DAT_CONSTRAINT_VIOLATION` | SQLite constraint failure (PK duplicate, FK, NOT NULL) surfaced by a write | `Database constraint violated: <detail>` |
| `KUMA_DAT_DB_BUSY` | `SQLITE_BUSY`/`SQLITE_LOCKED` persists beyond `DB_BUSY_TIMEOUT_MS` | `Database is busy; another process holds a write lock.` |
| `KUMA_CONFLICT_STALE` (global) | `expectedUpdatedAt` differs from the stored value | defined in [10](10-rpc-protocol.md) |

Messages that include `<detail>` MUST NOT include secret values (GR-04). Entity-specific "not found" errors belong to the entity specs ([04](04-workspaces-groups-services.md), [07](07-kubernetes.md)). The 1.x text `Source service not found` (duplicate) is mapped by spec 04.

---

## 7. Deviations

| ID | Summary (full text in [15](15-traceability-and-parity.md)) |
|----|-----------------------------------------------------------|
| DEV-20 | Rows whose primary key/foreign key text is not a valid UUID are skipped, instead of 1.x generating a random UUID on every read. |
| DEV-21 | Unparsable `DATETIME` text decodes to the Unix epoch with a warning, and non-integer required integers return `KUMA_DAT_ROW_DECODE`, instead of 1.x trapping. |
| DEV-22 | `updatedAt` on every successful update is `max(now, previous + 1 ms)` so `expectedUpdatedAt` is a reliable token (1.x used plain `Date()`). |
| DEV-23 | Deterministic tie-break ordering (`rowid ASC` after the 1.x ORDER BY keys; ports by `rowid`; `groupIDs` sorted on the wire) where 1.x left order unspecified. |
| ADD-20 | Backup copy of `kuma.sqlite` before applying any pending migration, and a one-time `kuma.sqlite.pre-daemon.bak` before the first daemon write to a 1.x-created DB. |
| ADD-21 | Refuse to open (no writes) a DB whose `grdb_migrations` has identifiers unknown to the daemon (1.x Release ignored them, 1.x Debug erased the DB). |
| ADD-22 | `busy_timeout = 5000` ms and an advisory warning when a 1.x app instance (`com.kuma.Kuma`) is running. |
| (existing) DEV-03, DEV-14 | Delete cascade stops running services first (3.11.5). |
| (existing) DEV-11 | All 1.x UserDefaults keys → `daemon-state.sqlite` `settings` (§3.10, §3.15); see [15 DEV-11](15-traceability-and-parity.md). |
| (existing) DEV-10 | `runtime_process` persisted (3.10). |

---

## 8. Invariants

| ID | Statement |
|----|-----------|
| INV-D-DAT-01 | After the daemon opens/creates `kuma.sqlite`, `grdb_migrations` contains exactly the eight identifiers `v1_production_schema` … `v8_provider_auto_reconnect` and no others. |
| INV-D-DAT-02 | The user objects of `sqlite_master` (type, name, tbl_name, sql) and their creation order equal the listing of 3.5.1 byte for byte; the daemon never alters `kuma.sqlite` DDL outside the migration replay of 3.6. |
| INV-D-DAT-03 | Every connection to `kuma.sqlite` has `PRAGMA foreign_keys = ON` (except inside the per-migration disable/check/enable sequence) and the database is in WAL mode. |
| INV-D-DAT-04 | Every UUID written to any column is a 36-character uppercase hyphenated string; every UUID emitted on the wire is uppercase. |
| INV-D-DAT-05 | Every date written to `kuma.sqlite` has the form `YYYY-MM-DD HH:MM:SS.mmm` in UTC (one exception exists in existing data: v3 `datetime('now')` rows, which are only read). |
| INV-D-DAT-06 | Booleans are written as integers `0`/`1`; `provider.autoReconnect` is never NULL. |
| INV-D-DAT-07 | At the end of every operation that changes the workspace set, at least one workspace row exists. |
| INV-D-DAT-08 | The daemon never reads or writes `service.groupID`; membership is solely `service_group_membership`. |
| INV-D-DAT-09 | `portMapping.serviceID` and, for rows the daemon creates, `portMapping.providerID` are non-NULL; mapping visibility follows 3.11.2 exactly. |
| INV-D-DAT-10 | Deleting a workspace, service, group or provider produces exactly the cascade effects of 3.11.5 (groups never delete services; deleting a provider deletes only its port mappings and repoints `activeProviderID`). |
| INV-D-DAT-11 | `sshPassword`, `ngrokAuthToken` and `kube_config.configContent` are written only as vault ciphertext or NULL (or `""` for the empty/file-backed kubeconfig content), never plaintext. |
| INV-D-DAT-12 | `kuma.sqlite` is never written when `grdb_migrations` holds an unknown identifier. |
| INV-D-DAT-13 | Successful updates strictly increase the entity's `updatedAt`; a stale `expectedUpdatedAt` never results in a write. |
| INV-D-DAT-14 | `daemon-state.sqlite` is a separate file; none of its tables exist in `kuma.sqlite`. |
| INV-D-DAT-15 | After a reorder call, the list's `sortOrder` values are exactly `0..n-1` in the requested order. |
| INV-D-DAT-16 | The virtual Default kubeconfig id never has a row written to `kube_config`. |
| INV-D-DAT-17 | `wipeAndResetDatabase` leaves `grdb_migrations` intact and exactly one workspace. |

---

## 9. Acceptance tests

| ID | Arrange | Assert |
|----|---------|--------|
| DT-DAT-01 | Empty data dir; start daemon storage layer | `kuma.sqlite` exists, `journal_mode = wal`, `PRAGMA foreign_keys` is 1 on every pooled connection |
| DT-DAT-02 | Fresh DB from DT-DAT-01 | `SELECT identifier FROM grdb_migrations ORDER BY rowid` equals the eight identifiers in order |
| DT-DAT-03 | Fresh DB | `SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY rowid` equals the 3.5.1 listing exactly (including `grdb_migrations` first, quoting and column order) |
| DT-DAT-04 | Fresh DB | Exactly one `workspace` row; `imagePath` NULL, `sortOrder` 0, id uppercase 36 chars, name matches `<First>'s Space`, dates match `^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$` |
| DT-DAT-05 | A fixture `kuma.sqlite` produced by 1.x (real file) with services, groups, ports | Daemon opens it without any DDL change (schema listing unchanged), `grdb_migrations` unchanged, all lists return the rows with uppercase ids |
| DT-DAT-06 | DB with only `v1`..`v2` applied (service has legacy `groupID`; portMapping rows lacking providerID; services with/without activeProviderID) | Daemon applies v3..v8: membership rows created for non-empty `groupID` with `createdAt` in `YYYY-MM-DD HH:MM:SS` form; legacy `groupID` values untouched; v5 backfill assigns `COALESCE(active, earliest provider)`; services without any provider keep NULL `providerID`; a backup file `kuma.sqlite.pre-migrate-*.bak` exists and opens as a valid DB |
| DT-DAT-07 | DB whose `grdb_migrations` also contains `v9_future` | Open fails with `KUMA_DAT_SCHEMA_TOO_NEW`; file bytes unchanged (hash before/after); no WAL growth |
| DT-DAT-08 | Garbage file named `kuma.sqlite` | `KUMA_DAT_DB_OPEN_FAILED`; file not deleted or modified |
| DT-DAT-09 | Write a service via daemon, read raw SQL | `createdAt`/`updatedAt` are `YYYY-MM-DD HH:MM:SS.mmm` UTC text (`typeof = text`), `isDisabled`/`isStarred` integer 0/1, `id`/`workspaceID` uppercase |
| DT-DAT-10 | Rows inserted by hand with dates: `2026-01-02`, `2026-01-02 03:04`, `2026-01-02T03:04:05Z`, `2026-01-02 03:04:05.5`, `2026-01-02 03:04:05.123456`, `2026-01-02 03:04:05+02:00`, REAL `1767323045.25` | Each decodes to the expected UTC instant (midnight for date-only; fractions truncated to ms; `+02:00` applied; REAL as Unix seconds) |
| DT-DAT-11 | Row with `createdAt = 'not a date'` | List call succeeds, that row's `createdAt` is `1970-01-01T00:00:00.000Z`, a warning is logged (DEV-21) |
| DT-DAT-12 | Provider row with `id = 'not-a-uuid'`; service row with lowercase UUID text elsewhere unaffected | The provider is skipped from `provider.list` (DEV-20), no random id appears, other rows unaffected; an optional column `kubeConfigID = 'bad'` yields `kubeConfigID` absent |
| DT-DAT-13 | Provider row with `type = 'weird'` | Decodes as `docker`; after `provider.update` the column holds `docker` |
| DT-DAT-14 | Input UUID `f874297a-4994-4bf7-a7b4-041d80989622` (lowercase) for `workspace.get` | Row found; response id uppercase; invalid input `{F874...}` → `KUMA_DAT_INVALID_UUID` |
| DT-DAT-15 | Service with two providers P1 (createdAt older), P2; `activeProviderID` NULL | Deck item category/target are P1's; `isActive` true on P1 only; `activeProviderID` effective = P1 |
| DT-DAT-16 | Service with `activeProviderID` pointing to a deleted provider id (dangling) and mappings for P1 | Deck item uses first provider's category/target; no option has `isActive = true`; `localPorts = []` (mappings scoped to P1 are not visible) |
| DT-DAT-17 | Service with P1 (2222:22) and P2 (8080:80) mappings (cf. TC-C10) | Active P1 → `[2222]`; after switching active to P2 → `[8080]`; deck `localPorts` agrees |
| DT-DAT-18 | Service whose mappings all have NULL `providerID` (legacy), two providers | Mappings visible for either active provider; after adding one mapping with a non-NULL providerID for P1: with P1 active only that one is visible; with P2 active `[]` |
| DT-DAT-19 | Workspace with services, providers, mappings, groups, memberships | `workspace.delete` removes all child rows (counts 0), avatar file deleted; with ≥2 workspaces the other is untouched; deleting the sole workspace is rejected and nothing is deleted |
| DT-DAT-20 | Group G with two member services | `group.delete` removes the group and its membership rows; services still exist; legacy `service.groupID` NULL-ed if it referenced G |
| DT-DAT-21 | Provider P (active) with mappings | `provider.delete` removes P and its mappings; `service.activeProviderID` becomes the earliest remaining provider id (or NULL) |
| DT-DAT-22 | Create three workspaces and groups; reorder with a new id order | `sortOrder` values are exactly `0..n-1` in that order and each row's `updatedAt` increased; first group created in an empty workspace has `sortOrder = 1` |
| DT-DAT-23 | Create services/providers in the same millisecond | List order is stable: `createdAt ASC, rowid ASC`; ports in `rowid` order |
| DT-DAT-24 | Run `wipeAndResetDatabase` equivalent on a populated DB | All user tables empty except one new workspace (new id ≠ old); `grdb_migrations` still 8 rows; `kubeconfigs/` and `master.key` untouched |
| DT-DAT-25 | Compute `UUID.stable` for the 12 seed strings of 3.16 | Results equal the table values exactly (no version/variant bits masked) |
| DT-DAT-26 | Resolved targets table 3.14.1 | `docker` with composeFilePath `/a/b/stack.yml` → `Docker: stack.yml`; yaml `  image: "docker.io/library/mongo:7"` → `Docker: mongo:7`; `docker.io/redis:alpine` → `Docker: redis:alpine`; `library/postgres:16` → `Docker: postgres:16`; `- image: x` ignored; ssh with only host → `SSH: root@<host>:22`; tunnel `NGROK` → `Ngrok Tunnel -> 8080`; processMonitor blank → `Process Monitor`; kubernetes `targetName` `  api-* ` → `k8s: api-*` |
| DT-DAT-27 | Kubernetes provider added without `kubeTargetType`/`usePattern` | Stored row has `kubeTargetType = 'pod'` and `usePattern = 1`; legacy row with NULLs is returned with those defaults |
| DT-DAT-28 | Save secrets via daemon | Raw columns `sshPassword`, `ngrokAuthToken` match `^[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]*$` and differ from the plaintext; 1.x-style plaintext legacy value in the column is returned as plaintext on read |
| DT-DAT-29 | `daemon-state.sqlite` created | `sqlite_master` contains exactly `settings`, `runtime_process`, `meta` with the DDL of 3.10; `meta` has `schemaVersion = 1` and a UUID `instanceId` that is identical after restart; none of these tables exist in `kuma.sqlite` |
| DT-DAT-30 | `expectedUpdatedAt` equal to stored → update succeeds and `updatedAt` strictly greater; a second update with the old token → `KUMA_CONFLICT_STALE` and the row is unchanged; two updates inside one millisecond still produce increasing `updatedAt` | as stated |
| DT-DAT-31 | Virtual Default kubeconfig | `kubeconfig.list` returns Default first with id `00000000-0000-0000-0000-000000000001`, `isDefault: true`; no `kube_config` row exists for it; `kubeconfig.delete` of it fails; a DB row with that id (hand-inserted) is not listed |
| DT-DAT-32 | Concurrent 1.x-style writer holds a write transaction for 1 s | Daemon write waits (busy timeout) and succeeds; with a lock held for > 5 s it fails with `KUMA_DAT_DB_BUSY` |
| DT-DAT-33 | Duplicate service with two providers, ports, groups (cf. TC-C07) | New service name `<name> (Copy)`, fresh ids, providers copied in order, active mapped to the corresponding copy, mappings re-pointed, memberships copied; copy is one transaction (failure injected midway leaves nothing) |
| DT-DAT-34 | `service.update` with new `groupIDs` | All previous membership rows for the service are replaced (new `createdAt`), `service.groupID` column unchanged |

---

## Proposed RPC additions

None. All data operations map to methods in the registry of [00 §5](00-overview-and-conventions.md). `daemon.status` (ADD-06) SHOULD report `dbPath`, applied migration identifiers (`schemaMigrations`), whether `daemon-state.sqlite` is healthy, and the advisory "1.x app running" flag of 3.12; the field names are for [14](14-lifecycle-and-platform.md) and [10](10-rpc-protocol.md) to fix.

---

## Open questions / residual risks

1. **UUID case of foreign-written rows.** 1.x always writes uppercase, and the daemon normalizes input to uppercase, so a row whose key text was stored in lowercase by some third-party tool is unreachable (as it already is in 1.x because of exact-match queries). Chosen: out of spec; such rows are returned by list queries with uppercased ids but cannot be addressed by id. Revisit only if real data shows lowercase ids.
2. **DateFormatter truncation vs rounding.** GRDB formats with `DateFormatter` (`SSS`). I specify truncation of sub-millisecond digits; if Foundation rounds in some versions, a freshly written 1.x value may differ from the daemon's by 1 ms for identical instants. Tolerated: the daemon only ever compares values it read back from the DB (never recomputes from Swift `Date`).
3. **Schema text identity depends on the GRDB revision.** The listing in 3.5.1 is from a real DB written by a GRDB revision close to the pinned `0d8cf958...`; older GRDB versions emitted `PRIMARY KEY NOT NULL` for text primary keys. A 1.x Debug build compares against its own GRDB output, so a DB created by an older 1.x GRDB would already have been erased/recreated; Release builds never compare. The daemon follows the listing observed.
4. **`PRAGMA foreign_keys = OFF` inside `wipeAndResetDatabase` is a no-op** (it runs inside GRDB's write transaction); the final state is identical, but the daemon should not rely on FK-off semantics there.
5. **Multi-user daemon uid.** The default workspace name uses the daemon's uid; if the daemon runs under another account than the GUI user the name differs from what 1.x would have produced. Only affects the first-run name.
6. **v5 backfill can reference a missing provider** when `activeProviderID` dangles at migration time; the FK check would then fail the migration. Not observed in 1.x-created data; the daemon fails safe (rollback + `KUMA_DAT_MIGRATION_FAILED`) rather than modify the backfill.
7. **`ServicePortMapping`/membership concurrency token.** They have no `updatedAt`; clients replacing ports concurrently rely on the parent's token only when the parent is updated in the same call (`provider.set_ports` is last-write-wins, as in 1.x).
