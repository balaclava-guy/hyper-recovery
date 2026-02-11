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
  # COCKPIT WEB UI BRANDING
  #############################################################################
  
  # Cockpit login title
  services.cockpit.settings.WebService.LoginTitle = lib.mkDefault "SNOSU: Hyper Recovery";
  
  # Cockpit 353+ reads branding from flat files in /etc/cockpit/branding/
  environment.etc = {
    "cockpit/branding/branding.css".source = "${brandingDir}/branding.css";
    "cockpit/branding/logo.png".source = "${brandingDir}/logo-source.png";
    "cockpit/branding/brand-large.png".source = "${brandingDir}/logo-source.png";
    "cockpit/branding/apple-touch-icon.png".source = "${brandingDir}/logo-source.png";
    "cockpit/branding/favicon.ico".source = "${brandingDir}/logo-source.png";
    
    # Legacy layout for compatibility with older Cockpit behavior
    "cockpit/branding/snosu/branding.ini".source = "${brandingDir}/branding.ini";
    "cockpit/branding/snosu/branding.css".source = "${brandingDir}/branding.css";
    "cockpit/branding/snosu/logo.png".source = "${brandingDir}/logo-source.png";
    "cockpit/branding/snosu/brand-large.png".source = "${brandingDir}/logo-source.png";
    "cockpit/branding/snosu/apple-touch-icon.png".source = "${brandingDir}/logo-source.png";
    "cockpit/branding/snosu/favicon.ico".source = "${brandingDir}/logo-source.png";
  };

  #############################################################################
  # TERMINAL MOTD
  #############################################################################
  
  environment.etc."motd".text = ''
    Welcome to SNOSU: Hyper Recovery Environment
    * Access the Web UI at: https://<IP>:9090
    * Default user: snosu / nixos
  '';

  environment.etc."snosu/motd-logo.ansi".source = "${assetsDir}/motd-logo.ansi";
}
