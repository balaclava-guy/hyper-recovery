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

        # Process each file and normalize names for CI stability
        while IFS= read -r file; do
          if [ -z "$file" ]; then continue; fi
          
          base_name=$(basename "$file")
          parent_dir=$(basename "$(dirname "$file")")
          
          # Determine standardized output name based on parent directory and file type
          # The linkFarm creates usb/, usb-debug/, vm/ directories
          if [[ "$parent_dir" == *"debug"* ]]; then
            out_name="hyper-recovery-debug.iso.7z"
          elif [[ "$base_name" == *".iso" ]]; then
            out_name="hyper-recovery-live.iso.7z"
          elif [[ "$base_name" == *".qcow2" ]]; then
            out_name="hyper-recovery-vm.qcow2.7z"
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
