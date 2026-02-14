{ config, lib, pkgs, ... }:

# Immutable VM Management Module
# Automates setup of VMs that boot existing OS installations without modifying them

with lib;

let
  cfg = config.services.immutable-vms;
in
{
  options.services.immutable-vms = {
    enable = mkEnableOption "Immutable VM management";

    autoStartNetwork = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically start the default libvirt network at boot";
    };
  };

  config = mkIf cfg.enable {
    # Ensure libvirt default network is active
    systemd.services.libvirt-default-network = mkIf cfg.autoStartNetwork {
      description = "Start libvirt default network";
      after = [ "libvirtd.service" ];
      wants = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        # Wait for libvirtd to be ready
        for i in {1..30}; do
          if ${pkgs.libvirt}/bin/virsh -c qemu:///system list > /dev/null 2>&1; then
            break
          fi
          sleep 1
        done

        # Start default network if not already active
        if ! ${pkgs.libvirt}/bin/virsh -c qemu:///system net-info default 2>/dev/null | grep -q "Active.*yes"; then
          ${pkgs.libvirt}/bin/virsh -c qemu:///system net-start default || true
        fi

        # Set network to autostart
        ${pkgs.libvirt}/bin/virsh -c qemu:///system net-autostart default || true
      '';
    };

    # TODO: Future enhancements
    # - Auto-discovery of bootable OS installations on attached disks
    # - Automatic QCOW2 overlay creation
    # - Dynamic VM definition generation
    # - Cockpit integration for one-click VM import
  };
}
