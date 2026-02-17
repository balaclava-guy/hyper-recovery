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
    # AppArmor is configured via security.apparmor.enable
    # (NixOS manages LSM configuration automatically)
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

  boot.kernelModules = [
    # LVM thin-pool support
    "dm_thin_pool"
    "dm_persistent_data"
    "dm_bio_prison"
    "dm_bufio"
    # KVM virtualization support
    "kvm-intel"
    "kvm-amd"
  ];

  # LVM thin-pool support for Proxmox "pve" volume groups.
  #
  # Two problems exist with udev-triggered LVM activation (`lvm-activate-<VG>`):
  #
  # 1. Race condition: udev detects the VG PVs and fires `vgchange -aay` via
  #    systemd-run *before* systemd-modules-load has inserted dm_thin_pool
  #    (observed: activation at ~2s, module at ~5s).
  #
  # 2. Missing userspace tool: LVM defaults to /usr/sbin/thin_check which does
  #    not exist on NixOS.  Without it LVM refuses to activate thin pools.
  #
  # Fix (1) with a one-shot retry service ordered after modules are loaded.
  # Fix (2) by pointing LVM at the Nix store paths via lvmlocal.conf.
  environment.etc."lvm/lvmlocal.conf".text = ''
    global {
      thin_check_executable = "${pkgs.thin-provisioning-tools}/bin/thin_check"
      thin_dump_executable = "${pkgs.thin-provisioning-tools}/bin/thin_dump"
      thin_repair_executable = "${pkgs.thin-provisioning-tools}/bin/thin_repair"
    }
  '';

  systemd.services.lvm-thin-activate = {
    description = "Re-activate LVM thin-pool volumes after kernel modules are loaded";
    after = [ "systemd-modules-load.service" ];
    wants = [ "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];
    # Reset the failed state of the racy udev-triggered unit, then retry.
    path = [ pkgs.lvm2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.lvm2.bin}/bin/vgchange -aay";
    };
  };

  # Firmware & wireless
  # Include all wireless firmware families without pulling the full firmware set.
  hardware.enableAllFirmware = false;
  hardware.enableRedistributableFirmware = false;
  hardware.firmware = [
    hyper-firmware-wireless-all
    pkgs.wireless-regdb
  ];
  hardware.wirelessRegulatoryDatabase = true;

  # AppArmor for container security (fixed in nixpkgs PR #386060)
  security.apparmor.enable = true;

  # Pre-create Incus AppArmor directories to prevent boot-time race condition
  # apparmor.service tries to load Incus profiles before Incus creates these directories
  systemd.tmpfiles.rules = [
    "d /var/lib/incus/security/apparmor 0700 root root -"
    "d /var/lib/incus/security/apparmor/cache 0700 root root -"
    "d /var/lib/incus/security/apparmor/profiles 0700 root root -"
  ];
}
