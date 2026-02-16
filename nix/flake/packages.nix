{ self, inputs, ... }:

# Flake-parts module for package definitions
# Exports theme packages, scripts, and utilities

let
  version = import ../version.nix;
in
{
  perSystem = { pkgs, system, lib, ... }:
    let
      scripts = pkgs.callPackage ../packages/scripts {};
    in
    {
    packages = lib.optionalAttrs pkgs.stdenv.isLinux {
      # Theme packages
      snosu-plymouth-theme = pkgs.callPackage ../packages/themes/plymouth.nix {};
      snosu-grub-theme = pkgs.callPackage ../packages/themes/grub.nix {};

       # Script packages (Linux only)
       hyper-debug = scripts.hyper-debug;
       hyper-hw = scripts.hyper-hw;
       hyper-debug-serial = scripts.hyper-debug-serial;
       save-boot-logs = scripts.save-boot-logs;
       hyper-ci-debug = scripts.hyper-ci-debug;
      
       # Firmware package
       hyper-firmware-core = (pkgs.callPackage ../packages/firmware.nix {}).hyper-firmware-core;
      
      # WiFi setup daemon
      hyper-connect = pkgs.callPackage ../packages/hyper-connect.nix {};

      # LXConsole web UI for incus
      lxconsole = pkgs.callPackage ../packages/lxconsole.nix {};
    } // {
      # Cross-platform packages
      # These work on both Linux and macOS

      # Development/deployment scripts
      hyper-fetch-iso = scripts.hyper-fetch-iso;
      deploy-to-proxmox = scripts.deploy-to-proxmox;

      # Theme VM (cross-platform)
      theme-vm = pkgs.stdenvNoCC.mkDerivation {
        pname = "theme-vm";
        version = version.version;
        dontUnpack = true;

        installPhase = ''
          mkdir -p $out/bin
          cp ${../../scripts/theme-vm.py} $out/bin/theme-vm.py
          chmod +x $out/bin/theme-vm.py

          substituteInPlace $out/bin/theme-vm.py \
            --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'

          substituteInPlace $out/bin/theme-vm.py \
            --replace-fail "@qemu_system_aarch64@" "${pkgs.qemu}/bin/qemu-system-aarch64" \
            --replace-fail "@qemu_img@" "${pkgs.qemu}/bin/qemu-img" \
            --replace-fail "@mformat@" "${pkgs.mtools}/bin/mformat" \
            --replace-fail "@mcopy@" "${pkgs.mtools}/bin/mcopy" \
            --replace-fail "@xorriso@" "${pkgs.xorriso}/bin/xorriso" \
            --replace-fail "@firmware_search_dirs@" ""

          patchShebangs $out/bin/theme-vm.py
        '';
      };
    };
  };
}
