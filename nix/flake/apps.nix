{ self, inputs, ... }:

# Flake-parts module for flake apps

{
  perSystem = { config, system, lib, ... }: {
    apps = {
      theme-vm = {
        type = "app";
        program = "${config.packages.theme-vm}/bin/theme-vm.py";
        meta.description = "Run a stripped dowm VM for previewing grub and plymouth themes";
      };

      deploy-to-proxmox = {
        type = "app";
        program = "${config.packages.deploy-to-proxmox}/bin/deploy-to-proxmox";
        meta.description = "Build and deploy Hyper Recovery to Proxmox test VMs";
      };
    };
  };
}
