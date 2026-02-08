{ inputs, ... }:

{
  images = { lib, ... }: {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/image/images.nix"
    ];

    image.modules = {
      iso = { lib, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ];

        image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.iso";
        isoImage.volumeID = "SNOSU_RECOVERY";
        isoImage.makeEfiBootable = true;
        isoImage.makeBiosBootable = true;
        isoImage.squashfsCompression = "zstd -Xcompression-level 19";

        isoImage.grubTheme = config.boot.loader.grub.theme;

        system.nixos.distroName = "";
        system.nixos.label = "";
        isoImage.prependToMenuLabel = "START HYPER RECOVERY";
        isoImage.appendToMenuLabel = "";

        boot.initrd.kernelModules = [ "loop" "isofs" ];
      };

      iso-debug = { lib, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ];

        image.fileName = lib.mkDefault "snosu-hyper-recovery-debug-x86_64-linux.iso";
        isoImage.volumeID = "SNOSU_RECOVERY";
        isoImage.makeEfiBootable = true;
        isoImage.makeBiosBootable = true;
        isoImage.squashfsCompression = "zstd -Xcompression-level 19";

        isoImage.grubTheme = config.boot.loader.grub.theme;

        system.nixos.distroName = "";
        system.nixos.label = "";
        isoImage.prependToMenuLabel = "START HYPER RECOVERY (Debug)";
        isoImage.appendToMenuLabel = "";

        boot.kernelParams = lib.mkAfter [
          "loglevel=7"
          "systemd.log_level=debug"
          "systemd.log_target=console"
          "rd.debug"
          "plymouth.debug"
        ];

        boot.initrd.kernelModules = [ "loop" "isofs" ];
      };

      raw-efi = { lib, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/virtualisation/disk-image.nix"
        ];

        image.format = "raw";
        image.efiSupport = true;
        image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.img";
      };

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
