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

#### BIOS Boot (Legacy Systems)

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
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <graphics type='vnc' port='-1' autoport='yes'/>
  </devices>
</domain>
```

#### UEFI Boot (Recommended for GPT disks)

```xml
<domain type='kvm'>
  <name>my-imported-os</name>
  <memory unit='GiB'>4</memory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash'>/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/my-os-overlay.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <!-- For Advanced Format drives (4K sectors), add: -->
      <blockio logical_block_size='512' physical_block_size='4096'/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'>
      <listen type='address' address='0.0.0.0'/>
    </graphics>
    <video>
      <model type='qxl'/>
    </video>
  </devices>
</domain>
```

**Note**: Use UEFI boot for modern systems with GPT partition tables, especially those with Advanced Format (4K sector) drives.

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

### Issue 4: Advanced Format Drives (4K Sectors)

**Symptom**: Some SATA SSDs (like Crucial MX500) have 4K physical sectors but 512-byte logical sectors. When booted with BIOS firmware, the VM hangs at "Booting from Hard Disk..." with 99.7% CPU usage.

**Root Cause**: Block size mismatch between the physical drive (4096-byte physical sectors) and QEMU's default emulation (512-byte physical sectors).

**Detection**:
```bash
# Check physical block size
cat /sys/block/sda/queue/physical_block_size  # 4096 = Advanced Format
cat /sys/block/nvme0n1/queue/physical_block_size  # 512 = traditional

# Check logical block size
cat /sys/block/sda/queue/logical_block_size  # Usually 512 for both
```

**Solution**: Use UEFI firmware instead of BIOS, and specify block sizes explicitly:

```xml
<domain type='kvm'>
  <name>pve-sata</name>
  <os>
    <type arch='x86_64' machine='q35'>hvm</type>
    <loader readonly='yes' type='pflash'>/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
    <boot dev='hd'/>
  </os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/pve-sata-overlay.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <blockio logical_block_size='512' physical_block_size='4096'/>
    </disk>
    <graphics type='vnc' port='-1' autoport='yes' listen='0.0.0.0'>
      <listen type='address' address='0.0.0.0'/>
    </graphics>
    <video>
      <model type='qxl'/>
    </video>
  </devices>
</domain>
```

**Key Points**:
- **UEFI boot required**: BIOS boot fails with GPT + 4K sectors
- **Block sizes**: Use `<blockio logical_block_size='512' physical_block_size='4096'/>`
- **VNC console**: Add graphics device to see kernel output (Proxmox doesn't output to serial by default)
- **q35 machine**: Required for UEFI firmware support

**Why UEFI works**: UEFI firmware handles GPT partition tables natively and doesn't have the same sector size assumptions as legacy BIOS.

### Issue 5: tmpfs Disk Space Exhaustion (CRITICAL)

**Incident Date**: 2026-02-14

**Symptom**: System completely unresponsive - SSH hangs, Cockpit hangs, TTYs won't spawn, VMs paused with I/O errors.

**Root Cause**: Created a 100GB RAW disk image on tmpfs (RAM filesystem) which only had 15GB total capacity. When ZFS pool was created and started allocating real space (14GB), the tmpfs filled to 100%, causing all I/O operations to fail.

**What Happened**:
1. Created `/var/lib/libvirt/images/barbican-zfs.img` (100GB) on tmpfs for ZFS storage
2. ZFS pool creation allocated 14GB of real space on the sparse file
3. During VM migration, overlays tried to grow, hitting 100% disk usage
4. VMs paused with "I/O error" status
5. All processes requiring disk I/O hung (SSH, Cockpit, getty, systemd services)
6. System became completely unresponsive except for ping/network stack

**Impact**:
- Complete system lockup requiring hard reboot
- Potential loss of all changes in QCOW2 overlays (stored in tmpfs)
- Risk of losing network configurations and other VM state

**Recovery Steps Taken**:
1. Attempted SSH commands - all hung due to full disk
2. Tried Cockpit web interface - also hung
3. Physical console access - TTY switch worked but no getty spawned
4. Magic SysRq keys on physical keyboard:
   - `Alt+SysRq+S` (Emergency Sync) - **WORKED** (flushed buffers)
   - `Alt+SysRq+F` (OOM Killer) - Disabled in kernel config
   - Most other SysRq operations disabled
5. Hard power cycle (reset button) after Emergency Sync
6. System recovered on reboot with VM overlays intact

**Prevention**:
```bash
# ❌ NEVER DO THIS on tmpfs/RAM filesystem:
sudo qemu-img create -f raw /var/lib/libvirt/images/large-disk.img 100G

# ✅ CORRECT: Check available space first
df -h /var/lib/libvirt/images

# ✅ CORRECT: Use appropriate storage location
# For Hyper Recovery (tmpfs root), large disk images should be:
# 1. Stored on mounted physical disks
# 2. Or use sparse QCOW2 format (not RAW)
# 3. Or created on persistent storage only
```

**Safe Approach for Additional VM Disks**:

**Option 1: Mount Real Filesystem**
```bash
# Create mount point on persistent storage
sudo mkdir -p /mnt/vm-storage
sudo mount /dev/sda3 /mnt/vm-storage  # Use actual partition

# Create disk images there
sudo qemu-img create -f raw /mnt/vm-storage/zfs-disk.img 100G
```

**Option 2: Use QCOW2 Format (More Space Efficient)**
```bash
# QCOW2 starts small and grows as needed
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/zfs-disk.qcow2 100G
# Initial size: ~200KB, grows only as data is written
```

**Option 3: Attach Physical Disk/Partition Directly**
```xml
<!-- Attach a real partition or whole disk -->
<disk type='block' device='disk'>
  <driver name='qemu' type='raw'/>
  <source dev='/dev/sdb'/>
  <target dev='vdb' bus='virtio'/>
</disk>
```

**Monitoring Disk Space**:
```bash
# Always check before creating large files
df -h /var/lib/libvirt/images

# Monitor overlay growth
watch -n 5 'du -sh /var/lib/libvirt/images/*.qcow2'

# Check tmpfs usage
df -h / | grep tmpfs
```

**Emergency Recovery Tools**:

If system becomes unresponsive due to full disk:

1. **Magic SysRq Keys** (on physical keyboard):
   ```
   Alt + SysRq + S  (Emergency Sync - flush buffers)
   Alt + SysRq + F  (Invoke OOM Killer - if enabled)
   ```

2. **REISUB Sequence** (safe reboot for hung systems):
   ```
   R - Take keyboard back from X
   E - Terminate all processes (SIGTERM)
   I - Kill all processes (SIGKILL)
   S - Sync filesystems
   U - Remount read-only
   B - Reboot
   ```
   Note: Many SysRq operations may be disabled in NixOS kernel config

3. **Last Resort**: Hard reset/power cycle
   - Use after attempting Emergency Sync (Alt+SysRq+S)
   - Minimizes risk of data loss in overlays

**Lessons Learned**:
- **Always check filesystem type** before creating large files (`df -T`)
- **tmpfs capacity equals RAM** - treat it as limited
- **RAW format allocates full size** on some filesystems
- **Emergency Sync saved configurations** - overlay files were properly flushed
- **Network stack survives** I/O hangs (ping still worked)
- **Magic SysRq is critical** for recovery on physical systems

**Status**: Resolved. System recovered after hard reboot with VM network configurations intact. Future deployments will use persistent storage for large disk images.

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
