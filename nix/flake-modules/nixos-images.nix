{ self, inputs, ... }:

{
  # Export NixOS modules for reuse
  flake.nixosModules = {
    base-system = import ../modules/base-system.nix;
    hardware = import ../modules/hardware.nix;
    boot-branding = import ../modules/boot-branding.nix;
    services = import ../modules/services.nix;
    debug-overlay = import ../modules/debug-overlay.nix;
    grub-iso-image = import ../modules/grub-iso-image.nix;
    image-usb-live = import ../modules/image-usb-live.nix;
    image-usb-live-debug = import ../modules/image-usb-live-debug.nix;
  };

  # Define NixOS configurations at flake level
  flake.nixosConfigurations = {
    # Regular USB Live Image (Clean, production-ready)
    usb-live = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Apply cockpit overlay
        { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
        
        # Core system modules (clean, no debug)
        self.nixosModules.base-system
        self.nixosModules.hardware
        self.nixosModules.boot-branding
        self.nixosModules.services
        
        # ISO image infrastructure from nixpkgs
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        
        # ISO image configuration
        self.nixosModules.image-usb-live
      ];
    };

    # Debug USB Live Image (Regular + debug overlay)
    usb-live-debug = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Apply cockpit overlay
        { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
        
        # Core system modules (same as regular)
        self.nixosModules.base-system
        self.nixosModules.hardware
        self.nixosModules.boot-branding
        self.nixosModules.services
        
        # Debug enhancements
        self.nixosModules.debug-overlay
        
        # ISO image infrastructure from nixpkgs
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        
        # Debug ISO configuration
        self.nixosModules.image-usb-live-debug
      ];
    };
  };

  perSystem = { pkgs, system, lib, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages = {
        # 1. USB Live Image (Hybrid BIOS/EFI ISO) - Regular
        usb = self.nixosConfigurations.usb-live.config.system.build.isoImage;

        # 2. USB Live Image (Debug variant with verbose logging)
        usb-debug = self.nixosConfigurations.usb-live-debug.config.system.build.isoImage;

        # Meta-package for CI to build everything
        images = pkgs.linkFarm "snosu-images" [
          { name = "usb"; path = self.nixosConfigurations.usb-live.config.system.build.isoImage; }
          { name = "usb-debug"; path = self.nixosConfigurations.usb-live-debug.config.system.build.isoImage; }
        ];

        # Compressed artifacts - individual 7z files (one per image)
        images-7z = pkgs.runCommand "snosu-hyper-recovery-images-7z" {
          nativeBuildInputs = [ pkgs._7zz pkgs.findutils pkgs.coreutils ];
        } ''
          set -euo pipefail
          mkdir -p $out

          images_root="${self.nixosConfigurations.usb-live.config.system.build.isoImage}"
          images_debug_root="${self.nixosConfigurations.usb-live-debug.config.system.build.isoImage}"

          # Find all image files (including ISO for hybrid USB images)
          files=$(find -L "$images_root" "$images_debug_root" -type f \( \
            -name "*.iso" -o -name "*.img" -o -name "*.raw" \
          \) || true)

          if [ -z "$files" ]; then
            echo "No image artifacts found" >&2
            echo "Checked directories:" >&2
            echo "  - $images_root" >&2
            echo "  - $images_debug_root" >&2
            exit 1
          fi

          # Process each file and normalize names for CI stability
          while IFS= read -r file; do
            if [ -z "$file" ]; then continue; fi

            base_name=$(basename "$file")
            parent_path=$(dirname "$file")

            # Determine standardized output name based on which config it came from
            if [[ "$parent_path" == *"usb-live-debug"* ]]; then
              out_name="hyper-recovery-debug.iso.7z"
            else
              out_name="hyper-recovery-live.iso.7z"
            fi

            echo "Compressing $base_name -> $out_name..."
            7zz a -t7z -mx=9 -mmt -ms=on "$out/$out_name" "$file"
          done <<< "$files"

          echo "Compression complete. Normalized Artifacts:"
          ls -lh $out/
        '';
      };
    };
}
