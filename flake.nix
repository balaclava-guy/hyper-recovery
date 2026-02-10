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
        ./nix/flake-modules/packages.nix
        ./nix/flake-modules/nixos-images.nix
        ./nix/flake-modules/apps.nix
        ./nix/flake-modules/devshells.nix
      ];

      flake = {
        # TODO(2026-02-10): Temporary workaround.
        #
        # NixOS Cockpit's module builds a `cockpit-plugins-env` buildEnv that links `/bin`
        # from all plugin `passthru.cockpitPath` entries. On our pinned nixpkgs, Cockpit
        # itself pulls Python 3.13 while `cockpit-zfs` pulls a Python 3.12 env, and both
        # provide `bin/idle3`, causing a buildEnv path collision in CI.
        #
        # Remove once nixpkgs resolves the Python version mismatch, or the Cockpit module
        # stops linking `/bin` from plugin dependency envs.
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

      # Per-system configuration handled by imported modules
    };
}
