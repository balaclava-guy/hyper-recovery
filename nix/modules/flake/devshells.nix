{ self, inputs, ... }:

# Flake-parts module for developer environment

{
  imports = [ inputs.devshell.flakeModule ];
  
  perSystem = { config, pkgs, system, lib, ... }: {
    devshells.default = {
      name = "hyper-recovery-dev";
      
      packages = with pkgs; [
        p7zip
        nixpkgs-fmt
        statix
      ] ++ lib.optionals (system == "aarch64-darwin") [
        python3
        qemu
        mtools
        xorriso
      ];
      
      commands = [
        {
          name = "build-usb";
          command = "nix build .#usb";
          help = "Build regular USB image";
          category = "build";
        }
        {
          name = "build-usb-debug";
          command = "nix build .#usb-debug";
          help = "Build debug USB image";
          category = "build";
        }
        {
          name = "build-all";
          command = "nix build .#images";
          help = "Build all images";
          category = "build";
        }
        {
          name = "compress-images";
          command = "nix build .#images-7z";
          help = "Build compressed 7z archives";
          category = "build";
        }
        {
          name = "check";
          command = "nix flake check";
          help = "Check flake validity";
          category = "validation";
        }
        {
          name = "run-theme-vm";
          command = "nix run .#theme-vm";
          help = "Run theme preview VM";
          category = "dev";
        }
        {
          name = "show-packages";
          command = "nix flake show";
          help = "Show all flake outputs";
          category = "info";
        }
      ];
      
      env = [
        {
          name = "HYPER_RECOVERY_ROOT";
          eval = "$PRJ_ROOT";
        }
      ];
      
      motd = ''
        {202}Snosu Hyper Recovery Development Environment{reset}
        
        $(type -p menu &>/dev/null && menu)
        
        {bold}Quick Start:{reset}
          build-usb          - Build regular recovery image
          build-usb-debug    - Build debug recovery image  
          check              - Validate flake
          run-theme-vm       - Preview boot themes
      '';
    };
  };
}
