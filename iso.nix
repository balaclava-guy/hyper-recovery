{ config, pkgs, lib, ... }:

{
  # ZFS Support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false; # Don't auto-import on boot to avoid conflicts
  networking.hostId = "8425e349"; # Required for ZFS

  # Kernel & Hardware
  boot.kernelPackages = pkgs.linuxPackages_latest;
  
  # Hypervisor & Virtualization
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
      ovmf.enable = true;
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

  # User Configuration
  users.users.root.password = "nixos";
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # ISO Specifics
  isoImage.squashfsCompression = "zstd";
  
  # Serial console support
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];
  
  # Syslinux Menu (BIOS)
  # We override the default theme to add local boot options.
  # Note: This replaces the graphical NixOS menu with a text/simple menu.
  isoImage.syslinuxTheme = lib.mkForce ''
    DEFAULT boot
    TIMEOUT 100
    PROMPT 1
    
    UI menu.c32
    
    MENU TITLE Hypervisor OS Boot CD
    
    LABEL boot
      MENU LABEL NixOS Installer / Hypervisor
      LINUX /boot/bzImage
      INITRD /boot/initrd
      APPEND ${toString config.boot.kernelParams} init=${config.system.build.toplevel}/init

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
