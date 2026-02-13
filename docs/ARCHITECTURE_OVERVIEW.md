# Hyper Recovery Architecture Overview

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    HYPER RECOVERY SYSTEM                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      BOOT SEQUENCE                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. GRUB Bootloader (theme: snosu-grub-theme)                   │
│     ├─ Colors: #cfcfcf (items), #ffffff (selected)              │
│     ├─ Font: Undefined Medium 28pt                              │
│     └─ Background: hyper-recovery-grub-bg.png                   │
│                                                                   │
│  2. Kernel Load + Initrd                                         │
│     ├─ Modules: i915, amdgpu, nouveau, virtio_gpu               │
│     ├─ Storage: nvme, ahci, xhci_pci, usb_storage               │
│     └─ Filesystems: zfs, exfat, vfat, iso9660, squashfs         │
│                                                                   │
│  3. Plymouth Boot Splash (theme: snosu-hyper-recovery)          │
│     ├─ Animation: 120 frames @ 24fps                            │
│     ├─ Background: hyper-recovery-bg.png                        │
│     ├─ Progress Bar: hyper-recovery-progress-bar.png            │
│     └─ Font: Undefined Medium 14pt                              │
│                                                                   │
│  4. Systemd Init                                                 │
│     ├─ systemd-journald.service                                 │
│     ├─ network-online.target                                    │
│     ├─ multi-user.target                                        │
│     └─ [Services start here]                                    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    SYSTEM SERVICES                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ NETWORKING (base.nix)                                   │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ • NetworkManager (enabled)                              │    │
│  │ • dhcpcd (disabled)                                     │    │
│  │ • wpa_supplicant (available)                            │    │
│  │ • iw (WiFi management)                                  │    │
│  │ • nmcli (NetworkManager CLI)                            │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ VIRTUALIZATION (services.nix)                           │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ • libvirtd (KVM/QEMU)                                   │    │
│  │ • swtpm (TPM emulation)                                 │    │
│  │ • Cockpit (Web UI @ :9090)                              │    │
│  │   ├─ cockpit-machines                                   │    │
│  │   ├─ cockpit-zfs                                        │    │
│  │   └─ cockpit-files                                      │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ SSH (base.nix)                                          │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ • OpenSSH enabled                                       │    │
│  │ • PermitRootLogin: yes                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ DEBUG SERVICES (debug.nix - optional)                   │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ • save-boot-logs (oneshot)                              │    │
│  │ • hyper-debug-serial (oneshot)                          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    CUSTOM SCRIPTS                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ hyper-debug (Python)                                    │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ Collects:                                               │    │
│  │ • System info (uname, os-release, cmdline)              │    │
│  │ • Hardware info (lspci, lsusb, dmidecode)               │    │
│  │ • Storage info (lsblk, zfs list, mdadm)                 │    │
│  │ • Network info (ip, nmcli, ethtool)                     │    │
│  │ • Kernel logs (dmesg, journalctl)                       │    │
│  │ • Plymouth logs (if available)                          │    │
│  │ • Systemd logs (journalctl)                             │    │
│  │ • Mounts (mount, df)                                    │    │
│  │ • Processes (ps, systemctl)                             │    │
│  │                                                          │    │
│  │ Output: /tmp/hyper-debug-<timestamp>/                   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ hyper-hw (Python)                                       │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ Manages:                                                │    │
│  │ • Firmware switching (core ↔ full)                      │    │
│  │ • Uses firmware_class.path sysfs parameter              │    │
│  │ • Non-persistent across reboot                          │    │
│  │                                                          │    │
│  │ Commands:                                               │    │
│  │ • hyper-hw firmware core                                │    │
│  │ • hyper-hw firmware full                                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ hyper-debug-serial (Python)                             │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ Outputs diagnostics to serial console (/dev/ttyS0)      │    │
│  │ Useful for headless systems                             │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ save-boot-logs (Python)                                 │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ Saves boot logs to Ventoy USB partition                 │    │
│  │ Runs as systemd service (oneshot)                       │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    BRANDING & THEMING                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ COLOR PALETTE                                           │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ Primary:     #0ea1fb (Blue)                             │    │
│  │ Accent:      #48d7fb (Cyan)                             │    │
│  │ Background:  #070c19 (Dark Navy)                        │    │
│  │ Text:        #15223b (Dark Text)                        │    │
│  │ Error:       #e94a57 (Coral)                            │    │
│  │ Warning:     #efbe1d (Gold)                             │    │
│  │ Gradient:    #070c19 → #111d34 → #150562               │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ FONTS                                                   │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ GRUB:       Undefined Medium 28pt                       │    │
│  │ Plymouth:   Undefined Medium 14pt                       │    │
│  │ Cockpit:    PatternFly defaults (CSS overrides)         │    │
│  │ Terminal:   System Sans                                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ COCKPIT WEB UI (branding.nix)                           │    │
│  ├─────────────────────────────────────────────────────────┤    │
│  │ • Login Title: "SNOSU Hyper Recovery"                   │    │
│  │ • Logo: logo-source.png                                 │    │
│  │ • CSS: branding.css (PatternFly v5/v6 compatible)       │    │
│  │ • Favicon: logo-source.png                              │    │
│  │ • Sidebar: Dark gradient background                     │    │
│  │ • Header: Shell gradient (#070c19 → #150562)            │    │
│  │ • Links: #0b6bd3 (light), #69cbff (dark)                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    NIX MODULE STRUCTURE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  nix/modules/system/                                             │
│  ├─ base.nix              (Core system, networking, packages)    │
│  ├─ hardware.nix          (Kernel, firmware, drivers)            │
│  ├─ branding.nix          (Plymouth, GRUB, Cockpit themes)       │
│  ├─ services.nix          (Cockpit, virtualization)              │
│  └─ debug.nix             (Debug logging, services)              │
│                                                                   │
│  nix/modules/iso/                                                │
│  ├─ base.nix              (Common ISO settings)                  │
│  └─ grub-bootloader.nix   (GRUB configuration)                   │
│                                                                   │
│  nix/flake/                                              │
│  ├─ packages.nix          (Package definitions)                  │
│  ├─ images.nix            (NixOS configurations)                 │
│  ├─ apps.nix              (CLI apps)                             │
│  └─ devshells.nix         (Dev environments)                     │
│                                                                   │
│  nix/packages/                                                   │
│  ├─ scripts/default.nix   (Script packaging helper)              │
│  ├─ themes/               (Plymouth, GRUB themes)                │
│  └─ firmware.nix          (Firmware packages)                    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    BUILD PROCESS                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  flake.nix                                                       │
│    ↓                                                              │
│  nix/flake/images.nix                                    │
│    ├─ usb-live (regular)                                         │
│    └─ usb-live-debug (with debug overlay)                        │
│    ↓                                                              │
│  Module Composition:                                             │
│    ├─ base.nix                                                   │
│    ├─ hardware.nix                                               │
│    ├─ branding.nix                                               │
│    ├─ services.nix                                               │
│    ├─ [debug.nix] (optional)                                     │
│    ├─ iso-base.nix                                               │
│    └─ iso-grub-bootloader.nix                                    │
│    ↓                                                              │
│  NixOS System Build                                              │
│    ├─ Evaluate all modules                                       │
│    ├─ Build packages                                             │
│    ├─ Create ISO image                                           │
│    └─ Apply GRUB theme                                           │
│    ↓                                                              │
│  Output: result/iso/snosu-hyper-recovery-*.iso                   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    DEPLOYMENT                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Option 1: Direct Write (dd)                                     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ sudo dd if=result/iso/snosu-hyper-recovery-*.iso \      │    │
│  │         of=/dev/sdX bs=4M status=progress              │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  Option 2: Ventoy (Recommended)                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ 1. Install Ventoy on USB                                │    │
│  │ 2. Copy ISO to Ventoy partition                         │    │
│  │ 3. Boot from USB → Ventoy menu                          │    │
│  │ 4. Select Hyper Recovery                                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  Boot Modes:                                                     │
│  • BIOS/Legacy: GRUB with hybrid MBR                             │
│  • UEFI: GRUB at /EFI/BOOT/bootx64.efi                           │
│  • Ventoy: Chainloads from either mode                           │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Module Dependency Graph

```
flake.nix
  ↓
images.nix (usb-live, usb-live-debug)
  ├─ base.nix
  │   ├─ Networking (NetworkManager)
  │   ├─ Users (snosu/nixos)
  │   ├─ SSH (OpenSSH)
  │   └─ Packages (hyper-debug, hyper-hw, etc.)
  │
  ├─ hardware.nix
  │   ├─ Kernel (linuxPackages)
  │   ├─ Kernel modules (i915, amdgpu, nvme, etc.)
  │   └─ Firmware (wireless-regdb, hyperFirmwareCore)
  │
  ├─ branding.nix
  │   ├─ Plymouth (snosu-hyper-recovery theme)
  │   ├─ GRUB (snosu-grub-theme)
  │   └─ Cockpit (branding.css, logo.png)
  │
  ├─ services.nix
  │   ├─ Cockpit (libvirtd, cockpit-machines, etc.)
  │   └─ Virtualization (libvirtd, swtpm)
  │
  ├─ [debug.nix] (optional)
  │   ├─ Kernel params (verbose logging)
  │   ├─ Services (save-boot-logs, hyper-debug-serial)
  │   └─ Packages (debug scripts)
  │
  ├─ iso-base.nix
  │   ├─ ISO image settings
  │   ├─ Compression (zstd)
  │   └─ Boot modes (BIOS, EFI, USB)
  │
  └─ iso-grub-bootloader.nix
      └─ GRUB configuration
```

## Service Startup Order

```
systemd-journald.service
  ↓
network-online.target
  ├─ NetworkManager
  ├─ systemd-networkd
  └─ [WiFi setup service would go here]
  ↓
multi-user.target
  ├─ save-boot-logs (debug only)
  ├─ hyper-debug-serial (debug only)
  ├─ Cockpit
  ├─ libvirtd
  └─ SSH
  ↓
System Ready
```

## Key Integration Points for WiFi Setup Service

```
1. Script Location
   scripts/hyper-connect.py
   └─ Uses: nmcli, iw, subprocess

2. Package Definition
   nix/packages/scripts/default.nix
   └─ makePythonScript helper

3. Service Definition
   nix/modules/system/network.nix (new)
   └─ Type: oneshot
   └─ After: systemd-journald, network-online.target
   └─ Wants: network-online.target

4. Module Import
   nix/flake/images.nix
   └─ Add: self.nixosModules.network

5. System Packages (optional)
   nix/modules/system/base.nix
   └─ Add: scripts.hyper-connect

6. Control Plane (recommended)
   API Gateway (new)
   └─ Host "system control" endpoints (WiFi backend switching, libvirt helpers, etc.)
   └─ Prefer auth + auditing + a single surface over exposing these operations via the captive portal
```

---

**Architecture Version**: 1.0
**Last Updated**: 2026-02-10
**NixOS Version**: 25.05
