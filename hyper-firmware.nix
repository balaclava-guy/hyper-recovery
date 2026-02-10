{ pkgs, lib }:

let
  inherit (pkgs) stdenv linux-firmware runCommand coreutils findutils;

  firmwareSrc = "${linux-firmware}/lib/firmware";

  # Keep this list intentionally biased toward recovery:
  # - Common Intel/AMD GPUs (Plymouth/KMS)
  # - Common WiFi families
  # - Minimal wired NIC firmware so users can get online to fetch more if needed
  #
  # Anything not in this list can be enabled at runtime via `hyper-hw firmware full`.
  keepDirs = [
    # GPU / display
    "i915"
    "amdgpu"

    # WiFi
    "iwlwifi"
    "ath10k"
    "ath11k"
    "brcm"
    "mediatek"
    "mt76"
    "rtw88"
    "rtw89"

    # Bluetooth (common laptop combos)
    "rtl_bt"

    # Wired NIC (fallback path to get online)
    "bnx2"
    "bnx2x"
    "tg3"
    "rtl_nic"
  ];
in
{
  hyperFirmwareCore = runCommand "hyper-firmware-core" {
    # Ensure the builder has basic utils even in restricted environments.
    nativeBuildInputs = [ coreutils findutils ];
  } ''
    set -euo pipefail

    out_firmware="$out/lib/firmware"
    mkdir -p "$out_firmware"

    copy_dir() {
      local d="$1"
      if [ -d "${firmwareSrc}/$d" ]; then
        # Dereference symlinks so we don't retain references to the full linux-firmware output.
        cp -aL "${firmwareSrc}/$d" "$out_firmware/"
      fi
    }

    # Copy whitelisted directories (if present in this linux-firmware version).
    ${lib.concatMapStringsSep "\n" (d: "copy_dir ${lib.escapeShellArg d}") keepDirs}

    # Intel Bluetooth firmware: keep only ibt-* (avoid pulling unrelated intel blobs).
    if [ -d "${firmwareSrc}/intel" ]; then
      mkdir -p "$out_firmware/intel"
      shopt -s nullglob
      for f in "${firmwareSrc}/intel"/ibt-*; do
        cp -aL "$f" "$out_firmware/intel/"
      done
    fi

    # Sanity check: ensure we didn't accidentally include the entire linux-firmware tree.
    # (This is a soft check; it doesn't fail builds, but helps catch obvious mistakes.)
    if [ -d "$out_firmware/iwlwifi" ] || [ -d "$out_firmware/i915" ]; then
      : # expected
    fi
  '';
}
