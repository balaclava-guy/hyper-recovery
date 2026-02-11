{
  description = "Super Nixos Utilities: Hyper Recovery";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ { self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      
      imports = [
        ./nix/flake/packages.nix
        ./nix/flake/images.nix
        ./nix/flake/apps.nix
        ./nix/flake/devshells.nix
      ];
    };
}
