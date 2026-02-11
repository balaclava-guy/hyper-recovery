{ config, pkgs, lib, ... }:

# CENTRALIZED DEBUG CONFIGURATION
# 
# This module contains ALL debug-related functionality:
# - Verbose kernel parameters
# - Plymouth debug logging
# - Debug scripts and services
# - Serial console output
# - Boot log capture
#
# Usage: Import this AFTER base, hardware, branding, and services
# to create a debug build variant.
#
# Philosophy: The base build is clean and production-ready.
#             This overlay adds verbose logging and automatic diagnostics.

let
  scripts = pkgs.callPackage ../../packages/scripts {};
in
{
  #############################################################################
  # KERNEL DEBUG PARAMETERS
  #############################################################################
  
  boot.kernelParams = lib.mkForce [
    "loglevel=7"                      # Verbose kernel logging
    "systemd.log_level=debug"         # Systemd debug output
    "systemd.log_target=console"      # Log to console
    "rd.debug"                        # Initrd debug mode
    "plymouth.debug"                  # Plymouth debug output
    "splash"                          # Keep splash (to debug it)
    "console=ttyS0,115200"            # Serial console
  ];

  #############################################################################
  # CONSOLE DEBUG SETTINGS
  #############################################################################

  services.openssh.settings.PermitRootLogin = "yes";
  
  boot.consoleLogLevel = lib.mkForce 7;
  boot.initrd.verbose = lib.mkForce true;

  #############################################################################
  # PLYMOUTH DEBUG LOGGING
  #############################################################################
  
  boot.plymouth.extraConfig = lib.mkForce ''
    DebugFile=/dev/ttyS0
    DebugLevel=info
  '';

  #############################################################################
  # DEBUG SCRIPTS
  #############################################################################
  
  environment.systemPackages = [
    scripts.hyper-debug-serial
    scripts.save-boot-logs
    scripts.hyper-ci-debug
    # Note: hyper-debug and hyper-hw are already in base
  ];

  #############################################################################
  # AUTOMATIC DEBUG SERVICES
  #############################################################################
  
  # Save boot logs to Ventoy USB
  systemd.services.save-boot-logs = {
    description = "Save boot logs to Ventoy USB";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "local-fs.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${scripts.save-boot-logs}/bin/save-boot-logs";
    };
  };

  # Dump diagnostics to serial console
  systemd.services.hyper-debug-serial = {
    description = "Dump hyper debug info to serial console";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    
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

  # Collect CI debug info to well-known location
  systemd.services.hyper-ci-debug = {
    description = "Collect debug info for CI/automated testing";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-journald.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${scripts.hyper-ci-debug}/bin/hyper-ci-debug";
      # Safeguard timeout (workflow poll will wait up to 5min for marker)
      TimeoutStartSec = "300s";
    };
  };
}
