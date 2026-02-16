{ config, lib, pkgs, ... }:

# Container and VM Management Module
# Configuration for incus-based container and VM management

with lib;

let
  cfg = config.services.immutable-vms;
in
{
  options.services.immutable-vms = {
    enable = mkEnableOption "Incus container and VM management";

    autoInit = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically initialize incus on first boot";
    };
  };

  config = mkIf cfg.enable {
    # Placeholder for future incus automation
    # Will be populated with incus-specific logic

    # TODO: Future enhancements
    # - Auto-discovery of bootable OS installations on attached disks
    # - Automatic container/VM provisioning
    # - LXConsole integration for one-click import
  };
}
