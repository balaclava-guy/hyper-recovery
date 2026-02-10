{ pkgs, lib }:

pkgs.stdenv.mkDerivation {
  pname = "snosu-plymouth-theme";
  version = "1.0.0";
  
  src = ../../../themes/plymouth/hyper-recovery;
  fontSrc = ../../../assets/fonts/undefined-medium/undefined-medium.ttf;
  
  nativeBuildInputs = [ pkgs.plymouth ];
  
  installPhase = ''
    mkdir -p $out/share/plymouth/themes/snosu-hyper-recovery
    
    # Copy theme files (script, plymouth config, images)
    cp snosu-hyper-recovery.plymouth $out/share/plymouth/themes/snosu-hyper-recovery/
    cp snosu-hyper-recovery.script $out/share/plymouth/themes/snosu-hyper-recovery/
    cp *.png $out/share/plymouth/themes/snosu-hyper-recovery/
    cp -r animation $out/share/plymouth/themes/snosu-hyper-recovery/
    
    # Copy and install font
    mkdir -p $out/share/fonts/truetype
    cp $fontSrc $out/share/fonts/truetype/undefined-medium.ttf
    
    # Also copy font to theme directory for direct access
    cp $fontSrc $out/share/plymouth/themes/snosu-hyper-recovery/undefined-medium.ttf
    
    # Verify all required files are present
    echo "Verifying Plymouth theme installation..."
    test -f $out/share/plymouth/themes/snosu-hyper-recovery/snosu-hyper-recovery.plymouth || \
      (echo "ERROR: .plymouth file missing" && exit 1)
    test -f $out/share/plymouth/themes/snosu-hyper-recovery/snosu-hyper-recovery.script || \
      (echo "ERROR: .script file missing" && exit 1)
    
    # Count animation frames
    frame_count=$(ls -1 $out/share/plymouth/themes/snosu-hyper-recovery/*.png 2>/dev/null | wc -l)
    echo "Found $frame_count PNG files in theme directory"
    
    # Fix permissions
    chmod -R +r $out/share/plymouth/themes/snosu-hyper-recovery
    chmod -R +r $out/share/fonts
  '';
  
  meta = with lib; {
    description = "Snosu Hyper Recovery Plymouth boot splash theme";
    license = licenses.unfree;  # Adjust as needed
    platforms = platforms.linux;
  };
}
