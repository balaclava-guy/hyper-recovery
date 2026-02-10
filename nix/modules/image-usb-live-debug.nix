{ lib, pkgs, config, ... }:

# USB Live Image (Debug) - ISO-specific configuration
# This module contains ONLY ISO image settings, not system configuration
# Debug system configuration comes from debug-overlay.nix

{
  imports = [
    ./grub-iso-image.nix
  ];

  # Enable unified GRUB bootloader
  isoImage.useUnifiedGrub = true;

  # Same hybrid boot setup as regular
  isoImage.makeEfiBootable = true;
  isoImage.makeBiosBootable = true;
  isoImage.makeUsbBootable = true;

  # Debug image metadata
  isoImage.volumeID = "HYPER_RECOVERY_DEBUG";
  image.fileName = lib.mkDefault "snosu-hyper-recovery-debug-x86_64-linux.iso";
  
  # Use GRUB theme from boot-branding module
  isoImage.grubTheme = config.boot.loader.grub.theme;
  
  # Use conservative compression for debug image to rule out FS issues
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
  
  # Clean boot menu labels
  system.nixos.distroName = "";
  system.nixos.label = "";
  isoImage.prependToMenuLabel = "START HYPER RECOVERY (Debug)";
  isoImage.appendToMenuLabel = "";

  # USB/CD-ROM kernel modules
  boot.initrd.kernelModules = [ "loop" "isofs" "usb_storage" "uas" "sd_mod" ];
}
