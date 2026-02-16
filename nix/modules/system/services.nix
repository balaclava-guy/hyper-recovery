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
      # Enable HTTPS API for remote management
      config = {
        "core.https_address" = "[::]:8443";
      };

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

    # Set up symlinks to static assets in writable directory
    preStart = ''
      cd /var/lib/lxconsole
      ln -sf ${lxconsole}/share/lxconsole/static static
      ln -sf ${lxconsole}/share/lxconsole/templates templates
      ln -sf ${lxconsole}/share/lxconsole/lxconsole lxconsole
      ln -sf ${lxconsole}/share/lxconsole/run.py run.py
    '';

    serviceConfig = {
      Type = "simple";
      User = "lxconsole";
      Group = "lxconsole";
      WorkingDirectory = "/var/lib/lxconsole";
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

  # Auto-configure lxconsole with Incus connection
  systemd.services.lxconsole-auto-configure = {
    description = "Auto-configure LXConsole with local Incus server";
    after = [ "incus.service" "lxconsole.service" ];
    wants = [ "incus.service" "lxconsole.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "lxconsole";
      Group = "lxconsole";
    };

    script = ''
      # Wait for lxconsole to generate certificates and database
      for i in {1..30}; do
        if [ -f /var/lib/lxconsole/certs/client.crt ] && [ -f /var/lib/lxconsole/lxconsole.db ]; then
          break
        fi
        sleep 1
      done

      # Trust the certificate in Incus (run as incus-admin group member)
      if [ -f /var/lib/lxconsole/certs/client.crt ]; then
        if ! ${pkgs.incus-lts}/bin/incus config trust list --format=csv 2>/dev/null | grep -q lxconsole; then
          ${pkgs.incus-lts}/bin/incus config trust add-certificate /var/lib/lxconsole/certs/client.crt --name=lxconsole 2>/dev/null || true
        fi
      fi

      # Pre-configure server in lxconsole database if not already configured
      if [ -f /var/lib/lxconsole/lxconsole.db ]; then
        # Check if server already exists
        SERVER_EXISTS=$(${pkgs.sqlite}/bin/sqlite3 /var/lib/lxconsole/lxconsole.db \
          "SELECT COUNT(*) FROM servers WHERE name='local';" 2>/dev/null || echo "0")

        if [ "$SERVER_EXISTS" = "0" ]; then
          # Add local Incus server (using https://127.0.0.1:8443)
          ${pkgs.sqlite}/bin/sqlite3 /var/lib/lxconsole/lxconsole.db <<SQL
            INSERT OR IGNORE INTO servers (name, addr, protocol, auth_type, description)
            VALUES ('local', 'https://127.0.0.1:8443', 'incus', 'tls', 'Local Incus server (auto-configured)');
SQL
        fi
      fi
    '';
  };

  # Add LXConsole info to MOTD
  environment.etc."profile.d/lxconsole-motd.sh".text = ''
    echo ""
    echo "  🌐 LXConsole Web UI: http://$(hostname -I | awk '{print $1}'):5000"
    echo ""
  '';

  # Open firewall for lxconsole and Incus API
  networking.firewall.allowedTCPPorts = [ 5000 8443 ];
}
