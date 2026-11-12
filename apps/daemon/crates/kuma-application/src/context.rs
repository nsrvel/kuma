#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ClientKind {
    #[default]
    Cli,
    App,
    Mcp,
    Rest,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    Unix,
    Rest,
}

#[derive(Debug, Clone, Copy)]
pub struct DispatchContext {
    pub transport: Transport,
    pub client_kind: ClientKind,
}

impl DispatchContext {
    pub fn unix(client_kind: ClientKind) -> Self {
        Self {
            transport: Transport::Unix,
            client_kind,
        }
    }

    pub fn rest() -> Self {
        Self {
            transport: Transport::Rest,
            client_kind: ClientKind::Rest,
        }
    }

    pub fn reveal_allowed(&self) -> bool {
        self.transport == Transport::Unix
            && matches!(self.client_kind, ClientKind::Cli | ClientKind::App)
    }

    pub fn transport_str(&self) -> &'static str {
        match self.transport {
            Transport::Unix => "unix",
            Transport::Rest => "rest",
        }
    }

    pub fn client_kind_str(&self) -> &'static str {
        self.client_kind.as_str()
    }
}

impl ClientKind {
    pub fn parse(s: &str) -> Option<Self> {
        match s.trim().to_ascii_lowercase().as_str() {
            "cli" => Some(Self::Cli),
            "app" => Some(Self::App),
            "mcp" => Some(Self::Mcp),
            "rest" => Some(Self::Rest),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Cli => "cli",
            Self::App => "app",
            Self::Mcp => "mcp",
            Self::Rest => "rest",
        }
    }
}

pub fn apply_client_kind(current: &mut ClientKind, requested: ClientKind) {
    match (*current, requested) {
        (ClientKind::Mcp, ClientKind::Cli | ClientKind::App) => {}
        (ClientKind::Rest, ClientKind::Cli | ClientKind::App) => {}
        _ => *current = requested,
    }
}

pub fn params_want_reveal(params: &serde_json::Value) -> bool {
    params
        .get("revealSecrets")
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}
