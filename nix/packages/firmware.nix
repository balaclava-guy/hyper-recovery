{ pkgs, lib }:

let
  inherit (pkgs) linux-firmware runCommand coreutils findutils;

  firmwareSrc = "${linux-firmware}/lib/firmware";

  mkFirmwareSubset = {
    name,
    dirs,
    fileGlobs ? [ ],
  }:
    runCommand name {
      nativeBuildInputs = [ coreutils findutils ];
    } ''
      set -euo pipefail

      out_firmware="$out/lib/firmware"
      mkdir -p "$out_firmware"

      copy_dir() {
        local d="$1"
        if [ -d "${firmwareSrc}/$d" ]; then
          cp -aL "${firmwareSrc}/$d" "$out_firmware/"
        fi
      }

      copy_glob() {
        local pattern="$1"
        shopt -s nullglob
        for f in ${firmwareSrc}/$pattern; do
          if [ -f "$f" ]; then
            cp -aL "$f" "$out_firmware/"
          fi
        done
      }

      ${lib.concatMapStringsSep "\n" (d: "copy_dir ${lib.escapeShellArg d}") dirs}
      ${lib.concatMapStringsSep "\n" (g: "copy_glob ${lib.escapeShellArg g}") fileGlobs}

      # Keep Intel BT blobs for laptop combo cards.
      if [ -d "${firmwareSrc}/intel" ]; then
        mkdir -p "$out_firmware/intel"
        shopt -s nullglob
        for f in "${firmwareSrc}/intel"/ibt-*; do
          cp -aL "$f" "$out_firmware/intel/"
        done
      fi
    '';

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

  wirelessAllDirs = [
    "ath3k"
    "ath6k"
    "ath9k_htc"
    "ath10k"
    "ath11k"
    "ath12k"
    "b43"
    "b43legacy"
    "brcm"
    "cypress"
    "iwlwifi"
    "libertas"
    "mediatek"
    "mt7601u"
    "mt76"
    "mwl8k"
    "mwlwifi"
    "qca"
    "rsi_91x"
    "rtlwifi"
    "rtw88"
    "rtw89"
    "rtl_bt"
    "ti-connectivity"
    "wil6210"
    "wfx"
    "wl12xx"
    "wl18xx"
    "zd1211"
  ];

  wirelessRootGlobs = [
    "carl9170-1.fw"
    "htc_7010.fw"
    "htc_9271.fw"
    "iwlwifi-*.ucode"
    "iwlwifi-*.pnvm"
    "iwlwifi-*.iml"
    "iwlwifi-*.bseq"
    "rt*.bin"
    "rt*.fw"
  ];
in
{
  hyper-firmware-core = mkFirmwareSubset {
    name = "hyper-firmware-core";
    dirs = keepDirs;
  };

  hyper-firmware-wireless-all = mkFirmwareSubset {
    name = "hyper-firmware-wireless-all";
    dirs = wirelessAllDirs;
    fileGlobs = wirelessRootGlobs;
  };
}
