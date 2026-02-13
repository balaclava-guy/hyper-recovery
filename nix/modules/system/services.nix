{ pkgs, ... }:

# Services configuration for Hyper Recovery environment
# Cockpit, virtualization, and core services

{
  # Virtualization Stack
  virtualisation.libvirtd = {
    enable = true;
    dbus.enable = true;
    # Cockpit expects a consistently available libvirt backend.
    # - Keep libvirtd running (avoid idle socket-activation timeout)
    # - Avoid polkit prompts for system services (libvirt-dbus) by relying on
    #   unix socket permissions instead.
    extraOptions = [ "--timeout" "0" ];
    extraConfig = ''
      auth_unix_ro = "none"
      auth_unix_rw = "none"
      unix_sock_group = "libvirtd"
      unix_sock_ro_perms = "0770"
      unix_sock_rw_perms = "0770"
    '';
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # When using socket activation, systemd creates the libvirt sockets.
  # Ensure they are restricted to the libvirtd group to match extraConfig.
  systemd.sockets.libvirtd.socketConfig = {
    SocketMode = "0660";
    SocketGroup = "libvirtd";
  };
  systemd.sockets."libvirtd-ro".socketConfig = {
    SocketMode = "0660";
    SocketGroup = "libvirtd";
  };
  systemd.sockets."libvirtd-admin".socketConfig = {
    SocketMode = "0660";
    SocketGroup = "libvirtd";
  };

  # libvirt-dbus is a system service (no interactive polkit agent). Give it
  # direct socket access for its backend connection.
  # cockpit-machines communicates with libvirt exclusively through libvirt-dbus.
  # The upstream unit is only D-Bus activated, but the D-Bus service file is not
  # installed into the system bus services directory on NixOS, so activation
  # never fires.  Start it explicitly instead.
  systemd.services.libvirt-dbus = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.SupplementaryGroups = [
      "qemu-libvirtd"
      "libvirtd"
    ];
  };

  # Management Interface (Cockpit)
  services.cockpit = {
    enable = true;
    # TODO(2026-02-10): Temporary workaround.
    # Cockpit Python version mismatch causing buildEnv path collision.
    package =
      let
        base = pkgs.cockpit.overrideAttrs (old: {
          passthru = (old.passthru or { }) // {
            cockpitPath =
              pkgs.lib.filter
                (p: !(pkgs.lib.hasInfix "python3" (builtins.toString p)))
                (old.passthru.cockpitPath or [ ]);
          };
        });
      in
      base;
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
