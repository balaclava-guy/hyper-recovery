//! Web routes and handlers

use super::components;
use crate::controller::{AppState, ControlCommand, WifiBackend, WifiStateSnapshot};
use axum::{
    extract::State,
    response::{Html, IntoResponse},
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Main portal page (SSR)
pub async fn index(State(state): State<Arc<AppState>>) -> Html<String> {
    let wifi_state = state.wifi_state.read().await;
    let snapshot = WifiStateSnapshot::from(&*wifi_state);

    Html(components::render_portal_page(&snapshot))
}

/// API: Get current status
pub async fn api_status(State(state): State<Arc<AppState>>) -> Json<WifiStateSnapshot> {
    let wifi_state = state.wifi_state.read().await;
    Json(WifiStateSnapshot::from(&*wifi_state))
}

#[derive(Debug, Deserialize)]
pub struct ConnectRequest {
    ssid: String,
    password: String,
    #[serde(default = "default_save")]
    save: bool,
}

fn default_save() -> bool {
    true
}

#[derive(Debug, Serialize)]
pub struct ApiResponse {
    success: bool,
    message: String,
}

#[derive(Debug, Deserialize)]
pub struct BackendRequest {
    backend: WifiBackend,
}

/// API: Connect to network
pub async fn api_connect(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ConnectRequest>,
) -> impl IntoResponse {
    let result = state
        .command_tx
        .send(ControlCommand::Connect {
            ssid: req.ssid.clone(),
            password: req.password,
            save: req.save,
        })
        .await;

    match result {
        Ok(()) => Json(ApiResponse {
            success: true,
            message: format!("Connecting to {}...", req.ssid),
        }),
        Err(e) => Json(ApiResponse {
            success: false,
            message: format!("Failed to send command: {}", e),
        }),
    }
}

/// API: Trigger rescan
pub async fn api_scan(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let result = state.command_tx.send(ControlCommand::Scan).await;

    match result {
        Ok(()) => Json(ApiResponse {
            success: true,
            message: "Scan initiated".to_string(),
        }),
        Err(e) => Json(ApiResponse {
            success: false,
            message: format!("Failed to send command: {}", e),
        }),
    }
}

/// API: Switch NetworkManager WiFi backend (iwd / wpa_supplicant)
///
/// NOTE: This is a troubleshooting escape hatch for the captive portal.
/// If/when a general API Gateway exists for Hyper Recovery system control,
/// this endpoint should likely move there (with auth, auditing, and a more
/// general network/host control surface).
pub async fn api_backend(
    State(state): State<Arc<AppState>>,
    Json(req): Json<BackendRequest>,
) -> impl IntoResponse {
    let result = state
        .command_tx
        .send(ControlCommand::SwitchBackend {
            backend: req.backend,
        })
        .await;

    match result {
        Ok(()) => Json(ApiResponse {
            success: true,
            message: format!(
                "Switching WiFi backend to {}. The setup AP may restart; reconnect if needed.",
                req.backend.as_nm_value()
            ),
        }),
        Err(e) => Json(ApiResponse {
            success: false,
            message: format!("Failed to send backend switch command: {}", e),
        }),
    }
}
