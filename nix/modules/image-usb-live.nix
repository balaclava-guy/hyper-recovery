{ lib, pkgs, config, ... }:

# USB Live Image (Regular) - ISO-specific configuration
# This module contains ONLY ISO image settings, not system configuration

{
  imports = [
    ./grub-iso-image.nix
  ];

  # Enable unified GRUB bootloader (replaces syslinux for BIOS)
  isoImage.useUnifiedGrub = true;

  # Hybrid boot configuration - works on both BIOS and EFI systems
  isoImage.makeEfiBootable = true;      # EFI boot via GRUB
  isoImage.makeBiosBootable = true;     # BIOS boot via GRUB (unified)
  isoImage.makeUsbBootable = true;      # Hybrid MBR for USB drives

  # Image metadata
  isoImage.volumeID = "HYPER_RECOVERY";
  image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.iso";
  
  # Use GRUB theme from boot-branding module
  isoImage.grubTheme = config.boot.loader.grub.theme;
  
  # Compression for smaller file size
  # NOTE: Using standard compression (level 3) to ensure maximum compatibility
  # and prevent "Invalid argument" OverlayFS errors during boot.
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
  
  # Clean boot menu labels
  system.nixos.distroName = "";
  system.nixos.label = "";
  isoImage.prependToMenuLabel = "START HYPER RECOVERY";
  isoImage.appendToMenuLabel = "";
  
  # USB/CD-ROM kernel modules
  boot.initrd.kernelModules = [ "loop" "isofs" "usb_storage" "uas" "sd_mod" ];
}
