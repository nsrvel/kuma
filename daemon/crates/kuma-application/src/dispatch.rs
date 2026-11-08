use crate::handlers::{
    daemon, data, env, events, exec, group, k8s, kubeconfig, logs, provider, service, settings,
    workspace,
};
use kuma_exec::ExecEngine;
use crate::lifecycle::{DataCounts, LifecycleState};
use kuma_protocol::jsonrpc::{Request, Response, ERR_INVALID_REQUEST, ERR_METHOD_NOT_FOUND};
use kuma_protocol::methods;
use kuma_store::StoreHandle;
use std::sync::Arc;

pub struct Application {
    store: Arc<StoreHandle>,
    exec: Arc<ExecEngine>,
    request_shutdown: Arc<dyn Fn() + Send + Sync>,
    lifecycle: LifecycleState,
    counts: DataCounts,
}

pub enum DispatchOutcome {
    Reply(Response),
    ShutdownRequested(Response),
}

impl Application {
    pub fn new(
        store: Arc<StoreHandle>,
        exec: Arc<ExecEngine>,
        request_shutdown: Arc<dyn Fn() + Send + Sync>,
        lifecycle: LifecycleState,
        counts: DataCounts,
    ) -> Self {
        Self {
            store,
            exec,
            request_shutdown,
            lifecycle,
            counts,
        }
    }

    pub fn exec(&self) -> &Arc<ExecEngine> {
        &self.exec
    }

    pub fn dispatch(&self, req: Request) -> DispatchOutcome {
        if req.jsonrpc != "2.0" {
            return DispatchOutcome::Reply(Response::err(
                req.id,
                ERR_INVALID_REQUEST,
                "jsonrpc must be 2.0",
            ));
        }

        let store = &self.store;
        let bus = store.events();
        let settings = store.settings();

        match req.method.as_str() {
            methods::DAEMON_PING => DispatchOutcome::Reply(daemon::ping(req.id)),
            methods::DAEMON_STATUS => DispatchOutcome::Reply(daemon::status(
                req.id,
                &self.lifecycle,
                &self.counts,
                self.exec.as_ref(),
            )),
            methods::DAEMON_SHUTDOWN => {
                let response = daemon::shutdown(
                    req.id,
                    self.exec.as_ref(),
                    self.request_shutdown.as_ref(),
                );
                DispatchOutcome::ShutdownRequested(response)
            }
            methods::DAEMON_ROTATE_API_TOKEN => DispatchOutcome::Reply(daemon::rotate_api_token(
                req.id,
                store.data_dir(),
            )),
            methods::SETTINGS_LIST => {
                DispatchOutcome::Reply(settings::list(req.id, settings, &req.params))
            }
            methods::SETTINGS_GET => {
                DispatchOutcome::Reply(settings::get(req.id, settings, &req.params))
            }
            methods::SETTINGS_SET => {
                DispatchOutcome::Reply(settings::set(req.id, settings, &req.params))
            }
            methods::SETTINGS_RESET => {
                DispatchOutcome::Reply(settings::reset(req.id, settings))
            }
            methods::ENV_PATH => {
                DispatchOutcome::Reply(env::path(req.id, store.env(), &req.params))
            }
            methods::ENV_REFRESH => {
                DispatchOutcome::Reply(env::refresh(req.id, store.env()))
            }
            methods::ENV_RESOLVE_EXECUTABLE => DispatchOutcome::Reply(env::resolve_executable(
                req.id,
                store.env(),
                &req.params,
            )),
            methods::ENV_VALIDATE_BINARY => DispatchOutcome::Reply(env::validate_binary(
                req.id,
                store.env(),
                &req.params,
            )),
            methods::ENV_DEPENDENCIES => {
                DispatchOutcome::Reply(env::dependencies(req.id, store.env()))
            }
            methods::EVENTS_SUBSCRIBE => {
                DispatchOutcome::Reply(events::subscribe(req.id, bus, &req.params))
            }
            methods::EVENTS_UNSUBSCRIBE => {
                DispatchOutcome::Reply(events::unsubscribe(req.id, bus, &req.params))
            }
            methods::WORKSPACE_LIST => {
                DispatchOutcome::Reply(workspace::list(req.id, store.workspace()))
            }
            methods::WORKSPACE_GET => DispatchOutcome::Reply(workspace::get(
                req.id,
                store.workspace(),
                &req.params,
            )),
            methods::WORKSPACE_CREATE => DispatchOutcome::Reply(workspace::create(
                req.id,
                store.workspace(),
                bus,
                &req.params,
            )),
            methods::WORKSPACE_UPDATE => DispatchOutcome::Reply(workspace::update(
                req.id,
                store.workspace(),
                bus,
                &req.params,
            )),
            methods::WORKSPACE_DELETE => DispatchOutcome::Reply(workspace::delete(
                req.id,
                store,
                &self.exec,
                bus,
                &req.params,
            )),
            methods::WORKSPACE_REORDER => DispatchOutcome::Reply(workspace::reorder(
                req.id,
                store.workspace(),
                bus,
                &req.params,
            )),
            methods::WORKSPACE_SET_IMAGE => DispatchOutcome::Reply(workspace::set_image(
                req.id,
                store.workspace(),
                bus,
                &req.params,
            )),
            methods::WORKSPACE_CLEAR_IMAGE => DispatchOutcome::Reply(workspace::clear_image(
                req.id,
                store.workspace(),
                bus,
                &req.params,
            )),
            methods::WORKSPACE_GET_IMAGE => DispatchOutcome::Reply(workspace::get_image(
                req.id,
                store.workspace(),
                &req.params,
            )),
            methods::GROUP_LIST => DispatchOutcome::Reply(group::list(
                req.id,
                store.group(),
                &req.params,
            )),
            methods::GROUP_CREATE => DispatchOutcome::Reply(group::create(
                req.id,
                store.group(),
                bus,
                &req.params,
            )),
            methods::GROUP_UPDATE => DispatchOutcome::Reply(group::update(
                req.id,
                store.group(),
                bus,
                &req.params,
            )),
            methods::GROUP_DELETE => DispatchOutcome::Reply(group::delete(
                req.id,
                store.group(),
                bus,
                &req.params,
            )),
            methods::GROUP_REORDER => DispatchOutcome::Reply(group::reorder(
                req.id,
                store.group(),
                bus,
                &req.params,
            )),
            methods::SERVICE_LIST => DispatchOutcome::Reply(service::list(
                req.id,
                store.service(),
                &req.params,
            )),
            methods::SERVICE_GET => DispatchOutcome::Reply(service::get(
                req.id,
                store.service(),
                &req.params,
            )),
            methods::SERVICE_CREATE => DispatchOutcome::Reply(service::create(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_UPDATE => DispatchOutcome::Reply(service::update(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_DELETE => DispatchOutcome::Reply(service::delete(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_DUPLICATE => DispatchOutcome::Reply(service::duplicate(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_SET_STARRED => DispatchOutcome::Reply(service::set_starred(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_SET_DISABLED => DispatchOutcome::Reply(service::set_disabled(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_SET_GROUPS => DispatchOutcome::Reply(service::set_groups(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_TOGGLE_GROUP => DispatchOutcome::Reply(service::toggle_group(
                req.id,
                store.service(),
                bus,
                &req.params,
            )),
            methods::SERVICE_SWITCH_PROVIDER => DispatchOutcome::Reply(service::switch_provider(
                req.id,
                store,
                &self.exec,
                bus,
                &req.params,
            )),
            methods::SERVICE_PREFLIGHT => DispatchOutcome::Reply(service::preflight(
                req.id,
                store.service(),
                &req.params,
            )),
            methods::PROVIDER_LIST => DispatchOutcome::Reply(provider::list(
                req.id,
                store.provider(),
                &req.params,
            )),
            methods::PROVIDER_ADD => DispatchOutcome::Reply(provider::add(
                req.id,
                store.provider(),
                store.service(),
                bus,
                &req.params,
            )),
            methods::PROVIDER_UPDATE => DispatchOutcome::Reply(provider::update(
                req.id,
                store.provider(),
                store.vault(),
                bus,
                &req.params,
            )),
            methods::PROVIDER_DELETE => DispatchOutcome::Reply(provider::delete(
                req.id,
                store.provider(),
                bus,
                &req.params,
            )),
            methods::PROVIDER_SET_PORTS => DispatchOutcome::Reply(provider::set_ports(
                req.id,
                store.provider(),
                bus,
                &req.params,
            )),
            methods::SERVICE_STATUS => DispatchOutcome::Reply(exec::status(
                req.id,
                &self.exec,
                &req.params,
            )),
            methods::SERVICE_STATUSES => DispatchOutcome::Reply(exec::statuses(
                req.id,
                &self.exec,
                &req.params,
            )),
            methods::PORTS_CHECK => {
                DispatchOutcome::Reply(exec::ports_check(req.id, &req.params))
            }
            methods::SERVICE_START => DispatchOutcome::Reply(exec::start(
                req.id,
                store,
                &self.exec,
                bus,
                &req.params,
            )),
            methods::SERVICE_STOP => DispatchOutcome::Reply(exec::stop(
                req.id,
                &self.exec,
                bus,
                &req.params,
            )),
            methods::SERVICE_RESTART => DispatchOutcome::Reply(exec::restart(
                req.id,
                store,
                &self.exec,
                bus,
                &req.params,
            )),
            methods::SERVICE_START_ALL => DispatchOutcome::Reply(exec::start_all(
                req.id,
                store,
                &self.exec,
                bus,
                &req.params,
            )),
            methods::SERVICE_STOP_ALL => {
                DispatchOutcome::Reply(exec::stop_all(&self.exec, req.id))
            }
            methods::RUNTIME_ADOPT_REPORT => {
                DispatchOutcome::Reply(exec::adopt_report(req.id, &self.exec))
            }
            methods::KUBECONFIG_LIST => {
                DispatchOutcome::Reply(kubeconfig::list(req.id, store.kubeconfig()))
            }
            methods::KUBECONFIG_GET => DispatchOutcome::Reply(kubeconfig::get(
                req.id,
                store.kubeconfig(),
                &req.params,
            )),
            methods::KUBECONFIG_CREATE => DispatchOutcome::Reply(kubeconfig::create(
                req.id,
                store.kubeconfig(),
                &req.params,
            )),
            methods::KUBECONFIG_UPDATE => DispatchOutcome::Reply(kubeconfig::update(
                req.id,
                store.kubeconfig(),
                &req.params,
            )),
            methods::KUBECONFIG_DELETE => DispatchOutcome::Reply(kubeconfig::delete(
                req.id,
                store.kubeconfig(),
                &req.params,
            )),
            methods::KUBECONFIG_CONTEXTS => DispatchOutcome::Reply(kubeconfig::contexts(
                req.id,
                store.kubeconfig(),
                &req.params,
            )),
            methods::KUBECONFIG_TEST_CONNECTION => DispatchOutcome::Reply(
                kubeconfig::test_connection(req.id, store.kubeconfig(), &req.params),
            ),
            methods::K8S_NAMESPACES => {
                DispatchOutcome::Reply(k8s::namespaces(req.id, store, &req.params))
            }
            methods::K8S_RESOURCES => {
                DispatchOutcome::Reply(k8s::resources(req.id, store, &req.params))
            }
            methods::K8S_RESOLVE_TARGET => DispatchOutcome::Reply(k8s::resolve_target(
                req.id,
                store.kubeconfig(),
                &req.params,
            )),
            methods::LOGS_TAIL => {
                DispatchOutcome::Reply(logs::tail(req.id, store.logs(), &req.params))
            }
            methods::LOGS_CLEAR => {
                DispatchOutcome::Reply(logs::clear(req.id, store.logs(), &req.params))
            }
            methods::LOGS_WORKLOAD_TAIL => DispatchOutcome::Reply(logs::workload_tail(
                req.id,
                store.logs(),
                &req.params,
            )),
            methods::LOGS_FOLLOW => DispatchOutcome::Reply(logs::follow(req.id, store.logs(), &req.params)),
            methods::DATA_EXPORT => {
                DispatchOutcome::Reply(data::export(req.id, store.dataport()))
            }
            methods::DATA_EXPORT_SERVICE_JSON => DispatchOutcome::Reply(data::export_service_json(
                req.id,
                store.dataport(),
                &req.params,
            )),
            methods::DATA_IMPORT_PREVIEW => DispatchOutcome::Reply(data::import_preview(
                req.id,
                store.dataport(),
                &req.params,
            )),
            methods::DATA_IMPORT => DispatchOutcome::Reply(data::import(
                req.id,
                store.dataport(),
                &req.params,
            )),
            methods::DATA_FACTORY_RESET => DispatchOutcome::Reply(data::factory_reset(
                req.id,
                store,
                &self.exec,
            )),
            other => DispatchOutcome::Reply(Response::err(
                req.id,
                ERR_METHOD_NOT_FOUND,
                format!("method not found: {other}"),
            )),
        }
    }
}
