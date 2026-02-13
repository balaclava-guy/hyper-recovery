# Remote ISO Deployment Setup

This guide describes how to configure a remote NixOS box for automated ISO deployment via the `hyper-fetch-iso.py` script.

## Overview

The `hyper-fetch-iso.py` script can transfer ISO files to a remote Ventoy mount point using SSH/SCP instead of copying to a local directory. This allows you to:

- Run ISO deployment from any machine with SSH access
- Avoid needing Ventoy USB connected to your local development machine
- Centralize ISO testing on a dedicated remote box

## Requirements

### Remote Box Setup

The remote box must have:

1. **SSH Access**: Key-based SSH authentication configured
2. **exFAT Support**: For Ventoy partition mounting
3. **Ventoy Mount Point**: Directory to mount Ventoy USB
4. **Sufficient Disk Space**: For ISO storage (typically 2-4GB per ISO)

### Installation Steps

#### 1. Install exfatprogs

Add to your NixOS configuration:

```nix
# In your NixOS configuration (e.g., /etc/nixos/configuration.nix)
{
  environment.systemPackages = with pkgs; [
    exfatprogs
  ];
}
```

Apply the configuration:

```bash
sudo nixos-rebuild switch
```

#### 2. Create Ventoy Mount Point

```bash
sudo mkdir -p /mnt/ventoy
```

#### 3. Verify SSH Access

From the machine running `hyper-fetch-iso.py`:

```bash
ssh 10.10.100.119
```

You should be able to connect without a password prompt (key-based auth).

#### 4. Connect Ventoy USB

Insert the Ventoy USB drive into the remote box and identify the partition:

```bash
lsblk
```

 Look for the exFAT data partition (typically the second partition, e.g., `/dev/sdb2` or `/dev/sdc2`).

#### 5. Mount Ventoy Partition

```bash
sudo mount /dev/sdX1 /mnt/ventoy
```

Replace `/dev/sdX1` with the appropriate Ventoy partition device.

Verify the mount:
```bash
ls /mnt/ventoy
```

You should see existing ISO files (if any).

## Usage

### Local Mode (Default)

Copy ISO to local Ventoy mount:

```bash
scripts/hyper-fetch-iso.py --last-commit
```

### Remote Mode

Transfer ISO to remote Ventoy mount:

```bash
scripts/hyper-fetch-iso.py --last-commit --remote-host 10.10.100.119
```

With custom Ventoy path:

```bash
scripts/hyper-fetch-iso.py --last-commit \
  --remote-host 10.10.100.119 \
  --remote-ventoy-path /mnt/ventoy
```

### Remote Mode with Watch

Monitor and wait for CI completion before transfer:

```bash
scripts/hyper-fetch-iso.py --watch --last-commit --remote-host 10.10.100.119
```

## Troubleshooting

### Transfer Fails with SSH Error

Verify SSH connectivity:
```bash
ssh 10.10.100.119 "echo 'SSH working'"
```

### Remote Mount Path Not Accessible

Verify mount point exists on remote:
```bash
ssh 10.10.100.119 "test -d /mnt/ventoy && echo 'Mount point exists'"
```

Check if Ventoy is mounted:
```bash
ssh 10.10.100.119 "mount | grep ventoy"
```

### exFAT Mount Fails

Ensure exfatprogs is installed:
```bash
ssh 10.10.100.119 "which mkfs.exfat"
```

If not installed, add to NixOS config and rebuild.

### Permission Denied Writing to Mount Point

Ensure mount point is writable:
```bash
ssh 10.10.100.119 "touch /mnt/ventoy/test"
```

If permissions issue, ensure Ventoy USB is mounted with write access.

## Advanced: Auto-Mount Ventoy

For convenience, you can configure NixOS to auto-mount Ventoy USB when inserted.

### Using udev Rules

Create `/etc/nixos/udev/rules.d/99-ventoy-automount.rules`:

```
# Auto-mount Ventoy USB
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="Ventoy", RUN+="/usr/bin/mount /dev/%k /mnt/ventoy"
ACTION=="remove", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="Ventoy", RUN+="/usr/bin/umount /mnt/ventoy"
```

Note: Adjust `ID_FS_LABEL` to match your Ventoy USB label.

### Using fileSystems Entry

Add to your NixOS configuration:

```nix
{
  # Requires Ventoy UUID - find with: lsblk -f
  fileSystems."/mnt/ventoy" = {
    device = "/dev/disk/by-uuid/VENTOY-UUID";
    fsType = "exfat";
    options = [ "nofail" ];  # Don't fail boot if USB not connected
  };
}
```

Replace `VENTOY-UUID` with your Ventoy partition UUID.

Rebuild NixOS:
```bash
sudo nixos-rebuild switch
```

## Security Notes

1. **SSH Keys**: Use dedicated SSH key for automated transfers
2. **File Permissions**: Ensure `/mnt/ventoy` has appropriate permissions
3. **Network Transfer**: All transfers occur over SSH (encrypted)
4. **Authentication**: Key-based auth is required (no password prompts)

## Performance

- Local copy: ~100-200 MB/s (USB 3.0)
- Remote transfer (via SSH): Depends on network speed, typically 50-100 MB/s on gigabit LAN
- Resume capability:	rsync supports interrupted transfer resume
