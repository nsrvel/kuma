//! Language-agnostic contract between `kuma` clients and the daemon.
//!
//! See `docs/specs/daemon/10-rpc-protocol.md`.

pub mod jsonrpc;
pub mod methods;
pub mod paths;

pub const PROTOCOL_VERSION: &str = "0.1";

/// Maximum NDJSON line size (spec 10 §2.4).
pub const MAX_NDJSON_LINE_BYTES: usize = 16 * 1024 * 1024;
