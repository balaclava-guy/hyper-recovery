# Immutable VMs with Linked Clones

## Overview

Hyper Recovery supports importing existing OS installations (like Proxmox VE) as VMs that can boot and run normally, while keeping the original installation completely untouched. This is achieved using QCOW2 overlay images with copy-on-write semantics.

## How It Works

### Linked Clone Architecture

```
┌─────────────────────────────────────┐
│  Original Disk (Read-Only Backing) │
│  /dev/nvme0n1 or /dev/sda           │
│  ▪ BIOS boot partition              │
│  ▪ EFI System partition             │
│  ▪ Root filesystem (LVM/ZFS)        │
└──────────────┬──────────────────────┘
               │ (read-only reference)
               ▼
┌─────────────────────────────────────┐
│  QCOW2 Overlay (Writable Layer)     │
│  /var/lib/libvirt/images/*.qcow2    │
│  ▪ Starts at ~200KB                 │
│  ▪ Grows with writes (CoW)          │
│  ▪ Can be deleted to reset          │
└─────────────────────────────────────┘
```

### Key Benefits

1. **Non-Destructive** - Original installation never modified
2. **Ephemeral Testing** - Test changes, revert by deleting overlay
3. **Space Efficient** - Only stores differences from original
4. **Fast Reset** - Delete overlay to return to pristine state
5. **Multiple Instances** - Create multiple overlays from same backing file

## Implementation Guide

### Prerequisites

- Physical disk with existing OS installation accessible (e.g., `/dev/sda`, `/dev/nvme0n1`)
- Disk must have complete boot structure:
  - BIOS boot partition (for legacy boot)
  - EFI System partition (for UEFI boot)
  - Root filesystem partition

### Step 1: Create QCOW2 Overlay

Use `qemu-img` to create an overlay that references the entire physical disk:

```bash
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1 \
  -F raw \
  /var/lib/libvirt/images/my-os-overlay.qcow2
```

**Important**: Use the **entire disk** (`/dev/nvme0n1`), not just the root partition (`/dev/nvme0n1p3`). The VM needs access to boot partitions to load the bootloader.

### Step 2: Boot with QEMU (Direct Method)

For immediate testing without libvirt:

```bash
sudo qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -m 4G \
  -smp 2 \
  -drive file=/var/lib/libvirt/images/my-os-overlay.qcow2,if=virtio \
  -nographic
```

Add networking and other devices as needed:

```bash
sudo qemu-system-x86_64 \
  -machine pc,accel=kvm \
  -m 4G \
  -smp 2 \
  -drive file=/var/lib/libvirt/images/my-os-overlay.qcow2,if=virtio \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -vnc :0
```

### Step 3: Create libvirt VM Definition

For integration with Cockpit and virsh:

```xml
<domain type='kvm'>
  <name>my-imported-os</name>
  <memory unit='KiB'>4194304</memory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/my-os-overlay.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <graphics type='vnc' port='-1' autoport='yes'/>
  </devices>
</domain>
```

Define the VM:

```bash
virsh define my-vm.xml
```

## Practical Example: Importing Proxmox VE

This is a real-world example from Hyper Recovery development.

### Discovery Phase

1. **Identify Proxmox installations:**
   ```bash
   # Import ZFS pool
   sudo zpool import -f rpool

   # Check for ZFS-based Proxmox
   zfs list | grep pve

   # Check for LVM-based Proxmox
   sudo lvs | grep pve
   ```

2. **Examine disk layout:**
   ```bash
   sudo fdisk -l /dev/nvme0n1
   sudo fdisk -l /dev/sda
   ```

   Output shows:
   ```
   /dev/nvme0n1p1    BIOS boot (1007K)
   /dev/nvme0n1p2    EFI System (1G)
   /dev/nvme0n1p3    Linux LVM (237.5G)  ← Proxmox root

   /dev/sda1         BIOS boot (1007K)
   /dev/sda2         EFI System (512M)
   /dev/sda3         ZFS (931G)          ← Proxmox root
   ```

### Common Mistake: Using Only Root Partition

❌ **This will NOT boot:**
```bash
# WRONG: Only using root partition
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1p3 \
  -F raw \
  overlay.qcow2
```

**Why**: No bootloader! The VM will show:
```
Booting from Hard Disk...
Boot failed: not a bootable disk
```

✅ **Correct: Use entire disk:**
```bash
# CORRECT: Entire disk including boot partitions
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1 \
  -F raw \
  overlay.qcow2
```

### Creating the Overlays

```bash
# NVMe-based Proxmox (LVM)
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1 \
  -F raw \
  /var/lib/libvirt/images/pve-nvme-overlay.qcow2

# SATA-based Proxmox (ZFS)
sudo qemu-img create -f qcow2 \
  -b /dev/sda \
  -F raw \
  /var/lib/libvirt/images/pve-sata-overlay.qcow2
```

### Verify Overlay Configuration

```bash
sudo qemu-img info /var/lib/libvirt/images/pve-nvme-overlay.qcow2
```

Should show:
```
image: /var/lib/libvirt/images/pve-nvme-overlay.qcow2
file format: qcow2
virtual size: 238 GiB
disk size: 196 KiB                    ← Small initial size
backing file: /dev/nvme0n1            ← Full disk path
backing file format: raw
```

## Resetting VMs to Pristine State

### Method 1: Delete and Recreate Overlay

```bash
# Stop VM
virsh destroy my-vm  # or: sudo pkill qemu-system

# Delete overlay (discards all changes)
sudo rm /var/lib/libvirt/images/my-os-overlay.qcow2

# Recreate fresh overlay
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1 \
  -F raw \
  /var/lib/libvirt/images/my-os-overlay.qcow2

# Restart VM
virsh start my-vm
```

### Method 2: Keep Multiple Snapshots

```bash
# Create baseline overlay
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1 \
  -F raw \
  /var/lib/libvirt/images/baseline.qcow2

# Boot, configure system, shut down

# Create snapshot of configured state
sudo qemu-img create -f qcow2 \
  -b /var/lib/libvirt/images/baseline.qcow2 \
  -F qcow2 \
  /var/lib/libvirt/images/snapshot1.qcow2

# Now you can revert to baseline or snapshot1 anytime
```

## Known Issues & Workarounds

### Issue 1: systemd-journald Crash

**Symptom**: systemd-journald fails to start with assertion error:
```
Assertion 'path_is_absolute(p)' failed at src/basic/chase.c:680
```

**Impact**:
- systemctl commands fail
- libvirtd cannot start VMs via Cockpit (systemd-machined timeout)
- VM logs not captured properly

**Workaround**: Use direct QEMU invocation (documented above) until NixOS rebuild fixes the issue.

**Status**: Under investigation. Likely NixOS systemd configuration bug.

### Issue 2: virtlogd Not Running

**Symptom**: VM fails to start with:
```
Failed to connect socket to '/run/libvirt/virtlogd-sock': Connection refused
```

**Fix**: Manually start virtlogd:
```bash
sudo /nix/store/*/libvirt-*/sbin/virtlogd --daemon
```

**Permanent Fix**: Added to `nix/modules/system/services.nix`:
```nix
systemd.services.virtlogd = {
  wantedBy = [ "multi-user.target" ];
  before = [ "libvirtd.service" ];
};
```

### Issue 3: Polkit Authentication Failures

**Symptom**: Cockpit shows "authentication unavailable: no polkit agent"

**Fix**: Already implemented in services.nix:
```nix
security.polkit.extraConfig = ''
  polkit.addRule(function(action, subject) {
      if (action.id.indexOf("org.libvirt.") == 0 &&
          subject.user == "libvirtdbus") {
          return polkit.Result.YES;
      }
  });
'';
```

## Future Enhancements

### Planned Features

1. **Cockpit Integration**
   - Custom Cockpit module for immutable VM management
   - One-click overlay reset button
   - Visual diff of changes (show overlay growth)

2. **Automated Discovery**
   - Scan all attached disks for bootable OS installations
   - Auto-generate VM definitions
   - Suggest memory/CPU allocation based on original system

3. **Snapshot Management**
   - Named snapshots with descriptions
   - Snapshot tree visualization
   - Quick rollback in Cockpit UI

4. **Import Wizard**
   - Guided TUI/web interface
   - Detect OS type (Proxmox, Ubuntu, Windows, etc.)
   - Auto-configure VM hardware for optimal compatibility

### User Experience Goals

The ideal workflow should be:

1. Insert USB with Hyper Recovery
2. Boot system
3. Open Cockpit → "Import Existing OS"
4. System auto-detects Proxmox/other OS on disk
5. Click "Create Immutable VM"
6. VM appears in Cockpit, ready to start
7. "Reset to Original" button available for one-click cleanup

## Technical Notes

### Why Whole Disk vs Partition?

**Bootloader location matters:**

- **BIOS boot**: GRUB stage 1.5 installed in MBR gap or BIOS boot partition
- **UEFI boot**: Bootloader files in EFI System Partition (ESP)

If you only provide the root partition:
1. QEMU/BIOS looks for bootloader → not found
2. Boot fails immediately

### ZFS Datasets vs zvols

**Important distinction:**

- **ZFS filesystem datasets** (like `rpool/ROOT/pve-1`) do NOT create `/dev/zvol/*` block devices
- **ZFS volumes (zvols)** are block devices accessible via `/dev/zvol/...`

For immutable VMs:
- ✅ Use raw partition: `/dev/sda3` (contains ZFS pool)
- ❌ Cannot use: `/dev/zvol/rpool/ROOT/pve-1` (doesn't exist for filesystems)

### QCOW2 Backing File Chains

You can create multi-level overlays:

```
Physical Disk (/dev/sda)
    ↓ (backing)
Base Overlay (baseline.qcow2)
    ↓ (backing)
Test Overlay 1 (test1.qcow2)
    ↓ (backing)
Test Overlay 2 (test2.qcow2)
```

**Performance considerations:**
- Each layer adds slight I/O overhead
- Keep chains shallow (2-3 levels max)
- Consolidate with `qemu-img commit` or `rebase` when needed

## Testing Checklist

When implementing immutable VM support:

- [ ] Disk auto-detection works for SATA/NVMe/USB
- [ ] Correctly identifies entire disk vs partition
- [ ] Creates overlay in appropriate location
- [ ] VM boots successfully (BIOS and UEFI modes)
- [ ] Network connectivity functional
- [ ] Console/VNC access available
- [ ] Overlay grows as expected with writes
- [ ] Reset operation works (delete + recreate)
- [ ] Multiple concurrent VMs from same backing file work
- [ ] Original disk untouched after VM operations

## Troubleshooting

### VM Won't Boot

1. **Check if entire disk used:**
   ```bash
   sudo qemu-img info /var/lib/libvirt/images/overlay.qcow2
   ```
   Look for: `backing file: /dev/nvme0n1` (not `/dev/nvme0n1p3`)

2. **Verify disk is accessible:**
   ```bash
   sudo fdisk -l /dev/nvme0n1
   ```

3. **Test with minimal QEMU command:**
   ```bash
   sudo qemu-system-x86_64 -m 2G -drive file=overlay.qcow2,if=virtio -nographic
   ```

### Overlay Growing Too Large

1. **Check current size:**
   ```bash
   du -sh /var/lib/libvirt/images/*.qcow2
   ```

2. **Identify what's using space:**
   - Boot VM, check disk usage inside guest
   - Logs writing to disk?
   - Package manager cache?

3. **Reset if needed:**
   ```bash
   sudo rm overlay.qcow2 && qemu-img create -f qcow2 -b /dev/nvme0n1 -F raw overlay.qcow2
   ```

### Performance Issues

1. **Use `cache=none` for direct I/O:**
   ```xml
   <driver name='qemu' type='qcow2' cache='none'/>
   ```

2. **Consider using virtio drivers** (already recommended above)

3. **For production use, consider committing overlay:**
   ```bash
   # Consolidate changes into new backing file
   sudo qemu-img convert -O qcow2 overlay.qcow2 standalone.qcow2
   ```

## Security Considerations

### Read-Only Backing Files

The backing file (physical disk) is opened read-only by QEMU. Even if compromised, the VM cannot modify the original installation.

### Overlay File Permissions

Overlays should be:
- Owned by root or libvirt-qemu user
- Not world-readable (may contain sensitive data from guest)

```bash
sudo chown root:root /var/lib/libvirt/images/*.qcow2
sudo chmod 600 /var/lib/libvirt/images/*.qcow2
```

### Multi-Tenancy

For shared systems:
- Each user gets separate overlay files
- Use libvirt's session mode for user-level VMs
- Or use qcow2 encryption for sensitive overlays

## References

- QEMU Documentation: https://qemu.readthedocs.io/en/latest/system/images.html
- libvirt Domain XML Format: https://libvirt.org/formatdomain.html
- QCOW2 Specification: https://github.com/qemu/qemu/blob/master/docs/interop/qcow2.txt
- NixOS libvirt module: https://search.nixos.org/options?query=virtualisation.libvirtd

---

**Last Updated**: 2026-02-14
**Status**: Feature working with direct QEMU; Cockpit integration pending systemd-journald fix
