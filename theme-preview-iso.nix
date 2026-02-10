{ config, pkgs, lib, ... }:

let
  # Plymouth theme package (copied from payload.nix, but without pulling in the full payload).
  snosuPlymouthTheme = pkgs.stdenv.mkDerivation {
    pname = "snosu-hyper-recovery-plymouth";
    version = "1.0";
    src = ./themes/plymouth/hyper-recovery;
    fontSrc = ./assets/fonts/undefined-medium/undefined-medium.ttf;

    nativeBuildInputs = [ pkgs.plymouth ];

    installPhase = ''
      mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery

      cp snosu-hyper-recovery.plymouth $out/share/plymouth/themes/snosu-hyper-recovery/
      cp snosu-hyper-recovery.script $out/share/plymouth/themes/snosu-hyper-recovery/
      cp *.png $out/share/plymouth/themes/snosu-hyper-recovery/
      cp -r animation $out/share/plymouth/themes/snosu-hyper-recovery/

      mkdir -p $out/share/fonts/truetype
      cp $fontSrc $out/share/fonts/truetype/undefined-medium.ttf
      cp $fontSrc $out/share/plymouth/themes/snosu-hyper-recovery/undefined-medium.ttf

      chmod -R +r $out/share/plymouth/themes/snosu-hyper-recovery
      chmod -R +r $out/share/fonts
    '';
  };

  # GRUB theme package (copied from payload.nix).
  snosuGrubTheme = pkgs.stdenv.mkDerivation {
    pname = "snosu-hyper-recovery-grub";
    version = "1.0";
    src = ./themes/grub/hyper-recovery;
    fontSrc = ./assets/fonts/undefined-medium/undefined-medium.ttf;

    nativeBuildInputs = [ pkgs.grub2 ];

    installPhase = ''
      mkdir -p $out
      cp * $out/

      grub-mkfont -s 12 -o $out/undefined_medium_12.pf2 $fontSrc
      grub-mkfont -s 14 -o $out/undefined_medium_14.pf2 $fontSrc
      grub-mkfont -s 16 -o $out/undefined_medium_16.pf2 $fontSrc
      grub-mkfont -s 24 -o $out/undefined_medium_24.pf2 $fontSrc
      grub-mkfont -s 28 -o $out/undefined_medium_28.pf2 $fontSrc

      sed -i 's/Hyper Street Fighter 2 Regular/Undefined Medium/g' $out/theme.txt
      sed -i 's/Hyper Fighting Regular/Undefined Medium/g' $out/theme.txt
    '';
  };
in
{
  system.stateVersion = "25.05";

  documentation.enable = false;
  programs.command-not-found.enable = false;

  networking.hostName = "hyper-theme-preview";

  # Keep the GRUB menu visible so you can inspect the theme, then select the entry
  # to see Plymouth during boot.
  boot.loader.timeout = lib.mkForce null;

  # Clean menu label for theme iteration.
  system.nixos.distroName = "";
  system.nixos.label = "";
  isoImage.prependToMenuLabel = "THEME PREVIEW";
  isoImage.appendToMenuLabel = "";

  isoImage.volumeID = "HYPER_THEME";
  image.fileName = "hyper-theme-preview-x86_64-linux.iso";

  isoImage.useUnifiedGrub = true;
  isoImage.makeEfiBootable = true;
  isoImage.makeBiosBootable = true;
  isoImage.makeUsbBootable = true;
  isoImage.grubTheme = snosuGrubTheme;
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  boot.supportedFilesystems = [ "vfat" "iso9660" "squashfs" "overlay" ];

  # Plymouth needs early KMS in QEMU to actually show.
  boot.kernelParams = [
    "quiet"
    "splash"
    "loglevel=0"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "udev.log_priority=3"
    "vt.global_cursor_default=0"
    "fbcon=nodefer"
    "plymouth.ignore-serial-consoles"
  ];
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.initrd.systemd.enable = true;
  boot.initrd.kernelModules = [
    "virtio_gpu"
    "virtio_pci"
    "virtio_blk"
    "sr_mod"
    "isofs"
    "squashfs"
    "overlay"
    "loop"
  ];

  boot.plymouth = {
    enable = lib.mkForce true;
    theme = "snosu-hyper-recovery";
    themePackages = [ snosuPlymouthTheme ];
    font = "${snosuPlymouthTheme}/share/fonts/truetype/undefined-medium.ttf";
  };

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub = {
    enable = true;
    theme = snosuGrubTheme;
    splashImage = "${snosuGrubTheme}/background.png";
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # Make the ISO boot to a console and stay there (no network/services needed).
  services.getty.autologinUser = "root";
  users.mutableUsers = false;
  users.allowNoPasswordLogin = true;
  users.users.root = {
    initialPassword = lib.mkForce null;
    hashedPassword = lib.mkForce null;
    hashedPasswordFile = lib.mkForce null;
    initialHashedPassword = lib.mkForce null;
  };

  environment.systemPackages = [ pkgs.plymouth ];
}
