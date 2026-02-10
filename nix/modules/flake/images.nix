{ self, inputs, ... }:

# Flake-parts module for NixOS image configurations
# Defines nixosConfigurations and image build outputs

{
  # Export NixOS modules for reuse
  flake.nixosModules = {
    base = import ../system/base.nix;
    hardware = import ../system/hardware.nix;
    branding = import ../system/branding.nix;
    services = import ../system/services.nix;
    debug = import ../system/debug.nix;
    wifi-setup = import ../system/wifi-setup.nix;
    iso-base = import ../iso/base.nix;
    iso-grub-bootloader = import ../iso/grub-bootloader.nix;
  };

  # Define NixOS configurations at flake level
  flake.nixosConfigurations = {
    # Regular USB Live Image (Clean, production-ready)
    usb-live = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
        
        # Core system modules (clean, no debug)
        self.nixosModules.base
        self.nixosModules.hardware
        self.nixosModules.branding
        self.nixosModules.services
        self.nixosModules.wifi-setup
        
        # ISO image infrastructure
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        self.nixosModules.iso-base
        
        # Regular image specifics
        {
          isoImage.volumeID = "HYPER_RECOVERY";
          image.fileName = "snosu-hyper-recovery-x86_64-linux.iso";
          isoImage.prependToMenuLabel = "START HYPER RECOVERY";
          
          # Enable WiFi setup service
          services.hyper-wifi-setup = {
            enable = true;
            autoStartTui = true;
          };
        }
      ];
    };

    # Debug USB Live Image (Regular + debug overlay)
    usb-live-debug = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
        
        # Core system modules (same as regular)
        self.nixosModules.base
        self.nixosModules.hardware
        self.nixosModules.branding
        self.nixosModules.services
        self.nixosModules.wifi-setup
        
        # Debug enhancements (the ONLY difference)
        self.nixosModules.debug
        
        # ISO image infrastructure
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        self.nixosModules.iso-base
        
        # Debug image specifics
        {
          isoImage.volumeID = "HYPER_RECOVERY_DEBUG";
          image.fileName = "snosu-hyper-recovery-debug-x86_64-linux.iso";
          isoImage.prependToMenuLabel = "START HYPER RECOVERY (Debug)";
          
          # Enable WiFi setup service
          services.hyper-wifi-setup = {
            enable = true;
            autoStartTui = true;
          };
        }
      ];
    };
  };

  perSystem = { pkgs, system, lib, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages = {
        # USB Live Image (Regular)
        usb = self.nixosConfigurations.usb-live.config.system.build.isoImage;

        # USB Live Image (Debug)
        usb-debug = self.nixosConfigurations.usb-live-debug.config.system.build.isoImage;

        # Meta-package for CI
        images = pkgs.linkFarm "snosu-images" [
          { name = "usb"; path = self.nixosConfigurations.usb-live.config.system.build.isoImage; }
          { name = "usb-debug"; path = self.nixosConfigurations.usb-live-debug.config.system.build.isoImage; }
        ];

        # Compressed artifacts for CI
        images-7z = pkgs.runCommand "snosu-hyper-recovery-images-7z" {
          nativeBuildInputs = [ pkgs._7zz pkgs.findutils pkgs.coreutils ];
        } ''
          set -euo pipefail
          mkdir -p $out

          images_root="${self.nixosConfigurations.usb-live.config.system.build.isoImage}"
          images_debug_root="${self.nixosConfigurations.usb-live-debug.config.system.build.isoImage}"

          files=$(find -L "$images_root" "$images_debug_root" -type f \( \
            -name "*.iso" -o -name "*.img" -o -name "*.raw" \
          \) || true)

          if [ -z "$files" ]; then
            echo "No image artifacts found" >&2
            exit 1
          fi

          while IFS= read -r file; do
            if [ -z "$file" ]; then continue; fi

            base_name=$(basename "$file")
            parent_path=$(dirname "$file")

            if [[ "$parent_path" == *"debug"* ]]; then
              out_name="hyper-recovery-debug.iso.7z"
            else
              out_name="hyper-recovery-live.iso.7z"
            fi

            echo "Compressing $base_name -> $out_name..."
            7zz a -t7z -mx=9 -mmt -ms=on "$out/$out_name" "$file"
          done <<< "$files"

          ls -lh $out/
        '';
      };
    };
}
