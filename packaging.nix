{ inputs, ... }:

{
  images = { lib, pkgs, config, modulesPath, ... }: {
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
        
        # Image metadata
        isoImage.volumeID = "HYPER_RECOVERY";
        image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.iso";
        
        # Use GRUB theme from payload.nix
        isoImage.grubTheme = config.boot.loader.grub.theme;
        
        # Compression for smaller file size
        isoImage.squashfsCompression = "zstd -Xcompression-level 19";
        
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
        
        isoImage.volumeID = "HYPER_RECOVERY_DEBUG";
        image.fileName = lib.mkDefault "snosu-hyper-recovery-debug-x86_64-linux.iso";
        
        isoImage.grubTheme = config.boot.loader.grub.theme;
        isoImage.squashfsCompression = "zstd -Xcompression-level 19";
        
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
          # "plymouth.debug" # Too verbose, fills screen with Plymouth-internal logs
          # "splash" # Disabled in debug mode so we see text logs clearly
        ];

        # Explicitly disable Plymouth in debug mode to ensure clean text console
        boot.plymouth.enable = false;

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
