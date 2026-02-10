//! NetworkManager D-Bus integration

use super::NetworkInfo;
use anyhow::{Context, Result};
use std::collections::HashMap;
use zbus::Connection;
use zvariant::Value;

/// Check if we have network connectivity via NetworkManager
pub async fn check_connectivity() -> Result<bool> {
    let connection = Connection::system().await?;
    
    let proxy = zbus::Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
    ).await?;

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
        ).await?;

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
    
    // Use nmcli for simplicity - it handles the async scan properly
    let output = tokio::process::Command::new("nmcli")
        .args([
            "-t", "-f", "SSID,BSSID,SIGNAL,FREQ,CHAN,SECURITY",
            "device", "wifi", "list",
            "--rescan", "yes",
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
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() >= 6 {
            let ssid = parts[0].to_string();
            
            // Skip empty SSIDs and duplicates
            if ssid.is_empty() || seen_ssids.contains(&ssid) {
                continue;
            }
            seen_ssids.insert(ssid.clone());

            let signal: u8 = parts[2].parse().unwrap_or(0);
            let freq: u32 = parts[3]
                .trim_end_matches(" MHz")
                .parse()
                .unwrap_or(0);
            let channel: u8 = parts[4].parse().unwrap_or(0);
            let security = parts[5].to_string();
            let is_secured = !security.is_empty() && security != "--";

            networks.push(NetworkInfo {
                ssid,
                bssid: parts[1].to_string(),
                signal_strength: signal,
                frequency: freq,
                channel,
                is_secured,
                security_type: if is_secured { security } else { "Open".to_string() },
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

    // Small delay for NM to pick up the device
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    // Try to connect
    let output = tokio::process::Command::new("nmcli")
        .args([
            "device", "wifi", "connect", ssid,
            "password", password,
            "ifname", interface,
        ])
        .output()
        .await
        .context("Failed to run nmcli connect")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        anyhow::bail!("Connection failed: {} {}", stdout, stderr);
    }

    // Wait for connectivity
    let timeout = tokio::time::timeout(
        std::time::Duration::from_secs(30),
        wait_for_connectivity(),
    ).await;

    match timeout {
        Ok(Ok(())) => {
            tracing::info!("Successfully connected and got connectivity");
            Ok(())
        }
        Ok(Err(e)) => {
            anyhow::bail!("Connected but failed to verify: {}", e);
        }
        Err(_) => {
            anyhow::bail!("Connection timed out waiting for connectivity");
        }
    }
}

/// Create a WiFi connection profile via D-Bus
#[allow(dead_code)]
pub async fn create_wifi_connection_dbus(
    ssid: &str,
    password: &str,
) -> Result<String> {
    let connection = Connection::system().await?;
    
    let proxy = zbus::Proxy::new(
        &connection,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager/Settings",
        "org.freedesktop.NetworkManager.Settings",
    ).await?;

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
