# Daemon Spec 04: Workspaces, Groups, Services, Providers and the Deck Query

> **Status:** Draft for implementation  
> **Areas:** `WS` (workspaces and image store), `GRP` (service groups), `SVC` (services, providers as rows, deck)  
> **Depends on:** [00](00-overview-and-conventions.md) (IDs, registry), [01](01-data-model.md) (entities, columns, storage formats, ordering, cascade matrix, `updatedAt` policy)  
> **Cooperates with:** [02](02-security-and-secrets.md) (secret redaction on the wire), [03](03-settings-and-environment.md) (selected-workspace preference), [05](05-providers-and-validation.md) (provider field rules, create rules, validator), [06](06-execution-engine.md) (stop/start/runtime state), [08](08-logs-and-events.md) (event payload schema), [09](09-dataport.md) (backup/import/factory reset use the image store), [10](10-rpc-protocol.md) (final parameter schemas)

---

## 1. Purpose and scope

This spec defines every daemon behavior that 1.x implemented in `WorkspaceStore`, `WorkspaceImageStore`, the sidebar group view-model, the deck view-model, the service inspector view-model, and the `ServiceRepository` / `WorkspaceRepository` / `ServiceGroupRepository` write paths:

- Workspace CRUD, never-zero rule, reorder, default-seed rules, the avatar image store (`workspace.*`).
- Group CRUD, ordering and many-to-many membership (`group.*`, `service.set_groups`, `service.toggle_group`).
- Service lifecycle of the *row*: create, get, update, delete, duplicate, star, disable, switch provider (`service.*` except start/stop/restart/bulk/status, which are [06](06-execution-engine.md)).
- Provider rows of a service: list, add, update, delete, replace port mappings (`provider.*`). Provider *field semantics* and validation are [05](05-providers-and-validation.md).
- The deck query `service.list` (search, filters, sort, DTO) and the **bulk-action target set** consumed by [06](06-execution-engine.md).
- The mapping of 1.x intra-app notifications to daemon events, and an explicit list of everything that stays in the client (`[CLIENT]`).

Out of scope: DDL and storage formats ([01](01-data-model.md)); provider field tables, URL normalization, `ServiceConfigurationValidator` ([05](05-providers-and-validation.md)); process execution and runtime state wire format ([06](06-execution-engine.md)); event payload schemas ([08](08-logs-and-events.md)); backup JSON ([09](09-dataport.md)).

Terminology used below: *effective active provider* = `service.activeProviderID ?? providers.first?.id` ([01 §3.11.1](01-data-model.md)); *operational* = runtime status `starting`, `running` or `reconnecting` ([01 §3.18.2](01-data-model.md)); *trim* = Swift `.whitespacesAndNewlines` unless stated; *now* = one timestamp per operation, ms precision, with the DEV-22 monotonic rule `updatedAt = max(now, previous + 1 ms)` ([01 §3.11.7](01-data-model.md)).

---

## 2. 1.x source of truth (paths read)

All paths are relative to the repository root. Line numbers are as read.

| Topic | Files |
|-------|-------|
| Workspace store | `Kuma/Stores/WorkspaceStore.swift` (key `:9`, load `:47-77`, select `:80-83`, add `:85-112`, rename `:114-129`, update `:131-156`, delete `:158-184`, move `:186-210`) |
| Workspace model | `Kuma/Domain/Models/Workspace.swift` (`defaultName :44-50`, `defaultWorkspace :53-55`) |
| Workspace repository | `Kuma/Core/Database/Repositories/WorkspaceRepository.swift` (`updateSortOrders :42-51`, `delete :53`) |
| Group repository | `Kuma/Core/Database/Repositories/ServiceGroupRepository.swift` |
| Image store | `Kuma/Core/Storage/WorkspaceImageStore.swift` (cache count `:21`, dir `:27-45`, save `:52-95`, base64 save `:98-111`, base64 load `:114-122`, thumbnail `:127-160`, cache key/revision `:162-179`, resolve `:182-187`, delete `:190-194`, clear `:197-201`) |
| Workspace UI | `Kuma/Presentation/Features/Workspace/Views/WorkspaceFormSheet.swift`, `WorkspaceSwitcherPopover.swift`, `Components/InactiveWorkspaceRow.swift`, `WorkspaceAvatarPickerView`, `WorkspaceAvatarView` |
| Global shortcuts and menus | `Kuma/App/KumaShortcuts.swift:29-80`, `Kuma/App/KumaCommands.swift:11-62` |
| Sidebar (groups) | `Kuma/Presentation/Features/Sidebar/ViewModels/SidebarViewModel+Groups.swift` (`:5` load, `:19` reconcile, `:42` add, `:69` rename, `:94` delete, `:116` selected group), `SidebarViewModel+Reorder.swift` (`:5-55`), `SidebarViewModel+FlattenedRows.swift` (`:19-195`), `SidebarViewModel.swift`, `SidebarView.swift` and its row/menu views |
| Deck view-model | `ServicesDeckViewModel.swift` (`:12-100`), `+Filtering.swift` (`:9-90`), `+ServiceActions.swift` (`:6-229`), `+ExecutionActions.swift` (`:5-80`), `+WorkspaceLoad.swift` (`:5-98`) |
| Deck views | `Views/Deck/ServicesDeckView*.swift`, `Views/Deck/Components/ServicesDeckContentBodyView.swift`, `ServiceCardRow.swift`, `ServicesDeckCardGridView.swift`, `ServiceTableView.swift`, `ServiceDeckTableSection.swift`, `CardToggleSwitch.swift`, `ServiceStatusObserver.swift`, `ServiceNonPortBadge.swift`, `SyncedServiceRuntime.swift`, `ServicesDeckRuntimeObservation.swift`, `ServiceActionContextMenu`, `ServiceDeckActions.swift` |
| Deck read model | `Kuma/Presentation/Features/Services/Models/ServiceCardSnapshot.swift` (`toggling :57`, `matchesSearchQuery :64`, `deckSearchKey :114`), `Kuma/Core/Database/Repositories/ServiceRepository+DeckItems.swift` (`:5-104`, `:106-168`, `:170-185`, `:188`) |
| Service repository | `Kuma/Core/Database/Repositories/ServiceRepository+CRUD.swift` (`fetchService :5`, `fetchServiceDetail :17-43`, `toggleStarred :45-55`, `insertService :104-122`, `updateService :124-137`, `insertProvider :139`, `updateProvider :145`, `deleteProvider :151`, `savePortMappings :157-178`, `toggleGroupMembership :180-199`, `deleteService :201`, `duplicateService :208-285`) |
| Create flow | `Views/CreateService/CreateServiceSheet.swift`, `Components/CreateServicePayloadBuilder.swift` (`buildPayload :9-95`, `isFormValid :100-145`), `CreateServiceSaving`, `Kuma/ContentView.swift` (`createServiceDefaultsForCurrentSidebar`, `:101`) |
| Inspector view-model | `ServiceInspectorViewModel.swift`, `+AutoSave.swift` (`:5-89`), `+Providers.swift` (`:5-171`), `+Loading.swift` (`:5-77`), `+Execution.swift`, `+Validation.swift` (`:5-107`) |
| Inspector views | `Views/Inspector/ServiceInspectorView.swift`, `ServiceProvidersSectionView.swift`, `Components/InspectorConfigFormStack.swift` (`:40-57`), `ServiceProvidersListView.swift` (`canDelete: providers.count > 1 :38`), `ProviderItemRowView.swift` |
| Execution glue (behavior owned by 06) | `Kuma/Core/Execution/ServiceStartSupport.swift`, `ServiceStopSupport.swift` |
| Notifications | `Kuma/Core/Notifications/Notification+Kuma.swift` (`:8-29`), `Views/Deck/ServicesDeckView+Notifications.swift`, `ServicesDeckView+DeckChrome.swift` (`:81-98`) |
| Tests read (implicit requirements) | `KumaTests/Features/Services/ServicesPersistenceAndSyncTests.swift` (TC-C01..C13), `ServicesInitialStateTests.swift` (TC-A01..A06b), `UIOptimizationTests.swift` (TC-UI01, TC-E05/E05b/E05c, TC-G02..G06), `ServicesValidationAndSecurityTests.swift` (TC-B05, Services.E01, TC-E01b, TC-RUN04, Services.B04i); workspace tests TC-C06, TC-E03, TC-E05 (reorder, corrupt image, out-of-range) |

---

## 3. Normative behavior

### 3.0 Conventions common to every method in this spec

1. **Identifiers.** UUID parameters accept any case and are normalized to uppercase before comparison or storage; responses emit uppercase ([01 §3.4.1](01-data-model.md)). A malformed UUID is `KUMA_DAT_INVALID_UUID`.
2. **Timestamps.** Wire form `YYYY-MM-DDTHH:MM:SS.sssZ`; storage form `yyyy-MM-dd HH:mm:ss.SSS` UTC ([01 §3.4](01-data-model.md)).
3. **`updatedAt`.** Every successful write RPC that names a `workspace`, `service_group`, `service` or `provider` row sets that row's `updatedAt` per DEV-22, **even when no field value changed** (1.x unconditionally set `updatedAt = Date()` on every commit). Exceptions that follow 1.x and do **not** touch any parent `updatedAt`: membership changes by `service.set_groups` / `service.toggle_group`, port replacement by `provider.set_ports` ([01 §3.11.7](01-data-model.md)).
4. **`expectedUpdatedAt`.** Optional on `workspace.update`, `workspace.set_image`, `workspace.clear_image`, `group.update`, `service.update`, `service.set_disabled`, `service.set_starred`, `service.switch_provider`, `provider.add`, `provider.update`. If present it is compared (ms precision, inside the write transaction) to the stored `updatedAt` of the **row the method names** (`provider.add` and `provider.delete` name the parent **service** row); mismatch → `KUMA_CONFLICT_STALE`, no write ([01 §3.13](01-data-model.md)). Absent → last write wins.
5. **Serialization.** Write methods touching the same workspace, group or service are serialized (GR-03). `service.switch_provider` and `service.set_disabled` hold the per-service serialization across their stop/start sub-steps (they queue other mutating calls on that service, they do not block reads).
6. **Transactions.** Each write method is one SQLite write transaction unless this spec says otherwise. No process or network I/O happens inside a transaction ([01 §3.12](01-data-model.md)). Event emission happens **after** commit, in the order listed in §3.9.
7. **Missing entities.** A write or read that names a missing workspace/group/service/provider fails with the `KUMA_*_NOT_FOUND` code of the entity (DEV-57). List queries by `workspaceID` for an unknown workspace return an empty list (1.x `fetchAll(workspaceID:)` / `fetchDeckItems(forWorkspace:)` returned `[]`).
8. **Secrets.** Provider objects in responses never contain `sshPassword` or `ngrokAuthToken`; they carry `sshPasswordSet` and `ngrokAuthTokenSet` ([02](02-security-and-secrets.md), brief). Write calls accept the secret fields.
9. **Partial updates.** For `*.update` methods an **absent** key means "unchanged"; an explicit JSON `null` clears an optional field; unknown keys are rejected by the protocol layer ([10](10-rpc-protocol.md)).

### 3.1 Constants

| Name | Value | Source |
|------|-------|--------|
| `WORKSPACE_DEFAULT_NEW_NAME` | `New Workspace` (blank trimmed input on create) | `WorkspaceStore.swift:87` |
| `WORKSPACE_SEED_NAME` | `<First>'s Space` ([01 §3.8](01-data-model.md)) | `Workspace.swift:44-50` |
| `GROUP_DEFAULT_NEW_NAME` | `New Group` | `SidebarViewModel+Groups.swift:42` |
| `GROUP_FALLBACK_RENAME` | `Untitled Group` (blank trimmed rename) | `SidebarViewModel+Groups.swift:72` |
| `SERVICE_COPY_SUFFIX` | ` (Copy)` appended to the source name: `"\(name) (Copy)"` | `ServiceRepository+CRUD.swift:229` |
| `IMAGE_MAX_PIXELS` | `512` (stored avatar longest side) | `WorkspaceImageStore.swift:73` |
| `IMAGE_FILE_NAME` | `<UPPERCASE-WORKSPACE-UUID>.png` | `WorkspaceImageStore.swift:53` |
| `IMAGE_DIR` | `<data dir>/Workspaces/Images` | `WorkspaceImageStore.swift:37` ([01 §3.1](01-data-model.md)) |
| `IMAGE_THUMB_DEFAULT` | `128` (`get_image` default `size`) | `WorkspaceImageStore.swift:127` |
| `IMAGE_CACHE_COUNT_LIMIT` | `100` entries (optional daemon cache) | `WorkspaceImageStore.swift:21` |
| `IMAGE_THUMB_REQUEST_FACTOR` | avatar views request `maxDimension = size * 2` | `WorkspaceAvatarView` |
| `IMAGE_SIZE_CLAMP` | `get_image` `size` clamped to `1...1024` (daemon decision, §3.3.4) | this spec |
| `GROUP_FIRST_SORT_ORDER` | `1` (first group of an empty workspace: `(max ?? 0) + 1`) | `SidebarViewModel+Groups.swift:44` |
| `PORT_MIN` / `PORT_MAX` | `1` / `65535` | `ServiceConfigurationValidator.swift:94`, `CreateServicePayloadBuilder.swift:110-111` |
| `PORT_DEFAULT_PROTOCOL` | `TCP` | `ServicePortMapping.swift:18`, `AppDatabase.swift:173` |
| `AUTOSAVE_DEBOUNCE_MS` | `800` (`[CLIENT]`) | `ServiceInspectorViewModel+AutoSave.swift:30` |
| `BULK_START_SPACING_MS` | `150` (owned by [06](06-execution-engine.md)) | `ServicesDeckViewModel+ExecutionActions.swift`, `+WorkspaceLoad.swift:73` |
| `RESTART_GAP_MS` | `300` (owned by [06](06-execution-engine.md)) | `ServicesDeckViewModel+ExecutionActions.swift:72` |
| `SERVICE_STOP_TOTAL` | `KumaExecutionTimeouts.serviceStopTotal` then force release (owned by [06](06-execution-engine.md)) | `ServiceStopSupport.swift:6-11` |

### 3.2 Workspaces

#### 3.2.1 `workspace.list`

Params: none. Result: `{ "workspaces": [Workspace] }` ordered `sortOrder ASC, createdAt ASC, rowid ASC` ([01 §3.11.3](01-data-model.md)). There is always at least one element (never-zero rule, [01 §3.8](01-data-model.md): the daemon re-seeds a default workspace if the table is empty at open).

#### 3.2.2 `workspace.get`

Params: `{ "id" }`. Result: `{ "workspace": Workspace }`. Missing → `KUMA_WS_NOT_FOUND`.

#### 3.2.3 `workspace.create` (`WorkspaceStore.addWorkspace`, `WorkspaceStore.swift:85-112`)

Params: `{ "name"?: string, "imageBase64"?: string }`.

1. `trimmed = trim(name ?? "")`; `finalName = trimmed.isEmpty ? "New Workspace" : trimmed`. (The form refuses blank names itself with "Name cannot be empty" ([CLIENT], §3.12); the store-level fallback to `New Workspace` is the parity behavior for the RPC. A *present but blank* `name` therefore yields `New Workspace`; `KUMA_WS_NAME_EMPTY` is reserved for `workspace.update`, DEV-52.)
2. New `id` = random UUID. `sortOrder = <number of workspace rows at transaction time>` (not `max + 1`; gaps left by earlier deletes are never repaired, so duplicate `sortOrder` values are possible and are tie-broken by `createdAt, rowid`).
3. If `imageBase64` is present: decode and store a managed 512 px PNG as `<ID>.png` (§3.3.2); `imagePath = "<ID>.png"`. Image failure → `KUMA_WS_IMAGE_INVALID` and **no workspace is created** (DEV-50). Absent → `imagePath = NULL`.
4. Insert row: `createdAt = updatedAt = now`. Emit `workspace.changed {change:"created"}`.
5. Result `{ "workspace": Workspace }`. Selecting the new workspace is `[CLIENT]` (§3.12, `WorkspaceStore.swift:100`, `WorkspaceFormSheet` calls `selectWorkspace`).

1.x quirk replaced by DEV-50: the form passed a plain absolute path as `imagePath`; `URL(string:)` of such a string is not a file URL, so 1.x stored the **absolute path unchanged** (no managed copy, no resize) instead of saving a copy. The daemon never stores an absolute path it did not receive from legacy data.

Names are **not unique** (duplicates allowed, [01 §3.11.4](01-data-model.md)).

#### 3.2.4 `workspace.update` (`renameWorkspace :114-129`, `updateWorkspace :131-156`, form `saveChanges`)

Params: `{ "id", "name"?, "imageBase64"?, "clearImage"?: bool, "expectedUpdatedAt"? }`.

1. Workspace must exist (`KUMA_WS_NOT_FOUND`); token check (§3.0.4).
2. If `name` present: `trimmed = trim(name)`; empty → `KUMA_WS_NAME_EMPTY` ("Name cannot be empty", exact `WorkspaceFormSheet.swift:125`); else store `trimmed` (DEV-52: 1.x `renameWorkspace` stored the raw string; only the form trimmed).
3. `imageBase64` and `clearImage: true` together → `KUMA_WS_IMAGE_CONFLICT`.
4. `imageBase64` present → replace image (§3.3.3). `clearImage: true` → clear image (§3.3.5). Neither → `imagePath` unchanged.
5. `updatedAt` bumped (§3.0.3). Emit `workspace.changed {change:"updated"}` (plus `"image"` in `changed` if the image changed, §3.9). Result `{ "workspace": Workspace }`.

`workspace.set_image` and `workspace.clear_image` are the image-only forms of the same operation (same validation, same event).

#### 3.2.5 `workspace.delete` (`deleteWorkspace :158-184`)

Params: `{ "id" }`. Result: `{ "deleted": true, "nextWorkspaceId": UUID }`.

Algorithm:

1. Workspace missing → `KUMA_WS_NOT_FOUND`.
2. `workspace count <= 1` → `KUMA_WS_LAST_WORKSPACE`; **nothing** is stopped or deleted (INV-D-WS-01; `WorkspaceStore.swift:160-163` guard).
3. **DEV-03:** for every service of the workspace whose runtime state is operational or `stopping`, call the [06](06-execution-engine.md) stop path (coalesced, with `serviceStopTotal` and force-release fallback) and wait for all of them. Stop failures are logged and do not abort the delete (the stop path always ends in a forced release). 1.x never stopped them (orphans).
4. Transaction: `DELETE FROM workspace WHERE id = ?`. The cascade removes services, providers, port mappings, groups and memberships ([01 §3.11.5](01-data-model.md)). Sort orders of the remaining workspaces are **not** renumbered.
5. After commit: delete the avatar file if `imagePath` names a **managed** file (§3.3.6, DEV-55); drop runtime/activity-log state of every deleted service ([06](06-execution-engine.md), [08](08-logs-and-events.md); 1.x equivalent: `stateStore.removeService`).
6. `nextWorkspaceId` = id of the first remaining workspace in `workspace.list` order. 1.x selected `workspaces.first` only when the deleted workspace was the selected one; the daemon does not know the client selection, so the **client** applies `nextWorkspaceId` only if the deleted workspace was its selected one (and rewrites the preference, [03 §3.9.6](03-settings-and-environment.md); the daemon never rewrites `kuma.selectedWorkspaceId.storage`).
7. Emit, in order: one `service.deleted` per removed service, then `workspace.changed {change:"deleted", workspaceID, nextWorkspaceId}`. No `group.changed` is emitted (implied by `workspace.changed`).

State transitions of §3.2.5 are in table T1 (§3.13).

#### 3.2.6 `workspace.reorder` (`moveWorkspace :186-210`, `WorkspaceRepository.updateSortOrders :42-51`)

Two mutually exclusive forms; supplying both or neither → `KUMA_WS_REORDER_INVALID`.

**Form A (permutation).** `{ "workspaceIDs": [UUID] }`: must contain every workspace id exactly once (any order) else `KUMA_WS_REORDER_INVALID`. Assign `sortOrder = index` (0..n-1) in the given order.

**Form B (1.x swap).** `{ "fromIndex": int, "toIndex": int }` indexes into the current `workspace.list` order. Algorithm exactly as 1.x:

```
guard 0 <= fromIndex < n, 0 <= toIndex < n, fromIndex != toIndex   // otherwise: no-op (no write, no event, success)
list.swapAt(fromIndex, toIndex)                                     // swap, NOT move: A,B,C with (0,2) -> C,B,A
for index in 0..<n: list[index].sortOrder = index; list[index].updatedAt = now
```

Both forms then persist with one transaction of `n` statements `UPDATE workspace SET sortOrder = ?, updatedAt = ? WHERE id = ?` (every row of the list, so `updatedAt` of **every** workspace changes). Result `{ "workspaces": [Workspace] }` (the new order). Event `workspace.changed {change:"reordered"}` only when a write happened. After a successful reorder the `sortOrder` values are exactly `0..n-1` (INV-D-DAT-15). 1.x had no UI caller for `moveWorkspace`; tests TC-C06 (A,B,C swap 0↔2 → C,B,A with `sortOrder` 0,1,2) and TC-E05 (out-of-range = no-op) pin Form B.

#### 3.2.7 Default workspace seed

The seed name rule (`Workspace.defaultName`, [01 §3.8](01-data-model.md)) and the three seeding moments (migration v1, open with zero rows, end of `wipeAndResetDatabase`) are owned by [01](01-data-model.md). This spec adds only: the seeded workspace has `imagePath NULL`, `sortOrder 0`; the daemon exposes it through `workspace.list` like any other.

### 3.3 Workspace image store

Implemented by the daemon as an internal component used by `workspace.*` image methods and by [09](09-dataport.md) (import/export/factory reset). All paths are relative to the data dir ([01 §3.1](01-data-model.md)).

#### 3.3.1 Paths and addressing

- Directory `Workspaces/Images`, created with `create_dir_all` when a write needs it. Failure → `KUMA_WS_IMAGE_IO`. (1.x fell back silently to the temp directory, `WorkspaceImageStore.swift:43-45`, losing the file; the daemon fails instead, consistent with [01 §3.1](01-data-model.md) "MUST NOT fall back".)
- Managed file name: `<UPPERCASE-WORKSPACE-UUID>.png`. `workspace.imagePath` stores the **bare file name** for managed files.
- **Resolution** (`resolveURL :182-187`): `imagePath` starting with `/` is a **legacy absolute path** used as-is for **reading**; any other value is joined to the images directory. A bare name containing `/`, `..` or a NUL is rejected on write and treated as "no image" on read.
- Legacy absolute paths appear only in data written by 1.x (create-with-image quirk, §3.2.3). The daemon reads them but never writes one.

#### 3.3.2 Save from bytes (`saveWorkspaceImage :52-95`, daemon form)

Input: image bytes (decoded from `imageBase64`; standard base64 alphabet with padding, whitespace-tolerant). Algorithm:

1. Decode base64; invalid → `KUMA_WS_IMAGE_INVALID`.
2. Decode the image (any format the decoder supports), applying EXIF orientation (`kCGImageSourceCreateThumbnailWithTransform`). Undecodable → `KUMA_WS_IMAGE_INVALID` (1.x returned `nil`, TC-E03).
3. Downscale so that `max(width, height) <= 512`, preserving aspect ratio, **never upscaling** (`kCGImageSourceThumbnailMaxPixelSize: 512`, `ThumbnailFromImageAlways`).
4. Encode PNG (8-bit RGBA/RGB with alpha retained).
5. Write to a temporary file in the same directory and `rename` over `<ID>.png` (atomic replace, equals `Data.write(options: .atomic)`). **Differences from 1.x (DEV-50):** 1.x deleted the existing destination *before* decoding the source, so a corrupt source destroyed the previous avatar; the daemon decodes and encodes first and replaces only on success, so a failure leaves the old file and DB untouched.
6. Bump the per-path revision (§3.3.7). Return the file name `<ID>.png`.

Rust implementation notes (normative on observable behavior, informative on library choice):

| Need | Options |
|------|---------|
| Decode + EXIF orientation | `image` crate (`ImageReader::with_guessed_format`, `ImageDecoder::orientation`, `DynamicImage::apply_orientation`); formats enabled: PNG, JPEG, GIF, WebP, BMP, TIFF |
| Resize (no upscale) | `image::imageops::resize` with `FilterType::Lanczos3`, or `DynamicImage::thumbnail`; `fast_image_resize` is an acceptable faster alternative |
| PNG encode | `image::codecs::png::PngEncoder` (or the `png` crate) |
| Atomic write | `tempfile::NamedTempFile::new_in(images_dir)` + `persist(dest)` |
| HEIC/HEIF, RAW, PDF (decoded by ImageIO in 1.x) | not supported by the `image` crate; such input returns `KUMA_WS_IMAGE_INVALID`. A client with ImageIO SHOULD transcode to PNG/JPEG before calling (see residual risk 1) |

#### 3.3.3 Replace (`workspace.update` with `imageBase64`, `workspace.set_image`; `updateWorkspace :131-156`)

1. Run §3.3.2 first (failure aborts everything: no file, DB or `updatedAt` change; DEV-50).
2. Update `workspace.imagePath = "<ID>.png"`, bump `updatedAt`.
3. If the previous `imagePath` was a **managed** file with a different name than `<ID>.png`, delete it after commit (§3.3.6). A previous legacy absolute path is **never deleted** (DEV-55); it is simply no longer referenced.

(1.x order was: delete old file, save new, set `imagePath` to the result which may be `nil` on failure, so a failed replace silently lost the avatar.)

#### 3.3.4 Thumbnail read (`workspace.get_image`; `thumbnail(for:maxDimension:) :127-160`)

Params: `{ "id", "size"?: int }`. `size` defaults to `128` and is clamped to `1...1024`; it is the **maximum side in pixels** of the returned image.

1. Workspace missing → `KUMA_WS_NOT_FOUND`.
2. If `imagePath` is NULL, or the resolved file is missing, unreadable or not decodable → success with `{ "hasImage": false }` (1.x returned `nil`; the UI then shows initials, §3.12). This is not an error.
3. Otherwise read the file **from bytes** (so a replaced file is never served stale, `:140`), decode with orientation, downscale to `max(w,h) <= size` without upscaling, encode PNG.
4. Result `{ "hasImage": true, "mimeType": "image/png", "imageBase64": "<base64>", "width": int, "height": int }`.

Avatar views request `size * 2` points as pixels (`IMAGE_THUMB_REQUEST_FACTOR`); that factor is client behavior.

#### 3.3.5 Clear (`workspace.clear_image`; form: both `imagePath` and the picked URL nil, `WorkspaceFormSheet.saveChanges`)

1. Set `imagePath = NULL`, bump `updatedAt` (always, even when already NULL).
2. After commit, delete the previous file if it was **managed** (§3.3.6). Success even when no file existed.

#### 3.3.6 Delete rules

`deleteImage` in 1.x was a best-effort `removeItem` of the *resolved* path (errors ignored). The daemon deletes **only files inside `Workspaces/Images`** (DEV-55): a legacy absolute `imagePath` is never removed, because in 1.x that path is the user's original photo (the create-with-image quirk stored it) and `deleteWorkspace` would have deleted it. Deletion is best-effort (errors logged, not surfaced) and bumps the revision (§3.3.7). Triggers: `workspace.delete`, `workspace.clear_image`, replace with a differently-named previous managed file, and factory reset (`Workspaces/Images` removed as a whole directory by [09](09-dataport.md); the next write recreates it).

#### 3.3.7 Cache and revision semantics

The daemon MAY cache decoded thumbnails; if it does, the key is `"<resolved path>-<size>-r<revision>"` and the capacity is `IMAGE_CACHE_COUNT_LIMIT` entries, where `revision` is a per-path counter (starting at 0) incremented on every save, base64 import and delete of that path, and reset to empty by `clearCache` (factory reset). Normative observable rule: after any write or delete of an avatar file, the next `workspace.get_image` for any `size` reflects the new file (INV-D-WS-07).

#### 3.3.8 Raw base64 import/export (internal API for [09](09-dataport.md); `saveBase64Image :98-111`, `loadBase64Image :114-122`)

- `import_raw(workspaceID, base64) -> file name | none`: standard-base64 decode (invalid → none, no file written); write the **raw decoded bytes** (no decode, no resize, no validation) to `<ID>.png` with an atomic replace; bump revision. [09](09-dataport.md) calls it **before** the DB write and overwrites `imagePath` with the returned name; none → `imagePath` NULL.
- `export_raw(imagePath) -> base64 | none`: resolve (§3.3.1), none if the file is missing/unreadable, else base64 of the raw file bytes (standard alphabet, no line breaks).
- A raw-imported file may not be a decodable image; `workspace.get_image` then returns `hasImage: false` (§3.3.4 step 2).

### 3.4 Groups

Group rows are `service_group` ([01 §4.2](01-data-model.md)); membership is `service_group_membership` only (legacy `service.groupID` ignored, [01 §3.11.6](01-data-model.md)). Groups are scoped by `workspaceID` (required, immutable).

#### 3.4.1 `group.list`

Params: `{ "workspaceID" }`. Result `{ "groups": [ServiceGroup] }` ordered `sortOrder ASC, createdAt ASC, rowid ASC`. Unknown workspace → `[]`.

#### 3.4.2 `group.create` (`addGroup :42-67`)

Params: `{ "workspaceID", "name"?: string }`.

1. Workspace missing → `KUMA_WS_NOT_FOUND`.
2. `name` absent, null or blank after trim → `New Group`; else the trimmed name (DEV-52: 1.x did not trim on create but its UI only ever passed the literal `New Group`; tests accept a 300-character name and emoji verbatim, and trimming does not alter those).
3. `sortOrder = (max(sortOrder) over the workspace's groups ?? 0) + 1`: the first group of a workspace gets `1`. No renumbering happens at create (so deleting a group leaves gaps; contiguity `0..n-1` holds only after `group.reorder`, INV-SIDEBAR-05, §3.4.5).
4. `createdAt = updatedAt = now`. Emit `group.changed {change:"created", groupID}`. Result `{ "group": ServiceGroup }`.
5. Client-only follow-ups in 1.x (select the new group, begin inline rename, expand the "Groups" node) are `[CLIENT]` (§3.12).

#### 3.4.3 `group.update` (`renameGroup :69-92`)

Params: `{ "id", "name", "expectedUpdatedAt"? }`. `trimmed = trim(name)`; empty → `Untitled Group` (**not** an error); store `trimmed`; bump `updatedAt`. Group missing → `KUMA_GRP_NOT_FOUND`. `workspaceID` cannot be changed. Emit `group.changed {change:"updated", groupID}`. Result `{ "group": ServiceGroup }`.

#### 3.4.4 `group.delete` (`deleteGroup :94-114`)

Params: `{ "id" }`. Result `{ "deleted": true }`. Deletes the row; memberships cascade ([01 §3.11.5](01-data-model.md)); **services are never deleted or modified** (INV-SIDEBAR-03, INV-D-GRP-02). Sort orders of the remaining groups are not renumbered. Missing → `KUMA_GRP_NOT_FOUND`. Emit `group.changed {change:"deleted", groupID}` only. Clients refetch `service.list` on `group.changed` because member services' `groupIDs` changed (1.x deck did not refresh member snapshots here; a stale snapshot in 1.x is not reproduced). Selecting "All Services" when the deleted group was selected is `[CLIENT]` (`SidebarViewModel+Groups.swift:99-103`).

#### 3.4.5 `group.reorder` (`moveGroups :5-26`, `ServiceGroupRepository.updateSortOrders :42-51`)

Params: `{ "workspaceID", "groupIDs": [UUID] }`: a permutation of **all** groups of the workspace (else `KUMA_GRP_REORDER_INVALID`). Assign `sortOrder = index` (0..n-1) and `updatedAt = now` to every group in one transaction of `n` statements `UPDATE service_group SET sortOrder = ?, updatedAt = ? WHERE id = ?`. Result `{ "groups": [ServiceGroup] }`. Emit `group.changed {change:"reordered"}` (no `groupID`).

The three client gestures compute the permutation with SwiftUI `Array.move(fromOffsets:toOffset:)` semantics (`SidebarViewModel+Reorder.swift`); these are `[CLIENT]` but normative for behavioral parity of clients:

| Gesture | Precondition | `toOffset` passed to `move(fromOffsets: [index], toOffset:)` |
|---------|--------------|--------------------------------------------------------------|
| Move Up (`moveGroupUp`, `canMoveGroupUp`) | `index > 0` | `index - 1` |
| Move Down (`moveGroupDown`, `canMoveGroupDown`) | `index < count - 1` | `index + 2` |
| Drag onto target (`reorderGroup(draggedID, targetID)`) | ids differ and both exist, else no-op | `toIndex > fromIndex ? toIndex + 1 : toIndex` |

Drag payload is the group UUID string; a non-UUID payload is rejected by the client.

#### 3.4.6 Membership (many-to-many)

A service belongs to zero or more groups; a group contains zero or more services; unique per `(serviceID, groupID)`. A membership may only connect a service and a group of the **same workspace** (DEV-54: 1.x only had FK integrity; its UI could never offer a foreign group). Violations → `KUMA_GRP_WORKSPACE_MISMATCH`; a missing group → `KUMA_GRP_NOT_FOUND`. Removing a membership never validates the workspace (so legacy cross-workspace rows can be removed). The RPCs are `service.set_groups` and `service.toggle_group` (§3.5.9, §3.5.10) and the optional `groupIDs` of `service.create` / `service.update`.

### 3.5 Services

#### 3.5.1 `service.list` (the deck query)

Specified in §3.7.

#### 3.5.2 `service.get` (`fetchServiceDetail :17-43`, [01 §4.11](01-data-model.md))

Params: `{ "id" }`. Result (single read transaction, TC-C01):

```json
{
  "service": { "id": "…", "name": "Postgres DB", "workspaceID": "…", "groupIDs": ["…"], "isDisabled": false, "isStarred": false, "createdAt": "…", "updatedAt": "…" },
  "providers": [ { "id": "…", "serviceID": "…", "type": "docker", "…": "…", "sshPasswordSet": false, "ngrokAuthTokenSet": false, "displayName": "Docker", "resolvedTarget": "Docker: pg:16", "isAutoReconnectEnabled": false } ],
  "portMappings": [ { "id": "…", "serviceID": "…", "providerID": "…", "localPort": 5432, "remotePort": 5432, "protocolType": "TCP" } ],
  "activeProviderID": "…",
  "runtime": { "status": "stopped", "isLoading": false, "statusTitle": "Stopped" },
  "liveTarget": null
}
```

- `providers`: `createdAt ASC, rowid ASC`; kubernetes providers have the read-time defaults applied (`kubeTargetType` NULL/empty → `pod`, `usePattern` NULL → `true`, [01 §3.14.3](01-data-model.md)); secrets redacted (§3.0.8).
- `portMappings`: **filtered** by [01 §3.11.2](01-data-model.md) for the effective active provider, `rowid ASC`.
- `activeProviderID`: the **effective** one (possibly absent when the service has no provider).
- `runtime`: the three keys of [01 §4.9](01-data-model.md) from the [06](06-execution-engine.md) runtime store (`stopped` for unknown services). `liveTarget`: the ephemeral resolved Kubernetes resource name of a running kubernetes service, else absent (owned by [06](06-execution-engine.md)/[07](07-kubernetes.md); 1.x `KubeLiveTargetDisplay`).
- `service.description` is omitted when NULL; `service.activeProviderID` (the **stored** value) is also returned inside `service` when non-NULL.
- Missing → `KUMA_SVC_NOT_FOUND` (message `Service not found: <id>`).

#### 3.5.3 `service.create` (`CreateServicePayloadBuilder.buildPayload`, `ServiceRepository.insertService :104-122`, `CreateServiceSaving.save`)

Params:

```json
{
  "workspaceID": "…",
  "name": "Postgres DB",
  "description": "optional",
  "isDisabled": false,
  "isStarred": false,
  "groupIDs": ["…"],
  "provider": { "type": "ssh", "label": "…", "…": "fields of 05" },
  "ports": [ { "localPort": 2222, "remotePort": 22, "protocolType": "TCP" } ]
}
```

1. Workspace must exist (`KUMA_WS_NOT_FOUND`).
2. `name = trim(name)`; empty → `KUMA_SVC_NAME_EMPTY` (the 1.x form disables Create when the trimmed name is empty, `CreateServicePayloadBuilder.isFormValid :102`, DEV-52).
3. `description = trim(description)`; empty → NULL (`CreateServicePayloadBuilder.swift:14-15`).
4. `isDisabled` default `false` (`generalDraft.isDisabled`). `isStarred` default `false`: this is `starOnCreate`; the client sets it when the sidebar selection is "Starred" (§3.12, `ContentView.createServiceDefaultsForCurrentSidebar`).
5. `groupIDs` default `[]`: this is `initialGroupID` (client passes `[groupID]` when a group row is selected). Each id must exist in the same workspace (DEV-54).
6. `provider` is built and validated by [05](05-providers-and-validation.md) (per-category required fields = `isFormValid`, URL normalization, kubernetes defaults, SSH credential normalization, secret encryption). Required: exactly one provider at create time. The provider gets a fresh `id`, `serviceID = service.id`, `createdAt = updatedAt = now`.
7. `ports`: each entry must satisfy `1 <= port <= 65535` for both ports (`KUMA_SVC_INVALID_PORT`, DEV-56; entries are never silently dropped by the daemon, the 1.x client-side filter is `[CLIENT]`, §3.10). Every mapping is stored with `serviceID = service.id` and `providerID = provider.id` (1.x: NULL `providerID` → default provider id; the daemon always sets it, INV-D-DAT-09), `protocolType` default `TCP`, new `id` (a supplied `id` is honored unless it collides, in which case a fresh UUID is generated for the duplicate within the batch). The 1.x form only offers ports for kubernetes and ssh; the daemon stores whatever is supplied.
8. One transaction: insert service (`createdAt = updatedAt = now`, `activeProviderID` **NULL**, see below), provider, mappings, one membership row per group (`createdAt = now`).
9. Emit `service.created {serviceID, workspaceID}`. Result: the same object as `service.get` (§3.5.2).

`activeProviderID` stays **NULL** on create (1.x `buildPayload` never set it and `insertService` does not repoint it); the effective active provider is the first (only) provider. It becomes non-NULL on `provider.add` or `service.switch_provider`.

#### 3.5.4 `service.update` (`ServiceRepository.updateService :124-137`; inspector `commitChanges`)

Params: `{ "id", "name"?, "description"?, "icon"?, "colorHex"?, "groupIDs"?, "expectedUpdatedAt"? }`.

- Service must exist (`KUMA_SVC_NOT_FOUND`); token check (§3.0.4).
- `name`: stored **verbatim** (1.x inspector writes whatever was typed, including an empty string; there is no trimming or validation in the update path, `InspectorConfigFormStack.swift:44-50`).
- `description`: the empty string `""` is stored as NULL (`$0.isEmpty ? nil : $0`, `InspectorConfigFormStack.swift:54`); other values verbatim (not trimmed); `null` clears.
- `icon`, `colorHex`: free text, no 1.x UI; stored verbatim, `null` clears.
- `groupIDs`: if **present**, the membership set is replaced: delete all memberships of the service, insert each given id with `createdAt = now` (membership `createdAt` is reset, [01 §3.11.7](01-data-model.md)); duplicates ignored; DEV-54 validation. If **absent**, memberships are untouched (1.x always rewrote them from the in-memory set; the daemon never overwrites memberships a client did not mention).
- The fields `isStarred`, `isDisabled`, `activeProviderID`, `workspaceID`, `id`, `createdAt`, `updatedAt` are **not** updatable here; supplying one fails with `KUMA_SVC_FIELD_READONLY` naming the right method (`service.set_starred`, `service.set_disabled`, `service.switch_provider`; `workspaceID`/`id`/`createdAt`/`updatedAt` have no method). This keeps the stop-on-disable and stop/restart-on-switch side effects unavoidable.
- `updatedAt` is bumped even for an empty patch. Emit `service.updated {serviceID, workspaceID, changed:["service"]}` (add `"memberships"` when `groupIDs` was present). Result `{ "service": Service }`.

#### 3.5.5 `service.delete` (`ServicesDeckViewModel.deleteService :202-222`, inspector `deleteService :165-173`)

Params: `{ "id" }`. Result `{ "deleted": true }`.

1. Missing → `KUMA_SVC_NOT_FOUND`.
2. **DEV-14:** if the service's runtime state is operational or `stopping`, stop it through [06](06-execution-engine.md) and wait (1.x only disabled the Delete button while running; the deck context-menu "Delete" had no running guard at all, so the process was orphaned).
3. Transaction: `DELETE FROM service WHERE id = ?`. Providers, port mappings and memberships cascade; groups are untouched ([01 §3.11.5](01-data-model.md)).
4. After commit: purge runtime state, activity-log buffer and the live Kubernetes target of the service ([06](06-execution-engine.md), [08](08-logs-and-events.md); 1.x `stateStore.removeService`).
5. Emit `service.deleted {serviceID, workspaceID}`. The confirmation dialog is `[CLIENT]` (§3.12).

#### 3.5.6 `service.duplicate` (`duplicateService :208-285`; deck `duplicateService :136-173`)

Params: `{ "id" }`. Result: the `service.get` object (§3.5.2) of the **new** service. Source missing → `KUMA_SVC_NOT_FOUND` with the exact 1.x text `Source service not found` (1.x: `NSError(domain: "lokastudio.kuma", code: 404, …)`). One transaction:

1. New service id = random UUID. Copy the service row: `name = "\(source.name) (Copy)"` (appended to the stored name, not trimmed), `createdAt = updatedAt = now`, `workspaceID` same, `isDisabled` and `isStarred` **preserved**, `icon`, `colorHex`, `description` copied, `activeProviderID` set below.
2. Copy every provider (ordered `createdAt ASC, rowid ASC`) with a new random UUID, `serviceID = new id`, `createdAt = updatedAt = now`, all other columns copied, secrets carried over (decrypted and re-encrypted with a fresh nonce, [02](02-security-and-secrets.md)). Build the map `oldProviderID → newProviderID`.
3. New `activeProviderID`: the copy of the provider whose **old** id equals `source.activeProviderID`; if there is none (NULL, dangling, or not among the source's providers) the **first copied provider**; NULL when the source has no provider. (`ServiceRepository+CRUD.swift:231-253`; note: a source with NULL `activeProviderID` therefore yields a copy with a **non-NULL** `activeProviderID`.)
4. Copy **all** port mappings of the source (unfiltered): new id, `serviceID = new id`, `protocolType` copied, `providerID = map[old providerID]`; if the old `providerID` is NULL or unmapped, use the new active provider id; **skip** the mapping if there is none.
5. Copy memberships (`createdAt = now`).
6. Runtime state of the copy is `stopped`; nothing is started. Emit `service.created {serviceID: <new id>, workspaceID}`.

#### 3.5.7 `service.set_starred` (`toggleStarred :45-55`; deck `:6-21`; inspector `:133-147`)

Params: `{ "id", "starred"?: bool, "expectedUpdatedAt"? }`. `starred` absent → toggle (`isStarred = !isStarred`, 1.x behavior); present → set to that value. Always bumps `updatedAt` (1.x toggle set `updatedAt = now`). Missing service → `KUMA_SVC_NOT_FOUND` (1.x returned `false` silently, DEV-57). Emit `service.updated {changed:["service"]}`. Result `{ "service": Service }`.

#### 3.5.8 `service.set_disabled` (deck `toggleDisabled :23-58`; inspector `toggleDisabled :149-163`)

Params: `{ "id", "disabled": bool, "expectedUpdatedAt"? }`.

1. Missing → `KUMA_SVC_NOT_FOUND`; token check.
2. Transaction: `isDisabled = disabled`, `updatedAt` bumped (full-row `updateService` in 1.x, memberships rewritten with the same set; the daemon touches no memberships).
3. **DEV-51:** if `disabled == true` and the service is operational (`starting`, `running`, `reconnecting`), stop it through [06](06-execution-engine.md) after the flag is committed and wait; its runtime state ends `stopped`. 1.x only set the UI state to idle (`stateStore?.setExecutionState(.idle, …)`) and left the process running unsupervised, and the inspector toggle was disabled while running.
4. Meaning of the flag: a disabled service **cannot be started** by bulk actions (excluded from `service.start_all`, §3.8) and the deck shows a lock instead of the toggle (`CardToggleSwitch`); direct `service.start` behavior for disabled services is defined by [06](06-execution-engine.md). The Start item of the context menu is disabled for disabled services (`[CLIENT]`).
5. Emit `service.updated {changed:["service"]}`; the stop emits `service.state_changed` ([08](08-logs-and-events.md)). Result `{ "service": Service }`.

The status bucket `disabled` of `service.list` filters by this flag (§3.7.3).

#### 3.5.9 `service.set_groups`

Params: `{ "id", "groupIDs": [UUID] }`. Replaces the membership set (delete all, insert each with `createdAt = now`; duplicates ignored). Validation: DEV-54. Does **not** touch `service.updatedAt` (consistent with toggle, [01 §3.11.7](01-data-model.md)). Result `{ "id", "groupIDs": [UUID sorted ascending] }`. Emit `service.updated {changed:["memberships"]}`.

#### 3.5.10 `service.toggle_group` (`toggleGroupMembership :180-199`; deck `toggleGroup :95-133`)

Params: `{ "id", "groupID" }`. If the pair exists delete it, else insert it (`createdAt = now`; DEV-54 validation applies to the insert only). Does **not** touch `service.updatedAt`. Result `{ "id", "groupIDs": [UUID sorted ascending] }` (the full resulting set, as 1.x returned). Missing service/group → `KUMA_SVC_NOT_FOUND` / `KUMA_GRP_NOT_FOUND`. Emit `service.updated {changed:["memberships"]}`.

#### 3.5.11 `service.switch_provider` (deck `:61-92`; inspector `+Providers.swift:5-56`)

Params: `{ "id", "providerID", "expectedUpdatedAt"? }`. Result:

```json
{ "service": { "…": "Service" }, "activeProviderID": "…", "changed": true,
  "restart": { "attempted": true, "started": false, "error": { "code": "KUMA_…", "message": "…" } } }
```

(`restart.error` present only on failure; `restart.attempted` false when the service was not operational.) Algorithm (table T2 in §3.13):

1. Service missing → `KUMA_SVC_NOT_FOUND`. `providerID` must be a provider **of this service** else `KUMA_SVC_PROVIDER_NOT_FOUND` (DEV-53: neither 1.x path validated).
2. If `providerID` equals the effective active provider: success, `changed:false`, no write, no event, no stop (the inspector guard `providerID != activeProviderID`; the deck had none and would have restarted needlessly, DEV-53).
3. `wasRunning = runtime state is operational` (`starting`, `running` or `reconnecting`; `isOperational`). Flushing pending inspector edits before the call is `[CLIENT]` (`flushPendingAutoSave`, `:10`).
4. If `wasRunning`: stop through [06](06-execution-engine.md) (state `stopping`, then `stopped`; coalesced; `serviceStopTotal` + force release).
5. Transaction: `service.activeProviderID = providerID`, `updatedAt` bumped. Failure here → the RPC fails (`KUMA_DAT_*`), the service stays stopped (1.x `clearStoppingIfStillPending`), no restart.
6. Emit `service.updated {changed:["activeProvider"]}`.
7. If `wasRunning`: start through the [06](06-execution-engine.md) user-initiated start path (identical to `service.start`, including its configuration validation and port-conflict policy). On failure the runtime state becomes `crashed(exitCode: 1)` with the failure message recorded as the last failure (`ServiceStartSupport.applyUserStartFailure`, `ServiceStartSupport.swift:41-52`) and `restart.error` carries the error; **the RPC itself succeeds** because the switch was committed. The inspector's pre-start `validateConfigurationForStart` that left the service merely stopped (with an issue banner) is replaced by this single path (DEV-53); a client that wants the banner calls `service.preflight` ([05](05-providers-and-validation.md)) first.
8. Result per above; `restart.started = true` after a successful start.

#### 3.5.12 Inspector auto-save commit shape

The 1.x inspector commits through three repository calls (`ServiceInspectorViewModel+AutoSave.swift:41-89`), non-atomic, each a separate transaction. In the daemon the same shape is three RPCs issued by the client; the daemon contract per call is in §3.5.4, §3.6.3, §3.6.5:

| Step | 1.x call | Daemon call | Always? |
|------|----------|-------------|---------|
| 1 | `updateService(srv)` with `updatedAt = now` (also rewrites memberships from `srv.groupIDs`) | `service.update` (name/description/…; send `groupIDs` only if the user changed memberships) | yes |
| 2 | `updateProvider(activeProv.withKubernetesDefaults())` after SSH normalization (`ProviderSSHAuth.normalizeForPersistence`) and kube config/context sync | `provider.update` for the **active** provider (SSH normalization and kubernetes defaults are applied by the daemon, [05](05-providers-and-validation.md), [01 §3.14.3](01-data-model.md)) | yes |
| 3 | `savePortMappings(realPorts, forService:, providerID: active.id)` | `provider.set_ports` | **only if `portsDraftDirty`** (the user touched the port rows; when ports were not edited existing mappings are preserved, TC-C13) |

`[CLIENT]`: the 800 ms debounce (`AUTOSAVE_DEBOUNCE_MS`), the revision counters (`pendingSaveRevision`/`lastCommittedRevision`), the flush on dismiss and before provider switch (TC-E01, TC-E01b), cancelling on service change, and the port-row filter `Int(trimmed local) > 0 && Int(trimmed remote) > 0` with protocol `"TCP"` and `providerID = active provider` (rows failing the filter are dropped before the call). The client keeps the `updatedAt` returned by each call as the next `expectedUpdatedAt`.

### 3.6 Providers (rows of a service)

Provider fields, per-category rules, URL normalization, SSH credential normalization and secret encryption are [05](05-providers-and-validation.md) and [02](02-security-and-secrets.md); the entity is [01 §4.4](01-data-model.md). This section defines orchestration, active-provider maintenance and ports.

#### 3.6.1 `provider.list`

Params: `{ "serviceID" }`. Result `{ "providers": [Provider], "activeProviderID": UUID? }`: `createdAt ASC, rowid ASC`; kubernetes read-time defaults applied; secrets redacted; each provider carries the derived members `displayName`, `resolvedTarget`, `isAutoReconnectEnabled` ([01 §3.14.1](01-data-model.md)); `activeProviderID` is the **effective** one. Service missing → `KUMA_SVC_NOT_FOUND`.

#### 3.6.2 `provider.add` (`addProvider :58-95`)

Params: `{ "serviceID", "provider": { "type", "label"?, … }, "expectedUpdatedAt"? }` (`expectedUpdatedAt` is the **service** token).

1. Service missing → `KUMA_SVC_NOT_FOUND`; token check on the service.
2. Build the provider per [05](05-providers-and-validation.md) (a kubernetes provider persists `kubeTargetType`/`usePattern` defaults, [01 §3.14.3](01-data-model.md)); new `id`, `serviceID`, `createdAt = updatedAt = now`.
3. One transaction: insert the provider; set `service.activeProviderID = provider.id` (**the added provider becomes active**) and bump `service.updatedAt`. No port mappings are created (the inspector's empty port row for kubernetes/ssh is client state, `+Providers.swift:77-81`); the client uses `provider.set_ports`.
4. Emit `service.updated {changed:["providers","activeProvider"]}`. Result `{ "provider": Provider, "service": Service, "activeProviderID": UUID }`.

The daemon does not stop a running service when its active provider changes this way (the 1.x inspector was locked while running, `[CLIENT]`, residual risk 9).

#### 3.6.3 `provider.update` (`updateProviderDirectly :97-109`; commit step 2)

Params: `{ "id", "<provider fields>"…, "expectedUpdatedAt"? }`. Provider missing → `KUMA_SVC_PROVIDER_NOT_FOUND`. `id`, `serviceID`, `createdAt` are immutable. Field semantics (partial update, secret handling, normalization, `type` handling) are [05](05-providers-and-validation.md); this spec fixes: `provider.updatedAt` is bumped (DEV-22), the **service row is not touched**, kubernetes providers persist the kubernetes defaults, and the whole row is rewritten as in 1.x (`update` rewrites every column, [01 §3.11.7](01-data-model.md)). Emit `service.updated {changed:["providers"]}` for the owning service. Result `{ "provider": Provider }`.

#### 3.6.4 `provider.delete` (`deleteProvider :111-131`, [01 §3.11.1](01-data-model.md))

Params: `{ "id", "expectedUpdatedAt"? }` (service token).

1. Provider missing → `KUMA_SVC_PROVIDER_NOT_FOUND`.
2. If the service has exactly one provider → `KUMA_SVC_LAST_PROVIDER` (DEV-58: the 1.x UI hid the delete action when `providers.count <= 1`, `ServiceProvidersListView.swift:38`).
3. One transaction (1.x used two non-atomic steps): delete the provider (its port mappings cascade; legacy NULL-provider mappings are untouched); **if the deleted provider was the effective active provider**, set `service.activeProviderID = <remaining providers ordered createdAt ASC, rowid ASC>.first.id` and bump `service.updatedAt`. If it was not the effective active provider the service row is left unchanged (a dangling stored `activeProviderID` is not repaired).
4. Emit `service.updated {changed:["providers"]}` (add `"activeProvider"` when repointed). Result `{ "deleted": true, "activeProviderID": UUID }`.

#### 3.6.5 `provider.set_ports` (`savePortMappings :157-178`)

Params: `{ "serviceID", "providerID", "ports": [ { "id"?, "localPort": int, "remotePort": int, "protocolType"?: string } ] }`.

1. Service missing → `KUMA_SVC_NOT_FOUND`; the provider must belong to the service else `KUMA_SVC_PROVIDER_NOT_FOUND`.
2. Validate every row: both ports integers with `1 <= p <= 65535`; the first failing row (1-based `N`) → `KUMA_SVC_INVALID_PORT`, nothing is written (DEV-56). Duplicate local ports within the batch are allowed (conflicts are a runtime concern, [06](06-execution-engine.md)). An empty `ports` array is valid and clears the provider's mappings.
3. One transaction: `DELETE FROM portMapping WHERE serviceID = ? AND providerID = ?` (rows with NULL `providerID`, i.e. legacy rows, are never deleted); then insert each row with **forced** `serviceID` and `providerID`, `protocolType` default `TCP`; an `id` that repeats within the batch gets a fresh UUID for the repeat (`:166-175`); an `id` that collides with a row of another provider fails with `KUMA_DAT_CONSTRAINT_VIOLATION` ([01 §3.11.4](01-data-model.md)).
4. No `updatedAt` is touched and no token is taken (last write wins, [01](01-data-model.md) residual 7). Emit `service.updated {changed:["ports"]}`. Result `{ "portMappings": [ServicePortMapping] }` (the provider's rows in `rowid ASC`).

Visibility of the stored rows to the deck/inspector follows [01 §3.11.2](01-data-model.md); in particular a service whose mappings are all legacy keeps showing them for any active provider until the first non-NULL-provider mapping exists.

### 3.7 Deck query: `service.list`

Replaces `fetchDeckItems` + `ServicesDeckViewModel.recomputeFilteredSnapshots` ([06](06-execution-engine.md) obtains the bulk target set from the same function, §3.8).

#### 3.7.1 Parameters

| Param | Type | Default | Meaning |
|-------|------|---------|---------|
| `workspaceID` | UUID | required | Workspace to list. Unknown → empty result |
| `search` | string | `""` | Free text (§3.7.2) |
| `starredOnly` | bool | `false` | Keep only `isStarred` services |
| `groupID` | UUID | none | Keep only members of that group |
| `statuses` | array of `running`, `stopped`, `crashed`, `disabled` | `[]` | Status buckets (§3.7.3); empty = no filter |
| `providers` | array of `ProviderCategory` raw values | `[]` | Keep services whose **active** provider category is in the set; empty = no filter |
| `sort` | `name`, `status` or `created` | none | Sort (§3.7.4); absent = repository order |

Invalid enum values → `KUMA_DAT_INVALID_ENUM`. The 1.x UI raw values of the sort enum are `Name`, `Status`, `Date Created` (`ServiceSortOption`); the wire values are the lowercase tokens above (the 1.x default in the view-model is `name`; choosing it is `[CLIENT]`).

Result: `{ "items": [ServiceListItem], "totalCount": int }`. `totalCount` is the number of services in the workspace **before** any filter (lets a client choose between the empty states "No Services Yet" and "No Services Found", §3.12). The base order, before sorting, is `createdAt ASC, rowid ASC` ([01 §3.11.3](01-data-model.md)).

#### 3.7.2 Search

For each service the daemon builds `searchKey` (`ServiceCardSnapshot.deckSearchKey :114`): the following parts joined with a single space `" "`, then lowercased (Unicode lowercase mapping):

1. `trim(name)`
2. `trim(description)` **if non-empty** after trim
3. `trim(resolvedTarget)` **if non-empty** after trim (`resolvedTarget` of the active provider, [01 §3.14.1](01-data-model.md); for kubernetes this is the configured pattern/name `k8s: <targetName>`, never the live name)
4. `activeProviderCategory.sidebarLabel` (`Docker`, `Kubernetes`, `Podman`, `Shell`, `SSH`, `Health Check`, `Tunnel`, `Process Monitor`, [01 §3.18.1](01-data-model.md))
5. for each provider option in provider order: `trim(label)` **if non-empty** (the raw label, without the category fallback)
6. for each local port of the active provider: its plain decimal text (`8080`, no grouping)

`query = lowercase(trim(search))`. An empty query matches everything. Otherwise a service matches when `searchKey` **contains** `query` as a substring (comparison on NFC-normalized text), **or** when `activeProviderCategory == kubernetes`, a live Kubernetes target name exists for the service, and `lowercase(liveTarget)` contains `query` (`matchesSearchQuery :64`). The live-target alternative is evaluated at query time (it is not part of the key).

#### 3.7.3 Filters, applied in this order (`+Filtering.swift:22-66`)

1. `starredOnly`: drop services with `isStarred == false`.
2. `groupID`: drop services whose `groupIDs` does not contain it.
3. search (§3.7.2).
4. `statuses` (if non-empty): a **disabled** service is kept iff `disabled` is in the set (its runtime status is ignored). Otherwise the runtime status is mapped to a bucket and kept iff the bucket is in the set:

| Runtime `status` ([01 §3.18.2](01-data-model.md)) | Bucket |
|---------------------------------------------------|--------|
| `running`, `starting`, `reconnecting` | `running` |
| `stopped`, `stopping` | `stopped` |
| `crashed` | `crashed` |

   A service unknown to the runtime store has status `stopped`.
5. `providers` (if non-empty): keep iff the active provider category is in the set.

Filters 3 and 4 depend on live runtime (`liveTarget`, status). A client that has them active re-issues `service.list` on `service.state_changed` (1.x re-ran the filter in `notifyExecutionStatesChanged` only when search text, a status filter or the status sort was active, TC-E05b; with none active the client does nothing, TC-E05, TC-E05c).

#### 3.7.4 Sort (`+Filtering.swift:67-86`)

| `sort` | Order |
|--------|-------|
| absent | repository order (`createdAt ASC, rowid ASC`) |
| `name` | `name` ascending by **localized case-insensitive comparison** (`localizedCaseInsensitiveCompare`): Unicode Collation (CLDR root/process locale) at secondary strength, i.e. case ignored, accents significant, digits and punctuation per the collation; ties keep the base order (stable) |
| `status` | `priority` ascending, then `name` as in `name`; `priority = 5` for a disabled service, otherwise `ServiceState.sortPriority` of the runtime status: `running 0, starting 1, reconnecting 2, stopping 3, crashed 4, stopped 5`; ties keep base order |
| `created` | `createdAt` **descending** (newest first); ties keep base order |

Rust: `icu_collator` (ICU4X) with `Strength::Secondary` for `name`.

#### 3.7.5 `ServiceListItem` (DTO)

The keys of `ServiceDeckItem` ([01 §4.8](01-data-model.md)) plus derived card fields:

| Field (JSON key) | Type | Optional | Default | Source / rule |
|------------------|------|----------|---------|---------------|
| `id` | UUID | no | | `service.id` |
| `name` | string | no | | `service.name` (verbatim) |
| `groupIDs` | UUID[] sorted ascending | no | `[]` | memberships |
| `isDisabled` | bool | no | false | |
| `isStarred` | bool | no | false | |
| `activeProviderCategory` | `ProviderCategory` | no | `docker` | [01 §3.11.1](01-data-model.md) (`docker` when the service has no provider) |
| `resolvedTarget` | string | no | `""` | [01 §3.14.1](01-data-model.md) |
| `serviceDescription` | string | yes | omitted | `service.description` (raw) |
| `localPorts` | int[] | no | `[]` | [01 §3.11.2](01-data-model.md), `rowid ASC` |
| `providerOptions` | array | no | `[]` | provider order; each `{id, category, label, isActive, displayLabel}`: `label` raw trimmed (`""` when unset, [01](01-data-model.md)), `isActive` per [01 §3.11.1](01-data-model.md), **`displayLabel`** = `label` if non-empty else `category.sidebarLabel` (the card's `ProviderOption.label`) |
| `createdAt` | timestamp | no | | `service.createdAt` |
| `subtitle` | string | no | `""` | `trim(description)` if non-empty, else `trim(resolvedTarget)` if non-empty, else `""` (`ServiceCardSnapshot`) |
| `displaySubtitle` | string | no | | kubernetes with a live target name: `k8s: <liveTarget>`; else `subtitle` if non-empty; else `activeProviderCategory.sidebarLabel` |
| `liveTarget` | string | yes | omitted | live resolved Kubernetes name from [06](06-execution-engine.md)/[07](07-kubernetes.md), only while known |
| `runtime` | object | no | idle | `{status, isLoading, statusTitle}` of [01 §4.9](01-data-model.md) from the [06](06-execution-engine.md) store |

`subtitle`, `displaySubtitle`, `displayLabel` and `liveTarget` are derived convenience fields (ADD-59). `searchKey` is internal and not returned. No pagination exists (1.x loaded the whole workspace).

### 3.8 Bulk-action target set (consumed by [06](06-execution-engine.md))

`bulkActionSnapshots = filteredSnapshots` in 1.x: bulk actions act on **what the deck currently shows**, including its search/status/provider/group/starred filters, in the **sorted order** shown. Normative definition for the daemon:

```
BulkTargets(workspaceID, filters, sort) = items returned by service.list(workspaceID, search, starredOnly, groupID, statuses, providers, sort)
StartTargets = [ i in BulkTargets  where  !i.isDisabled  and  !operational(i.runtime.status) ]    // start order = list order
StopTargets  = [ i in BulkTargets  where  operational(i.runtime.status) ]
canStartAll  = StartTargets is not empty;   canStopAll = StopTargets is not empty
operational(status) = status in { starting, running, reconnecting }
```

`service.start_all` / `service.stop_all` ([06](06-execution-engine.md)) take the same filter parameters; with none they act on the whole workspace. `stopping` and `crashed` services are start targets (they are not operational); disabled services are never start targets. Spacing (`BULK_START_SPACING_MS` = 150 ms) and restart gap are [06](06-execution-engine.md). Spec 06 defines the RPC parameter names; the set definition above is owned here.

### 3.9 Events and the mapping of 1.x notifications

Event names are those of [00 §5.7](00-overview-and-conventions.md); payload schemas are fixed by [08](08-logs-and-events.md). The payloads below are the **minimum** this spec requires (ids and a coarse change tag) so clients can refetch; entity bodies are not included. The 1.x `source` userinfo (`deck`/`inspector`/`execution`) used to skip self-echoes is replaced by the event envelope's origin (`clientRequestId`/`origin`, spec 08/10): a client suppresses echoes of its own calls.

| 1.x notification (`Notification+Kuma.swift`) | Posted by (1.x) | Daemon event | Minimum payload |
|----------------------------------------------|-----------------|--------------|-----------------|
| `kuma.serviceCreated` | create sheet (`ContentView.swift:101`, object nil = reload all), deck duplicate (`+ServiceActions.swift:165`, object = new id) | `service.created` | `{serviceID, workspaceID}` |
| `kuma.serviceUpdated` (source deck/inspector/execution) | deck star/disable/switch/toggle group; inspector commit, add/update/delete provider, star, disable | `service.updated` | `{serviceID, workspaceID, changed: ["service" \| "providers" \| "ports" \| "memberships" \| "activeProvider"]}` |
| `kuma.serviceDeleted` | deck delete (`:215`), inspector delete (`+Providers.swift:169`) | `service.deleted` | `{serviceID, workspaceID}` |
| `kuma.groupsUpdated` (object = group id, or nil on reorder) | sidebar add/rename/delete/reorder | `group.changed` | `{workspaceID, groupID?, change: "created" \| "updated" \| "deleted" \| "reordered"}` |
| (none; `WorkspaceStore` is observable) | workspace create/update/delete/reorder | `workspace.changed` | `{workspaceID?, change: "created" \| "updated" \| "deleted" \| "reordered", changed?: ["image"], nextWorkspaceId?}` |
| `kuma.serviceStateChanged` | execution engine | `service.state_changed` | owned by [06](06-execution-engine.md)/[08](08-logs-and-events.md) |
| `kuma.createServiceRequested`, `kuma.focusSearch`, `kuma.openSettings`, `kuma.openOnboarding` and other UI-routing notifications | client chrome | none | `[CLIENT]` intra-app commands (§3.12) |

Emission rules per RPC:

| RPC | Events (in order) |
|-----|-------------------|
| `workspace.create` / `update` / `set_image` / `clear_image` / `reorder` | `workspace.changed` (`created`/`updated`(+`changed:["image"]`)/`reordered`) |
| `workspace.delete` | `service.state_changed` (stops, by 06), `service.deleted` per service, `workspace.changed {deleted}` |
| `group.*` | `group.changed` |
| `service.create` / `duplicate` | `service.created` |
| `service.update`, `set_starred`, `set_disabled`, `switch_provider`, `provider.add/update/delete/set_ports`, `set_groups`, `toggle_group` | `service.updated` (+ `service.state_changed` from stop/start sub-steps) |
| `service.delete` | `service.state_changed` (stop, by 06), `service.deleted` |
| A no-op (swap with invalid/equal indexes, same-provider switch) | nothing |

All events are emitted after the transaction commits ([08](08-logs-and-events.md) assigns `seq`).

### 3.10 Create-time rules that stay in the client (`[CLIENT]` but normative for clients)

- The port rows sent to `service.create` / `provider.set_ports` are the rows the user filled with `Int(trim(local)) > 0 && Int(trim(remote)) > 0`; protocol `"TCP"`. Incomplete rows are dropped client-side (create: `CreateServicePayloadBuilder.swift:80-90`, inspector: `+AutoSave.swift:58-69`). The create form additionally requires every non-empty row to be within `1...65535` (`isFormValid :104-115`), and kubernetes requires at least one complete valid port row (`:122-129`).
- `starOnCreate` and `initialGroupID` come from the sidebar selection (`ContentView.createServiceDefaultsForCurrentSidebar`): `isStarred = (selection == "starred-services")`; `groupIDs = [id]` when the selected row is a group (`groupIDForSelectedRow`, `SidebarViewModel+Groups.swift:116`), else `[]`.
- After a successful create the client closes the sheet and refetches; the new service is not auto-selected.

### 3.11 Error precedence

When several error conditions hold at once, write methods report the **first** of this list, so clients and tests get deterministic results:

1. Protocol/syntax: malformed UUID, unknown enum value, wrong JSON type (`KUMA_DAT_INVALID_UUID`, `KUMA_DAT_INVALID_ENUM`, protocol errors of [10](10-rpc-protocol.md)).
2. Existence of the named entity (`KUMA_WS_NOT_FOUND`, `KUMA_GRP_NOT_FOUND`, `KUMA_SVC_NOT_FOUND`, `KUMA_SVC_PROVIDER_NOT_FOUND`).
3. Concurrency token (`KUMA_CONFLICT_STALE`).
4. Method-specific state guards (`KUMA_WS_LAST_WORKSPACE`, `KUMA_SVC_LAST_PROVIDER`, `KUMA_SVC_FIELD_READONLY`, `KUMA_WS_IMAGE_CONFLICT`, `KUMA_WS_REORDER_INVALID`, `KUMA_GRP_REORDER_INVALID`).
5. Value validation in parameter order (`KUMA_WS_NAME_EMPTY`, `KUMA_SVC_NAME_EMPTY`, then referenced groups `KUMA_GRP_NOT_FOUND` / `KUMA_GRP_WORKSPACE_MISMATCH`, then provider validation of [05](05-providers-and-validation.md), then `KUMA_SVC_INVALID_PORT`, then `KUMA_WS_IMAGE_INVALID`).
6. Storage failures (`KUMA_WS_IMAGE_IO`, `KUMA_DAT_*`).

Side effects (stopping services, writing image files) start only after steps 1-5 pass.

### 3.12 Client-side behavior (`[CLIENT]`, listed so nothing is silently dropped)

The daemon provides data and events only. Exact strings are recorded for client fidelity.

**Workspaces**

- `WorkspaceFormSheet`: titles `New Workspace` (create) and `Workspace Settings` (edit); name placeholder `My Workspace`; Save/Add disabled while the trimmed name is empty; `saveChanges` shows `Name cannot be empty` for a blank trimmed name; create flow = `workspace.create` then selecting the new workspace; edit flow with both the image path and the picked URL nil = `clearImage`; the delete row shows only when `workspaces.count > 1`; confirm dialog title `Delete Workspace?`, message `“<name>” and all its services will be permanently deleted.`, confirm button `Delete` (`WorkspaceFormSheet.swift:49-132`).
- `WorkspaceSwitcherPopover`: active row labelled `Active Workspace` with a gear tooltip `Workspace Settings`; inactive rows show the badge `⌘N` with `N` = 1-based index in the full `workspace.list` order when `N <= 9`; row context menu `Switch to Workspace`, `Workspace Settings`, `Delete` (delete only when more than one workspace exists); delete confirmation message `All services and configurations in “<name>” will be permanently deleted. This action cannot be undone.`; bottom button `New Workspace`; list scroll max height 220; haptic `levelChange` on select.
- `WorkspaceAvatarPickerView`: file panel limited to images, buttons `Choose Photo` / `Remove Photo`, remove badge. `WorkspaceAvatarView`: requests thumbnails at `size * 2`; when `hasImage` is false shows initials on a gradient chosen by a djb2-like hash of the name over 5 palettes.
- Global menu `Workspaces` (`KumaCommands.swift:30-51`): one item per workspace in list order; the first nine items carry the shortcut `⌘1`..`⌘9` (`index + 1`), later items have none; `New Workspace…` = `⇧⌘N` (`KumaShortcuts.newWorkspace`). Other global shortcuts: `⌘,` Settings, `⌘F` Find Services, `⌘?` Onboarding guide, `Space` toggle selected service, `⌘R` restart selected service, `Esc` deselect/dismiss (`KumaShortcuts.swift:29-80`; the last three are hidden buttons in `ServicesDeckView+DeckChrome.swift:81-98` acting on `selectedServiceID`).
- Selected workspace persistence: preference `kuma.selectedWorkspaceId.storage` ([03](03-settings-and-environment.md)); on load use it if it names an existing workspace else the first workspace; after deleting the selected workspace apply `nextWorkspaceId`; alerts `Database Error`, `Save Failed`, `Update Failed`, `Delete Failed`, `Reorder Failed` map to RPC errors.

**Sidebar and groups**

- Fixed nodes `All Services` (`square.grid.2x2.fill`), `Starred` (`star`), `Groups` header (action `New Group` with `plus`), group rows (`folder`), footer `Settings` (tooltip `Settings (⌘,)`) and Help; stable ids in [01 §3.16.3](01-data-model.md). Selection is valid only if it is one of the stable ids or a group of the current workspace, else `all-services` (`reconcileSelectionForLoadedWorkspace :19-40`). After create, select the new group, begin inline rename (placeholder `Group Name`; Enter or focus loss commits, Esc commits the original title), expand the Groups node.
- Group row context menu: `Rename`, `Move Up`, `Move Down`, `Delete` (confirm title `Delete Group?`, message `Services in “<title>” will remain in your workspace.`, button `Delete`).
- Empty placeholder rows: id `UUID.stable(<node id> + ".empty-placeholder")`; text `No starred items` (Starred), `No services` (All Services), otherwise `No \(title.lowercased()) services`, so the empty Groups node reads literally `No groups services` (`emptyPlaceholderText :139`).
- Keyboard (`handleMove :149-193`): up/down move through navigable rows clamped at the ends; left collapses and right expands the selected node when it has children.
- The sidebar reloads groups when the workspace changes and on `group.changed`.

**Deck**

- Toolbar: `Add New Service`, `Start All`, `Stop All`, `Import`, `Export`; filter menu Status (`Running`, `Stopped`, `Crashed`, `Disabled`), Provider (all `ProviderCategory` labels), `Reset Filters`; sort menu `Sort By`; `⌘I` toggles the inspector; view modes `card` and `table` (`DeckViewMode`); table columns `Name`, `Provider`, `Ports`, `Status`, actions.
- Empty states: `No Starred Services` (`Star your most frequently used services from the context menu to access them quickly from here.`) when `starredOnly`; `No Services Yet` (`Create a service to start port-forwarding, container, or shell runs.`, button `Create Service`) when `totalCount == 0`; else `No Services Found` (`Try refining your search text or active filter options.`).
- Card toggle (`CardToggleSwitch`): disabled services show a lock (`Service disabled`) instead of a toggle; the switch is on for running/starting/reconnecting and is inert while `isLoading` or status `starting`/`stopping`; accessibility `Stop service`/`Start service`.
- Context menu order: `Start`/`Stop` (Start disabled for disabled services; Stop shown for running/starting/reconnecting), `Restart` (disabled if disabled or status != running), divider, `Open Details`, `Switch Provider` submenu (checkmark on the active option; label = `displayLabel`), `Groups` submenu (toggle per group; hidden if no groups), `Star`/`Unstar`, `Duplicate`, `Copy Config` (= `data.export_service_json` to the pasteboard plus the `Purr` sound), divider, `Disable`/`Enable` (not disabled while running in the deck), `Delete` (confirm dialog `Delete Service?`, message `‘<name>’ and its configurations will be permanently deleted.`).
- Optimistic updates (star, disable, toggle group, duplicate, delete) with a single-service refetch on failure; `duplicateSearchKey` optimistic helper; recompute-on-notification optimization (`ServicesDeckRuntimeObservation`, TC-E05*).
- Auto-resume at first load (`resumeServicesIfNeeded`, `+WorkspaceLoad.swift:50-78`: setting `autoResumeServices`, saved ids, enabled services only, 150 ms spacing) is behavior of [03](03-settings-and-environment.md)/[06](06-execution-engine.md)/[14](14-lifecycle-and-platform.md).

**Inspector**

- `isLocked = service.isDisabled || isRunning || executionState == .starting`; locked sections are disabled; header banner for a disabled service `Disabled` / `Turn on in Options to run or edit.`; option rows `Disable Service` / `Excluded from bulk actions.`, `Auto Reconnect` / `Up to 3 retries after disconnect.`, `Delete Service` / `Permanent removal.` (delete disabled while running); the inspector's `toggleDisabled` control is disabled while running.
- Provider rows: delete offered only when `providers.count > 1`; adding a kubernetes/ssh provider creates one empty port row; `loadService` creates one empty port row for an empty kubernetes/ssh list and applies kubernetes defaults; the inspector reloads on `service.updated`/`group.changed` (except its own echoes) and clears on `service.deleted`.
- Port field validation text `Port must be a valid integer between 1 and 65535`; validator banner text for start is [05](05-providers-and-validation.md).

### 3.13 State transition tables

**T1: `workspace.delete`**

| Workspaces before | Target exists | Running services in target | Result |
|-------------------|---------------|----------------------------|--------|
| any | no | n/a | `KUMA_WS_NOT_FOUND` |
| 1 | yes | any | `KUMA_WS_LAST_WORKSPACE`, nothing stopped, nothing deleted |
| >= 2 | yes | 0 | delete row (cascade), delete managed image, events, `nextWorkspaceId` |
| >= 2 | yes | >= 1 | stop all (wait), then as above (DEV-03) |

**T2: `service.switch_provider`** (`R` = runtime state when called)

| Provider belongs to service | Same as effective active | `R` operational | Steps | Result |
|-----------------------------|--------------------------|-----------------|-------|--------|
| no | n/a | n/a | none | `KUMA_SVC_PROVIDER_NOT_FOUND` |
| yes | yes | any | none | success, `changed:false` |
| yes | no | no | write `activeProviderID` + `updatedAt`, event | success, `restart.attempted:false` |
| yes | no | yes | stop, write, event, start | stop ok, start ok: `running` (`restart.started:true`); start fails: `crashed(1)` + last failure, success with `restart.error`; DB write fails: `stopped`, RPC error |

**T3: `service.set_disabled`**

| Requested | Current flag | Runtime | Effect |
|-----------|--------------|---------|--------|
| `true` | false | operational | commit flag, stop service (DEV-51), end `stopped` |
| `true` | false | not operational | commit flag only |
| `true` | true | any | idempotent write (`updatedAt` bumped) |
| `false` | true | `stopped` (necessarily) | commit flag only; service becomes startable and a start target again |
| `false` | false | any | idempotent write (`updatedAt` bumped) |

**T4: `workspace.imagePath` transitions**

| From | Operation | To | File effect |
|------|-----------|----|-------------|
| NULL | create with image / `set_image` | `<ID>.png` | new managed file |
| `<ID>.png` | `set_image` | `<ID>.png` | atomic replace; revision bump |
| `<ID>.png` | `set_image` with undecodable bytes | unchanged | old file kept (DEV-50) |
| `<ID>.png` | `clear_image` | NULL | managed file deleted |
| legacy absolute path | `set_image` | `<ID>.png` | new managed file; **original untouched** (DEV-55) |
| legacy absolute path | `clear_image` / `workspace.delete` | NULL / row gone | **original untouched** (DEV-55) |
| any | factory reset | row re-seeded NULL | `Workspaces/Images` directory removed |

**T5: group `sortOrder` (illustration)**

| Step | Groups (name: sortOrder) |
|------|--------------------------|
| create A, B, C in an empty workspace | A:1, B:2, C:3 |
| delete B | A:1, C:3 |
| create D | A:1, C:3, D:4 |
| `group.reorder [D, A, C]` | D:0, A:1, C:2 (all `updatedAt` bumped) |

### 3.14 Coverage of every 1.x function

| 1.x function | Disposition |
|--------------|-------------|
| `WorkspaceStore.loadFromDatabase` | seeding: [01 §3.8](01-data-model.md); selection restore: `[CLIENT]` §3.12 |
| `WorkspaceStore.selectWorkspace`, `selectedWorkspaceId` didSet | `[CLIENT]` (preference, [03](03-settings-and-environment.md)) |
| `WorkspaceStore.addWorkspace` | §3.2.3 |
| `WorkspaceStore.renameWorkspace`, `updateWorkspace` | §3.2.4, §3.3.3 |
| `WorkspaceStore.deleteWorkspace` | §3.2.5 |
| `WorkspaceStore.moveWorkspace` | §3.2.6 Form B |
| `WorkspaceRepository` `fetchAll`/`insert`/`update`/`updateSortOrders`/`delete` | §3.2, [01 §3.11.3](01-data-model.md); `update` of a missing row errors in 1.x, `delete` of a missing id was ignored (DEV-57) |
| `ServiceGroupRepository` (same five) | §3.4 |
| `Workspace.defaultName` / `defaultWorkspace` / `init(from:)` / `CodingKeys` | [01 §3.8](01-data-model.md), [01 §4.1](01-data-model.md) |
| `WorkspaceImageStore` `imagesDirectoryURL` | §3.3.1 |
| `saveWorkspaceImage`, `saveBase64Image`, `loadBase64Image` | §3.3.2, §3.3.8 |
| `thumbnail`, `cacheKey`, `revision`, `evictCache`, `clearCache` | §3.3.4, §3.3.7 |
| `resolveURL`, `deleteImage` | §3.3.1, §3.3.6 |
| `SidebarViewModel.loadGroups`, `reconcileSelectionForLoadedWorkspace`, `groupIDForSelectedRow` | `group.list` (§3.4.1); the other two `[CLIENT]` |
| `addGroup`, `renameGroup`, `deleteGroup` | §3.4.2-§3.4.4 |
| `moveGroups`, `moveGroupUp/Down`, `canMoveGroupUp/Down`, `reorderGroup` | §3.4.5 (daemon: permutation; gestures `[CLIENT]`) |
| `rebuildEntries`, `rebuildFlattenedRows`, `emptyPlaceholderText`, `handleMove`, `makeDefault`, `toggleExpanded`, `isExpanded` | `[CLIENT]` §3.12 |
| `ServiceRepository.fetchService`, `fetchServiceDetail`, `fetchProviders`, `fetchPortMappings` ×2, `fetchAllPortMappings` | §3.5.2, §3.6.1, [01 §3.11.2](01-data-model.md) |
| `fetchDeckItems`, `fetchDeckItem`, `portMappingsForActiveProvider`, `localPortsForActiveProvider` | §3.7, [01 §3.19](01-data-model.md) |
| `insertService`, `updateService`, `insertProvider`, `updateProvider`, `deleteProvider` | §3.5.3, §3.5.4, §3.6.2-§3.6.4 |
| `savePortMappings`, `toggleGroupMembership`, `toggleStarred`, `deleteService`, `duplicateService` | §3.6.5, §3.5.10, §3.5.7, §3.5.5, §3.5.6 |
| `ServiceCardSnapshot.init(deckItem:)`, `deckSearchKey`, `matchesSearchQuery`, `toggling(starred:)` | §3.7.2, §3.7.5; `toggling` is a `[CLIENT]` in-memory helper; the test-only default `searchKey = "\(name) \(subtitle)".lowercased()` (TC-A04) is dead code outside tests |
| `ServicesDeckViewModel.recomputeFilteredSnapshots`, `reconcileSearchFilterForRuntimeChanges`, `notifyExecutionStatesChanged` | §3.7.3, §3.7.4; the reconcile/notify optimizations `[CLIENT]` |
| `duplicateSearchKey`, `refreshSingleServiceSnapshot`, `refreshGroups`, `loadWorkspace(Async)`, `selectService`, `runtime(for:)`, `isOperational` | `[CLIENT]` (load = `service.list` + `group.list`) |
| `ServicesDeckViewModel.toggleStarred`, `toggleDisabled`, `switchProvider`, `toggleGroup`, `duplicateService`, `deleteService`, `promptDeleteService`, `confirmDeletePendingService` | §3.5.7, §3.5.8, §3.5.11, §3.5.10, §3.5.6, §3.5.5; prompt/confirm `[CLIENT]` |
| `copyConfig` | `[CLIENT]` over `data.export_service_json` ([09](09-dataport.md)) |
| `toggleService`, `toggleServiceAsync`, `startAllServices`, `stopAllServices`, `restartService`, `canStartAll`, `canStopAll`, `resumeServicesIfNeeded` | [06](06-execution-engine.md) (target set §3.8) |
| `ServiceInspectorViewModel.loadService`, `reloadDraftPortsForActiveProvider`, `syncKubeConfigSelectionFromActiveProvider`, `clearAfterExternalDeletion`, `postUpdatedNotification` | `[CLIENT]` (data = `service.get`) |
| `scheduleAutoSave`, `flushPendingAutoSave`, `cancelAutoSave`, `commitChanges` | `[CLIENT]` orchestration; daemon contract §3.5.12 |
| Inspector `switchProvider`, `addProvider`, `updateProviderDirectly`, `deleteProvider`, `toggleStarred`, `toggleDisabled`, `deleteService` | §3.5.11, §3.6.2, §3.6.3, §3.6.4, §3.5.7, §3.5.8, §3.5.5 |
| Inspector `toggleRunning`, `validateConfigurationForStart`, `recomputeConfigurationIssues`, `logBlockingConfigurationIssuesToActivity`, `refreshKubernetesTargetValidation`, `canStartService` | [05](05-providers-and-validation.md), [06](06-execution-engine.md) |
| `ServiceStartSupport.start`, `applyUserStartFailure`, `ServiceStopSupport.stopOffMainActor` | [06](06-execution-engine.md); consumed by §3.5.8, §3.5.11 |
| `CreateServicePayloadBuilder.buildPayload`, `isFormValid` | §3.5.3 with [05](05-providers-and-validation.md); form-only rules `[CLIENT]` §3.10 |
| `ContentView.createServiceDefaultsForCurrentSidebar` | `[CLIENT]` §3.10 |
| `KumaShortcuts`, `KumaCommands` | `[CLIENT]` §3.12 |
| `CardToggleSwitch`, `ServiceCardRow`, `ServicesDeckCardGridView`, `ServiceTableView`, `ServiceDeckTableSection`, `ServiceStatusObserver`, `ServiceNonPortBadge`, `SyncedServiceRuntime`, `ServicesDeckContentBodyView` | `[CLIENT]` §3.12 |

---

## 4. Data shapes

JSON keys, enum values, UUID and timestamp forms follow [01 §3.4.5](01-data-model.md). Entities are defined in [01 §4](01-data-model.md) and **not redefined** here; this section lists the request/result shapes owned by spec 04 (final schemas: [10](10-rpc-protocol.md)).

### 4.1 Wire entities (references)

| Entity | Defined in | Notes added by this spec |
|--------|-----------|--------------------------|
| `Workspace` | [01 §4.1](01-data-model.md) | plus derived `hasImage` (bool: `imagePath` non-null and the file is readable; ADD-59) |
| `ServiceGroup` | [01 §4.2](01-data-model.md) | |
| `Service` | [01 §4.3](01-data-model.md) | `groupIDs` sorted ascending |
| `Provider` | [01 §4.4](01-data-model.md) | secrets replaced by `sshPasswordSet`, `ngrokAuthTokenSet`; plus derived `displayName`, `resolvedTarget`, `isAutoReconnectEnabled` (ADD-59) |
| `ServicePortMapping` | [01 §4.5](01-data-model.md) | may include derived `displayString` |
| `ServiceRuntimeState` | [01 §4.9](01-data-model.md) | |

### 4.2 Workspace methods

| Method | Params (key: type, optional?, default) | Result |
|--------|----------------------------------------|--------|
| `workspace.list` | none | `{workspaces: Workspace[]}` |
| `workspace.get` | `id`: UUID | `{workspace}` |
| `workspace.create` | `name`: string, optional, `New Workspace`; `imageBase64`: string, optional, none | `{workspace}` |
| `workspace.update` | `id`: UUID; `name`: string, optional; `imageBase64`: string, optional; `clearImage`: bool, optional, false; `expectedUpdatedAt`: timestamp, optional | `{workspace}` |
| `workspace.delete` | `id`: UUID | `{deleted: true, nextWorkspaceId: UUID}` |
| `workspace.reorder` | form A: `workspaceIDs`: UUID[]; form B: `fromIndex`: int, `toIndex`: int | `{workspaces}` |
| `workspace.set_image` | `id`; `imageBase64`: string; `expectedUpdatedAt`? | `{workspace}` |
| `workspace.clear_image` | `id`; `expectedUpdatedAt`? | `{workspace}` |
| `workspace.get_image` | `id`; `size`: int, optional, 128 (clamped 1..1024) | `{hasImage: bool, mimeType?: "image/png", imageBase64?: string, width?: int, height?: int}` |

### 4.3 Group methods

| Method | Params | Result |
|--------|--------|--------|
| `group.list` | `workspaceID` | `{groups}` |
| `group.create` | `workspaceID`; `name`: optional, `New Group` | `{group}` |
| `group.update` | `id`; `name`: string; `expectedUpdatedAt`? | `{group}` |
| `group.delete` | `id` | `{deleted: true}` |
| `group.reorder` | `workspaceID`; `groupIDs`: UUID[] | `{groups}` |

### 4.4 Service methods

| Method | Params | Result |
|--------|--------|--------|
| `service.list` | `workspaceID`; `search`: string, optional, `""`; `starredOnly`: bool, optional, false; `groupID`: UUID, optional; `statuses`: string[], optional, `[]`; `providers`: string[], optional, `[]`; `sort`: string, optional | `{items: ServiceListItem[], totalCount: int}` |
| `service.get` | `id` | `{service, providers[], portMappings[], activeProviderID?, runtime, liveTarget?}` |
| `service.create` | `workspaceID`; `name`; `description`?; `isDisabled`?: false; `isStarred`?: false; `groupIDs`?: `[]`; `provider`: object ([05](05-providers-and-validation.md)); `ports`?: `[{id?, localPort, remotePort, protocolType?}]` | as `service.get` |
| `service.update` | `id`; `name`?; `description`?; `icon`?; `colorHex`?; `groupIDs`?; `expectedUpdatedAt`? | `{service}` |
| `service.delete` | `id` | `{deleted: true}` |
| `service.duplicate` | `id` | as `service.get` (new service) |
| `service.set_starred` | `id`; `starred`?: bool (absent = toggle); `expectedUpdatedAt`? | `{service}` |
| `service.set_disabled` | `id`; `disabled`: bool; `expectedUpdatedAt`? | `{service}` |
| `service.set_groups` | `id`; `groupIDs` | `{id, groupIDs}` |
| `service.toggle_group` | `id`; `groupID` | `{id, groupIDs}` |
| `service.switch_provider` | `id`; `providerID`; `expectedUpdatedAt`? | `{service, activeProviderID, changed: bool, restart: {attempted: bool, started: bool, error?: {code, message}}}` |

### 4.5 Provider methods

| Method | Params | Result |
|--------|--------|--------|
| `provider.list` | `serviceID` | `{providers, activeProviderID?}` |
| `provider.add` | `serviceID`; `provider`: object; `expectedUpdatedAt`? (service token) | `{provider, service, activeProviderID}` |
| `provider.update` | `id`; provider fields ([05](05-providers-and-validation.md)); `expectedUpdatedAt`? | `{provider}` |
| `provider.delete` | `id`; `expectedUpdatedAt`? (service token) | `{deleted: true, activeProviderID?}` |
| `provider.set_ports` | `serviceID`; `providerID`; `ports`: `[{id?, localPort, remotePort, protocolType?}]` | `{portMappings}` |

### 4.6 `ServiceListItem`

See §3.7.5 (table is the normative definition).

### 4.7 Event payloads (minimum)

See §3.9. Final schema: [08](08-logs-and-events.md).

---

## 5. Features table

| FEAT id | Tag | Description | 1.x source | RPC methods |
|---------|-----|-------------|------------|-------------|
| FEAT-WS-01 | [PARITY] | List workspaces ordered `sortOrder, createdAt, rowid`; never empty | `WorkspaceRepository.swift`, `WorkspaceStore.swift:47-77` | `workspace.list` |
| FEAT-WS-02 | [PARITY] | Get one workspace | `WorkspaceStore.swift` | `workspace.get` |
| FEAT-WS-03 | [PARITY] | Create workspace: trim, blank → `New Workspace`, `sortOrder = count`, optional avatar | `WorkspaceStore.swift:85-112` | `workspace.create` |
| FEAT-WS-04 | [PARITY] | Update/rename workspace (name trimmed, blank rejected `Name cannot be empty`), `updatedAt` bump | `WorkspaceStore.swift:114-156`, `WorkspaceFormSheet.swift:124-125` | `workspace.update` |
| FEAT-WS-05 | [PARITY] | Delete workspace: never-zero guard, cascade, avatar purge, returns `nextWorkspaceId` | `WorkspaceStore.swift:158-184` | `workspace.delete` |
| FEAT-WS-06 | [PARITY] | Delete stops the workspace's running services first (DEV-03) | `WorkspaceStore.swift:158-184` (1.x orphaned) | `workspace.delete` |
| FEAT-WS-07 | [PARITY] | Reorder workspaces: swap form (guards, `swapAt`, reindex `0..n-1`, batch UPDATE with `updatedAt`) and permutation form | `WorkspaceStore.swift:186-210`, `WorkspaceRepository.swift:42-51` | `workspace.reorder` |
| FEAT-WS-08 | [PARITY] | Default workspace `<First>'s Space` seed (owned by 01) | `Workspace.swift:44-55` | `workspace.list` |
| FEAT-WS-09 | [PARITY] | Avatar save: ImageIO-equivalent 512 px PNG, orientation applied, atomic write, `<UUID>.png` | `WorkspaceImageStore.swift:52-95` | `workspace.create`, `workspace.update`, `workspace.set_image` |
| FEAT-WS-10 | [PARITY] | Avatar thumbnail read (default 128, no upscale, never stale), `hasImage:false` fallback | `WorkspaceImageStore.swift:127-160` | `workspace.get_image` |
| FEAT-WS-11 | [PARITY] | Clear avatar | `WorkspaceFormSheet.swift` (edit flow), `WorkspaceImageStore.swift:190-194` | `workspace.clear_image`, `workspace.update` |
| FEAT-WS-12 | [PARITY] | Legacy absolute `imagePath` readable; never deleted (DEV-55) | `WorkspaceImageStore.swift:182-187` | `workspace.get_image`, `workspace.delete` |
| FEAT-WS-13 | [PARITY] | Image cleanup on delete/replace/clear and factory reset; revision cache semantics | `WorkspaceImageStore.swift:162-201`, `DataPortService+FactoryReset.swift` | `workspace.delete`, `workspace.set_image`, `workspace.clear_image` |
| FEAT-WS-14 | [PARITY] | Raw base64 avatar import/export for backups (internal store API) | `WorkspaceImageStore.swift:98-122` | - (used by `data.import`, `data.export`) |
| FEAT-WS-15 | [PARITY] | Workspace names are not unique | [01 §3.11.4](01-data-model.md) | `workspace.create`, `workspace.update` |
| FEAT-WS-16 | [V2-ADD] | `expectedUpdatedAt` concurrency token on workspace writes; `workspace.changed` event; derived `hasImage` (ADD-59) | brief | `workspace.update`, `workspace.set_image`, `workspace.clear_image` |
| FEAT-WS-17 | [CLIENT] | Workspace switcher popover (rows, `Active Workspace`, `⌘N` badges, context menu, delete confirm, haptic) | `WorkspaceSwitcherPopover.swift`, `InactiveWorkspaceRow.swift` | - |
| FEAT-WS-18 | [CLIENT] | Workspace form sheet (titles, placeholder, disabled Save, delete confirmation, select-after-create) | `WorkspaceFormSheet.swift` | - |
| FEAT-WS-19 | [CLIENT] | Avatar picker and initials/gradient fallback | `WorkspaceAvatarPickerView`, `WorkspaceAvatarView` | - |
| FEAT-WS-20 | [CLIENT] | `Workspaces` menu with `⌘1`..`⌘9`, `⇧⌘N` new workspace | `KumaCommands.swift:30-51`, `KumaShortcuts.swift:44-50` | - |
| FEAT-WS-21 | [CLIENT] | Selected-workspace preference and post-delete fallback using `nextWorkspaceId` | `WorkspaceStore.swift:9-20,51-60,171-173` | `settings.get`, `settings.set` |
| FEAT-GRP-01 | [PARITY] | List groups of a workspace ordered `sortOrder, createdAt, rowid` | `ServiceGroupRepository.swift:21` | `group.list` |
| FEAT-GRP-02 | [PARITY] | Create group: default `New Group`, `sortOrder = max + 1` (first = 1) | `SidebarViewModel+Groups.swift:42-67` | `group.create` |
| FEAT-GRP-03 | [PARITY] | Rename group: trim, blank → `Untitled Group`, `updatedAt` bump | `SidebarViewModel+Groups.swift:69-92` | `group.update` |
| FEAT-GRP-04 | [PARITY] | Delete group: memberships cascade, services never deleted | `SidebarViewModel+Groups.swift:94-114` | `group.delete` |
| FEAT-GRP-05 | [PARITY] | Reorder groups: contiguous `0..n-1` + `updatedAt` for all, batch UPDATE | `SidebarViewModel+Reorder.swift:5-26`, `ServiceGroupRepository.swift:42-51` | `group.reorder` |
| FEAT-GRP-06 | [PARITY] | Groups scoped to a workspace (immutable `workspaceID`); same-workspace membership enforced (DEV-54) | `ServiceGroupRepository.swift`, `AppDatabase.swift` | `group.create`, `service.set_groups`, `service.toggle_group` |
| FEAT-GRP-07 | [PARITY] | Many-to-many membership: replace set / toggle one, returns full set | `ServiceRepository+CRUD.swift:124-137,180-199` | `service.set_groups`, `service.toggle_group`, `service.update` |
| FEAT-GRP-08 | [PARITY] | Group change notification → `group.changed` | `Notification+Kuma.swift:15`, `SidebarViewModel+Groups.swift:62,87,109` | `group.create`, `group.update`, `group.delete`, `group.reorder` |
| FEAT-GRP-09 | [CLIENT] | Sidebar fixed nodes and stable node ids (`all-services`, `starred-services`, `groups`, `settings`), selection validity, fallback to All Services | `SidebarViewModel+Groups.swift:19-40`, [01 §3.16.3](01-data-model.md) | - |
| FEAT-GRP-10 | [CLIENT] | Group row UI: context menu (`Rename`, `Move Up`, `Move Down`, `Delete`), inline editor, delete confirm text, select + edit after create | `SidebarView.swift` and row views | - |
| FEAT-GRP-11 | [CLIENT] | Move up/down/drag algorithms producing the permutation (`Array.move` offsets) | `SidebarViewModel+Reorder.swift:28-55` | `group.reorder` |
| FEAT-GRP-12 | [CLIENT] | Sidebar keyboard navigation (up/down clamp, left collapse, right expand) | `SidebarViewModel+FlattenedRows.swift:149-193` | - |
| FEAT-GRP-13 | [CLIENT] | Empty-node placeholder texts (`No starred items`, `No services`, `No groups services`) | `SidebarViewModel+FlattenedRows.swift:139-147` | - |
| FEAT-GRP-14 | [CLIENT] | Sidebar footer (Settings tooltip `Settings (⌘,)`, Help link) and group reload on workspace change / `group.changed` | `SidebarView.swift` | `group.list` |
| FEAT-SVC-01 | [PARITY] | Deck query: base order `createdAt, rowid`, workspace scoped, `totalCount` | `ServiceRepository+DeckItems.swift:5-104` | `service.list` |
| FEAT-SVC-02 | [PARITY] | Search: composed `searchKey`, trimmed lowercase query, live Kubernetes target match | `ServiceCardSnapshot.swift:64,114` | `service.list` |
| FEAT-SVC-03 | [PARITY] | Filters in order: starredOnly, group, search, status buckets (disabled special-case), provider category | `ServicesDeckViewModel+Filtering.swift:22-66` | `service.list` |
| FEAT-SVC-04 | [PARITY] | Sorts: name (localized case-insensitive), status (priority, disabled = 5, then name), created (newest first), default repository order | `ServicesDeckViewModel+Filtering.swift:67-86` | `service.list` |
| FEAT-SVC-05 | [PARITY] | List item DTO: deck item fields, `subtitle`, provider option labels, runtime merge | `ServiceCardSnapshot.swift`, `ServiceDeckItem.swift` | `service.list` |
| FEAT-SVC-06 | [PARITY] | Service detail: service, providers (k8s defaults), filtered ports, effective active provider | `ServiceRepository+CRUD.swift:17-43` | `service.get` |
| FEAT-SVC-07 | [PARITY] | Create service in one transaction (service, default provider, ports with provider id, memberships), `activeProviderID` NULL | `ServiceRepository+CRUD.swift:104-122`, `CreateServicePayloadBuilder.swift` | `service.create` |
| FEAT-SVC-08 | [CLIENT] | Create defaults from sidebar selection (`starOnCreate`, `initialGroupID`), form validity gating, port-row filter | `ContentView.swift`, `CreateServicePayloadBuilder.swift:80-145` | `service.create` |
| FEAT-SVC-09 | [PARITY] | Update service metadata; replace memberships when `groupIDs` given; `updatedAt` bump | `ServiceRepository+CRUD.swift:124-137` | `service.update` |
| FEAT-SVC-10 | [PARITY] | Delete service with cascade; stops a running service first (DEV-14) | `ServiceRepository+CRUD.swift:201`, `+ServiceActions.swift:202-222` | `service.delete` |
| FEAT-SVC-11 | [PARITY] | Duplicate service: exact algorithm (`(Copy)`, provider/port/membership copies, active remap) | `ServiceRepository+CRUD.swift:208-285` | `service.duplicate` |
| FEAT-SVC-12 | [PARITY] | Star: toggle or explicit value, bumps `updatedAt` | `ServiceRepository+CRUD.swift:45-55` | `service.set_starred` |
| FEAT-SVC-13 | [PARITY] | Enable/disable: excluded from bulk start; disabling stops a running service (DEV-51) | `+ServiceActions.swift:23-58`, `+Providers.swift:149-163` | `service.set_disabled` |
| FEAT-SVC-14 | [PARITY] | Replace group membership set | `ServiceRepository+CRUD.swift:124-137` | `service.set_groups` |
| FEAT-SVC-15 | [PARITY] | Toggle one group membership, returns full set, no `updatedAt` change | `ServiceRepository+CRUD.swift:180-199` | `service.toggle_group` |
| FEAT-SVC-16 | [PARITY] | Switch active provider with stop → write → restart-if-was-running (DEV-53) | `+ServiceActions.swift:61-92`, `+Providers.swift:5-56` | `service.switch_provider` |
| FEAT-SVC-17 | [PARITY] | List providers of a service with effective active id | `ServiceRepository+CRUD.swift:57-64` | `provider.list` |
| FEAT-SVC-18 | [PARITY] | Add provider: becomes active, service `updatedAt` bumped | `+Providers.swift:58-95` | `provider.add` |
| FEAT-SVC-19 | [PARITY] | Update provider row (all columns, `updatedAt` bump, k8s defaults) | `+Providers.swift:97-109`, `+AutoSave.swift:72` | `provider.update` |
| FEAT-SVC-20 | [PARITY] | Delete provider: cascade ports, repoint active to first remaining, refuse last provider (DEV-58) | `+Providers.swift:111-131` | `provider.delete` |
| FEAT-SVC-21 | [PARITY] | Replace port mappings of one provider (delete by `serviceID` + `providerID`, dedupe ids, forced ids, range check DEV-56) | `ServiceRepository+CRUD.swift:157-178` | `provider.set_ports` |
| FEAT-SVC-22 | [PARITY] | Inspector commit shape: service + active provider always, ports only if dirty | `+AutoSave.swift:41-89` | `service.update`, `provider.update`, `provider.set_ports` |
| FEAT-SVC-23 | [PARITY] | Bulk-action target set = the filtered, sorted deck list; start targets exclude disabled/operational | `ServicesDeckViewModel.swift:53-60`, `+ExecutionActions.swift` | `service.list`, `service.start_all`, `service.stop_all` |
| FEAT-SVC-24 | [PARITY] | Mutation events and notification mapping (created/updated/deleted) | `Notification+Kuma.swift:8-29` | `service.create`, `service.update`, `service.delete`, `service.duplicate`, `service.set_starred`, `service.set_disabled`, `service.set_groups`, `service.toggle_group`, `service.switch_provider`, `provider.add`, `provider.update`, `provider.delete`, `provider.set_ports` |
| FEAT-SVC-25 | [V2-ADD] | `expectedUpdatedAt` tokens on service/provider writes; `KUMA_SVC_FIELD_READONLY` guard; derived DTO fields (ADD-59) | brief | `service.update`, `service.set_starred`, `service.set_disabled`, `service.switch_provider`, `provider.update`, `service.list` |
| FEAT-SVC-26 | [CLIENT] | Deck toolbar, filter/sort menus, card/table modes, table columns | `ServicesDeckView*.swift`, `ServiceTableView.swift` | `service.list` |
| FEAT-SVC-27 | [CLIENT] | Card context menu items, order and enable rules; `Copy Config` with `Purr` sound | `ServiceActionContextMenu`, `+ServiceActions.swift:175-187` | `data.export_service_json` |
| FEAT-SVC-28 | [CLIENT] | Card toggle switch states, lock icon for disabled, accessibility labels | `CardToggleSwitch.swift` | `service.start`, `service.stop` |
| FEAT-SVC-29 | [CLIENT] | Hidden shortcuts: `Space` toggle, `⌘R` restart, `Esc` dismiss, `⌘F` focus search, `⌘I` inspector | `KumaShortcuts.swift:60-77`, `ServicesDeckView+DeckChrome.swift:81-98` | `service.start`, `service.stop`, `service.restart` |
| FEAT-SVC-30 | [CLIENT] | Deck empty states and texts | `ServicesDeckContentBodyView.swift:55-80` | `service.list` |
| FEAT-SVC-31 | [CLIENT] | Optimistic updates, single-service refetch, runtime-notification gating | `+ServiceActions.swift`, `+WorkspaceLoad.swift:80-97`, `ServicesDeckRuntimeObservation.swift` | `service.list`, `service.get` |
| FEAT-SVC-32 | [CLIENT] | Inspector locks, banners, option texts, auto-save debounce 800 ms, flush on dismiss/provider switch, port-row filter | `+AutoSave.swift:10-39`, inspector views | `service.update`, `provider.update`, `provider.set_ports` |
| FEAT-SVC-33 | [CLIENT] | Delete-service confirmation (`Delete Service?`) and delete-provider affordance rule (`providers.count > 1`) | `+ServiceActions.swift:189-200`, `ServiceProvidersListView.swift:38` | `service.delete`, `provider.delete` |
| FEAT-SVC-34 | [CLIENT] | Client reaction to events (deck skips own echoes, inspector reloads on updated/group events, clears on deleted) | `ServicesDeckView+Notifications.swift`, `ServiceInspectorView.swift:117-130` | `events.subscribe` |

---

## 6. Error catalog

| Code | Condition | Message |
|------|-----------|---------|
| `KUMA_WS_NOT_FOUND` | Workspace id does not exist (get, update, delete, image methods, `group.create`, `service.create`) | `Workspace not found: <id>` |
| `KUMA_WS_NAME_EMPTY` | `workspace.update` with a blank (after trim) `name` | `Name cannot be empty` |
| `KUMA_WS_LAST_WORKSPACE` | `workspace.delete` when exactly one workspace exists | `Attempted to delete the sole remaining workspace <id>. Operation blocked.` |
| `KUMA_WS_IMAGE_INVALID` | `imageBase64` is not valid base64, or is not a decodable image | `Failed to read image source` |
| `KUMA_WS_IMAGE_CONFLICT` | `workspace.update` with both `imageBase64` and `clearImage: true` | `Specify either imageBase64 or clearImage, not both` |
| `KUMA_WS_IMAGE_IO` | Images directory cannot be created or the file cannot be written | `Failed to create workspace images directory: <detail>` or `Failed to save workspace image: <detail>` |
| `KUMA_WS_REORDER_INVALID` | `workspace.reorder` with both/neither forms, or `workspaceIDs` not exactly the set of workspaces | `workspaceIDs must list every workspace exactly once` / `Specify either workspaceIDs or fromIndex and toIndex` |
| `KUMA_GRP_NOT_FOUND` | Group id does not exist | `Group not found: <id>` |
| `KUMA_GRP_REORDER_INVALID` | `group.reorder` `groupIDs` not exactly the groups of the workspace | `groupIDs must list every group of the workspace exactly once` |
| `KUMA_GRP_WORKSPACE_MISMATCH` | A membership insert would connect a service and a group of different workspaces | `Group <groupID> does not belong to the workspace of service <serviceID>` |
| `KUMA_SVC_NOT_FOUND` | Service id does not exist | `Service not found: <id>`; for `service.duplicate` exactly `Source service not found` |
| `KUMA_SVC_NAME_EMPTY` | `service.create` with a blank (after trim) `name` | `Name cannot be empty` |
| `KUMA_SVC_PROVIDER_NOT_FOUND` | Provider id does not exist, or does not belong to the named service | `Provider not found: <id>` |
| `KUMA_SVC_LAST_PROVIDER` | `provider.delete` of the only provider of a service | `A service must keep at least one provider.` |
| `KUMA_SVC_INVALID_PORT` | A port row outside `1..65535` or not an integer in `service.create` / `provider.set_ports` | `Port row <N>: enter local and remote ports (1–65535).` (`N` is 1-based; the dash is U+2013, exact 1.x text of `ServiceConfigurationValidator.swift:94`) |
| `KUMA_SVC_FIELD_READONLY` | `service.update` carries `isStarred`, `isDisabled`, `activeProviderID`, `workspaceID`, `id`, `createdAt` or `updatedAt` | `Field '<field>' cannot be changed with service.update; use <method>` (`<method>` is `service.set_starred`, `service.set_disabled`, `service.switch_provider`, or `no method exists` for the others) |
| `KUMA_CONFLICT_STALE` | `expectedUpdatedAt` mismatch | defined in [10](10-rpc-protocol.md) |
| `KUMA_DAT_INVALID_UUID`, `KUMA_DAT_INVALID_ENUM`, `KUMA_DAT_CONSTRAINT_VIOLATION`, `KUMA_DAT_DB_BUSY` | Data-layer failures | defined in [01 §6](01-data-model.md) |

Provider validation errors (`KUMA_PRV_*`) raised while building a provider in `service.create` / `provider.add` / `provider.update` belong to [05](05-providers-and-validation.md). Start failures during the restart step of `service.switch_provider` are reported inside `restart.error`, never as the RPC error.

---

## 7. Deviations

Full text in [15](15-traceability-and-parity.md). Ids 50-59 are this spec's range (ids are never reused).

| ID | Summary |
|----|---------|
| DEV-03 (pre-assigned) | `workspace.delete` stops the workspace's running services first (1.x orphaned them). §3.2.5. |
| DEV-14 (pre-assigned) | `service.delete` stops a running service first (1.x only disabled the button). §3.5.5. |
| DEV-11 (pre-assigned) | Selected workspace and all other prefs use daemon settings KV (not UserDefaults); key `kuma.selectedWorkspaceId.storage` in §3.12. Full scope: [15 DEV-11](15-traceability-and-parity.md). |
| DEV-50 | Workspace avatar writes always produce a managed 512 px PNG copy and are failure-safe: create-with-image no longer stores the raw absolute path (1.x `URL(string:)` quirk), replacement decodes before touching the old file, and an invalid image is `KUMA_WS_IMAGE_INVALID` instead of silently clearing/ignoring the avatar. §3.2.3, §3.3.2, §3.3.3. |
| DEV-51 | `service.set_disabled(true)` stops a running service (1.x only reset the UI state to idle and left the process unsupervised). §3.5.8. |
| DEV-52 | Name rules are enforced by the daemon on every write path instead of only in forms: `workspace.update` trims and rejects blank (`KUMA_WS_NAME_EMPTY`); `service.create` trims and rejects blank (`KUMA_SVC_NAME_EMPTY`); `group.create` trims and falls back to `New Group`. Blank group rename stays `Untitled Group` and blank workspace create stays `New Workspace` (parity). §3.2.3, §3.2.4, §3.4.2, §3.5.3. |
| DEV-53 | `service.switch_provider` validates that the provider belongs to the service, treats a same-provider switch as a no-op (the inspector guard; the deck had none), and uses one restart path (the [06](06-execution-engine.md) user-initiated start) whose failure leaves `crashed(1)` + last failure (the inspector's validation-failure path left the service stopped). §3.5.11. |
| DEV-54 | Group membership is validated to connect a service and a group of the same workspace (1.x relied on UI and FKs). §3.4.6. |
| DEV-55 | The daemon deletes only avatar files located inside `Workspaces/Images`; a legacy absolute `imagePath` (which in 1.x is the user's original photo) is never deleted, preventing the 1.x `deleteWorkspace`/replace data loss. §3.3.6. |
| DEV-56 | Port rows are range-checked (`1..65535`, integers) at write time in `service.create` and `provider.set_ports`; 1.x persisted any positive value from the inspector and caught out-of-range values only at start validation. §3.5.3, §3.6.5. |
| DEV-57 | Operations naming a missing workspace/group/service/provider return `KUMA_*_NOT_FOUND`; 1.x silently ignored deletes of unknown ids and `toggleStarred` returned `false`. List queries by an unknown workspace still return empty lists. §3.0.7. |
| DEV-58 | `provider.delete` refuses to delete the only provider (1.x enforced it only by hiding the button, `providers.count > 1`). §3.6.4. |
| ADD-59 | Derived convenience fields not stored in 1.x models: `Workspace.hasImage`; `ServiceListItem.subtitle`/`displaySubtitle`/`liveTarget`/`runtime`/`providerOptions[].displayLabel`; `service.list` `totalCount`; `Provider.displayName`/`resolvedTarget`/`isAutoReconnectEnabled`; `workspace.get_image` thumbnails returned as base64 PNG. §3.3.4, §3.7.5. |
| (global) DEV-22 / DEV-23 | `updatedAt` monotonic rule and deterministic tie-breaks apply to every write and list here ([01](01-data-model.md)). |

---

## 8. Invariants

| ID | Statement |
|----|-----------|
| INV-D-WS-01 | At the end of every operation at least one workspace exists; `workspace.delete` of the sole workspace changes nothing (no stop, no delete). |
| INV-D-WS-02 | After a successful `workspace.reorder` the `sortOrder` values of all workspaces are exactly `0..n-1` in the new order and every workspace's `updatedAt` increased; an invalid/equal swap writes nothing. |
| INV-D-WS-03 | `workspace.delete` stops every operational service of the workspace before deleting rows (DEV-03) and leaves no child rows (services, providers, ports, groups, memberships) of that workspace. |
| INV-D-WS-04 | A managed avatar file is named `<UPPERCASE-UUID>.png`, is at most 512 px on its longest side (unless raw-imported by [09](09-dataport.md)), and is replaced atomically; a failed image operation never changes the existing file, `imagePath` or `updatedAt`. |
| INV-D-WS-05 | The daemon never deletes, overwrites or writes a file outside `Workspaces/Images` as part of any workspace or image operation. |
| INV-D-WS-06 | The daemon never writes an absolute path into `workspace.imagePath`; it only reads one that already exists in the data. |
| INV-D-WS-07 | After any avatar write or delete, the next `workspace.get_image` (any `size`) reflects the new state. |
| INV-D-WS-08 | `workspace.name` written by the daemon is trimmed and non-empty. |
| INV-D-GRP-01 | A group's `workspaceID` never changes; every membership connects a service and a group of the same workspace. |
| INV-D-GRP-02 | Deleting a group never deletes or modifies any service row; it removes exactly that group's membership rows. |
| INV-D-GRP-03 | `group.create` assigns `max(sortOrder in the workspace) + 1` (first group = 1); `group.reorder` leaves exactly `0..n-1` and bumps every group's `updatedAt` (INV-SIDEBAR-05). |
| INV-D-GRP-04 | `group.name` written by the daemon is trimmed; a blank rename becomes `Untitled Group`. |
| INV-D-SVC-01 | A service created by `service.create` has exactly one provider, `activeProviderID` NULL, and every port mapping it owns has non-NULL `serviceID` and `providerID`. |
| INV-D-SVC-02 | The effective active provider is `service.activeProviderID ?? providers.first?.id`; `provider.delete` of the effective active provider repoints `activeProviderID` to the earliest remaining provider in the same transaction; a service never loses its last provider through the API. |
| INV-D-SVC-03 | `provider.add` makes the added provider active and bumps the service `updatedAt`. |
| INV-D-SVC-04 | `provider.set_ports` deletes only rows with the given `serviceID` **and** `providerID` (never legacy NULL-provider rows) and stores only ports in `1..65535`. |
| INV-D-SVC-05 | `service.set_groups` / `service.toggle_group` never change `service.updatedAt`; `service.update`, `set_starred`, `set_disabled`, `switch_provider` always strictly increase it. |
| INV-D-SVC-06 | `service.duplicate` is atomic, produces fresh ids for the service, every provider and every port mapping, preserves `isDisabled`/`isStarred`, and maps the active provider to its copy (else the first copy). |
| INV-D-SVC-07 | A service with `isDisabled == true` is never operational after `service.set_disabled` returns, and is never a bulk start target. |
| INV-D-SVC-08 | `service.switch_provider` never leaves the old provider's process running after the new `activeProviderID` is committed. |
| INV-D-SVC-09 | `service.list` is a pure function of persisted rows plus the runtime store: identical filters and sort produce identical order; `BulkTargets` is exactly its item list. |
| INV-D-SVC-10 | No response of this spec contains `sshPassword`, `ngrokAuthToken` or kubeconfig plaintext. |
| INV-D-SVC-11 | Every mutation listed in §3.9 emits its event(s) after commit, never before, and never for a no-op. |

---

## 9. Acceptance tests

Tests assert observable RPC results and raw SQL rows unless stated.

### 9.1 Workspaces

| ID | Arrange | Assert |
|----|---------|--------|
| DT-WS-01 | Fresh data dir | `workspace.list` has exactly one workspace named `<First>'s Space`, `sortOrder 0`, `imagePath` absent, `hasImage:false` |
| DT-WS-02 | `workspace.create {name:"  Work  "}` | name `Work`, `sortOrder` equals the previous workspace count, `createdAt == updatedAt`, event `workspace.changed {created}` |
| DT-WS-03 | `workspace.create {name:"   "}` and `{}` | both create a workspace named `New Workspace` (no error) |
| DT-WS-04 | Two creates with the same name | both succeed (no uniqueness) |
| DT-WS-05 | `workspace.update {id, name:"  "}` | `KUMA_WS_NAME_EMPTY`, message `Name cannot be empty`; row unchanged |
| DT-WS-06 | `workspace.update {id, name:" X "}` | stored `X`; `updatedAt` strictly greater; `expectedUpdatedAt` old value on a second call → `KUMA_CONFLICT_STALE`, no write |
| DT-WS-07 | One workspace only, with a running service | `workspace.delete` → `KUMA_WS_LAST_WORKSPACE`; the service is still running; no rows deleted |
| DT-WS-08 | Two workspaces, target has services, groups, providers, ports, memberships, one running service, and an avatar | `workspace.delete` returns `nextWorkspaceId` = first remaining; the running service is stopped before its row disappears (a `service.state_changed` precedes `service.deleted`); all child tables have 0 rows for the target; avatar file gone; other workspace untouched; `workspace.changed {deleted}` emitted last |
| DT-WS-09 | Workspaces A(0),B(1),C(2) | `workspace.delete B` leaves sortOrders 0 and 2 (no renumbering) |
| DT-WS-10 | A,B,C order | `workspace.reorder {fromIndex:0,toIndex:2}` → list C,B,A with `sortOrder` 0,1,2 and every `updatedAt` increased (TC-C06) |
| DT-WS-11 | A,B,C | `workspace.reorder {fromIndex:0,toIndex:5}`, `{fromIndex:-1,toIndex:1}` and `{fromIndex:1,toIndex:1}` succeed as no-ops: order, `updatedAt` unchanged, no event (TC-E05) |
| DT-WS-12 | A,B,C | `workspace.reorder {workspaceIDs:[C,A,B]}` → `sortOrder` C0,A1,B2; `[A,B]` (missing C) and `[A,A,B]` → `KUMA_WS_REORDER_INVALID`; both forms together → `KUMA_WS_REORDER_INVALID` |
| DT-WS-13 | Create with a 2000×1000 JPEG whose EXIF orientation is 6 (rotate 90° clockwise) | `Workspaces/Images/<ID>.png` exists with the PNG signature; orientation applied then downscaled so the longest side is 512, i.e. 256 wide × 512 high; `imagePath == "<ID>.png"` (bare name), `hasImage:true` |
| DT-WS-14 | Create with a 100×60 PNG | stored file is 100×60 (no upscale) |
| DT-WS-15 | `workspace.set_image` with non-image bytes, and with invalid base64 | `KUMA_WS_IMAGE_INVALID`; existing file bytes and `imagePath`, `updatedAt` unchanged (DEV-50, TC-E03); `workspace.create` with the same bytes creates no workspace |
| DT-WS-16 | Workspace with a stored avatar; `workspace.get_image {id}` then `{id,size:32}` | first PNG has max side ≤ 128, second ≤ 32; `{size:5000}` is clamped to 1024 (no upscale beyond file size) |
| DT-WS-17 | Replace the avatar with a different image, then `get_image` | returns the new pixels (no stale cache) (INV-D-WS-07) |
| DT-WS-18 | Workspace without avatar, and one whose file was deleted from disk | `get_image` → `{hasImage:false}` success |
| DT-WS-19 | Hand-set `imagePath` to an absolute path `/tmp/orig.png` (legacy) | `get_image` serves it; `workspace.clear_image` and `workspace.delete` leave `/tmp/orig.png` untouched (DEV-55); `set_image` stores `<ID>.png` and leaves `/tmp/orig.png` untouched |
| DT-WS-20 | Avatar present | `workspace.clear_image` → `imagePath` NULL, managed file deleted, `updatedAt` bumped; calling it again succeeds and bumps again |
| DT-WS-21 | `workspace.update` with `imageBase64` and `clearImage:true` | `KUMA_WS_IMAGE_CONFLICT` |
| DT-WS-22 | Internal `import_raw` of base64 of arbitrary bytes, then `export_raw` | file `<ID>.png` holds the exact raw bytes; export returns the same base64; invalid base64 returns none and writes nothing; `get_image` then returns `hasImage:false` |
| DT-WS-23 | Images dir removed (factory reset), then `workspace.set_image` | directory recreated, file written |
| DT-WS-24 | `workspace.get` / `delete` with an unknown id and with a lowercase valid UUID | `KUMA_WS_NOT_FOUND`; lowercase input finds the row, id emitted uppercase |

### 9.2 Groups

| ID | Arrange | Assert |
|----|---------|--------|
| DT-GRP-01 | Empty workspace; `group.create {workspaceID}` | name `New Group`, `sortOrder 1` (INV-D-GRP-03), event `group.changed {created}` |
| DT-GRP-02 | Create A,B,C then delete B then create D | sortOrders 1,2,3 → 1,3 → D gets 4 (T5) |
| DT-GRP-03 | `group.create {name:"  Ops  "}`, `{name:"   "}`, 300-char name, emoji name | `Ops`, `New Group`, the 300-char name verbatim, the emoji name verbatim |
| DT-GRP-04 | `group.update {id, name:"   "}` | name `Untitled Group` (no error); `{name:" Prod "}` → `Prod`; `updatedAt` bumped |
| DT-GRP-05 | `group.create` with unknown workspace | `KUMA_WS_NOT_FOUND` |
| DT-GRP-06 | Groups D(0), A(1), C(2) after reorder `[D,A,C]` | `sortOrder` exactly 0,1,2; all `updatedAt` increased; `group.reorder` with a missing/extra id → `KUMA_GRP_REORDER_INVALID` |
| DT-GRP-07 | Group G with two member services | `group.delete` removes G and its membership rows; both services still exist unchanged; `group.changed {deleted}` only; `service.list` no longer shows G in `groupIDs` |
| DT-GRP-08 | Two workspaces each with groups | `group.list` returns only the requested workspace's groups; unknown workspace → `[]` |
| DT-GRP-09 | Service in workspace W1 and group in W2 | `service.toggle_group`, `service.set_groups` → `KUMA_GRP_WORKSPACE_MISMATCH`; nothing written (DEV-54) |
| DT-GRP-10 | Client move algorithms on `[A,B,C]` | Move Up on B → `[B,A,C]`; Move Down on B → `[A,C,B]`; Move Up on A and Move Down on C are not offered; drag A onto C → `[B,C,A]`; drag C onto A → `[C,A,B]`; drag A onto A is a no-op |

### 9.3 Services and providers

| ID | Arrange | Assert |
|----|---------|--------|
| DT-SVC-01 | `service.create` for an ssh provider with ports `[2222:22]`, `isStarred:true`, `groupIDs:[G]` | raw rows: service `activeProviderID` NULL, `isStarred 1`, one provider, one `portMapping` with non-NULL `providerID`, one membership; result equals `service.get`; event `service.created` |
| DT-SVC-02 | `service.create {name:"  "}` | `KUMA_SVC_NAME_EMPTY`; nothing written. Name `" Redis "` is stored `Redis`; description `"   "` stored NULL |
| DT-SVC-03 | `service.create` with port `70000` or `0` | `KUMA_SVC_INVALID_PORT` with the row number; nothing written (DEV-56) |
| DT-SVC-04 | `service.create` with unknown workspace / unknown group | `KUMA_WS_NOT_FOUND` / `KUMA_GRP_NOT_FOUND` |
| DT-SVC-05 | Service with providers P1 (older), P2; `activeProviderID` NULL | `service.get.activeProviderID == P1`; `providerOptions` mark P1 active; ports are P1's (TC-C10) |
| DT-SVC-06 | Service with 3 ssh mappings; `service.update {name:"Renamed SSH"}` | the three mappings still exist (TC-C13); `updatedAt` bumped; memberships untouched when `groupIDs` absent |
| DT-SVC-07 | `service.update {groupIDs:[G2]}` on a member of G1 | memberships replaced with fresh `createdAt`; `service.groupID` column unchanged (DT-DAT-34) |
| DT-SVC-08 | `service.update {isStarred:true}` | `KUMA_SVC_FIELD_READONLY` naming `service.set_starred`; same for `isDisabled`, `activeProviderID`, `workspaceID` |
| DT-SVC-09 | `service.update {description:""}` | stored NULL; `name:""` is stored verbatim (empty) |
| DT-SVC-10 | `service.set_starred` without `starred` twice | `true` then `false` (toggle); each bumps `updatedAt`; with `starred:true` twice stays true, bumped each time; unknown id → `KUMA_SVC_NOT_FOUND` (TC-C08) |
| DT-SVC-11 | Running service; `service.set_disabled {disabled:true}` | process stopped, runtime `stopped`, `isDisabled 1`; flag committed before the stop completes; `service.state_changed` emitted (DEV-51) |
| DT-SVC-12 | Disabled service | not included in `StartTargets`; `statuses:["disabled"]` returns it; `statuses:["stopped"]` does not |
| DT-SVC-13 | `service.toggle_group` twice with the same group | result sets `[G]` then `[]`; `service.updatedAt` unchanged both times; `service.set_groups [G1,G1,G2]` yields `[G1,G2]` sorted |
| DT-SVC-14 | Duplicate of a service with 2 providers (active = second), 3 ports (one with NULL `providerID`), groups, `isStarred`, `isDisabled` | new name `<name> (Copy)`; fresh ids for service, providers, ports; providers copied in `createdAt` order; copied active = copy of the second; NULL-provider port re-pointed to the new active provider; memberships copied; flags preserved; `createdAt == updatedAt`; one transaction (injected failure leaves nothing) (TC-C07, DT-DAT-33); event `service.created` with the new id |
| DT-SVC-15 | Duplicate of a service with NULL `activeProviderID` | copy has `activeProviderID` = first copied provider (non-NULL) |
| DT-SVC-16 | Duplicate of a service with no providers and a port | copy has no providers and the port is skipped; unknown id → `KUMA_SVC_NOT_FOUND` with message exactly `Source service not found` |
| DT-SVC-17 | Running service with providers P1 (active), P2; `service.switch_provider {providerID:P2}` | process stopped, `activeProviderID == P2`, `updatedAt` bumped, process restarted using P2 (runtime `running`), `restart:{attempted:true,started:true}`; events `service.updated` before the restart's `service.state_changed` |
| DT-SVC-18 | Stopped service; switch to P2 | no stop/start; `restart.attempted:false`; deck item category becomes P2's (TC-C09) |
| DT-SVC-19 | Switch to the effective active provider | `changed:false`, no write, no event, process untouched |
| DT-SVC-20 | Switch to a provider of another service / unknown id | `KUMA_SVC_PROVIDER_NOT_FOUND`; nothing stopped (DEV-53) |
| DT-SVC-21 | Running service; P2 is misconfigured so start fails | RPC succeeds; runtime `crashed` with exit code 1 and a last-failure message; `restart.error` populated; `activeProviderID == P2` |
| DT-SVC-22 | `provider.add` to a service with one provider | new provider active, service `updatedAt` bumped, no port mappings created; kubernetes provider stores `kubeTargetType 'pod'`, `usePattern 1` |
| DT-SVC-23 | `provider.update` of a provider | provider `updatedAt` bumped; service `updatedAt` unchanged; `serviceID` change rejected by the protocol layer; response has `sshPasswordSet`, no `sshPassword` |
| DT-SVC-24 | Service with P1 (active), P2; `provider.delete P1` | P1 and its port rows gone; `activeProviderID == P2`; service `updatedAt` bumped (DT-DAT-21); `provider.delete P2` (now the last) → `KUMA_SVC_LAST_PROVIDER` |
| DT-SVC-25 | `provider.delete P2` while P1 is active | P1 stays active; service row unchanged |
| DT-SVC-26 | Provider P with mappings; `provider.set_ports` with `[8080:80, 9090:90]` | old rows of P deleted, new rows stored with forced `serviceID`/`providerID`, `TCP`; other provider's rows and legacy NULL-provider rows untouched; no `updatedAt` changes; event `service.updated {ports}` |
| DT-SVC-27 | `provider.set_ports` with duplicate row ids in one batch, and with `[]` | duplicates get fresh ids; `[]` clears P's rows |
| DT-SVC-28 | `provider.set_ports` with a row `65536`, `0`, `-1` | `KUMA_SVC_INVALID_PORT` naming the row; nothing deleted or written; wrong provider → `KUMA_SVC_PROVIDER_NOT_FOUND` |
| DT-SVC-29 | Running service; `service.delete` | process stopped first (`service.state_changed` before `service.deleted`); providers, ports, memberships gone; groups remain; runtime/log state purged (DEV-14) |
| DT-SVC-30 | `service.delete` unknown id | `KUMA_SVC_NOT_FOUND` |
| DT-SVC-31 | `service.get` for a kubernetes provider stored with NULL `kubeTargetType`/`usePattern` | response shows `pod` and `true`; secrets absent, `sshPasswordSet`/`ngrokAuthTokenSet` present (TC-C01 shape: service + 1 provider + filtered ports) |

### 9.4 Deck query

| ID | Arrange | Assert |
|----|---------|--------|
| DT-SVC-40 | Services "Alpha Service" (docker, subtitle `nginx:latest`) and "Beta Worker" (shell) | `search:"Alpha"` → 1 item; `search:"  ALPHA  "` → same (trim + lowercase); empty search → both; `totalCount` is 2 in all cases (TC-UI01) |
| DT-SVC-41 | A service with description `"  dev db  "`, ssh provider labeled `Prod SSH` (host `gw`, user `root`, port 22), local ports 8080 and 8443 | queries `dev db`, `  DEV DB  `, `ssh`, `prod ssh`, `root@gw`, `8443`, `8080` each return it (the key holds the trimmed description, the target `SSH: root@gw:22`, the label `SSH`, the option label `Prod SSH` and the ports); query `dev  db` (two spaces) and `9999` do not |
| DT-SVC-42 | Kubernetes service with `targetName "redis-*"`; running with live target `redis-master-0` | `search:"master"` matches via live target; after stop (no live target) it does not; `search:"redis"` matches in both states |
| DT-SVC-43 | Services across providers | `providers:["shell"]` returns only active-provider-shell services; a service whose active provider is switched leaves/enters the result accordingly |
| DT-SVC-44 | One running, one starting, one reconnecting, one stopping, one stopped, one crashed, one disabled | `statuses:["running"]` → running+starting+reconnecting; `["stopped"]` → stopped+stopping; `["crashed"]` → crashed; `["disabled"]` → only disabled; `["running","disabled"]` → union; a disabled service never appears for `running`/`stopped`/`crashed` even if a stale runtime says running |
| DT-SVC-45 | Starred and unstarred services; group G | `starredOnly:true` → starred only; `groupID:G` → members only; combined = intersection; filters applied in the order of §3.7.3 give the same set regardless of order of evaluation |
| DT-SVC-46 | Names `beta`, `Alpha`, `alpha2`, `Écho` | `sort:"name"` → `Alpha, alpha2, beta, Écho` (case-insensitive collation, accent-significant, `Écho` after `beta` per collation); ties keep creation order |
| DT-SVC-47 | Services with statuses running(Z), starting(B), crashed(A), stopped(C), disabled(D) | `sort:"status"` → running, starting, crashed, then stopped(C) and disabled(D) both priority 5 ordered by name (C, D) |
| DT-SVC-48 | Three services created at t1<t2<t3 | `sort:"created"` → t3, t2, t1; no `sort` → t1, t2, t3 |
| DT-SVC-49 | Service with a label-less ssh provider and one labeled ` Prod ` | `providerOptions[].label` is `""` and `Prod`; `displayLabel` is `SSH` and `Prod`; `isActive` per [01 §3.11.1](01-data-model.md) |
| DT-SVC-50 | Services with: description only; target only; neither; kubernetes running with live target | `subtitle` = trimmed description; trimmed target; `""`; `displaySubtitle` = `SSH`-style category label for the empty one; `k8s: <live>` for the live one |
| DT-SVC-51 | `service.list` for an unknown workspace | `{items:[],totalCount:0}` |
| DT-SVC-52 | Invalid `sort:"newest"`, `statuses:["paused"]`, `providers:["vm"]` | `KUMA_DAT_INVALID_ENUM` |
| DT-SVC-53 | Filters active: `search:"api"`, `statuses:["stopped"]`, `sort:"name"` | `StartTargets` equals the items that are not disabled and not operational in that exact order; `StopTargets` is empty; with one running item `canStopAll` is true only if that item passes the filters |
| DT-SVC-54 | Raw items | no item or detail contains `sshPassword`, `ngrokAuthToken`, or kubeconfig content (INV-D-SVC-10) |

### 9.5 Concurrency, events and wire

| ID | Arrange | Assert |
|----|---------|--------|
| DT-SVC-60 | Two clients: both read service S (`updatedAt` T0); client 1 `service.update` succeeds; client 2 `service.update` with `expectedUpdatedAt: T0` | `KUMA_CONFLICT_STALE`, row unchanged; without `expectedUpdatedAt` the write succeeds (last write wins) |
| DT-SVC-61 | Two updates within one millisecond | `updatedAt` strictly increasing (DEV-22) |
| DT-SVC-62 | Subscribe to events; run `service.create`, `service.update`, `service.set_groups`, `provider.set_ports`, `service.delete`, `group.create`, `group.reorder`, `workspace.create`, `workspace.delete` | the events and `changed`/`change` tags of §3.9 are emitted after commit in order; a no-op swap and a same-provider switch emit none |
| DT-SVC-63 | All responses | UUIDs uppercase (lowercase input accepted), timestamps `YYYY-MM-DDTHH:MM:SS.sssZ`, `groupIDs` sorted ascending, optional absent keys omitted (not `null`) |
| DT-SVC-64 | `service.update` immediately followed by `provider.update` and `provider.set_ports` (the inspector commit shape) | three calls succeed independently; with unchanged ports the client skips `provider.set_ports` and existing mappings stay (TC-C13); a failure of step 2 leaves step 1 committed (non-atomic, as 1.x) |
| DT-SVC-65 | `data.export_service_json` after duplicate/switch | consistent with the stored rows (smoke check that this spec's writes match what [09](09-dataport.md) exports) |

---

## Proposed RPC additions

None. Every method and event used here exists in [00 §5](00-overview-and-conventions.md) and [00 §5.7](00-overview-and-conventions.md). Parameter names in §4 are definitive for spec 04; [10](10-rpc-protocol.md) should adopt them. Two requests for other authors: [06](06-execution-engine.md) should give `service.start_all` / `service.stop_all` the same filter parameters as `service.list` (§3.8), and [08](08-logs-and-events.md) should adopt the minimum payloads of §3.9.

---

## Open questions / residual risks

1. **Image decoding parity.** 1.x decodes with ImageIO (HEIC, RAW, PDF and others) and uses `kCGImageSourceThumbnailMaxPixelSize` whose behavior for sources already smaller than the maximum is believed, not verified, to be "no upscale". Chosen: never upscale; formats beyond the Rust `image` crate's set return `KUMA_WS_IMAGE_INVALID`. A macOS client SHOULD transcode HEIC/RAW to PNG/JPEG before `imageBase64`.
2. **Live Kubernetes target.** `liveTarget` (card subtitle `k8s: <name>` and the search alternative) comes from an ephemeral per-service map set at start and cleared at stop and process exit (`KubernetesRunner`, `ExecutionSupervisor.swift:171`); its source of truth is [06](06-execution-engine.md)/[07](07-kubernetes.md). This spec only consumes it.
3. **Switch-provider failure semantics.** 1.x had two behaviors (deck: `crashed(1)` on any error without validation; inspector: validate first, stay stopped on validation failure). Chosen: one path with `crashed(1)` + last failure (DEV-53).
4. **Name collation.** `localizedCaseInsensitiveCompare` depends on the process locale; the daemon uses CLDR root at secondary strength. Locales with tailored collation (for example Swedish å) may order differently from a 1.x process running under that locale.
5. **`service.update` name.** Parity keeps the inspector's verbatim name (an empty or padded name can be stored, `InspectorConfigFormStack.swift:44-50`). Only `service.create` rejects blank names (DEV-52). A stricter rule would break per-keystroke auto-save from a client that briefly clears the field.
6. **`activeProviderID` is NULL after create.** Parity with `buildPayload`/`insertService`; consumers must use the effective rule ([01 §3.11.1](01-data-model.md)).
7. **Workspace `sortOrder` on create** is the row count, so after deleting a middle workspace the next create can duplicate an existing `sortOrder` (tie-broken by `createdAt, rowid`). Parity retained; `workspace.reorder` repairs it.
8. **`workspace.reorder` swap form** has no 1.x UI caller (tests only) and is kept for parity; clients should use the permutation form.
9. **No edit lock in the daemon.** 1.x locked the inspector while running (`isLocked`, UI only); the daemon lets `provider.add/update/delete` and `service.update` change a running service. The running process is unaffected until restarted; `provider.add` changes the active provider without stopping it. Clients are expected to keep the lock; the daemon does not enforce it.
10. **Non-atomic inspector commit.** The three-call shape (§3.5.12) is non-atomic exactly as in 1.x; a failure after step 1 leaves a partial save. No composite RPC was added to stay inside the registry.
11. **Sidebar placeholder text.** The literal `No groups services` is a 1.x wording quirk (`"No \(title.lowercased()) services"` applied to the node titled `Groups`); recorded verbatim for client fidelity.
12. **`ServiceCardSnapshot` search key for test constructors** (`"\(name) \(subtitle)"`) differs from the deck's composition; only the deck composition (§3.7.2) is normative.
