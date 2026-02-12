//! Leptos + shadcn component rendering for the captive portal.

use crate::controller::{ConnectionStatus, NetworkInfo, WifiStateSnapshot};
use leptos::prelude::*;
use leptos_shadcn_alert::{Alert, AlertDescription, AlertTitle, AlertVariant};
use leptos_shadcn_badge::{Badge, BadgeVariant};
use leptos_shadcn_button::{Button, ButtonSize, ButtonVariant};
use leptos_shadcn_card::{Card, CardContent, CardDescription, CardHeader, CardTitle};
use leptos_shadcn_input::Input;

const PORTAL_BEHAVIOR_JS: &str = r#"
(function () {
  var selectedSsid = '';

  function byId(id) {
    return document.getElementById(id);
  }

  function showModal(id) {
    byId(id).classList.remove('hidden');
  }

  function hideModal(id) {
    byId(id).classList.add('hidden');
  }

  function statusToneForState(status) {
    if (status === 'Connected') return 'connected';
    if (status === 'Connecting') return 'connecting';
    if (status === 'Failed') return 'failed';
    return 'waiting';
  }

  function updateStatus(text, tone, detail) {
    var status = byId('status');
    var title = byId('status-text');
    var description = byId('status-detail');

    status.setAttribute('data-state', tone);
    title.textContent = text;
    if (typeof detail === 'string' && detail.length > 0) {
      description.textContent = detail;
    }
  }

  async function connect(ssid, password, save) {
    updateStatus('Connecting to ' + ssid + '...', 'connecting', 'Attempting to join selected network.');

    try {
      var response = await fetch('/api/connect', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ssid: ssid, password: password, save: save })
      });

      var data = await response.json();

      if (data.success) {
        updateStatus(data.message, 'connecting', 'Waiting for connection result...');
        pollStatus();
      } else {
        updateStatus('Connection failed', 'failed', data.message);
      }
    } catch (err) {
      updateStatus('Connection error', 'failed', err.message || 'Unexpected network error.');
    }
  }

  async function pollStatus() {
    try {
      var response = await fetch('/api/status');
      var data = await response.json();
      var tone = statusToneForState(data.status);

      if (data.status === 'Connected') {
        updateStatus('Connected to ' + (data.connected_ssid || 'network'), tone, 'You can close this page now.');
        return;
      }

      if (data.status === 'Failed') {
        updateStatus('Connection failed', tone, data.last_error || 'Unknown error while connecting.');
        return;
      }

      if (data.status === 'Connecting') {
        updateStatus('Connecting to ' + (data.connecting_to || 'network') + '...', tone, 'Still negotiating with access point...');
        setTimeout(pollStatus, 1000);
      }
    } catch (_) {
      updateStatus('Connection in progress', 'connecting', 'Portal may restart while network comes up.');
    }
  }

  function bindNetworkRows() {
    var rows = document.querySelectorAll('.network-row');
    rows.forEach(function (row) {
      row.addEventListener('click', function () {
        var ssid = row.getAttribute('data-ssid') || '';
        var secured = row.getAttribute('data-secured') === 'true';
        selectedSsid = ssid;

        if (secured) {
          byId('modal-ssid').textContent = ssid;
          byId('password-input').value = '';
          byId('save-password').checked = true;
          showModal('password-modal');
        } else {
          connect(ssid, '', false);
        }
      });
    });
  }

  byId('manual-entry-btn').addEventListener('click', function () {
    byId('manual-ssid').value = '';
    byId('manual-password').value = '';
    byId('manual-save-password').checked = true;
    showModal('manual-modal');
  });

  byId('scan-networks-btn').addEventListener('click', async function () {
    try {
      var response = await fetch('/api/scan', { method: 'POST' });
      var data = await response.json();
      updateStatus(data.success ? data.message : 'Scan failed', data.success ? 'waiting' : 'failed', 'Refreshing network list...');
      setTimeout(function () { window.location.reload(); }, 800);
    } catch (err) {
      updateStatus('Scan error', 'failed', err.message || 'Unable to trigger scan.');
    }
  });

  byId('connect-form').addEventListener('submit', function (event) {
    event.preventDefault();
    var password = byId('password-input').value;
    var save = byId('save-password').checked;
    hideModal('password-modal');
    connect(selectedSsid, password, save);
  });

  byId('manual-form').addEventListener('submit', function (event) {
    event.preventDefault();
    var ssid = byId('manual-ssid').value;
    var password = byId('manual-password').value;
    var save = byId('manual-save-password').checked;
    hideModal('manual-modal');
    connect(ssid, password, save);
  });

  byId('cancel-password-btn').addEventListener('click', function () {
    hideModal('password-modal');
  });

  byId('cancel-manual-btn').addEventListener('click', function () {
    hideModal('manual-modal');
  });

  byId('toggle-password-btn').addEventListener('click', function () {
    var input = byId('password-input');
    input.type = input.type === 'password' ? 'text' : 'password';
  });

  byId('toggle-manual-password-btn').addEventListener('click', function () {
    var input = byId('manual-password');
    input.type = input.type === 'password' ? 'text' : 'password';
  });

  bindNetworkRows();

  setInterval(function () {
    if (!document.querySelector('.modal:not(.hidden)')) {
      window.location.reload();
    }
  }, 30000);
})();
"#;

pub fn render_portal_page(snapshot: &WifiStateSnapshot) -> String {
    let status_text = status_text(snapshot);
    let status_detail = status_detail(snapshot);
    let status_variant = status_variant(&snapshot.status);
    let status_tone = status_tone(&snapshot.status);
    let status_class = format!("portal-status state-{}", status_tone);
    let networks = snapshot.available_networks.clone();
    let has_networks = !networks.is_empty();

    let body_html = view! {
            <div class="portal-root">
                <Card class="portal-shell">
                    <CardHeader class="portal-header">
                        <CardTitle class="portal-title">"Hyper Recovery"</CardTitle>
                        <CardDescription class="portal-subtitle">"WiFi Setup Module"</CardDescription>
                    </CardHeader>

                    <CardContent class="portal-content">
                        <Alert class=status_class id="status" variant=status_variant>
                            <AlertTitle class="portal-status-title" id="status-text">{status_text.clone()}</AlertTitle>
                            <AlertDescription class="portal-status-detail" id="status-detail">{status_detail}</AlertDescription>
                        </Alert>

                        <div class="portal-actions">
                            <Button
                                variant=ButtonVariant::Outline
                                size=ButtonSize::Sm
                                class="portal-action-btn"
                                id="scan-networks-btn"
                            >
                                "Scan Again"
                            </Button>

                            <Button
                                variant=ButtonVariant::Secondary
                                size=ButtonSize::Sm
                                class="portal-action-btn"
                                id="manual-entry-btn"
                            >
                                "Enter Network Manually"
                            </Button>
                        </div>

                        <section class="network-list" id="network-list">
                            {if has_networks {
                                networks
                                    .iter()
                                    .cloned()
                                    .map(render_network_row)
                                    .collect_view()
                                    .into_any()
                            } else {
                                view! {
                                    <p class="empty-state">
                                        "No networks detected yet. Use Scan Again to refresh the list."
                                    </p>
                                }
                                .into_any()
                            }}
                        </section>
                    </CardContent>
                </Card>

                <div class="modal hidden" id="password-modal">
                    <Card class="modal-card">
                        <CardHeader class="modal-header">
                            <CardTitle class="modal-title">"Enter Password"</CardTitle>
                            <CardDescription class="modal-subtitle" id="modal-ssid">
                                "Selected network"
                            </CardDescription>
                        </CardHeader>

                        <CardContent class="modal-content">
                            <form class="portal-form" id="connect-form">
                                <div class="password-row">
                                    <Input
                                        class="portal-input"
                                        id="password-input"
                                        input_type="password"
                                        placeholder="Password"
                                    />
                                    <button class="toggle-btn" id="toggle-password-btn" type="button">"Show"</button>
                                </div>

                                <label class="checkbox-row">
                                    <input checked=true id="save-password" type="checkbox"/>
                                    <span>"Remember password for auto-connect"</span>
                                </label>

                                <div class="modal-actions">
                                    <button class="plain-btn secondary" id="cancel-password-btn" type="button">"Cancel"</button>
                                    <button class="plain-btn primary" type="submit">"Connect"</button>
                                </div>
                            </form>
                        </CardContent>
                    </Card>
                </div>

                <div class="modal hidden" id="manual-modal">
                    <Card class="modal-card">
                        <CardHeader class="modal-header">
                            <CardTitle class="modal-title">"Manual Network Entry"</CardTitle>
                            <CardDescription class="modal-subtitle">
                                "Enter SSID and password for hidden network"
                            </CardDescription>
                        </CardHeader>

                        <CardContent class="modal-content">
                            <form class="portal-form" id="manual-form">
                                <Input
                                    class="portal-input"
                                    id="manual-ssid"
                                    input_type="text"
                                    placeholder="Network Name (SSID)"
                                />

                                <div class="password-row">
                                    <Input
                                        class="portal-input"
                                        id="manual-password"
                                        input_type="password"
                                        placeholder="Password (leave empty for open network)"
                                    />
                                    <button class="toggle-btn" id="toggle-manual-password-btn" type="button">"Show"</button>
                                </div>

                                <label class="checkbox-row">
                                    <input checked=true id="manual-save-password" type="checkbox"/>
                                    <span>"Remember password for auto-connect"</span>
                                </label>

                                <div class="modal-actions">
                                    <button class="plain-btn secondary" id="cancel-manual-btn" type="button">"Cancel"</button>
                                    <button class="plain-btn primary" type="submit">"Connect"</button>
                                </div>
                            </form>
                        </CardContent>
                    </Card>
                </div>
            </div>
    }
    .to_html();

    format!(
        r#"<!DOCTYPE html>
<html class="dark" lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
  <title>Hyper Recovery - WiFi Setup</title>
  <link rel="stylesheet" href="/style.css">
</head>
<body>
{}
<script>{}</script>
</body>
</html>"#,
        body_html, PORTAL_BEHAVIOR_JS
    )
}

fn render_network_row(network: NetworkInfo) -> impl IntoView {
    let network_label = if network.is_secured {
        network.security_type
    } else {
        "Open".to_string()
    };

    let badge_variant = if network.is_secured {
        BadgeVariant::Secondary
    } else {
        BadgeVariant::Default
    };

    view! {
        <button
            class="network-row"
            data-secured=if network.is_secured { "true" } else { "false" }
            data-ssid=network.ssid.clone()
            type="button"
        >
            <div class="network-main">
                <span class="network-ssid">{network.ssid.clone()}</span>

                <div class="network-meta">
                    <span class="network-channel">{format!("CH {}", network.channel)}</span>
                    <Badge class="network-badge" variant=badge_variant>{network_label}</Badge>
                </div>
            </div>

            <div class="signal-wrap">
                <div class="signal-meter">
                    <span style=format!("width: {}%;", network.signal_strength)></span>
                </div>
                <span class="signal-value">{format!("{}%", network.signal_strength)}</span>
            </div>
        </button>
    }
}

fn status_variant(status: &ConnectionStatus) -> AlertVariant {
    match status {
        ConnectionStatus::Connected => AlertVariant::Success,
        ConnectionStatus::Connecting => AlertVariant::Warning,
        ConnectionStatus::Failed => AlertVariant::Destructive,
        _ => AlertVariant::Default,
    }
}

fn status_tone(status: &ConnectionStatus) -> &'static str {
    match status {
        ConnectionStatus::Connected => "connected",
        ConnectionStatus::Connecting => "connecting",
        ConnectionStatus::Failed => "failed",
        _ => "waiting",
    }
}

fn status_text(state: &WifiStateSnapshot) -> String {
    match state.status {
        ConnectionStatus::Connected => format!(
            "Connected to {}",
            state.connected_ssid.as_deref().unwrap_or("network")
        ),
        ConnectionStatus::Connecting => format!(
            "Connecting to {}...",
            state.connecting_to.as_deref().unwrap_or("network")
        ),
        ConnectionStatus::Failed => "Connection failed".to_string(),
        ConnectionStatus::Scanning => "Scanning for nearby networks".to_string(),
        ConnectionStatus::AwaitingCredentials => "Select a network to connect".to_string(),
        ConnectionStatus::Initializing => "Preparing WiFi setup".to_string(),
        ConnectionStatus::Disconnected => "Disconnected from WiFi".to_string(),
    }
}

fn status_detail(state: &WifiStateSnapshot) -> String {
    match state.status {
        ConnectionStatus::Connected => "Connection is active. You can continue setup.".to_string(),
        ConnectionStatus::Connecting => "Attempting authentication and DHCP handshake.".to_string(),
        ConnectionStatus::Failed => state
            .last_error
            .clone()
            .unwrap_or_else(|| "An unknown error occurred while connecting.".to_string()),
        ConnectionStatus::Scanning => "Searching for available access points...".to_string(),
        ConnectionStatus::AwaitingCredentials => {
            "Choose a network or enter credentials manually.".to_string()
        }
        ConnectionStatus::Initializing => {
            "Waiting for wireless interfaces to become ready.".to_string()
        }
        ConnectionStatus::Disconnected => "No active WiFi connection was detected.".to_string(),
    }
}
