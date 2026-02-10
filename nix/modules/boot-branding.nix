{ config, pkgs, lib, ... }:

# Boot branding configuration for Hyper Recovery
# Plymouth boot splash and GRUB theme
# WITHOUT any debug features (clean boot experience)

let
  # Import theme packages (will be properly wired once we integrate with flake-parts)
  snosuPlymouthTheme = pkgs.callPackage ../packages/themes/plymouth.nix {};
  snosuGrubTheme = pkgs.callPackage ../packages/themes/grub.nix {};
in
{
  # Plymouth Boot Splash (CLEAN - no debug logging)
  boot.initrd.systemd.enable = true;
  boot.plymouth = {
    enable = lib.mkForce true;
    theme = "snosu-hyper-recovery";
    themePackages = [ snosuPlymouthTheme ];
    font = "${snosuPlymouthTheme}/share/fonts/truetype/undefined-medium.ttf";
    # NO extraConfig with DebugFile/DebugLevel - that's debug-only
  };

  # GRUB Configuration
  boot.loader.grub = {
    enable = true;
    theme = snosuGrubTheme;
    splashImage = "${snosuGrubTheme}/background.png";
    
    # Hybrid boot support - both EFI and BIOS
    efiSupport = true;
    efiInstallAsRemovable = true;  # Critical for Ventoy compatibility
    device = "nodev";  # Will be set during image postVM hook
    
    # GRUB configuration
    useOSProber = true;  # Detect other OSes on local drives
    
    # NOTE: Do not add manual 'menuentry' items here for kernel/initrd.
    # On the ISO, kernel paths are dynamic and managed by the ISO generator.
    # Manual entries with '/boot/kernel' will fail.
  };
  
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.grub.memtest86.enable = lib.mkForce false;  # Keep menu clean
}
