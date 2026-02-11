# Hyper Recovery Codebase Exploration Report

## Executive Summary

This document provides a comprehensive analysis of the hyper-recovery codebase structure, patterns, and integration points for the new WiFi setup service.

---

## 1. NetworkManager Configuration in payload.nix

### Current Configuration (base.nix)

```nix
# Networking
networking.networkmanager.enable = true;
networking.dhcpcd.enable = false;

# Standard Packages (including user-facing diagnostic tools)
environment.systemPackages = with pkgs; [
  qemu-utils zfs parted gptfdisk htop vim git perl
  pciutils usbutils smartmontools nvme-cli os-prober efibootmgr
  wpa_supplicant dhcpcd udisks2
  networkmanager  # nmcli
  iw
  plymouth  # For Plymouth debugging
  scripts.hyper-debug  # User-triggered diagnostics
  scripts.hyper-hw     # Firmware management
];
```

**Key Points:**
- **NetworkManager is enabled** as the primary network manager
- **dhcpcd is disabled** (NetworkManager handles DHCP)
- **wpa_supplicant** is available for WiFi support
- **iw** is available for WiFi interface management
- **nmcli** (NetworkManager CLI) is available for scripting

### Integration Point for WiFi Setup Service
The WiFi setup service should:
1. Use `nmcli` for WiFi configuration (already available)
2. Depend on `network-online.target` (systemd target)
3. Run after `systemd-journald.service` and `network-online.target`
4. Be optional (not blocking boot if WiFi fails)

---

## 2. Service Definition & Startup Patterns

### Systemd Service Structure

The project uses **systemd services** defined in Nix modules. Example from `debug.nix`:

```nix
# Save boot logs to Ventoy USB
systemd.services.save-boot-logs = {
  description = "Save boot logs to Ventoy USB";
  wantedBy = [ "multi-user.target" ];
  after = [ "systemd-journald.service" "local-fs.target" ];
  
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${scripts.save-boot-logs}/bin/save-boot-logs";
  };
};

# Dump diagnostics to serial console
systemd.services.hyper-debug-serial = {
  description = "Dump hyper debug info to serial console";
  wantedBy = [ "multi-user.target" ];
  after = [ "systemd-journald.service" "network-online.target" ];
  wants = [ "network-online.target" ];
  
  serviceConfig = {
    Type = "oneshot";
    StandardOutput = "tty";
    StandardError = "tty";
    TTYPath = "/dev/ttyS0";
    TTYReset = "yes";
    TTYVHangup = "yes";
  };
  
  path = with pkgs; [
    coreutils
    util-linux
    systemd
    networkmanager
    plymouth
    scripts.hyper-debug
  ];
  
  script = ''
    set -euo pipefail
    echo "hyper-debug-serial: starting"
    ${scripts.hyper-debug-serial}/bin/hyper-debug-serial
    echo "hyper-debug-serial: done"
  '';
};
```

### Service Definition Patterns

**Key Patterns:**
1. **wantedBy**: Specifies when service should start (e.g., `multi-user.target`)
2. **after**: Specifies ordering dependencies
3. **wants**: Soft dependencies (service starts but doesn't block if dependency fails)
4. **Type**: 
   - `oneshot` = runs once and exits
   - `simple` = runs continuously
   - `notify` = waits for systemd notification
5. **path**: Makes binaries available in service's PATH
6. **script**: Inline shell script or reference to binary

### Recommended WiFi Setup Service Pattern

```nix
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
  };
  
  path = with pkgs; [
    coreutils
    networkmanager
    iw
  ];
};
```

---

## 3. Rust Package Integration

### Current Rust Status

**No Rust packages currently in the project.** All scripts are Python 3.

### How to Add Rust Packages

The project uses **Nix derivations** for packaging. For Rust, follow this pattern:

#### Option A: Simple Rust Binary (Cargo.toml in repo)

```nix
# nix/packages/wifi-setup.nix
{ pkgs, lib }:

pkgs.rustPlatform.buildRustPackage {
  pname = "hyper-wifi-setup";
  version = "1.0.0";
  
  src = ../../../src/hyper-wifi-setup;  # Path to Cargo.toml directory
  
  cargoLock = {
    lockFile = ../../../src/hyper-wifi-setup/Cargo.lock;
  };
  
  nativeBuildInputs = with pkgs; [
    pkg-config
  ];
  
  buildInputs = with pkgs; [
    # Add any C dependencies here
  ];
  
  meta = with lib; {
    description = "WiFi setup service for Hyper Recovery";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
```

#### Option B: Reference in packages.nix

```nix
# nix/flake/packages.nix
{
  perSystem = { pkgs, system, lib, ... }: {
    packages = lib.optionalAttrs pkgs.stdenv.isLinux {
      hyper-wifi-setup = pkgs.callPackage ../../packages/wifi-setup.nix {};
    };
  };
}
```

#### Option C: Include in System

```nix
# nix/modules/system/base.nix
let
  scripts = pkgs.callPackage ../../packages/scripts {};
  wifiSetup = pkgs.callPackage ../../packages/wifi-setup.nix {};
in
{
  environment.systemPackages = with pkgs; [
    # ... existing packages ...
    wifiSetup
  ];
}
```

---

## 4. Theming & Branding Approach

### Color Palette (from branding.css)

```css
:root {
  /* Primary Colors */
  --snosu-ink: #070c19;           /* Dark navy background */
  --snosu-ink-2: #111d34;         /* Lighter navy */
  --snosu-paper: #f4f7fc;         /* Light background */
  --snosu-panel: #ffffff;         /* White panels */
  --snosu-border: #d8e1f0;        /* Light border */
  
  /* Text Colors */
  --snosu-text: #15223b;          /* Dark text */
  --snosu-text-muted: #4c5d7b;    /* Muted text */
  
  /* Accent Colors */
  --snosu-blue: #0ea1fb;          /* Primary blue */
  --snosu-cyan: #48d7fb;          /* Cyan accent */
  --snosu-coral: #e94a57;         /* Error/warning red */
  --snosu-gold: #efbe1d;          /* Warning yellow */
  --snosu-violet: #150562;        /* Dark violet */
  
  /* Gradients */
  --snosu-shell-gradient: linear-gradient(100deg, #070c19 0%, #111d34 55%, #150562 100%);
}
```

### Theme Files Structure

```
assets/
├── branding/
│   ├── branding.css          # Cockpit UI styling
│   ├── branding.ini          # Branding metadata
│   └── logo-source.png       # Logo image
├── fonts/
│   ├── pixelcode/            # Pixel Code font family
│   └── undefined-medium/     # Undefined Medium font
├── grub/
│   └── hyper-recovery-grub-bg.png
├── plymouth/
│   ├── hyper-recovery-bg.png
│   ├── hyper-recovery-glow.png
│   ├── hyper-recovery-logo.png
│   ├── hyper-recovery-progress-bar.png
│   └── hyper-recovery-progress-frame.png
└── motd-logo.ansi           # Terminal MOTD logo

themes/
├── grub/
│   └── hyper-recovery/
│       ├── theme.txt        # GRUB theme config
│       ├── background.png
│       └── blob_*.png       # Selection indicators
└── plymouth/
    └── hyper-recovery/
        ├── snosu-hyper-recovery.plymouth
        ├── snosu-hyper-recovery.script
        └── animation/       # 120 animation frames
```

### Branding Configuration (branding.ini)

```ini
[Branding]
Name=SNOSU Hyper Recovery
Logo=logo.png
Css=branding.css
```

### Cockpit Branding Integration (branding.nix)

```nix
environment.etc = {
  "cockpit/branding/branding.css".source = "${brandingDir}/branding.css";
  "cockpit/branding/logo.png".source = "${brandingDir}/logo-source.png";
  "cockpit/branding/brand-large.png".source = "${brandingDir}/logo-source.png";
  "cockpit/branding/apple-touch-icon.png".source = "${brandingDir}/logo-source.png";
  "cockpit/branding/favicon.ico".source = "${brandingDir}/logo-source.png";
  
  # Legacy layout for compatibility
  "cockpit/branding/snosu/branding.ini".source = "${brandingDir}/branding.ini";
  "cockpit/branding/snosu/branding.css".source = "${brandingDir}/branding.css";
  "cockpit/branding/snosu/logo.png".source = "${brandingDir}/logo-source.png";
};
```

### GRUB Theme Configuration (theme.txt)

```
# Boot Menu (Right Side)
+ boot_menu {
    left = 50%
    width = 48%
    top = 22%
    height = 56%
    item_font = "Hyper Fighting Regular 28"
    item_color = "#cfcfcf"
    selected_item_color = "#ffffff"
    selected_item_pixmap_style = "blob_*.png"
}

# Progress Bar (Bottom Right)
+ progress_bar {
    id = "__timeout__"
    left = 52%
    top = 80%
    width = 46%
    height = 20
    fg_color = "#ffffff"
    bg_color = "#333333"
}
```

### Plymouth Theme Configuration (snosu-hyper-recovery.script)

```javascript
// Configuration
frame_count = 120;
fps = 24; 
min_loops = 1; 

// Font Configuration
font_name = "Sans";
font_size = 14;

// Screen dimensions
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

// Background
Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

// Load animation images
for (i = 1; i <= frame_count; i++)
  {
    images[i] = Image("animation/" + i + ".png");
  }
```

### Fonts Used

- **Plymouth/GRUB**: Undefined Medium (custom font)
- **Cockpit UI**: PatternFly defaults with CSS overrides
- **Terminal**: System default (Sans)

---

## 5. Custom Scripts & Binaries Structure

### Script Organization

```
scripts/
├── hyper-debug.py           # System diagnostics collector
├── hyper-debug-serial.py    # Serial console debug dumper
├── hyper-hw.py              # Hardware/firmware manager
├── save-boot-logs.py        # Boot log saver
├── generate_motd_ansi.py    # MOTD generator
├── generate_theme_assets.py # Theme asset generator
├── theme-vm                 # Theme VM launcher (binary)
└── shell/
    └── snosu-motd.sh        # MOTD shell script
```

### Script Packaging Pattern (scripts/default.nix)

```nix
{ pkgs, lib }:

let
  # Helper function to create a Python script package
  makePythonScript = { name, script, runtimeInputs ? [] }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1.0.0";
      
      dontUnpack = true;
      dontBuild = true;
      
      nativeBuildInputs = [ pkgs.makeWrapper ];
      
      installPhase = ''
        mkdir -p $out/bin
        cp ${script} $out/bin/${name}
        chmod +x $out/bin/${name}
        
        # Ensure it uses the packaged Python
        substituteInPlace $out/bin/${name} \
          --replace '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
        
        # Wrap with runtime dependencies in PATH
        ${lib.optionalString (runtimeInputs != []) ''
          wrapProgram $out/bin/${name} \
            --prefix PATH : ${lib.makeBinPath runtimeInputs}
        ''}
      '';
    };
in
{
  # User-facing diagnostic tool (included in regular build)
  hyper-debug = makePythonScript {
    name = "hyper-debug";
    script = ../../../scripts/hyper-debug.py;
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
      plymouth
      pciutils
      mount
      umount
    ];
  };
  
  # Hardware/firmware management tool
  hyper-hw = makePythonScript {
    name = "hyper-hw";
    script = ../../../scripts/hyper-hw.py;
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      nix
      kmod
    ];
  };
  
  # Debug-only: Serial console debug dumper
  hyper-debug-serial = makePythonScript {
    name = "hyper-debug-serial";
    script = ../../../scripts/hyper-debug-serial.py;
    runtimeInputs = with pkgs; [
      coreutils
    ];
  };
  
  # Debug-only: Automatic boot log saver
  save-boot-logs = makePythonScript {
    name = "save-boot-logs";
    script = ../../../scripts/save-boot-logs.py;
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
      mount
      umount
    ];
  };
}
```

### Example Script: hyper-debug.py

```python
#!/usr/bin/env python3
"""
hyper-debug: Collect system diagnostics for Hyper Recovery environment.

This script gathers comprehensive system information useful for debugging
boot issues, hardware problems, and system failures.

Usage:
    hyper-debug [--output-dir DIR]
"""

import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


def run_command(cmd: list[str], output_file: Path, description: str = "") -> None:
    """Run a command and save its output to a file."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )
        with output_file.open('w') as f:
            if result.stdout:
                f.write(result.stdout)
            if result.stderr:
                f.write(f"\n--- stderr ---\n{result.stderr}")
        if description:
            print(f"✓ {description}")
    except subprocess.TimeoutExpired:
        print(f"⚠ {description} timed out", file=sys.stderr)
    except FileNotFoundError:
        print(f"⚠ {' '.join(cmd)} not found, skipping", file=sys.stderr)
    except Exception as e:
        print(f"⚠ {description} failed: {e}", file=sys.stderr)
```

### Example Script: hyper-hw.py

```python
#!/usr/bin/env python3
"""
hyper-hw: Hardware firmware management for Hyper Recovery.

This tool allows runtime switching between minimal "core" firmware (included
in the ISO) and full "full" firmware (downloaded via network when needed).

Usage:
    hyper-hw firmware core    # Revert to core firmware
    hyper-hw firmware full    # Download and activate full linux-firmware
"""

SYSFS_PATH = Path("/sys/module/firmware_class/parameters/path")
STATE_DIR = Path("/run/hyper-hw")
BASE_PATH_FILE = STATE_DIR / "base-firmware-path"
OVERLAY_DIR = STATE_DIR / "firmware-overlay"
UNION_DIR = OVERLAY_DIR / "union"

# Default firmware path in NixOS activation scripts
DEFAULT_BASE_PATH = "/run/current-system/firmware/lib/firmware"
```

### Key Patterns for Custom Scripts

1. **Python 3 shebang**: `#!/usr/bin/env python3`
2. **Nix wrapping**: Substitutes shebang with packaged Python path
3. **Runtime dependencies**: Injected via `wrapProgram` and PATH
4. **Error handling**: Graceful failures with stderr output
5. **Logging**: Output to stdout/stderr captured by systemd journal

---

## 6. Project Structure & Module Organization

### Nix Module Hierarchy

```
nix/
├── modules/
│   ├── system/              # System configuration modules
│   │   ├── base.nix         # Core system (networking, users, packages)
│   │   ├── hardware.nix     # Kernel, firmware, drivers
│   │   ├── branding.nix     # Plymouth, GRUB, Cockpit themes
│   │   ├── services.nix     # Cockpit, virtualization
│   │   └── debug.nix        # Debug logging, services
│   ├── iso/                 # ISO image configuration
│   │   ├── base.nix         # Common ISO settings
│   │   └── grub-bootloader.nix
│   └── flake/               # Flake-parts modules
│       ├── packages.nix     # Package definitions
│       ├── images.nix       # NixOS configurations
│       ├── apps.nix         # CLI apps
│       └── devshells.nix    # Development shells
├── packages/
│   ├── scripts/
│   │   └── default.nix      # Script packaging
│   ├── themes/
│   │   ├── plymouth.nix
│   │   └── grub.nix
│   ├── firmware.nix
│   └── lib/
└── flake.nix                # Flake entry point
```

### Module Import Order (images.nix)

```nix
# Regular USB Live Image (Clean, production-ready)
usb-live = inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
    
    # Core system modules (clean, no debug)
    self.nixosModules.base
    self.nixosModules.hardware
    self.nixosModules.branding
    self.nixosModules.services
    
    # ISO image infrastructure
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
    self.nixosModules.iso-base
    
    # Regular image specifics
    {
      isoImage.volumeID = "HYPER_RECOVERY";
      image.fileName = "snosu-hyper-recovery-x86_64-linux.iso";
      isoImage.prependToMenuLabel = "START HYPER RECOVERY";
    }
  ];
};

# Debug USB Live Image (Regular + debug overlay)
usb-live-debug = inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
    
    # Core system modules (same as regular)
    self.nixosModules.base
    self.nixosModules.hardware
    self.nixosModules.branding
    self.nixosModules.services
    
    # Debug enhancements (the ONLY difference)
    self.nixosModules.debug
    
    # ISO image infrastructure
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
    self.nixosModules.iso-base
    
    # Debug image specifics
    {
      isoImage.volumeID = "HYPER_RECOVERY_DEBUG";
      image.fileName = "snosu-hyper-recovery-debug-x86_64-linux.iso";
      isoImage.prependToMenuLabel = "START HYPER RECOVERY (Debug)";
    }
  ];
};
```

---

## 7. Recommended Integration Points for WiFi Setup Service

### Option 1: Python Script (Recommended for Quick Integration)

**File**: `scripts/hyper-wifi-setup.py`

```python
#!/usr/bin/env python3
"""
hyper-wifi-setup: Interactive WiFi setup for Hyper Recovery.

Provides a simple interface to configure WiFi networks using nmcli.
"""

import subprocess
import sys
from pathlib import Path

def list_networks():
    """List available WiFi networks."""
    result = subprocess.run(
        ["nmcli", "device", "wifi", "list"],
        capture_output=True,
        text=True
    )
    return result.stdout

def connect_network(ssid: str, password: str):
    """Connect to a WiFi network."""
    result = subprocess.run(
        ["nmcli", "device", "wifi", "connect", ssid, "password", password],
        capture_output=True,
        text=True
    )
    return result.returncode == 0

if __name__ == "__main__":
    print("Available WiFi Networks:")
    print(list_networks())
```

**Integration in scripts/default.nix**:

```nix
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

### Option 2: Systemd Service (For Automatic Setup)

**File**: `nix/modules/system/network.nix` (new module)

```nix
{ config, pkgs, lib, ... }:

let
  scripts = pkgs.callPackage ../../packages/scripts {};
in
{
  # WiFi Setup Service
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

**Add to images.nix**:

```nix
modules = [
  # ... existing modules ...
  self.nixosModules.network  # Add this
];
```

### Option 3: Interactive TUI (For User-Friendly Setup)

Consider using a TUI library like:
- **Python**: `urwid` or `blessed`
- **Rust**: `crossterm` + `ratatui`

Example structure:

```python
#!/usr/bin/env python3
"""
hyper-wifi-setup: Interactive WiFi setup TUI.
"""

import subprocess
from blessed import Terminal

term = Terminal()

def show_menu():
    """Display interactive WiFi menu."""
    networks = get_available_networks()
    
    with term.location(0, 0):
        print(term.clear)
        print(term.bold("WiFi Setup for Hyper Recovery"))
        print()
        
        for i, network in enumerate(networks):
            print(f"{i+1}. {network['ssid']} ({network['signal']}%)")
        
        choice = input("\nSelect network (number): ")
        ssid = networks[int(choice)-1]['ssid']
        password = input("Password: ")
        
        connect_network(ssid, password)
```

### Integration Checklist

- [ ] Create `scripts/hyper-wifi-setup.py`
- [ ] Add to `nix/packages/scripts/default.nix`
- [ ] Create `nix/modules/system/network.nix` (optional)
- [ ] Add module to `nix/flake/images.nix`
- [ ] Include in `environment.systemPackages` in base.nix
- [ ] Test with `nix build .#usb`
- [ ] Verify service starts: `systemctl status hyper-wifi-setup`
- [ ] Test WiFi connection: `nmcli device wifi list`

---

## 8. Build & Deployment

### Building Images

```bash
# Regular image
nix build .#usb

# Debug image
nix build .#usb-debug

# All images
nix build .#image-all

# Compressed artifacts
nix build .#image-compressed
```

### Output Structure

```
result/iso/
├── snosu-hyper-recovery-x86_64-linux.iso
└── snosu-hyper-recovery-debug-x86_64-linux.iso
```

### Writing to USB

```bash
# Linux/macOS
sudo dd if=result/iso/snosu-hyper-recovery-x86_64-linux.iso of=/dev/sdX bs=4M status=progress

# Using Ventoy
cp result/iso/snosu-hyper-recovery-x86_64-linux.iso /path/to/ventoy/partition/
```

---

## 9. Key Files Reference

| File | Purpose |
|------|---------|
| `nix/modules/system/base.nix` | Core system config, networking, packages |
| `nix/modules/system/hardware.nix` | Kernel, firmware, drivers |
| `nix/modules/system/branding.nix` | Plymouth, GRUB, Cockpit themes |
| `nix/modules/system/services.nix` | Cockpit, virtualization services |
| `nix/modules/system/debug.nix` | Debug logging, debug services |
| `nix/flake/images.nix` | NixOS configurations, image builds |
| `nix/packages/scripts/default.nix` | Script packaging helper |
| `scripts/hyper-debug.py` | System diagnostics collector |
| `scripts/hyper-hw.py` | Hardware/firmware manager |
| `assets/branding/branding.css` | Cockpit UI styling |
| `themes/grub/hyper-recovery/theme.txt` | GRUB theme config |
| `themes/plymouth/hyper-recovery/snosu-hyper-recovery.script` | Plymouth animation |

---

## 10. Summary: WiFi Setup Service Implementation

### Recommended Approach

1. **Create Python script** (`scripts/hyper-wifi-setup.py`)
   - Use `nmcli` for WiFi operations
   - Provide both CLI and interactive modes
   - Handle errors gracefully

2. **Package in Nix** (`nix/packages/scripts/default.nix`)
   - Follow existing `makePythonScript` pattern
   - Include `networkmanager` and `iw` in runtimeInputs

3. **Create systemd service** (`nix/modules/system/network.nix`)
   - Type: `oneshot`
   - wantedBy: `multi-user.target`
   - after: `systemd-journald.service`, `network-online.target`
   - wants: `network-online.target` (soft dependency)

4. **Add to base configuration**
   - Import module in `images.nix`
   - Include script in `environment.systemPackages`

5. **Test & Verify**
   - Build: `nix build .#usb`
   - Boot and verify: `systemctl status hyper-wifi-setup`
   - Test WiFi: `nmcli device wifi list`

### Color Palette for UI (if needed)

- **Primary**: `#0ea1fb` (blue)
- **Accent**: `#48d7fb` (cyan)
- **Background**: `#070c19` (dark navy)
- **Text**: `#15223b` (dark text)
- **Error**: `#e94a57` (coral)

### Fonts Available

- **System**: Sans (default)
- **Monospace**: Available via system
- **Custom**: Undefined Medium (in assets)

---

## Appendix: File Locations

```
/Users/hassan/projects/hyper-recovery/
├── nix/
│   ├── modules/
│   │   ├── system/
│   │   │   ├── base.nix
│   │   │   ├── hardware.nix
│   │   │   ├── branding.nix
│   │   │   ├── services.nix
│   │   │   └── debug.nix
│   │   ├── iso/
│   │   │   ├── base.nix
│   │   │   └── grub-bootloader.nix
│   │   └── flake/
│   │       ├── packages.nix
│   │       ├── images.nix
│   │       ├── apps.nix
│   │       └── devshells.nix
│   ├── packages/
│   │   ├── scripts/
│   │   │   └── default.nix
│   │   ├── themes/
│   │   │   ├── plymouth.nix
│   │   │   └── grub.nix
│   │   └── firmware.nix
│   └── flake.nix
├── scripts/
│   ├── hyper-debug.py
│   ├── hyper-debug-serial.py
│   ├── hyper-hw.py
│   ├── save-boot-logs.py
│   ├── generate_motd_ansi.py
│   ├── generate_theme_assets.py
│   ├── theme-vm
│   └── shell/
│       └── snosu-motd.sh
├── assets/
│   ├── branding/
│   │   ├── branding.css
│   │   ├── branding.ini
│   │   └── logo-source.png
│   ├── fonts/
│   │   ├── pixelcode/
│   │   └── undefined-medium/
│   ├── grub/
│   │   └── hyper-recovery-grub-bg.png
│   ├── plymouth/
│   │   ├── hyper-recovery-bg.png
│   │   ├── hyper-recovery-glow.png
│   │   ├── hyper-recovery-logo.png
│   │   ├── hyper-recovery-progress-bar.png
│   │   └── hyper-recovery-progress-frame.png
│   └── motd-logo.ansi
├── themes/
│   ├── grub/
│   │   └── hyper-recovery/
│   │       ├── theme.txt
│   │       ├── background.png
│   │       └── blob_*.png
│   └── plymouth/
│       └── hyper-recovery/
│           ├── snosu-hyper-recovery.plymouth
│           ├── snosu-hyper-recovery.script
│           └── animation/
├── README.md
├── UPGRADE_NOTES.md
└── AGENTS.md
```

---

**Document Generated**: 2026-02-10
**Codebase Version**: NixOS 25.05
**Last Updated**: 2026-02-10
