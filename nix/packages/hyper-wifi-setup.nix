# Nix package for hyper-wifi-setup
{ lib
, rustPlatform
, pkg-config
, dbus
, openssl
}:

rustPlatform.buildRustPackage rec {
  pname = "hyper-wifi-setup";
  version = "0.1.0";

  src = ../../pkgs/hyper-wifi-setup;

  cargoLock = {
    lockFile = ../../pkgs/hyper-wifi-setup/Cargo.lock;
  };

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    dbus
    openssl
  ];

  # Skip tests in build (they require network/dbus)
  doCheck = false;

  meta = with lib; {
    description = "WiFi setup daemon with TUI and captive portal for Hyper Recovery";
    homepage = "https://github.com/snosu/hyper-recovery";
    license = licenses.mit;
    maintainers = [];
    platforms = platforms.linux;
  };
}
