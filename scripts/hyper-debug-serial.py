#!/usr/bin/env python3
"""
hyper-debug-serial: Dump diagnostic information to serial console.

This script is designed to run automatically when hyper.debug=1 is passed
as a kernel parameter. It collects diagnostics via hyper-debug and outputs
key information to the serial console for debugging boot issues in headless
environments.

This is typically invoked by the hyper-debug-serial systemd service.

Usage:
    hyper-debug-serial
"""

import os
import subprocess
import sys
from pathlib import Path


DEBUG_DIR = Path("/run/hyper-debug")

# Files to output to serial console (in order)
FILES_TO_OUTPUT = [
    "system-info.txt",
    "plymouth.txt",
    "journal-plymouth.txt",
    "graphics.txt",
]


def main() -> int:
    """Main entry point."""
    # Set output directory for hyper-debug
    os.environ["HYPER_DEBUG_DIR"] = str(DEBUG_DIR)
    
    # Clean up any existing debug directory
    if DEBUG_DIR.exists():
        import shutil
        shutil.rmtree(DEBUG_DIR, ignore_errors=True)
    
    DEBUG_DIR.mkdir(parents=True, exist_ok=True)
    
    print("=== hyper-debug-serial start ===")
    
    # Run hyper-debug to collect diagnostics
    try:
        subprocess.run(
            ["hyper-debug"],
            timeout=120,  # 2 minutes max
            check=False  # Don't fail if hyper-debug has issues
        )
    except subprocess.TimeoutExpired:
        print("⚠ hyper-debug timed out", file=sys.stderr)
    except FileNotFoundError:
        print("ERROR: hyper-debug command not found", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"⚠ hyper-debug failed: {e}", file=sys.stderr)
    
    # Output selected files to console
    for filename in FILES_TO_OUTPUT:
        file_path = DEBUG_DIR / filename
        
        if not file_path.exists():
            continue
        
        try:
            print(f"\n--- {filename} ---")
            with file_path.open() as f:
                print(f.read())
            print()  # Extra newline for readability
        except Exception as e:
            print(f"⚠ Failed to read {filename}: {e}", file=sys.stderr)
    
    print("=== hyper-debug-serial end ===")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
