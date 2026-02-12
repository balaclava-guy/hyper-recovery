//! Hyper WiFi Setup - WiFi configuration daemon with TUI and captive portal
//!
//! This binary provides three modes:
//! - `daemon`: Runs the WiFi controller, AP, and web portal
//! - `tui`: Connects to the daemon and provides a terminal UI
//! - `status`: Quick status check (for scripts)

mod controller;
mod tui;
mod web;

use clap::{Parser, Subcommand};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

#[derive(Parser)]
#[command(name = "hyper-wifi-setup")]
#[command(about = "WiFi setup for Hyper Recovery", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the WiFi setup daemon (controller + web portal)
    Daemon {
        /// WiFi interface to use for AP
        #[arg(long, default_value = "auto")]
        interface: String,

        /// AP SSID
        #[arg(long, default_value = "HyperRecovery")]
        ssid: String,

        /// AP IP address
        #[arg(long, default_value = "auto")]
        ap_ip: String,

        /// Web portal port
        #[arg(long, default_value = "80")]
        port: u16,

        /// Grace period before starting AP (seconds)
        #[arg(long, default_value = "10")]
        grace_period: u64,
    },

    /// Run the TUI client (connects to daemon)
    Tui {
        /// Unix socket path for daemon communication
        #[arg(long, default_value = "/run/hyper-wifi-setup.sock")]
        socket: String,
    },

    /// Check current status
    Status {
        /// Unix socket path for daemon communication
        #[arg(long, default_value = "/run/hyper-wifi-setup.sock")]
        socket: String,
    },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(tracing_subscriber::fmt::layer())
        .init();

    let cli = Cli::parse();

    match cli.command {
        Commands::Daemon {
            interface,
            ssid,
            ap_ip,
            port,
            grace_period,
        } => {
            tracing::info!("Starting Hyper WiFi Setup daemon");
            controller::run_daemon(controller::DaemonConfig {
                interface,
                ssid,
                ap_ip,
                port,
                grace_period,
            })
            .await?;
        }
        Commands::Tui { socket } => {
            tracing::info!("Starting TUI client");
            tui::run_tui(&socket).await?;
        }
        Commands::Status { socket } => {
            controller::print_status(&socket).await?;
        }
    }

    Ok(())
}
