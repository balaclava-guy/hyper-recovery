//! NetworkManager D-Bus integration

use super::{NetworkInfo, WifiBackend};
use anyhow::{Context, Result};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::net::Ipv4Addr;
use std::path::Path;
use std::process::Command;
use zbus::Connection;
use zvariant::{OwnedObjectPath, Value};

const DEFAULT_AP_IP: &str = "192.168.42.1";
const AP_IP_CANDIDATES: [&str; 5] = [
    "192.168.42.1",
    "10.42.0.1",
    "172.20.42.1",
    "192.168.88.1",
    "10.123.0.1",
];
const NM_DEST: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const NM_IFACE: &str = "org.freedesktop.NetworkManager";
const NM_DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device";
const NM_WIFI_DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const NM_AP_IFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
const NM_DEVICE_TYPE_WIFI: u32 = 2;
const NM_DEVICE_STATE_ACTIVATED: u32 = 100;
const NM_DEVICE_STATE_FAILED: u32 = 120;
const NM_80211_AP_FLAGS_PRIVACY: u32 = 0x1;

/// Parse the active NetworkManager WiFi backend from `NetworkManager --print-config`.
pub async fn current_wifi_backend() -> Result<WifiBackend> {
    let output = tokio::task::spawn_blocking(|| {
        Command::new("NetworkManager")
            .arg("--print-config")
            .output()
    })
    .await
    .context("Failed to join NetworkManager config probe")??;

    if !output.status.success() {
        anyhow::bail!("NetworkManager --print-config failed");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        let line = line.trim();
        if let Some(value) = line.strip_prefix("wifi.backend=") {
            let value = value.trim();
            return match value {
                "iwd" => Ok(WifiBackend::Iwd),
                "wpa_supplicant" => Ok(WifiBackend::WpaSupplicant),
                other => anyhow::bail!("Unknown NetworkManager wifi.backend value: {}", other),
            };
        }
    }

    anyhow::bail!("NetworkManager wifi.backend not found in printed config")
}

/// Switch NetworkManager WiFi backend (best-effort) by writing an override file and restarting services.
///
/// Notes:
/// - This restarts NetworkManager and may interrupt connectivity.
/// - Intended for troubleshooting in a recovery environment.
pub async fn switch_wifi_backend(backend: WifiBackend) -> Result<()> {
    let backend_value = backend.as_nm_value();
    let script = format!(
        r#"set -e
export PATH=/run/current-system/sw/bin:$PATH
CONF_DIR=/etc/NetworkManager/conf.d
CONF_FILE=$CONF_DIR/99-hyper-connect-backend.conf

mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" <<'EOF'
[device]
wifi.backend={backend_value}
EOF

if [ "{backend_value}" = "iwd" ]; then
  if ! systemctl cat iwd.service >/dev/null 2>&1; then
    echo "iwd.service is not available on this image" >&2
    exit 2
  fi
  systemctl stop wpa_supplicant.service || true
  systemctl start iwd.service
else
  if ! systemctl cat wpa_supplicant.service >/dev/null 2>&1; then
    echo "wpa_supplicant.service is not available on this image" >&2
    exit 2
  fi
  systemctl stop iwd.service || true
  systemctl start wpa_supplicant.service
fi

systemctl restart NetworkManager.service
"#
    );

    // hyper-connect runs with a hardened unit; run the switch outside of its sandbox.
    let output = tokio::process::Command::new("/run/current-system/sw/bin/systemd-run")
        .args([
            "--quiet",
            "--wait",
            "--collect",
            "--unit",
            "hyper-connect-backend-switch",
            "--property",
            "Type=oneshot",
            "--property",
            "TimeoutStartSec=45s",
            "--",
            "/run/current-system/sw/bin/bash",
            "-lc",
            &script,
        ])
        .output()
        .await
        .context("Failed to execute backend switch via systemd-run")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("Backend switch failed: {}", stderr.trim());
    }

    Ok(())
}

#[derive(Debug, Clone)]
struct WirelessInterface {
    name: String,
    driver_bound: bool,
    device_hint: String,
}

/// Resolve and validate wireless interface selection.
///
/// Behavior:
/// - `auto` picks a detected wireless interface
/// - explicit interface is used if valid
/// - if explicit interface is missing but exactly one wireless interface exists, fallback to it
pub fn resolve_wireless_interface(configured: &str) -> Result<String> {
    let configured = configured.trim();
    let interfaces = list_wireless_interfaces();

    if configured.eq_ignore_ascii_case("auto") || configured.is_empty() {
        return choose_auto_interface(&interfaces);
    }

    if let Some(iface) = interfaces.iter().find(|iface| iface.name == configured) {
        if iface.driver_bound {
            return Ok(iface.name.clone());
        }

        anyhow::bail!(
            "Wireless card detected for interface '{}' (device: {}) but no kernel driver is bound. This usually indicates missing firmware or driver support for the adapter.",
            iface.name,
            iface.device_hint
        );
    }

    let detected_wireless: Vec<&WirelessInterface> = interfaces
        .iter()
        .filter(|iface| !iface.name.starts_with("p2p-"))
        .collect();

    let viable_interfaces: Vec<&WirelessInterface> = detected_wireless
        .iter()
        .copied()
        .filter(|iface| iface.driver_bound)
        .collect();

    if viable_interfaces.len() == 1 {
        let detected = viable_interfaces[0];
        tracing::warn!(
            configured = configured,
            detected = %detected.name,
            "Configured interface not found; falling back to detected wireless interface"
        );
        return Ok(detected.name.clone());
    }

    if !viable_interfaces.is_empty() {
        let names = viable_interfaces
            .iter()
            .map(|iface| iface.name.as_str())
            .collect::<Vec<_>>()
            .join(", ");

        anyhow::bail!(
            "Configured interface '{}' was not found. Detected wireless interfaces: {}. Set --interface explicitly or use --interface auto.",
            configured,
            names
        );
    }

    if !detected_wireless.is_empty() {
        let names = detected_wireless
            .iter()
            .map(|iface| format!("{} ({})", iface.name, iface.device_hint))
            .collect::<Vec<_>>()
            .join(", ");

        anyhow::bail!(
            "Configured interface '{}' was not found. Wireless interface(s) detected but no kernel driver is bound: {}. This usually indicates missing firmware or driver support.",
            configured,
            names
        );
    }

    let unbound_wifi = detect_unbound_pci_wifi_devices();
    if !unbound_wifi.is_empty() {
        anyhow::bail!(
            "No wireless interface is currently available. Detected wireless PCI device(s) without loaded driver: {}. This usually means firmware/driver for the adapter is missing.",
            unbound_wifi.join(", ")
        );
    }

    anyhow::bail!(
        "Configured interface '{}' was not found and no wireless interfaces were detected",
        configured
    );
}

/// Resolve AP IP address, using conflict-aware selection when `auto` is requested.
pub fn resolve_ap_ip(configured: &str) -> Result<String> {
    let configured = configured.trim();
    if !configured.eq_ignore_ascii_case("auto") {
        let ip: Ipv4Addr = configured
            .parse()
            .with_context(|| format!("Invalid AP IP address: '{}'", configured))?;
        return Ok(ip.to_string());
    }

    let occupied = occupied_ipv4_prefixes();
    for candidate in AP_IP_CANDIDATES {
        let Ok(ip) = candidate.parse::<Ipv4Addr>() else {
            continue;
        };
        let [a, b, c, _] = ip.octets();
        if !occupied.contains(&(a, b, c)) {
            tracing::info!(ap_ip = %candidate, "Selected AP subnet automatically");
            return Ok(candidate.to_string());
        }
    }

    tracing::warn!(
        fallback = DEFAULT_AP_IP,
        "All preferred AP subnets overlap with existing addresses; falling back to default"
    );
    Ok(DEFAULT_AP_IP.to_string())
}

fn choose_auto_interface(interfaces: &[WirelessInterface]) -> Result<String> {
    let mut viable_interfaces = interfaces
        .iter()
        .filter(|iface| iface.driver_bound && !iface.name.starts_with("p2p-"))
        .collect::<Vec<_>>();

    viable_interfaces.sort_by(|a, b| a.name.cmp(&b.name));

    if let Some(interface) = viable_interfaces.first() {
        tracing::info!(interface = %interface.name, "Auto-selected wireless interface");
        return Ok(interface.name.clone());
    }

    let without_driver = interfaces
        .iter()
        .filter(|iface| !iface.driver_bound && !iface.name.starts_with("p2p-"))
        .map(|iface| format!("{} ({})", iface.name, iface.device_hint))
        .collect::<Vec<_>>();

    if !without_driver.is_empty() {
        anyhow::bail!(
            "Wireless interface(s) detected but no kernel driver is bound: {}. This usually indicates missing firmware or driver support.",
            without_driver.join(", ")
        );
    }

    let unbound_wifi = detect_unbound_pci_wifi_devices();
    if !unbound_wifi.is_empty() {
        anyhow::bail!(
            "No usable wireless interface found. Detected wireless PCI device(s) without loaded driver: {}. This usually means firmware/driver for the adapter is missing.",
            unbound_wifi.join(", ")
        );
    }

    anyhow::bail!("No usable wireless interfaces detected")
}

fn list_wireless_interfaces() -> Vec<WirelessInterface> {
    let mut interfaces = Vec::new();
    let Ok(entries) = fs::read_dir("/sys/class/net") else {
        return interfaces;
    };

    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        let iface_path = entry.path();
        if !iface_path.join("wireless").exists() {
            continue;
        }

        let driver_bound = iface_path.join("device/driver").exists();
        let device_hint = fs::read_link(iface_path.join("device"))
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string()))
            .unwrap_or_else(|| "unknown-device".to_string());

        interfaces.push(WirelessInterface {
            name,
            driver_bound,
            device_hint,
        });
    }

    interfaces
}

fn occupied_ipv4_prefixes() -> HashSet<(u8, u8, u8)> {
    let mut prefixes = HashSet::new();

    let Ok(output) = Command::new("ip")
        .args(["-4", "-o", "addr", "show"])
        .output()
    else {
        return prefixes;
    };

    if !output.status.success() {
        return prefixes;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        for token in line.split_whitespace() {
            if !token.contains('/') {
                continue;
            }

            let Some(address) = token.split('/').next() else {
                continue;
            };

            if let Ok(ip) = address.parse::<Ipv4Addr>() {
                let [a, b, c, _] = ip.octets();
                prefixes.insert((a, b, c));
                break;
            }
        }
    }

    prefixes
}

fn detect_unbound_pci_wifi_devices() -> Vec<String> {
    let mut devices = Vec::new();
    let pci_root = Path::new("/sys/bus/pci/devices");

    let entries = match fs::read_dir(pci_root) {
        Ok(entries) => entries,
        Err(_) => return devices,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let class = fs::read_to_string(path.join("class")).unwrap_or_default();
        let class = class.trim();

        // 0x0280xx = Network controller / Other (typically wireless adapters)
        if !class.starts_with("0x0280") {
            continue;
        }

        if path.join("driver").exists() {
            continue;
        }

        let slot = entry.file_name().to_string_lossy().to_string();
        let vendor = fs::read_to_string(path.join("vendor"))
            .unwrap_or_else(|_| "unknown-vendor".to_string())
            .trim()
            .to_string();
        let device = fs::read_to_string(path.join("device"))
            .unwrap_or_else(|_| "unknown-device".to_string())
            .trim()
            .to_string();

        devices.push(format!("{} (vendor {}, device {})", slot, vendor, device));
    }

    devices
}

/// Check if we have network connectivity via NetworkManager
pub async fn check_connectivity() -> Result<bool> {
    let connection = Connection::system().await?;

    let proxy = zbus::Proxy::new(&connection, NM_DEST, NM_PATH, NM_IFACE).await?;

    // NM_CONNECTIVITY_FULL = 4
    let connectivity: u32 = proxy.get_property("Connectivity").await?;

    Ok(connectivity == 4)
}

/// Wait for network connectivity
pub async fn wait_for_connectivity() -> Result<()> {
    let connection = Connection::system().await?;

    loop {
        let proxy = zbus::Proxy::new(&connection, NM_DEST, NM_PATH, NM_IFACE).await?;

        let connectivity: u32 = proxy.get_property("Connectivity").await?;

        if connectivity == 4 {
            return Ok(());
        }

        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }
}

/// Scan for available WiFi networks
pub async fn scan_networks(interface: &str) -> Result<Vec<NetworkInfo>> {
    tracing::info!(interface = %interface, "Scanning for WiFi networks");

    let connection = Connection::system().await?;
    let device_path = get_wifi_device_path(&connection, interface).await?;

    request_scan_and_wait(&connection, &device_path).await;

    let ap_paths = get_access_points(&connection, &device_path).await?;
    let mut by_ssid = HashMap::<String, NetworkInfo>::new();

    for ap_path in ap_paths {
        let Some(network) = read_access_point(&connection, &ap_path).await? else {
            continue;
        };

        by_ssid
            .entry(network.ssid.clone())
            .and_modify(|existing| {
                if network.signal_strength > existing.signal_strength {
                    *existing = network.clone();
                }
            })
            .or_insert(network);
    }

    let mut networks: Vec<_> = by_ssid.into_values().collect();
    networks.sort_by(|a, b| b.signal_strength.cmp(&a.signal_strength));

    tracing::info!(count = networks.len(), "Found WiFi networks");
    Ok(networks)
}

/// Connect to a WiFi network
pub async fn connect_to_network(interface: &str, ssid: &str, password: &str) -> Result<()> {
    tracing::info!(interface = %interface, ssid = %ssid, "Connecting to WiFi network");

    // During AP mode we stop the WiFi backend and mark the device unmanaged to allow
    // hostapd to take exclusive control. Ensure the backend is restarted before asking
    // NetworkManager to activate a station connection.
    let backend = current_wifi_backend().await.unwrap_or(WifiBackend::Iwd);
    let service_name = match backend {
        WifiBackend::Iwd => "iwd.service",
        WifiBackend::WpaSupplicant => "wpa_supplicant.service",
    };
    let _ = tokio::process::Command::new("systemctl")
        .args(["start", service_name])
        .output()
        .await;

    let connection = Connection::system().await?;
    let device_path = get_wifi_device_path(&connection, interface).await?;
    let device_proxy =
        zbus::Proxy::new(&connection, NM_DEST, device_path.as_str(), NM_DEVICE_IFACE).await?;

    let _ = device_proxy.set_property("Managed", &true).await;
    let _ = device_proxy.set_property("Autoconnect", &true).await;
    let _ = device_proxy.call::<_, _, ()>("Disconnect", &()).await;

    // Clear AP addressing leftovers before returning interface to client mode.
    let _ = tokio::process::Command::new("ip")
        .args(["addr", "flush", "dev", interface])
        .output()
        .await;
    let _ = tokio::process::Command::new("ip")
        .args(["link", "set", interface, "up"])
        .output()
        .await;

    let max_attempts = 3;
    let mut last_error = String::new();

    for attempt in 1..=max_attempts {
        tracing::info!(attempt, max_attempts, ssid = %ssid, "Activating WiFi connection via D-Bus");
        request_scan_and_wait(&connection, &device_path).await;

        let specific_ap = match find_best_ap_for_ssid(&connection, &device_path, ssid).await? {
            Some(path) => path,
            None => {
                let any = OwnedObjectPath::try_from("/")
                    .context("Failed to create root object path for activation")?;
                last_error = format!("SSID '{}' not found in current scan results", ssid);
                tracing::warn!(attempt, max_attempts, ssid = %ssid, "SSID not in scan list, trying hidden profile activation");
                any
            }
        };

        let settings = build_connection_settings(ssid, password, specific_ap.as_str() == "/");
        let nm_proxy = zbus::Proxy::new(&connection, NM_DEST, NM_PATH, NM_IFACE).await?;
        let activate_result =
            activate_connection(&nm_proxy, &settings, device_path.clone(), specific_ap).await;

        match activate_result {
            Ok(()) => {
                wait_for_device_activation(
                    &connection,
                    &device_path,
                    std::time::Duration::from_secs(35),
                )
                .await?;
                tracing::info!("Successfully connected to WiFi network");
                return Ok(());
            }
            Err(e) => {
                last_error = e;
                tracing::warn!(
                    attempt,
                    max_attempts,
                    ssid = %ssid,
                    error = %last_error,
                    "WiFi connection attempt failed"
                );
            }
        }

        if attempt < max_attempts {
            tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        }
    }

    anyhow::bail!(
        "Connection failed after {} attempts: {}",
        max_attempts,
        last_error
    );
}

/// Create a WiFi connection profile via D-Bus
#[allow(dead_code)]
pub async fn create_wifi_connection_dbus(ssid: &str, password: &str) -> Result<String> {
    let connection = Connection::system().await?;

    let proxy = zbus::Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings",
    )
    .await?;

    // Build connection settings
    let uuid = uuid::Uuid::new_v4().to_string();

    let mut conn_settings: HashMap<&str, Value> = HashMap::new();
    conn_settings.insert("type", Value::from("802-11-wireless"));
    conn_settings.insert("id", Value::from(ssid));
    conn_settings.insert("uuid", Value::from(uuid.as_str()));

    let mut wifi_settings: HashMap<&str, Value> = HashMap::new();
    wifi_settings.insert("ssid", Value::from(ssid.as_bytes().to_vec()));
    wifi_settings.insert("mode", Value::from("infrastructure"));

    let mut security_settings: HashMap<&str, Value> = HashMap::new();
    security_settings.insert("key-mgmt", Value::from("wpa-psk"));
    security_settings.insert("psk", Value::from(password));

    let mut ipv4_settings: HashMap<&str, Value> = HashMap::new();
    ipv4_settings.insert("method", Value::from("auto"));

    let mut config: HashMap<&str, HashMap<&str, Value>> = HashMap::new();
    config.insert("connection", conn_settings);
    config.insert("802-11-wireless", wifi_settings);
    config.insert("802-11-wireless-security", security_settings);
    config.insert("ipv4", ipv4_settings);

    let path: zvariant::OwnedObjectPath = proxy
        .call_method("AddConnection", &(config,))
        .await?
        .body()
        .deserialize()?;

    Ok(path.to_string())
}

async fn wait_for_device_activation(
    connection: &Connection,
    device_path: &OwnedObjectPath,
    timeout: std::time::Duration,
) -> Result<()> {
    let deadline = std::time::Instant::now() + timeout;
    let device_proxy =
        zbus::Proxy::new(connection, NM_DEST, device_path.as_str(), NM_DEVICE_IFACE).await?;

    loop {
        let state: u32 = device_proxy.get_property("State").await?;
        if state == NM_DEVICE_STATE_ACTIVATED {
            return Ok(());
        }
        if state == NM_DEVICE_STATE_FAILED {
            let reason: (u32, u32) = device_proxy
                .get_property("StateReason")
                .await
                .unwrap_or((state, 0));
            anyhow::bail!(
                "Device activation failed: state={} reason={}",
                reason.0,
                reason.1
            );
        }

        if std::time::Instant::now() >= deadline {
            anyhow::bail!(
                "Connection timed out waiting for device activation (state={})",
                state
            );
        }

        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }
}

async fn get_wifi_device_path(connection: &Connection, interface: &str) -> Result<OwnedObjectPath> {
    let nm_proxy = zbus::Proxy::new(connection, NM_DEST, NM_PATH, NM_IFACE).await?;
    let device_path: OwnedObjectPath = nm_proxy
        .call("GetDeviceByIpIface", &(interface,))
        .await
        .with_context(|| {
            format!(
                "Failed to resolve NetworkManager device for '{}'",
                interface
            )
        })?;

    let device_proxy =
        zbus::Proxy::new(connection, NM_DEST, device_path.as_str(), NM_DEVICE_IFACE).await?;
    let device_type: u32 = device_proxy.get_property("DeviceType").await?;
    if device_type != NM_DEVICE_TYPE_WIFI {
        anyhow::bail!(
            "Interface '{}' is not a WiFi device according to NetworkManager (type={})",
            interface,
            device_type
        );
    }

    Ok(device_path)
}

async fn request_scan_and_wait(connection: &Connection, device_path: &OwnedObjectPath) {
    let Ok(wifi_proxy) = zbus::Proxy::new(
        connection,
        NM_DEST,
        device_path.as_str(),
        NM_WIFI_DEVICE_IFACE,
    )
    .await
    else {
        return;
    };

    let last_scan_before: i64 = wifi_proxy.get_property("LastScan").await.unwrap_or(-1);

    let options = HashMap::<&str, Value>::new();
    let _ = wifi_proxy
        .call::<_, _, ()>("RequestScan", &(options,))
        .await;

    let scan_deadline = std::time::Instant::now() + std::time::Duration::from_secs(6);
    while std::time::Instant::now() < scan_deadline {
        let last_scan_now: i64 = wifi_proxy.get_property("LastScan").await.unwrap_or(-1);
        if last_scan_now > last_scan_before {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(400)).await;
    }
}

async fn get_access_points(
    connection: &Connection,
    device_path: &OwnedObjectPath,
) -> Result<Vec<OwnedObjectPath>> {
    let wifi_proxy = zbus::Proxy::new(
        connection,
        NM_DEST,
        device_path.as_str(),
        NM_WIFI_DEVICE_IFACE,
    )
    .await?;

    let ap_paths: Vec<OwnedObjectPath> = wifi_proxy.call("GetAllAccessPoints", &()).await?;
    Ok(ap_paths)
}

async fn read_access_point(
    connection: &Connection,
    ap_path: &OwnedObjectPath,
) -> Result<Option<NetworkInfo>> {
    let ap_proxy = zbus::Proxy::new(connection, NM_DEST, ap_path.as_str(), NM_AP_IFACE).await?;

    let ssid_raw: Vec<u8> = ap_proxy.get_property("Ssid").await?;
    if ssid_raw.is_empty() {
        return Ok(None);
    }

    let ssid = String::from_utf8_lossy(&ssid_raw).to_string();
    if ssid.is_empty() {
        return Ok(None);
    }

    let bssid: String = ap_proxy.get_property("HwAddress").await.unwrap_or_default();
    let signal_strength: u8 = ap_proxy.get_property("Strength").await.unwrap_or(0);
    let frequency: u32 = ap_proxy.get_property("Frequency").await.unwrap_or(0);
    let flags: u32 = ap_proxy.get_property("Flags").await.unwrap_or(0);
    let wpa_flags: u32 = ap_proxy.get_property("WpaFlags").await.unwrap_or(0);
    let rsn_flags: u32 = ap_proxy.get_property("RsnFlags").await.unwrap_or(0);
    let is_secured = (flags & NM_80211_AP_FLAGS_PRIVACY) != 0 || wpa_flags != 0 || rsn_flags != 0;

    Ok(Some(NetworkInfo {
        ssid,
        bssid,
        signal_strength,
        frequency,
        channel: frequency_to_channel(frequency),
        is_secured,
        security_type: classify_security(flags, wpa_flags, rsn_flags),
    }))
}

async fn find_best_ap_for_ssid(
    connection: &Connection,
    device_path: &OwnedObjectPath,
    ssid: &str,
) -> Result<Option<OwnedObjectPath>> {
    let ap_paths = get_access_points(connection, device_path).await?;
    let mut best: Option<(OwnedObjectPath, u8)> = None;

    for ap_path in ap_paths {
        let ap_proxy = zbus::Proxy::new(connection, NM_DEST, ap_path.as_str(), NM_AP_IFACE).await?;
        let ssid_raw: Vec<u8> = ap_proxy.get_property("Ssid").await.unwrap_or_default();
        if ssid_raw.is_empty() {
            continue;
        }

        let candidate_ssid = String::from_utf8_lossy(&ssid_raw).to_string();
        if candidate_ssid != ssid {
            continue;
        }

        let strength: u8 = ap_proxy.get_property("Strength").await.unwrap_or(0);
        match &best {
            Some((_, best_strength)) if *best_strength >= strength => {}
            _ => best = Some((ap_path, strength)),
        }
    }

    Ok(best.map(|(path, _)| path))
}

fn build_connection_settings<'a>(
    ssid: &'a str,
    password: &'a str,
    hidden: bool,
) -> HashMap<&'static str, HashMap<&'static str, Value<'a>>> {
    let mut conn_settings = HashMap::new();
    conn_settings.insert("type", Value::from("802-11-wireless"));
    conn_settings.insert("id", Value::from(ssid));
    conn_settings.insert("uuid", Value::from(uuid::Uuid::new_v4().to_string()));
    conn_settings.insert("autoconnect", Value::from(false));

    let mut wifi_settings = HashMap::new();
    wifi_settings.insert("ssid", Value::from(ssid.as_bytes().to_vec()));
    wifi_settings.insert("mode", Value::from("infrastructure"));
    if hidden {
        wifi_settings.insert("hidden", Value::from(true));
    }

    let mut ipv4_settings = HashMap::new();
    ipv4_settings.insert("method", Value::from("auto"));

    let mut ipv6_settings = HashMap::new();
    ipv6_settings.insert("method", Value::from("auto"));

    let mut settings = HashMap::new();
    settings.insert("connection", conn_settings);
    settings.insert("802-11-wireless", wifi_settings);
    settings.insert("ipv4", ipv4_settings);
    settings.insert("ipv6", ipv6_settings);

    if !password.is_empty() {
        let mut security_settings = HashMap::new();
        security_settings.insert("key-mgmt", Value::from("wpa-psk"));
        security_settings.insert("psk", Value::from(password));
        settings.insert("802-11-wireless-security", security_settings);
    }

    settings
}

async fn activate_connection<'a>(
    nm_proxy: &zbus::Proxy<'_>,
    settings: &HashMap<&'static str, HashMap<&'static str, Value<'a>>>,
    device_path: OwnedObjectPath,
    specific_ap: OwnedObjectPath,
) -> std::result::Result<(), String> {
    let mut options: HashMap<&str, Value> = HashMap::new();
    options.insert("persist", Value::from("volatile"));

    let v2_result: std::result::Result<
        (
            OwnedObjectPath,
            OwnedObjectPath,
            HashMap<String, zvariant::OwnedValue>,
        ),
        zbus::Error,
    > = nm_proxy
        .call(
            "AddAndActivateConnection2",
            &(settings, &device_path, &specific_ap, options),
        )
        .await;

    match v2_result {
        Ok(_) => Ok(()),
        Err(zbus::Error::MethodError(name, _, _))
            if name.as_str() == "org.freedesktop.DBus.Error.UnknownMethod" =>
        {
            let legacy: std::result::Result<(OwnedObjectPath, OwnedObjectPath), zbus::Error> =
                nm_proxy
                    .call(
                        "AddAndActivateConnection",
                        &(settings, &device_path, &specific_ap),
                    )
                    .await;
            legacy.map(|_| ()).map_err(|e| e.to_string())
        }
        Err(e) => Err(e.to_string()),
    }
}

fn classify_security(flags: u32, wpa_flags: u32, rsn_flags: u32) -> String {
    if rsn_flags != 0 && wpa_flags != 0 {
        return "WPA/WPA2".to_string();
    }
    if rsn_flags != 0 {
        return "WPA2/WPA3".to_string();
    }
    if wpa_flags != 0 {
        return "WPA".to_string();
    }
    if (flags & NM_80211_AP_FLAGS_PRIVACY) != 0 {
        return "WEP/Protected".to_string();
    }
    "Open".to_string()
}

fn frequency_to_channel(freq: u32) -> u8 {
    match freq {
        2412..=2472 => ((freq - 2407) / 5) as u8,
        2484 => 14,
        5000..=5900 => ((freq - 5000) / 5) as u8,
        _ => 0,
    }
}
