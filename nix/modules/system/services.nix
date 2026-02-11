{ pkgs, ... }:

# Services configuration for Hyper Recovery environment
# Cockpit, virtualization, and core services

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
    # TODO(2026-02-10): Temporary workaround.
    # Cockpit Python version mismatch causing buildEnv path collision.
    package = pkgs.cockpit.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        cockpitPath =
          pkgs.lib.filter
            (p: !(pkgs.lib.hasInfix "python3" (builtins.toString p)))
            (old.passthru.cockpitPath or [ ]);
      };
    });
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
