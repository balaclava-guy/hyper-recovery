{ inputs, ... }:

{
  # ISO Format Configuration
  iso = { lib, ... }: {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix"
      ./payload.nix
    ];

    # ISO Specific Overrides
    isoImage.isoName = "snosu-hyper-recovery-x86_64-linux.iso";
    isoImage.volumeID = "SNOSU_RECOVERY";
    isoImage.makeEfiBootable = true;
    isoImage.makeBiosBootable = true; # We'll theme this via syslinux for now until we move to full hybrid

    # Squashfs settings for speed/size
    isoImage.squashfsCompression = "zstd -Xcompression-level 19";

    # Force the boot menu label to be clean
    system.nixos.distroName = "";
    system.nixos.label = "";
    isoImage.prependToMenuLabel = "START HYPER RECOVERY";
    isoImage.appendToMenuLabel = "";

    # Ensure initrd has loop/isofs for Ventoy
    boot.initrd.kernelModules = [ "loop" "isofs" ];
  };

  # USB/Raw Image Configuration
  usb = {
    imports = [
      ./payload.nix
    ];
    # We'll use this with nixos-generators or raw disk image module
    # Logic is handled in flake.nix using the 'raw-efi' format
  };
}
