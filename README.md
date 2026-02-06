# Hypervisor OS Boot CD

This repository contains a Nix Flake to generate a minimalist Hypervisor OS ISO based on NixOS.

## Features
- **Minimalist Hypervisor**: KVM/QEMU/Libvirt enabled.
- **Cockpit Management**: Web interface for managing VMs and system (Port 9090).
- **ZFS Support**: Includes ZFS kernel modules and tools.
- **Rescue/Recovery**: Tools to import existing ZFS pools (Proxmox) and fix issues.

## Building the ISO

You need a system with Nix installed and Flakes enabled.

```bash
nix build .#iso
```

The resulting ISO will be in `result/iso/`.

## Usage

1.  **Boot**: Burn the ISO to USB or attach to a server.
2.  **Login**:
    -   User: `root`
    -   Password: `nixos`
3.  **Cockpit**: Access `https://<IP_ADDRESS>:9090`
4.  **ZFS Import**:
    -   Run `import-proxmox-pools` to scan.
    -   Use `zpool import -f <poolname>` to force import if uncleanly unmounted.
5.  **Booting Attached Drives**:
    -   The ISO boot menu (Systemd-boot/Syslinux) should detect other bootloaders.
    -   Alternatively, use the machine's BIOS/UEFI boot menu.
