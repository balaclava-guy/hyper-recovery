//! Access Point management using hostapd and dnsmasq

use anyhow::{Context, Result};
use std::process::Stdio;
use tokio::process::{Child, Command};
use tokio::sync::OnceCell;
use std::sync::Mutex;

// Global handles for cleanup
static HOSTAPD_HANDLE: OnceCell<Mutex<Option<Child>>> = OnceCell::const_new();
static DNSMASQ_HANDLE: OnceCell<Mutex<Option<Child>>> = OnceCell::const_new();

/// Start the WiFi access point
pub async fn start_ap(interface: &str, ssid: &str, ap_ip: &str) -> Result<()> {
    tracing::info!(
        interface = %interface,
        ssid = %ssid,
        ip = %ap_ip,
        "Starting access point"
    );

    // Ensure interface is not managed by NetworkManager
    let _ = Command::new("nmcli")
        .args(["device", "set", interface, "managed", "no"])
        .output()
        .await;

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

    let hostapd_conf_path = "/tmp/hyper-hostapd.conf";
    tokio::fs::write(hostapd_conf_path, &hostapd_conf)
        .await
        .context("Failed to write hostapd config")?;

    // Create dnsmasq config
    let dnsmasq_conf = format!(
        r#"interface={}
listen-address={}
bind-interfaces
dhcp-range=192.168.42.10,192.168.42.250,255.255.255.0,12h
dhcp-option=option:router,{}
dhcp-option=option:dns-server,{}
address=/#/{}
"#,
        interface, ap_ip, ap_ip, ap_ip, ap_ip
    );

    let dnsmasq_conf_path = "/tmp/hyper-dnsmasq.conf";
    tokio::fs::write(dnsmasq_conf_path, &dnsmasq_conf)
        .await
        .context("Failed to write dnsmasq config")?;

    // Start hostapd
    tracing::info!("Starting hostapd");
    let hostapd = Command::new("hostapd")
        .arg("-d")
        .arg(hostapd_conf_path)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Failed to start hostapd")?;

    HOSTAPD_HANDLE
        .get_or_init(|| async { Mutex::new(Some(hostapd)) })
        .await;

    // Wait for hostapd to initialize
    tokio::time::sleep(std::time::Duration::from_secs(2)).await;

    // Start dnsmasq
    tracing::info!("Starting dnsmasq");
    let dnsmasq = Command::new("dnsmasq")
        .arg("--keep-in-foreground")
        .arg("--no-daemon")
        .arg(&format!("--conf-file={}", dnsmasq_conf_path))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .context("Failed to start dnsmasq")?;

    DNSMASQ_HANDLE
        .get_or_init(|| async { Mutex::new(Some(dnsmasq)) })
        .await;

    tracing::info!("Access point started successfully");
    Ok(())
}

/// Stop the access point
pub async fn stop_ap() -> Result<()> {
    tracing::info!("Stopping access point");

    // Kill dnsmasq
    if let Some(handle) = DNSMASQ_HANDLE.get() {
        if let Ok(mut guard) = handle.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill().await;
            }
        }
    }

    // Also kill any stray dnsmasq processes we started
    let _ = Command::new("pkill")
        .args(["-f", "hyper-dnsmasq.conf"])
        .output()
        .await;

    // Kill hostapd
    if let Some(handle) = HOSTAPD_HANDLE.get() {
        if let Ok(mut guard) = handle.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill().await;
            }
        }
    }

    // Also kill any stray hostapd processes
    let _ = Command::new("pkill")
        .args(["-f", "hyper-hostapd.conf"])
        .output()
        .await;

    // Clean up temp files
    let _ = tokio::fs::remove_file("/tmp/hyper-hostapd.conf").await;
    let _ = tokio::fs::remove_file("/tmp/hyper-dnsmasq.conf").await;

    tracing::info!("Access point stopped");
    Ok(())
}
