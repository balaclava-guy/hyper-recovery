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

  perSystem = { pkgs, system, lib, ... }:
    lib.optionalAttrs (system == "x86_64-linux") (
      let
        # Helper to build NixOS system with image output
        buildImage = modules: imageName:
          let
            nixosSystem = inputs.nixpkgs.lib.nixosSystem {
              inherit system;
              modules = modules;
            };
          in
          nixosSystem.config.system.build.images.${imageName};

        # Regular USB Live Image (Clean, production-ready)
        regularModules = [
          # Apply cockpit overlay
          { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
          
          # Core system modules (clean, no debug)
          self.nixosModules.base-system
          self.nixosModules.hardware
          self.nixosModules.boot-branding
          self.nixosModules.services
          
          # Image packaging
          (import ../../packaging.nix { inherit inputs; }).images
          
          # ISO image configuration (from old packaging.nix structure)
          self.nixosModules.image-usb-live
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ];

        # Debug USB Live Image (Regular + debug overlay)
        debugModules = [
          # Apply cockpit overlay
          { nixpkgs.overlays = [ self.overlays.cockpitZfs ]; }
          
          # Core system modules (same as regular)
          self.nixosModules.base-system
          self.nixosModules.hardware
          self.nixosModules.boot-branding
          self.nixosModules.services
          
          # Debug enhancements
          self.nixosModules.debug-overlay
          
          # Image packaging
          (import ../../packaging.nix { inherit inputs; }).images
          
          # Debug ISO configuration
          self.nixosModules.image-usb-live-debug
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ];

      in
      {
        packages = {
          # 1. USB Live Image (Hybrid BIOS/EFI ISO) - Regular
          usb = buildImage regularModules "usb-live";

          # 2. USB Live Image (Debug variant with verbose logging)
          usb-debug = buildImage debugModules "usb-live-debug";

          # Meta-package for CI to build everything
          images = pkgs.linkFarm "snosu-images" [
            { name = "usb"; path = self.packages.${system}.usb; }
            { name = "usb-debug"; path = self.packages.${system}.usb-debug; }
          ];

          # Compressed artifacts - individual 7z files (one per image)
          images-7z = pkgs.runCommand "snosu-hyper-recovery-images-7z" {
            nativeBuildInputs = [ pkgs._7zz pkgs.findutils pkgs.coreutils ];
          } ''
            set -euo pipefail
            mkdir -p $out

            images_root="${self.packages.${system}.images}"

            # Find all image files (including ISO for hybrid USB images)
            files=$(find -L "$images_root" -type f \( \
              -name "*.iso" -o -name "*.img" -o -name "*.raw" \
            \) || true)

            if [ -z "$files" ]; then
              echo "No image artifacts found under $images_root" >&2
              echo "Directory contents:" >&2
              find -L "$images_root" -maxdepth 4 -type f | head -n 50 >&2
              exit 1
            fi

            # Process each file and normalize names for CI stability
            while IFS= read -r file; do
              if [ -z "$file" ]; then continue; fi

              base_name=$(basename "$file")
              parent_dir=$(basename "$(dirname "$file")")

              # Determine standardized output name based on parent directory and file type
              if [[ "$parent_dir" == *"debug"* ]]; then
                out_name="hyper-recovery-debug.iso.7z"
              elif [[ "$base_name" == *".iso" ]]; then
                out_name="hyper-recovery-live.iso.7z"
              else
                out_name="''${base_name}.7z"
              fi

              echo "Compressing $parent_dir/$base_name -> $out_name..."
              7zz a -t7z -mx=9 -mmt -ms=on "$out/$out_name" "$file"
            done <<< "$files"

            echo "Compression complete. Normalized Artifacts:"
            ls -lh $out/
          '';
        };
      }
    );
}
