#!/usr/bin/env python3
"""
save-boot-logs: Save boot logs to Ventoy USB drive.

This script is designed to run automatically during boot (via systemd service)
in debug builds. It saves journalctl and dmesg output to a Ventoy USB drive
for offline analysis.

This helps debug boot issues by automatically capturing logs without requiring
user interaction or serial console access.

Usage:
    save-boot-logs
"""

import subprocess
import sys
from pathlib import Path


VENTOY_LABELS = ["VENTOY", "Ventoy", "ventoy"]
MOUNT_POINT = Path("/mnt/ventoy")
LOG_DIR_NAME = "boot-logs"


def find_ventoy_device() -> Path | None:
    """
    Find Ventoy USB device by label.
    
    Returns:
        Path to Ventoy device, or None if not found
    """
    for label in VENTOY_LABELS:
        device_path = Path(f"/dev/disk/by-label/{label}")
        if device_path.exists():
            return device_path
    return None


def save_logs() -> int:
    """
    Save boot logs to Ventoy USB drive.
    
    Returns:
        Exit code (0 for success)
    """
    # Find Ventoy device
    device = find_ventoy_device()
    if not device:
        # Not an error - Ventoy USB may not be present
        print("No Ventoy USB found, skipping log save")
        return 0
    
    print(f"Found Ventoy device: {device}")
    
    # Create mount point
    MOUNT_POINT.mkdir(parents=True, exist_ok=True)
    
    # Mount Ventoy
    try:
        subprocess.run(
            ["mount", "-o", "rw", str(device), str(MOUNT_POINT)],
            check=True,
            timeout=10,
            capture_output=True
        )
    except subprocess.CalledProcessError as e:
        print(f"Failed to mount Ventoy: {e}", file=sys.stderr)
        return 0  # Not critical
    except Exception as e:
        print(f"Mount error: {e}", file=sys.stderr)
        return 0
    
    # Create log directory
    log_dir = MOUNT_POINT / LOG_DIR_NAME
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"Failed to create log directory: {e}", file=sys.stderr)
        subprocess.run(["umount", str(MOUNT_POINT)], capture_output=True, timeout=10)
        return 0
    
    # Save journal logs
    try:
        journal_result = subprocess.run(
            ["journalctl", "-b", "-o", "short-precise"],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if journal_result.returncode == 0:
            (log_dir / "journal.txt").write_text(journal_result.stdout)
            print("✓ Saved journal logs")
    except Exception as e:
        print(f"⚠ Failed to save journal: {e}", file=sys.stderr)
    
    # Save dmesg logs
    try:
        dmesg_result = subprocess.run(
            ["dmesg", "-T"],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if dmesg_result.returncode == 0:
            (log_dir / "dmesg.txt").write_text(dmesg_result.stdout)
            print("✓ Saved dmesg logs")
        else:
            # Fallback to plain dmesg
            dmesg_result = subprocess.run(
                ["dmesg"],
                capture_output=True,
                text=True,
                timeout=30
            )
            if dmesg_result.returncode == 0:
                (log_dir / "dmesg.txt").write_text(dmesg_result.stdout)
                print("✓ Saved dmesg logs")
    except Exception as e:
        print(f"⚠ Failed to save dmesg: {e}", file=sys.stderr)
    
    # Sync filesystem
    try:
        subprocess.run(["sync"], timeout=30, check=True)
        print("✓ Synced filesystem")
    except Exception as e:
        print(f"⚠ Sync failed: {e}", file=sys.stderr)
    
    # Unmount
    try:
        subprocess.run(
            ["umount", str(MOUNT_POINT)],
            timeout=10,
            capture_output=True,
            check=True
        )
        print(f"✓ Logs saved to Ventoy: {log_dir}")
    except Exception as e:
        print(f"⚠ Unmount failed: {e}", file=sys.stderr)
    
    return 0


def main() -> int:
    """Main entry point."""
    return save_logs()


if __name__ == "__main__":
    sys.exit(main())
