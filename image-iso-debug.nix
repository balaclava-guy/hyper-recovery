{ lib, ... }:

{
  isoImage.isoName = lib.mkForce "snosu-hyper-recovery-debug-x86_64-linux.iso";
  isoImage.volumeID = lib.mkForce "SNOSU_RECOVERY_DBG";
  isoImage.prependToMenuLabel = lib.mkForce "START HYPER RECOVERY (DEBUG)";

  boot.kernelParams = [
    "loglevel=7"
    "systemd.log_level=debug"
    "systemd.log_target=console"
    "systemd.journald.forward_to_console=yes"
    "rd.systemd.show_status=1"
    "rd.udev.log_level=debug"
    "udev.log_priority=debug"
    "rd.debug"
    "plymouth.debug"
  ];
}
