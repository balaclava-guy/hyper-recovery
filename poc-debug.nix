{ config, lib, pkgs, ... }:

{
  system.stateVersion = "25.05";
  networking.hostName = "hyper-recovery-poc";

  documentation.enable = false;
  programs.command-not-found.enable = false;

  users.mutableUsers = false;
  users.users.root = {
    password = "nixos";
    initialPassword = lib.mkForce null;
    hashedPassword = lib.mkForce null;
    hashedPasswordFile = lib.mkForce null;
    initialHashedPassword = lib.mkForce null;
  };

  boot.kernelParams = [
    "loglevel=7"
    "systemd.log_level=debug"
    "systemd.log_target=console"
    "rd.debug"
    "rd.udev.log_level=debug"
    "rd.systemd.show_status=1"
    "boot.shell_on_fail"
  ];

  isoImage = {
    volumeID = "HYPER_RECOVERY_POC";
    makeEfiBootable = true;
    makeBiosBootable = true;
    makeUsbBootable = true;
  };
  image.fileName = "hyper-recovery-poc-x86_64-linux.iso";

  boot.supportedFilesystems = [ "vfat" "exfat" "iso9660" "squashfs" "overlay" ];

  boot.initrd.availableKernelModules = [
    "usb_storage"
    "uas"
    "sd_mod"
    "vfat"
    "exfat"
    "iso9660"
    "squashfs"
    "overlay"
    "loop"
  ];

  boot.initrd.kernelModules = [
    "usb_storage"
    "uas"
    "sd_mod"
    "vfat"
    "exfat"
    "iso9660"
    "squashfs"
    "overlay"
    "loop"
  ];

  boot.initrd.systemd = {
    enable = true;
    initrdBin = [ pkgs.coreutils pkgs.util-linux ];
    services.initrd-logdump = {
      description = "Dump initrd logs to Ventoy";
      wantedBy = [ "initrd.target" ];
      before = [ "initrd-switch-root.target" ];
      after = [ "systemd-udevd.service" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        mkdir -p /run/initrd-logdump
        cat /proc/cmdline > /run/initrd-logdump/cmdline.txt
        dmesg -T > /run/initrd-logdump/dmesg.txt || dmesg > /run/initrd-logdump/dmesg.txt
        journalctl -b --no-pager > /run/initrd-logdump/journal.txt || true
        ls -lah /dev/disk > /run/initrd-logdump/dev-disk.txt || true
        ls -lah /dev/disk/by-label > /run/initrd-logdump/dev-by-label.txt || true

        target=""
        for label in VENTOY Ventoy ventoy; do
          if [ -e "/dev/disk/by-label/$label" ]; then
            target="/dev/disk/by-label/$label"
            break
          fi
        done

        if [ -n "$target" ]; then
          mkdir -p /mnt/ventoy
          if mount -o rw "$target" /mnt/ventoy; then
            log_dir="/mnt/ventoy/hyper-recovery-initrd-logs"
            mkdir -p "$log_dir"
            cp -v /run/initrd-logdump/* "$log_dir/" || true
            sync || true
            umount /mnt/ventoy || true
          fi
        fi
      '';
    };
  };

  systemd.services.save-boot-logs = {
    description = "Save boot logs to Ventoy USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      set -euo pipefail
      labels=("VENTOY" "Ventoy" "ventoy")
      device=""
      for label in "''${labels[@]}"; do
        if [ -e "/dev/disk/by-label/$label" ]; then
          device="/dev/disk/by-label/$label"
          break
        fi
      done
      if [ -z "$device" ]; then exit 0; fi
      mkdir -p /mnt/ventoy
      mount -o rw "$device" /mnt/ventoy || exit 0
      log_dir="/mnt/ventoy/boot-logs"
      mkdir -p "$log_dir"
      journalctl -b -o short-precise > "$log_dir/journal.txt" || true
      dmesg -T > "$log_dir/dmesg.txt" || true
      sync
    '';
  };
}
