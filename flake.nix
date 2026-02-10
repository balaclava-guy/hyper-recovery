{
  description = "Snosu Hyper Recovery Environment";

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
        ./nix/modules/flake/packages.nix
        ./nix/modules/flake/images.nix
        ./nix/modules/flake/apps.nix
        ./nix/modules/flake/devshells.nix
      ];

      flake = {
        # TODO(2026-02-10): Temporary workaround.
        # Cockpit Python version mismatch causing buildEnv path collision.
        overlays.cockpitZfs = final: prev: {
          cockpit = prev.cockpit.overrideAttrs (old: {
            passthru = (old.passthru or { }) // {
              cockpitPath =
                prev.lib.filter
                  (p: !(prev.lib.hasInfix "python3" (builtins.toString p)))
                  (old.passthru.cockpitPath or [ ]);
            };
          });
        };
      };
    };
}
