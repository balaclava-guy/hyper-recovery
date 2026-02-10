//! Shared state types for WiFi controller

use serde::{Deserialize, Serialize};
use std::time::Instant;

/// Current connection status
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub enum ConnectionStatus {
    #[default]
    Initializing,
    Scanning,
    AwaitingCredentials,
    Connecting,
    Connected,
    Failed,
    Disconnected,
}

/// Information about a discovered WiFi network
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInfo {
    pub ssid: String,
    pub bssid: String,
    pub signal_strength: u8, // 0-100
    pub frequency: u32,      // MHz
    pub channel: u8,
    pub is_secured: bool,
    pub security_type: String, // "WPA2", "WPA3", "WEP", "Open"
}

/// Complete WiFi state
#[derive(Debug, Clone, Default)]
pub struct WifiState {
    pub status: ConnectionStatus,
    pub available_networks: Vec<NetworkInfo>,
    pub connected_ssid: Option<String>,
    pub connecting_to: Option<String>,
    pub ap_running: bool,
    pub ap_ssid: Option<String>,
    pub portal_url: Option<String>,
    pub last_error: Option<String>,
    pub last_scan: Option<Instant>,
}

/// Serializable version of WifiState (for IPC/web)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WifiStateSnapshot {
    pub status: ConnectionStatus,
    pub available_networks: Vec<NetworkInfo>,
    pub connected_ssid: Option<String>,
    pub connecting_to: Option<String>,
    pub ap_running: bool,
    pub ap_ssid: Option<String>,
    pub portal_url: Option<String>,
    pub last_error: Option<String>,
    pub last_scan_secs_ago: Option<u64>,
}

impl From<&WifiState> for WifiStateSnapshot {
    fn from(state: &WifiState) -> Self {
        Self {
            status: state.status.clone(),
            available_networks: state.available_networks.clone(),
            connected_ssid: state.connected_ssid.clone(),
            connecting_to: state.connecting_to.clone(),
            ap_running: state.ap_running,
            ap_ssid: state.ap_ssid.clone(),
            portal_url: state.portal_url.clone(),
            last_error: state.last_error.clone(),
            last_scan_secs_ago: state.last_scan.map(|t| t.elapsed().as_secs()),
        }
    }
}
