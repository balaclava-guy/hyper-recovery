#!/usr/bin/env python3
"""
hyper-debug: Collect system diagnostics for Hyper Recovery environment.

This script gathers comprehensive system information useful for debugging
boot issues, hardware problems, and system failures. It collects logs,
device information, and system state, then optionally copies everything
to a Ventoy USB drive for offline analysis.

Usage:
    hyper-debug [--output-dir DIR]

Environment variables:
    HYPER_DEBUG_DIR: Override default output directory
"""

import argparse
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


def run_command(cmd: list[str], output_file: Path, description: str = "") -> None:
    """
    Run a command and save its output to a file.
    
    Args:
        cmd: Command and arguments as a list
        output_file: Path to save the output
        description: Human-readable description for logging
    """
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=30,
        )
        with output_file.open('w') as f:
            if result.stdout:
                f.write(result.stdout)
            if result.stderr:
                f.write(f"\n--- stderr ---\n{result.stderr}")
        if description:
            print(f"✓ {description}")
    except subprocess.TimeoutExpired:
        print(f"⚠ {description} timed out", file=sys.stderr)
    except FileNotFoundError:
        print(f"⚠ {' '.join(cmd)} not found, skipping", file=sys.stderr)
    except Exception as e:
        print(f"⚠ {description} failed: {e}", file=sys.stderr)


def collect_system_info(out_dir: Path) -> None:
    """Collect basic system information."""
    info_file = out_dir / "system-info.txt"
    
    with info_file.open('w') as f:
        f.write("=== System Info ===\n")
        f.write(f"Collection time: {datetime.now().isoformat()}\n\n")
    
    # Append uname
    run_command(["uname", "-a"], info_file, "System info (uname)")
    
    # Append os-release
    try:
        with open("/etc/os-release") as src:
            with info_file.open('a') as dst:
                dst.write("\n=== OS Release ===\n")
                dst.write(src.read())
    except FileNotFoundError:
        pass
    
    # Append cmdline
    try:
        with open("/proc/cmdline") as src:
            with info_file.open('a') as dst:
                dst.write("\n=== Kernel Command Line ===\n")
                dst.write(src.read())
    except FileNotFoundError:
        pass


def collect_block_devices(out_dir: Path) -> None:
    """Collect block device information."""
    block_file = out_dir / "block-devices.txt"
    
    with block_file.open('w') as f:
        f.write("=== Block Devices ===\n")
    
    # lsblk
    run_command(
        ["lsblk", "-a", "-o", "NAME,KNAME,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS"],
        block_file,
        "Block devices (lsblk)"
    )
    
    # blkid
    with block_file.open('a') as f:
        f.write("\n=== Block IDs ===\n")
    run_command(["blkid"], block_file, "Block IDs (blkid)")
    
    # /dev/disk/by-label
    with block_file.open('a') as f:
        f.write("\n=== Disk Labels ===\n")
    run_command(["ls", "-la", "/dev/disk/by-label/"], block_file, "Disk labels")


def collect_mounts(out_dir: Path) -> None:
    """Collect mount information."""
    run_command(
        ["findmnt", "-a"],
        out_dir / "mounts.txt",
        "Mounts (findmnt)"
    )


def collect_systemd_status(out_dir: Path) -> None:
    """Collect systemd service status."""
    run_command(
        ["systemctl", "--failed"],
        out_dir / "systemd-failed.txt",
        "Failed services (systemctl)"
    )
    
    run_command(
        ["systemctl", "status"],
        out_dir / "systemd-status.txt",
        "Systemd status"
    )


def collect_plymouth_info(out_dir: Path) -> None:
    """Collect Plymouth boot splash information."""
    plymouth_file = out_dir / "plymouth.txt"
    
    with plymouth_file.open('w') as f:
        f.write("=== Plymouth ===\n")
    
    # Check if Plymouth daemon is running
    try:
        subprocess.run(
            ["plymouth", "--ping"],
            capture_output=True,
            timeout=5,
            check=True
        )
        with plymouth_file.open('a') as f:
            f.write("Plymouth daemon: RUNNING\n\n")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        with plymouth_file.open('a') as f:
            f.write("Plymouth daemon: NOT RUNNING\n\n")
    
    # List available themes
    with plymouth_file.open('a') as f:
        f.write("=== Available Themes ===\n")
    run_command(
        ["plymouth-set-default-theme", "--list"],
        plymouth_file,
        "Plymouth themes"
    )
    
    # Current theme
    try:
        result = subprocess.run(
            ["plymouth-set-default-theme"],
            capture_output=True,
            text=True,
            timeout=5
        )
        with plymouth_file.open('a') as f:
            f.write(f"\nCurrent theme: {result.stdout.strip()}\n\n")
    except Exception:
        pass
    
    # Plymouth runtime directory
    with plymouth_file.open('a') as f:
        f.write("=== Runtime Directory ===\n")
    run_command(["ls", "-la", "/run/plymouth/"], plymouth_file, "Plymouth runtime")
    
    # Plymouth config
    with plymouth_file.open('a') as f:
        f.write("\n=== Configuration ===\n")
    try:
        with open("/etc/plymouth/plymouthd.conf") as src:
            with plymouth_file.open('a') as dst:
                dst.write(src.read())
    except FileNotFoundError:
        pass


def collect_kernel_messages(out_dir: Path) -> None:
    """Collect kernel ring buffer messages."""
    # Try with timestamps first
    result = subprocess.run(
        ["dmesg", "-T"],
        capture_output=True,
        text=True
    )
    
    if result.returncode == 0:
        with (out_dir / "dmesg.txt").open('w') as f:
            f.write(result.stdout)
        print("✓ Kernel messages (dmesg)")
    else:
        # Fallback to plain dmesg
        run_command(
            ["dmesg"],
            out_dir / "dmesg.txt",
            "Kernel messages (dmesg)"
        )


def collect_journal_logs(out_dir: Path) -> None:
    """Collect systemd journal logs."""
    # Full boot journal
    run_command(
        ["journalctl", "-b", "--no-pager"],
        out_dir / "journal.txt",
        "Journal (full boot)"
    )
    
    # Plymouth-specific logs
    run_command(
        ["journalctl", "-b", "-u", "plymouth*", "--no-pager"],
        out_dir / "journal-plymouth.txt",
        "Journal (Plymouth)"
    )
    
    # Cockpit logs
    run_command(
        ["journalctl", "-b", "-u", "cockpit.socket", "-u", "cockpit.service",
         "-u", "cockpit-wsinstance*", "-u", "cockpit-session*", "--no-pager"],
        out_dir / "journal-cockpit.txt",
        "Journal (Cockpit)"
    )


def collect_graphics_info(out_dir: Path) -> None:
    """Collect graphics and DRM information."""
    graphics_file = out_dir / "graphics.txt"
    
    with graphics_file.open('w') as f:
        f.write("=== Graphics ===\n")
    
    # DRI devices
    run_command(["ls", "-la", "/dev/dri/"], graphics_file, "DRI devices")
    
    # DRM status
    with graphics_file.open('a') as f:
        f.write("\n=== DRM Status ===\n")
    
    try:
        for drm_path in Path("/sys/class/drm").glob("*/status"):
            with drm_path.open() as src:
                with graphics_file.open('a') as dst:
                    dst.write(f"{drm_path}: {src.read()}")
    except Exception:
        pass
    
    # VGA info from lspci
    with graphics_file.open('a') as f:
        f.write("\n=== PCI Graphics ===\n")
    
    try:
        result = subprocess.run(
            ["lspci", "-k"],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Extract VGA-related lines
        for line in result.stdout.split('\n'):
            if 'vga' in line.lower() or 'display' in line.lower():
                with graphics_file.open('a') as f:
                    f.write(line + '\n')
                # Get next 3 lines for driver info
                idx = result.stdout.split('\n').index(line)
                for i in range(1, 4):
                    if idx + i < len(result.stdout.split('\n')):
                        with graphics_file.open('a') as f:
                            f.write(result.stdout.split('\n')[idx + i] + '\n')
                break
    except Exception:
        pass


def try_copy_to_ventoy(out_dir: Path) -> bool:
    """
    Attempt to copy diagnostics to Ventoy USB drive.
    
    Returns:
        True if successfully copied, False otherwise
    """
    ventoy_labels = ["Ventoy", "VENTOY", "ventoy"]
    mount_point = Path("/mnt/ventoy-debug")
    
    for label in ventoy_labels:
        device_path = Path(f"/dev/disk/by-label/{label}")
        if not device_path.exists():
            continue
        
        try:
            # Create mount point
            mount_point.mkdir(parents=True, exist_ok=True)
            
            # Mount Ventoy
            subprocess.run(
                ["mount", "-o", "rw", str(device_path), str(mount_point)],
                check=True,
                timeout=10,
                capture_output=True
            )
            
            # Copy diagnostics
            dest_dir = mount_point / "hyper-recovery-debug"
            dest_dir.mkdir(parents=True, exist_ok=True)
            
            for item in out_dir.iterdir():
                if item.is_file():
                    shutil.copy2(item, dest_dir)
            
            # Sync filesystem
            subprocess.run(["sync"], timeout=30)
            
            print(f"\n✓ Copied to Ventoy USB: {dest_dir}")
            
            # Unmount
            subprocess.run(
                ["umount", str(mount_point)],
                timeout=10,
                capture_output=True
            )
            
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"⚠ Failed to mount/copy to Ventoy: {e}", file=sys.stderr)
            # Try to unmount if mount succeeded but copy failed
            subprocess.run(
                ["umount", str(mount_point)],
                capture_output=True,
                timeout=10
            )
        except Exception as e:
            print(f"⚠ Ventoy copy error: {e}", file=sys.stderr)
    
    return False


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Collect system diagnostics for Hyper Recovery"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Output directory (default: $HYPER_DEBUG_DIR or /tmp/hyper-debug-TIMESTAMP)"
    )
    
    args = parser.parse_args()
    
    # Determine output directory
    if args.output_dir:
        out_dir = args.output_dir
    elif "HYPER_DEBUG_DIR" in os.environ:
        out_dir = Path(os.environ["HYPER_DEBUG_DIR"])
    else:
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        out_dir = Path(f"/tmp/hyper-debug-{timestamp}")
    
    # Create output directory
    out_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Collecting system diagnostics to {out_dir} ...\n")
    
    # Collect all diagnostics
    collect_system_info(out_dir)
    collect_block_devices(out_dir)
    collect_mounts(out_dir)
    collect_systemd_status(out_dir)
    collect_plymouth_info(out_dir)
    collect_kernel_messages(out_dir)
    collect_journal_logs(out_dir)
    collect_graphics_info(out_dir)
    
    print(f"\n✓ Diagnostics collected in: {out_dir}")
    
    # Try to copy to Ventoy USB
    try_copy_to_ventoy(out_dir)
    
    print(f"\nTo view: ls {out_dir}")
    print(f"To copy via SSH: scp -r root@<IP>:{out_dir} .")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
