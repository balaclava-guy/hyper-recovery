{ self, inputs, ... }:

# Flake-parts module for flake apps

{
  perSystem = { config, system, ... }: {
    apps = {
      theme-vm = {
        type = "app";
        program = "${config.packages.theme-vm}/bin/theme-vm.py";
        meta.description = "Run a stripped dowm VM for previewing grub and plymouth themes";
      };
    };
  };
}
