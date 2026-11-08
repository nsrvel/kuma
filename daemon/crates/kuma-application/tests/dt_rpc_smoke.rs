//! Dispatch smoke: every registry RPC is wired (not METHOD_NOT_FOUND).

use kuma_application::{
    Application, ClientKind, DataCounts, DispatchContext, DispatchOutcome, LifecycleState,
};
use kuma_exec::ExecEngine;
use kuma_protocol::jsonrpc::{Request, ERR_METHOD_NOT_FOUND};
use kuma_protocol::methods;
use kuma_store::StoreHandle;
use serde_json::{json, Map, Value};
use std::sync::Arc;

struct SmokeFixture {
    _dir: tempfile::TempDir,
    app: Application,
    workspace_id: String,
    service_id: String,
    provider_id: String,
    group_id: String,
    kube_default: String,
}

impl SmokeFixture {
    fn new() -> Self {
        let dir = tempfile::tempdir().unwrap();
        let store = Arc::new(StoreHandle::open(dir.path()).unwrap());
        let workspace_id = store.workspace().list().unwrap()[0]["id"]
            .as_str()
            .unwrap()
            .to_string();

        let mut create: Map<String, Value> = Map::new();
        create.insert("name".into(), json!("rpc-smoke-svc"));
        create.insert("workspaceID".into(), json!(workspace_id));
        let svc = store.service().create(&create).unwrap();
        let service_id = svc["id"].as_str().unwrap().to_string();
        let provider_id = store.provider().list(&service_id).unwrap()["providers"][0]["id"]
            .as_str()
            .unwrap()
            .to_string();

        let mut gparams: Map<String, Value> = Map::new();
        gparams.insert("workspaceID".into(), json!(workspace_id));
        gparams.insert("name".into(), json!("smoke-grp"));
        let grp = store.group().create(&gparams).unwrap();
        let group_id = grp["id"].as_str().unwrap().to_string();

        let kube_default = kuma_store::kubeconfig::DEFAULT_ID.to_string();

        let app = Application::new(
            store,
            ExecEngine::new(),
            Arc::new(|| {}),
            LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000001".into()),
            DataCounts::empty(),
        );

        Self {
            _dir: dir,
            app,
            workspace_id,
            service_id,
            provider_id,
            group_id,
            kube_default,
        }
    }

    fn dispatch(&self, method: &str, params: Value) -> (DispatchOutcome, i32) {
        let req = Request {
            jsonrpc: "2.0".into(),
            method: method.into(),
            params,
            id: Some(json!(method)),
        };
        let mut ctx = DispatchContext::unix(ClientKind::Cli);
        let outcome = self.app.dispatch(req, &mut ctx);
        let code = match &outcome {
            DispatchOutcome::Reply(r) | DispatchOutcome::ShutdownRequested(r) => {
                r.error.as_ref().map(|e| e.code).unwrap_or(0)
            }
        };
        (outcome, code)
    }
}

fn params_for(f: &SmokeFixture, method: &str) -> Value {
    match method {
        methods::DAEMON_PING => json!({ "clientKind": "cli" }),
        methods::DAEMON_STATUS | methods::RUNTIME_ADOPT_REPORT => json!({}),
        methods::DAEMON_SHUTDOWN => json!({ "stopServices": false }),
        methods::DAEMON_ROTATE_API_TOKEN => json!({}),
        methods::SETTINGS_LIST | methods::ENV_PATH | methods::ENV_DEPENDENCIES => json!({}),
        methods::SETTINGS_GET => json!({ "key": "autoResume" }),
        methods::SETTINGS_SET => json!({ "settings": { "autoResume": true } }),
        methods::SETTINGS_RESET => json!({}),
        methods::ENV_RESOLVE_EXECUTABLE => json!({ "command": "echo" }),
        methods::ENV_VALIDATE_BINARY => json!({ "path": "/bin/echo" }),
        methods::ENV_REFRESH => json!({}),
        methods::WORKSPACE_LIST => json!({}),
        methods::WORKSPACE_GET | methods::WORKSPACE_DELETE | methods::WORKSPACE_GET_IMAGE => {
            json!({ "id": f.workspace_id })
        }
        methods::WORKSPACE_CREATE => json!({ "name": "ws-smoke-2" }),
        methods::WORKSPACE_UPDATE => json!({ "id": f.workspace_id, "name": "Default" }),
        methods::WORKSPACE_REORDER => json!({ "order": [f.workspace_id.clone()] }),
        methods::WORKSPACE_SET_IMAGE => json!({ "id": f.workspace_id, "imageBase64": "" }),
        methods::WORKSPACE_CLEAR_IMAGE => json!({ "id": f.workspace_id }),
        methods::GROUP_LIST => json!({ "workspaceID": f.workspace_id }),
        methods::GROUP_CREATE => json!({ "workspaceID": f.workspace_id, "name": "g2" }),
        methods::GROUP_UPDATE => json!({ "id": f.group_id, "name": "smoke-grp" }),
        methods::GROUP_DELETE => json!({ "id": f.group_id }),
        methods::GROUP_REORDER => json!({ "workspaceID": f.workspace_id, "order": [] }),
        methods::SERVICE_LIST => json!({}),
        methods::SERVICE_GET
        | methods::SERVICE_DELETE
        | methods::SERVICE_DUPLICATE
        | methods::SERVICE_PREFLIGHT
        | methods::SERVICE_START
        | methods::SERVICE_STOP
        | methods::SERVICE_RESTART
        | methods::SERVICE_STATUS
        | methods::LOGS_TAIL
        | methods::LOGS_CLEAR
        | methods::LOGS_WORKLOAD_TAIL
        | methods::LOGS_FOLLOW
        | methods::DATA_EXPORT_SERVICE_JSON => {
            json!({ "id": f.service_id, "serviceID": f.service_id })
        }
        methods::SERVICE_CREATE => json!({ "workspaceID": f.workspace_id, "name": "another" }),
        methods::SERVICE_UPDATE => json!({ "id": f.service_id, "name": "rpc-smoke-svc" }),
        methods::SERVICE_SET_STARRED => json!({ "id": f.service_id, "starred": true }),
        methods::SERVICE_SET_DISABLED => json!({ "id": f.service_id, "disabled": false }),
        methods::SERVICE_SET_GROUPS => json!({ "id": f.service_id, "groupIDs": [] }),
        methods::SERVICE_TOGGLE_GROUP => {
            json!({ "id": f.service_id, "groupID": f.group_id })
        }
        methods::SERVICE_SWITCH_PROVIDER => {
            json!({ "id": f.service_id, "providerID": f.provider_id })
        }
        methods::SERVICE_START_ALL | methods::SERVICE_STOP_ALL => json!({}),
        methods::SERVICE_STATUSES => json!({ "serviceIDs": [f.service_id.clone()] }),
        methods::PROVIDER_LIST => json!({ "serviceID": f.service_id }),
        methods::PROVIDER_ADD => {
            json!({ "serviceID": f.service_id, "provider": { "type": "shell", "label": "x" } })
        }
        methods::PROVIDER_UPDATE => {
            json!({ "id": f.provider_id, "type": "shell", "runCommand": "echo hi" })
        }
        methods::PROVIDER_DELETE => json!({ "id": f.provider_id }),
        methods::PROVIDER_SET_PORTS => {
            json!({
                "serviceID": f.service_id,
                "providerID": f.provider_id,
                "ports": [{ "localPort": 18080, "remotePort": 8080 }],
            })
        }
        methods::PORTS_CHECK => json!({ "localPort": 18080 }),
        methods::KUBECONFIG_LIST => json!({}),
        methods::KUBECONFIG_GET
        | methods::KUBECONFIG_DELETE
        | methods::KUBECONFIG_CONTEXTS
        | methods::KUBECONFIG_TEST_CONNECTION => json!({ "id": f.kube_default }),
        methods::KUBECONFIG_CREATE => {
            json!({ "name": "smoke-k", "content": "apiVersion: v1\nkind: Config\n" })
        }
        methods::KUBECONFIG_UPDATE => json!({ "id": f.kube_default, "name": "Default" }),
        methods::K8S_NAMESPACES | methods::K8S_RESOURCES => {
            json!({ "kubeConfigID": f.kube_default })
        }
        methods::K8S_RESOLVE_TARGET => {
            json!({ "kubeConfigID": f.kube_default, "targetName": "pod/redis" })
        }
        methods::EVENTS_SUBSCRIBE => json!({ "topics": ["*"] }),
        methods::EVENTS_UNSUBSCRIBE => json!({ "subscriptionId": "0" }),
        methods::DATA_EXPORT => json!({ "scope": "all" }),
        methods::DATA_IMPORT_PREVIEW | methods::DATA_IMPORT => json!({ "bundle": {} }),
        methods::DATA_FACTORY_RESET => json!({}),
        _ => json!({}),
    }
}

#[test]
fn dt_rpc_smoke_all_74_methods_wired() {
    let f = SmokeFixture::new();
    assert_eq!(methods::ALL.len(), 74);
    for method in methods::ALL {
        let params = params_for(&f, method);
        let (outcome, code) = f.dispatch(method, params);
        assert_ne!(code, ERR_METHOD_NOT_FOUND, "method not wired: {method}");
        if *method == methods::DAEMON_SHUTDOWN {
            assert!(matches!(outcome, DispatchOutcome::ShutdownRequested(_)));
        }
    }
}
