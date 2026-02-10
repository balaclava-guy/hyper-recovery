{ lib, pkgs, config, ... }:

# USB Live Image Base Configuration
# Common settings for ALL ISO variants (regular and debug)
# Specific variants only override what's different (volume ID, filename, menu label)

{
  imports = [
    ./grub-bootloader.nix
  ];

  # Enable unified GRUB bootloader (replaces syslinux for BIOS)
  isoImage.useUnifiedGrub = true;

  # Hybrid boot configuration - works on both BIOS and EFI systems
  isoImage.makeEfiBootable = true;
  isoImage.makeBiosBootable = true;
  isoImage.makeUsbBootable = true;

  # Use GRUB theme from branding module
  isoImage.grubTheme = config.boot.loader.grub.theme;
  
  # Compression for smaller file size
  # NOTE: Using standard compression (level 3) for maximum compatibility
  # and to prevent "Invalid argument" OverlayFS errors during boot.
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";
  
  # Clean boot menu labels (base - variants can override)
  system.nixos.distroName = "";
  system.nixos.label = "";
  isoImage.appendToMenuLabel = "";
  
  # USB/CD-ROM kernel modules
  boot.initrd.kernelModules = [ "loop" "isofs" "usb_storage" "uas" "sd_mod" ];
}
