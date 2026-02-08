{
  description = "Snosu Hyper Recovery Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    # Common OS configuration (The Payload)
    payload = ./payload.nix;

    # Image Packaging Definitions
    packaging = import ./packaging.nix { inherit inputs; };

    myOS = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        payload
        packaging.images
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

      # 3. VM Image (QCOW2 for testing)
      vm = myOS.config.system.build.images.qemu-efi;

      # Meta-package for CI to build everything
      images = pkgs.linkFarm "snosu-images" [
        { name = "usb"; path = self.packages.${system}.usb; }
        { name = "usb-debug"; path = self.packages.${system}.usb-debug; }
        { name = "vm"; path = self.packages.${system}.vm; }
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
          -name "*.iso" -o -name "*.img" -o -name "*.qcow2" -o -name "*.qcow" \
          -o -name "*.raw" -o -name "*.vmdk" -o -name "*.vhd" -o -name "*.vhdx" \
        \) || true)

        if [ -z "$files" ]; then
          echo "No image artifacts found under $images_root" >&2
          echo "Directory contents:" >&2
          find -L "$images_root" -maxdepth 4 -type f | head -n 50 >&2
          exit 1
        fi

        # Process each file
        while IFS= read -r file; do
          if [ -z "$file" ]; then continue; fi
          
          base_name=$(basename "$file")
          extension="''${base_name##*.}"
          
          if [[ "$extension" == "iso" ]]; then
            # ISOs are already compressed (SquashFS) and ready for DD.
            # Skip double compression to save time and give user immediate access.
            echo "Copying $base_name directly (no extra compression)..."
            cp "$file" "$out/$base_name"
          else
            # Compress other formats (qcow2, raw, etc) to save space
            echo "Compressing $base_name with 7zz (modern)..."
            # -mx=9: Ultra compression
            # -mmt: Multi-threading (default in 7zz)
            7zz a -t7z -mx=9 -mmt "$out/''${base_name}.7z" "$file"
            echo "Created $out/''${base_name}.7z"
          fi
        done <<< "$files"
        
        echo "Processing complete. Artifacts:"
        ls -lh $out/
      '';
    };
  };
}
