# WiFi Setup Service Integration Guide

## Quick Reference

### 1. NetworkManager is Already Enabled ✓

```nix
# From nix/modules/system/base.nix
networking.networkmanager.enable = true;
networking.dhcpcd.enable = false;

# Available tools in PATH:
# - nmcli (NetworkManager CLI)
# - wpa_supplicant
# - iw (WiFi interface management)
```

### 2. Service Definition Template

```nix
# nix/modules/system/network.nix (new file)
{ config, pkgs, lib, ... }:

let
  scripts = pkgs.callPackage ../../packages/scripts {};
in
{
  systemd.services.hyper-wifi-setup = {
    description = "WiFi Setup Service for Hyper Recovery";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${scripts.hyper-wifi-setup}/bin/hyper-wifi-setup";
      StandardOutput = "journal";
      StandardError = "journal";
      RemainAfterExit = "yes";
    };
    
    path = with pkgs; [
      coreutils
      networkmanager
      iw
    ];
  };
}
```

### 3. Script Packaging Template

```nix
# nix/packages/scripts/default.nix (add to existing)
hyper-wifi-setup = makePythonScript {
  name = "hyper-wifi-setup";
  script = ../../../scripts/hyper-wifi-setup.py;
  runtimeInputs = with pkgs; [
    coreutils
    networkmanager
    iw
  ];
};
```

### 4. Python Script Template

```python
#!/usr/bin/env python3
"""
hyper-wifi-setup: WiFi setup for Hyper Recovery.
"""

import subprocess
import sys

def list_networks():
    """List available WiFi networks."""
    result = subprocess.run(
        ["nmcli", "device", "wifi", "list"],
        capture_output=True,
        text=True
    )
    print(result.stdout)

def connect(ssid: str, password: str):
    """Connect to WiFi network."""
    result = subprocess.run(
        ["nmcli", "device", "wifi", "connect", ssid, "password", password],
        capture_output=True,
        text=True
    )
    if result.returncode == 0:
        print(f"✓ Connected to {ssid}")
    else:
        print(f"✗ Failed to connect: {result.stderr}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        list_networks()
    else:
        ssid = sys.argv[1]
        password = sys.argv[2] if len(sys.argv) > 2 else ""
        connect(ssid, password)
```

### 5. Integration Checklist

- [ ] Create `scripts/hyper-wifi-setup.py`
- [ ] Add to `nix/packages/scripts/default.nix`
- [ ] Create `nix/modules/system/network.nix`
- [ ] Add to `nix/flake/images.nix`:
  ```nix
  modules = [
    self.nixosModules.base
    self.nixosModules.hardware
    self.nixosModules.branding
    self.nixosModules.services
    self.nixosModules.network  # ← Add this
    # ... rest of modules
  ];
  ```
- [ ] Add to `nix/modules/system/base.nix` (optional):
  ```nix
  environment.systemPackages = with pkgs; [
    # ... existing packages ...
    scripts.hyper-wifi-setup
  ];
  ```
- [ ] Build: `nix build .#usb`
- [ ] Test: Boot and run `systemctl status hyper-wifi-setup`

## Color Palette (if UI needed)

```css
--snosu-blue: #0ea1fb;      /* Primary */
--snosu-cyan: #48d7fb;      /* Accent */
--snosu-coral: #e94a57;     /* Error */
--snosu-gold: #efbe1d;      /* Warning */
--snosu-ink: #070c19;       /* Background */
--snosu-text: #15223b;      /* Text */
```

## Available Commands

```bash
# List WiFi networks
nmcli device wifi list

# Connect to network
nmcli device wifi connect "SSID" password "PASSWORD"

# Show connection status
nmcli connection show

# Disconnect
nmcli device disconnect wlan0

# Show device info
nmcli device show
```

## Service Lifecycle

```
Boot
  ↓
systemd-journald.service starts
  ↓
network-online.target reached
  ↓
hyper-wifi-setup service starts (Type=oneshot)
  ↓
Script runs, configures WiFi
  ↓
Service exits (RemainAfterExit=yes keeps it "active")
  ↓
multi-user.target reached
  ↓
System ready
```

## Debugging

```bash
# Check service status
systemctl status hyper-wifi-setup

# View service logs
journalctl -u hyper-wifi-setup -n 50

# Run script manually
/run/current-system/sw/bin/hyper-wifi-setup

# Check NetworkManager status
nmcli general status

# Monitor WiFi devices
nmcli device
```

## Key Files

| File | Purpose |
|------|---------|
| `scripts/hyper-wifi-setup.py` | Main WiFi setup script |
| `nix/packages/scripts/default.nix` | Package definition |
| `nix/modules/system/network.nix` | Systemd service definition |
| `nix/flake/images.nix` | Module import |

## Notes

- **NetworkManager** is the primary network manager (dhcpcd is disabled)
- **nmcli** is the CLI tool for WiFi configuration
- Service runs **after** network-online.target but doesn't block boot
- Script output goes to **systemd journal** (view with `journalctl`)
- Service type is **oneshot** (runs once and exits)
- **RemainAfterExit=yes** keeps service marked as "active" after exit

