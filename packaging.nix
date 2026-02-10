{ inputs, ... }:

{
  images = { lib, pkgs, config, modulesPath, ... }:
  {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/image/images.nix"
    ];

    image.modules = {
      # Hybrid BIOS/EFI USB image using ISO format
      # Modern ISO images are designed for USB deployment with dd or Ventoy
      # They include hybrid MBR for BIOS and ESP for EFI in one image
      # 
      # This configuration uses unified GRUB2 for both BIOS and EFI boot,
      # providing a consistent boot experience across all firmware types.
      usb-live = { lib, pkgs, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
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
          ./grub-iso-image.nix
        ];

        # Enable unified GRUB bootloader
        isoImage.useUnifiedGrub = true;

        # Same hybrid boot setup
        isoImage.makeEfiBootable = true;
        isoImage.makeBiosBootable = true;
        isoImage.makeUsbBootable = true;

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
          "console=ttyS0,115200"
          "hyper.debug=1"
        ];

        # Keep Plymouth enabled for debugging the theme
        boot.plymouth.enable = true;

        boot.initrd.kernelModules = [ "loop" "isofs" "usb_storage" "uas" "sd_mod" ];
      };
    };
  };
}
