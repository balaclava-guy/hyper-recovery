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
          images = myOS.config.system.build.images;
          # Evaluate file paths at Nix evaluation time
          isoPath = "${images.iso}/${images.iso.passthru.filePath}";
          isoDebugPath = "${images.iso-debug}/${images.iso-debug.passthru.filePath}";
          rawPath = "${images.raw-efi}/${images.raw-efi.passthru.filePath}";
          qcow2Path = "${images.qemu-efi}/${images.qemu-efi.passthru.filePath}";
        in
        pkgs.runCommand "snosu-hyper-recovery-images-7z" {
          nativeBuildInputs = [ pkgs.p7zip pkgs.coreutils ];
        } ''
          set -euo pipefail
          mkdir -p $out

          # ISO
          7z a -t7z -mx=9 "$out/snosu-hyper-recovery-x86_64-linux.iso.7z" "${isoPath}"

          # Debug ISO
          7z a -t7z -mx=9 "$out/snosu-hyper-recovery-debug-x86_64-linux.iso.7z" "${isoDebugPath}"

          # Raw USB Image
          7z a -t7z -mx=9 "$out/snosu-hyper-recovery-x86_64-linux.img.7z" "${rawPath}"

          # QCOW2 VM Image
          7z a -t7z -mx=9 "$out/snosu-hyper-recovery-x86_64-linux.qcow2.7z" "${qcow2Path}"
        '';
    };
  };
}
