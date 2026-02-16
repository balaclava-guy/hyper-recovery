# Super NixOS Utilities: Hyper Recovery

<p align="center">
  <img src="./assets/branding/logo/super-nixos-utils-hyper-recovery-logo.png" alt="Super NixOS Utilities Hyper Recovery Logo">
</p>

This repository contains a Nix Flake to generate a portable hypervisor USB system based on NixOS.

## Features
- **Portable Container & VM Platform**: Live USB system with Incus (LXC/LXD)
- **Hybrid Boot**: Works in both BIOS and EFI modes
- **Ventoy Compatible**: Can be copied to Ventoy partition or written directly to USB
- **LXConsole Management**: Web interface for managing containers and VMs (Port 5000)
- **ZFS Support**: Includes ZFS kernel modules and tools
- **Rescue/Recovery**: Tools to import existing ZFS pools (Proxmox) and fix issues
- **Themed Boot**: Custom GRUB2 and Plymouth themes
- **Slim Firmware Core**: Ships a pruned firmware bundle by default, with an on-demand escape hatch

## What is Hyper Recovery?

Hyper Recovery is **not** a traditional live CD installer. It's a **portable container and VM platform** that:
- Boots from USB on any computer (BIOS or EFI)
- Provides Incus for managing containers and VMs
- Includes recovery tools and container images
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
nix build .#image-all           # All images as symlinks
nix build .#image-compressed    # Compressed archive for regular image
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

## GitHub Actions Quick Controls

Workflow: `.github/workflows/build.yml`

### Manual runs (`Run workflow`)

- `mode=standard`: fetch/upload regular artifacts + run visual test
- `mode=debug`: fetch/upload regular + debug artifacts + run visual test
- `mode=preview`: run preview VM with standard ISO
- `mode=preview-debug`: run preview VM with debug ISO
- `mode=preview-only`: run preview VM only (skip fetch + visual)
- `mode=preview-only-debug`: run preview VM only with debug ISO

`preview_duration` controls how long the preview tunnel stays alive.

### Commit-triggered runs (`check_suite` from Garnix)

Add one of these tags to the commit message:

- `[debug]`: include debug artifact fetch/upload in the workflow
- `[ci-debug]`: same as `[debug]`, plus extract comprehensive debug logs from VM
- `[preview]`: run preview VM for that commit
- `[preview-debug]`: run preview VM using debug ISO (also enables debug artifacts)

Examples:

```text
fix: tweak boot args [debug]
fix: investigate plymouth issue [ci-debug]
feat: test live VM path [preview]
chore: validate debug boot path [preview-debug]
```

### CI Debug Log Collection

When you use `[debug]` or `[ci-debug]` in your commit message, the workflow will:

1. Build and boot the debug ISO in CI
2. Automatically run `hyper-ci-debug` inside the VM to collect:
   - System info (uname, OS release, kernel cmdline)
   - Block devices and mounts
   - Systemd service status (including failed services)
   - Plymouth configuration and status
   - Full journal logs (boot, Plymouth, LXConsole, WiFi, NetworkManager)
   - Kernel messages (dmesg)
   - Graphics/DRM information
   - Network configuration
   - GRUB configuration
3. Extract these logs from the VM via virtio-9p shared folder
4. Upload as `ci-debug-logs` artifact in GitHub Actions

This takes you out of the critical path - no need to manually run commands or extract logs. Just add `[ci-debug]` to your commit message and download the artifact when the workflow completes.

**Artifact structure:**
```
ci-debug-logs/
├── bios/           # Logs from BIOS boot test
├── efi/            # Logs from EFI boot test
└── debug-efi/      # Logs from debug ISO EFI boot test
    ├── SUMMARY.txt         # Quick overview
    ├── system-info.txt
    ├── journal.txt
    ├── journal-plymouth.txt
    ├── journal-lxconsole.txt
    ├── dmesg.txt
    ├── systemd-failed.txt
    ├── plymouth.txt
    ├── graphics.txt
    ├── network.txt
    ├── grub.txt
    └── ...
```

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
3.  **LXConsole**: Access `http://<IP_ADDRESS>:5000`
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
6.  **Managing Containers/VMs**:
    -   Use GRUB's OS detection (enabled by default)
    -   Create and manage containers/VMs through LXConsole web interface
    -   Use the machine's BIOS/UEFI boot menu to chainload local drives

## Developer Tools

### hyper-fetch-iso

Automated ISO deployment tool that fetches the latest ISO from GitHub Actions and copies it to a Ventoy mount point.

**Local mode** (copy to local Ventoy USB):

```bash
nix run .#hyper-fetch-iso -- --last-commit
```

**Remote mode** (transfer via SSH to remote box):

```bash
nix run .#hyper-fetch-iso -- --last-commit --remote-host 10.10.100.119
```

With custom remote Ventoy path:

```bash
nix run .#hyper-fetch-iso -- --last-commit \
  --remote-host 10.10.100.119 \
  --remote-ventoy-path /mnt/ventoy
```

See `docs/REMOTE_ISO_DEPLOYMENT.md` for detailed setup instructions.

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

### LXConsole Connection Issues

If you cannot access the LXConsole web interface, check the service status:

```bash
systemctl status lxconsole incus
journalctl -b -u lxconsole -u incus --no-pager
```

Ensure you're accessing `http://<IP_ADDRESS>:5000` (not `https://`).
