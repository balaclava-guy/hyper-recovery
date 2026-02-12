//! WiFi Controller - Core logic for AP management and network connection

mod ap_manager;
pub mod credentials;
pub mod ipc;
mod network_manager;
pub mod state;

pub use state::{ConnectionStatus, NetworkInfo, WifiState, WifiStateSnapshot};

use anyhow::Result;
use std::sync::Arc;
use tokio::net::UnixListener;
use tokio::signal;
use tokio::sync::{mpsc, watch, RwLock};

/// Daemon configuration
pub struct DaemonConfig {
    pub interface: String,
    pub ssid: String,
    pub ap_ip: String,
    pub port: u16,
    pub grace_period: u64,
}

/// Shared application state
pub struct AppState {
    pub wifi_state: RwLock<WifiState>,
    pub config: DaemonConfig,
    pub state_tx: watch::Sender<WifiState>,
    pub command_tx: mpsc::Sender<ControlCommand>,
}

/// Commands that can be sent to the controller
#[derive(Debug, Clone)]
pub enum ControlCommand {
    Scan,
    Connect {
        ssid: String,
        password: String,
        save: bool,
    },
    Shutdown,
}

/// Run the daemon
pub async fn run_daemon(config: DaemonConfig) -> Result<()> {
    let mut config = config;
    config.interface = network_manager::resolve_wireless_interface(&config.interface)?;
    config.ap_ip = network_manager::resolve_ap_ip(&config.ap_ip)?;

    tracing::info!(
        interface = %config.interface,
        ssid = %config.ssid,
        ap_ip = %config.ap_ip,
        "Initializing WiFi controller"
    );

    // Create state channels
    let (state_tx, state_rx) = watch::channel(WifiState::default());
    let (command_tx, mut command_rx) = mpsc::channel::<ControlCommand>(32);

    let app_state = Arc::new(AppState {
        wifi_state: RwLock::new(WifiState::default()),
        config,
        state_tx,
        command_tx: command_tx.clone(),
    });

    // Check for existing connectivity
    tracing::info!("Checking for existing network connectivity...");

    let has_connectivity = network_manager::check_connectivity().await?;
    if has_connectivity {
        tracing::info!("Already connected to network, exiting");
        return Ok(());
    }

    // Grace period - wait for Ethernet/existing WiFi
    tracing::info!(
        seconds = app_state.config.grace_period,
        "Waiting grace period for network..."
    );

    let grace_result = tokio::time::timeout(
        std::time::Duration::from_secs(app_state.config.grace_period),
        network_manager::wait_for_connectivity(),
    )
    .await;

    if grace_result.is_ok() {
        tracing::info!("Network connected during grace period, exiting");
        return Ok(());
    }

    // No connectivity - scan and check for saved credentials
    tracing::info!("No network connectivity, scanning for networks...");

    // Initial WiFi scan (before starting AP)
    {
        let mut state = app_state.wifi_state.write().await;
        state.status = ConnectionStatus::Scanning;
        let _ = app_state.state_tx.send(state.clone());
    }

    let networks = network_manager::scan_networks(&app_state.config.interface).await?;

    // Load saved credentials and check for known networks
    let creds_store = credentials::CredentialsStore::load().unwrap_or_default();

    if let Some(known_network) = creds_store.best_known_network(&networks) {
        if let Some(password) = creds_store.get_password(&known_network.ssid) {
            tracing::info!(
                ssid = %known_network.ssid,
                signal = known_network.signal_strength,
                "Found saved credentials for available network, attempting auto-connect"
            );

            // Try to connect with saved credentials
            match network_manager::connect_to_network(
                &app_state.config.interface,
                &known_network.ssid,
                password,
            )
            .await
            {
                Ok(()) => {
                    tracing::info!(ssid = %known_network.ssid, "Auto-connected using saved credentials");
                    return Ok(());
                }
                Err(e) => {
                    tracing::warn!(
                        ssid = %known_network.ssid,
                        error = %e,
                        "Auto-connect failed, will start AP"
                    );
                }
            }
        }
    }

    // Update state with scanned networks
    {
        let mut state = app_state.wifi_state.write().await;
        state.available_networks = networks;
        state.status = ConnectionStatus::AwaitingCredentials;
        state.last_scan = Some(std::time::Instant::now());
        let _ = app_state.state_tx.send(state.clone());
    }

    tracing::info!("Starting AP and portal");

    // Start AP
    let _ap_handle = ap_manager::start_ap(
        &app_state.config.interface,
        &app_state.config.ssid,
        &app_state.config.ap_ip,
    )
    .await?;

    {
        let mut state = app_state.wifi_state.write().await;
        state.ap_running = true;
        state.ap_ssid = Some(app_state.config.ssid.clone());
        state.portal_url = Some(format!("http://{}", app_state.config.ap_ip));
        let _ = app_state.state_tx.send(state.clone());
    }

    // Start IPC server
    let socket_path = "/run/hyper-wifi-setup.sock";
    let _ = std::fs::remove_file(socket_path);
    let listener = UnixListener::bind(socket_path)?;
    tracing::info!(path = socket_path, "IPC server listening");

    let ipc_state = app_state.clone();
    let ipc_handle = tokio::spawn(async move { ipc::run_ipc_server(listener, ipc_state).await });

    // Start web portal
    let web_state = app_state.clone();
    let web_state_rx = state_rx.clone();
    let web_handle =
        tokio::spawn(async move { crate::web::run_server(web_state, web_state_rx).await });

    // Main control loop
    let ctrl_state = app_state.clone();
    let control_handle = tokio::spawn(async move {
        loop {
            tokio::select! {
                Some(cmd) = command_rx.recv() => {
                    match cmd {
                        ControlCommand::Scan => {
                            tracing::info!("Rescan requested");
                            // Would need to stop AP briefly for rescan
                            // For now, just log
                        }
                        ControlCommand::Connect { ssid, password, save } => {
                            tracing::info!(ssid = %ssid, save = save, "Connection requested");

                            // Update state
                            {
                                let mut state = ctrl_state.wifi_state.write().await;
                                state.status = ConnectionStatus::Connecting;
                                state.connecting_to = Some(ssid.clone());
                                state.last_error = None;
                                let _ = ctrl_state.state_tx.send(state.clone());
                            }

                            // Give the portal a short window to render "connecting" before AP teardown.
                            tokio::time::sleep(std::time::Duration::from_millis(1200)).await;

                            // Stop AP
                            if let Err(e) = ap_manager::stop_ap().await {
                                tracing::warn!(error = %e, "Failed to stop AP cleanly");
                            }

                            // Attempt connection
                            match network_manager::connect_to_network(
                                &ctrl_state.config.interface,
                                &ssid,
                                &password,
                            ).await {
                                Ok(()) => {
                                    tracing::info!("Successfully connected to WiFi");

                                    // Save credentials if requested
                                    if save {
                                        let mut creds = credentials::CredentialsStore::load()
                                            .unwrap_or_default();
                                        creds.save_credential(&ssid, &password);
                                        if let Err(e) = creds.save() {
                                            tracing::warn!(error = %e, "Failed to save credentials");
                                        } else {
                                            tracing::info!(ssid = %ssid, "Saved WiFi credentials");
                                        }
                                    }

                                    let mut state = ctrl_state.wifi_state.write().await;
                                    state.status = ConnectionStatus::Connected;
                                    state.connected_ssid = Some(ssid);
                                    state.connecting_to = None;
                                    state.ap_running = false;
                                    let _ = ctrl_state.state_tx.send(state.clone());

                                    // Give time for DHCP, then exit
                                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                                    break;
                                }
                                Err(e) => {
                                    tracing::error!(error = %e, "Failed to connect");

                                    // Restart AP
                                    if let Err(e) = ap_manager::start_ap(
                                        &ctrl_state.config.interface,
                                        &ctrl_state.config.ssid,
                                        &ctrl_state.config.ap_ip,
                                    ).await {
                                        tracing::error!(error = %e, "Failed to restart AP");
                                    }

                                    let mut state = ctrl_state.wifi_state.write().await;
                                    state.status = ConnectionStatus::Failed;
                                    state.connecting_to = None;
                                    state.last_error = Some(e.to_string());
                                    state.ap_running = true;
                                    let _ = ctrl_state.state_tx.send(state.clone());
                                }
                            }
                        }
                        ControlCommand::Shutdown => {
                            tracing::info!("Shutdown requested");
                            break;
                        }
                    }
                }
                _ = signal::ctrl_c() => {
                    tracing::info!("Received SIGINT, shutting down");
                    break;
                }
            }
        }
    });

    // Wait for control loop to finish
    let _ = control_handle.await;

    // Cleanup
    tracing::info!("Cleaning up...");
    let _ = ap_manager::stop_ap().await;
    ipc_handle.abort();
    web_handle.abort();

    Ok(())
}

/// Print current status (for CLI)
pub async fn print_status(socket_path: &str) -> Result<()> {
    match ipc::get_status(socket_path).await {
        Ok(state) => {
            println!("WiFi Setup Status");
            println!("=================");
            println!("Status: {:?}", state.status);
            if let Some(ssid) = &state.connected_ssid {
                println!("Connected to: {}", ssid);
            }
            if state.ap_running {
                println!(
                    "AP Running: {} ({})",
                    state.ap_ssid.as_deref().unwrap_or("unknown"),
                    state.portal_url.as_deref().unwrap_or("unknown")
                );
            }
            println!("Available networks: {}", state.available_networks.len());
            for net in &state.available_networks {
                println!(
                    "  - {} ({}%, {})",
                    net.ssid,
                    net.signal_strength,
                    if net.is_secured { "secured" } else { "open" }
                );
            }
        }
        Err(e) => {
            eprintln!("Failed to get status: {}", e);
            eprintln!("Is the daemon running?");
        }
    }
    Ok(())
}
