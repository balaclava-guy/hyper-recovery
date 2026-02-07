{
  description = "Snosu Hyper Recovery Environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    # Common OS configuration (The Payload)
    payload = ./payload.nix;

    # Image Packaging Definitions
    packaging = import ./packaging.nix { inherit inputs; };
  in
  {
    devShells.${system}.default = pkgs.mkShell {
      packages = [ pkgs.peazip pkgs.p7zip ];
    };

    packages.${system} = {
      # 1. Standard ISO
      iso = nixos-generators.nixosGenerate {
        inherit system;
        modules = [ packaging.iso ];
        format = "install-iso";
      };

      # 2. Debug ISO
      iso-debug = nixos-generators.nixosGenerate {
        inherit system;
        modules = [
          packaging.iso
          ({ lib, ... }: {
            isoImage.isoName = lib.mkForce "snosu-hyper-recovery-debug-x86_64-linux.iso";
            boot.kernelParams = [ "loglevel=7" "systemd.log_level=debug" "rd.debug" "plymouth.debug" ];
          })
        ];
        format = "install-iso";
      };

      # 3. Raw USB Image (IMG)
      usb = nixos-generators.nixosGenerate {
        inherit system;
        modules = [ payload ];
        format = "raw-efi";
      };

      # 4. VM Image (QCOW2)
      vm = nixos-generators.nixosGenerate {
        inherit system;
        modules = [ payload ];
        format = "qcow";
      };

      # Meta-package for CI to build everything
      images = pkgs.linkFarm "snosu-images" [
        { name = "iso"; path = self.packages.${system}.iso; }
        { name = "iso-debug"; path = self.packages.${system}.iso-debug; }
        { name = "usb"; path = self.packages.${system}.usb; }
        { name = "vm"; path = self.packages.${system}.vm; }
      ];

      # 5. Compressed artifacts (7z LZMA2)
      images-7z = pkgs.runCommand "snosu-hyper-recovery-images-7z" {
        nativeBuildInputs = [ pkgs.p7zip pkgs.findutils pkgs.coreutils ];
      } ''
        set -euo pipefail
        mkdir -p $out

        images_root="${self.packages.${system}.images}"
        files=$(find -L "$images_root" -type f \( \
          -name "*.iso" -o -name "*.img" -o -name "*.qcow2" -o -name "*.qcow" \
          -o -name "*.raw" -o -name "*.vmdk" -o -name "*.vhd" -o -name "*.vhdx" \
        \))

        if [ -z "$files" ]; then
          echo "No image artifacts found under $images_root" >&2
          find -L "$images_root" -maxdepth 4 -type f | head -n 50 >&2
          exit 1
        fi

        while IFS= read -r file; do
          rel=$(realpath --relative-to="$images_root" "$file")
          safe_name=$(echo "$rel" | sed 's|/|__|g')
          7z a -t7z -mx=9 "$out/''${safe_name}.7z" "$file"
        done <<< "$files"
      '';
    };
  };
}
