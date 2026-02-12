//! Saved WiFi credentials storage
//!
//! Stores WiFi credentials in a simple JSON file for auto-reconnection.
//!
//! Security considerations:
//! - Credentials are stored in plaintext on the filesystem
//! - The file is only readable by root (mode 0600)
//! - This is acceptable for a recovery environment where:
//!   - The system is ephemeral (live USB)
//!   - The user explicitly opts in to saving credentials
//!   - The alternative is re-entering credentials on every boot
//! - For persistent installations, consider using NetworkManager's
//!   built-in credential storage instead

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

/// Default path for saved credentials
pub const CREDENTIALS_PATH: &str = "/var/lib/hyper-connect/credentials.json";

/// Saved credentials for a network
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedCredential {
    pub ssid: String,
    pub password: String,
    /// When the credential was last used successfully
    #[serde(default)]
    pub last_used: Option<u64>,
    /// Number of successful connections
    #[serde(default)]
    pub success_count: u32,
}

/// Credentials store
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CredentialsStore {
    /// Map of SSID to credentials
    pub networks: HashMap<String, SavedCredential>,
    /// Version for future compatibility
    #[serde(default = "default_version")]
    pub version: u32,
}

fn default_version() -> u32 {
    1
}

impl CredentialsStore {
    /// Load credentials from disk
    pub fn load() -> Result<Self> {
        Self::load_from(CREDENTIALS_PATH)
    }

    /// Load credentials from a specific path
    pub fn load_from<P: AsRef<Path>>(path: P) -> Result<Self> {
        let path = path.as_ref();

        if !path.exists() {
            tracing::debug!(path = %path.display(), "No saved credentials file");
            return Ok(Self::default());
        }

        let content = fs::read_to_string(path).context("Failed to read credentials file")?;

        let store: Self =
            serde_json::from_str(&content).context("Failed to parse credentials file")?;

        tracing::info!(
            count = store.networks.len(),
            "Loaded saved WiFi credentials"
        );

        Ok(store)
    }

    /// Save credentials to disk
    pub fn save(&self) -> Result<()> {
        self.save_to(CREDENTIALS_PATH)
    }

    /// Save credentials to a specific path
    pub fn save_to<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let path = path.as_ref();

        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).context("Failed to create credentials directory")?;
        }

        let content =
            serde_json::to_string_pretty(self).context("Failed to serialize credentials")?;

        // Write to temp file first, then rename for atomicity
        let temp_path = path.with_extension("tmp");
        fs::write(&temp_path, &content).context("Failed to write credentials file")?;

        // Set restrictive permissions (root only)
        let mut perms = fs::metadata(&temp_path)?.permissions();
        perms.set_mode(0o600);
        fs::set_permissions(&temp_path, perms)?;

        // Atomic rename
        fs::rename(&temp_path, path).context("Failed to finalize credentials file")?;

        tracing::info!(
            path = %path.display(),
            count = self.networks.len(),
            "Saved WiFi credentials"
        );

        Ok(())
    }

    /// Add or update credentials for a network
    pub fn save_credential(&mut self, ssid: &str, password: &str) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        if let Some(existing) = self.networks.get_mut(ssid) {
            existing.password = password.to_string();
            existing.last_used = Some(now);
            existing.success_count += 1;
        } else {
            self.networks.insert(
                ssid.to_string(),
                SavedCredential {
                    ssid: ssid.to_string(),
                    password: password.to_string(),
                    last_used: Some(now),
                    success_count: 1,
                },
            );
        }
    }

    /// Get saved password for a network
    pub fn get_password(&self, ssid: &str) -> Option<&str> {
        self.networks.get(ssid).map(|c| c.password.as_str())
    }

    /// Check if we have credentials for a network
    pub fn has_credentials(&self, ssid: &str) -> bool {
        self.networks.contains_key(ssid)
    }

    /// Remove credentials for a network
    pub fn remove_credential(&mut self, ssid: &str) -> bool {
        self.networks.remove(ssid).is_some()
    }

    /// Find known networks from a list of available networks
    pub fn find_known_networks<'a>(
        &self,
        available: &'a [super::NetworkInfo],
    ) -> Vec<&'a super::NetworkInfo> {
        available
            .iter()
            .filter(|n| self.networks.contains_key(&n.ssid))
            .collect()
    }

    /// Get the best known network to auto-connect to
    /// Prioritizes by: signal strength, then success count
    pub fn best_known_network<'a>(
        &self,
        available: &'a [super::NetworkInfo],
    ) -> Option<&'a super::NetworkInfo> {
        let mut known: Vec<_> = self.find_known_networks(available);

        known.sort_by(|a, b| {
            // First by signal strength (descending)
            let signal_cmp = b.signal_strength.cmp(&a.signal_strength);
            if signal_cmp != std::cmp::Ordering::Equal {
                return signal_cmp;
            }

            // Then by success count (descending)
            let a_count = self
                .networks
                .get(&a.ssid)
                .map(|c| c.success_count)
                .unwrap_or(0);
            let b_count = self
                .networks
                .get(&b.ssid)
                .map(|c| c.success_count)
                .unwrap_or(0);
            b_count.cmp(&a_count)
        });

        known.into_iter().next()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_save_and_load() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("creds.json");

        let mut store = CredentialsStore::default();
        store.save_credential("TestNetwork", "password123");
        store.save_to(&path).unwrap();

        let loaded = CredentialsStore::load_from(&path).unwrap();
        assert_eq!(loaded.get_password("TestNetwork"), Some("password123"));
    }

    #[test]
    fn test_update_credential() {
        let mut store = CredentialsStore::default();
        store.save_credential("TestNetwork", "password1");
        store.save_credential("TestNetwork", "password2");

        assert_eq!(store.get_password("TestNetwork"), Some("password2"));
        assert_eq!(store.networks.get("TestNetwork").unwrap().success_count, 2);
    }
}
