# Super NixOS Utilities: Hyper Recovery

<p align="center">
  <img src="./super-nixos-utils-hyper-recovery-logo.png" alt="Super NixOS Utilities Hyper Recovery Logo">
</p>

This repository contains a Nix Flake to generate a portable hypervisor USB system based on NixOS.

## Features
- **Portable Hypervisor Platform**: Live USB system with KVM/QEMU/Libvirt
- **Hybrid Boot**: Works in both BIOS and EFI modes
- **Ventoy Compatible**: Can be copied to Ventoy partition or written directly to USB
- **Cockpit Management**: Web interface for managing VMs and system (Port 9090)
- **ZFS Support**: Includes ZFS kernel modules and tools
- **Rescue/Recovery**: Tools to import existing ZFS pools (Proxmox) and fix issues
- **Themed Boot**: Custom GRUB2 and Plymouth themes
- **Slim Firmware Core**: Ships a pruned firmware bundle by default, with an on-demand escape hatch

## What is Hyper Recovery?

Hyper Recovery is **not** a traditional live CD installer. It's a **portable hypervisor environment** that:
- Boots from USB on any computer (BIOS or EFI)
- Provides a hypervisor interface to boot local drives in VMs
- Includes recovery VMs like Clonezilla
- Does **not** persist computer-specific data on the USB
- Acts as a recovery and virtualization platform

## Building Images

You need a system with Nix installed and Flakes enabled.

### Hybrid USB Image (ISO format)

```bash
nix build .#usb
```

This produces a hybrid bootable ISO in `result/iso/` designed for USB deployment. Despite the `.iso` extension, this is a modern hybrid image that:
- Supports **both BIOS and EFI boot**
- Can be written directly to USB with `dd`
- Works with Ventoy
- Includes hybrid MBR for legacy systems

The "ISO" format is the industry standard for bootable USB images (used by SystemRescue, Clonezilla, NixOS installer, etc.).

### Debug Variant

```bash
nix build .#usb-debug
```

Debug variant with verbose logging and Plymouth debugging enabled.

### All Images + Compressed Artifacts

```bash
nix build .#images        # All images as symlinks
nix build .#images-7z     # Individual .7z files for each image
```

## Writing the USB Image

### Direct Write with dd (Linux/macOS)

```bash
# Find your USB device (e.g., /dev/sdb or /dev/disk2)
lsblk  # Linux
diskutil list  # macOS

# Write the ISO to USB (CAUTION: This will erase the USB drive!)
sudo dd if=result/iso/snosu-hyper-recovery-x86_64-linux.iso of=/dev/sdX bs=4M status=progress
sudo sync
```

### Using Etcher (All platforms)

1. Download [balenaEtcher](https://www.balena.io/etcher/)
2. Select `result/iso/snosu-hyper-recovery-x86_64-linux.iso`
3. Select your USB drive
4. Flash!

### Using Ventoy (Recommended for multi-boot USB)

1. Install [Ventoy](https://www.ventoy.net/) on your USB drive
2. Copy `result/iso/snosu-hyper-recovery-x86_64-linux.iso` to the Ventoy partition
3. Boot from the USB - Ventoy will present it in the boot menu
4. Works in both BIOS and EFI modes automatically

## Boot Modes

The ISO image is a **hybrid boot image** designed for USB:
- **BIOS/Legacy mode**: Uses GRUB with a hybrid MBR for USB drives
- **UEFI mode**: Uses GRUB installed to ESP at `/EFI/BOOT/bootx64.efi`
- **Ventoy**: Chainloads from either boot mode automatically
- **Works when dd'd to USB** or booted from Ventoy

## Usage

1.  **Boot**: Write to USB or copy to Ventoy partition
2.  **Login**:
    -   User: `snosu`
    -   Password: `nixos`
3.  **Cockpit**: Access `https://<IP_ADDRESS>:9090`
4.  **Firmware Compatibility (if hardware is missing)**:
    -   Default ISO includes a pruned firmware set to keep downloads small.
    -   If WiFi/GPU/NIC firmware is missing on your system, temporarily enable full firmware:
        ```bash
        sudo hyper-hw firmware full
        ```
    -   To revert to the core firmware path:
        ```bash
        sudo hyper-hw firmware core
        ```
5.  **ZFS Import**:
    -   Run `import-proxmox-pools` to scan
    -   Use `zpool import -f <poolname>` to force import if uncleanly unmounted
6.  **Booting Local Drives**:
    -   Use GRUB's OS detection (enabled by default)
    -   Boot local drives as VMs through Cockpit/libvirt
    -   Use the machine's BIOS/UEFI boot menu to chainload

## Troubleshooting

### Plymouth Boot Splash Not Showing

The system includes a custom Plymouth theme. If it doesn't display:
1. Try the debug boot menu entry (verbose logging enabled)
2. Check that your GPU supports KMS (Kernel Mode Setting)
3. Drivers included: i915 (Intel), amdgpu (AMD), nouveau (NVIDIA), radeon (old AMD)

## Theme Preview VM (macOS arm64)

For quick local iteration on the GRUB and Plymouth themes (without building the full ISO), run:

```bash
nix run .#theme-vm
```

This boots an Ubuntu ARM64 cloud VM in QEMU+HVF, syncs the themes from this repo into the VM,
and reboots once when changes are detected so you can see Plymouth.

### NixOS Base (more realistic)

If you want the guest to be NixOS (so GRUB/Plymouth wiring is closer to the real image), use:

```bash
nix run .#theme-vm -- --base nixos --fresh
```

The first boot will be the NixOS installer. Follow the instructions printed by `theme-vm`
(or open `README-NIXOS-INSTALL.txt` on the attached theme drive) to run the one-time install.
After that, you can just run:

```bash
nix run .#theme-vm -- --base nixos
```

### Boot Issues

- **BIOS mode not working**: Ensure the USB is bootable in legacy mode in BIOS settings
- **EFI mode not working**: Try disabling Secure Boot in UEFI settings
- **Ventoy not detecting**: Ensure the `.iso` file is in the root of the Ventoy partition

### Cockpit Login / Connection Failed

If the browser shows `Connection failed` after login, inspect the socket-activated Cockpit units
instead of only `journalctl -u cockpit`:

```bash
systemctl status cockpit.socket cockpit.service cockpit-wsinstance-http.service cockpit-session@*
journalctl -b -u cockpit.socket -u cockpit.service -u 'cockpit-wsinstance*' -u 'cockpit-session*' --no-pager
```

Also use `https://<IP_ADDRESS>:9090` (not `http://`) to avoid session/websocket issues on some clients.
