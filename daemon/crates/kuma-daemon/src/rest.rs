use crate::rest_registry::{match_route, path_params_to_rpc, RestRoute};
use axum::body::Body;
use axum::extract::{Request as AxumRequest, State};
use axum::http::{header, HeaderMap, HeaderValue, Method, StatusCode};
use axum::response::sse::Event;
use axum::response::{IntoResponse, Json, Response, Sse};
use axum::Router;
use futures_util::stream::{self, StreamExt};
use kuma_application::{Application, DispatchContext, DispatchOutcome};
use kuma_protocol::jsonrpc::{Request, Response as JsonRpcResponse, ERR_KUMA};
use kuma_store::api_token_path;
use serde_json::{json, Value};
use std::convert::Infallible;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use subtle::ConstantTimeEq;
use tokio::net::TcpListener;

#[derive(Clone)]
pub struct RestState {
    pub app: Arc<Application>,
    token_path: PathBuf,
}

pub async fn serve(app: Arc<Application>, data_dir: &Path) -> anyhow::Result<()> {
    if std::env::var("KUMA_REST").ok().as_deref() != Some("1") {
        return Ok(());
    }
    let token_path = api_token_path(data_dir);
    let state = RestState { app, token_path };
    let router = build_router(state);
    let addr: std::net::SocketAddr = "127.0.0.1:9364".parse().unwrap();
    let listener = TcpListener::bind(addr).await?;
    tracing::info!(%addr, routes = crate::rest_registry::route_keys().len(), "REST listener active");
    axum::serve(listener, router).await?;
    Ok(())
}

fn build_router(state: RestState) -> Router {
    Router::new()
        .route("/v1/jsonrpc", axum::routing::post(jsonrpc))
        .nest("/v1", Router::new().fallback(v1_fallback))
        .layer(axum::middleware::from_fn(security_headers))
        .with_state(state)
}

async fn security_headers(request: AxumRequest, next: axum::middleware::Next) -> Response {
    let mut resp = next.run(request).await;
    resp.headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    resp.headers_mut().insert(
        header::HeaderName::from_static("x-content-type-options"),
        HeaderValue::from_static("nosniff"),
    );
    resp
}

async fn v1_fallback(State(state): State<RestState>, req: AxumRequest) -> Response {
    let method = req.method().clone();
    let path = req
        .uri()
        .path()
        .strip_prefix("/v1")
        .unwrap_or(req.uri().path())
        .to_string();
    let headers = req.headers().clone();
    if reject_origin(&headers) {
        return rest_error(
            StatusCode::FORBIDDEN,
            "KUMA_SEC_ORIGIN",
            "Origin not allowed",
        )
        .into_response();
    }
    if reject_reveal(&req) {
        return rest_error(
            StatusCode::FORBIDDEN,
            "KUMA_SEC_REVEAL_FORBIDDEN",
            "revealSecrets forbidden",
        )
        .into_response();
    }
    let token = read_token_file(&state.token_path);
    if !authorized(&headers, &token) {
        return rest_error(
            StatusCode::UNAUTHORIZED,
            "KUMA_SEC_UNAUTHORIZED",
            "Unauthorized",
        )
        .into_response();
    }
    if reject_host(&headers) {
        return rest_error(StatusCode::FORBIDDEN, "KUMA_SEC_HOST", "Host not allowed")
            .into_response();
    }

    let Some((route, caps)) = match_route(&method, &path) else {
        return rest_error(StatusCode::NOT_FOUND, "KUMA_NOT_FOUND", "route not found")
            .into_response();
    };

    if route.path == "/events/stream" && method == Method::GET {
        return events_sse(state, &headers).await.into_response();
    }
    if route.path == "/services/:serviceId/logs/workload/stream" && method == Method::GET {
        return logs_sse(state, caps, &headers).await.into_response();
    }
    if route.rpc_method == "workspace.get_image" && method == Method::GET {
        return workspace_image_png(state, caps).await.into_response();
    }

    let (params, status_override) = match extract_params(req, &route, &caps).await {
        Ok(v) => v,
        Err(code) => {
            return rest_error(code, "KUMA_BAD_REQUEST", "invalid request body").into_response();
        }
    };

    match dispatch_rpc(&state, &route.rpc_method, params, status_override) {
        Ok((status, body)) => (status, Json(body)).into_response(),
        Err((status, code, msg)) => rest_error(status, code, &msg).into_response(),
    }
}

async fn extract_params(
    req: AxumRequest,
    route: &RestRoute,
    caps: &std::collections::HashMap<String, String>,
) -> Result<(Value, Option<StatusCode>), StatusCode> {
    let mut params = Value::Object(path_params_to_rpc(caps));
    if let Some(q) = req.uri().query() {
        merge_query(q, &mut params);
    }
    if matches!(route.method, Method::POST | Method::PUT | Method::PATCH) {
        let bytes = axum::body::to_bytes(req.into_body(), 4 * 1024 * 1024)
            .await
            .map_err(|_| StatusCode::BAD_REQUEST)?;
        if !bytes.is_empty() {
            let body: Value = serde_json::from_slice(&bytes).unwrap_or(json!({}));
            merge_body(&body, &mut params);
        }
    }
    Ok((params, None))
}

fn merge_query(q: &str, params: &mut Value) {
    let Some(obj) = params.as_object_mut() else {
        return;
    };
    for pair in q.split('&') {
        let Some((k, v)) = pair.split_once('=') else {
            continue;
        };
        obj.insert(k.to_string(), Value::String(urlencoding_light(v)));
    }
}

fn urlencoding_light(s: &str) -> String {
    s.replace('+', " ").replace("%20", " ")
}

fn merge_body(body: &Value, params: &mut Value) {
    let Some(obj) = params.as_object_mut() else {
        return;
    };
    if let Some(b) = body.as_object() {
        for (k, v) in b {
            obj.insert(k.clone(), v.clone());
        }
    }
}

fn dispatch_rpc(
    state: &RestState,
    rpc_method: &str,
    params: Value,
    _status_override: Option<StatusCode>,
) -> Result<(StatusCode, Value), (StatusCode, &'static str, String)> {
    let req = Request {
        jsonrpc: "2.0".into(),
        method: rpc_method.into(),
        params,
        id: Some(1.into()),
    };
    let mut ctx = DispatchContext::rest();
    let outcome = state.app.dispatch(req, &mut ctx);
    let resp = match outcome {
        DispatchOutcome::Reply(r) => r,
        DispatchOutcome::ShutdownRequested(r) => r,
    };
    if let Some(err) = resp.error {
        let status = map_rpc_http_status(err.code, &err.message);
        return Err((status, "KUMA_RPC_ERROR", err.message));
    }
    let body = resp.result.unwrap_or(json!({}));
    let status = if rpc_method == "daemon.shutdown" {
        StatusCode::ACCEPTED
    } else {
        StatusCode::OK
    };
    Ok((status, body))
}

async fn events_sse(state: RestState, headers: &HeaderMap) -> Response {
    let token = read_token_file(&state.token_path);
    if !authorized(headers, &token) {
        return rest_error(
            StatusCode::UNAUTHORIZED,
            "KUMA_SEC_UNAUTHORIZED",
            "Unauthorized",
        )
        .into_response();
    }
    let outcome = dispatch_rpc(&state, "events.subscribe", json!({ "topics": ["*"] }), None);
    let initial = match outcome {
        Ok((_, v)) => serde_json::to_string(&v).unwrap_or_else(|_| "{}".to_string()),
        Err((_, _, m)) => json!({ "error": m }).to_string(),
    };
    let epoch = state.app.rest_token_epoch();
    let app = Arc::clone(&state.app);
    let rx = state.app.store().events().live_subscribe();
    let live = stream::unfold((rx, epoch), move |(rx, epoch)| {
        let app = Arc::clone(&app);
        async move {
            if app.rest_token_epoch() != epoch {
                return None;
            }
            tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            loop {
                if app.rest_token_epoch() != epoch {
                    return None;
                }
                match rx.try_recv() {
                    Ok(line) => {
                        return Some((
                            Ok::<_, Infallible>(Event::default().data(line)),
                            (rx, epoch),
                        ));
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => {
                        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => return None,
                }
            }
        }
    });
    let stream = stream::once(async move { Ok(Event::default().data(initial)) }).chain(live);
    Sse::new(stream)
        .keep_alive(axum::response::sse::KeepAlive::default())
        .into_response()
}

async fn logs_sse(
    state: RestState,
    caps: std::collections::HashMap<String, String>,
    headers: &HeaderMap,
) -> Response {
    let token = read_token_file(&state.token_path);
    if !authorized(headers, &token) {
        return rest_error(
            StatusCode::UNAUTHORIZED,
            "KUMA_SEC_UNAUTHORIZED",
            "Unauthorized",
        )
        .into_response();
    }
    let sid = caps.get("serviceId").cloned().unwrap_or_default();
    if sid.is_empty() {
        return rest_error(
            StatusCode::BAD_REQUEST,
            "KUMA_BAD_REQUEST",
            "missing service id",
        )
        .into_response();
    }
    let initial = serde_json::to_string(&state.app.store().logs().follow_snapshot(&sid))
        .unwrap_or_else(|_| "{}".into());
    let epoch = state.app.rest_token_epoch();
    let app = Arc::clone(&state.app);
    let rx = state.app.store().logs().subscribe(&sid);
    let live = stream::unfold((rx, epoch), move |(rx, epoch)| {
        let app = Arc::clone(&app);
        async move {
            if app.rest_token_epoch() != epoch {
                return None;
            }
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            loop {
                if app.rest_token_epoch() != epoch {
                    return None;
                }
                match rx.try_recv() {
                    Ok(line) => {
                        return Some((
                            Ok::<_, Infallible>(Event::default().data(line)),
                            (rx, epoch),
                        ));
                    }
                    Err(std::sync::mpsc::TryRecvError::Empty) => {
                        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                    }
                    Err(std::sync::mpsc::TryRecvError::Disconnected) => return None,
                }
            }
        }
    });
    let stream = stream::once(async move { Ok(Event::default().data(initial)) }).chain(live);
    Sse::new(stream)
        .keep_alive(axum::response::sse::KeepAlive::default())
        .into_response()
}

async fn workspace_image_png(
    state: RestState,
    caps: std::collections::HashMap<String, String>,
) -> Response {
    let wid = caps.get("workspaceId").cloned().unwrap_or_default();
    if wid.is_empty() {
        return rest_error(
            StatusCode::BAD_REQUEST,
            "KUMA_BAD_REQUEST",
            "missing workspace id",
        )
        .into_response();
    }
    let outcome = dispatch_rpc(&state, "workspace.get_image", json!({ "id": wid }), None);
    let (_, body) = match outcome {
        Ok(v) => v,
        Err((status, code, msg)) => return rest_error(status, code, &msg).into_response(),
    };
    let has = body
        .get("hasImage")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if !has {
        return rest_error(
            StatusCode::NOT_FOUND,
            "KUMA_NOT_FOUND",
            "no workspace image",
        )
        .into_response();
    }
    let Some(b64) = body.get("imageBase64").and_then(|v| v.as_str()) else {
        return rest_error(
            StatusCode::NOT_FOUND,
            "KUMA_NOT_FOUND",
            "no workspace image",
        )
        .into_response();
    };
    let bytes = match base64::Engine::decode(&base64::engine::general_purpose::STANDARD, b64) {
        Ok(b) => b,
        Err(_) => {
            return rest_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                "KUMA_IMAGE",
                "decode failed",
            )
            .into_response();
        }
    };
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, "image/png")
        .body(Body::from(bytes))
        .unwrap_or_else(|_| {
            rest_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                "KUMA_IMAGE",
                "response build failed",
            )
            .into_response()
        })
}

async fn jsonrpc(
    State(state): State<RestState>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> Result<Json<JsonRpcResponse>, StatusCode> {
    let token = read_token_file(&state.token_path);
    if !authorized(&headers, &token) {
        return Err(StatusCode::UNAUTHORIZED);
    }
    let req = Request {
        jsonrpc: body
            .get("jsonrpc")
            .and_then(|v| v.as_str())
            .unwrap_or("2.0")
            .to_string(),
        method: body
            .get("method")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        params: body.get("params").cloned().unwrap_or(json!({})),
        id: body.get("id").cloned(),
    };
    let mut ctx = DispatchContext::rest();
    let outcome = state.app.dispatch(req, &mut ctx);
    let resp = match outcome {
        DispatchOutcome::Reply(r) => r,
        DispatchOutcome::ShutdownRequested(r) => r,
    };
    Ok(Json(resp))
}

fn rest_error(status: StatusCode, code: &str, message: &str) -> impl IntoResponse {
    (
        status,
        Json(json!({
            "error": { "code": code, "message": message }
        })),
    )
}

fn read_token_file(path: &Path) -> String {
    std::fs::read_to_string(path)
        .unwrap_or_default()
        .trim()
        .to_string()
}

pub fn authorized(headers: &HeaderMap, token: &str) -> bool {
    if token.is_empty() {
        return false;
    }
    let Some(v) = headers.get(header::AUTHORIZATION) else {
        return false;
    };
    let Ok(s) = v.to_str() else {
        return false;
    };
    let Some(bearer) = s
        .strip_prefix("Bearer ")
        .or_else(|| s.strip_prefix("bearer "))
    else {
        return false;
    };
    bearer.trim().as_bytes().ct_eq(token.as_bytes()).into()
}

fn reject_host(headers: &HeaderMap) -> bool {
    headers.get(header::HOST).is_some_and(|h| {
        h.to_str()
            .map(|s| !s.starts_with("127.0.0.1") && !s.starts_with("localhost"))
            .unwrap_or(true)
    })
}

fn reject_origin(headers: &HeaderMap) -> bool {
    headers.get(header::ORIGIN).is_some()
}

fn reject_reveal(req: &AxumRequest) -> bool {
    req.uri()
        .query()
        .is_some_and(|q| q.contains("revealSecrets"))
}

fn map_rpc_http_status(code: i32, message: &str) -> StatusCode {
    if message.contains("KUMA_CONFLICT") || message.contains("Stale") {
        return StatusCode::CONFLICT;
    }
    if message.contains("NOT_FOUND") || message.contains("not found") {
        return StatusCode::NOT_FOUND;
    }
    if code == ERR_KUMA {
        StatusCode::UNPROCESSABLE_ENTITY
    } else {
        StatusCode::INTERNAL_SERVER_ERROR
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use kuma_application::{Application, DataCounts, LifecycleState};
    use kuma_exec::ExecEngine;
    use kuma_store::{ensure_api_token, StoreHandle};
    use std::sync::Arc;
    use tower::ServiceExt;

    fn test_app(dir: &std::path::Path) -> (Arc<Application>, String) {
        let missing = dir.join("no-legacy.plist");
        std::env::set_var("KUMA_LEGACY_DEFAULTS_PLIST", missing.to_str().unwrap());
        ensure_api_token(dir).unwrap();
        let store = Arc::new(StoreHandle::open(dir).unwrap());
        std::env::remove_var("KUMA_LEGACY_DEFAULTS_PLIST");
        let app = Arc::new(Application::new(
            store,
            ExecEngine::new(),
            Arc::new(|| {}),
            LifecycleState::new("0.1.0", "00000000-0000-4000-8000-000000000099".into()),
            DataCounts::empty(),
        ));
        let token = read_token_file(&api_token_path(dir));
        (app, token)
    }

    #[test]
    fn rest_auth_and_merge_helpers() {
        let mut headers = HeaderMap::new();
        assert!(!authorized(&headers, "secret"));
        headers.insert(
            header::AUTHORIZATION,
            HeaderValue::from_static("Bearer secret"),
        );
        assert!(authorized(&headers, "secret"));
        assert!(reject_host(&HeaderMap::new()) == false);
        headers.insert(header::HOST, HeaderValue::from_static("evil.test"));
        assert!(reject_host(&headers));
        let mut params = json!({});
        merge_query("foo=bar&x=y", &mut params);
        assert_eq!(params["foo"], "bar");
        merge_body(&json!({"a": 1}), &mut params);
        assert_eq!(params["a"], 1);
        assert_eq!(
            map_rpc_http_status(ERR_KUMA, "KUMA_CONFLICT"),
            StatusCode::CONFLICT
        );
    }

    #[tokio::test]
    async fn rest_get_routes_smoke() {
        let dir = tempfile::tempdir().unwrap();
        let (app, token) = test_app(dir.path());
        let state = RestState {
            app,
            token_path: api_token_path(dir.path()),
        };
        let router = build_router(state);
        let auth = format!("Bearer {token}");
        let paths = [
            "/v1/daemon/ping",
            "/v1/daemon/status",
            "/v1/settings",
            "/v1/workspaces",
        ];
        for path in paths {
            let req = Request::builder()
                .method(Method::GET)
                .uri(path)
                .header(header::AUTHORIZATION, auth.clone())
                .body(Body::empty())
                .unwrap();
            let resp = router.clone().oneshot(req).await.unwrap();
            assert!(
                resp.status().is_success() || resp.status() == StatusCode::NOT_FOUND,
                "{path} status {}",
                resp.status()
            );
        }
    }

    #[tokio::test]
    async fn rest_all_registered_get_routes() {
        let dir = tempfile::tempdir().unwrap();
        let (app, token) = test_app(dir.path());
        let ws = app.store().workspace().list().unwrap()[0]["id"]
            .as_str()
            .unwrap()
            .to_string();
        let mut create = serde_json::Map::new();
        create.insert("workspaceID".into(), json!(ws));
        create.insert("name".into(), json!("rest-m"));
        let svc = app.store().service().create(&create).unwrap();
        let sid = svc["id"].as_str().unwrap();
        let plist = app.store().provider().list(sid).unwrap();
        let pid = plist["providers"][0]["id"].as_str().unwrap();
        let kid = kuma_store::kubeconfig::DEFAULT_ID;

        let state = RestState {
            app,
            token_path: api_token_path(dir.path()),
        };
        let router = build_router(state);
        let auth = format!("Bearer {token}");

        for route in crate::rest_registry::load_routes() {
            if route.method != Method::GET {
                continue;
            }
            if route.path.contains("stream") || route.path.contains("image") {
                continue;
            }
            let path = route
                .path
                .replace(":workspaceId", &ws)
                .replace(":serviceId", sid)
                .replace(":providerId", pid)
                .replace(":kubeconfigId", kid)
                .replace(":groupId", "00000000-0000-4000-8000-000000009999")
                .replace(":key", "autoResume")
                .replace(":subscriptionId", "0");
            let uri = format!("/v1{path}");
            let req = Request::builder()
                .method(Method::GET)
                .uri(&uri)
                .header(header::AUTHORIZATION, auth.clone())
                .body(Body::empty())
                .unwrap();
            let resp = router.clone().oneshot(req).await.unwrap();
            assert!(
                resp.status() != StatusCode::UNAUTHORIZED,
                "unauthorized on {uri}"
            );
        }
    }

    #[tokio::test]
    async fn rest_security_gates() {
        let dir = tempfile::tempdir().unwrap();
        let (app, token) = test_app(dir.path());
        let state = RestState {
            app,
            token_path: api_token_path(dir.path()),
        };
        let router = build_router(state);
        let req = Request::builder()
            .method(Method::GET)
            .uri("/v1/settings")
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            router.clone().oneshot(req).await.unwrap().status(),
            StatusCode::UNAUTHORIZED
        );
        let req = Request::builder()
            .method(Method::GET)
            .uri("/v1/settings")
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .header(header::ORIGIN, "https://evil.example")
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            router.clone().oneshot(req).await.unwrap().status(),
            StatusCode::FORBIDDEN
        );
        let req = Request::builder()
            .method(Method::GET)
            .uri("/v1/settings?revealSecrets=1")
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            router.clone().oneshot(req).await.unwrap().status(),
            StatusCode::FORBIDDEN
        );
        let req = Request::builder()
            .method(Method::GET)
            .uri("/v1/settings")
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .header(header::HOST, "evil.example")
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            router.oneshot(req).await.unwrap().status(),
            StatusCode::FORBIDDEN
        );
    }

    #[tokio::test]
    async fn rest_mutating_routes_smoke() {
        let dir = tempfile::tempdir().unwrap();
        let (app, token) = test_app(dir.path());
        let state = RestState {
            app,
            token_path: api_token_path(dir.path()),
        };
        let router = build_router(state);
        let auth = format!("Bearer {token}");
        let body = json!({ "name": "rest-ws-x" });
        let req = Request::builder()
            .method(Method::POST)
            .uri("/v1/workspaces")
            .header(header::AUTHORIZATION, auth.clone())
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(serde_json::to_vec(&body).unwrap()))
            .unwrap();
        let resp = router.oneshot(req).await.unwrap();
        assert!(resp.status().is_success() || resp.status() == StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn rest_jsonrpc_post() {
        let dir = tempfile::tempdir().unwrap();
        let (app, token) = test_app(dir.path());
        let state = RestState {
            app,
            token_path: api_token_path(dir.path()),
        };
        let router = build_router(state);
        let body = Body::from(
            serde_json::to_vec(&json!({
                "jsonrpc": "2.0",
                "method": "daemon.ping",
                "params": { "clientKind": "rest" },
                "id": 1
            }))
            .unwrap(),
        );
        let req = Request::builder()
            .method(Method::POST)
            .uri("/v1/jsonrpc")
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .header(header::CONTENT_TYPE, "application/json")
            .body(body)
            .unwrap();
        let resp = router.oneshot(req).await.unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[tokio::test]
    async fn rest_events_sse_initial_chunk() {
        let dir = tempfile::tempdir().unwrap();
        let (app, token) = test_app(dir.path());
        let state = RestState {
            app,
            token_path: api_token_path(dir.path()),
        };
        let router = build_router(state);
        let req = Request::builder()
            .method(Method::GET)
            .uri("/v1/events/stream")
            .header(header::AUTHORIZATION, format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap();
        let resp = tokio::time::timeout(std::time::Duration::from_secs(3), router.oneshot(req))
            .await
            .expect("sse timeout")
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let mut body = resp.into_body();
        let frame = tokio::time::timeout(std::time::Duration::from_secs(2), body.frame())
            .await
            .expect("first frame timeout")
            .expect("frame");
        assert!(frame.is_ok());
    }
}
