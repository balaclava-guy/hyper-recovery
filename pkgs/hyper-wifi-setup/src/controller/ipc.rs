//! IPC server for TUI client communication

use super::{AppState, ControlCommand};
use super::state::WifiStateSnapshot;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};

/// IPC request from client
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcRequest {
    GetStatus,
    Scan,
    Connect { ssid: String, password: String, #[serde(default = "default_save")] save: bool },
    Shutdown,
}

fn default_save() -> bool {
    true // Default to saving credentials
}

/// IPC response to client
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IpcResponse {
    Status(WifiStateSnapshot),
    Ok,
    Error(String),
}

/// Run the IPC server
pub async fn run_ipc_server(listener: UnixListener, state: Arc<AppState>) -> Result<()> {
    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let state = state.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_client(stream, state).await {
                        tracing::warn!(error = %e, "IPC client error");
                    }
                });
            }
            Err(e) => {
                tracing::error!(error = %e, "Failed to accept IPC connection");
            }
        }
    }
}

async fn handle_client(stream: UnixStream, state: Arc<AppState>) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    loop {
        line.clear();
        let n = reader.read_line(&mut line).await?;
        if n == 0 {
            break; // EOF
        }

        let request: IpcRequest = match serde_json::from_str(&line) {
            Ok(req) => req,
            Err(e) => {
                let response = IpcResponse::Error(format!("Invalid request: {}", e));
                let json = serde_json::to_string(&response)? + "\n";
                writer.write_all(json.as_bytes()).await?;
                continue;
            }
        };

        let response = match request {
            IpcRequest::GetStatus => {
                let wifi_state = state.wifi_state.read().await;
                IpcResponse::Status(WifiStateSnapshot::from(&*wifi_state))
            }
            IpcRequest::Scan => {
                let _ = state.command_tx.send(ControlCommand::Scan).await;
                IpcResponse::Ok
            }
            IpcRequest::Connect { ssid, password, save } => {
                let _ = state
                    .command_tx
                    .send(ControlCommand::Connect { ssid, password, save })
                    .await;
                IpcResponse::Ok
            }
            IpcRequest::Shutdown => {
                let _ = state.command_tx.send(ControlCommand::Shutdown).await;
                IpcResponse::Ok
            }
        };

        let json = serde_json::to_string(&response)? + "\n";
        writer.write_all(json.as_bytes()).await?;
    }

    Ok(())
}

/// Get status from daemon (client side)
pub async fn get_status(socket_path: &str) -> Result<WifiStateSnapshot> {
    let stream = UnixStream::connect(socket_path).await?;
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);

    let request = IpcRequest::GetStatus;
    let json = serde_json::to_string(&request)? + "\n";
    writer.write_all(json.as_bytes()).await?;

    let mut line = String::new();
    reader.read_line(&mut line).await?;

    let response: IpcResponse = serde_json::from_str(&line)?;
    match response {
        IpcResponse::Status(state) => Ok(state),
        IpcResponse::Error(e) => anyhow::bail!("Daemon error: {}", e),
        _ => anyhow::bail!("Unexpected response"),
    }
}

/// Send connect command to daemon (client side)
pub async fn send_connect(socket_path: &str, ssid: &str, password: &str, save: bool) -> Result<()> {
    let stream = UnixStream::connect(socket_path).await?;
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);

    let request = IpcRequest::Connect {
        ssid: ssid.to_string(),
        password: password.to_string(),
        save,
    };
    let json = serde_json::to_string(&request)? + "\n";
    writer.write_all(json.as_bytes()).await?;

    let mut line = String::new();
    reader.read_line(&mut line).await?;

    let response: IpcResponse = serde_json::from_str(&line)?;
    match response {
        IpcResponse::Ok => Ok(()),
        IpcResponse::Error(e) => anyhow::bail!("Daemon error: {}", e),
        _ => anyhow::bail!("Unexpected response"),
    }
}
