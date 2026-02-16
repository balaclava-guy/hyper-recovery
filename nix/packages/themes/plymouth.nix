{ pkgs, lib }:

let
  version = import ../version.nix;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "snosu-plymouth-theme";
  version = version.version;
  
  src = ../../../themes/plymouth/hyper-recovery;
  fontSrc = ../../../assets/fonts/undefined-medium/undefined-medium.ttf;
  
  nativeBuildInputs = [ pkgs.plymouth ];
  
  dontBuild = true;
  dontConfigure = true;
  
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery
    
    cp snosu-hyper-recovery.plymouth $out/share/plymouth/themes/snosu-hyper-recovery/
    cp snosu-hyper-recovery.script $out/share/plymouth/themes/snosu-hyper-recovery/
    cp *.png $out/share/plymouth/themes/snosu-hyper-recovery/
    cp -r animation $out/share/plymouth/themes/snosu-hyper-recovery/

    substituteInPlace $out/share/plymouth/themes/snosu-hyper-recovery/snosu-hyper-recovery.plymouth \
      --replace-fail "/run/current-system/sw/share/plymouth/themes/snosu-hyper-recovery" \
                     "$out/share/plymouth/themes/snosu-hyper-recovery"
    
    mkdir -p $out/share/fonts/truetype
    cp $fontSrc $out/share/fonts/truetype/undefined-medium.ttf
    cp $fontSrc $out/share/plymouth/themes/snosu-hyper-recovery/undefined-medium.ttf
    
    chmod -R +r $out/share/plymouth/themes/snosu-hyper-recovery
    chmod -R +r $out/share/fonts
    
    runHook postInstall
  '';
  
  meta = with lib; {
    description = "SNOSU Hyper Recovery Plymouth boot splash theme";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
