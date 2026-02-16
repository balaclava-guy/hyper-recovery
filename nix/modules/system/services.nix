{ pkgs, ... }:

# Services configuration for Hyper Recovery environment
# Incus virtualization and core services

let
  lxconsole = pkgs.callPackage ../../packages/lxconsole.nix {};
in
{
  # Enable nftables (required for incus networking)
  networking.nftables.enable = true;

  # Incus Virtualization Stack
  virtualisation.incus = {
    enable = true;

    # Preseed configuration for declarative initialization
    preseed = {
      networks = [
        {
          name = "incusbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.0.100.1/24";
            "ipv4.nat" = "true";
            "ipv6.address" = "none";
          };
        }
      ];

      storage_pools = [
        {
          name = "default";
          driver = "dir";
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
        }
      ];

      profiles = [
        {
          name = "default";
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              type = "disk";
              size = "50GiB";
            };
          };
        }
      ];
    };
  };

  # LXConsole Web UI
  systemd.services.lxconsole = {
    description = "LXConsole Web UI for Incus";
    after = [ "network.target" "incus.service" ];
    wants = [ "incus.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "lxconsole";
      Group = "lxconsole";
      WorkingDirectory = "${lxconsole}/share/lxconsole";
      ExecStart = "${lxconsole}/bin/lxconsole";
      Restart = "on-failure";
      RestartSec = "10s";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/lxconsole" ];
    };

    environment = {
      FLASK_SECRET_KEY = "CHANGE_ME_IN_PRODUCTION";  # TODO: Generate random key
      LXCONSOLE_DB_PATH = "/var/lib/lxconsole/lxconsole.db";
    };
  };

  # Create lxconsole user
  users.users.lxconsole = {
    isSystemUser = true;
    group = "lxconsole";
    extraGroups = [ "incus-admin" ];  # Allow incus access
  };

  users.groups.lxconsole = {};

  # Create state directory
  systemd.tmpfiles.rules = [
    "d /var/lib/lxconsole 0750 lxconsole lxconsole -"
  ];

  # Add LXConsole info to MOTD
  environment.etc."profile.d/lxconsole-motd.sh".text = ''
    echo ""
    echo "  🌐 LXConsole Web UI: http://$(hostname -I | awk '{print $1}'):5000"
    echo ""
  '';

  # Open firewall for lxconsole
  networking.firewall.allowedTCPPorts = [ 5000 ];
}
