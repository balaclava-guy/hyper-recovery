{ inputs, ... }:

{
  images = { lib, pkgs, config, modulesPath, ... }: {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/image/images.nix"
    ];

    image.modules = {
      usb-live = { lib, pkgs, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/virtualisation/disk-image.nix"
        ];

        image.fileName = lib.mkDefault "snosu-hyper-recovery-x86_64-linux.img";
        image.format = "raw";
        image.baseName = "snosu-hyper-recovery";
        
        # Enable EFI support for GPT partition table with ESP
        image.efiSupport = true;
        
        # Note: disk-image.nix handles partitioning and filesystems
        # It creates: GPT table, ESP partition, root partition
        # GRUB is installed for EFI by default when efiSupport = true
        # For hybrid BIOS boot, we rely on GRUB's configuration in payload.nix
        
        # Filesystem and boot support for USB devices
        boot.initrd.kernelModules = [ "usb_storage" "uas" "sd_mod" ];
      };

      usb-live-debug = { lib, pkgs, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/virtualisation/disk-image.nix"
        ];

        image.fileName = lib.mkDefault "snosu-hyper-recovery-debug-x86_64-linux.img";
        image.format = "raw";
        image.baseName = "snosu-hyper-recovery-debug";
        image.efiSupport = true;

        # Debug kernel parameters
        boot.kernelParams = lib.mkForce [
          "loglevel=7"
          "systemd.log_level=debug"
          "systemd.log_target=console"
          "rd.debug"
          "plymouth.debug"
          "splash"
        ];

        boot.initrd.kernelModules = [ "usb_storage" "uas" "sd_mod" ];
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
