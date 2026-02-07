{ lib, config, ... }:

{
  # ISO Specifics
  # Maximize compression (slower build, smaller ISO)
  isoImage.squashfsCompression = "zstd -Xcompression-level 19";

  # Set the ISO filename
  isoImage.isoName = "snosu-hyper-recovery-x86_64-linux.iso";
  
  # Set Volume ID for reliable booting
  isoImage.volumeID = "SNOSU_RECOVERY";

  # Prefer themed GRUB menu (UEFI only)
  isoImage.makeEfiBootable = true;
  isoImage.makeBiosBootable = false;

  # Use custom GRUB theme for the ISO bootloader
  isoImage.grubTheme = config.boot.loader.grub.theme;
  isoImage.splashImage = config.boot.loader.grub.splashImage;

  # Rename the default installer entry
  isoImage.prependToMenuLabel = "START HYPER RECOVERY";
  isoImage.appendToMenuLabel = ""; # Clear default
}
