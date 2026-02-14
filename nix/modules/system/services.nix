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

  # Install libvirt-dbus D-Bus policy so cockpit-machines can communicate with libvirt.
  # The NixOS libvirtd module enables libvirt-dbus but doesn't add its D-Bus policy.
  services.dbus.packages = [ pkgs.libvirt-dbus ];

  # Ensure virtlogd (VM logging daemon) is started with libvirtd.
  # Required for QEMU VMs to capture console output and logs.
  systemd.services.virtlogd = {
    wantedBy = [ "multi-user.target" ];
    before = [ "libvirtd.service" ];
  };

  # Allow libvirt-dbus to access libvirtd without polkit authentication prompts.
  # libvirt-dbus runs as a system service with no interactive polkit agent, so we
  # grant it direct access to libvirt actions.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (action.id.indexOf("org.libvirt.") == 0 &&
            subject.user == "libvirtdbus") {
            return polkit.Result.YES;
        }
    });
  '';

  # Management Interface (Cockpit)
  services.cockpit = {
    enable = true;
    openFirewall = true;
    # Allow access from dynamic LAN IP/hostnames used by recovery images.
    allowed-origins = [ "*" ];
    plugins = with pkgs; [
      cockpit-machines
      cockpit-files
      cockpit-zfs
    ];
    settings = {
      WebService = {
        AllowUnencrypted = true;
        AllowRoot = true;
      };
    };
  };
}
