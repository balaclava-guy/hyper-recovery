{ pkgs, lib }:

pkgs.stdenv.mkDerivation {
  pname = "snosu-grub-theme";
  version = "1.0.0";
  
  src = ../../../themes/grub/hyper-recovery;
  fontSrc = ../../../assets/fonts/undefined-medium/undefined-medium.ttf;
  
  nativeBuildInputs = [ pkgs.grub2 ];
  
  installPhase = ''
    mkdir -p $out
    cp * $out/
    
    # Generate GRUB font files in various sizes
    grub-mkfont -s 12 -o $out/undefined_medium_12.pf2 $fontSrc
    grub-mkfont -s 14 -o $out/undefined_medium_14.pf2 $fontSrc
    grub-mkfont -s 16 -o $out/undefined_medium_16.pf2 $fontSrc
    grub-mkfont -s 24 -o $out/undefined_medium_24.pf2 $fontSrc
    grub-mkfont -s 28 -o $out/undefined_medium_28.pf2 $fontSrc
    
    # Update theme.txt to use our custom font
    sed -i 's/Hyper Street Fighter 2 Regular/Undefined Medium/g' $out/theme.txt
    sed -i 's/Hyper Fighting Regular/Undefined Medium/g' $out/theme.txt
  '';
  
  meta = with lib; {
    description = "Snosu Hyper Recovery GRUB2 boot theme";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
