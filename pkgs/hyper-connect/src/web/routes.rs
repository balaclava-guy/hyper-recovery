//! Web routes and handlers

use super::components;
use crate::controller::{AppState, ControlCommand, WifiStateSnapshot};
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
