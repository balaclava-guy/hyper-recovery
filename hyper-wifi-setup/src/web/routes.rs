//! Web routes and handlers

use crate::controller::{AppState, ControlCommand, WifiStateSnapshot};
use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse},
    Json,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Main portal page (SSR)
pub async fn index(State(state): State<Arc<AppState>>) -> Html<String> {
    let wifi_state = state.wifi_state.read().await;
    let snapshot = WifiStateSnapshot::from(&*wifi_state);
    
    Html(render_portal_page(&snapshot, &state.config.ap_ip))
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

/// Render the portal page HTML
fn render_portal_page(state: &WifiStateSnapshot, ap_ip: &str) -> String {
    let networks_html: String = state
        .available_networks
        .iter()
        .map(|n| {
            let lock_icon = if n.is_secured { "🔒" } else { "🔓" };
            let signal_bars = signal_to_bars(n.signal_strength);
            let security_badge = if n.is_secured {
                format!(r#"<span class="badge">{}</span>"#, n.security_type)
            } else {
                r#"<span class="badge open">Open</span>"#.to_string()
            };
            
            format!(
                r#"
                <button class="network-card" onclick="selectNetwork('{}', {})">
                    <div class="network-info">
                        <span class="lock-icon">{}</span>
                        <div class="network-details">
                            <span class="ssid">{}</span>
                            <span class="meta">CH {} {}</span>
                        </div>
                    </div>
                    <div class="signal">
                        {}
                        <span class="signal-pct">{}%</span>
                    </div>
                </button>
                "#,
                html_escape(&n.ssid),
                n.is_secured,
                lock_icon,
                html_escape(&n.ssid),
                n.channel,
                security_badge,
                signal_bars,
                n.signal_strength,
            )
        })
        .collect();

    let status_class = match state.status {
        crate::controller::ConnectionStatus::Connected => "status-connected",
        crate::controller::ConnectionStatus::Connecting => "status-connecting",
        crate::controller::ConnectionStatus::Failed => "status-failed",
        _ => "status-waiting",
    };

    let status_text = match &state.status {
        crate::controller::ConnectionStatus::Connected => {
            format!("Connected to {}", state.connected_ssid.as_deref().unwrap_or("network"))
        }
        crate::controller::ConnectionStatus::Connecting => {
            format!("Connecting to {}...", state.connecting_to.as_deref().unwrap_or("network"))
        }
        crate::controller::ConnectionStatus::Failed => {
            format!("Failed: {}", state.last_error.as_deref().unwrap_or("Unknown error"))
        }
        _ => "Select a network to connect".to_string(),
    };

    format!(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Hyper Recovery - WiFi Setup</title>
    <link rel="stylesheet" href="/style.css">
</head>
<body>
    <div class="container">
        <header class="header">
            <h1 class="title">HYPER RECOVERY</h1>
            <p class="subtitle">WIFI SETUP MODULE</p>
        </header>

        <div id="status" class="status-bar {status_class}">
            <span id="status-text">{status_text}</span>
        </div>

        <main class="network-list" id="network-list">
            {networks_html}
        </main>

        <button class="manual-btn" onclick="showManualEntry()">
            Enter Network Manually
        </button>
    </div>

    <!-- Password Modal -->
    <div id="password-modal" class="modal hidden">
        <div class="modal-content">
            <h2>Enter Password</h2>
            <p id="modal-ssid"></p>
            <form id="connect-form" onsubmit="submitConnect(event)">
                <div class="input-group">
                    <input type="password" id="password-input" placeholder="Password" required minlength="8">
                    <button type="button" class="toggle-password" onclick="togglePassword()">👁️</button>
                </div>
                <div class="modal-actions">
                    <button type="button" class="btn-cancel" onclick="hideModal()">Cancel</button>
                    <button type="submit" class="btn-connect">Connect</button>
                </div>
            </form>
        </div>
    </div>

    <!-- Manual SSID Modal -->
    <div id="manual-modal" class="modal hidden">
        <div class="modal-content">
            <h2>Manual Network Entry</h2>
            <form id="manual-form" onsubmit="submitManual(event)">
                <div class="input-group">
                    <input type="text" id="manual-ssid" placeholder="Network Name (SSID)" required>
                </div>
                <div class="input-group">
                    <input type="password" id="manual-password" placeholder="Password (leave empty for open)">
                    <button type="button" class="toggle-password" onclick="toggleManualPassword()">👁️</button>
                </div>
                <div class="modal-actions">
                    <button type="button" class="btn-cancel" onclick="hideManualModal()">Cancel</button>
                    <button type="submit" class="btn-connect">Connect</button>
                </div>
            </form>
        </div>
    </div>

    <script>
        let selectedSsid = '';
        let selectedSecured = false;

        function selectNetwork(ssid, secured) {{
            selectedSsid = ssid;
            selectedSecured = secured;
            
            if (secured) {{
                document.getElementById('modal-ssid').textContent = ssid;
                document.getElementById('password-input').value = '';
                document.getElementById('password-modal').classList.remove('hidden');
            }} else {{
                // Connect to open network directly
                connect(ssid, '');
            }}
        }}

        function hideModal() {{
            document.getElementById('password-modal').classList.add('hidden');
        }}

        function showManualEntry() {{
            document.getElementById('manual-ssid').value = '';
            document.getElementById('manual-password').value = '';
            document.getElementById('manual-modal').classList.remove('hidden');
        }}

        function hideManualModal() {{
            document.getElementById('manual-modal').classList.add('hidden');
        }}

        function togglePassword() {{
            const input = document.getElementById('password-input');
            input.type = input.type === 'password' ? 'text' : 'password';
        }}

        function toggleManualPassword() {{
            const input = document.getElementById('manual-password');
            input.type = input.type === 'password' ? 'text' : 'password';
        }}

        function submitConnect(e) {{
            e.preventDefault();
            const password = document.getElementById('password-input').value;
            connect(selectedSsid, password);
            hideModal();
        }}

        function submitManual(e) {{
            e.preventDefault();
            const ssid = document.getElementById('manual-ssid').value;
            const password = document.getElementById('manual-password').value;
            connect(ssid, password);
            hideManualModal();
        }}

        async function connect(ssid, password) {{
            updateStatus('Connecting to ' + ssid + '...', 'status-connecting');
            
            try {{
                const response = await fetch('/api/connect', {{
                    method: 'POST',
                    headers: {{ 'Content-Type': 'application/json' }},
                    body: JSON.stringify({{ ssid, password }})
                }});
                
                const data = await response.json();
                
                if (data.success) {{
                    updateStatus(data.message, 'status-connecting');
                    // Poll for status updates
                    pollStatus();
                }} else {{
                    updateStatus('Error: ' + data.message, 'status-failed');
                }}
            }} catch (err) {{
                updateStatus('Connection error: ' + err.message, 'status-failed');
            }}
        }}

        function updateStatus(text, className) {{
            const statusBar = document.getElementById('status');
            const statusText = document.getElementById('status-text');
            statusBar.className = 'status-bar ' + className;
            statusText.textContent = text;
        }}

        async function pollStatus() {{
            try {{
                const response = await fetch('/api/status');
                const data = await response.json();
                
                if (data.status === 'Connected') {{
                    updateStatus('Connected! You can close this page.', 'status-connected');
                }} else if (data.status === 'Failed') {{
                    updateStatus('Failed: ' + (data.last_error || 'Unknown error'), 'status-failed');
                }} else if (data.status === 'Connecting') {{
                    updateStatus('Connecting to ' + (data.connecting_to || 'network') + '...', 'status-connecting');
                    setTimeout(pollStatus, 1000);
                }}
            }} catch (err) {{
                // Portal might be down if we connected successfully
                updateStatus('Connection in progress...', 'status-connecting');
            }}
        }}

        // Auto-refresh network list every 30 seconds
        setInterval(() => {{
            if (!document.querySelector('.modal:not(.hidden)')) {{
                location.reload();
            }}
        }}, 30000);
    </script>
</body>
</html>"##,
        status_class = status_class,
        status_text = html_escape(&status_text),
        networks_html = networks_html,
    )
}

fn signal_to_bars(signal: u8) -> String {
    let bars = (signal as f32 / 25.0).ceil() as usize;
    (0..4)
        .map(|i| {
            let height = (i + 1) * 25;
            let filled = i < bars;
            format!(
                r#"<div class="bar{}" style="height: {}%"></div>"#,
                if filled { " filled" } else { "" },
                height
            )
        })
        .collect()
}

fn html_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}
