{ lib, config, ... }:

{
  # ISO Specifics
  # Maximize compression (slower build, smaller ISO)
  isoImage.squashfsCompression = "zstd -Xcompression-level 19";

  # Set the ISO filename
  isoImage.isoName = "snosu-hyper-recovery-x86_64-linux.iso";
  
  # Set Volume ID for reliable booting
  isoImage.volumeID = "SNOSU_RECOVERY";

  # Use custom GRUB theme for the ISO bootloader
  isoImage.grubTheme = config.boot.loader.grub.theme;
  isoImage.splashImage = config.boot.loader.grub.splashImage;

  # Rename the default installer entry
  isoImage.prependToMenuLabel = "START HYPER RECOVERY";
  isoImage.appendToMenuLabel = ""; # Clear default

  # Syslinux Menu (BIOS)
  isoImage.syslinuxTheme = lib.mkForce ''
    DEFAULT boot
    TIMEOUT 100
    PROMPT 1

    UI menu.c32

    MENU TITLE Hypervisor OS Boot CD

    LABEL boot
      MENU LABEL START HYPER RECOVERY
      LINUX /boot/bzImage
      APPEND init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams} initrd=/boot/initrd root=live:CDLABEL=SNOSU_RECOVERY

    LABEL disk1
      MENU LABEL Boot from First Hard Disk (hd0)
      COM32 chain.c32
      APPEND hd0

    LABEL disk2
      MENU LABEL Boot from Second Hard Disk (hd1)
      COM32 chain.c32
      APPEND hd1

    MENU BEGIN Other
      MENU TITLE Other Options

      LABEL reboot
        MENU LABEL Reboot
        COM32 reboot.c32

      LABEL poweroff
        MENU LABEL Power Off
        COM32 poweroff.c32
    MENU END
  '';
}
