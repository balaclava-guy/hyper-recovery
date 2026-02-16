{ config, pkgs, lib, ... }:

# Centralized branding configuration for Hyper Recovery
# All visual identity and branding for:
# - Plymouth boot splash
# - GRUB bootloader theme
# - Cockpit web UI
# - Terminal MOTD
# - Future: noVNC, etc.

let
  # Theme packages
  snosuPlymouthTheme = pkgs.callPackage ../../packages/themes/plymouth.nix {};
  snosuGrubTheme = pkgs.callPackage ../../packages/themes/grub.nix {};
  
  # Asset paths
  assetsDir = ../../../assets;
  brandingDir = "${assetsDir}/branding";
in
{
  #############################################################################
  # PLYMOUTH BOOT SPLASH
  #############################################################################
  
  boot.initrd.systemd.enable = true;
  boot.plymouth = {
    enable = lib.mkForce true;
    theme = "snosu-hyper-recovery";
    themePackages = [ snosuPlymouthTheme ];
    font = "${snosuPlymouthTheme}/share/fonts/truetype/undefined-medium.ttf";
  };

  #############################################################################
  # GRUB BOOTLOADER THEME
  #############################################################################
  
  boot.loader.grub = {
    enable = true;
    theme = snosuGrubTheme;
    splashImage = "${snosuGrubTheme}/background.png";
    
    # Hybrid boot support - both EFI and BIOS
    efiSupport = true;
    efiInstallAsRemovable = true;  # Critical for Ventoy compatibility
    device = "nodev";
    
    useOSProber = true;  # Detect other OSes on local drives
  };
  
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.memtest86.enable = false;

  #############################################################################
  # WEB UI BRANDING (LXCONSOLE)
  #############################################################################

  # Placeholder for future lxconsole branding
  # Will be populated when lxconsole package is added

  #############################################################################
  # TERMINAL MOTD
  #############################################################################
  
  environment.etc."motd".text = ''
    Welcome to SNOSU: Hyper Recovery Environment
    * Access the Web UI at: http://<IP>:5000
    * Default user: snosu / nixos
  '';

  environment.etc."snosu/motd-logo.ansi".source = "${assetsDir}/motd-logo.ansi";
}
