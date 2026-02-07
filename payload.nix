{ config, pkgs, lib, ... }:

let
  # 1. Snosu Plymouth Theme Package
  snosuPlymouthTheme = pkgs.stdenv.mkDerivation {
    pname = "snosu-hyper-recovery-plymouth";
    version = "1.0";
    src = ./snosu-hyper-recovery;
    fontSrc = ./assets/fonts/undefined-medium/undefined-medium.ttf;
    
    installPhase = ''
      mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery
      cp -r * $out/share/plymouth/themes/snosu-hyper-recovery
      
      # Copy font to theme directory
      cp $fontSrc $out/share/plymouth/themes/snosu-hyper-recovery/undefined-medium.ttf
      
      # Fix permissions if needed
      chmod -R +w $out/share/plymouth/themes/snosu-hyper-recovery
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
  boot.supportedFilesystems = [ "zfs" "exfat" "vfat" ];
  boot.zfs.forceImportRoot = false;
  
  # Kernel & Hardware
  boot.kernelPackages = pkgs.linuxPackages;
  boot.kernelParams = [ 
    "quiet" 
    "splash" 
    "loglevel=3" 
    "rd.systemd.show_status=false" 
    "rd.udev.log_level=3" 
    "udev.log_priority=3" 
    "vt.global_cursor_default=0"
  ];

  # Performance & Space Optimizations
  documentation.enable = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
    * Default user: root / nixos
  '';

  # Standard Packages
  environment.systemPackages = with pkgs; [
    cockpit cockpit-machines cockpit-zfs cockpit-files
    qemu-utils virt-manager zfs parted gptfdisk htop vim git
    pciutils usbutils smartmontools nvme-cli os-prober efibootmgr
    wpa_supplicant dhcpcd udisks2
  ];

  # Auth
  users.mutableUsers = false;
  users.users.root = {
    password = "nixos";
    initialPassword = lib.mkForce null;
    hashedPassword = lib.mkForce null;
    hashedPasswordFile = lib.mkForce null;
    initialHashedPassword = lib.mkForce null;
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
    enable = true;
    theme = "snosu-hyper-recovery";
    themePackages = [ snosuPlymouthTheme ];
  };

  boot.loader.grub = {
    enable = true;
    theme = snosuGrubTheme;
    splashImage = "${snosuGrubTheme}/background.png";
    efiSupport = true;
    device = "nodev";
  };

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
}
