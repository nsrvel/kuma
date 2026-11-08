# 15 — Traceability and parity

> Aggregated index across daemon specs [00](00-overview-and-conventions.md)–[14](14-lifecycle-and-platform.md). Authoritative per-feature behavior remains in area specs; this document is the **parity gate** checklist and cross-transport matrix.

## 1. Parity gate definition

A daemon build **passes the parity gate** when all of the following hold:

1. **Coverage:** Every `[PARITY]` row in §2 has non-empty **RPC**, **CLI**, **MCP**, **REST**, and **DT** columns (use `—` only where the area spec marks the capability `(internal)` *and* documents a covering DT in the owning spec, e.g. spool capture covered by DT-EXE / DT-LOG).
2. **Wire:** RPC names match [00 §5](00-overview-and-conventions.md); CLI leaves match [11 Appendix A](11-cli.md); MCP tools match [12 §3.3](12-mcp.md); REST routes match [13 §10](13-rest-api.md).
3. **Traceability script:** `check_traceability.py` (CI) validates row counts: 73 RPC methods, 73 CLI leaves, 73 MCP tools, 73 REST primary mappings, and FEAT/RPC cross-links.
4. **`[V2-ADD]`** and **`[CLIENT]`** rows are excluded from the gate but must remain listed so nothing is silently dropped.
5. **Deviations:** Any intentional 1.x behavior change carries a **DEV-NN** id referenced from the FEAT row or area spec.

## 2. Master FEAT matrix

**Row count:** 430 unique `FEAT-*` ids extracted from spec §5 features tables.

| FEAT | Tag | RPC method(s) | CLI path | MCP tool | REST route | Primary spec | DT-xxx |
|------|-----|---------------|----------|----------|------------|--------------|--------|
| FEAT-API-01 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-02 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-03 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-04 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-05 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-06 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-07 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-08 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-09 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-10 | [V2-ADD] | service.start, service.preflight, ports.check, runtime.adopt_report | kuma service start; kuma service preflight; kuma ports check; kuma runtime adopt-report | kuma_service_start; kuma_service_preflight; kuma_ports_check; kuma_runtime_adopt_report | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/preflight; POST /v1/ports/check; GET /v1/runtime/adopt-report | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-11 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-12 | [V2-ADD] | logs.tail, logs.clear, logs.workload_tail | kuma logs tail; kuma logs clear; kuma logs workload-tail | kuma_logs_tail; kuma_logs_clear; kuma_logs_workload_tail | GET /v1/services/{serviceId}/logs/activity; DELETE /v1/services/{serviceId}/logs/activity; GET /v1/services/{serviceId}/logs/workload | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-13 | [V2-ADD] | events.subscribe, events.unsubscribe | kuma events subscribe; kuma events unsubscribe | kuma_events_subscribe; kuma_events_unsubscribe | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-14 | [V2-ADD] | logs.follow | kuma logs follow | kuma_logs_follow | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-15 | [V2-ADD] | events.subscribe, logs.follow | kuma events subscribe; kuma logs follow | kuma_events_subscribe; kuma_logs_follow | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-16 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-API-17 | [V2-ADD] | — | — | — | — | [13-rest-api](13-rest-api.md) | DT-API-01, DT-API-02, DT-API-03, DT-API-04, DT-API-05, DT-API-06, DT-API-07, DT-API-08 |
| FEAT-CLI-01 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-02 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-03 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-04 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-05 | [V2-ADD] | kubeconfig.get, service.get | kuma kubeconfig get; kuma service get | kuma_kubeconfig_get; kuma_service_get | GET /v1/kubeconfigs/{kubeconfigId}; GET /v1/services/{serviceId} | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-06 | [V2-ADD] | services.md | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-07 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-08 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-09 | [V2-ADD] | daemon.status | kuma daemon status | kuma_daemon_status | GET /v1/daemon/status | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-10 | [V2-ADD] | daemon.ping, daemon.shutdown | kuma daemon ping; kuma daemon shutdown | kuma_daemon_ping; kuma_daemon_shutdown | GET /v1/daemon/ping; POST /v1/daemon/shutdown | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-11 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-12 | [V2-ADD] | service.start, service.statuses | kuma service start; kuma service statuses | kuma_service_start; kuma_service_statuses | POST /v1/services/{serviceId}/start; GET /v1/services/statuses | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-13 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-14 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-15 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-16 | [V2-ADD] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-17 | [V2-ADD] | ports.check, runtime.adopt_report | kuma ports check; kuma runtime adopt-report | kuma_ports_check; kuma_runtime_adopt_report | POST /v1/ports/check; GET /v1/runtime/adopt-report | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-18 | [V2-ADD] | mcp.md | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-CLI-19 | [CLIENT] | — | — | — | — | [11-cli](11-cli.md) | DT-CLI-01…DT-CLI-09 (9 in CLI) |
| FEAT-DAT-01 | [PARITY] | daemon.status | kuma daemon status | kuma_daemon_status | GET /v1/daemon/status | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-02 | [PARITY] | — | — | — | — | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-03 | [PARITY] | — | — | — | — | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-04 | [PARITY] | workspace.list | kuma workspace list | kuma_workspace_list | GET /v1/workspaces | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-05 | [PARITY] | workspace.list, workspace.delete | kuma workspace list; kuma workspace delete | kuma_workspace_list; kuma_workspace_delete | GET /v1/workspaces; DELETE /v1/workspaces/{workspaceId} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-06 | [PARITY] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-07 | [PARITY] | data.factory_reset | kuma data factory-reset | kuma_data_factory_reset | POST /v1/data/factory-reset | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-08 | [PARITY] | service.get, service.list, service.switch_provider | kuma service get; kuma service list; kuma service switch-provider | kuma_service_get; kuma_service_list; kuma_service_switch_provider | GET /v1/services/{serviceId}; GET /v1/services; POST /v1/services/{serviceId}/switch-provider | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-09 | [PARITY] | service.get, service.list, provider.set_ports | kuma service get; kuma service list; kuma provider set-ports | kuma_service_get; kuma_service_list; kuma_provider_set_ports | GET /v1/services/{serviceId}; GET /v1/services; PUT /v1/providers/{providerId}/ports | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-10 | [PARITY] | workspace.delete, service.delete, group.delete, provider.delete | kuma workspace delete; kuma service delete; kuma group delete; kuma provider delete | kuma_workspace_delete; kuma_service_delete; kuma_group_delete; kuma_provider_delete | DELETE /v1/workspaces/{workspaceId}; DELETE /v1/services/{serviceId}; DELETE /v1/groups/{groupId}; DELETE /v1/providers/{providerId} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-11 | [PARITY] | workspace.list, group.list, service.list, provider.list, kubeconfig.list | kuma workspace list; kuma group list; kuma service list; kuma provider list; kuma kubeconfig list | kuma_workspace_list; kuma_group_list; kuma_service_list; kuma_provider_list; kuma_kubeconfig_list | GET /v1/workspaces; GET /v1/workspaces/{workspaceId}/groups; GET /v1/services; GET /v1/services/{serviceId}/providers; GET /v1/kubeconfigs | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-12 | [PARITY] | service.set_groups, service.toggle_group | kuma service set-groups; kuma service toggle-group | kuma_service_set_groups; kuma_service_toggle_group | PUT /v1/services/{serviceId}/groups; POST /v1/services/{serviceId}/groups/{groupId}/toggle | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-13 | [PARITY] | provider.add, provider.update, data.import | kuma provider add; kuma provider update; kuma data import | kuma_provider_add; kuma_provider_update; kuma_data_import | POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; POST /v1/data/import | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-14 | [PARITY] | service.get, provider.list, provider.add, provider.update | kuma service get; kuma provider list; kuma provider add; kuma provider update | kuma_service_get; kuma_provider_list; kuma_provider_add; kuma_provider_update | GET /v1/services/{serviceId}; GET /v1/services/{serviceId}/providers; POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-15 | [PARITY] | service.get, service.list, provider.list | kuma service get; kuma service list; kuma provider list | kuma_service_get; kuma_service_list; kuma_provider_list | GET /v1/services/{serviceId}; GET /v1/services; GET /v1/services/{serviceId}/providers | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-16 | [PARITY] | service.list, service.get | kuma service list; kuma service get | kuma_service_list; kuma_service_get | GET /v1/services; GET /v1/services/{serviceId} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-17 | [PARITY] | kubeconfig.list, kubeconfig.get, kubeconfig.delete | kuma kubeconfig list; kuma kubeconfig get; kuma kubeconfig delete | kuma_kubeconfig_list; kuma_kubeconfig_get; kuma_kubeconfig_delete | GET /v1/kubeconfigs; GET /v1/kubeconfigs/{kubeconfigId}; DELETE /v1/kubeconfigs/{kubeconfigId} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-18 | [PARITY] | provider.add, provider.update, kubeconfig.create | kuma provider add; kuma provider update; kuma kubeconfig create | kuma_provider_add; kuma_provider_update; kuma_kubeconfig_create | POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; POST /v1/kubeconfigs | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-19 | [PARITY] | — | — | — | — | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-20 | [CLIENT] | — | — | — | — | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-21 | [PARITY] | service.get, settings.get | kuma service get; kuma settings get | kuma_service_get; kuma_settings_get | GET /v1/services/{serviceId}; GET /v1/settings/{key} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-22 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-23 | [V2-ADD] | settings.list, settings.set, runtime.adopt_report | kuma settings list; kuma settings set; kuma runtime adopt-report | kuma_settings_list; kuma_settings_set; kuma_runtime_adopt_report | GET /v1/settings; PUT /v1/settings; GET /v1/runtime/adopt-report | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-24 | [V2-ADD] | workspace.update, group.update, service.update, provider.update, kubeconfig.update | kuma workspace update; kuma group update; kuma service update; kuma provider update; kuma kubeconfig update | kuma_workspace_update; kuma_group_update; kuma_service_update; kuma_provider_update; kuma_kubeconfig_update | PATCH /v1/workspaces/{workspaceId}; PATCH /v1/groups/{groupId}; PATCH /v1/services/{serviceId}; PATCH /v1/providers/{providerId}; PATCH /v1/kubeconfigs/{kubeconfigId} | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-25 | [V2-ADD] | daemon.status | kuma daemon status | kuma_daemon_status | GET /v1/daemon/status | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-26 | [PARITY] | workspace.get_image, workspace.set_image, workspace.clear_image | kuma workspace get-image; kuma workspace set-image; kuma workspace clear-image | kuma_workspace_get_image; kuma_workspace_set_image; kuma_workspace_clear_image | GET /v1/workspaces/{workspaceId}/image; PUT /v1/workspaces/{workspaceId}/image; DELETE /v1/workspaces/{workspaceId}/image | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-27 | [PARITY] | workspace.create, group.create, group.update, service.duplicate | kuma workspace create; kuma group create; kuma group update; kuma service duplicate | kuma_workspace_create; kuma_group_create; kuma_group_update; kuma_service_duplicate | POST /v1/workspaces; POST /v1/workspaces/{workspaceId}/groups; PATCH /v1/groups/{groupId}; POST /v1/services/{serviceId}/duplicate | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DAT-28 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [01-data-model](01-data-model.md) | DT-DAT-01…DT-DAT-34 (34 in DAT) |
| FEAT-DPT-01 | [PARITY] | data.export, data.import | kuma data export; kuma data import | kuma_data_export; kuma_data_import | POST /v1/data/export; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-02 | [PARITY] | data.export, data.import, data.import_preview | kuma data export; kuma data import; kuma data import-preview | kuma_data_export; kuma_data_import; kuma_data_import_preview | POST /v1/data/export; POST /v1/data/import; POST /v1/data/import/preview | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-03 | [PARITY] | data.export_service_json, data.import_preview, data.import | kuma data export-service-json; kuma data import-preview; kuma data import | kuma_data_export_service_json; kuma_data_import_preview; kuma_data_import | GET /v1/services/{serviceId}/export-json; POST /v1/data/import/preview; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-04 | [PARITY] | data.export, data.import | kuma data export; kuma data import | kuma_data_export; kuma_data_import | POST /v1/data/export; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-05 | [PARITY] | data.export_service_json | kuma data export-service-json | kuma_data_export_service_json | GET /v1/services/{serviceId}/export-json | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-06 | [PARITY] | data.import_preview, data.import | kuma data import-preview; kuma data import | kuma_data_import_preview; kuma_data_import | POST /v1/data/import/preview; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-07 | [PARITY] | data.import_preview, data.import | kuma data import-preview; kuma data import | kuma_data_import_preview; kuma_data_import | POST /v1/data/import/preview; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-08 | [PARITY] | data.export | kuma data export | kuma_data_export | POST /v1/data/export | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-09 | [PARITY] | data.import_preview, data.import | kuma data import-preview; kuma data import | kuma_data_import_preview; kuma_data_import | POST /v1/data/import/preview; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-10 | [PARITY] | data.export | kuma data export | kuma_data_export | POST /v1/data/export | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-11 | [PARITY] | data.export | kuma data export | kuma_data_export | POST /v1/data/export | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-12 | [PARITY] | data.export | kuma data export | kuma_data_export | POST /v1/data/export | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-13 | [PARITY] | data.export_service_json | kuma data export-service-json | kuma_data_export_service_json | GET /v1/services/{serviceId}/export-json | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-14 | [PARITY] | data.export | kuma data export | kuma_data_export | POST /v1/data/export | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-15 | [PARITY] | data.export, data.export_service_json | kuma data export; kuma data export-service-json | kuma_data_export; kuma_data_export_service_json | POST /v1/data/export; GET /v1/services/{serviceId}/export-json | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-16 | [PARITY] | data.export | kuma data export | kuma_data_export | POST /v1/data/export | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-17 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-18 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-19 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-20 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-21 | [PARITY] | data.export, data.export_service_json | kuma data export; kuma data export-service-json | kuma_data_export; kuma_data_export_service_json | POST /v1/data/export; GET /v1/services/{serviceId}/export-json | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-22 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-23 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-24 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-25 | [CLIENT] | — | — | — | — | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-26 | [PARITY] | data.factory_reset | kuma data factory-reset | kuma_data_factory_reset | POST /v1/data/factory-reset | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-27 | [PARITY] | data.import_preview, data.import | kuma data import-preview; kuma data import | kuma_data_import_preview; kuma_data_import | POST /v1/data/import/preview; POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-28 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-29 | [PARITY] | data.import_preview | kuma data import-preview | kuma_data_import_preview | POST /v1/data/import/preview | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-30 | [V2-ADD] | data.import_preview | kuma data import-preview | kuma_data_import_preview | POST /v1/data/import/preview | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-31 | [CLIENT] | — | — | — | — | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-32 | [CLIENT] | — | — | — | — | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-33 | [CLIENT] | — | — | — | — | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-34 | [CLIENT] | — | — | — | — | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-35 | [CLIENT] | — | — | — | — | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-DPT-36 | [PARITY] | data.import, data.factory_reset | kuma data import; kuma data factory-reset | kuma_data_import; kuma_data_factory_reset | POST /v1/data/import; POST /v1/data/factory-reset | [09-dataport](09-dataport.md) | DT-DPT-01…DT-DPT-32 (32 in DPT) |
| FEAT-EXE-01 | [PARITY] | service.start, service.stop | kuma service start; kuma service stop | kuma_service_start; kuma_service_stop | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/stop | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-02 | [PARITY] | service.start, service.stop | kuma service start; kuma service stop | kuma_service_start; kuma_service_stop | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/stop | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-03 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-04 | [PARITY] | service.start, service.start_all | kuma service start; kuma service start-all | kuma_service_start; kuma_service_start_all | POST /v1/services/{serviceId}/start; POST /v1/services/start-all | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-05 | [PARITY] | service.status | kuma service status | kuma_service_status | GET /v1/services/{serviceId}/status | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-06 | [PARITY] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-07 | [PARITY] | events.subscribe | kuma events subscribe | kuma_events_subscribe | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-08 | [V2-ADD] | service.start, service.stop, service.restart | kuma service start; kuma service stop; kuma service restart | kuma_service_start; kuma_service_stop; kuma_service_restart | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/stop; POST /v1/services/{serviceId}/restart | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-09 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-10 | [PARITY] | service.start, service.restart, service.start_all | kuma service start; kuma service restart; kuma service start-all | kuma_service_start; kuma_service_restart; kuma_service_start_all | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/restart; POST /v1/services/start-all | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-11 | [PARITY] | service.stop | kuma service stop | kuma_service_stop | POST /v1/services/{serviceId}/stop | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-12 | [PARITY] | service.stop | kuma service stop | kuma_service_stop | POST /v1/services/{serviceId}/stop | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-13 | [PARITY] | service.restart | kuma service restart | kuma_service_restart | POST /v1/services/{serviceId}/restart | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-14 | [PARITY] | service.start_all, service.stop_all | kuma service start-all; kuma service stop-all | kuma_service_start_all; kuma_service_stop_all | POST /v1/services/start-all; POST /v1/services/stop-all | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-15 | [PARITY] | service.set_disabled | kuma service set-disabled | kuma_service_set_disabled | PUT /v1/services/{serviceId}/disabled | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-16 | [PARITY] | service.switch_provider | kuma service switch-provider | kuma_service_switch_provider | POST /v1/services/{serviceId}/switch-provider | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-17 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-18 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-19 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-20 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-21 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-22 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-23 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-24 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-25 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-26 | [PARITY] | service.stop | kuma service stop | kuma_service_stop | POST /v1/services/{serviceId}/stop | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-27 | [PARITY] | service.stop | kuma service stop | kuma_service_stop | POST /v1/services/{serviceId}/stop | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-28 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-29 | [PARITY] | service.status | kuma service status | kuma_service_status | GET /v1/services/{serviceId}/status | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-30 | [PARITY] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-31 | [PARITY] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-32 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-33 | [V2-ADD] | ports.check | kuma ports check | kuma_ports_check | POST /v1/ports/check | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-34 | [PARITY] | service.start, service.preflight | kuma service start; kuma service preflight | kuma_service_start; kuma_service_preflight | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/preflight | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-35 | [PARITY] | settings.get | kuma settings get | kuma_settings_get | GET /v1/settings/{key} | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-36 | [PARITY] | events.subscribe | kuma events subscribe | kuma_events_subscribe | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-37 | [PARITY] | events.subscribe | kuma events subscribe | kuma_events_subscribe | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-38 | [PARITY] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-39 | [PARITY] | daemon.shutdown | kuma daemon shutdown | kuma_daemon_shutdown | POST /v1/daemon/shutdown | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-40 | [V2-ADD] | runtime.adopt_report | kuma runtime adopt-report | kuma_runtime_adopt_report | GET /v1/runtime/adopt-report | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-41 | [PARITY] | service.status, service.statuses | kuma service status; kuma service statuses | kuma_service_status; kuma_service_statuses | GET /v1/services/{serviceId}/status; GET /v1/services/statuses | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-42 | [CLIENT] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-43 | [CLIENT] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-44 | [CLIENT] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-45 | [CLIENT] | — | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-46 | [PARITY] | service.status | kuma service status | kuma_service_status | GET /v1/services/{serviceId}/status | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-47 | [PARITY] | service.log_line | — | — | — | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-EXE-48 | [PARITY] | settings.get | kuma settings get | kuma_settings_get | GET /v1/settings/{key} | [06-execution-engine](06-execution-engine.md) | DT-EXE-01…DT-EXE-22 (22 in EXE) |
| FEAT-GRP-01 | [PARITY] | group.list | kuma group list | kuma_group_list | GET /v1/workspaces/{workspaceId}/groups | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-02 | [PARITY] | group.create | kuma group create | kuma_group_create | POST /v1/workspaces/{workspaceId}/groups | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-03 | [PARITY] | group.update | kuma group update | kuma_group_update | PATCH /v1/groups/{groupId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-04 | [PARITY] | group.delete | kuma group delete | kuma_group_delete | DELETE /v1/groups/{groupId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-05 | [PARITY] | group.reorder | kuma group reorder | kuma_group_reorder | PUT /v1/workspaces/{workspaceId}/groups/order | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-06 | [PARITY] | group.create, service.set_groups, service.toggle_group | kuma group create; kuma service set-groups; kuma service toggle-group | kuma_group_create; kuma_service_set_groups; kuma_service_toggle_group | POST /v1/workspaces/{workspaceId}/groups; PUT /v1/services/{serviceId}/groups; POST /v1/services/{serviceId}/groups/{groupId}/toggle | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-07 | [PARITY] | service.set_groups, service.toggle_group, service.update | kuma service set-groups; kuma service toggle-group; kuma service update | kuma_service_set_groups; kuma_service_toggle_group; kuma_service_update | PUT /v1/services/{serviceId}/groups; POST /v1/services/{serviceId}/groups/{groupId}/toggle; PATCH /v1/services/{serviceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-08 | [PARITY] | group.create, group.update, group.delete, group.reorder | kuma group create; kuma group update; kuma group delete; kuma group reorder | kuma_group_create; kuma_group_update; kuma_group_delete; kuma_group_reorder | POST /v1/workspaces/{workspaceId}/groups; PATCH /v1/groups/{groupId}; DELETE /v1/groups/{groupId}; PUT /v1/workspaces/{workspaceId}/groups/order | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-09 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-10 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-11 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-12 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-13 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-GRP-14 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-GRP-01…DT-GRP-10 (10 in GRP) |
| FEAT-LIF-01 | [V2-ADD] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-02 | [V2-ADD] | daemon.ping | kuma daemon ping | kuma_daemon_ping | GET /v1/daemon/ping | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-03 | [V2-ADD] | daemon.status | kuma daemon status | kuma_daemon_status | GET /v1/daemon/status | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-04 | [PARITY] | daemon.ping | kuma daemon ping | kuma_daemon_ping | GET /v1/daemon/ping | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-05 | [V2-ADD] | daemon.status | kuma daemon status | kuma_daemon_status | GET /v1/daemon/status | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-06 | [V2-ADD] | daemon.shutdown | kuma daemon shutdown | kuma_daemon_shutdown | POST /v1/daemon/shutdown | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-07 | [V2-ADD] | events.subscribe | kuma events subscribe | kuma_events_subscribe | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-08 | [V2-ADD] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-09 | [V2-ADD] | runtime.adopt_report | kuma runtime adopt-report | kuma_runtime_adopt_report | GET /v1/runtime/adopt-report | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-10 | [PARITY] | events.subscribe | kuma events subscribe | kuma_events_subscribe | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-11 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-12 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-13 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-14 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-15 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-16 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-17 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-18 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-19 | [PARITY] | daemon.shutdown | kuma daemon shutdown | kuma_daemon_shutdown | POST /v1/daemon/shutdown | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-20 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-21 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-22 | [CLIENT] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-23 | [PARITY] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-24 | [V2-ADD] | daemon.status | kuma daemon status | kuma_daemon_status | GET /v1/daemon/status | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-25 | [V2-ADD] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LIF-26 | [V2-ADD] | — | — | — | — | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | DT-LIF-01…DT-LIF-15 (15 in LIF) |
| FEAT-LOG-01 | [PARITY] | engine.md | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-02 | [PARITY] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-03 | [PARITY] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-04 | [DEV] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-05 | [DEV] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-06 | [PARITY] | engine.md | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-07 | [PARITY] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-08 | [DEV] | logs.tail, logs.clear | kuma logs tail; kuma logs clear | kuma_logs_tail; kuma_logs_clear | GET /v1/services/{serviceId}/logs/activity; DELETE /v1/services/{serviceId}/logs/activity | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-09 | [PARITY] | service.log_line | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-10 | [PARITY] | service.log_line | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-11 | [PARITY] | service.log_line | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-12 | [PARITY] | service.log_line, service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-13 | [PARITY] | logs.tail | kuma logs tail | kuma_logs_tail | GET /v1/services/{serviceId}/logs/activity | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-14 | [PARITY] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-15 | [PARITY] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-16 | [PARITY] | logs.tail, service.log_line | kuma logs tail | kuma_logs_tail | GET /v1/services/{serviceId}/logs/activity | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-17 | [PARITY] | logs.tail | kuma logs tail | kuma_logs_tail | GET /v1/services/{serviceId}/logs/activity | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-18 | [PARITY] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-19 | [PARITY] | logs.tail | kuma logs tail | kuma_logs_tail | GET /v1/services/{serviceId}/logs/activity | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-20 | [PARITY] | logs.clear | kuma logs clear | kuma_logs_clear | DELETE /v1/services/{serviceId}/logs/activity | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-21 | [V2-ADD] | logs.workload_tail | kuma logs workload-tail | kuma_logs_workload_tail | GET /v1/services/{serviceId}/logs/workload | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-22 | [V2-ADD] | logs.follow, service.log_line | kuma logs follow | kuma_logs_follow | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-23 | [V2-ADD] | events.subscribe | kuma events subscribe | kuma_events_subscribe | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-24 | [V2-ADD] | events.unsubscribe | kuma events unsubscribe | kuma_events_unsubscribe | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-25 | [V2-ADD] | service.log_line | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-26 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-27 | [DEV] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-28 | [CLIENT] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-29 | [CLIENT] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-30 | [CLIENT] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-LOG-31 | [CLIENT] | — | — | — | — | [08-logs-and-events](08-logs-and-events.md) | DT-LOG-01…DT-LOG-18 (18 in LOG) |
| FEAT-MCP-01 | [V2-ADD] | — | — | — | — | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-02 | [V2-ADD] | — | — | — | — | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-03 | [V2-ADD] | conventions.md | — | — | — | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-04 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-05 | [V2-ADD] | — | — | — | — | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-06 | [V2-ADD] | daemon.status, settings.list, workspace.list, env.dependencies | kuma daemon status; kuma settings list; kuma workspace list; kuma env dependencies | kuma_daemon_status; kuma_settings_list; kuma_workspace_list; kuma_env_dependencies | GET /v1/daemon/status; GET /v1/settings; GET /v1/workspaces; GET /v1/env/dependencies | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-07 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-08 | [V2-ADD] | events.subscribe, logs.follow | kuma events subscribe; kuma logs follow | kuma_events_subscribe; kuma_logs_follow | — | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-MCP-09 | [V2-ADD] | data.factory_reset | kuma data factory-reset | kuma_data_factory_reset | POST /v1/data/factory-reset | [12-mcp](12-mcp.md) | DT-MCP-01…DT-MCP-09 (9 in MCP) |
| FEAT-PRV-01 | [PARITY] | service.create, provider.add, provider.update | kuma service create; kuma provider add; kuma provider update | kuma_service_create; kuma_provider_add; kuma_provider_update | POST /v1/workspaces/{workspaceId}/services; POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-02 | [PARITY] | service.get, service.list, provider.list | kuma service get; kuma service list; kuma provider list | kuma_service_get; kuma_service_list; kuma_provider_list | GET /v1/services/{serviceId}; GET /v1/services; GET /v1/services/{serviceId}/providers | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-03 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-04 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-05 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-06 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-07 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-08 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-09 | [PARITY] | service.create, provider.update, service.preflight | kuma service create; kuma provider update; kuma service preflight | kuma_service_create; kuma_provider_update; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-10 | [PARITY] | service.create, provider.add, provider.update | kuma service create; kuma provider add; kuma provider update | kuma_service_create; kuma_provider_add; kuma_provider_update | POST /v1/workspaces/{workspaceId}/services; POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-11 | [PARITY] | service.create | kuma service create | kuma_service_create | POST /v1/workspaces/{workspaceId}/services | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-12 | [V2-ADD] | service.create | kuma service create | kuma_service_create | POST /v1/workspaces/{workspaceId}/services | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-13 | [V2-ADD] | service.create, provider.set_ports, service.preflight | kuma service create; kuma provider set-ports; kuma service preflight | kuma_service_create; kuma_provider_set_ports; kuma_service_preflight | POST /v1/workspaces/{workspaceId}/services; PUT /v1/providers/{providerId}/ports; POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-14 | [PARITY] | service.create | kuma service create | kuma_service_create | POST /v1/workspaces/{workspaceId}/services | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-15 | [CLIENT] | — | — | — | — | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-16 | [PARITY] | provider.add | kuma provider add | kuma_provider_add | POST /v1/services/{serviceId}/providers | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-17 | [PARITY] | provider.update | kuma provider update | kuma_provider_update | PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-18 | [PARITY] | provider.update | kuma provider update | kuma_provider_update | PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-19 | [PARITY] | provider.update, provider.add | kuma provider update; kuma provider add | kuma_provider_update; kuma_provider_add | PATCH /v1/providers/{providerId}; POST /v1/services/{serviceId}/providers | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-20 | [V2-ADD] | service.create, provider.add, provider.update | kuma service create; kuma provider add; kuma provider update | kuma_service_create; kuma_provider_add; kuma_provider_update | POST /v1/workspaces/{workspaceId}/services; POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-21 | [PARITY] | provider.update | kuma provider update | kuma_provider_update | PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-22 | [V2-ADD] | provider.add, provider.update, provider.delete, provider.set_ports | kuma provider add; kuma provider update; kuma provider delete; kuma provider set-ports | kuma_provider_add; kuma_provider_update; kuma_provider_delete; kuma_provider_set_ports | POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; DELETE /v1/providers/{providerId}; PUT /v1/providers/{providerId}/ports | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-23 | [V2-ADD] | provider.delete | kuma provider delete | kuma_provider_delete | DELETE /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-24 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-25 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-26 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-27 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-28 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-29 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-30 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-31 | [V2-ADD] | service.preflight, kubeconfig.test_connection | kuma service preflight; kuma kubeconfig test-connection | kuma_service_preflight; kuma_kubeconfig_test_connection | POST /v1/services/{serviceId}/preflight; POST /v1/kubeconfigs/{kubeconfigId}/test-connection | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-32 | [PARITY] | service.preflight, service.start | kuma service preflight; kuma service start | kuma_service_preflight; kuma_service_start | POST /v1/services/{serviceId}/preflight; POST /v1/services/{serviceId}/start | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-33 | [V2-ADD] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-34 | [CLIENT] | — | — | — | — | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-35 | [PARITY] | service.create, service.preflight, service.start | kuma service create; kuma service preflight; kuma service start | kuma_service_create; kuma_service_preflight; kuma_service_start | POST /v1/workspaces/{workspaceId}/services; POST /v1/services/{serviceId}/preflight; POST /v1/services/{serviceId}/start | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-36 | [PARITY] | service.create, provider.update | kuma service create; kuma provider update | kuma_service_create; kuma_provider_update | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/providers/{providerId} | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-PRV-37 | [CLIENT] | — | — | — | — | [05-providers-and-validation](05-providers-and-validation.md) | DT-PRV-01…DT-PRV-48 (48 in PRV) |
| FEAT-RPC-01 | [V2-ADD] | — | — | — | — | [10-rpc-protocol](10-rpc-protocol.md) | DT-RPC-01, DT-RPC-02, DT-RPC-03, DT-RPC-04, DT-RPC-05, DT-RPC-06, DT-RPC-07 |
| FEAT-RPC-02 | [V2-ADD] | — | — | — | — | [10-rpc-protocol](10-rpc-protocol.md) | DT-RPC-01, DT-RPC-02, DT-RPC-03, DT-RPC-04, DT-RPC-05, DT-RPC-06, DT-RPC-07 |
| FEAT-RPC-03 | [V2-ADD] | — | — | — | — | [10-rpc-protocol](10-rpc-protocol.md) | DT-RPC-01, DT-RPC-02, DT-RPC-03, DT-RPC-04, DT-RPC-05, DT-RPC-06, DT-RPC-07 |
| FEAT-RPC-04 | [V2-ADD] | — | — | — | — | [10-rpc-protocol](10-rpc-protocol.md) | DT-RPC-01, DT-RPC-02, DT-RPC-03, DT-RPC-04, DT-RPC-05, DT-RPC-06, DT-RPC-07 |
| FEAT-RPC-05 | [V2-ADD] | — | — | — | — | [10-rpc-protocol](10-rpc-protocol.md) | DT-RPC-01, DT-RPC-02, DT-RPC-03, DT-RPC-04, DT-RPC-05, DT-RPC-06, DT-RPC-07 |
| FEAT-RPC-06 | [V2-ADD] | — | — | — | — | [10-rpc-protocol](10-rpc-protocol.md) | DT-RPC-01, DT-RPC-02, DT-RPC-03, DT-RPC-04, DT-RPC-05, DT-RPC-06, DT-RPC-07 |
| FEAT-SEC-01 | [PARITY] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-02 | [PARITY] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-03 | [PARITY] | provider.add, provider.update, provider.list, service.create, service.duplicate, service.get | kuma provider add; kuma provider update; kuma provider list; kuma service create; kuma service duplicate; kuma service get | kuma_provider_add; kuma_provider_update; kuma_provider_list; kuma_service_create; kuma_service_duplicate; kuma_service_get | POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; GET /v1/services/{serviceId}/providers; POST /v1/workspaces/{workspaceId}/services; POST /v1/services/{serviceId}/duplicate; GET /v1/services/{serviceId} | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-04 | [PARITY] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-05 | [PARITY] | kubeconfig.create, kubeconfig.update, kubeconfig.get, kubeconfig.list | kuma kubeconfig create; kuma kubeconfig update; kuma kubeconfig get; kuma kubeconfig list | kuma_kubeconfig_create; kuma_kubeconfig_update; kuma_kubeconfig_get; kuma_kubeconfig_list | POST /v1/kubeconfigs; PATCH /v1/kubeconfigs/{kubeconfigId}; GET /v1/kubeconfigs/{kubeconfigId}; GET /v1/kubeconfigs | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-06 | [PARITY] | provider.list, service.get, data.import | kuma provider list; kuma service get; kuma data import | kuma_provider_list; kuma_service_get; kuma_data_import | GET /v1/services/{serviceId}/providers; GET /v1/services/{serviceId}; POST /v1/data/import | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-07 | [PARITY] | provider.add, provider.update, kubeconfig.create, data.import | kuma provider add; kuma provider update; kuma kubeconfig create; kuma data import | kuma_provider_add; kuma_provider_update; kuma_kubeconfig_create; kuma_data_import | POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; POST /v1/kubeconfigs; POST /v1/data/import | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-08 | [PARITY] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-09 | [PARITY] | data.export, data.export_service_json | kuma data export; kuma data export-service-json | kuma_data_export; kuma_data_export_service_json | POST /v1/data/export; GET /v1/services/{serviceId}/export-json | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-10 | [PARITY] | data.export, data.export_service_json, data.import | kuma data export; kuma data export-service-json; kuma data import | kuma_data_export; kuma_data_export_service_json; kuma_data_import | POST /v1/data/export; GET /v1/services/{serviceId}/export-json; POST /v1/data/import | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-11 | [PARITY] | data.import | kuma data import | kuma_data_import | POST /v1/data/import | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-12 | [PARITY] | service.start, service.restart | kuma service start; kuma service restart | kuma_service_start; kuma_service_restart | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/restart | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-13 | [PARITY] | service.start, service.stop, service.restart | kuma service start; kuma service stop; kuma service restart | kuma_service_start; kuma_service_stop; kuma_service_restart | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/stop; POST /v1/services/{serviceId}/restart | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-14 | [PARITY] | service.start, kubeconfig.test_connection | kuma service start; kuma kubeconfig test-connection | kuma_service_start; kuma_kubeconfig_test_connection | POST /v1/services/{serviceId}/start; POST /v1/kubeconfigs/{kubeconfigId}/test-connection | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-15 | [PARITY] | kubeconfig.test_connection, service.preflight | kuma kubeconfig test-connection; kuma service preflight | kuma_kubeconfig_test_connection; kuma_service_preflight | POST /v1/kubeconfigs/{kubeconfigId}/test-connection; POST /v1/services/{serviceId}/preflight | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-16 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-17 | [PARITY] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-18 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-19 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-20 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-21 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-22 | [V2-ADD] | daemon.rotate_api_token | kuma daemon rotate-api-token | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-30 |
| FEAT-SEC-23 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-24 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-25 | [V2-ADD] | provider.list, provider.add, provider.update, service.get, service.list, kubeconfig.list, kubeconfig.get | kuma provider list; kuma provider add; kuma provider update; kuma service get; kuma service list; kuma kubeconfig list; kuma kubeconfig get | kuma_provider_list; kuma_provider_add; kuma_provider_update; kuma_service_get; kuma_service_list; kuma_kubeconfig_list; kuma_kubeconfig_get | GET /v1/services/{serviceId}/providers; POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; GET /v1/services/{serviceId}; GET /v1/services; GET /v1/kubeconfigs; GET /v1/kubeconfigs/{kubeconfigId} | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-26 | [V2-ADD] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-27 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-28 | [V2-ADD] | runtime.adopt_report, daemon.status | kuma runtime adopt-report; kuma daemon status | kuma_runtime_adopt_report; kuma_daemon_status | GET /v1/runtime/adopt-report; GET /v1/daemon/status | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-29 | [V2-ADD] | (all RPC) | (all CLI) | (all MCP) | (all REST) | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-30 | [V2-ADD] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-31 | [V2-ADD] | service.start, service.stop | kuma service start; kuma service stop | kuma_service_start; kuma_service_stop | POST /v1/services/{serviceId}/start; POST /v1/services/{serviceId}/stop | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-32 | [V2-ADD] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-33 | [CLIENT] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-34 | [CLIENT] | — | — | — | — | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SEC-35 | [PARITY] | kubeconfig.list, kubeconfig.get, kubeconfig.delete | kuma kubeconfig list; kuma kubeconfig get; kuma kubeconfig delete | kuma_kubeconfig_list; kuma_kubeconfig_get; kuma_kubeconfig_delete | GET /v1/kubeconfigs; GET /v1/kubeconfigs/{kubeconfigId}; DELETE /v1/kubeconfigs/{kubeconfigId} | [02-security-and-secrets](02-security-and-secrets.md) | DT-SEC-01…DT-SEC-40 (40 in SEC) |
| FEAT-SET-01 | [PARITY] | settings.list, settings.get | kuma settings list; kuma settings get | kuma_settings_list; kuma_settings_get | GET /v1/settings; GET /v1/settings/{key} | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-02 | [PARITY] | settings.set | kuma settings set | kuma_settings_set | PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-03 | [V2-ADD] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-04 | [PARITY] | settings.reset | kuma settings reset | kuma_settings_reset | POST /v1/settings/reset | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-05 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-06 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-07 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-08 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-09 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-10 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-11 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-12 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-13 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-14 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-15 | [PARITY] | engine.md | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-16 | [PARITY] | settings.get, settings.set, env.resolve_executable | kuma settings get; kuma settings set; kuma env resolve-executable | kuma_settings_get; kuma_settings_set; kuma_env_resolve_executable | GET /v1/settings/{key}; PUT /v1/settings; POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-17 | [PARITY] | settings.get, settings.set, env.dependencies | kuma settings get; kuma settings set; kuma env dependencies | kuma_settings_get; kuma_settings_set; kuma_env_dependencies | GET /v1/settings/{key}; PUT /v1/settings; GET /v1/env/dependencies | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-18 | [PARITY] | settings.get, settings.set, env.resolve_executable | kuma settings get; kuma settings set; kuma env resolve-executable | kuma_settings_get; kuma_settings_set; kuma_env_resolve_executable | GET /v1/settings/{key}; PUT /v1/settings; POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-19 | [PARITY] | settings.get, settings.set, env.resolve_executable | kuma settings get; kuma settings set; kuma env resolve-executable | kuma_settings_get; kuma_settings_set; kuma_env_resolve_executable | GET /v1/settings/{key}; PUT /v1/settings; POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-20 | [PARITY] | settings.get, settings.set, env.resolve_executable | kuma settings get; kuma settings set; kuma env resolve-executable | kuma_settings_get; kuma_settings_set; kuma_env_resolve_executable | GET /v1/settings/{key}; PUT /v1/settings; POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-21 | [PARITY] | settings.get, settings.set, env.resolve_executable | kuma settings get; kuma settings set; kuma env resolve-executable | kuma_settings_get; kuma_settings_set; kuma_env_resolve_executable | GET /v1/settings/{key}; PUT /v1/settings; POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-22 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-23 | [PARITY] | env.validate_binary, settings.set | kuma env validate-binary; kuma settings set | kuma_env_validate_binary; kuma_settings_set | POST /v1/env/validate-binary; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-24 | [PARITY] | settings.set | kuma settings set | kuma_settings_set | PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-25 | [V2-ADD] | settings.set | kuma settings set | kuma_settings_set | PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-26 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-27 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-28 | [PARITY] | env.path | kuma env path | kuma_env_path | GET /v1/env/path | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-29 | [PARITY] | env.refresh | kuma env refresh | kuma_env_refresh | POST /v1/env/refresh | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-30 | [PARITY] | env.resolve_executable | kuma env resolve-executable | kuma_env_resolve_executable | POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-31 | [PARITY] | env.resolve_executable | kuma env resolve-executable | kuma_env_resolve_executable | POST /v1/env/resolve-executable | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-32 | [PARITY] | env.dependencies | kuma env dependencies | kuma_env_dependencies | GET /v1/env/dependencies | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-33 | [PARITY] | env.dependencies | kuma env dependencies | kuma_env_dependencies | GET /v1/env/dependencies | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-34 | [PARITY] | env.dependencies | kuma env dependencies | kuma_env_dependencies | GET /v1/env/dependencies | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-35 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-36 | [PARITY] | settings.get, settings.set | kuma settings get; kuma settings set | kuma_settings_get; kuma_settings_set | GET /v1/settings/{key}; PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-37 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-38 | [V2-ADD] | settings.list | kuma settings list | kuma_settings_list | GET /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-39 | [V2-ADD] | settings.get, settings.set, settings.list | kuma settings get; kuma settings set; kuma settings list | kuma_settings_get; kuma_settings_set; kuma_settings_list | GET /v1/settings/{key}; PUT /v1/settings; GET /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-40 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-41 | [PARITY] | settings.set, settings.reset | kuma settings set; kuma settings reset | kuma_settings_set; kuma_settings_reset | PUT /v1/settings; POST /v1/settings/reset | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-42 | [CLIENT] | — | — | — | — | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SET-43 | [PARITY] | settings.set | kuma settings set | kuma_settings_set | PUT /v1/settings | [03-settings-and-environment](03-settings-and-environment.md) | DT-SET-01…DT-SET-35 (35 in SET) |
| FEAT-SVC-01 | [PARITY] | service.list | kuma service list | kuma_service_list | GET /v1/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-02 | [PARITY] | service.list | kuma service list | kuma_service_list | GET /v1/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-03 | [PARITY] | service.list | kuma service list | kuma_service_list | GET /v1/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-04 | [PARITY] | service.list | kuma service list | kuma_service_list | GET /v1/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-05 | [PARITY] | service.list | kuma service list | kuma_service_list | GET /v1/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-06 | [PARITY] | service.get | kuma service get | kuma_service_get | GET /v1/services/{serviceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-07 | [PARITY] | service.create | kuma service create | kuma_service_create | POST /v1/workspaces/{workspaceId}/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-08 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-09 | [PARITY] | service.update | kuma service update | kuma_service_update | PATCH /v1/services/{serviceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-10 | [PARITY] | service.delete | kuma service delete | kuma_service_delete | DELETE /v1/services/{serviceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-11 | [PARITY] | service.duplicate | kuma service duplicate | kuma_service_duplicate | POST /v1/services/{serviceId}/duplicate | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-12 | [PARITY] | service.set_starred | kuma service set-starred | kuma_service_set_starred | PUT /v1/services/{serviceId}/starred | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-13 | [PARITY] | service.set_disabled | kuma service set-disabled | kuma_service_set_disabled | PUT /v1/services/{serviceId}/disabled | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-14 | [PARITY] | service.set_groups | kuma service set-groups | kuma_service_set_groups | PUT /v1/services/{serviceId}/groups | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-15 | [PARITY] | service.toggle_group | kuma service toggle-group | kuma_service_toggle_group | POST /v1/services/{serviceId}/groups/{groupId}/toggle | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-16 | [PARITY] | service.switch_provider | kuma service switch-provider | kuma_service_switch_provider | POST /v1/services/{serviceId}/switch-provider | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-17 | [PARITY] | provider.list | kuma provider list | kuma_provider_list | GET /v1/services/{serviceId}/providers | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-18 | [PARITY] | provider.add | kuma provider add | kuma_provider_add | POST /v1/services/{serviceId}/providers | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-19 | [PARITY] | provider.update | kuma provider update | kuma_provider_update | PATCH /v1/providers/{providerId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-20 | [PARITY] | provider.delete | kuma provider delete | kuma_provider_delete | DELETE /v1/providers/{providerId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-21 | [PARITY] | provider.set_ports | kuma provider set-ports | kuma_provider_set_ports | PUT /v1/providers/{providerId}/ports | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-22 | [PARITY] | service.update, provider.update, provider.set_ports | kuma service update; kuma provider update; kuma provider set-ports | kuma_service_update; kuma_provider_update; kuma_provider_set_ports | PATCH /v1/services/{serviceId}; PATCH /v1/providers/{providerId}; PUT /v1/providers/{providerId}/ports | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-23 | [PARITY] | service.list, service.start_all, service.stop_all | kuma service list; kuma service start-all; kuma service stop-all | kuma_service_list; kuma_service_start_all; kuma_service_stop_all | GET /v1/services; POST /v1/services/start-all; POST /v1/services/stop-all | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-24 | [PARITY] | service.create, service.update, service.delete, service.duplicate, service.set_starred, service.set_disabled, service.set_groups, service.toggle_group, service.switch_provider, provider.add, provider.update, provider.delete, provider.set_ports | kuma service create; kuma service update; kuma service delete; kuma service duplicate; kuma service set-starred; kuma service set-disabled; kuma service set-groups; kuma service toggle-group; kuma service switch-provider; kuma provider add; kuma provider update; kuma provider delete; kuma provider set-ports | kuma_service_create; kuma_service_update; kuma_service_delete; kuma_service_duplicate; kuma_service_set_starred; kuma_service_set_disabled; kuma_service_set_groups; kuma_service_toggle_group; kuma_service_switch_provider; kuma_provider_add; kuma_provider_update; kuma_provider_delete; kuma_provider_set_ports | POST /v1/workspaces/{workspaceId}/services; PATCH /v1/services/{serviceId}; DELETE /v1/services/{serviceId}; POST /v1/services/{serviceId}/duplicate; PUT /v1/services/{serviceId}/starred; PUT /v1/services/{serviceId}/disabled; PUT /v1/services/{serviceId}/groups; POST /v1/services/{serviceId}/groups/{groupId}/toggle; POST /v1/services/{serviceId}/switch-provider; POST /v1/services/{serviceId}/providers; PATCH /v1/providers/{providerId}; DELETE /v1/providers/{providerId}; PUT /v1/providers/{providerId}/ports | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-25 | [V2-ADD] | service.update, service.set_starred, service.set_disabled, service.switch_provider, provider.update, service.list | kuma service update; kuma service set-starred; kuma service set-disabled; kuma service switch-provider; kuma provider update; kuma service list | kuma_service_update; kuma_service_set_starred; kuma_service_set_disabled; kuma_service_switch_provider; kuma_provider_update; kuma_service_list | PATCH /v1/services/{serviceId}; PUT /v1/services/{serviceId}/starred; PUT /v1/services/{serviceId}/disabled; POST /v1/services/{serviceId}/switch-provider; PATCH /v1/providers/{providerId}; GET /v1/services | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-26 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-27 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-28 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-29 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-30 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-31 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-32 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-33 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-SVC-34 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-SVC-01…DT-SVC-65 (52 in SVC) |
| FEAT-K8S-01 | [PARITY] | kubeconfig.list, kubeconfig.get | kuma kubeconfig list; kuma kubeconfig get | kuma_kubeconfig_list; kuma_kubeconfig_get | GET /v1/kubeconfigs; GET /v1/kubeconfigs/{kubeconfigId} | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-02 | [PARITY] | kubeconfig.list | kuma kubeconfig list | kuma_kubeconfig_list | GET /v1/kubeconfigs | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-03 | [PARITY] | kubeconfig.get | kuma kubeconfig get | kuma_kubeconfig_get | GET /v1/kubeconfigs/{kubeconfigId} | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-04 | [PARITY] | kubeconfig.create, kubeconfig.update | kuma kubeconfig create; kuma kubeconfig update | kuma_kubeconfig_create; kuma_kubeconfig_update | POST /v1/kubeconfigs; PATCH /v1/kubeconfigs/{kubeconfigId} | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-05 | [PARITY] | kubeconfig.create, kubeconfig.update | kuma kubeconfig create; kuma kubeconfig update | kuma_kubeconfig_create; kuma_kubeconfig_update | POST /v1/kubeconfigs; PATCH /v1/kubeconfigs/{kubeconfigId} | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-06 | [PARITY] | kubeconfig.delete | kuma kubeconfig delete | kuma_kubeconfig_delete | DELETE /v1/kubeconfigs/{kubeconfigId} | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-07 | [PARITY] | kubeconfig.contexts | kuma kubeconfig contexts | kuma_kubeconfig_contexts | GET /v1/kubeconfigs/{kubeconfigId}/contexts | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-08 | [PARITY] | kubeconfig.contexts | kuma kubeconfig contexts | kuma_kubeconfig_contexts | GET /v1/kubeconfigs/{kubeconfigId}/contexts | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-09 | [PARITY] | kubeconfig.contexts | kuma kubeconfig contexts | kuma_kubeconfig_contexts | GET /v1/kubeconfigs/{kubeconfigId}/contexts | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-10 | [PARITY] | kubeconfig.test_connection, service.preflight | kuma kubeconfig test-connection; kuma service preflight | kuma_kubeconfig_test_connection; kuma_service_preflight | POST /v1/kubeconfigs/{kubeconfigId}/test-connection; POST /v1/services/{serviceId}/preflight | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-11 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-12 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-13 | [PARITY] | k8s.resolve_target | kuma k8s resolve-target | kuma_k8s_resolve_target | POST /v1/k8s/resolve-target | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-14 | [PARITY] | k8s.resolve_target, service.start | kuma k8s resolve-target; kuma service start | kuma_k8s_resolve_target; kuma_service_start | POST /v1/k8s/resolve-target; POST /v1/services/{serviceId}/start | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-15 | [PARITY] | — | — | — | — | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-16 | [PARITY] | — | — | — | — | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-17 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-18 | [PARITY] | service.start | kuma service start | kuma_service_start | POST /v1/services/{serviceId}/start | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-19 | [PARITY] | service.status | kuma service status | kuma_service_status | GET /v1/services/{serviceId}/status | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-20 | [PARITY] | service.preflight | kuma service preflight | kuma_service_preflight | POST /v1/services/{serviceId}/preflight | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-21 | [V2-ADD] | k8s.namespaces | kuma k8s namespaces | kuma_k8s_namespaces | GET /v1/k8s/namespaces | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-22 | [V2-ADD] | k8s.resources | kuma k8s resources | kuma_k8s_resources | GET /v1/k8s/resources | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-23 | [PARITY] | logs.follow, logs.workload_tail | kuma logs follow; kuma logs workload-tail | kuma_logs_follow; kuma_logs_workload_tail | —; GET /v1/services/{serviceId}/logs/workload | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-24 | [CLIENT] | — | — | — | — | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-25 | [CLIENT] | — | — | — | — | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-K8S-26 | [CLIENT] | — | — | — | — | [07-kubernetes](07-kubernetes.md) | — |
| FEAT-WS-01 | [PARITY] | workspace.list | kuma workspace list | kuma_workspace_list | GET /v1/workspaces | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-02 | [PARITY] | workspace.get | kuma workspace get | kuma_workspace_get | GET /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-03 | [PARITY] | workspace.create | kuma workspace create | kuma_workspace_create | POST /v1/workspaces | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-04 | [PARITY] | workspace.update | kuma workspace update | kuma_workspace_update | PATCH /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-05 | [PARITY] | workspace.delete | kuma workspace delete | kuma_workspace_delete | DELETE /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-06 | [PARITY] | workspace.delete | kuma workspace delete | kuma_workspace_delete | DELETE /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-07 | [PARITY] | workspace.reorder | kuma workspace reorder | kuma_workspace_reorder | PUT /v1/workspaces/order | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-08 | [PARITY] | workspace.list | kuma workspace list | kuma_workspace_list | GET /v1/workspaces | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-09 | [PARITY] | workspace.create, workspace.update, workspace.set_image | kuma workspace create; kuma workspace update; kuma workspace set-image | kuma_workspace_create; kuma_workspace_update; kuma_workspace_set_image | POST /v1/workspaces; PATCH /v1/workspaces/{workspaceId}; PUT /v1/workspaces/{workspaceId}/image | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-10 | [PARITY] | workspace.get_image | kuma workspace get-image | kuma_workspace_get_image | GET /v1/workspaces/{workspaceId}/image | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-11 | [PARITY] | workspace.clear_image, workspace.update | kuma workspace clear-image; kuma workspace update | kuma_workspace_clear_image; kuma_workspace_update | DELETE /v1/workspaces/{workspaceId}/image; PATCH /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-12 | [PARITY] | workspace.get_image, workspace.delete | kuma workspace get-image; kuma workspace delete | kuma_workspace_get_image; kuma_workspace_delete | GET /v1/workspaces/{workspaceId}/image; DELETE /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-13 | [PARITY] | workspace.delete, workspace.set_image, workspace.clear_image | kuma workspace delete; kuma workspace set-image; kuma workspace clear-image | kuma_workspace_delete; kuma_workspace_set_image; kuma_workspace_clear_image | DELETE /v1/workspaces/{workspaceId}; PUT /v1/workspaces/{workspaceId}/image; DELETE /v1/workspaces/{workspaceId}/image | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-14 | [PARITY] | data.import, data.export | kuma data import; kuma data export | kuma_data_import; kuma_data_export | POST /v1/data/import; POST /v1/data/export | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-15 | [PARITY] | workspace.create, workspace.update | kuma workspace create; kuma workspace update | kuma_workspace_create; kuma_workspace_update | POST /v1/workspaces; PATCH /v1/workspaces/{workspaceId} | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-16 | [V2-ADD] | workspace.update, workspace.set_image, workspace.clear_image | kuma workspace update; kuma workspace set-image; kuma workspace clear-image | kuma_workspace_update; kuma_workspace_set_image; kuma_workspace_clear_image | PATCH /v1/workspaces/{workspaceId}; PUT /v1/workspaces/{workspaceId}/image; DELETE /v1/workspaces/{workspaceId}/image | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-17 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-18 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-19 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-20 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |
| FEAT-WS-21 | [CLIENT] | — | — | — | — | [04-workspaces-groups-services](04-workspaces-groups-services.md) | DT-WS-01…DT-WS-24 (24 in WS) |

## 3. Deviation register (DEV-NN)

**Count:** 68 unique deviation ids.

| ID | One-line description |
|----|----------------------|
| DEV-01 | `importIntoWorkspace` remaps `activeProviderID` through `providerIDMap` after the map is populated (1.x always imported `nil`). §3.9 step 3. |
| DEV-02 | Legacy tool-path keys (`kuma.custom_*_path`) are honored at runtime by every resolver (1.x honored them only in UI and scan) |
| DEV-03 | `workspace.delete` stops the workspace's running services first (1.x orphaned them). §3.2.5. |
| DEV-04 | All import paths use `parseAnyBackup` (Settings import accepts single-service JSON). §3.3. |
| DEV-05 | Selective import group filter: nil `workspaceID` groups no longer always pass; `reassignIDs` path respects selected service ids only. §3.8, DEV-105. |
| DEV-06 | Health check HTTP probe gets explicit request timeout (1.x URLSession default). |
| DEV-07 | Activity buffer retained until `logs.clear` or `begin_run`; not cleared on client panel close (§3.3.2). |
| DEV-08 | Full process-tree signal escalation on stop (not 1.x `terminateAll` SIGTERM-only ~200 ms) — invoked via `daemon.shutdown {stopServices:true}` |
| DEV-09 | Secrets use `master.key` (AES-256-GCM), not Keychain (pre-assigned). |
| DEV-10 | Persist `runtime_process`; adopt on daemon start; detach leaves children running |
| DEV-11 | All 1.x UserDefaults keys live in `daemon-state.sqlite` `settings` (same names); e.g. `kuma.selectedWorkspaceId.storage`, quit snapshot keys ([03](03-settings-and-environment.md), [04 §3.12](04-workspaces-groups-services.md)). |
| DEV-12 | Spool path and permissions; selective purge at daemon start (§3.2). |
| DEV-13 | Emit `notify` `healthCheckFailed` on health poll transition (§3.12 `notify`). |
| DEV-14 | `service.delete` stops a running service first (1.x only disabled the button). §3.5.5. |
| DEV-20 | Rows whose primary key/foreign key text is not a valid UUID are skipped, instead of 1.x generating a random UUID on every read. |
| DEV-21 | Unparsable `DATETIME` text decodes to the Unix epoch with a warning, and non-integer required integers return `KUMA_DAT_ROW_DECODE`, instead of 1.x trapping. |
| DEV-22 | `updatedAt` on every successful update is `max(now, previous + 1 ms)` so `expectedUpdatedAt` is a reliable token (1.x used plain `Date()`). |
| DEV-23 | Deterministic tie-break ordering (`rowid ASC` after the 1.x ORDER BY keys; ports by `rowid`; `groupIDs` sorted on the wire) where 1.x left order unspecified. |
| DEV-35 | Askpass script emits the password verbatim (1.x corrupted passwords containing `\ " $ `` ` ``), lives in `<runtime dir>/askpass/<serviceID>/` (dir `0700`), and is removed on stop, child exit, failed start, shutdown, and  |
| DEV-36 | Secret-file hygiene: (a) files/dirs created with final mode atomically (1.x chmod after write); (b) existing data dir, `kuma.sqlite`, `master.key`, `kubeconfigs/`, runtime dir are tightened to `0700`/`0600` and spool fil |
| DEV-36a | Secret files created with final mode atomically (not chmod-after-write). |
| DEV-36b | Tighten data dir, DB, master.key, kubeconfigs/, runtime permissions. |
| DEV-36c | master.key creation mutex-serialized; corrupt key backed up before replace. |
| DEV-36d | Delete materialized kubeconfig files on update/delete and orphan sweep. |
| DEV-37 | Credential read semantics: (a) ciphertext-shaped values that fail to decrypt are treated as unset instead of being used as the password/token (1.x fed the ciphertext string to ssh/ngrok); (b) `kubeconfig.get` reveal neve |
| DEV-38 | Workload (user process) output served to clients goes through the `workload` redaction profile (R4, R5, R8); 1.x showed raw output. On-disk spool remains raw. |
| DEV-40 | A custom tool path or default shell that is a directory is rejected (1.x `resolvedPath`/`validatedShellPath` accepted a directory because `isExecutableFile` is true for directories) |
| DEV-41 | PATH shell sniff has stdin `/dev/null` and a 10 s kill timeout, falling back to the daemon's `PATH` (1.x blocked indefinitely) |
| DEV-42 | Tool-path settings are trimmed on write and read (1.x stored raw text, validated trimmed, resolved untrimmed) |
| DEV-43 | When `$SHELL` is unset or empty the passwd shell is used before `/bin/zsh` (a LaunchAgent has no `SHELL`) |
| DEV-44 | Writing or deleting a tool-path setting also deletes its legacy fallback key (1.x: clearing a path with a legacy key present resurrected the legacy value) |
| DEV-50 | Workspace avatar writes always produce a managed 512 px PNG copy and are failure-safe: create-with-image no longer stores the raw absolute path (1.x `URL(string:)` quirk), replacement decodes before touching the old file |
| DEV-51 | `service.set_disabled(true)` stops a running service (1.x only reset the UI state to idle and left the process unsupervised). §3.5.8. |
| DEV-52 | Name rules are enforced by the daemon on every write path instead of only in forms: `workspace.update` trims and rejects blank (`KUMA_WS_NAME_EMPTY`); `service.create` trims and rejects blank (`KUMA_SVC_NAME_EMPTY`); `gr |
| DEV-53 | `service.switch_provider` validates that the provider belongs to the service, treats a same-provider switch as a no-op (the inspector guard; the deck had none), and uses one restart path (the 06 user-initiated start) who |
| DEV-54 | Group membership is validated to connect a service and a group of the same workspace (1.x relied on UI and FKs). §3.4.6. |
| DEV-55 | The daemon deletes only avatar files located inside `Workspaces/Images`; a legacy absolute `imagePath` (which in 1.x is the user's original photo) is never deleted, preventing the 1.x `deleteWorkspace`/replace data loss. |
| DEV-56 | Port rows are range-checked (`1..65535`, integers) at write time in `service.create` and `provider.set_ports`; 1.x persisted any positive value from the inspector and caught out-of-range values only at start validation.  |
| DEV-57 | Operations naming a missing workspace/group/service/provider return `KUMA_*_NOT_FOUND`; 1.x silently ignored deletes of unknown ids and `toggleStarred` returned `false`. List queries by an unknown workspace still return  |
| DEV-58 | `provider.delete` refuses to delete the only provider (1.x enforced it only by hiding the button, `providers.count > 1`). §3.6.4. |
| DEV-60 | The validator/preflight resolves compose YAML without writing the ephemeral `docker-compose.kuma.yml` (1.x `ComposeStackResolver.resolve` wrote it as a side effect of validation). |
| DEV-61 | A dangling kubeconfig id is reported as `k8s.kubeconfig` at preflight and rejected at create/update (the 1.x inspector silently re-selected another config in its picker). |
| DEV-62 | Port rows are validated server-side (complete, 1–65535, only for kubernetes/ssh) on `service.create` and `provider.set_ports`; 1.x validated only in the UI and persisted/dropped rows silently. |
| DEV-63 | UI-only guards become server-enforced: the running lock for provider add/update/delete/set_ports and the "last provider cannot be deleted" rule. |
| DEV-64 | `provider.update`/`provider.add` reject fields that do not apply to the resulting category (unless equal to stored) and reject setting both sources of the compose/script/ssh-credential pairs in one call (the UI set field |
| DEV-65 | Kubernetes context sanitization runs only when the patch touches `kubeConfigID` or `kubeContext`, and only when the kubeconfig yields at least one context (1.x re-sanitized on every commit and cleared the context when no |
| DEV-70 | Spool tail uses lossy UTF-8; empty tail → null `lastFailure`; active 8 MiB→4 MiB spool maintenance |
| DEV-71 | Disabled services rejected at `service.start` / reconnect / auto-resume; disabling stops running workload |
| DEV-72 | Snapshot `activeServiceIDsBeforeQuit` on daemon detach; auto-resume at boot for all saved ids (not first workspace only) |
| DEV-73 | `stop_all_services` / `detach_all` replace `terminateAll` + `stopAll` (§3.10.9) |
| DEV-74 | Lane ordering; publication 500 ms max; no post-start grace poll; stop publish after compose down; stop uses stored provider category |
| DEV-75 | Ephemeral compose YAML under `<runtime>/compose/<SERVICEID>/` only |
| DEV-76 | Health probes concurrent; monitor `ps` only when due; lowest pid match excluding daemon/ps child |
| DEV-77 | Keep `… on this Mac.` wording on non-macOS hosts |
| DEV-78 | Process group before exec; dynamic pid buffer; stdin null; spawn error shape; pid reuse guard; k8s adoption alive check; SSH destination validation; uid check before signalling foreign pids |
| DEV-79 | Runner environment includes resolved PATH (06). |
| DEV-80 | Daemon SHOULD call `clearCache` on kubeconfig writes and Default path setting changes (1.x never clears; cache grows until process exit). |
| DEV-91 | Spool tail followers re-seek when file shrinks (§3.2.4). |
| DEV-101 | Factory reset clears `daemon-state.sqlite` settings KV instead of macOS UserDefaults (`DEV-11`). §3.13 step 2. |
| DEV-102 | Factory reset stops services with full escalation (06) instead of SIGTERM-only `terminateAll`. §3.13 step 1. |
| DEV-105 | `importSelective` group filter restricted to selected workspaces; `importData(reassignIDs)` does not import unselected services when the client passes a subset (deck/workspace UI). §3.6, §3.8. |
| DEV-110 | Daemon single-instance uses lock file + `daemon.ping`, not AppKit bundle id |
| DEV-111 | Closing V2 client does not stop services; 1.x `applicationWillTerminate` always `stopAll` |
| DEV-112 | Normal daemon exit uses `detach_all` (services survive); 1.x quit kills subprocesses |
| DEV-113 | Scaffold socket under data dir without `run/`; CLI MUST follow resolved path from `daemon.status.runtimeDir` when debugging (14) |
| DEV-114 | Health-check macOS notification emitted as `notify` (DEV-13) though 1.x Swift path was unused |
| DEV-115 | Auto-resume stays client-driven RPC loop; daemon does not start services at S11 |
| DEV-120 | REST adapter strips `revealSecrets` query parameter before RPC dispatch and returns 403 if `true`. |

## 4. Addition register (ADD-NN)

**Count:** 42 unique addition ids.

| ID | One-line description |
|----|----------------------|
| ADD-01 | service.preflight RPC. |
| ADD-02 | ports.check RPC. |
| ADD-03 | Persisted adoption table + runtime.adopt_report. |
| ADD-04 | `k8s.namespaces` / `k8s.resources` RPCs for headless clients (§3.18–3.19). |
| ADD-05 | `logs.workload_tail`, `logs.follow` (§3.9–3.10). |
| ADD-06 | daemon.status / daemon.shutdown RPCs. |
| ADD-07 | Event `seq`, replay store, `sinceSeq` (§3.11). |
| ADD-08 | REST bearer-token auth. |
| ADD-09 | Legacy UserDefaults import at first daemon start. |
| ADD-20 | Backup copy of `kuma.sqlite` before applying any pending migration, and a one-time `kuma.sqlite.pre-daemon.bak` before the first daemon write to a 1.x-created DB. |
| ADD-21 | Refuse to open (no writes) a DB whose `grdb_migrations` has identifiers unknown to the daemon (1.x Release ignored them, 1.x Debug erased the DB). |
| ADD-22 | `busy_timeout = 5000` ms and an advisory warning when a 1.x app instance (`com.kuma.Kuma`) is running. |
| ADD-30 | Unix socket hardening: permissions, same-uid peer, no core dumps. |
| ADD-31 | REST loopback listener, api-token file, rotation, Host allow-list. |
| ADD-32 | Wire secret masking contract (sshPasswordSet, revealSecrets rules). |
| ADD-33 | Central redaction profiles; redacted argv in runtime_process. |
| ADD-34 | JSON Lines audit.log for mutating RPCs without secrets. |
| ADD-40 | settings.set strict flag (onboarding validate-then-persist). |
| ADD-41 | KUMA_LEGACY_DEFAULTS_PLIST override for legacy import path. |
| ADD-42 | env.validate_binary kind=kubeconfig for path-only kubeconfig checks. |
| ADD-59 | Derived convenience fields not stored in 1.x models: `Workspace.hasImage`; `ServiceListItem.subtitle`/`displaySubtitle`/`liveTarget`/`runtime`/`providerOptions[].displayLabel`; `service.list` `totalCount`; `Provider.disp |
| ADD-60 | `sshAuthType` param (`key`/`password`) and patch-driven inference on `service.create`, `provider.add`, `provider.update` (1.x kept it as inspector state). |
| ADD-100 | `data.import_preview` returns structured preview rows (ADD in spec 09 range). §3.11. |
| ADD-101 | Factory reset purges runtime process registry, activity logs, and emits `data.reset`. §3.13. |
| ADD-102 | `data.export` returns `suggestedFileName` using §3.1 patterns. §3.12. |
| ADD-110 | `kuma daemon install` / `uninstall` LaunchAgent `com.kuma.daemon` |
| ADD-111 | Optional `kuma daemon install --keep-alive` sets LaunchAgent `KeepAlive` true |
| ADD-112 | LaunchAgent stdout/stderr log files under runtime dir |
| ADD-113 | `daemon.status` exposes `instanceId`, `adoptReport`, `legacyAppRunning` |
| ADD-114 | Wire `notify.kind` enum for client notification mapping |
| ADD-115 | `meta.instanceId` regenerated on each daemon process start (event seq continuity per 08) |
| ADD-116 | CLI `kuma daemon status` prints JSON from `daemon.status` (see 11) |
| ADD-117 | Env `KUMA_SHUTDOWN_STOP_SERVICES=1` makes SIGTERM stop services (tests only) |
| ADD-118 | Document dual login items: app `SMAppService` vs daemon LaunchAgent |
| ADD-119 | Optional signed standalone `kuma` release artifact in CI |
| ADD-120 | REST default port `9364`, enable via `KUMA_REST=1` / `--rest`; optional future `KUMA_REST_TLS` + mTLS profile (§3.2.2). |
| ADD-121 | Optional WebSocket parallel to SSE for `events.subscribe` and `logs.follow`; SSE remains the required transport. |
| ADD-122 | `data factory-reset` requires `--yes` (CLI-only guard; RPC unchanged) |
| ADD-123 | MCP `kuma_data_factory_reset` requires JSON param `confirm: true` (parallel to CLI `--yes`) |
| ADD-124 | MCP v1 does not stream events as MCP notifications; polling/resources only |
| ADD-125 | `KUMA_SOCKET` explicit socket path override for CLI/MCP clients ([11](11-cli.md)) |
| ADD-126 | CLI `--json` error envelope includes structured `error.data` when daemon provides it ([11](11-cli.md)) |

## 5. Invariant index (INV-D-*)

**Count:** 139 invariants.

| INV | Spec | Statement (abbrev.) |
|-----|------|---------------------|
| INV-D-API-01 | [13-rest-api](13-rest-api.md) | Every RPC method in [00 §5](00-overview-and-conventions.md) has exactly one primary REST mapping row in §10 unless socket-only (`daemon.rotate_api_token`) or streaming-only exception. |
| INV-D-API-02 | [13-rest-api](13-rest-api.md) | Successful JSON responses use the same keys and values as the RPC result for that method ([10](10-rpc-protocol.md)). |
| INV-D-API-03 | [13-rest-api](13-rest-api.md) | REST never returns plaintext secrets ([02](02-security-and-secrets.md) GR-04, §3.11). |
| INV-D-API-04 | [13-rest-api](13-rest-api.md) | All REST handlers run with transport kind `rest` in the audit log ([02 §3.10](02-security-and-secrets.md)). |
| INV-D-API-05 | [13-rest-api](13-rest-api.md) | SSE replay ordering matches `events.subscribe` over the socket ([08](08-logs-and-events.md)). |
| INV-D-CLI-01 | [11-cli](11-cli.md) | Every RPC in [00 §5](00-overview-and-conventions.md) has exactly one documented CLI leaf in Appendix A, except §3.8 streaming pairing and §3.8.1 socket-only notes. |
| INV-D-CLI-02 | [11-cli](11-cli.md) | CLI MUST NOT emit secret fields on stdout/stderr unless `--reveal-secrets` and same-uid Unix peer ([02](02-security-and-secrets.md)). |
| INV-D-CLI-03 | [11-cli](11-cli.md) | `--json` stdout MUST contain valid JSON only (one value per invocation for non-streaming commands). |
| INV-D-CLI-04 | [11-cli](11-cli.md) | `kuma daemon run` MUST NOT dial the client socket to serve its own RPC. |
| INV-D-CLI-05 | [11-cli](11-cli.md) | Wire param keys sent by the CLI MUST use camelCase identical to Swift Codable ([00 brief](00-overview-and-conventions.md)). |
| INV-D-DAT-01 | [01-data-model](01-data-model.md) | After the daemon opens/creates `kuma.sqlite`, `grdb_migrations` contains exactly the eight identifiers `v1_production_schema` … `v8_provider_auto_reco |
| INV-D-DAT-02 | [01-data-model](01-data-model.md) | The user objects of `sqlite_master` (type, name, tbl_name, sql) and their creation order equal the listing of 3.5.1 byte for byte; the daemon never al |
| INV-D-DAT-03 | [01-data-model](01-data-model.md) | Every connection to `kuma.sqlite` has `PRAGMA foreign_keys = ON` (except inside the per-migration disable/check/enable sequence) and the database is i |
| INV-D-DAT-04 | [01-data-model](01-data-model.md) | Every UUID written to any column is a 36-character uppercase hyphenated string; every UUID emitted on the wire is uppercase. |
| INV-D-DAT-05 | [01-data-model](01-data-model.md) | Every date written to `kuma.sqlite` has the form `YYYY-MM-DD HH:MM:SS.mmm` in UTC (one exception exists in existing data: v3 `datetime('now')` rows, w |
| INV-D-DAT-06 | [01-data-model](01-data-model.md) | Booleans are written as integers `0`/`1`; `provider.autoReconnect` is never NULL. |
| INV-D-DAT-07 | [01-data-model](01-data-model.md) | At the end of every operation that changes the workspace set, at least one workspace row exists. |
| INV-D-DAT-08 | [01-data-model](01-data-model.md) | The daemon never reads or writes `service.groupID`; membership is solely `service_group_membership`. |
| INV-D-DAT-09 | [01-data-model](01-data-model.md) | `portMapping.serviceID` and, for rows the daemon creates, `portMapping.providerID` are non-NULL; mapping visibility follows 3.11.2 exactly. |
| INV-D-DAT-10 | [01-data-model](01-data-model.md) | Deleting a workspace, service, group or provider produces exactly the cascade effects of 3.11.5 (groups never delete services; deleting a provider del |
| INV-D-DAT-11 | [01-data-model](01-data-model.md) | `sshPassword`, `ngrokAuthToken` and `kube_config.configContent` are written only as vault ciphertext or NULL (or `""` for the empty/file-backed kubeco |
| INV-D-DAT-12 | [01-data-model](01-data-model.md) | `kuma.sqlite` is never written when `grdb_migrations` holds an unknown identifier. |
| INV-D-DAT-13 | [01-data-model](01-data-model.md) | Successful updates strictly increase the entity's `updatedAt`; a stale `expectedUpdatedAt` never results in a write. |
| INV-D-DAT-14 | [01-data-model](01-data-model.md) | `daemon-state.sqlite` is a separate file; none of its tables exist in `kuma.sqlite`. |
| INV-D-DAT-15 | [01-data-model](01-data-model.md) | After a reorder call, the list's `sortOrder` values are exactly `0..n-1` in the requested order. |
| INV-D-DAT-16 | [01-data-model](01-data-model.md) | The virtual Default kubeconfig id never has a row written to `kube_config`. |
| INV-D-DAT-17 | [01-data-model](01-data-model.md) | `wipeAndResetDatabase` leaves `grdb_migrations` intact and exactly one workspace. |
| INV-D-DPT-01 | [09-dataport](09-dataport.md) | Every import/export mutation uses the in-memory `KumaBackup` representation (single-service wrapped before import). |
| INV-D-DPT-02 | [09-dataport](09-dataport.md) | `importAll` persists workspaces, groups, services, providers, memberships, ports, and kubeconfigs in one SQLite write transaction. |
| INV-D-DPT-03 | [09-dataport](09-dataport.md) | Failed import transactions leave the database unchanged (TC-C08). |
| INV-D-DPT-04 | [09-dataport](09-dataport.md) | Export with scope `.workspace(W)` never includes services whose `workspaceID != W`. |
| INV-D-DPT-05 | [09-dataport](09-dataport.md) | Export with scope `.service(S)` never includes other services' rows. |
| INV-D-DPT-06 | [09-dataport](09-dataport.md) | Default kubeconfig id is never inserted from backup. |
| INV-D-DPT-07 | [09-dataport](09-dataport.md) | Imported port rows always have `protocolType = TCP` in SQLite. |
| INV-D-DPT-08 | [09-dataport](09-dataport.md) | After factory reset, exactly one workspace exists and `master.key` / `kubeconfigs/` remain on disk. |
| INV-D-DPT-09 | [09-dataport](09-dataport.md) | Preview and RPC list responses never contain cleartext or ciphertext secrets. |
| INV-D-DPT-10 | [09-dataport](09-dataport.md) | `version` in emitted exports equals `BACKUP_CURRENT_VERSION`. |
| INV-D-EXE-01 | [06-execution-engine](06-execution-engine.md) | At most one `runtime_process` row per `serviceID`. |
| INV-D-EXE-02 | [06-execution-engine](06-execution-engine.md) | When state is `crashed`, `exitCode` is non-null and never `0`. |
| INV-D-EXE-03 | [06-execution-engine](06-execution-engine.md) | When state is not `reconnecting`, `reconnectAttempt` and `reconnectMax` are null on the wire. |
| INV-D-EXE-04 | [06-execution-engine](06-execution-engine.md) | `lastFailure` is non-null only while state is `crashed` (except transient internal start failure before T6 completes). |
| INV-D-EXE-05 | [06-execution-engine](06-execution-engine.md) | G1: `running` retains last known `pid` on updates that omit pid. |
| INV-D-EXE-06 | [06-execution-engine](06-execution-engine.md) | G2: stale `runId` updates are dropped. |
| INV-D-EXE-07 | [06-execution-engine](06-execution-engine.md) | G4: no `stopping` publish from `stopped`/`crashed`/absent record. |
| INV-D-EXE-08 | [06-execution-engine](06-execution-engine.md) | G5: no `running` publish while `stopping`. |
| INV-D-EXE-09 | [06-execution-engine](06-execution-engine.md) | G7: identical public tuples emit at most one consecutive `service.state_changed`. |
| INV-D-EXE-10 | [06-execution-engine](06-execution-engine.md) | G8–G9: background polls never clobber in-flight `starting`/`stopping`. |
| INV-D-EXE-11 | [06-execution-engine](06-execution-engine.md) | Stop pipeline always ends with `stopped` and deleted `runtime_process` row unless `detach_all`. |
| INV-D-EXE-12 | [06-execution-engine](06-execution-engine.md) | Auto-reconnect attempts ≤ 3 per unexpected exit session. |
| INV-D-EXE-13 | [06-execution-engine](06-execution-engine.md) | `ports.check` never sends signals. |
| INV-D-EXE-14 | [06-execution-engine](06-execution-engine.md) | Persisted `argvJSON` / `lastFailure` never contain raw secrets ([02](02-security-and-secrets.md)). |
| INV-D-EXE-15 | [06-execution-engine](06-execution-engine.md) | `service.stop` is infallible on the wire (always returns stopped). |
| INV-D-GRP-01 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | A group's `workspaceID` never changes; every membership connects a service and a group of the same workspace. |
| INV-D-GRP-02 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | Deleting a group never deletes or modifies any service row; it removes exactly that group's membership rows. |
| INV-D-GRP-03 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `group.create` assigns `max(sortOrder in the workspace) + 1` (first group = 1); `group.reorder` leaves exactly `0..n-1` and bumps every group's `updat |
| INV-D-GRP-04 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `group.name` written by the daemon is trimmed; a blank rename becomes `Untitled Group`. |
| INV-D-LIF-01 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | At most one live daemon per user holds `kuma-daemon.lock` and serves `kuma-daemon.sock`. |
| INV-D-LIF-02 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | After `detach_all` shutdown, every previously running workload process still exists in the process table unless the user sent `stopServices: true`. |
| INV-D-LIF-03 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | `daemon.ping` never mutates persisted state. |
| INV-D-LIF-04 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | `notify` payloads never contain secrets after redaction (GR-04). |
| INV-D-LIF-05 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | Spool purge at start never deletes `<spool>/<serviceID>.out` when a `runtime_process` row exists for that `serviceID`. |
| INV-D-LIF-06 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | Socket and runtime dir are user-only (`0700` dir, `0600` socket). |
| INV-D-LIF-07 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | `protocolVersion` in ping/status matches the compiled `PROTOCOL_VERSION` constant. |
| INV-D-LIF-08 | [14-lifecycle-and-platform](14-lifecycle-and-platform.md) | LaunchAgent `ProgramArguments[0]` is an absolute path to the `kuma` binary that was used for `install`. |
| INV-D-LOG-01 | [08-logs-and-events](08-logs-and-events.md) | For each service, activity line `revision` strictly increases on any line-list mutation. |
| INV-D-LOG-02 | [08-logs-and-events](08-logs-and-events.md) | While not capturing, `emit` / `emitBatch` / `emitRawLine` append nothing (TC-L15, TC-L20). |
| INV-D-LOG-03 | [08-logs-and-events](08-logs-and-events.md) | After `end_capture`, previously stored lines remain until `clear`, `begin_run`, delete, or LRU eviction (TC-L13). |
| INV-D-LOG-04 | [08-logs-and-events](08-logs-and-events.md) | Buffer line count per service never exceeds `ACTIVITY_MAX_LINES`. |
| INV-D-LOG-05 | [08-logs-and-events](08-logs-and-events.md) | At most `ACTIVITY_MAX_SERVICES` non-empty buffers without eviction (TC-L21). |
| INV-D-LOG-06 | [08-logs-and-events](08-logs-and-events.md) | Every activity `text` field is ANSI-sanitized (§3.5) and `strict`-redacted before storage or `service.log_line`. |
| INV-D-LOG-07 | [08-logs-and-events](08-logs-and-events.md) | Spool files for services with a `runtime_process` row survive daemon restart (DEV-12). |
| INV-D-LOG-08 | [08-logs-and-events](08-logs-and-events.md) | Event `seq` is strictly increasing and equals persisted `meta.eventSeq` after each emit. |
| INV-D-LOG-09 | [08-logs-and-events](08-logs-and-events.md) | No secret material from [02](02-security-and-secrets.md) appears in activity lines, `service.log_line`, or `notify` bodies (GR-04). |
| INV-D-LOG-10 | [08-logs-and-events](08-logs-and-events.md) | `service.deleted` clears the activity buffer for that id. |
| INV-D-MCP-01 | [12-mcp](12-mcp.md) | Tool count = RPC count in [00 §5](00-overview-and-conventions.md) (73). |
| INV-D-MCP-02 | [12-mcp](12-mcp.md) | Every tool name is derivable by the §3.3 rule from its RPC method. |
| INV-D-MCP-03 | [12-mcp](12-mcp.md) | MCP MUST NOT expose secrets beyond redacted RPC responses. |
| INV-D-MCP-04 | [12-mcp](12-mcp.md) | stdout is exclusively MCP protocol bytes; logs go to stderr. |
| INV-D-MCP-05 | [12-mcp](12-mcp.md) | Appendix A row count equals Appendix A in [11](11-cli.md). |
| INV-D-PRV-01 | [05-providers-and-validation](05-providers-and-validation.md) | `ServiceConfigurationValidator.issues` is deterministic for a fixed `(service, provider, context, filesystem)` and has no side effect (no file or data |
| INV-D-PRV-02 | [05-providers-and-validation](05-providers-and-validation.md) | A disabled service yields an empty issue list from the validator and `ok: true, serviceDisabled: true` from `service.preflight`. |
| INV-D-PRV-03 | [05-providers-and-validation](05-providers-and-validation.md) | `service.start`, `service.start_all` and auto-resume never run the validator; their failure texts are the set B runner messages. |
| INV-D-PRV-04 | [05-providers-and-validation](05-providers-and-validation.md) | Within one preflight result issue codes are unique, and the order is: provider, ports, category rules, `k8s.target_resolve`. |
| INV-D-PRV-05 | [05-providers-and-validation](05-providers-and-validation.md) | Every validator rule emits severity `blocking`; the daemon never invents a `warning`. |
| INV-D-PRV-06 | [05-providers-and-validation](05-providers-and-validation.md) | The daemon never nulls or rewrites columns of other categories on `provider.update`, type change or `provider.add` (retained and ignored). |
| INV-D-PRV-07 | [05-providers-and-validation](05-providers-and-validation.md) | After any successful write that sets a non-blank compose path, `yamlConfig` is NULL; after any successful write that sets a non-blank `yamlConfig`, `c |
| INV-D-PRV-08 | [05-providers-and-validation](05-providers-and-validation.md) | After any successful write of an ssh provider, at most one of `sshPassword` and `sshKeyPath` is non-NULL. |
| INV-D-PRV-09 | [05-providers-and-validation](05-providers-and-validation.md) | After `provider.add`/`provider.update` of a kubernetes provider, `kubeTargetType` is non-NULL, non-empty and `usePattern` is non-NULL. |
| INV-D-PRV-10 | [05-providers-and-validation](05-providers-and-validation.md) | `autoReconnect` is written as a non-NULL boolean; `isAutoReconnectEnabled` is false for categories other than kubernetes, ssh, shell regardless of the |
| INV-D-PRV-11 | [05-providers-and-validation](05-providers-and-validation.md) | A stored label is never blank: `provider.add`/`update` trim it and map empty to NULL. |
| INV-D-PRV-12 | [05-providers-and-validation](05-providers-and-validation.md) | Port mappings written through the API satisfy `1 <= localPort, remotePort <= 65535` and belong to a kubernetes or ssh provider. |
| INV-D-PRV-13 | [05-providers-and-validation](05-providers-and-validation.md) | While a service is `running`, `starting` or `reconnecting`, no `provider.*` write succeeds. |
| INV-D-PRV-14 | [05-providers-and-validation](05-providers-and-validation.md) | A service always keeps at least one provider through `provider.delete`. |
| INV-D-PRV-15 | [05-providers-and-validation](05-providers-and-validation.md) | `service.preflight` performs no database write, starts no process, changes no `updatedAt`, and never includes secrets in its result or issue messages. |
| INV-D-PRV-16 | [05-providers-and-validation](05-providers-and-validation.md) | `URLNormalizer.normalize` never panics, runs in time linear in the input, and is idempotent (`normalize(normalize(x)) == normalize(x)` when the first  |
| INV-D-PRV-17 | [05-providers-and-validation](05-providers-and-validation.md) | `URLNormalizer.normalize` returns either none or a string whose `isValidURL` is true; it returns the user's text verbatim after the (re)built scheme p |
| INV-D-PRV-18 | [05-providers-and-validation](05-providers-and-validation.md) | Stored interval values (`httpCheckInterval`, `monitorInterval`) are never coerced to the 5/10/30/60 set; runner floors apply at run time only. |
| INV-D-PRV-19 | [05-providers-and-validation](05-providers-and-validation.md) | `resolvedTarget` and `displayName` are pure functions of the stored provider columns and never include secrets. |
| INV-D-PRV-20 | [05-providers-and-validation](05-providers-and-validation.md) | The path base for relative validator/runner paths is `/` (the daemon's working directory). |
| INV-D-RPC-01 | [10-rpc-protocol](10-rpc-protocol.md) | Every line on the Unix socket is exactly one JSON value + `\n`. |
| INV-D-RPC-02 | [10-rpc-protocol](10-rpc-protocol.md) | Every method in [00 §5](00-overview-and-conventions.md) appears in §6 with params and result. |
| INV-D-RPC-03 | [10-rpc-protocol](10-rpc-protocol.md) | `error.data.kumaCode` is present on all application errors. |
| INV-D-RPC-04 | [10-rpc-protocol](10-rpc-protocol.md) | Event `seq` strictly increases and matches `meta.eventSeq` after each emit ([08 INV-D-LOG-08](08-logs-and-events.md)). |
| INV-D-RPC-05 | [10-rpc-protocol](10-rpc-protocol.md) | No secret material in RPC errors, events, or default responses (GR-04). |
| INV-D-SEC-01 | [02-security-and-secrets](02-security-and-secrets.md) | `master.key` is exactly 32 raw bytes, mode `0600`, in a `0700` data dir; the daemon never logs, returns, or serializes it. |
| INV-D-SEC-02 | [02-security-and-secrets](02-security-and-secrets.md) | Every payload the daemon writes into `provider.sshPassword`, `provider.ngrokAuthToken`, `kube_config.configContent` and backup secret fields is `nonce |
| INV-D-SEC-03 | [02-security-and-secrets](02-security-and-secrets.md) | Any payload produced by Kuma 1.x with the same `master.key` decrypts in the daemon, and vice versa. |
| INV-D-SEC-04 | [02-security-and-secrets](02-security-and-secrets.md) | A failure to encrypt aborts the whole write; plaintext is never persisted and never exported in place of a ciphertext. |
| INV-D-SEC-05 | [02-security-and-secrets](02-security-and-secrets.md) | `provider.sshPassword`/`ngrokAuthToken` are NULL when unset or empty; never an encrypted empty string. File-backed kubeconfigs store `encrypt("")`, ne |
| INV-D-SEC-06 | [02-security-and-secrets](02-security-and-secrets.md) | No RPC response, event, log line, error message, audit entry or persisted argv contains a secret value or kubeconfig plaintext, except `revealSecrets: |
| INV-D-SEC-07 | [02-security-and-secrets](02-security-and-secrets.md) | The socket is `0600` in a `0700` directory and every connection's peer uid equals the daemon uid, else it is dropped before any byte is read. |
| INV-D-SEC-08 | [02-security-and-secrets](02-security-and-secrets.md) | The REST listener binds only to loopback, requires a valid bearer token on every request, validates `Host`, rejects any `Origin`, and never emits CORS |
| INV-D-SEC-09 | [02-security-and-secrets](02-security-and-secrets.md) | Token comparison is constant-time; the token file is `0600`; the token is never returned by any call. |
| INV-D-SEC-10 | [02-security-and-secrets](02-security-and-secrets.md) | Askpass scripts, materialized kubeconfigs and validation temp files are created with their final mode (`0700`/`0600`/`0600`) inside `0700` directories |
| INV-D-SEC-11 | [02-security-and-secrets](02-security-and-secrets.md) | The SSH password is delivered to `ssh` only via the askpass file; it never appears in argv or environment. |
| INV-D-SEC-12 | [02-security-and-secrets](02-security-and-secrets.md) | A ciphertext-shaped value that cannot be decrypted is never used as a credential. |
| INV-D-SEC-13 | [02-security-and-secrets](02-security-and-secrets.md) | Redaction is total, idempotent, linear-time, and uses the single mark `***`. |
| INV-D-SEC-14 | [02-security-and-secrets](02-security-and-secrets.md) | Every mutating call, every `revealSecrets` request and every rejected connection/request produces exactly one audit entry whose `refs` contain only wh |
| INV-D-SEC-15 | [02-security-and-secrets](02-security-and-secrets.md) | The daemon's own environment and its children's environment never contain the API token or master key. |
| INV-D-SEC-16 | [02-security-and-secrets](02-security-and-secrets.md) | The default kubeconfig (`00000000-0000-0000-0000-000000000001`) is never encrypted, copied, exported or imported. |
| INV-D-SVC-01 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | A service created by `service.create` has exactly one provider, `activeProviderID` NULL, and every port mapping it owns has non-NULL `serviceID` and ` |
| INV-D-SVC-02 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | The effective active provider is `service.activeProviderID ?? providers.first?.id`; `provider.delete` of the effective active provider repoints `activ |
| INV-D-SVC-03 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `provider.add` makes the added provider active and bumps the service `updatedAt`. |
| INV-D-SVC-04 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `provider.set_ports` deletes only rows with the given `serviceID` **and** `providerID` (never legacy NULL-provider rows) and stores only ports in `1.. |
| INV-D-SVC-05 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `service.set_groups` / `service.toggle_group` never change `service.updatedAt`; `service.update`, `set_starred`, `set_disabled`, `switch_provider` alw |
| INV-D-SVC-06 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `service.duplicate` is atomic, produces fresh ids for the service, every provider and every port mapping, preserves `isDisabled`/`isStarred`, and maps |
| INV-D-SVC-07 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | A service with `isDisabled == true` is never operational after `service.set_disabled` returns, and is never a bulk start target. |
| INV-D-SVC-08 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `service.switch_provider` never leaves the old provider's process running after the new `activeProviderID` is committed. |
| INV-D-SVC-09 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `service.list` is a pure function of persisted rows plus the runtime store: identical filters and sort produce identical order; `BulkTargets` is exact |
| INV-D-SVC-10 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | No response of this spec contains `sshPassword`, `ngrokAuthToken` or kubeconfig plaintext. |
| INV-D-SVC-11 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | Every mutation listed in §3.9 emits its event(s) after commit, never before, and never for a no-op. |
| INV-D-WS-01 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | At the end of every operation at least one workspace exists; `workspace.delete` of the sole workspace changes nothing (no stop, no delete). |
| INV-D-WS-02 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | After a successful `workspace.reorder` the `sortOrder` values of all workspaces are exactly `0..n-1` in the new order and every workspace's `updatedAt |
| INV-D-WS-03 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `workspace.delete` stops every operational service of the workspace before deleting rows (DEV-03) and leaves no child rows (services, providers, ports |
| INV-D-WS-04 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | A managed avatar file is named `<UPPERCASE-UUID>.png`, is at most 512 px on its longest side (unless raw-imported by [09](09-dataport.md)), and is rep |
| INV-D-WS-05 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | The daemon never deletes, overwrites or writes a file outside `Workspaces/Images` as part of any workspace or image operation. |
| INV-D-WS-06 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | The daemon never writes an absolute path into `workspace.imagePath`; it only reads one that already exists in the data. |
| INV-D-WS-07 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | After any avatar write or delete, the next `workspace.get_image` (any `size`) reflects the new state. |
| INV-D-WS-08 | [04-workspaces-groups-services](04-workspaces-groups-services.md) | `workspace.name` written by the daemon is trimmed and non-empty. |

## 6. 1.x test matrices → DT groups

| 1.x test matrix | Primary daemon spec | DT group(s) | Notes |
|-----------------|---------------------|-------------|-------|
| [00-app-test-matrix.md](../testing/00-app-test-matrix.md) | [14-lifecycle-and-platform.md](14-lifecycle-and-platform.md), [03-settings-and-environment.md](03-settings-and-environment.md) | DT-LIF-*, DT-SET-* | App shell, onboarding flags, quit behavior |
| [01-onboarding-test-matrix.md](../testing/01-onboarding-test-matrix.md) | [03-settings-and-environment.md](03-settings-and-environment.md) | DT-SET-* | First-run prefs; `client.` keys |
| [02-settings-test-matrix.md](../testing/02-settings-test-matrix.md) | [03-settings-and-environment.md](03-settings-and-environment.md) | DT-SET-01…DT-SET-30 | Tool paths, PATH, dependencies |
| [03-workspace-test-matrix.md](../testing/03-workspace-test-matrix.md) | [04-workspaces-groups-services.md](04-workspaces-groups-services.md), [01-data-model.md](01-data-model.md) | DT-WS-*, DT-DAT-* | TC-A…F ↔ DT-WS in spec 04 §9 |
| [04-sidebar-test-matrix.md](../testing/04-sidebar-test-matrix.md) | [04-workspaces-groups-services.md](04-workspaces-groups-services.md) | DT-GRP-*, DT-SVC-* | Groups, deck list, selection |
| [05-data-port-test-matrix.md](../testing/05-data-port-test-matrix.md) | [09-dataport.md](09-dataport.md) | DT-DPT-01…DT-DPT-32 | TC-A…E ↔ DT-DPT in spec 09 §9 |
| [06-services-test-matrix.md](../testing/06-services-test-matrix.md) | [05](05-providers-and-validation.md), [06](06-execution-engine.md), [08](08-logs-and-events.md) | DT-PRV-*, DT-EXE-*, DT-LOG-* | TC-L* → DT-LOG; TC-D* → DT-EXE |

Explicit TC→DT citations appear in area specs (e.g. [08 §9](08-logs-and-events.md) maps TC-L03 → DT-LOG-01). Implementers should treat **DT-*** as normative daemon tests; **TC-*** as 1.x Swift test names preserved for traceability.

## 7. File coverage (appendix)

The full Swift file classification table (**302 files**) lives in [15-appendix-file-coverage.md](15-appendix-file-coverage.md). Summary:

| Class | Count (approx.) | Parity implication |
|-------|-----------------|-------------------|
| `daemon` | 87 | Must match `[PARITY]` FEAT + DT |
| `shared` | 43 | Daemon owns behavior; client owns shell |
| `client-only` | 172 | Excluded from parity gate; see `[CLIENT]` FEAT rows |

See [15-appendix-file-coverage.md](15-appendix-file-coverage.md) for the per-file `# | File | Class | Spec | Note` table.

## 8. RPC wire index (74 methods)

Full RPC↔CLI↔MCP↔REST table: [13 §10](13-rest-api.md) (mirrors [11 Appendix A](11-cli.md) + [12 Appendix A](12-mcp.md)). **73** methods on REST/MCP; **`daemon.rotate_api_token`** is CLI + Unix socket only.

---

## Gap audit (2026-11-02) — resolved 2026-11-03

| # | Issue | Resolution |
|---|--------|------------|
| 1 | ADD-120/121 collision (CLI vs REST) | CLI surface ids renumbered to **ADD-125** / **ADD-126**; REST keeps **ADD-120** / **ADD-121**. |
| 2 | `daemon.rotate_api_token` outside 00 §5 | Registered in [00 §5.1](00-overview-and-conventions.md); CLI/MCP/REST rows in 11/12/13 §10. |
| 3 | DEV-11 wording drift | Canonical one-liner in §3 above; feature specs cross-ref the full KV scope. |
| 4 | Legacy `docs/testing/**` vs DT-* | Unchanged: §6 mapping remains normative; migrate test docs in a follow-up. |
| 5 | `service.log_line` FEAT parity warnings | Event-only (00 §5.7); `check_traceability.py` ignores non-registry names in `--warn-feat-parity`. |

