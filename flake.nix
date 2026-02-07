{
  description = "Minimalist Hypervisor OS Boot CD";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
  in
  {
    # Note: This defines an x86_64-linux ISO.
    # If building on macOS (aarch64-darwin), you need a remote builder or linux-builder.
    packages.x86_64-linux = let
      usbImage = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./iso.nix
        ];
        format = "raw-efi";
      };
    in {
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./iso.nix
        ];
        format = "install-iso";
      };
      usb = pkgs.runCommand "snosu-hyper-recovery-raw-efi" {} ''
        mkdir -p $out/usb
        ln -s ${usbImage} $out/usb/snosu-hyper-recovery-x86_64-linux.img
      '';
    };
  };
}
