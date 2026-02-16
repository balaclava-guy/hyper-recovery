#!/usr/bin/env python3
"""
Deploy Hyper Recovery image to Proxmox VMs
Builds on remote x86 builder, transfers to Proxmox, and creates/updates test VMs
"""

import argparse
import subprocess
import sys
import os
import json
from pathlib import Path

# Proxmox defaults
PROXMOX_HOST = "10.10.100.119"
PROXMOX_USER = "root"
PROXMOX_VMID_BIOS = 9001
PROXMOX_VMID_UEFI = 9002
PROXMOX_STORAGE = "local"
PROXMOX_ISO_DIR = "/var/lib/vz/template/iso"

def run_cmd(cmd, description, check=True, capture=False):
    """Run a command with nice output"""
    print(f"→ {description}...")
    if capture:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if check and result.returncode != 0:
            print(f"✗ Failed: {result.stderr}", file=sys.stderr)
            sys.exit(1)
        return result.stdout.strip()
    else:
        result = subprocess.run(cmd, shell=True)
        if check and result.returncode != 0:
            print(f"✗ Failed", file=sys.stderr)
            sys.exit(1)
    print(f"✓ {description} complete")

def build_image(debug=False):
    """Build the image using remote builder"""
    target = "usb-debug" if debug else "usb"
    print(f"\n=== Building {target} image on remote builder ===")

    # Build on remote builder (Nix will automatically use the builder from nix.conf)
    # We need to explicitly specify the system to trigger remote building
    # --max-jobs 0 forces all builds to remote builders (fixes "Undefined error: 0" on macOS)
    build_cmd = f"nix build .#{target} --print-out-paths --system x86_64-linux --max-jobs 0"
    out_path = run_cmd(build_cmd, f"Building {target} image", capture=True)

    # Find the ISO file
    iso_files = list(Path(out_path).rglob("*.iso"))
    if not iso_files:
        print("✗ No ISO file found in build output", file=sys.stderr)
        sys.exit(1)

    iso_path = str(iso_files[0])
    print(f"✓ Built image: {iso_path}")
    return iso_path

def transfer_to_proxmox(iso_path, proxmox_host, proxmox_user):
    """Transfer ISO to Proxmox host"""
    print(f"\n=== Transferring to Proxmox {proxmox_host} ===")

    iso_name = Path(iso_path).name
    remote_path = f"{PROXMOX_ISO_DIR}/{iso_name}"

    scp_cmd = f"scp {iso_path} {proxmox_user}@{proxmox_host}:{remote_path}"
    run_cmd(scp_cmd, f"Copying {iso_name} to Proxmox")

    return iso_name

def create_or_update_vm(proxmox_host, proxmox_user, vmid, name, iso_name, bios_mode="seabios"):
    """Create or update a Proxmox VM"""
    print(f"\n=== Configuring VM {vmid} ({name}) ===")

    ssh_prefix = f"ssh {proxmox_user}@{proxmox_host}"

    # Check if VM exists
    check_cmd = f"{ssh_prefix} 'qm status {vmid} 2>/dev/null'"
    result = subprocess.run(check_cmd, shell=True, capture_output=True)
    vm_exists = result.returncode == 0

    if vm_exists:
        print(f"→ VM {vmid} exists, stopping...")
        run_cmd(f"{ssh_prefix} 'qm stop {vmid} || true'", "Stopping VM", check=False)

        # Update ISO
        run_cmd(
            f"{ssh_prefix} 'qm set {vmid} --ide2 {PROXMOX_STORAGE}:iso/{iso_name},media=cdrom'",
            f"Updating VM {vmid} with new ISO"
        )
    else:
        print(f"→ Creating new VM {vmid}...")

        # Create VM
        create_cmd = f"""
        {ssh_prefix} 'qm create {vmid} \
            --name {name} \
            --memory 4096 \
            --cores 2 \
            --net0 virtio,bridge=vmbr0 \
            --ide2 {PROXMOX_STORAGE}:iso/{iso_name},media=cdrom \
            --boot order=ide2 \
            --bios {bios_mode} \
            --ostype l26'
        """
        run_cmd(create_cmd, f"Creating VM {vmid}")

    print(f"✓ VM {vmid} ({name}) ready with ISO: {iso_name}")

def main():
    parser = argparse.ArgumentParser(
        description="Deploy Hyper Recovery to Proxmox test VMs"
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Build debug variant"
    )
    parser.add_argument(
        "--proxmox-host",
        default=PROXMOX_HOST,
        help=f"Proxmox host (default: {PROXMOX_HOST})"
    )
    parser.add_argument(
        "--proxmox-user",
        default=PROXMOX_USER,
        help=f"Proxmox user (default: {PROXMOX_USER})"
    )
    parser.add_argument(
        "--vmid-bios",
        type=int,
        default=PROXMOX_VMID_BIOS,
        help=f"VM ID for BIOS test VM (default: {PROXMOX_VMID_BIOS})"
    )
    parser.add_argument(
        "--vmid-uefi",
        type=int,
        default=PROXMOX_VMID_UEFI,
        help=f"VM ID for UEFI test VM (default: {PROXMOX_VMID_UEFI})"
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip build step (use existing result/)"
    )
    parser.add_argument(
        "--build-only",
        action="store_true",
        help="Only build, don't deploy to Proxmox"
    )

    args = parser.parse_args()

    # Build image
    if args.skip_build:
        target = "usb-debug" if args.debug else "usb"
        iso_path = run_cmd(
            f"readlink -f result",
            "Finding existing build",
            capture=True
        )
        iso_files = list(Path(iso_path).rglob("*.iso"))
        if not iso_files:
            print("✗ No ISO found in result/", file=sys.stderr)
            sys.exit(1)
        iso_path = str(iso_files[0])
        print(f"✓ Using existing build: {iso_path}")
    else:
        iso_path = build_image(debug=args.debug)

    if args.build_only:
        print("\n✓ Build complete (--build-only specified)")
        return

    # Transfer to Proxmox
    iso_name = transfer_to_proxmox(iso_path, args.proxmox_host, args.proxmox_user)

    # Create/update VMs
    variant = "debug" if args.debug else "live"
    create_or_update_vm(
        args.proxmox_host,
        args.proxmox_user,
        args.vmid_bios,
        f"hyper-recovery-test-bios-{variant}",
        iso_name,
        bios_mode="seabios"
    )

    create_or_update_vm(
        args.proxmox_host,
        args.proxmox_user,
        args.vmid_uefi,
        f"hyper-recovery-test-uefi-{variant}",
        iso_name,
        bios_mode="ovmf"
    )

    print("\n" + "="*60)
    print("✓ Deployment complete!")
    print(f"  BIOS VM: {args.vmid_bios}")
    print(f"  UEFI VM: {args.vmid_uefi}")
    print(f"  ISO: {iso_name}")
    print("\nTo start VMs:")
    print(f"  ssh {args.proxmox_user}@{args.proxmox_host} 'qm start {args.vmid_bios}'")
    print(f"  ssh {args.proxmox_user}@{args.proxmox_host} 'qm start {args.vmid_uefi}'")
    print("="*60)

if __name__ == "__main__":
    main()
