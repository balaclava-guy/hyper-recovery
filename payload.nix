{ config, pkgs, lib, ... }:

let
  firmware = import ./hyper-firmware.nix { inherit pkgs lib; };
  hyperFirmwareCore = firmware.hyperFirmwareCore;

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
    journalctl -b -u cockpit.socket -u cockpit.service -u 'cockpit-wsinstance*' -u 'cockpit-session*' --no-pager > "$OUT_DIR/journal-cockpit.txt" 2>&1
    
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

  # Hardware helper: toggle firmware breadth at runtime.
  #
  # This is intentionally imperative: we keep the ISO slim by default, but allow
  # users to temporarily expand firmware coverage when they have connectivity.
  hyperHwScript = pkgs.writeShellScriptBin "hyper-hw" ''
    #!/usr/bin/env bash
    set -euo pipefail

    usage() {
      cat <<'EOF'
Usage:
  hyper-hw firmware core
  hyper-hw firmware full

Notes:
  - "full" downloads and activates full linux-firmware at runtime (requires network).
  - This is non-persistent across reboot.
EOF
    }

    if [[ $# -lt 2 ]]; then
      usage
      exit 2
    fi

    subcmd="$1"
    action="$2"

    if [[ "$subcmd" != "firmware" ]]; then
      usage
      exit 2
    fi

    sysfs_path="/sys/module/firmware_class/parameters/path"
    if [[ ! -e "$sysfs_path" ]]; then
      echo "hyper-hw: firmware_class.path is not available at $sysfs_path" >&2
      echo "hyper-hw: (is firmware_class built as a module / parameter supported by this kernel?)" >&2
      exit 1
    fi

    state_dir="/run/hyper-hw"
    mkdir -p "$state_dir"

    base_path_file="$state_dir/base-firmware-path"
    if [[ ! -s "$base_path_file" ]]; then
      # Store the current firmware path so we can revert later.
      cat "$sysfs_path" > "$base_path_file" || true
    fi
    base_path="$(cat "$base_path_file" 2>/dev/null || true)"
    if [[ -z "$base_path" ]]; then
      # Fallback to the conventional path in NixOS activation scripts.
      base_path="/run/current-system/firmware/lib/firmware"
    fi

    case "$action" in
      core)
        if [[ -e "$state_dir/firmware-overlay" ]]; then
          rm -rf "$state_dir/firmware-overlay"
        fi
        echo -n "$base_path" > "$sysfs_path"
        echo "hyper-hw: firmware path set to core: $base_path"
        ;;

      full)
        if ! command -v nix >/dev/null 2>&1; then
          echo "hyper-hw: nix is not in PATH" >&2
          exit 1
        fi

        # Use nixpkgs from NIX_PATH to keep this usable without pinning a flake at runtime.
        # Users can override by setting NIX_PATH or configuring substituters.
        echo "hyper-hw: downloading full linux-firmware via nix..."
        fw_out="$(nix build --no-link --print-out-paths 'nixpkgs#linux-firmware' | tail -n 1)"
        if [[ -z "$fw_out" ]] || [[ ! -d "$fw_out/lib/firmware" ]]; then
          echo "hyper-hw: linux-firmware build did not produce lib/firmware: $fw_out" >&2
          exit 1
        fi

        overlay="$state_dir/firmware-overlay"
        union="$overlay/union"
        rm -rf "$overlay"
        mkdir -p "$union"

        # Build a synthetic firmware tree so we can repoint firmware_class.path.
        # Order matters: base first, then full firmware overlays it.
        if [[ -d "$base_path" ]]; then
          (cd "$base_path" && find . -type f -print0) | while IFS= read -r -d $'\\0' f; do
            src="$base_path/$f"
            dst="$union/$f"
            mkdir -p "$(dirname "$dst")"
            ln -sf "$src" "$dst"
          done
        fi

        (cd "$fw_out/lib/firmware" && find . -type f -print0) | while IFS= read -r -d $'\\0' f; do
          src="$fw_out/lib/firmware/$f"
          dst="$union/$f"
          mkdir -p "$(dirname "$dst")"
          ln -sf "$src" "$dst"
        done

        echo -n "$union" > "$sysfs_path"
        echo "hyper-hw: firmware path set to full: $union"

        if command -v udevadm >/dev/null 2>&1; then
          echo "hyper-hw: triggering udev..."
          udevadm trigger || true
        fi
        ;;

      *)
        usage
        exit 2
        ;;
    esac
  '';

  # 1. Snosu Plymouth Theme Package
  snosuPlymouthTheme = pkgs.stdenv.mkDerivation {
    pname = "snosu-hyper-recovery-plymouth";
    version = "1.0";
    src = ./themes/plymouth/hyper-recovery;
    fontSrc = ./assets/fonts/undefined-medium/undefined-medium.ttf;
    
    nativeBuildInputs = [ pkgs.plymouth ];
    
    installPhase = ''
      mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery
      
      # Copy theme files (script, plymouth config, images)
      cp snosu-hyper-recovery.plymouth $out/share/plymouth/themes/snosu-hyper-recovery/
      cp snosu-hyper-recovery.script $out/share/plymouth/themes/snosu-hyper-recovery/
      cp *.png $out/share/plymouth/themes/snosu-hyper-recovery/
      cp -r animation $out/share/plymouth/themes/snosu-hyper-recovery/
      
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
    src = ./themes/grub/hyper-recovery;
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
  networking.hostName = "hyper-recovery";
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
    
    # Device-mapper (LVM / LVM-thin; needed for Proxmox "pve" VG thin-pools)
    "dm_mod"
    "dm_thin_pool"

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
  hardware.enableAllFirmware = false;
  hardware.enableRedistributableFirmware = false;
  hardware.firmware = [
    hyperFirmwareCore
    pkgs.wireless-regdb
  ];
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
    # Allow access from dynamic LAN IP/hostnames used by recovery images.
    allowed-origins = [ "*" ];
    plugins = with pkgs; [
      cockpit-machines
      cockpit-zfs
      cockpit-files
    ];
    settings = {
      WebService = {
        AllowUnencrypted = true;
        AllowRoot = true;
        LoginTitle = "SNOSU Hyper Recovery";
      };
    };
  };

  # Cockpit Branding
  # Cockpit 353+ reads branding from flat files in /etc/cockpit/branding/.
  environment.etc."cockpit/branding/branding.css".source = ./assets/branding/branding.css;
  environment.etc."cockpit/branding/logo.png".source = ./assets/branding/logo-source.png;
  environment.etc."cockpit/branding/brand-large.png".source = ./assets/branding/logo-source.png;
  environment.etc."cockpit/branding/apple-touch-icon.png".source = ./assets/branding/logo-source.png;
  environment.etc."cockpit/branding/favicon.ico".source = ./assets/branding/logo-source.png;
  # Keep legacy layout for compatibility with older Cockpit behavior.
  environment.etc."cockpit/branding/snosu/branding.ini".source = ./assets/branding/branding.ini;
  environment.etc."cockpit/branding/snosu/branding.css".source = ./assets/branding/branding.css;
  environment.etc."cockpit/branding/snosu/logo.png".source = ./assets/branding/logo-source.png;
  environment.etc."cockpit/branding/snosu/brand-large.png".source = ./assets/branding/logo-source.png;
  environment.etc."cockpit/branding/snosu/apple-touch-icon.png".source = ./assets/branding/logo-source.png;
  environment.etc."cockpit/branding/snosu/favicon.ico".source = ./assets/branding/logo-source.png;

  # UI & Branding
  environment.etc."motd".text = ''
    Welcome to Snosu Hyper Recovery Environment
    * Access the Web UI at: https://<IP>:9090
    * Default user: snosu / nixos
  '';
  environment.etc."snosu/motd-logo.ansi".source = ./assets/motd-logo.ansi;
  environment.etc."profile.d/snosu-motd.sh".text = ''
    #!/usr/bin/env bash

    # Print the logo only in interactive TTY login shells.
    if [[ "$-" != *i* ]] || [[ ! -t 1 ]]; then
      return 0 2>/dev/null || exit 0
    fi

    # Avoid duplicate output in nested shells.
    if [[ -n "''${SNOSU_MOTD_SHOWN:-}" ]]; then
      return 0 2>/dev/null || exit 0
    fi
    export SNOSU_MOTD_SHOWN=1

    logo_file=/etc/snosu/motd-logo.ansi
    if [[ ! -r "$logo_file" ]]; then
      return 0 2>/dev/null || exit 0
    fi

    parent_comm="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d '[:space:]')"
    is_cockpit=0
    if [[ -n "''${COCKPIT:-}" ]] || [[ "$parent_comm" == "cockpit-session" ]] || [[ "$parent_comm" == "cockpit-bridge" ]]; then
      is_cockpit=1
    fi

    supports_truecolor=0
    case "''${COLORTERM:-}" in
      *truecolor*|*24bit*) supports_truecolor=1 ;;
    esac
    if [[ "$supports_truecolor" -eq 0 ]]; then
      case "''${TERM:-}" in
        *-direct|xterm-kitty|wezterm|alacritty|foot*) supports_truecolor=1 ;;
      esac
    fi

    supports_256=0
    if command -v tput >/dev/null 2>&1; then
      colors="$(tput colors 2>/dev/null || echo 0)"
      if [[ "$colors" =~ ^[0-9]+$ ]] && [[ "$colors" -ge 256 ]]; then
        supports_256=1
      fi
    fi
    if [[ "$supports_256" -eq 0 ]]; then
      case "''${TERM:-}" in
        *256color*) supports_256=1 ;;
      esac
    fi

    if [[ "$is_cockpit" -eq 0 ]]; then
      if [[ "$supports_truecolor" -eq 1 ]]; then
        cat "$logo_file"
      elif [[ "$supports_256" -eq 1 ]] && command -v perl >/dev/null 2>&1; then
        cache_file="/tmp/snosu-motd-logo-256.''${UID:-0}.ansi"
        tmp_file="$cache_file.$$"

        if [[ ! -s "$cache_file" ]] || [[ "$logo_file" -nt "$cache_file" ]]; then
          if perl -CS -pe '
            sub rgb_to_256 {
              my ($r, $g, $b) = @_;
              my $ri = int(($r / 255) * 5 + 0.5);
              my $gi = int(($g / 255) * 5 + 0.5);
              my $bi = int(($b / 255) * 5 + 0.5);
              $ri = 0 if $ri < 0; $ri = 5 if $ri > 5;
              $gi = 0 if $gi < 0; $gi = 5 if $gi > 5;
              $bi = 0 if $bi < 0; $bi = 5 if $bi > 5;

              my $cube_idx = 16 + 36 * $ri + 6 * $gi + $bi;
              my @cube_vals = map { $_ == 0 ? 0 : 55 + $_ * 40 } ($ri, $gi, $bi);
              my $cube_dist = ($r - $cube_vals[0]) ** 2 + ($g - $cube_vals[1]) ** 2 + ($b - $cube_vals[2]) ** 2;

              my $gray_step = int((($r + $g + $b) / 3 - 8) / 10 + 0.5);
              $gray_step = 0 if $gray_step < 0;
              $gray_step = 23 if $gray_step > 23;
              my $gray_val = 8 + 10 * $gray_step;
              my $gray_idx = 232 + $gray_step;
              my $gray_dist = ($r - $gray_val) ** 2 + ($g - $gray_val) ** 2 + ($b - $gray_val) ** 2;

              return $gray_dist < $cube_dist ? $gray_idx : $cube_idx;
            }

            s/\e\[((?:3|4)8);2;(\d+);(\d+);(\d+)m/sprintf("\e[%s;5;%dm", $1, rgb_to_256($2, $3, $4))/ge;
          ' "$logo_file" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$cache_file"
          else
            rm -f "$tmp_file"
          fi
        fi

        if [[ -r "$cache_file" ]]; then
          cat "$cache_file"
        fi
      fi
    fi
  '';

  # Standard Packages
  environment.systemPackages = with pkgs; [
    qemu-utils zfs parted gptfdisk htop vim git perl
    pciutils usbutils smartmontools nvme-cli os-prober efibootmgr
    wpa_supplicant dhcpcd udisks2
    networkmanager  # nmcli
    iw
    hyperDebugScript  # Debug capture script - run 'hyper-debug'
    hyperHwScript     # Firmware toggle helper - run 'hyper-hw'
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
    password = "nixos";
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
