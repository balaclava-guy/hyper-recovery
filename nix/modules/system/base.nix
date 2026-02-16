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
    # Allow incus access without root
    extraGroups = [ "wheel" "incus-admin" ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkDefault "no";
  };
}
