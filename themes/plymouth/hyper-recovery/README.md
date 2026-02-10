# Snosu Hyper Recovery Plymouth Theme

This is a custom Plymouth boot splash theme created from `snouhr-logo-animated.mp4`.

## Features
*   **Animated Logo**: Loops continuously.
*   **Boot Messages**: Displays the last 3 boot status messages in the bottom right corner (Grey/White/Grey).
*   **Progress Bar**: A bouncing indicator below the text.
*   **Forced Loop**: Ensures the animation plays at least once (configurable via systemd).
*   **Skip**: Press `Space` to skip the forced loop delay if boot is ready.

## Installation on NixOS

1.  Move this `snosu-hyper-recovery` directory to your NixOS configuration directory (e.g., `/etc/nixos/` or `~/.config/nixos/`).

2.  Add the following configuration to your `configuration.nix` (or import it):

    ```nix
    { pkgs, ... }:
    let
      snosuTheme = pkgs.stdenv.mkDerivation {
        pname = "snosu-hyper-recovery-plymouth";
        version = "1.0";
        src = ./snosu-hyper-recovery; # Ensure this path points to this directory
        installPhase = ''
          mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery
          cp -r * $out/share/plymouth/themes/snosu-hyper-recovery
          # Fix permissions if needed
          chmod -R +w $out/share/plymouth/themes/snosu-hyper-recovery
        '';
      };
    in
    {
      boot.plymouth = {
        enable = true;
        theme = "snosu-hyper-recovery";
        themePackages = [ snosuTheme ];
      };
      
      # Optional: Ensure plymouth-quit waits for the animation loop if handled by systemd
      # (The script handles the delay internally, but this ensures the service doesn't kill it prematurely)
      systemd.services.plymouth-quit.serviceConfig.TimeoutStopSec = 20;
    }
    ```

3.  Rebuild your system:
    ```bash
    sudo nixos-rebuild switch
    ```

## Installation on Other Distros (Debian/Ubuntu/Fedora/Arch)

1.  Copy the directory to `/usr/share/plymouth/themes/`:
    ```bash
    sudo cp -r snosu-hyper-recovery /usr/share/plymouth/themes/
    ```

2.  Install/Set the theme:
    *   **Debian/Ubuntu**:
        ```bash
        sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth default.plymouth /usr/share/plymouth/themes/snosu-hyper-recovery/snosu-hyper-recovery.plymouth 100
        sudo update-alternatives --config default.plymouth  # Select the theme
        sudo update-initramfs -u
        ```
    *   **Arch/Fedora**:
        ```bash
        sudo plymouth-set-default-theme -R snosu-hyper-recovery
        ```

3.  Reboot to test.
