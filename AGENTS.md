# Agent Instructions for Hyper Recovery

This document provides AI agents with context on the Hyper Recovery project, environmental setup, and workflow conventions.

## Environment Setup

### Nix Flakes & Direnv

This project uses **Nix Flakes** for reproducible builds and **direnv** for automatic environment loading:
- Ensure the top-level `.envrc` file contains `use flake`
- This automatically loads the Nix devshell defined in `nix/flake/devshells.nix`
- All required tools and dependencies are available in the devshell

### Development Environment

The devshell at `nix/flake/devshells.nix` provides:
- **Build tools**: nixpkgs-fmt, statix for formatting/format validation
- **Rust toolchain**: cargo, rustc (for hyper-connect Rust package)
- **Python**: For scripts in `scripts/` directory
- **QEMU tools**: For testing images (on aarch64-darwin)
- **Archive tools**: p7zip for handling compressed builds

All commands are wrapped into shell aliases (see `devshells.default.commands`):
- `build-usb` - Build regular USB image
- `build-usb-debug` - Build debug USB image
- `check` - Validate flake
- `run-theme-vm` - Preview boot themes locally
- `fetch-latest-iso` - Deploy latest ISO to Ventoy USB

## Project Overview

**Hyper Recovery** is a portable hypervisor USB system based on NixOS that:
- Boots from USB on any computer (BIOS or EFI mode)
- Provides KVM/QEMU/libvirt for running VMs
- Includes Cockpit web interface (port 9090) for management
- Supports ZFS pools (import existing Proxmox pools)
- Includes recovery tools like Clonezilla (via VM)
- Custom themed GRUB2 and Plymouth boot screens

**Important**: This is NOT an installer ISO. It's a hypervisor recovery platform.

## File Structure

```
nix/
├── flake/                 # Flake module definitions
│   ├── images.nix         # NixOS configurations (usb-live, vm, etc.)
│   ├── packages.nix       # Package definitions
│   ├── devshells.nix      # Development environments
│   └── apps.nix           # CLI applications
├── modules/
│   ├── system/            # System modules
│   │   ├── base.nix       # Core system, networking, users
│   │   ├── hardware.nix   # Kernel modules, firmware, drivers
│   │   ├── branding.nix   # GRUB, Plymouth, Cockpit themes
│   │   ├── services.nix   # Cockpit, virtualization
│   │   ├── hyper-connect.nix  # WiFi setup daemon
│   │   └── debug.nix      # Debug logging/services (optional)
│   └── iso/               # ISO-specific modules
│       ├── base.nix       # Common ISO settings
│       └── grub-bootloader.nix  # GRUB configuration
└── packages/
    ├── scripts/default.nix # Python script packaging helper
    ├── themes/             # GRUB and Plymouth theme packages
    └── firmware.nix        # Firmware packages (core/full)
pkgs/hyper-connect/
├── Cargo.toml              # Rust dependencies
├── src/
│   ├── main.rs             # Entry point
│   ├── controller/         # Controller/TUI (ratatui)
│   ├── tui/                # TUI components
│   └── web/                # Axum web server + Leptos SSR
scripts/
├── hyper-debug.py          # System diagnostics
├── hyper-hw.py             # Firmware management
├── hyper-fetch-iso.py      # ISO deployment to Ventoy
├── hyper-ci-debug.py       # CI log collection
└── theme-vm.py             # Local theme preview (QEMU)
themes/
├── grub/hyper-recovery/    # GRUB2 theme assets
└── plymouth/hyper-recovery/ # Plymouth animation (120 frames)
```

## Build Targets

### Primary Images

Run `nix build .#<target>`:

- `usb` - Hybrid USB/ISO image (BIOS + EFI boot)
- `usb-debug` - Debug variant with verbose logging
- `vm` - QCOW2 VM image for testing

### Compressed Archives

- `image-compressed` - `.7z` archive of regular image
- `image-all-compressed` - All compressed archives (regular + debug)

### Python Scripts

Available via `nix run .#<name>`:

- `hyper-fetch-iso` - Deploy ISO from GitHub Actions
- `hyper-debug` - Collect system diagnostics
- `hyper-hw` - Switch firmware modes (core/full)

## Conventions

### 1. Code Style

- **Nix**: Use `nixpkgs-fmt` for formatting (`nixpkgs-fmt .`)
- **Python**: Follow PEP 8, shebang `#!/usr/bin/env python3`
- **Rust**: Use `cargo fmt`, prefer explicit types for public APIs

### 2. Module Organization

- System modules in `nix/modules/system/`
- ISO-specific modules in `nix/modules/iso/`
- Each module should be self-contained with clear imports
- Use `imports = [ ... ]` in `images.nix` to compose the final system

### 3. Python Scripts

- Scripts packaged via `nix/packages/scripts/default.nix` using `makePythonScript`
- Include `python3` in shebang (managed by devshell)
- Use `subprocess.run` for shell commands, error handling with `subprocess.CalledProcessError`

### 4. Testing

- Use QEMU for testing images locally: `nix run .#theme-vm`
- Visual tests run in CI via `.github/workflows/build.yml`
- Three boot modes tested: BIOS, EFI, debug-EFI

### 5. Debug Logging

- Add `[debug]` to commit message to include debug artifacts in CI
- Add `[ci-debug]` to enable CI debug log collection (runs `hyper-ci-debug` inside VM)
- Debug logs extracted via virtio-9p shared folder

### 6. Git Workflow

Before pushing changes to a remote repository:
- **Always prompt the user** for confirmation
- Run `check` to validate the flake
- Run relevant builds (e.g., `build-usb`) to ensure no breakage

## Common Workflows

### Adding a New System Module

1. Create file in `nix/modules/system/<name>.nix`
2. Import in `nix/flake/images.nix`:
```nix
imports = [
  ...
  ../modules/system/<name>.nix
];
```

### Modifying Boot Themes

1. Edit assets in `themes/grub/hyper-recovery/` or `themes/plymouth/hyper-recovery/`
2. Test locally: `nix run .#theme-vm`
3. Build image: `nix build .#usb`
4. Test with Ventoy or `dd` to USB

### Debugging Build Issues

1. Run with verbose output: `nix build .#usb --print-build-logs`
2. Check module syntax: `nix flake check`
3. Validate Nix code: `statix check`
4. Format code: `nixpkgs-fmt .`

### Testing Rust Changes (hyper-connect)

1. Enter devshell (or ensure direnv is loaded)
2. Build with cargo: `cargo build --release`
3. Test manually or rebuild USB image

## Important Notes

- **This is a hypervisor recovery system, not an installer**
- Builds produce hybrid images that work in both BIOS and EFI mode
- Ventoy-compatible for multi-boot USB setups
- Custom branding follows specific color palette (see `docs/ARCHITECTURE_OVERVIEW.md`)
- Plymouth animation requires KMS drivers (i915, amdgpu, nouveau)
- Firmware can be switched at runtime via `hyper-hw firmware core|full`

## Documentation Reference

- `docs/ARCHITECTURE_OVERVIEW.md` - System architecture and module dependencies
- `docs/UPGRADE_NOTES.md` - Migration from ISO-based builds
- `docs/REMOTE_ISO_DEPLOYMENT.md` - Setting up automated ISO deployment
- `README.md` - User-facing documentation

## CI/CD Commit Flags

Add to commit message to control CI workflow:

- `[debug]` - Include debug artifacts (builds both regular + debug)
- `[ci-debug]` - Enable CI debug log extraction (runs `hyper-ci-debug` inside VM)
- `[preview]` - Run preview VM in CI with temporary public URL
- `[preview-debug]` - Preview VM with debug ISO

Example:
```
feat: add WiFi setup service [debug][preview]
```
