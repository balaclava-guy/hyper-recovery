{ config, pkgs, lib, ... }:

let
  # Debug capture script - run 'hyper-debug' to collect diagnostics
  hyperDebugScript = pkgs.writeShellScriptBin "hyper-debug" ''
    #!/usr/bin/env bash
    set +e
    
    OUT_DIR="''${HYPER_DEBUG_DIR:-/tmp/hyper-debug-$(date +%Y%m%d-%H%M%S)}"
    mkdir -p "$OUT_DIR"
    
    echo "Collecting system diagnostics to $OUT_DIR ..."
    
    # Basic system info
    echo "=== System Info ===" > "$OUT_DIR/system-info.txt"
    date >> "$OUT_DIR/system-info.txt"
    uname -a >> "$OUT_DIR/system-info.txt"
    cat /etc/os-release >> "$OUT_DIR/system-info.txt" 2>/dev/null
    cat /proc/cmdline >> "$OUT_DIR/system-info.txt"
    
    # Block devices
    echo "=== Block Devices ===" > "$OUT_DIR/block-devices.txt"
    lsblk -a -o NAME,KNAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS >> "$OUT_DIR/block-devices.txt" 2>&1
    echo "" >> "$OUT_DIR/block-devices.txt"
    blkid >> "$OUT_DIR/block-devices.txt" 2>&1
    echo "" >> "$OUT_DIR/block-devices.txt"
    ls -la /dev/disk/by-label/ >> "$OUT_DIR/block-devices.txt" 2>&1
    
    # Mounts
    findmnt -a > "$OUT_DIR/mounts.txt" 2>&1
    
    # Systemd status
    systemctl --failed > "$OUT_DIR/systemd-failed.txt" 2>&1
    systemctl status > "$OUT_DIR/systemd-status.txt" 2>&1
    
    # Plymouth status
    echo "=== Plymouth ===" > "$OUT_DIR/plymouth.txt"
    plymouth --ping 2>&1 && echo "Plymouth daemon: RUNNING" >> "$OUT_DIR/plymouth.txt" || echo "Plymouth daemon: NOT RUNNING" >> "$OUT_DIR/plymouth.txt"
    plymouth-set-default-theme --list >> "$OUT_DIR/plymouth.txt" 2>&1
    echo "Current theme: $(plymouth-set-default-theme)" >> "$OUT_DIR/plymouth.txt" 2>&1
    ls -la /run/plymouth/ >> "$OUT_DIR/plymouth.txt" 2>&1
    cat /etc/plymouth/plymouthd.conf >> "$OUT_DIR/plymouth.txt" 2>&1
    
    # Kernel messages
    dmesg -T > "$OUT_DIR/dmesg.txt" 2>&1 || dmesg > "$OUT_DIR/dmesg.txt" 2>&1
    
    # Journal
    journalctl -b --no-pager > "$OUT_DIR/journal.txt" 2>&1
    journalctl -b -u plymouth* --no-pager > "$OUT_DIR/journal-plymouth.txt" 2>&1
    
    # Graphics/DRM info
    echo "=== Graphics ===" > "$OUT_DIR/graphics.txt"
    ls -la /dev/dri/ >> "$OUT_DIR/graphics.txt" 2>&1
    cat /sys/class/drm/*/status >> "$OUT_DIR/graphics.txt" 2>&1
    lspci -k | grep -A3 -i vga >> "$OUT_DIR/graphics.txt" 2>&1
    
    echo "Diagnostics collected in: $OUT_DIR"
    echo ""
    
    # Try to copy to Ventoy
    VENTOY_MNT=""
    for label in Ventoy VENTOY ventoy; do
      if [ -e "/dev/disk/by-label/$label" ]; then
        VENTOY_MNT="/mnt/ventoy-debug"
        mkdir -p "$VENTOY_MNT"
        if mount -o rw "/dev/disk/by-label/$label" "$VENTOY_MNT" 2>/dev/null; then
          DEST="$VENTOY_MNT/hyper-recovery-debug"
          mkdir -p "$DEST"
          cp -r "$OUT_DIR"/* "$DEST/"
          sync
          echo "Also copied to Ventoy USB: $DEST"
          umount "$VENTOY_MNT" 2>/dev/null || true
        fi
        break
      fi
    done
    
    echo ""
    echo "To view: ls $OUT_DIR"
    echo "To copy via SSH: scp -r root@<IP>:$OUT_DIR ."
  '';

  hyperDebugSerialScript = pkgs.writeShellScript "hyper-debug-serial" ''
    #!/usr/bin/env bash
    set -euo pipefail

    export HYPER_DEBUG_DIR="/run/hyper-debug"
    rm -rf "$HYPER_DEBUG_DIR"
    mkdir -p "$HYPER_DEBUG_DIR"

    echo "=== hyper-debug-serial start ==="
    hyper-debug || true

    for f in system-info.txt plymouth.txt journal-plymouth.txt graphics.txt; do
      if [ -f "$HYPER_DEBUG_DIR/$f" ]; then
        echo "--- $f ---"
        cat "$HYPER_DEBUG_DIR/$f"
        echo ""
      fi
    done

    echo "=== hyper-debug-serial end ==="
  '';

  # 1. Snosu Plymouth Theme Package
  snosuPlymouthTheme = pkgs.stdenv.mkDerivation {
    pname = "snosu-hyper-recovery-plymouth";
    version = "1.0";
    src = ./snosu-hyper-recovery;
    fontSrc = ./assets/fonts/undefined-medium/undefined-medium.ttf;
    
    nativeBuildInputs = [ pkgs.plymouth ];
    
    installPhase = ''
      mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery
      
      # Copy theme files (script, plymouth config, images)
      cp snosu-hyper-recovery.plymouth $out/share/plymouth/themes/snosu-hyper-recovery/
      cp snosu-hyper-recovery.script $out/share/plymouth/themes/snosu-hyper-recovery/
      cp *.png $out/share/plymouth/themes/snosu-hyper-recovery/
      
      # Copy and install font
      mkdir -p $out/share/fonts/truetype
      cp $fontSrc $out/share/fonts/truetype/undefined-medium.ttf
      
      # Also copy font to theme directory for direct access
      cp $fontSrc $out/share/plymouth/themes/snosu-hyper-recovery/undefined-medium.ttf
      
      # Verify all required files are present
      echo "Verifying Plymouth theme installation..."
      test -f $out/share/plymouth/themes/snosu-hyper-recovery/snosu-hyper-recovery.plymouth || \
        (echo "ERROR: .plymouth file missing" && exit 1)
      test -f $out/share/plymouth/themes/snosu-hyper-recovery/snosu-hyper-recovery.script || \
        (echo "ERROR: .script file missing" && exit 1)
      
      # Count animation frames
      frame_count=$(ls -1 $out/share/plymouth/themes/snosu-hyper-recovery/*.png 2>/dev/null | wc -l)
      echo "Found $frame_count PNG files in theme directory"
      
      # Fix permissions
      chmod -R +r $out/share/plymouth/themes/snosu-hyper-recovery
      chmod -R +r $out/share/fonts
    '';
  };

  # 2. Snosu GRUB Theme Package
  snosuGrubTheme = pkgs.stdenv.mkDerivation {
    pname = "snosu-hyper-recovery-grub";
    version = "1.0";
    src = ./snosu-hyper-recovery/grub;
    fontSrc = ./assets/fonts/undefined-medium/undefined-medium.ttf;
    
    nativeBuildInputs = [ pkgs.grub2 ];
    
    installPhase = ''
      mkdir -p $out
      cp * $out/
      
      grub-mkfont -s 12 -o $out/undefined_medium_12.pf2 $fontSrc
      grub-mkfont -s 14 -o $out/undefined_medium_14.pf2 $fontSrc
      grub-mkfont -s 16 -o $out/undefined_medium_16.pf2 $fontSrc
      grub-mkfont -s 24 -o $out/undefined_medium_24.pf2 $fontSrc
      grub-mkfont -s 28 -o $out/undefined_medium_28.pf2 $fontSrc
      
      sed -i 's/Hyper Street Fighter 2 Regular/Undefined Medium/g' $out/theme.txt
      sed -i 's/Hyper Fighting Regular/Undefined Medium/g' $out/theme.txt
    '';
  };

in
{
  # Core System Identity
  networking.hostName = "snosu-hyper-recovery";
  networking.hostId = "8425e349";
  system.stateVersion = "25.05";

  # ZFS & Filesystems
  boot.supportedFilesystems = [ "zfs" "exfat" "vfat" "iso9660" "squashfs" "overlay" ];
  boot.zfs.forceImportRoot = false;
  
  # Kernel & Hardware
  boot.kernelPackages = pkgs.linuxPackages;
  boot.kernelParams = [ 
    "quiet" 
    "splash" 
    "loglevel=0"                    # Suppress all but critical messages
    "rd.systemd.show_status=false" 
    "rd.udev.log_level=3" 
    "udev.log_priority=3" 
    "vt.global_cursor_default=0"
    "fbcon=nodefer"                   # Take over framebuffer early
    "plymouth.ignore-serial-consoles"  # Prevent serial console interference
    "iwlwifi.power_save=0"
  ];
  
  # Suppress console messages during boot (for Plymouth)
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  
  # KMS drivers for Plymouth (critical for boot splash to work)
  # AND storage drivers for boot (critical for finding root device)
  boot.initrd.kernelModules = [ 
    # Graphics
    "i915" "amdgpu" "nouveau" "radeon" "virtio_gpu"
    
    # Storage / Virtualization (Essential for Recovery Environment)
    "virtio_blk" "virtio_pci" "virtio_scsi"  # QEMU/KVM
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

  # Performance & Space Optimizations
  documentation.enable = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Firmware & wireless
  hardware.enableAllFirmware = true;
  hardware.firmware = with pkgs; [ linux-firmware ];
  hardware.wirelessRegulatoryDatabase = true;

  # Networking
  networking.networkmanager.enable = true;
  networking.dhcpcd.enable = false;

  # Virtualization Stack
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Management Interface (Cockpit)
  services.cockpit = {
    enable = true;
    openFirewall = true;
    settings = {
      WebService = {
        AllowUnencrypted = true;
        Branding = "snosu";
        AllowRoot = true;
      };
    };
  };

  # Cockpit Branding
  environment.etc."cockpit/branding/snosu/branding.ini".source = ./branding/snosu/branding.ini;
  environment.etc."cockpit/branding/snosu/branding.css".source = ./branding/snosu/branding.css;
  environment.etc."cockpit/branding/snosu/logo.png".source = ./branding/snosu/logo.png;
  environment.etc."cockpit/branding/snosu/apple-touch-icon.png".source = ./branding/snosu/logo.png;
  environment.etc."cockpit/branding/snosu/favicon.ico".source = ./branding/snosu/logo.png;

  # UI & Branding
  environment.etc."motd".text = (builtins.readFile ./assets/motd-logo.ansi) + ''
    Welcome to Snosu Hyper Recovery Environment
    * Access the Web UI at: https://<IP>:9090
    * Default user: snosu / nixos
  '';

  # Standard Packages
  environment.systemPackages = with pkgs; [
    cockpit cockpit-machines cockpit-zfs cockpit-files
    qemu-utils virt-manager zfs parted gptfdisk htop vim git
    pciutils usbutils smartmontools nvme-cli os-prober efibootmgr
    wpa_supplicant dhcpcd udisks2
    networkmanager  # nmcli
    iw
    hyperDebugScript  # Debug capture script - run 'hyper-debug'
    plymouth          # For Plymouth debugging
  ];

  # Auth
  users.mutableUsers = false;
  users.users.root = {
    initialPassword = lib.mkForce null;
    hashedPassword = lib.mkForce null;
    hashedPasswordFile = lib.mkForce null;
    initialHashedPassword = lib.mkForce null;
  };
  users.users.snosu = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = [ "wheel" ];
  };
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Disable memtest to keep menu clean
  boot.loader.grub.memtest86.enable = lib.mkForce false;

  # Boot Branding
  boot.initrd.systemd.enable = true;
  boot.plymouth = {
    enable = lib.mkForce true;
    theme = "snosu-hyper-recovery";
    themePackages = [ snosuPlymouthTheme ];
    font = "${snosuPlymouthTheme}/share/fonts/truetype/undefined-medium.ttf";
    extraConfig = ''
      DebugFile=/dev/ttyS0
      DebugLevel=info
    '';
  };

  # Ensure virtio_gpu is available for early KMS
  boot.initrd.availableKernelModules = [ "virtio_gpu" "virtio_pci" ];

  boot.loader.grub = {
    enable = true;
    theme = snosuGrubTheme;
    splashImage = "${snosuGrubTheme}/background.png";
    
    # Hybrid boot support - both EFI and BIOS
    efiSupport = true;
    efiInstallAsRemovable = true;  # Critical for Ventoy compatibility
    device = "nodev";  # Will be set during image postVM hook
    
    # GRUB configuration
    useOSProber = true;  # Detect other OSes on local drives
    
    # NOTE: Do not add manual 'menuentry' items here for kernel/initrd.
    # On the ISO, kernel paths are dynamic and managed by the ISO generator.
    # Manual entries with '/boot/kernel' will fail.
  };
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # Log Capture Service
  systemd.services.save-boot-logs = {
    description = "Save boot logs to Ventoy USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "save-boot-logs" ''
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
  };

  systemd.services.hyper-debug-serial = {
    description = "Dump hyper debug info to serial when hyper.debug=1";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionKernelCommandLine = "hyper.debug=1";
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyS0";
      TTYReset = "yes";
      TTYVHangup = "yes";
    };
    path = [
      pkgs.coreutils
      pkgs.util-linux
      pkgs.systemd
      pkgs.networkmanager
      pkgs.plymouth
      hyperDebugScript
    ];
    script = ''
      set -euo pipefail
      echo "hyper-debug-serial: starting"
      ${hyperDebugSerialScript}
      echo "hyper-debug-serial: done"
    '';
  };
}
