# MCP / RPC surface audit (2026-11-04)

Manual cross-check of **`mcp-tools.csv`** against [00 §5](00-overview-and-conventions.md), [11](11-cli.md), [12](12-mcp.md), [13 §10](13-rest-api.md), and Swift daemon coverage ([15-appendix](15-appendix-file-coverage.md)).

**Verdict:** No missing MCP tool for any registry RPC that should expose MCP. **`mcp-tools.csv` has 74 data rows** (73 × `mcp,rest,cli` + 1 × `cli_only` for `daemon.rotate_api_token`).

Regenerate CSV: `python3 docs/specs/daemon/export_mcp_tools_csv.py`

---

## Counts

| Surface | Count | Notes |
|---------|------:|-------|
| RPC registry (00 §5.1–5.6) | **74** | Authoritative method names |
| MCP tools (`kuma_*`) | **73** | CSV rows with `surface=mcp,rest,cli` |
| CSV rows (`cli_only`) | **1** | `daemon.rotate_api_token` — empty `mcp_tool` / `rest_endpoint` |
| MCP resources (12 §3.7) | **4** | Not tools; mirror read RPCs |
| Events (00 §5.7) | **13** | Delivered via `events.subscribe`, not MCP tools |
| CLI-only (no RPC) | **3** | `daemon run`, `daemon install`, `daemon uninstall` |

`check_traceability.py`: exit **0**.

---

## All 74 RPC methods (one-by-one)

| # | Module | RPC | MCP tool | REST (primary) | In CSV |
|---|--------|-----|----------|----------------|--------|
| 1 | Daemon | `daemon.ping` | `kuma_daemon_ping` | `GET /v1/daemon/ping` | yes |
| 2 | Daemon | `daemon.status` | `kuma_daemon_status` | `GET /v1/daemon/status` | yes |
| 3 | Daemon | `daemon.shutdown` | `kuma_daemon_shutdown` | `POST /v1/daemon/shutdown` | yes |
| 4 | Daemon | `daemon.rotate_api_token` | — (socket-only) | — (not exposed) | yes (`surface=cli_only`) |
| 5 | Settings | `settings.list` | `kuma_settings_list` | `GET /v1/settings` | yes |
| 6 | Settings | `settings.get` | `kuma_settings_get` | `GET /v1/settings/{key}` | yes |
| 7 | Settings | `settings.set` | `kuma_settings_set` | `PUT /v1/settings` | yes |
| 8 | Settings | `settings.reset` | `kuma_settings_reset` | `POST /v1/settings/reset` | yes |
| 9 | Environment | `env.path` | `kuma_env_path` | `GET /v1/env/path` | yes |
| 10 | Environment | `env.resolve_executable` | `kuma_env_resolve_executable` | `POST /v1/env/resolve-executable` | yes |
| 11 | Environment | `env.validate_binary` | `kuma_env_validate_binary` | `POST /v1/env/validate-binary` | yes |
| 12 | Environment | `env.dependencies` | `kuma_env_dependencies` | `GET /v1/env/dependencies` | yes |
| 13 | Environment | `env.refresh` | `kuma_env_refresh` | `POST /v1/env/refresh` | yes |
| 14 | Workspace | `workspace.list` | `kuma_workspace_list` | `GET /v1/workspaces` | yes |
| 15 | Workspace | `workspace.get` | `kuma_workspace_get` | `GET /v1/workspaces/{workspaceId}` | yes |
| 16 | Workspace | `workspace.create` | `kuma_workspace_create` | `POST /v1/workspaces` | yes |
| 17 | Workspace | `workspace.update` | `kuma_workspace_update` | `PATCH /v1/workspaces/{workspaceId}` | yes |
| 18 | Workspace | `workspace.delete` | `kuma_workspace_delete` | `DELETE /v1/workspaces/{workspaceId}` | yes |
| 19 | Workspace | `workspace.reorder` | `kuma_workspace_reorder` | `PUT /v1/workspaces/order` | yes |
| 20 | Workspace | `workspace.set_image` | `kuma_workspace_set_image` | `PUT /v1/workspaces/{workspaceId}/image` | yes |
| 21 | Workspace | `workspace.clear_image` | `kuma_workspace_clear_image` | `DELETE /v1/workspaces/{workspaceId}/image` | yes |
| 22 | Workspace | `workspace.get_image` | `kuma_workspace_get_image` | `GET /v1/workspaces/{workspaceId}/image` | yes |
| 23 | Group | `group.list` | `kuma_group_list` | `GET /v1/workspaces/{workspaceId}/groups` | yes |
| 24 | Group | `group.create` | `kuma_group_create` | `POST /v1/workspaces/{workspaceId}/groups` | yes |
| 25 | Group | `group.update` | `kuma_group_update` | `PATCH /v1/groups/{groupId}` | yes |
| 26 | Group | `group.delete` | `kuma_group_delete` | `DELETE /v1/groups/{groupId}` | yes |
| 27 | Group | `group.reorder` | `kuma_group_reorder` | `PUT /v1/workspaces/{workspaceId}/groups/order` | yes |
| 28 | Service | `service.list` | `kuma_service_list` | `GET /v1/services` | yes |
| 29 | Service | `service.get` | `kuma_service_get` | `GET /v1/services/{serviceId}` | yes |
| 30 | Service | `service.create` | `kuma_service_create` | `POST /v1/workspaces/{workspaceId}/services` | yes |
| 31 | Service | `service.update` | `kuma_service_update` | `PATCH /v1/services/{serviceId}` | yes |
| 32 | Service | `service.delete` | `kuma_service_delete` | `DELETE /v1/services/{serviceId}` | yes |
| 33 | Service | `service.duplicate` | `kuma_service_duplicate` | `POST /v1/services/{serviceId}/duplicate` | yes |
| 34 | Service | `service.set_starred` | `kuma_service_set_starred` | `PUT /v1/services/{serviceId}/starred` | yes |
| 35 | Service | `service.set_disabled` | `kuma_service_set_disabled` | `PUT /v1/services/{serviceId}/disabled` | yes |
| 36 | Service | `service.set_groups` | `kuma_service_set_groups` | `PUT /v1/services/{serviceId}/groups` | yes |
| 37 | Service | `service.toggle_group` | `kuma_service_toggle_group` | `POST /v1/services/{serviceId}/groups/{groupId}/toggle` | yes |
| 38 | Service | `service.switch_provider` | `kuma_service_switch_provider` | `POST /v1/services/{serviceId}/switch-provider` | yes |
| 39 | Provider | `provider.list` | `kuma_provider_list` | `GET /v1/services/{serviceId}/providers` | yes |
| 40 | Provider | `provider.add` | `kuma_provider_add` | `POST /v1/services/{serviceId}/providers` | yes |
| 41 | Provider | `provider.update` | `kuma_provider_update` | `PATCH /v1/providers/{providerId}` | yes |
| 42 | Provider | `provider.delete` | `kuma_provider_delete` | `DELETE /v1/providers/{providerId}` | yes |
| 43 | Provider | `provider.set_ports` | `kuma_provider_set_ports` | `PUT /v1/providers/{providerId}/ports` | yes |
| 44 | Execution | `service.preflight` | `kuma_service_preflight` | `POST /v1/services/{serviceId}/preflight` | yes |
| 45 | Execution | `service.start` | `kuma_service_start` | `POST /v1/services/{serviceId}/start` | yes |
| 46 | Execution | `service.stop` | `kuma_service_stop` | `POST /v1/services/{serviceId}/stop` | yes |
| 47 | Execution | `service.restart` | `kuma_service_restart` | `POST /v1/services/{serviceId}/restart` | yes |
| 48 | Execution | `service.start_all` | `kuma_service_start_all` | `POST /v1/services/start-all` | yes |
| 49 | Execution | `service.stop_all` | `kuma_service_stop_all` | `POST /v1/services/stop-all` | yes |
| 50 | Execution | `service.status` | `kuma_service_status` | `GET /v1/services/{serviceId}/status` | yes |
| 51 | Execution | `service.statuses` | `kuma_service_statuses` | `GET /v1/services/statuses` | yes |
| 52 | Execution | `ports.check` | `kuma_ports_check` | `POST /v1/ports/check` | yes |
| 53 | Execution | `runtime.adopt_report` | `kuma_runtime_adopt_report` | `GET /v1/runtime/adopt-report` | yes |
| 54 | Kubernetes | `kubeconfig.list` | `kuma_kubeconfig_list` | `GET /v1/kubeconfigs` | yes |
| 55 | Kubernetes | `kubeconfig.get` | `kuma_kubeconfig_get` | `GET /v1/kubeconfigs/{kubeconfigId}` | yes |
| 56 | Kubernetes | `kubeconfig.create` | `kuma_kubeconfig_create` | `POST /v1/kubeconfigs` | yes |
| 57 | Kubernetes | `kubeconfig.update` | `kuma_kubeconfig_update` | `PATCH /v1/kubeconfigs/{kubeconfigId}` | yes |
| 58 | Kubernetes | `kubeconfig.delete` | `kuma_kubeconfig_delete` | `DELETE /v1/kubeconfigs/{kubeconfigId}` | yes |
| 59 | Kubernetes | `kubeconfig.contexts` | `kuma_kubeconfig_contexts` | `GET /v1/kubeconfigs/{kubeconfigId}/contexts` | yes |
| 60 | Kubernetes | `kubeconfig.test_connection` | `kuma_kubeconfig_test_connection` | `POST /v1/kubeconfigs/{kubeconfigId}/test-connection` | yes |
| 61 | Kubernetes | `k8s.resolve_target` | `kuma_k8s_resolve_target` | `POST /v1/k8s/resolve-target` | yes |
| 62 | Kubernetes | `k8s.namespaces` | `kuma_k8s_namespaces` | `GET /v1/k8s/namespaces` | yes |
| 63 | Kubernetes | `k8s.resources` | `kuma_k8s_resources` | `GET /v1/k8s/resources` | yes |
| 64 | Logs | `logs.tail` | `kuma_logs_tail` | `GET /v1/services/{serviceId}/logs/activity` | yes |
| 65 | Logs | `logs.clear` | `kuma_logs_clear` | `DELETE /v1/services/{serviceId}/logs/activity` | yes |
| 66 | Logs | `logs.workload_tail` | `kuma_logs_workload_tail` | `GET /v1/services/{serviceId}/logs/workload` | yes |
| 67 | Logs | `logs.follow` | `kuma_logs_follow` | `GET /v1/services/{serviceId}/logs/workload/stream` (SSE) | yes |
| 68 | Events | `events.subscribe` | `kuma_events_subscribe` | `GET /v1/events/stream` (SSE) | yes |
| 69 | Events | `events.unsubscribe` | `kuma_events_unsubscribe` | `DELETE /v1/events/subscriptions/{subscriptionId}` | yes |
| 70 | DataPort | `data.export` | `kuma_data_export` | `POST /v1/data/export` | yes |
| 71 | DataPort | `data.export_service_json` | `kuma_data_export_service_json` | `GET /v1/services/{serviceId}/export-json` | yes |
| 72 | DataPort | `data.import_preview` | `kuma_data_import_preview` | `POST /v1/data/import/preview` | yes |
| 73 | DataPort | `data.import` | `kuma_data_import` | `POST /v1/data/import` | yes |
| 74 | DataPort | `data.factory_reset` | `kuma_data_factory_reset` | `POST /v1/data/factory-reset` | yes |

---

## MCP resources (not in `mcp-tools.csv`)

| URI | Backing RPC |
|-----|-------------|
| `kuma://daemon/status` | `daemon.status` |
| `kuma://settings` | `settings.list` |
| `kuma://workspaces` | `workspace.list` |
| `kuma://env/dependencies` | `env.dependencies` |

---

## Events (not MCP tools)

`service.state_changed`, `service.log_line`, `service.created`, `service.updated`, `service.deleted`, `group.changed`, `workspace.changed`, `kubeconfig.changed`, `settings.changed`, `notify`, `data.imported`, `data.reset`, `daemon.shutting_down`

---

## Swift / parity (summary)

Independent pass over **87 daemon + 43 shared** Swift files ([7637027d audit](7637027d-95bd-4af1-a437-07d182007615)): **0 gaps** — every daemon-owned user operation maps to §5 RPC, an event, or an explicit `[CLIENT]` split.

---

## Intentionally not RPC / not MCP tools

| Capability | Where | Why |
|------------|-------|-----|
| Run daemon process | `kuma daemon run` | Local server; not an RPC |
| LaunchAgent install | `kuma daemon install/uninstall` | macOS plist; ADD-110 |
| Rotate API token over MCP/REST | — | Security; Unix socket only |
| Crypto vault / migrations | startup | Side effect of daemon lifecycle |
| UI validation drafts | Swift inspector | `service.preflight` on persisted data |
