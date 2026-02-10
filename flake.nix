{
  description = "Snosu Hyper Recovery Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    # TODO(2026-02-10): Temporary workaround.
    #
    # NixOS Cockpit's module builds a `cockpit-plugins-env` buildEnv that links `/bin`
    # from all plugin `passthru.cockpitPath` entries. On our pinned nixpkgs, Cockpit
    # itself pulls Python 3.13 while `cockpit-zfs` pulls a Python 3.12 env, and both
    # provide `bin/idle3`, causing a buildEnv path collision in CI.
    #
    # Remove once nixpkgs resolves the Python version mismatch, or the Cockpit module
    # stops linking `/bin` from plugin dependency envs.
    cockpitZfsOverlay = final: prev: {
      # Prefer dropping Cockpit's python from cockpitPath (to avoid buildEnv /bin collisions)
      # over dropping cockpit-zfs' python, since cockpit-zfs explicitly depends on python312.
      cockpit = prev.cockpit.overrideAttrs (old: {
        passthru = (old.passthru or {}) // {
          cockpitPath =
            prev.lib.filter
              (p: !(prev.lib.hasInfix "python3" (builtins.toString p)))
              (old.passthru.cockpitPath or []);
        };
      });
    };

    # Common OS configuration (The Payload)
    payload = ./payload.nix;

    # Image Packaging Definitions
    packaging = import ./packaging.nix { inherit inputs; };

    myOS = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        { nixpkgs.overlays = [ cockpitZfsOverlay ]; }
        payload
        packaging.images
      ];
    };

    pocOS = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./poc-debug.nix
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
      ];
    };

    # Minimal ISO purely for iterating on GRUB + Plymouth themes.
    themeOS = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./theme-preview-iso.nix
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
        ./grub-iso-image.nix
      ];
    };
  in
  {
    devShells.${system}.default = pkgs.mkShell {
      packages = [ pkgs.p7zip ];
    };

    packages.${system} = {
      # 1. USB Live Image (Hybrid BIOS/EFI ISO)
      # Note: Modern ISOs are hybrid images designed for USB deployment
      # Can be written to USB with dd or booted via Ventoy
      usb = myOS.config.system.build.images.usb-live;

      # 2. USB Live Image (Debug variant with verbose logging)
      usb-debug = myOS.config.system.build.images.usb-live-debug;

      # POC minimal ISO for initrd log capture
      poc-iso = pocOS.config.system.build.isoImage;

      # Theme preview ISO (GRUB theme + Plymouth theme, minimal userspace)
      theme-iso = themeOS.config.system.build.isoImage;

      poc-images-7z = pkgs.runCommand "snosu-hyper-recovery-poc-7z" {
        nativeBuildInputs = [ pkgs._7zz pkgs.coreutils ];
      } ''
        set -euo pipefail
        mkdir -p $out

        shopt -s nullglob
        isos=(${pocOS.config.system.build.isoImage}/iso/*.iso)
        if [ "''${#isos[@]}" -eq 0 ]; then
          echo "No ISO found under ${pocOS.config.system.build.isoImage}/iso" >&2
          ls -lah ${pocOS.config.system.build.isoImage} >&2
          exit 1
        fi

        7zz a -t7z -mx=9 -mmt -ms=on "$out/hyper-recovery-live.iso.7z" "''${isos[0]}"
      '';

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
            # Fallback for anything else (shouldn't happen with current setup)
            out_name="''${base_name}.7z"
          fi
          
          echo "Compressing $parent_dir/$base_name -> $out_name..."
          
          # Compress with 7zz
          # -mx=9: We keep high compression for the *artifact container* (the .7z file)
          # because this runs on the build runner, not inside the booted OS.
          # The "Invalid argument" error comes from the internal ISO squashfs, not this .7z.
          7zz a -t7z -mx=9 -mmt -ms=on "$out/$out_name" "$file"
        done <<< "$files"
        
        echo "Compression complete. Normalized Artifacts:"
        ls -lh $out/
      '';
    };
  };
}
