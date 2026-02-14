# Manual Steps Required (To Be Automated)

## Issue: Immutable VM Setup Requires Manual Configuration

After booting the Hyper Recovery USB, the following manual steps are currently required to use the immutable VM feature:

### 1. Create QCOW2 Overlays

```bash
sudo mkdir -p /var/lib/libvirt/images

# Create overlay for NVMe Proxmox
sudo qemu-img create -f qcow2 \
  -b /dev/nvme0n1 \
  -F raw \
  /var/lib/libvirt/images/pve-nvme-overlay.qcow2

# Create overlay for SATA/ZFS Proxmox
sudo qemu-img create -f qcow2 \
  -b /dev/sda \
  -F raw \
  /var/lib/libvirt/images/pve-sata-overlay.qcow2
```

### 2. Define VMs in libvirt System Connection

Create VM definitions and import them:

```bash
# NVMe VM definition
cat > /tmp/pve-nvme.xml << 'EOF'
<domain type='kvm'>
  <name>pve-nvme</name>
  <memory unit='KiB'>4194304</memory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <emulator>/run/current-system/sw/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/pve-nvme-overlay.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <serial type='pty'/>
    <console type='pty'/>
  </devices>
</domain>
EOF

virsh -c qemu:///system define /tmp/pve-nvme.xml

# SATA VM definition
cat > /tmp/pve-sata.xml << 'EOF'
<domain type='kvm'>
  <name>pve-sata</name>
  <memory unit='KiB'>4194304</memory>
  <vcpu>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
  </os>
  <devices>
    <emulator>/run/current-system/sw/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/var/lib/libvirt/images/pve-sata-overlay.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <serial type='pty'/>
    <console type='pty'/>
  </devices>
</domain>
EOF

virsh -c qemu:///system define /tmp/pve-sata.xml
```

### 3. Start Default Libvirt Network

```bash
virsh -c qemu:///system net-start default
```

## Automation Plan

These steps should be automated via a new NixOS module that:

1. **Auto-discovers** bootable OS installations on attached disks
2. **Creates QCOW2 overlays** automatically at boot
3. **Generates VM definitions** from discovered systems
4. **Imports VMs** into libvirt system connection
5. **Starts default network** automatically

See `nix/modules/system/immutable-vms.nix` for the implementation.

## Current Status

- ✅ Manual process documented
- ✅ Immutable VM feature validated and working
- ⏳ Automation module to be created
- ⏳ Auto-discovery to be implemented

## Related Documentation

- `docs/IMMUTABLE_VMS.md` - Comprehensive feature documentation
- `nix/modules/system/immutable-vms.nix` - Automation module (to be created)
