{ config, pkgs, lib, ... }:

# Base system configuration for Hyper Recovery environment
# This module contains core system identity, users, and basic settings
# WITHOUT any debug features (those go in debug-overlay.nix)

let
  # Import scripts (will be properly wired once we integrate with flake-parts)
  scripts = pkgs.callPackage ../packages/scripts {};
in
{
  # Core System Identity
  networking.hostName = "hyper-recovery";
  networking.hostId = "8425e349";
  system.stateVersion = "25.05";

  # Performance & Space Optimizations
  documentation.enable = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # ZFS & Filesystems
  boot.supportedFilesystems = [ "zfs" "exfat" "vfat" "iso9660" "squashfs" "overlay" ];
  boot.zfs.forceImportRoot = false;

  # Networking
  networking.networkmanager.enable = true;
  networking.dhcpcd.enable = false;

  # UI & Branding
  environment.etc."motd".text = ''
    Welcome to Snosu Hyper Recovery Environment
    * Access the Web UI at: https://<IP>:9090
    * Default user: snosu / nixos
  '';

  environment.etc."snosu/motd-logo.ansi".source = ../../assets/motd-logo.ansi;

  environment.etc."profile.d/snosu-motd.sh".text = ''
    #!/usr/bin/env bash

    # Print the logo only in interactive TTY login shells.
    if [[ "$-" != *i* ]] || [[ ! -t 1 ]]; then
      return 0 2>/dev/null || exit 0
    fi

    # Avoid duplicate output in nested shells.
    if [[ -n "''${SNOSU_MOTD_SHOWN:-}" ]]; then
      return 0 2>/dev/null || exit 0
    fi
    export SNOSU_MOTD_SHOWN=1

    logo_file=/etc/snosu/motd-logo.ansi
    if [[ ! -r "$logo_file" ]]; then
      return 0 2>/dev/null || exit 0
    fi

    parent_comm="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d '[:space:]')"
    is_cockpit=0
    if [[ -n "''${COCKPIT:-}" ]] || [[ "$parent_comm" == "cockpit-session" ]] || [[ "$parent_comm" == "cockpit-bridge" ]]; then
      is_cockpit=1
    fi

    supports_truecolor=0
    case "''${COLORTERM:-}" in
      *truecolor*|*24bit*) supports_truecolor=1 ;;
    esac
    if [[ "$supports_truecolor" -eq 0 ]]; then
      case "''${TERM:-}" in
        *-direct|xterm-kitty|wezterm|alacritty|foot*) supports_truecolor=1 ;;
      esac
    fi

    supports_256=0
    if command -v tput >/dev/null 2>&1; then
      colors="$(tput colors 2>/dev/null || echo 0)"
      if [[ "$colors" =~ ^[0-9]+$ ]] && [[ "$colors" -ge 256 ]]; then
        supports_256=1
      fi
    fi
    if [[ "$supports_256" -eq 0 ]]; then
      case "''${TERM:-}" in
        *256color*) supports_256=1 ;;
      esac
    fi

    if [[ "$is_cockpit" -eq 0 ]]; then
      if [[ "$supports_truecolor" -eq 1 ]]; then
        cat "$logo_file"
      elif [[ "$supports_256" -eq 1 ]] && command -v perl >/dev/null 2>&1; then
        cache_file="/tmp/snosu-motd-logo-256.''${UID:-0}.ansi"
        tmp_file="$cache_file.$$"

        if [[ ! -s "$cache_file" ]] || [[ "$logo_file" -nt "$cache_file" ]]; then
          if perl -CS -pe '
            sub rgb_to_256 {
              my ($r, $g, $b) = @_;
              my $ri = int(($r / 255) * 5 + 0.5);
              my $gi = int(($g / 255) * 5 + 0.5);
              my $bi = int(($b / 255) * 5 + 0.5);
              $ri = 0 if $ri < 0; $ri = 5 if $ri > 5;
              $gi = 0 if $gi < 0; $gi = 5 if $gi > 5;
              $bi = 0 if $bi < 0; $bi = 5 if $bi > 5;

              my $cube_idx = 16 + 36 * $ri + 6 * $gi + $bi;
              my @cube_vals = map { $_ == 0 ? 0 : 55 + $_ * 40 } ($ri, $gi, $bi);
              my $cube_dist = ($r - $cube_vals[0]) ** 2 + ($g - $cube_vals[1]) ** 2 + ($b - $cube_vals[2]) ** 2;

              my $gray_step = int((($r + $g + $b) / 3 - 8) / 10 + 0.5);
              $gray_step = 0 if $gray_step < 0;
              $gray_step = 23 if $gray_step > 23;
              my $gray_val = 8 + 10 * $gray_step;
              my $gray_idx = 232 + $gray_step;
              my $gray_dist = ($r - $gray_val) ** 2 + ($g - $gray_val) ** 2 + ($b - $gray_val) ** 2;

              return $gray_dist < $cube_dist ? $gray_idx : $cube_idx;
            }

            s/\e\[((?:3|4)8);2;(\d+);(\d+);(\d+)m/sprintf("\e[%s;5;%dm", $1, rgb_to_256($2, $3, $4))/ge;
          ' "$logo_file" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$cache_file"
          else
            rm -f "$tmp_file"
          fi
        fi

        if [[ -r "$cache_file" ]]; then
          cat "$cache_file"
        fi
      fi
    fi
  '';

  # Standard Packages (including user-facing diagnostic tools)
  environment.systemPackages = with pkgs; [
    qemu-utils zfs parted gptfdisk htop vim git perl
    pciutils usbutils smartmontools nvme-cli os-prober efibootmgr
    wpa_supplicant dhcpcd udisks2
    networkmanager  # nmcli
    iw
    plymouth  # For Plymouth debugging
    scripts.hyper-debug  # User-triggered diagnostics
    scripts.hyper-hw     # Firmware management
  ];

  # User Authentication
  users.mutableUsers = false;
  users.users.root = {
    initialPassword = lib.mkForce null;
    hashedPassword = lib.mkForce null;
    hashedPasswordFile = lib.mkForce null;
    initialHashedPassword = lib.mkForce null;
  };
  users.users.snosu = {
    isNormalUser = true;
    password = "nixos";
    extraGroups = [ "wheel" ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };
}
