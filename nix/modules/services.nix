{ config, pkgs, lib, ... }:

# Services configuration for Hyper Recovery environment
# Cockpit, virtualization, and core services
# WITHOUT any automatic debug services

{
  # Virtualization Stack
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
    };
  };

  # Management Interface (Cockpit)
  services.cockpit = {
    enable = true;
    openFirewall = true;
    # Allow access from dynamic LAN IP/hostnames used by recovery images.
    allowed-origins = [ "*" ];
    plugins = with pkgs; [
      cockpit-machines
      cockpit-zfs
      cockpit-files
    ];
    settings = {
      WebService = {
        AllowUnencrypted = true;
        AllowRoot = true;
        LoginTitle = "SNOSU Hyper Recovery";
      };
    };
  };

  # Cockpit Branding
  # Cockpit 353+ reads branding from flat files in /etc/cockpit/branding/.
  environment.etc."cockpit/branding/branding.css".source = ../../assets/branding/branding.css;
  environment.etc."cockpit/branding/logo.png".source = ../../assets/branding/logo-source.png;
  environment.etc."cockpit/branding/brand-large.png".source = ../../assets/branding/logo-source.png;
  environment.etc."cockpit/branding/apple-touch-icon.png".source = ../../assets/branding/logo-source.png;
  environment.etc."cockpit/branding/favicon.ico".source = ../../assets/branding/logo-source.png;
  # Keep legacy layout for compatibility with older Cockpit behavior.
  environment.etc."cockpit/branding/snosu/branding.ini".source = ../../assets/branding/branding.ini;
  environment.etc."cockpit/branding/snosu/branding.css".source = ../../assets/branding/branding.css;
  environment.etc."cockpit/branding/snosu/logo.png".source = ../../assets/branding/logo-source.png;
  environment.etc."cockpit/branding/snosu/brand-large.png".source = ../../assets/branding/logo-source.png;
  environment.etc."cockpit/branding/snosu/apple-touch-icon.png".source = ../../assets/branding/logo-source.png;
  environment.etc."cockpit/branding/snosu/favicon.ico".source = ../../assets/branding/logo-source.png;
}
