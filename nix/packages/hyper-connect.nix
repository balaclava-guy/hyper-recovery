# Nix package for hyper-connect
{ lib
, rustPlatform
, pkg-config
, dbus
, openssl
}:

rustPlatform.buildRustPackage rec {
  pname = "hyper-connect";
  version = "0.1.0";

  src = ../../pkgs/hyper-connect;

  cargoLock = {
    lockFile = ../../pkgs/hyper-connect/Cargo.lock;
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
