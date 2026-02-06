{
  description = "Minimalist Hypervisor OS Boot CD";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }: {
    # Note: This defines an x86_64-linux ISO.
    # If building on macOS (aarch64-darwin), you need a remote builder or linux-builder.
    packages.x86_64-linux = {
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./iso.nix
        ];
        format = "install-iso";
      };
    };
  };
}
