{ self, inputs, ... }:

{
  perSystem = { pkgs, system, lib, ... }: {
    packages = lib.optionalAttrs pkgs.stdenv.isLinux {
      # Theme packages (Linux-only: Plymouth and GRUB are Linux-specific)
      snosu-plymouth-theme = pkgs.callPackage ../packages/themes/plymouth.nix {};
      snosu-grub-theme = pkgs.callPackage ../packages/themes/grub.nix {};
      
      # Script packages (Linux-only: depend on systemd, plymouth, util-linux)
      hyper-debug = (pkgs.callPackage ../packages/scripts {}).hyper-debug;
      hyper-hw = (pkgs.callPackage ../packages/scripts {}).hyper-hw;
      hyper-debug-serial = (pkgs.callPackage ../packages/scripts {}).hyper-debug-serial;
      save-boot-logs = (pkgs.callPackage ../packages/scripts {}).save-boot-logs;
      
      # Firmware package (Linux-only)
      hyper-firmware-core = (pkgs.callPackage ../packages/firmware.nix {}).hyperFirmwareCore;
    } // {
      # Theme VM (cross-platform: works on any system with QEMU)
      theme-vm = pkgs.stdenvNoCC.mkDerivation {
        pname = "theme-vm";
        version = "0.1.0";

        dontUnpack = true;
        dontBuild = true;

        installPhase = ''
          set -euo pipefail
          mkdir -p $out/bin
          cp ${../../scripts/theme-vm} $out/bin/theme-vm
          chmod +x $out/bin/theme-vm

          # Ensure the packaged app does not rely on a host Python.
          substituteInPlace $out/bin/theme-vm \
            --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'

          substituteInPlace $out/bin/theme-vm \
            --replace-fail "@qemu_system_aarch64@" "${pkgs.qemu}/bin/qemu-system-aarch64" \
            --replace-fail "@qemu_img@" "${pkgs.qemu}/bin/qemu-img" \
            --replace-fail "@mformat@" "${pkgs.mtools}/bin/mformat" \
            --replace-fail "@mcopy@" "${pkgs.mtools}/bin/mcopy" \
            --replace-fail "@xorriso@" "${pkgs.xorriso}/bin/xorriso" \
            --replace-fail "@firmware_search_dirs@" ""

          patchShebangs $out/bin/theme-vm
        '';
      };
    };
  };
}
