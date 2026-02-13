{ config, pkgs, lib, ... }:

# Base system configuration for Hyper Recovery environment
# Core system identity, users, networking, and packages

let
  scripts = pkgs.callPackage ../../packages/scripts {};
  motdScript = ../../../scripts/shell/snosu-motd.sh;
in
{
  # Core System Identity
  networking.hostName = "hyper-recovery";
  networking.hostId = "8425e349";
  system.stateVersion = "25.05";

  # Performance & Space Optimizations
  documentation.enable = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # ZFS & Filesystems
  boot.supportedFilesystems = [ "zfs" "exfat" "vfat" "iso9660" "squashfs" "overlay" ];
  boot.zfs.forceImportRoot = false;

  # Networking
  networking.networkmanager.enable = true;
  # Allow switching WiFi stack; default to iwd for Intel stability.
  networking.wireless.iwd.enable = true;
  networking.networkmanager.wifi.backend = "iwd";
  networking.dhcpcd.enable = false;

  # MOTD shell script (sourced on login)
  environment.etc."profile.d/snosu-motd.sh".source = motdScript;

  # Standard Packages (including user-facing diagnostic tools)
  environment.systemPackages = with pkgs; [
    qemu-utils zfs parted gptfdisk htop vim git perl
    pciutils usbutils smartmontools nvme-cli os-prober efibootmgr
    # WiFi tooling (NM backend can be iwd or wpa_supplicant).
    iwd wpa_supplicant dhcpcd udisks2
    networkmanager  # nmcli
    iw
    virt-manager # provides virt-install/virt-clone for VM creation
    plymouth  # For Plymouth debugging
    scripts.hyper-debug  # User-triggered diagnostics
    scripts.hyper-hw     # Firmware management
  ];

  # User Authentication
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
    # Allow Cockpit/libvirt access without root
    # Note: "libvirt" group is required for libvirt-dbus D-Bus policy
    extraGroups = [ "wheel" "libvirtd" "libvirt" "kvm" ];
  };

  # Create "libvirt" group for libvirt-dbus D-Bus policy compatibility.
  # The upstream libvirt-dbus D-Bus policy expects "libvirt" group, but NixOS
  # uses "libvirtd". We need both for full compatibility.
  users.groups.libvirt = {};

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkDefault "no";
  };
}
