//! Access Point management using hostapd and dnsmasq

use anyhow::{bail, Context, Result};
use std::net::Ipv4Addr;
use std::process::Stdio;
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

    prepare_device_for_ap(interface).await;

    // Bring interface down, set mode, bring up
    let _ = Command::new("ip")
        .args(["link", "set", interface, "down"])
        .output()
        .await;

    // Configure IP address
    let _ = Command::new("ip")
        .args(["addr", "flush", "dev", interface])
        .output()
        .await;

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
listen-address={}
bind-interfaces
dhcp-leasefile={}/dnsmasq.leases
pid-file={}/dnsmasq.pid
dhcp-range={},{},255.255.255.0,12h
dhcp-option=option:router,{}
dhcp-option=option:dns-server,{}
address=/#/{}
"#,
        interface, ap_ip, RUNTIME_DIR, RUNTIME_DIR, dhcp_start, dhcp_end, ap_ip, ap_ip, ap_ip
    );

    tokio::fs::write(DNSMASQ_CONF_PATH, &dnsmasq_conf)
        .await
        .context("Failed to write dnsmasq config")?;

    // Start hostapd
    tracing::info!("Starting hostapd");
    let mut hostapd = Command::new("hostapd")
        .arg("-d")
        .arg(HOSTAPD_CONF_PATH)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
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

    // Start dnsmasq
    tracing::info!("Starting dnsmasq");
    let mut dnsmasq = Command::new("dnsmasq")
        .arg("--keep-in-foreground")
        .arg("--no-daemon")
        .arg(&format!("--conf-file={}", DNSMASQ_CONF_PATH))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
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

async fn prepare_device_for_ap(interface: &str) {
    let Ok(connection) = Connection::system().await else {
        return;
    };
    let Ok(nm_proxy) = zbus::Proxy::new(&connection, NM_DEST, NM_PATH, NM_IFACE).await else {
        return;
    };
    let Ok(device_path) = nm_proxy
        .call::<_, _, zvariant::OwnedObjectPath>("GetDeviceByIpIface", &(interface,))
        .await
    else {
        return;
    };
    let Ok(device_proxy) =
        zbus::Proxy::new(&connection, NM_DEST, device_path.as_str(), NM_DEVICE_IFACE).await
    else {
        return;
    };

    let _ = device_proxy.set_property("Autoconnect", &false).await;
    let _ = device_proxy.call::<_, _, ()>("Disconnect", &()).await;
}
