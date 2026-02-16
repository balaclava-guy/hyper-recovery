# Migration Summary: Cockpit/Libvirt → Incus/LXConsole

**Date**: 2026-02-16
**Branch**: `incus-lxconsole`

## Overview

Successfully migrated Hyper Recovery from cockpit/libvirt to incus/lxconsole, introduced semantic versioning, and added Proxmox deployment workflow.

---

## 1. Cockpit/Libvirt Removal ✅

### Removed Components

**nix/modules/system/services.nix**
- All libvirtd configuration and socket settings
- libvirt-dbus setup and D-Bus policy
- cockpit service and plugins
- virtlogd configuration
- polkit rules for libvirt

**nix/modules/system/branding.nix**
- Cockpit branding assets (CSS, logos, favicons)
- Updated MOTD to reference port 5000 instead of 9090

**nix/modules/system/base.nix**
- Removed `libvirtd` and `libvirt` groups
- Removed `virt-manager` package
- Updated user groups to `incus-admin` instead of libvirt groups

**nix/modules/system/immutable-vms.nix**
- Removed libvirt network automation
- Repurposed for future incus automation

---

## 2. Incus/LXConsole Addition ✅

### Incus Configuration

**nix/modules/system/services.nix**
- Enabled `virtualisation.incus`
- Configured preseed with:
  - Network: `incusbr0` at `10.0.100.1/24` with NAT
  - Storage pool: `default` (dir-based)
  - Default profile: 50GB disk, eth0 on incusbr0
- Enabled nftables (required for incus)

### LXConsole Package

**nix/packages/lxconsole.nix** (NEW)
- Python Flask application from PenningLabs/lxconsole
- Version: unstable-2025-02-16
- Commit: `9aa95a1625ee03664edc177a6d369495b258d3fc`
- Hash: `sha256-dGfUf/ehus4d61DgR8G8m/Wy2Q4jFaYljBJPEUcq2+c=`

**nix/modules/system/services.nix**
- Systemd service with security hardening
- Dedicated `lxconsole` user in `incus-admin` group
- State directory: `/var/lib/lxconsole`
- Firewall: Port 5000 opened

---

## 3. Semantic Versioning System ✅

### Central Version File

**nix/version.nix** (NEW)
```nix
{
  version = "0.1.0";
  name = "hyper-recovery";
  fullName = "snosu-hyper-recovery";
  volumeId = "HYPER-RECOVERY";
  volumeIdDebug = "HYPER-RECOVERY-DEBUG";

  # Helper functions for naming
  mkBaseName = ...
  mkIsoName = ...
}
```

### Updated Files to Use Central Version

- **nix/flake/images.nix**: Image naming and volume IDs
- **nix/flake/packages.nix**: Theme-vm package
- **nix/packages/scripts/default.nix**: All scripts
- **nix/packages/themes/plymouth.nix**: Plymouth theme
- **nix/packages/themes/grub.nix**: GRUB theme
- **nix/packages/hyper-connect.nix**: WiFi daemon

### Versioned Filenames

**Before**: `snosu-hyper-recovery-x86_64-linux.iso`
**After**: `snosu-hyper-recovery-0.1.0-x86_64-linux.iso`

**Before**: `hyper-recovery-live.iso.7z`
**After**: `snosu-hyper-recovery-0.1.0.iso.7z`

---

## 4. Proxmox Deployment Workflow ✅

### Deployment Script

**scripts/deploy-to-proxmox.py** (NEW)

Automated workflow:
1. **Build**: Uses remote x86 builder (`nixos-builder-x86.xjn.io`)
2. **Transfer**: Copies ISO to Proxmox `/var/lib/vz/template/iso/`
3. **Create VMs**: Auto-creates/updates test VMs
   - VM 9001: BIOS/SeaBIOS mode
   - VM 9002: UEFI/OVMF mode
4. **Mount ISO**: Attaches newly built ISO to both VMs

### Flake Integration

**nix/flake/apps.nix**
- New app: `deploy-to-proxmox`
- Usage: `nix run .#deploy-to-proxmox`

**nix/flake/packages.nix**
- Package: `deploy-to-proxmox`

**nix/flake/devshells.nix**
- Command: `deploy-proxmox`
- Command: `deploy-proxmox-debug`

### Usage Examples

```bash
# Standard deployment
nix run .#deploy-to-proxmox

# Debug variant
nix run .#deploy-to-proxmox -- --debug

# Custom Proxmox host
nix run .#deploy-to-proxmox -- --proxmox-host 192.168.1.100

# Build only (skip deployment)
nix run .#deploy-to-proxmox -- --build-only

# Skip build (use existing result/)
nix run .#deploy-to-proxmox -- --skip-build

# Custom VM IDs
nix run .#deploy-to-proxmox -- --vmid-bios 8001 --vmid-uefi 8002
```

---

## 5. Documentation Updates ✅

### README.md
- Updated features list: cockpit → lxconsole
- Updated port references: 9090 → 5000
- Updated usage instructions
- Updated troubleshooting section

### CLAUDE.md / AGENTS.md
- Added versioning section
- Added Proxmox deployment section
- Updated project overview
- Updated file structure
- Updated command aliases

---

## Files Changed

```
Modified:
  AGENTS.md
  README.md
  nix/flake/apps.nix
  nix/flake/devshells.nix
  nix/flake/images.nix
  nix/flake/packages.nix
  nix/modules/system/base.nix
  nix/modules/system/branding.nix
  nix/modules/system/immutable-vms.nix
  nix/modules/system/services.nix
  nix/packages/hyper-connect.nix
  nix/packages/scripts/default.nix
  nix/packages/themes/grub.nix
  nix/packages/themes/plymouth.nix

New:
  nix/packages/lxconsole.nix
  nix/version.nix
  scripts/deploy-to-proxmox.py
```

---

## Testing Checklist

- [ ] Validate flake: `nix flake check`
- [ ] Build lxconsole package: `nix build .#lxconsole`
- [ ] Build USB image: `nix build .#usb`
- [ ] Test Proxmox deployment: `nix run .#deploy-to-proxmox --build-only`
- [ ] Verify version in image filename
- [ ] Boot BIOS VM and test lxconsole at port 5000
- [ ] Boot UEFI VM and test incus functionality

---

## Next Steps

1. **Test the migration**:
   ```bash
   nix build .#usb
   ls -lh result/iso/
   # Should see: snosu-hyper-recovery-0.1.0-x86_64-linux.iso
   ```

2. **Deploy to Proxmox**:
   ```bash
   deploy-proxmox
   # SSH to Proxmox and start VMs to test
   ```

3. **Verify incus works**:
   - Boot the image
   - Access lxconsole at http://IP:5000
   - Create a test container
   - Verify incus CLI works: `incus list`

4. **Update memory notes** if new issues are discovered

---

## Breaking Changes

⚠️ **Port Change**: Web UI moved from 9090 (cockpit) to 5000 (lxconsole)
⚠️ **Technology Stack**: libvirt → incus (different VM/container API)
⚠️ **User Groups**: `libvirtd` → `incus-admin`

---

## Benefits

✅ **Lighter**: Incus is more lightweight than libvirt stack
✅ **Modern**: LXConsole provides better UX than cockpit-machines
✅ **Containers**: First-class LXC container support
✅ **Versioned**: Proper semantic versioning across project
✅ **Automated**: Proxmox deployment workflow for rapid testing
