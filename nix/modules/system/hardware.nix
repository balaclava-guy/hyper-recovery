{ config, pkgs, lib, ... }:

# Hardware configuration for Hyper Recovery environment
# Kernel, firmware, and driver configuration

let
  firmware = import ../../packages/firmware.nix { inherit pkgs lib; };
  hyper-firmware-wireless-all = firmware.hyper-firmware-wireless-all;
in
{
  # Kernel & Boot Parameters (CLEAN - no debug)
  boot.kernelPackages = pkgs.linuxPackages;
  boot.kernelParams = [
    "quiet"
    "splash"
    # Keep regular build output quiet during initrd and early boot.
    "rd.systemd.show_status=false"
    "systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "vt.global_cursor_default=0"
    "fbcon=nodefer"
    "plymouth.ignore-serial-consoles"
    "iwlwifi.power_save=0"
  ];
  
  # Suppress console messages during boot (for Plymouth)
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  
  # KMS drivers for Plymouth (critical for boot splash)
  # AND storage drivers for boot (critical for finding root device)
  boot.initrd.kernelModules = [ 
    # Graphics
    "i915" "amdgpu" "nouveau" "radeon" "virtio_gpu"

    # Device-mapper (LVM / LVM-thin; needed for Proxmox "pve" VG thin-pools)
    "dm_mod"
    "dm_thin_pool"
    "dm_persistent_data"
    "dm_bio_prison"
    "dm_bufio"

    # Storage / Virtualization (Essential for Recovery Environment)
    "virtio_blk" "virtio_pci" "virtio_scsi"  # QEMU/KVM
    "9p" "9pnet" "9pnet_virtio"             # QEMU virtio-9p shared folder
    "nvme"        # NVMe drives
    "ahci"        # SATA
    "xhci_pci"    # USB 3.x
    "usb_storage" # USB Mass Storage
    "sd_mod"      # SCSI/SATA disks
    "sr_mod"      # CD-ROMs
    "isofs"       # ISO9660 for live media
    "squashfs"    # SquashFS root
    "overlay"     # OverlayFS for live root
  ];

  # Ensure virtio_gpu is available for early KMS
  boot.initrd.availableKernelModules = [ "virtio_gpu" "virtio_pci" "9p" "9pnet_virtio" "dm_thin_pool" "dm_persistent_data" "dm_bio_prison" "dm_bufio" ];

  # Ensure dm_thin_pool is loaded early in stage 2 boot, before udev triggers
  # LVM activation. This prevents the "thin-pool target support missing" error
  # when activating Proxmox thin-provisioned volumes.
  boot.kernelModules = [
    "dm_thin_pool"
    "dm_persistent_data"
    "dm_bio_prison"
    "dm_bufio"
  ];

  # Firmware & wireless
  # Include all wireless firmware families without pulling the full firmware set.
  hardware.enableAllFirmware = false;
  hardware.enableRedistributableFirmware = false;
  hardware.firmware = [
    hyper-firmware-wireless-all
    pkgs.wireless-regdb
  ];
  hardware.wirelessRegulatoryDatabase = true;
}
