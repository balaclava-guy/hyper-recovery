# NixOS module for hyper-wifi-setup
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.hyper-wifi-setup;
  
  hyper-wifi-setup = pkgs.callPackage ./default.nix {};
in
{
  options.services.hyper-wifi-setup = {
    enable = mkEnableOption "Hyper WiFi Setup service";

    interface = mkOption {
      type = types.str;
      default = "wlan0";
      description = "WiFi interface to use for AP mode";
    };

    ssid = mkOption {
      type = types.str;
      default = "HyperRecovery";
      description = "SSID for the setup access point";
    };

    apIp = mkOption {
      type = types.str;
      default = "192.168.42.1";
      description = "IP address for the AP interface";
    };

    port = mkOption {
      type = types.port;
      default = 80;
      description = "Port for the captive portal web server";
    };

    gracePeriod = mkOption {
      type = types.int;
      default = 10;
      description = "Seconds to wait for existing network before starting AP";
    };

    autoStartTui = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically start TUI on tty2";
    };
  };

  config = mkIf cfg.enable {
    # Ensure required packages are available
    environment.systemPackages = [
      hyper-wifi-setup
      pkgs.hostapd
      pkgs.dnsmasq
      pkgs.iw
      pkgs.wirelesstools
    ];

    # Main daemon service
    systemd.services.hyper-wifi-setup = {
      description = "Hyper WiFi Setup Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" "systemd-resolved.service" ];
      wants = [ "NetworkManager.service" ];

      # Only start if WiFi hardware is present
      unitConfig = {
        ConditionPathExists = "/sys/class/net/${cfg.interface}/wireless";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${hyper-wifi-setup}/bin/hyper-wifi-setup daemon --interface ${cfg.interface} --ssid ${cfg.ssid} --ap-ip ${cfg.apIp} --port ${toString cfg.port} --grace-period ${toString cfg.gracePeriod}";
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "hyper-wifi-setup";
        RuntimeDirectoryMode = "0755";

        # Security hardening (limited due to network requirements)
        NoNewPrivileges = false;  # Needs to spawn hostapd/dnsmasq
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ "/run" "/tmp" ];
        
        # Capabilities for network management
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_NET_BIND_SERVICE" "CAP_SETUID" "CAP_SETGID" ];
      };

      path = [
        pkgs.networkmanager
        pkgs.hostapd
        pkgs.dnsmasq
        pkgs.iproute2
        pkgs.iw
        pkgs.coreutils
        pkgs.procps
      ];
    };

    # TUI on tty2 (optional)
    systemd.services.hyper-wifi-setup-tui = mkIf cfg.autoStartTui {
      description = "Hyper WiFi Setup TUI";
      after = [ "hyper-wifi-setup.service" "getty@tty2.service" ];
      wants = [ "hyper-wifi-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${pkgs.bash}/bin/bash -lc 'for i in {1..60}; do [ -S /run/hyper-wifi-setup.sock ] && exit 0; sleep 1; done; echo IPC socket not ready >&2; exit 1'";
        ExecStart = "${hyper-wifi-setup}/bin/hyper-wifi-setup tui";
        Restart = "on-failure";
        RestartSec = "2s";
        
        StandardInput = "tty";
        StandardOutput = "tty";
        TTYPath = "/dev/tty2";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
      };
    };

    # Firewall rules for captive portal
    networking.firewall = {
      allowedTCPPorts = [ cfg.port 53 ];
      allowedUDPPorts = [ 53 67 68 ];
      
      # Allow traffic on AP interface
      extraCommands = ''
        iptables -A INPUT -i ${cfg.interface} -p tcp --dport ${toString cfg.port} -j ACCEPT
        iptables -A INPUT -i ${cfg.interface} -p udp --dport 53 -j ACCEPT
        iptables -A INPUT -i ${cfg.interface} -p udp --dport 67:68 -j ACCEPT
      '';
    };
  };
}
