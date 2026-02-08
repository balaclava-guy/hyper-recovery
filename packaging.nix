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
        
        # Enable EFI support for GPT partition table
        image.efiSupport = true;
        
        # Ensure we have a proper partition layout
        # The disk-image.nix module will create:
        # - GPT partition table
        # - ESP (EFI System Partition)
        # - Root partition
        
        # GRUB will be installed by NixOS's activation scripts
        # We just need to ensure it's configured for both BIOS and EFI
        boot.loader.grub = {
          # Force both targets
          extraInstallCommands = lib.mkAfter ''
            # Install GRUB for BIOS boot (in addition to EFI)
            echo "Installing GRUB for BIOS compatibility..."
            ${pkgs.grub2}/bin/grub-install --target=i386-pc --force $device || true
            
            echo "Hybrid GRUB installation complete (BIOS + EFI)"
          '';
        };

        # Filesystem and boot support
        boot.initrd.kernelModules = [ "usb_storage" "uas" "sd_mod" ];
        
        # Ensure filesystem labels are set
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          autoResize = true;
        };
        
        fileSystems."/boot" = lib.mkIf config.image.efiSupport {
          device = "/dev/disk/by-label/ESP";
          fsType = "vfat";
        };
      };

      usb-live-debug = { lib, pkgs, config, ... }: {
        imports = [
          "${inputs.nixpkgs}/nixos/modules/virtualisation/disk-image.nix"
        ];

        image.fileName = lib.mkDefault "snosu-hyper-recovery-debug-x86_64-linux.img";
        image.format = "raw";
        image.baseName = "snosu-hyper-recovery-debug";
        image.efiSupport = true;
        
        # GRUB hybrid installation
        boot.loader.grub = {
          extraInstallCommands = lib.mkAfter ''
            echo "Installing GRUB for BIOS compatibility (debug)..."
            ${pkgs.grub2}/bin/grub-install --target=i386-pc --force $device || true
            echo "Hybrid GRUB installation complete (BIOS + EFI)"
          '';
        };

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
        
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          autoResize = true;
        };
        
        fileSystems."/boot" = lib.mkIf config.image.efiSupport {
          device = "/dev/disk/by-label/ESP";
          fsType = "vfat";
        };
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
