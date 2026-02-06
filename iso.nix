{ config, pkgs, lib, ... }:

let
  # 1. Generate Assets using Python/Pillow
  hyperRecoveryThemeAssets = pkgs.runCommand "hyper-recovery-theme-assets" {
    nativeBuildInputs = [ pkgs.python3 pkgs.python3Packages.pillow ];
    src = ./scripts/generate_theme_assets.py;
  } ''
    mkdir -p $out/grub $out/plymouth
    
    # Create a working directory
    mkdir work
    cd work
    
    # Copy script
    cp $src generate_assets.py
    
    # Patch script to output to current directory
    sed -i 's|BASE_DIR = Path(__file__).resolve().parent.parent|BASE_DIR = Path(".")|' generate_assets.py
    
    # Run script (outputs to ./assets/grub and ./assets/plymouth)
    python3 generate_assets.py
    
    # Install
    cp assets/grub/* $out/grub/
    cp assets/plymouth/* $out/plymouth/
  '';

  # 2. Plymouth Theme Package
  hyperRecoveryPlymouthTheme = pkgs.stdenv.mkDerivation {
    name = "hyper-recovery-plymouth-theme";
    src = ./themes/hyper-recovery/plymouth;
    
    installPhase = ''
      mkdir -p $out/share/plymouth/themes/hyper-recovery
      
      # Copy config files from src
      cp * $out/share/plymouth/themes/hyper-recovery/
      
      # Copy generated assets
      cp ${hyperRecoveryThemeAssets}/plymouth/* $out/share/plymouth/themes/hyper-recovery/
      
      # Fix paths in .plymouth file
      substituteInPlace $out/share/plymouth/themes/hyper-recovery/hyper-recovery.plymouth \
        --replace "ImageDir=." "ImageDir=$out/share/plymouth/themes/hyper-recovery" \
        --replace "ScriptFile=hyper-recovery.script" "ScriptFile=$out/share/plymouth/themes/hyper-recovery/hyper-recovery.script"
    '';
  };

  # 3. GRUB Theme Package
  hyperRecoveryGrubTheme = pkgs.stdenv.mkDerivation {
    name = "hyper-recovery-grub-theme";
    src = ./themes/hyper-recovery/grub;
    
    installPhase = ''
      mkdir -p $out
      
      # Copy config
      cp * $out/
      
      # Copy generated assets
      cp ${hyperRecoveryThemeAssets}/grub/* $out/
    '';
  };

in
{
  # ZFS Support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "8425e349";

  # Kernel & Hardware
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
  # Hypervisor & Virtualization
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  # Cockpit Management
  services.cockpit = {
    enable = true;
    openFirewall = true;
    settings = {
      WebService = {
        AllowUnencrypted = true;
      };
    };
  };
  
  environment.systemPackages = with pkgs; [
    cockpit
    cockpit-machines
    cockpit-zfs
    zfs
    parted
    gptfdisk
    htop
    vim
    git
    pciutils
    usbutils
    smartmontools
    nvme-cli
    os-prober
    efibootmgr
    wpa_supplicant
    dhcpcd
    
    (pkgs.writeShellScriptBin "import-proxmox-pools" ''
      #!/bin/sh
      echo "Scanning for ZFS pools..."
      sudo zpool import
      
      echo ""
      echo "To import a pool, run: sudo zpool import -f <poolname>"
      echo "The -f flag is often needed if the pool was not cleanly exported (e.g. crash/power loss)."
      echo "Proxmox pools are typically named 'rpool'."
    '')
  ];

  # Networking
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  # Nix Configuration
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # User Configuration
  users.users.root.password = "nixos";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # ISO Specifics
  isoImage.squashfsCompression = "zstd";
  
  # Serial console support & Splash
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" "splash" "boot.shell_on_fail" ];
  
  # GRUB Theme (EFI)
  boot.loader.grub = {
    enable = true;
    version = 2;
    device = "nodev";
    efiSupport = true;
    theme = hyperRecoveryGrubTheme;
    # We point to the file inside the theme package
    splashImage = "${hyperRecoveryGrubTheme}/hyper-recovery-grub-bg.png";
  };

  # Plymouth Theme
  boot.plymouth = {
    enable = true;
    theme = "hyper-recovery";
    themePackages = [ hyperRecoveryPlymouthTheme ];
  };

  # Syslinux Menu (BIOS)
  isoImage.syslinuxTheme = lib.mkForce ''
    DEFAULT boot
    TIMEOUT 100
    PROMPT 1
    
    UI menu.c32
    
    MENU TITLE Hypervisor OS Boot CD
    
    LABEL boot
      MENU LABEL NixOS Installer / Hypervisor
      LINUX /boot/bzImage
      APPEND init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams} initrd=/boot/initrd

    LABEL disk1
      MENU LABEL Boot from First Hard Disk (hd0)
      COM32 chain.c32
      APPEND hd0
      
    LABEL disk2
      MENU LABEL Boot from Second Hard Disk (hd1)
      COM32 chain.c32
      APPEND hd1
      
    LABEL reboot
      MENU LABEL Reboot
      COM32 reboot.c32
      
    LABEL poweroff
      MENU LABEL Power Off
      COM32 poweroff.c32
  '';
}
