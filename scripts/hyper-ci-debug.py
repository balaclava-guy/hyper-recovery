#!/usr/bin/env python3
"""
hyper-ci-debug: Collect debug info for CI/automated testing.

This script is designed to run automatically in CI environments (GitHub Actions)
to collect comprehensive debug information that can be extracted from the VM
and uploaded as artifacts.

Unlike hyper-debug (which targets Ventoy USB), this script:
- Writes to a well-known location that CI can extract (/tmp/ci-debug/)
- Includes additional CI-specific diagnostics
- Formats output for automated parsing
- Runs automatically via systemd service in debug builds

Usage:
    hyper-ci-debug [--output-dir DIR]

Environment variables:
    HYPER_CI_DEBUG_DIR: Override default output directory
"""

import argparse
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional


# Well-known location for CI to extract
DEFAULT_OUTPUT_DIR = Path("/tmp/ci-debug")

# Virtio-9p shared folder mount point (used in CI)
SHARED_MOUNT_POINT = Path("/mnt/ci-debug-share")
SHARED_MOUNT_TAG = "ci_debug_share"


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
            f.write(f"# Command: {' '.join(cmd)}\n")
            f.write(f"# Exit code: {result.returncode}\n")
            f.write(f"# Timestamp: {datetime.now().isoformat()}\n\n")
            if result.stdout:
                f.write(result.stdout)
            if result.stderr:
                f.write(f"\n--- stderr ---\n{result.stderr}")
        if description:
            print(f"✓ {description}")
    except subprocess.TimeoutExpired:
        print(f"⚠ {description} timed out", file=sys.stderr)
        with output_file.open('w') as f:
            f.write(f"# Command: {' '.join(cmd)}\n")
            f.write(f"# ERROR: Command timed out after 30s\n")
    except FileNotFoundError:
        print(f"⚠ {' '.join(cmd)} not found, skipping", file=sys.stderr)
    except Exception as e:
        print(f"⚠ {description} failed: {e}", file=sys.stderr)
        with output_file.open('w') as f:
            f.write(f"# Command: {' '.join(cmd)}\n")
            f.write(f"# ERROR: {e}\n")


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
    
    # Append uptime
    with info_file.open('a') as dst:
        dst.write("\n=== Uptime ===\n")
    run_command(["uptime"], info_file, "Uptime")


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
    
    # List all services
    run_command(
        ["systemctl", "list-units", "--type=service", "--all", "--no-pager"],
        out_dir / "systemd-services.txt",
        "All services"
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
        with plymouth_file.open('a') as dst:
            dst.write("(config file not found)\n")


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
    
    # WiFi setup logs
    run_command(
        ["journalctl", "-b", "-u", "hyper-wifi-setup", "--no-pager"],
        out_dir / "journal-wifi.txt",
        "Journal (WiFi Setup)"
    )
    
    # NetworkManager logs
    run_command(
        ["journalctl", "-b", "-u", "NetworkManager", "--no-pager"],
        out_dir / "journal-networkmanager.txt",
        "Journal (NetworkManager)"
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
    
    # Loaded kernel modules (graphics-related)
    with graphics_file.open('a') as f:
        f.write("\n=== Loaded Graphics Modules ===\n")
    
    try:
        result = subprocess.run(
            ["lsmod"],
            capture_output=True,
            text=True,
            timeout=10
        )
        for line in result.stdout.split('\n'):
            if any(mod in line.lower() for mod in ['drm', 'i915', 'amdgpu', 'nouveau', 'radeon', 'nvidia']):
                with graphics_file.open('a') as f:
                    f.write(line + '\n')
    except Exception:
        pass


def collect_network_info(out_dir: Path) -> None:
    """Collect network configuration and status."""
    network_file = out_dir / "network.txt"
    
    with network_file.open('w') as f:
        f.write("=== Network ===\n")
    
    # IP addresses
    run_command(["ip", "addr"], network_file, "IP addresses")
    
    # Routes
    with network_file.open('a') as f:
        f.write("\n=== Routes ===\n")
    run_command(["ip", "route"], network_file, "Routes")
    
    # NetworkManager status
    with network_file.open('a') as f:
        f.write("\n=== NetworkManager Status ===\n")
    run_command(["nmcli", "general", "status"], network_file, "NetworkManager status")
    
    # WiFi devices
    with network_file.open('a') as f:
        f.write("\n=== WiFi Devices ===\n")
    run_command(["nmcli", "device", "wifi", "list"], network_file, "WiFi devices")


def collect_grub_info(out_dir: Path) -> None:
    """Collect GRUB configuration and boot entries."""
    grub_file = out_dir / "grub.txt"
    
    with grub_file.open('w') as f:
        f.write("=== GRUB Configuration ===\n")
    
    # Check for GRUB config files
    grub_configs = [
        "/boot/grub/grub.cfg",
        "/boot/grub2/grub.cfg",
        "/boot/efi/EFI/BOOT/grub.cfg",
    ]
    
    for config_path in grub_configs:
        if Path(config_path).exists():
            with grub_file.open('a') as f:
                f.write(f"\n=== {config_path} ===\n")
            try:
                with open(config_path) as src:
                    with grub_file.open('a') as dst:
                        dst.write(src.read())
            except Exception as e:
                with grub_file.open('a') as dst:
                    dst.write(f"(error reading: {e})\n")


def create_summary(out_dir: Path) -> None:
    """Create a summary file with key information."""
    summary_file = out_dir / "SUMMARY.txt"
    
    with summary_file.open('w') as f:
        f.write("=== CI Debug Summary ===\n")
        f.write(f"Collection time: {datetime.now().isoformat()}\n")
        f.write(f"Output directory: {out_dir}\n\n")
        
        # List all collected files
        f.write("=== Collected Files ===\n")
        for item in sorted(out_dir.iterdir()):
            if item.is_file() and item.name != "SUMMARY.txt":
                size = item.stat().st_size
                f.write(f"  {item.name} ({size} bytes)\n")
        
        f.write("\n=== Quick Status ===\n")
        
        # Check for failed services
        failed_services_file = out_dir / "systemd-failed.txt"
        if failed_services_file.exists():
            content = failed_services_file.read_text()
            if "0 loaded units listed" in content or "No units found" in content:
                f.write("✓ No failed systemd services\n")
            else:
                f.write("⚠ Some systemd services failed (see systemd-failed.txt)\n")
        
        # Check Plymouth status
        plymouth_file = out_dir / "plymouth.txt"
        if plymouth_file.exists():
            content = plymouth_file.read_text()
            if "RUNNING" in content:
                f.write("✓ Plymouth daemon is running\n")
            else:
                f.write("⚠ Plymouth daemon is not running\n")
        
        f.write("\n=== Instructions ===\n")
        f.write("This debug bundle was automatically collected by hyper-ci-debug.\n")
        f.write("All files are in plain text format for easy analysis.\n")
        f.write("Check SUMMARY.txt first for an overview of system status.\n")


def setup_shared_folder() -> Optional[Path]:
    """
    Try to mount virtio-9p shared folder if available.
    
    Returns:
        Path to mounted shared folder, or None if not available
    """
    try:
        # Check if virtio-9p module is loaded
        result = subprocess.run(
            ["lsmod"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if "9p" not in result.stdout and "9pnet_virtio" not in result.stdout:
            # Try to load the module
            subprocess.run(
                ["modprobe", "9pnet_virtio"],
                capture_output=True,
                timeout=5
            )
        
        # Create mount point
        SHARED_MOUNT_POINT.mkdir(parents=True, exist_ok=True)
        
        # Try to mount the shared folder
        result = subprocess.run(
            ["mount", "-t", "9p", "-o", "trans=virtio,version=9p2000.L",
             SHARED_MOUNT_TAG, str(SHARED_MOUNT_POINT)],
            capture_output=True,
            timeout=10
        )
        
        if result.returncode == 0:
            print(f"✓ Mounted virtio-9p shared folder at {SHARED_MOUNT_POINT}")
            return SHARED_MOUNT_POINT
        else:
            return None
            
    except Exception as e:
        print(f"⚠ Could not mount shared folder: {e}", file=sys.stderr)
        return None


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Collect debug info for CI/automated testing"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help=f"Output directory (default: $HYPER_CI_DEBUG_DIR or {DEFAULT_OUTPUT_DIR})"
    )
    
    args = parser.parse_args()
    
    # Try to setup shared folder first (for CI environments)
    shared_folder = setup_shared_folder()
    
    # Determine output directory
    if args.output_dir:
        out_dir = args.output_dir
    elif shared_folder:
        # Use shared folder if available (CI environment)
        out_dir = shared_folder
        print(f"Using shared folder for CI: {out_dir}")
    elif "HYPER_CI_DEBUG_DIR" in os.environ:
        out_dir = Path(os.environ["HYPER_CI_DEBUG_DIR"])
    else:
        out_dir = DEFAULT_OUTPUT_DIR
    
    # Create output directory
    out_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Collecting CI debug info to {out_dir} ...\n")
    
    # Collect all diagnostics
    collect_system_info(out_dir)
    collect_block_devices(out_dir)
    collect_mounts(out_dir)
    collect_systemd_status(out_dir)
    collect_plymouth_info(out_dir)
    collect_kernel_messages(out_dir)
    collect_journal_logs(out_dir)
    collect_graphics_info(out_dir)
    collect_network_info(out_dir)
    collect_grub_info(out_dir)
    
    # Create summary
    create_summary(out_dir)
    
    print(f"\n✓ CI debug info collected in: {out_dir}")
    print(f"✓ Summary: {out_dir}/SUMMARY.txt")
    
    # Write completion marker file for coordination with CI
    # The workflow will poll for this file to know when to shut down the VM
    marker_file = out_dir / ".CI_DEBUG_COMPLETE"
    marker_file.write_text(f"Completed at: {datetime.now().isoformat()}\n")
    print(f"✓ Wrote completion marker: {marker_file}")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
