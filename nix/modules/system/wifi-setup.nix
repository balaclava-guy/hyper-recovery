# NixOS module for hyper-wifi-setup
# Provides automatic WiFi configuration via captive portal and TUI

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.hyper-wifi-setup;
  hyper-wifi-setup = pkgs.callPackage ../../packages/hyper-wifi-setup.nix {};
in
{
  options.services.hyper-wifi-setup = {
    enable = mkEnableOption "Hyper WiFi Setup service";

    interface = mkOption {
      type = types.str;
      default = "auto";
      description = "WiFi interface to use for AP mode (or 'auto' to detect)";
    };

    ssid = mkOption {
      type = types.str;
      default = "HyperRecovery";
      description = "SSID for the setup access point";
    };

    apIp = mkOption {
      type = types.str;
      default = "auto";
      description = "AP gateway IP address (or 'auto' to pick a non-conflicting subnet)";
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
      default = false;
      description = "Automatically start TUI and focus tty1";
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

      serviceConfig = {
        Type = "simple";
        ExecStart = "${hyper-wifi-setup}/bin/hyper-wifi-setup daemon --interface ${cfg.interface} --ssid ${cfg.ssid} --ap-ip ${cfg.apIp} --port ${toString cfg.port} --grace-period ${toString cfg.gracePeriod}";
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "hyper-wifi-setup";
        RuntimeDirectoryMode = "0755";

        # Security hardening (limited due to network requirements)
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ "/run" "/tmp" "/sys/class/net" ];
      };

      path = [
        pkgs.networkmanager
        pkgs.hostapd
        pkgs.dnsmasq
        pkgs.iproute2
        pkgs.iw
        pkgs.coreutils
        pkgs.procps
        pkgs.util-linux
      ];
    };

    # TUI (optional)
    systemd.services.hyper-wifi-setup-tui = mkIf cfg.autoStartTui {
      description = "Hyper WiFi Setup TUI";
      wantedBy = [ "multi-user.target" ];
      after = [ "hyper-wifi-setup.service" "plymouth-quit.service" "plymouth-quit-wait.service" ];
      wants = [ "hyper-wifi-setup.service" ];
      before = [ "getty@tty1.service" ];
      conflicts = [ "getty@tty1.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${pkgs.kbd}/bin/chvt 1";
        ExecStart = "${hyper-wifi-setup}/bin/hyper-wifi-setup tui";
        Restart = "no";

        StandardInput = "tty-force";
        StandardOutput = "tty";
        StandardError = "journal";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
      };
    };

    # Create credentials directory
    systemd.tmpfiles.rules = [
      "d /var/lib/hyper-wifi-setup 0700 root root -"
    ];

    # Firewall rules for captive portal
    networking.firewall = {
      allowedTCPPorts = [ cfg.port 53 ];
      allowedUDPPorts = [ 53 67 68 ];
    };
  };
}
