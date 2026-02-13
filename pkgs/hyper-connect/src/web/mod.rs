//! Web portal using Leptos SSR + Axum

mod assets;
mod components;
mod routes;

use crate::controller::{AppState, WifiState};
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Router,
};
use std::sync::Arc;
use tokio::sync::watch;

/// Run the web server
pub async fn run_server(
    state: Arc<AppState>,
    _state_rx: watch::Receiver<WifiState>,
) -> anyhow::Result<()> {
    let app = Router::new()
        // Main portal page
        .route("/", get(routes::index))
        // API endpoints
        .route("/api/status", get(routes::api_status))
        .route("/api/connect", post(routes::api_connect))
        .route("/api/scan", post(routes::api_scan))
        .route("/api/backend", post(routes::api_backend))
        // Captive portal detection endpoints
        .route("/generate_204", get(captive_check))
        .route("/hotspot-detect.html", get(captive_redirect))
        .route("/connecttest.txt", get(captive_redirect))
        .route("/ncsi.txt", get(captive_redirect))
        // Static assets
        .route("/style.css", get(assets::serve_css))
        // Fallback - redirect everything to portal
        .fallback(get(captive_redirect))
        .with_state(state.clone());

    let addr = format!("0.0.0.0:{}", state.config.port);
    tracing::info!(addr = %addr, "Starting web portal");

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

/// Captive portal check - return 204 when connected, redirect when not
async fn captive_check(State(state): State<Arc<AppState>>) -> Response {
    let wifi_state = state.wifi_state.read().await;

    if matches!(
        wifi_state.status,
        crate::controller::ConnectionStatus::Connected
    ) {
        StatusCode::NO_CONTENT.into_response()
    } else {
        // Redirect to portal
        (
            StatusCode::FOUND,
            [("Location", format!("http://{}/", state.config.ap_ip))],
        )
            .into_response()
    }
}

/// Redirect to portal
async fn captive_redirect(State(state): State<Arc<AppState>>) -> Response {
    (
        StatusCode::FOUND,
        [("Location", format!("http://{}/", state.config.ap_ip))],
    )
        .into_response()
}
