# Hyper Recovery Codebase Exploration - Executive Summary

## Overview

This exploration analyzed the hyper-recovery codebase to understand its architecture, patterns, and integration points for a new WiFi setup service.

**Key Finding**: The codebase is well-structured with clear separation of concerns, making it straightforward to add new services.

---

## 1. NetworkManager Configuration ✓

**Status**: Already enabled and ready to use

```nix
# From nix/modules/system/base.nix
networking.networkmanager.enable = true;
networking.dhcpcd.enable = false;
```

**Available Tools**:
- `nmcli` - NetworkManager CLI (primary tool for WiFi setup)
- `wpa_supplicant` - WiFi authentication
- `iw` - WiFi interface management

**Integration**: WiFi setup service can use `nmcli` directly without additional dependencies.

---

## 2. Service Definition & Startup Patterns

### Pattern Used in Project

All services follow this structure:

```nix
systemd.services.<name> = {
  description = "...";
  wantedBy = [ "multi-user.target" ];
  after = [ "systemd-journald.service" "network-online.target" ];
  wants = [ "network-online.target" ];  # Soft dependency
  
  serviceConfig = {
    Type = "oneshot";  # or "simple"
    ExecStart = "${script}/bin/script-name";
    StandardOutput = "journal";
    StandardError = "journal";
  };
  
  path = with pkgs; [ /* runtime dependencies */ ];
};
```

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
    RemainAfterExit = "yes";
  };
  
  path = with pkgs; [ coreutils networkmanager iw ];
};
```

---

## 3. Rust Package Integration

**Current Status**: No Rust packages in project (all scripts are Python 3)

### How to Add Rust (if needed)

```nix
# nix/packages/wifi-setup.nix
{ pkgs, lib }:

pkgs.rustPlatform.buildRustPackage {
  pname = "hyper-wifi-setup";
  version = "1.0.0";
  src = ../../../src/hyper-wifi-setup;
  cargoLock = { lockFile = ../../../src/hyper-wifi-setup/Cargo.lock; };
  # ... rest of config
}
```

**Recommendation**: Use Python for consistency with existing scripts (hyper-debug.py, hyper-hw.py).

---

## 4. Theming & Branding

### Color Palette (SNOSU Brand)

| Color | Hex | Usage |
|-------|-----|-------|
| Primary Blue | `#0ea1fb` | Links, buttons, accents |
| Cyan | `#48d7fb` | Highlights, active states |
| Dark Navy | `#070c19` | Backgrounds |
| Dark Text | `#15223b` | Text content |
| Coral | `#e94a57` | Errors, warnings |
| Gold | `#efbe1d` | Warnings |

### Fonts

- **GRUB**: Undefined Medium 28pt
- **Plymouth**: Undefined Medium 14pt
- **Cockpit**: PatternFly defaults (CSS overrides)
- **Terminal**: System Sans

### Theme Files

```
assets/
├── branding/
│   ├── branding.css      # Cockpit UI styling
│   ├── branding.ini      # Metadata
│   └── logo-source.png   # Logo
├── fonts/
│   ├── pixelcode/        # Pixel Code font family
│   └── undefined-medium/ # Undefined Medium font
├── grub/
│   └── hyper-recovery-grub-bg.png
└── plymouth/
    ├── hyper-recovery-bg.png
    ├── hyper-recovery-logo.png
    ├── hyper-recovery-progress-bar.png
    └── animation/        # 120 animation frames
```

---

## 5. Custom Scripts & Binaries Structure

### Script Packaging Pattern

All scripts use a helper function in `nix/packages/scripts/default.nix`:

```nix
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
      
      # Substitute Python path
      substituteInPlace $out/bin/${name} \
        --replace '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
      
      # Wrap with runtime dependencies
      ${lib.optionalString (runtimeInputs != []) ''
        wrapProgram $out/bin/${name} \
          --prefix PATH : ${lib.makeBinPath runtimeInputs}
      ''}
    '';
  };
```

### Existing Scripts

| Script | Purpose | Type |
|--------|---------|------|
| `hyper-debug.py` | System diagnostics collector | User-facing |
| `hyper-hw.py` | Hardware/firmware manager | User-facing |
| `hyper-debug-serial.py` | Serial console debug dumper | Debug-only |
| `save-boot-logs.py` | Boot log saver | Debug-only |

---

## 6. Project Structure

### Nix Module Organization

```
nix/modules/
├── system/
│   ├── base.nix           # Core system, networking, packages
│   ├── hardware.nix       # Kernel, firmware, drivers
│   ├── branding.nix       # Plymouth, GRUB, Cockpit themes
│   ├── services.nix       # Cockpit, virtualization
│   └── debug.nix          # Debug logging, services
├── iso/
│   ├── base.nix           # Common ISO settings
│   └── grub-bootloader.nix
└── flake/
    ├── packages.nix       # Package definitions
    ├── images.nix         # NixOS configurations
    ├── apps.nix
    └── devshells.nix
```

### Module Import Order (images.nix)

```nix
modules = [
  self.nixosModules.base
  self.nixosModules.hardware
  self.nixosModules.branding
  self.nixosModules.services
  # [self.nixosModules.debug]  # Optional
  "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
  self.nixosModules.iso-base
];
```

---

## 7. WiFi Setup Service Integration Points

### Recommended Implementation Path

#### Step 1: Create Python Script
**File**: `scripts/hyper-wifi-setup.py`

```python
#!/usr/bin/env python3
"""WiFi setup for Hyper Recovery."""

import subprocess
import sys

def list_networks():
    result = subprocess.run(
        ["nmcli", "device", "wifi", "list"],
        capture_output=True, text=True
    )
    print(result.stdout)

def connect(ssid: str, password: str):
    result = subprocess.run(
        ["nmcli", "device", "wifi", "connect", ssid, "password", password],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"✓ Connected to {ssid}")
    else:
        print(f"✗ Failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        list_networks()
    else:
        connect(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
```

#### Step 2: Add to Script Packaging
**File**: `nix/packages/scripts/default.nix`

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

#### Step 3: Create Service Module
**File**: `nix/modules/system/network.nix` (new)

```nix
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
    
    path = with pkgs; [ coreutils networkmanager iw ];
  };
}
```

#### Step 4: Import Module
**File**: `nix/flake/images.nix`

```nix
modules = [
  self.nixosModules.base
  self.nixosModules.hardware
  self.nixosModules.branding
  self.nixosModules.services
  self.nixosModules.network  # ← Add this
  # ... rest
];
```

#### Step 5: Build & Test

```bash
# Build
nix build .#usb

# Boot and verify
systemctl status hyper-wifi-setup
journalctl -u hyper-wifi-setup -n 50

# Test WiFi
nmcli device wifi list
```

---

## 8. Key Files Reference

| File | Purpose | Lines |
|------|---------|-------|
| `nix/modules/system/base.nix` | Core system config | 65 |
| `nix/modules/system/hardware.nix` | Kernel, firmware | 66 |
| `nix/modules/system/branding.nix` | Themes | 89 |
| `nix/modules/system/services.nix` | Cockpit, virtualization | 37 |
| `nix/modules/system/debug.nix` | Debug services | 111 |
| `nix/flake/images.nix` | NixOS configs | 129 |
| `nix/packages/scripts/default.nix` | Script packaging | 83 |
| `scripts/hyper-debug.py` | Diagnostics | 300+ |
| `scripts/hyper-hw.py` | Firmware manager | 200+ |
| `assets/branding/branding.css` | Cockpit styling | 145 |

---

## 9. Build & Deployment

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

### Output

```
result/iso/
├── snosu-hyper-recovery-x86_64-linux.iso
└── snosu-hyper-recovery-debug-x86_64-linux.iso
```

### Writing to USB

```bash
# Direct write
sudo dd if=result/iso/snosu-hyper-recovery-x86_64-linux.iso \
         of=/dev/sdX bs=4M status=progress

# Or use Ventoy (recommended)
cp result/iso/snosu-hyper-recovery-x86_64-linux.iso /path/to/ventoy/
```

---

## 10. Summary: What You Need to Know

### ✓ Already Available
- NetworkManager enabled and configured
- nmcli, wpa_supplicant, iw tools available
- Python 3 environment with subprocess support
- Systemd service infrastructure
- Script packaging pattern established
- Branding/theming system in place

### ✓ Integration Points
1. **Script**: `scripts/hyper-wifi-setup.py`
2. **Package**: Add to `nix/packages/scripts/default.nix`
3. **Service**: Create `nix/modules/system/network.nix`
4. **Module**: Import in `nix/flake/images.nix`
5. **Build**: `nix build .#usb`

### ✓ Service Lifecycle
```
Boot → systemd-journald → network-online.target → 
hyper-wifi-setup (oneshot) → multi-user.target → Ready
```

### ✓ Testing
```bash
systemctl status hyper-wifi-setup
journalctl -u hyper-wifi-setup
nmcli device wifi list
```

---

## Documentation Generated

1. **CODEBASE_EXPLORATION.md** - Comprehensive technical analysis
2. **WIFI_SETUP_INTEGRATION_GUIDE.md** - Quick reference for implementation
3. **ARCHITECTURE_OVERVIEW.md** - Visual system architecture
4. **EXPLORATION_SUMMARY.md** - This document

---

## Next Steps

1. Create `scripts/hyper-wifi-setup.py` with desired functionality
2. Add to `nix/packages/scripts/default.nix`
3. Create `nix/modules/system/network.nix`
4. Update `nix/flake/images.nix` to import network module
5. Build: `nix build .#usb`
6. Test on actual hardware or VM

---

**Exploration Date**: 2026-02-10
**Codebase Version**: NixOS 25.05
**Status**: Ready for WiFi setup service implementation
