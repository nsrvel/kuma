mod launchagent;
mod mcp;

use anyhow::Result;
use clap::{Parser, Subcommand};
use kuma_protocol::methods;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "kuma", about = "Kuma local dev services daemon and tools")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Daemon lifecycle (LaunchAgent, foreground server).
    Daemon {
        #[command(subcommand)]
        command: DaemonCommands,
    },
    /// MCP stdio bridge to the running daemon.
    Mcp,
    /// Call one JSON-RPC method on the running daemon.
    Call {
        #[arg(long)]
        method: String,
        #[arg(long, default_value = "{}")]
        params: String,
    },
    /// Thin RPC helpers (spec 11 subset).
    Workspace {
        #[command(subcommand)]
        command: WorkspaceCommands,
    },
    Service {
        #[command(subcommand)]
        command: ServiceCommands,
    },
    Kubeconfig {
        #[command(subcommand)]
        command: KubeconfigCommands,
    },
    Runtime {
        #[command(subcommand)]
        command: RuntimeCommands,
    },
}

#[derive(Subcommand)]
enum WorkspaceCommands {
    List,
    GetImage {
        #[arg(long)]
        id: String,
    },
}

#[derive(Subcommand)]
enum KubeconfigCommands {
    List,
}

#[derive(Subcommand)]
enum ServiceCommands {
    Start {
        #[arg(long)]
        id: String,
    },
    Stop {
        #[arg(long)]
        id: String,
    },
    Preflight {
        #[arg(long)]
        id: String,
    },
}

#[derive(Subcommand)]
enum RuntimeCommands {
    AdoptReport,
}

#[derive(Subcommand)]
enum DaemonCommands {
    /// Run the daemon in the foreground (also used by LaunchAgent).
    Run,
    /// Install user LaunchAgent plist and load via launchctl.
    Install,
    /// Unload and remove user LaunchAgent plist.
    Uninstall,
    /// Rotate REST bearer token (Unix socket only).
    RotateApiToken,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive("kuma=info".parse()?))
        .init();

    match Cli::parse().command {
        Commands::Daemon { command } => match command {
            DaemonCommands::Run => kuma_daemon::run().await?,
            DaemonCommands::Install => launchagent::install()?,
            DaemonCommands::Uninstall => launchagent::uninstall()?,
            DaemonCommands::RotateApiToken => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(methods::DAEMON_ROTATE_API_TOKEN, serde_json::json!({}))
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
        },
        Commands::Mcp => mcp::run_stdio_mcp().await?,
        Commands::Workspace { command } => match command {
            WorkspaceCommands::List => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(
                        kuma_protocol::methods::WORKSPACE_LIST,
                        serde_json::json!({}),
                    )
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
            WorkspaceCommands::GetImage { id } => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(
                        kuma_protocol::methods::WORKSPACE_GET_IMAGE,
                        serde_json::json!({ "id": id }),
                    )
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
        },
        Commands::Kubeconfig { command } => match command {
            KubeconfigCommands::List => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(
                        kuma_protocol::methods::KUBECONFIG_LIST,
                        serde_json::json!({}),
                    )
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
        },
        Commands::Service { command } => match command {
            ServiceCommands::Start { id } => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(
                        kuma_protocol::methods::SERVICE_START,
                        serde_json::json!({ "id": id }),
                    )
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
            ServiceCommands::Stop { id } => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(
                        kuma_protocol::methods::SERVICE_STOP,
                        serde_json::json!({ "id": id }),
                    )
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
            ServiceCommands::Preflight { id } => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(
                        kuma_protocol::methods::SERVICE_PREFLIGHT,
                        serde_json::json!({ "id": id }),
                    )
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
        },
        Commands::Runtime { command } => match command {
            RuntimeCommands::AdoptReport => {
                let mut client = kuma_client::DaemonClient::connect_default().await?;
                let v = client
                    .call(methods::RUNTIME_ADOPT_REPORT, serde_json::json!({}))
                    .await?;
                println!("{}", serde_json::to_string_pretty(&v)?);
            }
        },
        Commands::Call { method, params } => {
            let params: serde_json::Value = serde_json::from_str(&params)?;
            let mut client = kuma_client::DaemonClient::connect_default().await?;
            let v = client.call(&method, params).await?;
            println!("{}", serde_json::to_string_pretty(&v)?);
        }
    }

    Ok(())
}
