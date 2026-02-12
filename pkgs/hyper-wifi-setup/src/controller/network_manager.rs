//! NetworkManager D-Bus integration

use super::NetworkInfo;
use anyhow::{Context, Result};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::net::Ipv4Addr;
use std::path::Path;
use std::process::Command;
use zbus::Connection;
use zvariant::Value;

const DEFAULT_AP_IP: &str = "192.168.42.1";
const AP_IP_CANDIDATES: [&str; 5] = [
    "192.168.42.1",
    "10.42.0.1",
    "172.20.42.1",
    "192.168.88.1",
    "10.123.0.1",
];
const NMCLI_SEPARATOR: &str = "|";

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

    let proxy = zbus::Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
    )
    .await?;

    // NM_CONNECTIVITY_FULL = 4
    let connectivity: u32 = proxy.get_property("Connectivity").await?;

    Ok(connectivity == 4)
}

/// Wait for network connectivity
pub async fn wait_for_connectivity() -> Result<()> {
    let connection = Connection::system().await?;

    loop {
        let proxy = zbus::Proxy::new(
            &connection,
            "org.freedesktop.NetworkManager",
            "/org/freedesktop/NetworkManager",
            "org.freedesktop.NetworkManager",
        )
        .await?;

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

    // Use nmcli for simplicity - it handles the async scan properly.
    // Use a custom field separator to avoid splitting BSSID colons.
    let output = tokio::process::Command::new("nmcli")
        .args([
            "-t",
            "--escape",
            "yes",
            "--separator",
            NMCLI_SEPARATOR,
            "-f",
            "SSID,BSSID,SIGNAL,FREQ,CHAN,SECURITY",
            "device",
            "wifi",
            "list",
            "ifname",
            interface,
            "--rescan",
            "yes",
        ])
        .output()
        .await
        .context("Failed to run nmcli")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nmcli failed: {}", stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut networks = Vec::new();
    let mut seen_ssids = std::collections::HashSet::new();

    for line in stdout.lines() {
        let fields = split_escaped_fields(line, NMCLI_SEPARATOR.chars().next().unwrap());
        if fields.len() >= 6 {
            let ssid = fields[0].clone();

            // Skip empty SSIDs and duplicates
            if ssid.is_empty() || seen_ssids.contains(&ssid) {
                continue;
            }
            seen_ssids.insert(ssid.clone());

            let signal: u8 = fields[2].parse().unwrap_or(0);
            let freq: u32 = fields[3]
                .split_whitespace()
                .next()
                .unwrap_or("0")
                .parse()
                .unwrap_or(0);
            let channel: u8 = fields[4].parse().unwrap_or(0);
            let security = fields[5].clone();
            let is_secured = !security.is_empty() && security != "--";

            networks.push(NetworkInfo {
                ssid,
                bssid: fields[1].clone(),
                signal_strength: signal,
                frequency: freq,
                channel,
                is_secured,
                security_type: if is_secured {
                    security
                } else {
                    "Open".to_string()
                },
            });
        }
    }

    // Sort by signal strength (strongest first)
    networks.sort_by(|a, b| b.signal_strength.cmp(&a.signal_strength));

    tracing::info!(count = networks.len(), "Found WiFi networks");
    Ok(networks)
}

/// Connect to a WiFi network
pub async fn connect_to_network(interface: &str, ssid: &str, password: &str) -> Result<()> {
    tracing::info!(interface = %interface, ssid = %ssid, "Connecting to WiFi network");

    // First, ensure the interface is managed by NetworkManager
    let _ = tokio::process::Command::new("nmcli")
        .args(["device", "set", interface, "managed", "yes"])
        .output()
        .await;

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
        tracing::info!(attempt, max_attempts, ssid = %ssid, "Attempting WiFi connection");

        let _ = tokio::process::Command::new("nmcli")
            .args(["device", "wifi", "rescan", "ifname", interface])
            .output()
            .await;

        tokio::time::sleep(std::time::Duration::from_secs(2)).await;

        let mut command = tokio::process::Command::new("nmcli");
        command.args([
            "--wait", "20", "device", "wifi", "connect", ssid, "ifname", interface,
        ]);
        if !password.is_empty() {
            command.args(["password", password]);
        }

        let output = command
            .output()
            .await
            .context("Failed to run nmcli connect")?;

        if output.status.success() {
            wait_for_interface_connection(interface, std::time::Duration::from_secs(30)).await?;
            tracing::info!("Successfully connected to WiFi network");
            return Ok(());
        }

        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        last_error = format!("{} {}", stdout.trim(), stderr.trim())
            .trim()
            .to_string();

        if last_error.contains("No network with SSID") {
            tracing::warn!(
                ssid = %ssid,
                interface = %interface,
                "SSID not visible in scan cache; retrying with hidden=yes"
            );

            let mut hidden_connect = tokio::process::Command::new("nmcli");
            hidden_connect.args([
                "--wait", "20", "device", "wifi", "connect", ssid, "ifname", interface, "hidden",
                "yes",
            ]);
            if !password.is_empty() {
                hidden_connect.args(["password", password]);
            }

            let hidden_output = hidden_connect
                .output()
                .await
                .context("Failed to run nmcli hidden connect")?;

            if hidden_output.status.success() {
                wait_for_interface_connection(interface, std::time::Duration::from_secs(30))
                    .await?;
                tracing::info!("Successfully connected to WiFi network via hidden retry");
                return Ok(());
            }

            let hidden_stderr = String::from_utf8_lossy(&hidden_output.stderr);
            let hidden_stdout = String::from_utf8_lossy(&hidden_output.stdout);
            last_error = format!("{} {}", hidden_stdout.trim(), hidden_stderr.trim())
                .trim()
                .to_string();
        }

        tracing::warn!(
            attempt,
            max_attempts,
            ssid = %ssid,
            error = %last_error,
            "WiFi connection attempt failed"
        );

        if attempt < max_attempts {
            tokio::time::sleep(std::time::Duration::from_secs(2)).await;
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

fn split_escaped_fields(line: &str, separator: char) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut escaped = false;

    for ch in line.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }

        if ch == '\\' {
            escaped = true;
            continue;
        }

        if ch == separator {
            fields.push(current);
            current = String::new();
            continue;
        }

        current.push(ch);
    }

    if escaped {
        current.push('\\');
    }
    fields.push(current);

    fields
}

async fn wait_for_interface_connection(
    interface: &str,
    timeout: std::time::Duration,
) -> Result<()> {
    let deadline = std::time::Instant::now() + timeout;

    loop {
        let output = tokio::process::Command::new("nmcli")
            .args(["-t", "-f", "GENERAL.STATE", "device", "show", interface])
            .output()
            .await
            .context("Failed to check interface state")?;

        if output.status.success() {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.contains("GENERAL.STATE:100") {
                return Ok(());
            }
        }

        if std::time::Instant::now() >= deadline {
            anyhow::bail!("Connection timed out waiting for interface to become connected");
        }

        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
    }
}

#[cfg(test)]
mod tests {
    use super::split_escaped_fields;

    #[test]
    fn splits_nmcli_line_with_escaped_separator() {
        let line = "My\\|SSID|76\\:d1\\:a9\\:a1\\:32\\:d1|88|2412|1|WPA2";
        let fields = split_escaped_fields(line, '|');

        assert_eq!(fields.len(), 6);
        assert_eq!(fields[0], "My|SSID");
        assert_eq!(fields[1], "76:d1:a9:a1:32:d1");
        assert_eq!(fields[2], "88");
    }
}
