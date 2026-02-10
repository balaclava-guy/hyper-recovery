{ config, pkgs, lib, ... }:

# Debug overlay module for Hyper Recovery environment
# This module EXTENDS the base system with debug features
# 
# Usage: Import this AFTER base-system, hardware, boot-branding, and services
# to create a debug build variant.
#
# Philosophy: The base build is clean and production-ready.
#             This overlay adds verbose logging and automatic diagnostics.

let
  # Import scripts (will be properly wired once we integrate with flake-parts)
  scripts = pkgs.callPackage ../packages/scripts {};
in
{
  # Override boot parameters for verbose logging
  boot.kernelParams = lib.mkForce [
    "loglevel=7"                      # Verbose kernel logging
    "systemd.log_level=debug"         # Systemd debug output
    "systemd.log_target=console"      # Log to console
    "rd.debug"                        # Initrd debug mode
    "plymouth.debug"                  # Plymouth debug output
    "splash"                          # Keep splash (to debug it)
    "console=ttyS0,115200"            # Serial console
    "hyper.debug=1"                   # Our custom debug flag
  ];

  # Enable Plymouth debug logging to serial console
  boot.plymouth.extraConfig = lib.mkForce ''
    DebugFile=/dev/ttyS0
    DebugLevel=info
  '';

  # Override console log levels for verbose output
  boot.consoleLogLevel = lib.mkForce 7;
  boot.initrd.verbose = lib.mkForce true;

  # Add debug-specific scripts to system packages
  environment.systemPackages = [
    scripts.hyper-debug-serial
    scripts.save-boot-logs
    # Note: hyper-debug and hyper-hw are already in base-system
  ];

  # Automatic debug service: Save boot logs to Ventoy USB
  systemd.services.save-boot-logs = {
    description = "Save boot logs to Ventoy USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "local-fs.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${scripts.save-boot-logs}/bin/save-boot-logs";
    };
  };

  # Automatic debug service: Dump diagnostics to serial console
  systemd.services.hyper-debug-serial = {
    description = "Dump hyper debug info to serial when hyper.debug=1";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    
    # Only run if hyper.debug=1 kernel parameter is present
    unitConfig.ConditionKernelCommandLine = "hyper.debug=1";
    
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyS0";
      TTYReset = "yes";
      TTYVHangup = "yes";
    };
    
    path = with pkgs; [
      coreutils
      util-linux
      systemd
      networkmanager
      plymouth
      scripts.hyper-debug
    ];
    
    script = ''
      set -euo pipefail
      echo "hyper-debug-serial: starting"
      ${scripts.hyper-debug-serial}/bin/hyper-debug-serial
      echo "hyper-debug-serial: done"
    '';
  };
}
