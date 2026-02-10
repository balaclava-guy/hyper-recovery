{ config, pkgs, lib, ... }:

# Services configuration for Hyper Recovery environment
# Cockpit, virtualization, and core services
# WITHOUT any automatic debug services

{
  # Virtualization Stack
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Management Interface (Cockpit)
  services.cockpit = {
    enable = true;
    openFirewall = true;
    # Allow access from dynamic LAN IP/hostnames used by recovery images.
    allowed-origins = [ "*" ];
    plugins = with pkgs; [
      cockpit-machines
      cockpit-zfs
      cockpit-files
    ];
    settings = {
      WebService = {
        AllowUnencrypted = true;
        AllowRoot = true;
      };
    };
  };
}
