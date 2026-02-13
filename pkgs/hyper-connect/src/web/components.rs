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
  var pollTimer = null;
  var connectInProgress = false;

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
    if (status === 'SwitchingBackend') return 'connecting';
    if (status === 'Failed') return 'failed';
    return 'waiting';
  }

  function statusTextForSnapshot(data) {
    if (!data || !data.status) return 'Preparing WiFi setup';
    if (data.status === 'Connected') return 'Connected to ' + (data.connected_ssid || 'network');
    if (data.status === 'Connecting') return 'Connecting to ' + (data.connecting_to || 'network') + '...';
    if (data.status === 'SwitchingBackend') return 'Switching WiFi backend...';
    if (data.status === 'Failed') return 'Connection failed';
    if (data.status === 'Scanning') return 'Scanning for nearby networks';
    if (data.status === 'AwaitingCredentials') return 'Select a network to connect';
    if (data.status === 'Disconnected') return 'Disconnected from WiFi';
    return 'Preparing WiFi setup';
  }

  function statusDetailForSnapshot(data) {
    if (!data || !data.status) return 'Waiting for wireless interfaces to become ready.';
    if (data.status === 'Connected') return 'Connection is active. You can close this page now.';
    if (data.status === 'Connecting') return 'Authentication and DHCP are still in progress.';
    if (data.status === 'SwitchingBackend') return 'Restarting WiFi services. The setup AP may restart; reconnect if needed.';
    if (data.status === 'Failed') return data.last_error || 'Unknown error while connecting.';
    if (data.status === 'Scanning') return 'Searching for available access points...';
    if (data.status === 'AwaitingCredentials') return 'Choose a network or enter credentials manually.';
    if (data.status === 'Disconnected') return 'No active WiFi connection was detected.';
    return 'Waiting for wireless interfaces to become ready.';
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

  function updateStatusFromSnapshot(data) {
    updateStatus(
      statusTextForSnapshot(data),
      statusToneForState(data && data.status),
      statusDetailForSnapshot(data)
    );
  }

  function clearPoll() {
    if (pollTimer) {
      clearTimeout(pollTimer);
      pollTimer = null;
    }
  }

  function schedulePoll(delayMs) {
    clearPoll();
    pollTimer = setTimeout(pollStatus, delayMs);
  }

  async function connect(ssid, password, save) {
    connectInProgress = true;
    updateStatus(
      'Connecting to ' + ssid + '...',
      'connecting',
      'Applying credentials and starting authentication...'
    );
    schedulePoll(250);

    try {
      var response = await fetch('/api/connect', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ssid: ssid, password: password, save: save })
      });

      var data = await response.json();

      if (data.success) {
        updateStatus('Connection requested', 'connecting', data.message || 'Waiting for daemon status...');
        schedulePoll(400);
      } else {
        connectInProgress = false;
        clearPoll();
        updateStatus('Connection failed', 'failed', data.message);
      }
    } catch (err) {
      connectInProgress = false;
      clearPoll();
      updateStatus('Connection error', 'failed', err.message || 'Unexpected network error.');
    }
  }

  async function pollStatus() {
    try {
      var response = await fetch('/api/status', { cache: 'no-store' });
      if (!response.ok) {
        throw new Error('Status endpoint unavailable');
      }
      var data = await response.json();
      updateStatusFromSnapshot(data);

      if (data.status === 'Connected') {
        connectInProgress = false;
        clearPoll();
        return;
      }

      if (data.status === 'Failed') {
        connectInProgress = false;
        clearPoll();
        return;
      }

      if (data.status === 'Connecting') {
        schedulePoll(1000);
        return;
      }

      schedulePoll(connectInProgress ? 1200 : 2500);
    } catch (err) {
      if (connectInProgress) {
        updateStatus('Connection in progress', 'connecting', 'Still attempting to join the network...');
        schedulePoll(1500);
        return;
      }

      updateStatus('Waiting for portal status', 'waiting', 'Retrying status sync...');
      schedulePoll(2500);
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

  byId('settings-btn').addEventListener('click', function () {
    showModal('settings-modal');
    // Populate current backend from the last known status.
    fetch('/api/status', { cache: 'no-store' })
      .then(function (response) { return response.json(); })
      .then(function (data) {
        var backend = (data && data.wifi_backend) ? data.wifi_backend : null;
        var backendLabel = backend === 'iwd' ? 'iwd' : (backend === 'wpa_supplicant' ? 'wpa_supplicant' : 'unknown');
        byId('backend-current').textContent = backendLabel;
      })
      .catch(function () {
        byId('backend-current').textContent = 'unknown';
      });
  });

  byId('cancel-settings-btn').addEventListener('click', function () {
    hideModal('settings-modal');
  });

  byId('backend-form').addEventListener('submit', async function (event) {
    event.preventDefault();
    var selected = document.querySelector('input[name="backend"]:checked');
    if (!selected) {
      return;
    }

    hideModal('settings-modal');
    updateStatus('Switching WiFi backend...', 'connecting', 'Restarting WiFi services and NetworkManager...');
    connectInProgress = true;

    try {
      var response = await fetch('/api/backend', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ backend: selected.value })
      });
      var data = await response.json();
      updateStatus(data.success ? 'Backend switch requested' : 'Backend switch failed', data.success ? 'connecting' : 'failed', data.message || '');
      schedulePoll(1200);
    } catch (err) {
      connectInProgress = false;
      clearPoll();
      updateStatus('Backend switch error', 'failed', err.message || 'Unable to switch backend.');
    }
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
    if (connectInProgress) {
      return;
    }

    if (!document.querySelector('.modal:not(.hidden)')) {
      window.location.reload();
    }
  }, 30000);

  pollStatus();
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

                            <Button
                                variant=ButtonVariant::Outline
                                size=ButtonSize::Sm
                                class="portal-action-btn"
                                id="settings-btn"
                            >
                                "Help / Settings"
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

                <div class="modal hidden" id="settings-modal">
                    <Card class="modal-card">
                        <CardHeader class="modal-header">
                            <CardTitle class="modal-title">"Help / Settings"</CardTitle>
                            <CardDescription class="modal-subtitle">
                                "If WiFi connection is unreliable, try switching the NetworkManager WiFi backend. This restarts WiFi services and may temporarily drop your connection to the setup AP."
                            </CardDescription>
                        </CardHeader>

                        <CardContent class="modal-content">
                            <div class="settings-row">
                                <span class="settings-label">"Current backend"</span>
                                <span class="settings-value" id="backend-current">"unknown"</span>
                            </div>

                            <form class="portal-form" id="backend-form">
                                <label class="radio-row">
                                    <input name="backend" type="radio" value="iwd"/>
                                    <span>"iwd (recommended for Intel WiFi)"</span>
                                </label>
                                <label class="radio-row">
                                    <input name="backend" type="radio" value="wpa_supplicant"/>
                                    <span>"wpa_supplicant (max compatibility)"</span>
                                </label>

                                <div class="modal-actions">
                                    <button class="plain-btn secondary" id="cancel-settings-btn" type="button">"Close"</button>
                                    <button class="plain-btn primary" type="submit">"Apply & Restart WiFi"</button>
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
  <meta name="color-scheme" content="dark">
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
        ConnectionStatus::SwitchingBackend => AlertVariant::Warning,
        ConnectionStatus::Failed => AlertVariant::Destructive,
        _ => AlertVariant::Default,
    }
}

fn status_tone(status: &ConnectionStatus) -> &'static str {
    match status {
        ConnectionStatus::Connected => "connected",
        ConnectionStatus::Connecting => "connecting",
        ConnectionStatus::SwitchingBackend => "connecting",
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
        ConnectionStatus::SwitchingBackend => "Switching WiFi backend...".to_string(),
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
        ConnectionStatus::SwitchingBackend => {
            "Restarting WiFi services. The setup AP may restart; reconnect if needed.".to_string()
        }
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
