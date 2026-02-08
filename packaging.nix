{ inputs, ... }:

{
  images = { lib, pkgs, config, modulesPath, ... }:
  let
    biosSplash = ./snosu-hyper-recovery/isolinux/background.png;
    syslinuxTheme = ''
      MENU TITLE SNOSU HYPER RECOVERY
      MENU RESOLUTION 800 600
      MENU CLEAR
      MENU MARGIN 0
      MENU ROWS 6
      MENU VSHIFT 8
      MENU HSHIFT 40
      MENU WIDTH 30
      MENU CMDLINEROW -4
      MENU TABMSGROW  -2
      MENU HELPMSGROW -1
      MENU HELPMSGENDROW -1

      #                                FG:AARRGGBB  BG:AARRGGBB   shadow
      MENU COLOR BORDER       30;44      #00000000    #00000000   none
      MENU COLOR SCREEN       37;40      #FF000000    #00000000   none
      MENU COLOR TITLE        1;37;40    #FFFFFFFF    #00000000   none
      MENU COLOR UNSEL        37;40      #FFCFCFCF    #00000000   none
      MENU COLOR SEL          7;37;40    #FFFFFFFF    #00000000   none
      MENU COLOR TABMSG       31;40      #80000000    #00000000   none
      MENU COLOR TIMEOUT      1;37;40    #FF000000    #00000000   none
      MENU COLOR TIMEOUT_MSG  37;40      #FF000000    #00000000   none
      MENU COLOR CMDMARK      1;36;40    #FF000000    #00000000   none
      MENU COLOR CMDLINE      37;40      #FF000000    #00000000   none
    '';
  in {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/image/images.nix"
    ];

    image.modules = {
      # Hybrid BIOS/EFI USB image using ISO format
      # Modern ISO images are designed for USB deployment with dd or Ventoy
      # They include hybrid MBR for BIOS and ESP for EFI in one image
      usb-live = { lib, pkgs, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ];

        # Hybrid boot configuration - works on both BIOS and EFI systems
        isoImage.makeEfiBootable = true;      # EFI boot via GRUB
        isoImage.makeBiosBootable = true;     # BIOS boot via syslinux
        isoImage.makeUsbBootable = true;      # Hybrid MBR for USB drives

        # BIOS boot theme (syslinux/isolinux)
        isoImage.splashImage = biosSplash;
        isoImage.syslinuxTheme = syslinuxTheme;
        
        # Image metadata
        isoImage.volumeID = "HYPER_RECOVERY";
        image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.iso";
        
        # Use GRUB theme from payload.nix
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
      };

      # Debug variant with verbose logging
      usb-live-debug = { lib, pkgs, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ];

        # Same hybrid boot setup
        isoImage.makeEfiBootable = true;
        isoImage.makeBiosBootable = true;
        isoImage.makeUsbBootable = true;

        # BIOS boot theme (syslinux/isolinux)
        isoImage.splashImage = biosSplash;
        isoImage.syslinuxTheme = syslinuxTheme;
        
        isoImage.volumeID = "HYPER_RECOVERY_DEBUG";
        image.fileName = lib.mkDefault "snosu-hyper-recovery-debug-x86_64-linux.iso";
        
        isoImage.grubTheme = config.boot.loader.grub.theme;
        # Use more conservative compression for debug image to rule out FS issues
        isoImage.squashfsCompression = "zstd -Xcompression-level 3";
        
        system.nixos.distroName = "";
        system.nixos.label = "";
        isoImage.prependToMenuLabel = "START HYPER RECOVERY (Debug)";
        isoImage.appendToMenuLabel = "";

        # Debug kernel parameters
        boot.kernelParams = lib.mkForce [
          "loglevel=7"
          "systemd.log_level=debug"
          "systemd.log_target=console"
          "rd.debug"
          "plymouth.debug"
          "splash"
        ];

        # Keep Plymouth enabled for debugging the theme
        boot.plymouth.enable = true;

        boot.initrd.kernelModules = [ "loop" "isofs" "usb_storage" "uas" "sd_mod" ];
      };

      # VM image for testing (EFI only)
      qemu-efi = { lib, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/virtualisation/disk-image.nix"
        ];

        image.format = "qcow2";
        image.efiSupport = true;
        image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.qcow2";
      };
    };
  };
}
