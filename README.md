# Super NixOS Utilities: Hyper Recovery

<p align="center">
  <img src="./super-nixos-utils-hyper-recovery-logo.png" alt="Super NixOS Utilities Hyper Recovery Logo">
</p>

This repository contains a Nix Flake to generate a minimalist Hypervisor OS ISO based on NixOS.

## Features
- **Minimalist Hypervisor**: KVM/QEMU/Libvirt enabled.
- **Cockpit Management**: Web interface for managing VMs and system (Port 9090).
- **ZFS Support**: Includes ZFS kernel modules and tools.
- **Rescue/Recovery**: Tools to import existing ZFS pools (Proxmox) and fix issues.

## Building images

### ISO

You need a system with Nix installed and Flakes enabled.

```bash
nix build .#iso
```

The resulting ISO will be in `result/iso/`.

### USB

```bash
nix build .#usb
```

This produces a signed `raw-efi` image that can be written directly to a flash drive via `dd` (see `result/usb/`).

## Writing the USB image with Etcher or Ventoy

- **Etcher**: Pick `result/usb/raw-efi` as the source image, select the target drive, and flash following the usual validation prompts.
- **Ventoy**: Copy the `raw-efi` image into the Ventoy partition and boot from the USB stick; Ventoy will present it in the boot menu.

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
