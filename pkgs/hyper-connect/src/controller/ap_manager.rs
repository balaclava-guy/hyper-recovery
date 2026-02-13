//! Access Point management using hostapd and dnsmasq

use anyhow::{bail, Context, Result};
use std::net::Ipv4Addr;
use tokio::process::{Child, Command};
use tokio::sync::{Mutex, OnceCell};
use zbus::Connection;

// Global handles for cleanup
static HOSTAPD_HANDLE: OnceCell<Mutex<Option<Child>>> = OnceCell::const_new();
static DNSMASQ_HANDLE: OnceCell<Mutex<Option<Child>>> = OnceCell::const_new();
const RUNTIME_DIR: &str = "/run/hyper-connect";
const HOSTAPD_CONF_PATH: &str = "/run/hyper-connect/hyper-hostapd.conf";
const DNSMASQ_CONF_PATH: &str = "/run/hyper-connect/hyper-dnsmasq.conf";
const NM_DEST: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const NM_IFACE: &str = "org.freedesktop.NetworkManager";
const NM_DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device";

/// Start the WiFi access point
pub async fn start_ap(interface: &str, ssid: &str, ap_ip: &str) -> Result<()> {
    tracing::info!(
        interface = %interface,
        ssid = %ssid,
        ip = %ap_ip,
        "Starting access point"
    );

    let result = start_ap_inner(interface, ssid, ap_ip).await;
    if let Err(err) = result {
        tracing::warn!(error = %err, "AP start failed; attempting to restore WiFi services");
        let _ = stop_ap().await;
        let _ = restore_device_after_ap(interface).await;
        return Err(err);
    }

    Ok(())
}

async fn start_ap_inner(interface: &str, ssid: &str, ap_ip: &str) -> Result<()> {
    prepare_device_for_ap(interface).await?;

    // Put the interface into a clean state before hostapd touches it.
    let _ = Command::new("ip")
        .args(["link", "set", interface, "down"])
        .output()
        .await;
    let _ = Command::new("ip")
        .args(["addr", "flush", "dev", interface])
        .output()
        .await;

    // Create hostapd config
    let hostapd_conf = format!(
        r#"interface={}
driver=nl80211
ssid={}
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=0
"#,
        interface, ssid
    );

    tokio::fs::create_dir_all(RUNTIME_DIR)
        .await
        .context("Failed to create runtime directory")?;
    tokio::fs::write(HOSTAPD_CONF_PATH, &hostapd_conf)
        .await
        .context("Failed to write hostapd config")?;

    let ap_ip_addr: Ipv4Addr = ap_ip
        .parse()
        .with_context(|| format!("Invalid AP IP address: '{}'", ap_ip))?;
    let [a, b, c, _] = ap_ip_addr.octets();
    let dhcp_start = format!("{}.{}.{}.10", a, b, c);
    let dhcp_end = format!("{}.{}.{}.250", a, b, c);

    // Create dnsmasq config
    let dnsmasq_conf = format!(
        r#"interface={}
bind-dynamic
dhcp-leasefile={}/dnsmasq.leases
pid-file={}/dnsmasq.pid
dhcp-range={},{},255.255.255.0,12h
dhcp-option=option:router,{}
dhcp-option=option:dns-server,{}
address=/#/{}
"#,
        interface, RUNTIME_DIR, RUNTIME_DIR, dhcp_start, dhcp_end, ap_ip, ap_ip, ap_ip
    );

    tokio::fs::write(DNSMASQ_CONF_PATH, &dnsmasq_conf)
        .await
        .context("Failed to write dnsmasq config")?;

    // Start hostapd. It may toggle the interface state while switching to AP mode,
    // so we delay assigning the AP IP until hostapd is stable.
    tracing::info!("Starting hostapd");
    let mut hostapd = Command::new("hostapd")
        .arg("-d")
        .arg(HOSTAPD_CONF_PATH)
        .spawn()
        .context("Failed to start hostapd")?;

    // Wait for hostapd to initialize
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;

    if let Some(status) = hostapd
        .try_wait()
        .context("Failed to check hostapd process")?
    {
        bail!("hostapd exited early with status: {}", status);
    }

    let hostapd_handle = HOSTAPD_HANDLE
        .get_or_init(|| async { Mutex::new(None) })
        .await;
    {
        let mut guard = hostapd_handle.lock().await;
        *guard = Some(hostapd);
    }

    // Configure IP address after hostapd has taken control of the interface.
    Command::new("ip")
        .args(["addr", "add", &format!("{}/24", ap_ip), "dev", interface])
        .output()
        .await
        .context("Failed to set IP address")?;

    Command::new("ip")
        .args(["link", "set", interface, "up"])
        .output()
        .await
        .context("Failed to bring interface up")?;

    // Wait for the IP address to be fully assigned before starting dnsmasq.
    wait_for_ip_assignment(interface, ap_ip).await?;

    // Start dnsmasq
    tracing::info!("Starting dnsmasq");
    let mut dnsmasq = Command::new("dnsmasq")
        .arg("--keep-in-foreground")
        .arg("--no-daemon")
        .arg(&format!("--conf-file={}", DNSMASQ_CONF_PATH))
        .spawn()
        .context("Failed to start dnsmasq")?;

    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    if let Some(status) = dnsmasq
        .try_wait()
        .context("Failed to check dnsmasq process")?
    {
        let _ = stop_ap().await;
        bail!("dnsmasq exited early with status: {}", status);
    }

    let dnsmasq_handle = DNSMASQ_HANDLE
        .get_or_init(|| async { Mutex::new(None) })
        .await;
    {
        let mut guard = dnsmasq_handle.lock().await;
        *guard = Some(dnsmasq);
    }

    tracing::info!("Access point started successfully");
    Ok(())
}

async fn restore_device_after_ap(interface: &str) -> Result<()> {
    // Ensure iwd is available again for NetworkManager's WiFi backend.
    let _ = Command::new("systemctl")
        .args(["start", "iwd.service"])
        .output()
        .await;

    // Best-effort: re-enable NetworkManager management of this device.
    if let Ok(connection) = Connection::system().await {
        if let Ok(nm_proxy) = zbus::Proxy::new(&connection, NM_DEST, NM_PATH, NM_IFACE).await {
            if let Ok(device_path) = nm_proxy
                .call::<_, _, zvariant::OwnedObjectPath>("GetDeviceByIpIface", &(interface,))
                .await
            {
                if let Ok(device_proxy) =
                    zbus::Proxy::new(&connection, NM_DEST, device_path.as_str(), NM_DEVICE_IFACE)
                        .await
                {
                    let _ = device_proxy.set_property("Managed", &true).await;
                    let _ = device_proxy.set_property("Autoconnect", &true).await;
                }
            }
        }
    }

    Ok(())
}

/// Stop the access point
pub async fn stop_ap() -> Result<()> {
    tracing::info!("Stopping access point");

    // Kill dnsmasq
    if let Some(handle) = DNSMASQ_HANDLE.get() {
        let mut guard = handle.lock().await;
        if let Some(mut child) = guard.take() {
            let _ = child.kill().await;
        }
    }

    // Also kill any stray dnsmasq processes we started
    let _ = Command::new("pkill")
        .args(["-f", DNSMASQ_CONF_PATH])
        .output()
        .await;

    // Kill hostapd
    if let Some(handle) = HOSTAPD_HANDLE.get() {
        let mut guard = handle.lock().await;
        if let Some(mut child) = guard.take() {
            let _ = child.kill().await;
        }
    }

    // Also kill any stray hostapd processes
    let _ = Command::new("pkill")
        .args(["-f", HOSTAPD_CONF_PATH])
        .output()
        .await;

    // Clean up temp files
    let _ = tokio::fs::remove_file(HOSTAPD_CONF_PATH).await;
    let _ = tokio::fs::remove_file(DNSMASQ_CONF_PATH).await;
    let _ = tokio::fs::remove_file("/run/hyper-connect/dnsmasq.leases").await;
    let _ = tokio::fs::remove_file("/run/hyper-connect/dnsmasq.pid").await;

    tracing::info!("Access point stopped");
    Ok(())
}

/// Wait for an IP address to be fully assigned to an interface.
async fn wait_for_ip_assignment(interface: &str, expected_ip: &str) -> Result<()> {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);

    while std::time::Instant::now() < deadline {
        let output = Command::new("ip")
            .args(["-4", "-o", "addr", "show", "dev", interface])
            .output()
            .await
            .context("Failed to check IP assignment")?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        if stdout.contains(expected_ip) {
            return Ok(());
        }

        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }

    bail!(
        "Timed out waiting for IP {} to be assigned to {}",
        expected_ip,
        interface
    );
}

async fn prepare_device_for_ap(interface: &str) -> Result<()> {
    // hostapd expects exclusive control of the nl80211 interface. In our images,
    // NetworkManager uses iwd as the WiFi backend, so both need to release the device.

    // Best-effort: tell NetworkManager to disconnect and stop managing this device.
    if let Ok(connection) = Connection::system().await {
        if let Ok(nm_proxy) = zbus::Proxy::new(&connection, NM_DEST, NM_PATH, NM_IFACE).await {
            if let Ok(device_path) = nm_proxy
                .call::<_, _, zvariant::OwnedObjectPath>("GetDeviceByIpIface", &(interface,))
                .await
            {
                if let Ok(device_proxy) =
                    zbus::Proxy::new(&connection, NM_DEST, device_path.as_str(), NM_DEVICE_IFACE)
                        .await
                {
                    let _ = device_proxy.set_property("Autoconnect", &false).await;
                    let _ = device_proxy.call::<_, _, ()>("Disconnect", &()).await;
                    let _ = device_proxy.set_property("Managed", &false).await;
                }
            }
        }
    }

    // Stop iwd and wait until it is actually inactive.
    tracing::debug!("Stopping iwd to release interface for hostapd");
    let _ = Command::new("systemctl")
        .args(["stop", "iwd.service"])
        .output()
        .await;

    wait_for_systemd_inactive("iwd.service", std::time::Duration::from_secs(6)).await?;
    wait_for_station_disconnect(interface, std::time::Duration::from_secs(6)).await?;
    Ok(())
}

async fn wait_for_systemd_inactive(unit: &str, timeout: std::time::Duration) -> Result<()> {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        let status = Command::new("systemctl")
            .args(["is-active", "--quiet", unit])
            .status()
            .await
            .with_context(|| format!("Failed to query systemd unit status for {}", unit))?;

        if !status.success() {
            return Ok(());
        }

        tokio::time::sleep(std::time::Duration::from_millis(120)).await;
    }

    bail!("Timed out waiting for systemd unit {} to stop", unit);
}

async fn wait_for_station_disconnect(interface: &str, timeout: std::time::Duration) -> Result<()> {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        let output = Command::new("iw")
            .args(["dev", interface, "link"])
            .output()
            .await
            .context("Failed to query WiFi link status")?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        if stdout.contains("Not connected") {
            return Ok(());
        }

        tokio::time::sleep(std::time::Duration::from_millis(120)).await;
    }

    bail!(
        "Timed out waiting for {} to disconnect from its current WiFi network",
        interface
    );
}
