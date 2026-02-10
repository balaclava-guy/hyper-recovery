#!/usr/bin/env python3
"""
hyper-hw: Hardware firmware management for Hyper Recovery.

This tool allows runtime switching between minimal "core" firmware (included
in the ISO) and full "full" firmware (downloaded via network when needed).

The recovery environment ships with minimal firmware to keep the ISO small,
but users can expand firmware coverage at runtime when they have network
connectivity.

Usage:
    hyper-hw firmware core    # Revert to core firmware
    hyper-hw firmware full    # Download and activate full linux-firmware

Implementation:
    This uses the firmware_class.path sysfs parameter to switch the kernel's
    firmware search path at runtime. Changes are non-persistent across reboot.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional


SYSFS_PATH = Path("/sys/module/firmware_class/parameters/path")
STATE_DIR = Path("/run/hyper-hw")
BASE_PATH_FILE = STATE_DIR / "base-firmware-path"
OVERLAY_DIR = STATE_DIR / "firmware-overlay"
UNION_DIR = OVERLAY_DIR / "union"

# Default firmware path in NixOS activation scripts
DEFAULT_BASE_PATH = "/run/current-system/firmware/lib/firmware"


def print_usage() -> None:
    """Print usage information."""
    print("""Usage:
  hyper-hw firmware core
  hyper-hw firmware full

Notes:
  - "core" uses the minimal firmware included in the ISO
  - "full" downloads and activates full linux-firmware at runtime (requires network)
  - Changes are non-persistent across reboot
""")


def check_firmware_support() -> bool:
    """
    Check if firmware_class.path is available.
    
    Returns:
        True if supported, False otherwise
    """
    if not SYSFS_PATH.exists():
        print(f"ERROR: firmware_class.path is not available at {SYSFS_PATH}", file=sys.stderr)
        print("       (is firmware_class built as a module / parameter supported by this kernel?)", file=sys.stderr)
        return False
    return True


def get_base_firmware_path() -> str:
    """
    Get the base firmware path, either from saved state or current sysfs value.
    
    Returns:
        Path to base firmware directory
    """
    # Create state directory
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    
    # Check if we've saved the base path before
    if BASE_PATH_FILE.exists() and BASE_PATH_FILE.stat().st_size > 0:
        try:
            return BASE_PATH_FILE.read_text().strip()
        except Exception:
            pass
    
    # Read current firmware path from sysfs
    try:
        current_path = SYSFS_PATH.read_text().strip()
        if current_path:
            # Save it for later
            BASE_PATH_FILE.write_text(current_path)
            return current_path
    except Exception:
        pass
    
    # Fallback to NixOS default
    return DEFAULT_BASE_PATH


def set_firmware_core() -> int:
    """
    Switch to core firmware (minimal).
    
    Returns:
        Exit code (0 for success)
    """
    base_path = get_base_firmware_path()
    
    # Clean up overlay if it exists
    if OVERLAY_DIR.exists():
        shutil.rmtree(OVERLAY_DIR, ignore_errors=True)
    
    # Set firmware path to base
    try:
        SYSFS_PATH.write_text(base_path)
        print(f"✓ Firmware path set to core: {base_path}")
        return 0
    except Exception as e:
        print(f"ERROR: Failed to set firmware path: {e}", file=sys.stderr)
        return 1


def set_firmware_full() -> int:
    """
    Download and activate full linux-firmware.
    
    Returns:
        Exit code (0 for success)
    """
    # Check if nix is available
    if not shutil.which("nix"):
        print("ERROR: nix is not in PATH", file=sys.stderr)
        return 1
    
    base_path = get_base_firmware_path()
    
    # Download full linux-firmware via nix
    print("Downloading full linux-firmware via nix...")
    print("(This may take a while on first run)")
    
    try:
        result = subprocess.run(
            ["nix", "build", "--no-link", "--print-out-paths", "nixpkgs#linux-firmware"],
            capture_output=True,
            text=True,
            timeout=600,  # 10 minutes max
            check=True
        )
        
        fw_out = result.stdout.strip().split('\n')[-1]  # Last line is the path
        fw_lib = Path(fw_out) / "lib" / "firmware"
        
        if not fw_lib.exists():
            print(f"ERROR: linux-firmware build did not produce lib/firmware: {fw_out}", file=sys.stderr)
            return 1
        
        print(f"✓ Downloaded to: {fw_out}")
        
    except subprocess.CalledProcessError as e:
        print(f"ERROR: nix build failed: {e}", file=sys.stderr)
        if e.stderr:
            print(e.stderr, file=sys.stderr)
        return 1
    except subprocess.TimeoutExpired:
        print("ERROR: nix build timed out after 10 minutes", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: Unexpected error during download: {e}", file=sys.stderr)
        return 1
    
    # Build synthetic firmware tree (union of base + full)
    print("Building firmware overlay...")
    
    # Clean up old overlay
    if OVERLAY_DIR.exists():
        shutil.rmtree(OVERLAY_DIR, ignore_errors=True)
    
    UNION_DIR.mkdir(parents=True, exist_ok=True)
    
    # Symlink base firmware first
    base_firmware_path = Path(base_path)
    if base_firmware_path.exists():
        for item in base_firmware_path.rglob("*"):
            if item.is_file():
                rel_path = item.relative_to(base_firmware_path)
                dest = UNION_DIR / rel_path
                dest.parent.mkdir(parents=True, exist_ok=True)
                
                # Create symlink
                try:
                    dest.symlink_to(item)
                except FileExistsError:
                    pass  # File already exists, skip
    
    # Overlay full firmware (overwrites base symlinks if same name)
    for item in fw_lib.rglob("*"):
        if item.is_file():
            rel_path = item.relative_to(fw_lib)
            dest = UNION_DIR / rel_path
            dest.parent.mkdir(parents=True, exist_ok=True)
            
            # Remove existing symlink if present, then create new one
            if dest.exists() or dest.is_symlink():
                dest.unlink()
            
            try:
                dest.symlink_to(item)
            except Exception as e:
                print(f"⚠ Warning: Failed to symlink {rel_path}: {e}", file=sys.stderr)
    
    # Set firmware path to union
    try:
        SYSFS_PATH.write_text(str(UNION_DIR))
        print(f"✓ Firmware path set to full: {UNION_DIR}")
    except Exception as e:
        print(f"ERROR: Failed to set firmware path: {e}", file=sys.stderr)
        return 1
    
    # Trigger udev to reload firmware
    if shutil.which("udevadm"):
        print("Triggering udev to reload firmware...")
        try:
            subprocess.run(
                ["udevadm", "trigger"],
                timeout=30,
                capture_output=True
            )
            print("✓ udev triggered")
        except Exception as e:
            print(f"⚠ Warning: udevadm trigger failed: {e}", file=sys.stderr)
    
    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Hardware firmware management for Hyper Recovery",
        add_help=False  # We'll handle help ourselves for custom formatting
    )
    parser.add_argument("subcmd", nargs='?', help=argparse.SUPPRESS)
    parser.add_argument("action", nargs='?', help=argparse.SUPPRESS)
    
    # Parse args
    args = parser.parse_args()
    
    # Check for help
    if not args.subcmd or args.subcmd in ["-h", "--help", "help"]:
        print_usage()
        return 2
    
    # Validate command structure
    if args.subcmd != "firmware":
        print_usage()
        return 2
    
    if not args.action or args.action not in ["core", "full"]:
        print_usage()
        return 2
    
    # Check firmware_class support
    if not check_firmware_support():
        return 1
    
    # Execute command
    if args.action == "core":
        return set_firmware_core()
    elif args.action == "full":
        return set_firmware_full()
    else:
        print_usage()
        return 2


if __name__ == "__main__":
    sys.exit(main())
