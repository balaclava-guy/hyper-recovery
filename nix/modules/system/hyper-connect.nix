# NixOS module for hyper-connect
# Provides automatic WiFi configuration via captive portal and TUI

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.hyper-connect;
  hyperConnect = pkgs.callPackage ../../packages/hyper-connect.nix {};
in
{
  options.services.hyper-connect = {
    enable = mkEnableOption "Hyper Connect service";

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
      hyperConnect
      pkgs.hostapd
      pkgs.dnsmasq
      pkgs.iw
      pkgs.wirelesstools
    ];

    # Main daemon service
    systemd.services.hyper-connect = {
      description = "Hyper Connect Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" "systemd-resolved.service" ];
      wants = [ "NetworkManager.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${hyperConnect}/bin/hyper-connect daemon --interface ${cfg.interface} --ssid ${cfg.ssid} --ap-ip ${cfg.apIp} --port ${toString cfg.port} --grace-period ${toString cfg.gracePeriod}";
        Restart = "on-failure";
        RestartSec = "5s";
        RuntimeDirectory = "hyper-connect";
        RuntimeDirectoryMode = "0755";

        # Security hardening (limited due to network requirements)
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ "/run" "/tmp" "/sys/class/net" "/var/lib/hyper-connect" ];
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
    systemd.services.hyper-connect-tui = mkIf cfg.autoStartTui {
      description = "Hyper Connect TUI";
      wantedBy = [ "multi-user.target" ];
      after = [ "hyper-connect.service" "plymouth-quit.service" "plymouth-quit-wait.service" ];
      wants = [ "hyper-connect.service" ];
      before = [ "getty@tty1.service" ];
      conflicts = [ "getty@tty1.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${pkgs.kbd}/bin/chvt 1";
        ExecStart = "${hyperConnect}/bin/hyper-connect tui";
        Restart = "no";

        StandardInput = "tty-force";
        StandardOutput = "tty";
        StandardError = "journal";
        TTYPath = "/dev/tty1";
        TTYReset = true;
        TTYVHangup = true;
        TTYVTDisallocate = true;
      };

      # Use --no-block to avoid blocking on getty startup (which can hang
      # waiting for the TTY to be released by the exiting TUI).
      postStop = ''
        ${pkgs.systemd}/bin/systemctl --no-block start getty@tty1.service || true
      '';
    };

    # Create credentials directory
    systemd.tmpfiles.rules = [
      "d /var/lib/hyper-connect 0700 root root -"
    ];

    # Firewall rules for captive portal
    networking.firewall = {
      allowedTCPPorts = [ cfg.port 53 ];
      allowedUDPPorts = [ 53 67 68 ];
    };
  };
}
