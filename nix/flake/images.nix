{ self, inputs, ... }:

# Flake-parts module for NixOS image configurations
# Defines nixosConfigurations and image build outputs

let
  mkUsbImage = { debug ? false }:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        [
          # Core system modules (clean, no debug)
          self.nixosModules.base
          self.nixosModules.hardware
          self.nixosModules.branding
          self.nixosModules.services
          self.nixosModules.hyper-connect

          # ISO image infrastructure
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
          self.nixosModules.iso-base

          # Shared image specifics
          {
            isoImage.volumeID = if debug then "HYPER-RECOVERY-DEBUG" else "HYPER-RECOVERY";
            image.baseName = inputs.nixpkgs.lib.mkForce (
              if debug then "snosu-hyper-recovery-debug-x86_64-linux" else "snosu-hyper-recovery-x86_64-linux"
            );
            isoImage.prependToMenuLabel = if debug then "START HYPER RECOVERY (Debug)" else "START HYPER RECOVERY";

            # Enable WiFi setup service
            services.hyper-connect = {
              enable = true;
              autoStartTui = true;
            };
          }
        ]
        ++ inputs.nixpkgs.lib.optionals debug [
          # Debug enhancements (the ONLY difference)
          self.nixosModules.debug
        ];
    };
in
{
  # Export NixOS modules for reuse
  flake.nixosModules = {
    base = import ../modules/system/base.nix;
    hardware = import ../modules/system/hardware.nix;
    branding = import ../modules/system/branding.nix;
    services = import ../modules/system/services.nix;
    debug = import ../modules/system/debug.nix;
    hyper-connect = import ../modules/system/hyper-connect.nix;
    iso-base = import ../modules/iso/base.nix;
    iso-grub-bootloader = import ../modules/iso/grub-bootloader.nix;
  };

  # Define NixOS configurations at flake level
  flake.nixosConfigurations = {
    usb-live = mkUsbImage { };
    usb-live-debug = mkUsbImage { debug = true; };
  };

  perSystem = { pkgs, system, lib, ... }:
    lib.optionalAttrs (system == "x86_64-linux") (
      let
        usbImage = self.nixosConfigurations.usb-live.config.system.build.isoImage;
        usbDebugImage = self.nixosConfigurations.usb-live-debug.config.system.build.isoImage;

        mkCompressedArtifacts = { name, imageRoots }:
          pkgs.runCommand name {
            nativeBuildInputs = [ pkgs._7zz pkgs.findutils pkgs.coreutils ];
          } ''
            set -euo pipefail
            mkdir -p $out

            files=$(find -L ${lib.escapeShellArgs (map builtins.toString imageRoots)} -type f \( \
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
      in
      {
        packages = {
          # USB Live Images
          usb = usbImage;
          usb-debug = usbDebugImage;

          # Meta-packages
          image = pkgs.linkFarm "snosu-image" [
            { name = "usb"; path = usbImage; }
          ];
          image-debug = pkgs.linkFarm "snosu-image-debug" [
            { name = "usb-debug"; path = usbDebugImage; }
          ];
          image-all = pkgs.linkFarm "snosu-image-all" [
            { name = "usb"; path = usbImage; }
            { name = "usb-debug"; path = usbDebugImage; }
          ];

          # Compressed artifacts
          image-compressed = mkCompressedArtifacts {
            name = "snosu-hyper-recovery-image-compressed";
            imageRoots = [ usbImage ];
          };
          image-debug-compressed = mkCompressedArtifacts {
            name = "snosu-hyper-recovery-image-debug-compressed";
            imageRoots = [ usbDebugImage ];
          };
          image-all-compressed = mkCompressedArtifacts {
            name = "snosu-hyper-recovery-image-all-compressed";
            imageRoots = [ usbImage usbDebugImage ];
          };
        };
      }
    );
}
