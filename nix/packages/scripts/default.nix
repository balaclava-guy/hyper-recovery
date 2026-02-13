{ pkgs, lib }:

let
  # Helper function to create a Python script package
  makePythonScript = { name, script, runtimeInputs ? [] }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1.0.0";
      
      dontUnpack = true;
      dontBuild = true;
      
      nativeBuildInputs = [ pkgs.makeWrapper ];
      
      installPhase = ''
        mkdir -p $out/bin
        cp ${script} $out/bin/${name}
        chmod +x $out/bin/${name}
        
        # Ensure it uses the packaged Python
        substituteInPlace $out/bin/${name} \
          --replace '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
        
        # Wrap with runtime dependencies in PATH
        ${lib.optionalString (runtimeInputs != []) ''
          wrapProgram $out/bin/${name} \
            --prefix PATH : ${lib.makeBinPath runtimeInputs}
        ''}
      '';
    };
in
{
  # User-facing diagnostic tool (included in regular build)
  hyper-debug = makePythonScript {
    name = "hyper-debug";
    script = ../../../scripts/hyper-debug.py;
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
      plymouth
      pciutils
      mount
      umount
    ];
  };
  
  # Hardware/firmware management tool (included in regular build)
  hyper-hw = makePythonScript {
    name = "hyper-hw";
    script = ../../../scripts/hyper-hw.py;
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      nix
      kmod
    ];
  };
  
  # Debug-only: Serial console debug dumper
  hyper-debug-serial = makePythonScript {
    name = "hyper-debug-serial";
    script = ../../../scripts/hyper-debug-serial.py;
    runtimeInputs = with pkgs; [
      coreutils
      # hyper-debug will be in PATH via the debug service
    ];
  };
  
  # Debug-only: Automatic boot log saver
  save-boot-logs = makePythonScript {
    name = "save-boot-logs";
    script = ../../../scripts/save-boot-logs.py;
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
      mount
      umount
    ];
  };
  
  # CI-only: Automated debug collection for GitHub Actions
  hyper-ci-debug = makePythonScript {
    name = "hyper-ci-debug";
    script = ../../../scripts/hyper-ci-debug.py;
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
      plymouth
      pciutils
      iproute2
      networkmanager
      mount
      umount
      findutils
    ];
  };

  # Developer utility: fetch latest live ISO artifact and copy to Ventoy
  hyper-fetch-iso = makePythonScript {
    name = "hyper-fetch-iso";
    script = ../../../scripts/hyper-fetch-iso.py;
    runtimeInputs = with pkgs; [
      coreutils
      git
      gh
      p7zip
    ];
  };
}
