mod launchagent;
mod mcp;

use anyhow::Result;
use clap::{Parser, Subcommand};
use kuma_protocol::methods;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "kuma", about = "Kuma local dev services background daemon and MCP server")]
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
    }

    Ok(())
}
