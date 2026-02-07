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
      packages = [ pkgs.peazip pkgs.p7zip ];
    };

    packages.${system} = {
      # 1. Standard ISO
      iso = myOS.config.system.build.images.iso;

      # 2. Debug ISO
      iso-debug = myOS.config.system.build.images.iso-debug;

      # 3. Raw USB Image (IMG)
      usb = myOS.config.system.build.images.raw-efi;

      # 4. VM Image (QCOW2)
      vm = myOS.config.system.build.images.qemu-efi;

      # Meta-package for CI to build everything
      images = pkgs.linkFarm "snosu-images" [
        { name = "iso"; path = self.packages.${system}.iso; }
        { name = "iso-debug"; path = self.packages.${system}.iso-debug; }
        { name = "usb"; path = self.packages.${system}.usb; }
        { name = "vm"; path = self.packages.${system}.vm; }
      ];

      # 5. Compressed artifacts (7z LZMA2)
      images-7z =
        let
          imageFiles =
            nixpkgs.lib.mapAttrsToList
              (_: image: "${image}/${image.passthru.filePath}")
              myOS.config.system.build.images;
          imageFilesArgs = nixpkgs.lib.escapeShellArgs imageFiles;
        in
        pkgs.runCommand "snosu-hyper-recovery-images-7z" {
          nativeBuildInputs = [ pkgs.p7zip pkgs.coreutils ];
        } ''
          set -euo pipefail
          mkdir -p $out

          workdir=$(mktemp -d)
          for file in ${imageFilesArgs}; do
            if [ ! -f "$file" ]; then
              echo "Missing image file: $file" >&2
              exit 1
            fi
            base_name=$(basename "$file")
            cp "$file" "$workdir/$base_name"
            7z a -t7z -mx=9 "$out/''${base_name}.7z" "$workdir/$base_name"
            rm -f "$workdir/$base_name"
          done
        '';
    };
  };
}
