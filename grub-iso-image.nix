# Custom ISO image module that uses GRUB2 for both BIOS and EFI boot
# This replaces the default syslinux-based BIOS boot with a unified GRUB2 bootloader
#
# Benefits:
# - Single bootloader for both BIOS and EFI
# - Unified boot menu appearance
# - Shared grub.cfg configuration
# - Simpler maintenance

{ config, lib, pkgs, ... }:

let
  # Timeout in grub is in seconds.
  # null means max timeout (infinity)
  # 0 means disable timeout
  grubTimeout = if config.boot.loader.timeout == null then -1 else config.boot.loader.timeout;

  # Target architecture for EFI
  targetArch = if config.boot.loader.grub.forcei686 then "ia32" else pkgs.stdenv.hostPlatform.efiArch;

  grubPkgs = if config.boot.loader.grub.forcei686 then pkgs.pkgsi686Linux else pkgs;

  # Options submenus (same as upstream iso-image.nix)
  optionsSubMenus = [
    { title = "Copy ISO Files to RAM"; class = "copytoram"; params = [ "copytoram" ]; }
    { title = "No modesetting"; class = "nomodeset"; params = [ "nomodeset" ]; }
    { title = "Debug Console Output"; class = "debug"; params = [ "debug" ]; }
    { title = "Disable display-manager"; class = "quirk-disable-displaymanager"; 
      params = [ "systemd.mask=display-manager.service" "plymouth.enable=0" ]; }
    { title = "Rotate framebuffer Clockwise"; class = "rotate-90cw"; params = [ "fbcon=rotate:1" ]; }
    { title = "Rotate framebuffer Upside-Down"; class = "rotate-180"; params = [ "fbcon=rotate:2" ]; }
    { title = "Rotate framebuffer Counter-Clockwise"; class = "rotate-90ccw"; params = [ "fbcon=rotate:3" ]; }
    { title = "Serial console=ttyS0,115200n8"; class = "serial"; params = [ "console=ttyS0,115200n8" ]; }
  ];

  # Build a single menu entry
  menuBuilderGrub2 = { name, class, image, params, initrd }: ''
    menuentry '${name}' --class ${class} {
      linux ${image} ''${isoboot} ${params}
      initrd ${initrd}
    }
  '';

  # Build all menu entries
  buildMenuGrub2 = { cfg ? config, params ? [] }:
    let
      menuConfig = {
        name = lib.concatStrings [
          cfg.isoImage.prependToMenuLabel
          cfg.system.nixos.distroName
          " "
          cfg.system.nixos.label
          cfg.isoImage.appendToMenuLabel
          (lib.optionalString (cfg.isoImage.configurationName != null) (" " + cfg.isoImage.configurationName))
        ];
        params = "init=${cfg.system.build.toplevel}/init ${toString cfg.boot.kernelParams} ${toString params}";
        image = "/boot/${cfg.boot.kernelPackages.kernel + "/" + cfg.system.boot.loader.kernelFile}";
        initrd = "/boot/${cfg.system.build.initialRamdisk + "/" + cfg.system.boot.loader.initrdFile}";
        class = "installer";
      };
    in
    ''
      ${lib.optionalString cfg.isoImage.showConfiguration (menuBuilderGrub2 menuConfig)}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          specName: { configuration, ... }:
          buildMenuGrub2 { cfg = configuration; inherit params; }
        ) cfg.specialisation
      )}
    '';

  # Unified GRUB menu configuration (works for both BIOS and EFI)
  grubMenuCfg = ''
    set textmode=${lib.boolToString (config.isoImage.forceTextMode)}

    #
    # Menu configuration
    #

    # Search using a "marker file"
    search --set=root --file /boot/grub/nixos-iso-marker

    insmod all_video
    insmod gfxterm
    insmod png
    set gfxpayload=keep
    set gfxmode=${lib.concatStringsSep "," [
      "1920x1200"
      "1920x1080"
      "1366x768"
      "1280x800"
      "1280x720"
      "1200x1920"
      "1024x768"
      "800x1280"
      "800x600"
      "auto"
    ]}

    if [ "$textmode" == "false" ]; then
      terminal_output gfxterm
      terminal_input  console
    else
      terminal_output console
      terminal_input  console
      # Sets colors for console term.
      set menu_color_normal=cyan/blue
      set menu_color_highlight=white/blue
    fi

    ${if config.isoImage.grubTheme != null then ''
      # Sets theme.
      set theme=($root)/boot/grub/theme/theme.txt
      # Load theme fonts
      $(find ${config.isoImage.grubTheme} -iname '*.pf2' -printf "loadfont ($root)/boot/grub/theme/%P\n")
    '' else ''
      if background_image ($root)/boot/grub/background.png; then
        set color_normal=black/black
        set color_highlight=white/blue
      else
        set menu_color_normal=cyan/blue
        set menu_color_highlight=white/blue
      fi
    ''}

    hiddenentry 'Text mode' --hotkey 't' {
      loadfont ($root)/boot/grub/unicode.pf2
      set textmode=true
      terminal_output console
    }

    ${lib.optionalString (config.isoImage.grubTheme != null) ''
      hiddenentry 'GUI mode' --hotkey 'g' {
        $(find ${config.isoImage.grubTheme} -iname '*.pf2' -printf "loadfont ($root)/boot/grub/theme/%P\n")
        set textmode=false
        terminal_output gfxterm
      }
    ''}
  '';

  # The unified grub.cfg that works for both BIOS and EFI
  grubCfg = pkgs.writeText "grub.cfg" ''
    set timeout=${toString grubTimeout}

    clear
    echo ""
    echo "Loading boot menu..."
    echo ""
    echo "Press 't' for text mode, 'c' for command line..."
    echo ""

    ${grubMenuCfg}

    # If the parameter iso_path is set, append the findiso parameter to the kernel
    # line. We need this to allow the nixos iso to be booted from grub directly.
    if [ ''${iso_path} ] ; then
      set isoboot="findiso=''${iso_path}"
    fi

    #
    # Menu entries
    #

    ${buildMenuGrub2 {}}
    submenu "Options" --class submenu {
      ${grubMenuCfg}

      ${lib.concatMapStringsSep "\n" ({ title, class, params }: ''
        submenu "${title}" --class ${class} {
          ${grubMenuCfg}
          ${buildMenuGrub2 { inherit params; }}
        }
      '') optionsSubMenus}
    }

    menuentry 'Shutdown' --class shutdown {
      halt
    }
    menuentry 'Reboot' --class reboot {
      reboot
    }
  '';

  # Modules needed for both BIOS and EFI GRUB
  grubModules = [
    # Filesystem and partition support
    "fat" "iso9660" "udf" "part_gpt" "part_msdos"
    # Core functionality
    "normal" "boot" "linux" "configfile" "loopback" "chain" "halt" "reboot"
    # Search commands
    "search" "search_label" "search_fs_uuid" "search_fs_file"
    # User commands
    "ls" "echo" "test" "true"
    # Graphics
    "gfxmenu" "gfxterm" "gfxterm_background" "gfxterm_menu"
    "all_video" "videoinfo" "png"
    # Other
    "loadenv" "serial"
  ];

  # BIOS-specific modules
  biosModules = grubModules ++ [ "biosdisk" ];

  # EFI-specific modules  
  efiModules = grubModules ++ [ "efi_gop" "efifwsetup" ]
    ++ lib.optional (builtins.pathExists "${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget}/efi_uga.mod") "efi_uga";

  # Build the unified GRUB directory with both BIOS and EFI support
  grubDir = pkgs.runCommand "grub-unified-directory"
    {
      nativeBuildInputs = [ pkgs.buildPackages.grub2 pkgs.buildPackages.grub2_efi ];
      strictDeps = true;
    }
    ''
      mkdir -p $out/boot/grub/i386-pc
      mkdir -p $out/boot/grub/x86_64-efi
      mkdir -p $out/EFI/BOOT

      # Create marker file for GRUB to find the ISO filesystem
      touch $out/boot/grub/nixos-iso-marker

      # Copy the unified grub.cfg
      cp ${grubCfg} $out/boot/grub/grub.cfg

      # Copy unicode font
      cp ${grubPkgs.grub2}/share/grub/unicode.pf2 $out/boot/grub/

      # Copy theme if configured
      ${lib.optionalString (config.isoImage.grubTheme != null) ''
        mkdir -p $out/boot/grub/theme
        cp -r ${config.isoImage.grubTheme}/* $out/boot/grub/theme/
      ''}

      # Copy background image
      ${lib.optionalString (config.isoImage.efiSplashImage != null) ''
        cp ${config.isoImage.efiSplashImage} $out/boot/grub/background.png
      ''}

      echo "Building GRUB BIOS image (i386-pc)..."
      echo "Modules: ${toString biosModules}"

      # Build BIOS core.img
      grub-mkimage \
        --directory=${pkgs.grub2}/lib/grub/i386-pc \
        --prefix=/boot/grub \
        --output=$out/boot/grub/i386-pc/core.img \
        --format=i386-pc \
        --compression=auto \
        ${toString biosModules}

      # Concatenate cdboot.img + core.img for El Torito BIOS boot
      cat ${pkgs.grub2}/lib/grub/i386-pc/cdboot.img \
          $out/boot/grub/i386-pc/core.img \
          > $out/boot/grub/eltorito.img

      # Copy boot_hybrid.img for USB hybrid MBR boot
      cp ${pkgs.grub2}/lib/grub/i386-pc/boot_hybrid.img $out/boot/grub/

      # Copy BIOS modules for runtime loading
      cp ${pkgs.grub2}/lib/grub/i386-pc/*.mod $out/boot/grub/i386-pc/
      cp ${pkgs.grub2}/lib/grub/i386-pc/*.lst $out/boot/grub/i386-pc/ 2>/dev/null || true

      echo "Building GRUB EFI image (${grubPkgs.grub2_efi.grubTarget})..."
      echo "Modules: ${toString efiModules}"

      # Build EFI image
      grub-mkimage \
        --directory=${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget} \
        --prefix=/boot/grub \
        --output=$out/EFI/BOOT/BOOT${lib.toUpper targetArch}.EFI \
        --format=${grubPkgs.grub2_efi.grubTarget} \
        ${toString efiModules}

      # Copy EFI modules for runtime loading
      cp ${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget}/*.mod $out/boot/grub/x86_64-efi/
      cp ${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget}/*.lst $out/boot/grub/x86_64-efi/ 2>/dev/null || true

      # Also copy grub.cfg to EFI directory (some firmwares look there)
      cp ${grubCfg} $out/EFI/BOOT/grub.cfg

      echo "GRUB unified directory created successfully"
      echo "BIOS boot image: $out/boot/grub/eltorito.img"
      echo "EFI boot image: $out/EFI/BOOT/BOOT${lib.toUpper targetArch}.EFI"
    '';

  # EFI boot image (FAT filesystem image for El Torito)
  efiImg = pkgs.runCommand "efi-image_eltorito"
    {
      nativeBuildInputs = [
        pkgs.buildPackages.mtools
        pkgs.buildPackages.libfaketime
        pkgs.buildPackages.dosfstools
      ];
      strictDeps = true;
    }
    ''
      mkdir ./contents && cd ./contents
      mkdir -p ./EFI/BOOT

      # Copy EFI bootloader and config
      cp "${grubDir}"/EFI/BOOT/* ./EFI/BOOT/

      # Rewrite dates for reproducibility
      find . -exec touch --date=2000-01-01 {} +

      # Calculate image size
      usage_size=$(( $(du -s --block-size=1M --apparent-size . | tr -cd '[:digit:]') * 1024 * 1024 ))
      image_size=$(( ($usage_size * 110) / 100 ))
      block_size=$((1024*1024))
      image_size=$(( ($image_size / $block_size + 1) * $block_size ))
      # Minimum 2MB for FAT
      if [ $image_size -lt 2097152 ]; then
        image_size=2097152
      fi
      echo "EFI image size: $image_size bytes"

      truncate --size=$image_size "$out"
      mkfs.vfat --invariant -i 12345678 -n EFIBOOT "$out"

      # Copy files to FAT image
      for d in $(find EFI -type d | sort); do
        faketime "2000-01-01 00:00:00" mmd -i "$out" "::/$d"
      done
      for f in $(find EFI -type f | sort); do
        mcopy -pvm -i "$out" "$f" "::/$f"
      done

      fsck.vfat -vn "$out"
    '';

in
{
  options.isoImage.useUnifiedGrub = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Use unified GRUB2 bootloader for both BIOS and EFI boot instead of
      syslinux for BIOS and GRUB for EFI.
    '';
  };

  config = lib.mkIf config.isoImage.useUnifiedGrub {
    # Override the default iso-image contents to use GRUB instead of syslinux
    isoImage.contents = lib.mkForce (
      let
        cfgFiles = cfg:
          lib.optionals cfg.isoImage.showConfiguration [
            {
              source = cfg.boot.kernelPackages.kernel + "/" + cfg.system.boot.loader.kernelFile;
              target = "/boot/" + cfg.boot.kernelPackages.kernel + "/" + cfg.system.boot.loader.kernelFile;
            }
            {
              source = cfg.system.build.initialRamdisk + "/" + cfg.system.boot.loader.initrdFile;
              target = "/boot/" + cfg.system.build.initialRamdisk + "/" + cfg.system.boot.loader.initrdFile;
            }
          ]
          ++ lib.concatLists (
            lib.mapAttrsToList (_: { configuration, ... }: cfgFiles configuration) cfg.specialisation
          );
      in
      [
        { source = pkgs.writeText "version" config.system.nixos.label; target = "/version.txt"; }
      ]
      ++ lib.unique (cfgFiles config)
      # GRUB unified boot files
      ++ [
        { source = "${grubDir}/boot/grub"; target = "/boot/grub"; }
        { source = "${grubDir}/EFI"; target = "/EFI"; }
        { source = efiImg; target = "/boot/efi.img"; }
      ]
      # Loopback config for booting from other GRUB instances
      ++ lib.optionals (!config.boot.initrd.systemd.enable) [
        {
          source = (pkgs.writeTextDir "grub/loopback.cfg" "source /boot/grub/grub.cfg") + "/grub";
          target = "/boot/grub-loopback";
        }
      ]
    );

    # Override the ISO build to use GRUB for BIOS boot
    system.build.isoImage = lib.mkForce (
      pkgs.callPackage "${pkgs.path}/nixos/lib/make-iso9660-image.nix" {
        inherit (config.isoImage) compressImage volumeID;
        contents = config.isoImage.contents;
        isoName = "${config.image.baseName}.iso";

        # BIOS boot via GRUB El Torito image
        bootable = config.isoImage.makeBiosBootable;
        bootImage = "/boot/grub/eltorito.img";

        # We don't need syslinux anymore
        syslinux = null;

        # USB hybrid boot via GRUB's boot_hybrid.img
        usbBootable = config.isoImage.makeUsbBootable && config.isoImage.makeBiosBootable;
        isohybridMbrImage = "${grubDir}/boot/grub/boot_hybrid.img";

        # EFI boot
        efiBootable = config.isoImage.makeEfiBootable;
        efiBootImage = "boot/efi.img";

        # Squashfs for the Nix store
        squashfsContents = config.isoImage.storeContents;
        squashfsCompression = config.isoImage.squashfsCompression;
      }
    );

  };
}
