{ pkgs, lib }:

let
  version = import ../../version.nix;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "snosu-grub-theme";
  version = version.version;
  
  src = ../../../themes/grub/hyper-recovery;
  fontSrc = ../../../assets/fonts/undefined-medium/undefined-medium.ttf;
  
  nativeBuildInputs = [ pkgs.grub2 ];
  
  dontConfigure = true;
  
  buildPhase = ''
    runHook preBuild
    
    # Generate GRUB font files
    grub-mkfont -s 12 -o undefined_medium_12.pf2 $fontSrc
    grub-mkfont -s 14 -o undefined_medium_14.pf2 $fontSrc
    grub-mkfont -s 16 -o undefined_medium_16.pf2 $fontSrc
    grub-mkfont -s 24 -o undefined_medium_24.pf2 $fontSrc
    grub-mkfont -s 28 -o undefined_medium_28.pf2 $fontSrc
    
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out
    cp $src/* $out/
    cp *.pf2 $out/
    
    # Update theme.txt to use our custom font
    sed -i 's/Hyper Street Fighter 2 Regular/Undefined Medium/g' $out/theme.txt
    sed -i 's/Hyper Fighting Regular/Undefined Medium/g' $out/theme.txt
    
    runHook postInstall
  '';
  
  meta = with lib; {
    description = "SNOSU Hyper Recovery GRUB2 boot theme";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
