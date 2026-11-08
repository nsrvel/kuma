# Kuma daemon (Rust)

V2 core: **`kuma`** CLI and background daemon. Clean-architecture workspace; Swift `Kuma/` untouched until parity.

**Spec:** [`docs/specs/daemon/`](../docs/specs/daemon/00-overview-and-conventions.md)  
**Overview:** [`docs/specs/07-kuma-daemon.md`](../docs/specs/07-kuma-daemon.md)

## Crates

| Crate | Role |
|-------|------|
| `kuma-domain` | Pure domain errors (no I/O) |
| `kuma-protocol` | NDJSON JSON-RPC, paths, 74 RPC method names |
| `kuma-application` | Use-case dispatch (daemon, settings, env, events, workspace, group, service/provider CRUD) |
| `kuma-client` | Unix socket NDJSON JSON-RPC client |
| `kuma-store` | `kuma.sqlite` migrations v1..v8, `daemon-state.sqlite`, settings KV, env PATH, event bus, WGS data stores |
| `kuma-daemon` | Unix socket adapter (peer UID, flock, shutdown) |
| `kuma-cli` | Binary `kuma` |

## Tests

`cargo test` uses [`daemon/.cargo/config.toml`](.cargo/config.toml) to set `KUMA_SKIP_PATH_SNIFF=1` so env PATH resolution does not spawn a login shell during tests.

## Build

```bash
cd daemon
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

### Line coverage (CI gate ≥90%)

CI (`.github/workflows/daemon-ci.yml`) installs `cargo-llvm-cov` with `llvm-tools-preview` and runs:

```bash
cargo llvm-cov --all --exclude kuma-cli --summary-only --fail-under-lines 90
```

Local (requires `rustup component add llvm-tools-preview` and `cargo install cargo-llvm-cov`):

```bash
cargo llvm-cov --all --exclude kuma-cli --html
```

## Run (dev)

```bash
KUMA_RUNTIME_DIR=/tmp/kuma-dev cargo run -p kuma-cli -- daemon run
```

Default socket: `~/Library/Application Support/Kuma/run/kuma-daemon.sock`  
Overrides: `KUMA_DATA_DIR`, `KUMA_RUNTIME_DIR`, `KUMA_LEGACY_DEFAULTS_PLIST` (ADD-09 plist path for tests / relocated 1.x prefs)

### Smoke test

```bash
printf '%s\n' '{"jsonrpc":"2.0","method":"daemon.ping","params":{},"id":1}' \
  | python3 -c "import socket,sys; p=sys.argv[1]; s=socket.socket(socket.AF_UNIX); s.connect(p); s.sendall(sys.stdin.buffer.read()); print(s.recv(4096).decode(), end='')" \
  "/tmp/kuma-dev/kuma-daemon.sock"
```

## Commands

| Command | Status |
|---------|--------|
| `kuma daemon run` | Storage open (S6), daemon/settings/env/events/workspace/group/service/provider CRUD RPCs; exec/logs/k8s still method-not-found |
| `kuma daemon install` | Planned |
| `kuma mcp` | After parity gate |
