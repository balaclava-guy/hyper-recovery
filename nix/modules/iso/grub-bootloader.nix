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
  grubTimeout = if config.boot.loader.timeout == null then -1 else config.boot.loader.timeout;
  targetArch = if config.boot.loader.grub.forcei686 then "ia32" else pkgs.stdenv.hostPlatform.efiArch;
  grubPkgs = if config.boot.loader.grub.forcei686 then pkgs.pkgsi686Linux else pkgs;

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

  menuBuilderGrub2 = { name, class, image, params, initrd }: ''
    menuentry '${name}' --class ${class} {
      linux ${image} ''${isoboot} ${params}
      initrd ${initrd}
    }
  '';

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

  grubMenuCfg = ''
    set textmode=${lib.boolToString (config.isoImage.forceTextMode)}

    search --set=root --file /boot/grub/nixos-iso-marker

    insmod all_video
    insmod gfxterm
    insmod png
    set gfxpayload=keep
    set gfxmode=${lib.concatStringsSep "," [
      "1920x1200" "1920x1080" "1366x768" "1280x800" "1280x720"
      "1200x1920" "1024x768" "800x1280" "800x600" "auto"
    ]}

    if [ "$textmode" == "false" ]; then
      terminal_output gfxterm
      terminal_input  console
    else
      terminal_output console
      terminal_input  console
      set menu_color_normal=cyan/blue
      set menu_color_highlight=white/blue
    fi

    ${if config.isoImage.grubTheme != null then ''
      set theme=($root)/boot/grub/theme/theme.txt
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

  grubCfg = pkgs.writeText "grub.cfg" ''
    set timeout=${toString grubTimeout}

    clear
    echo ""
    echo "Loading boot menu..."
    echo ""
    echo "Press 't' for text mode, 'c' for command line..."
    echo ""

    ${grubMenuCfg}

    if [ ''${iso_path} ] ; then
      set isoboot="findiso=''${iso_path}"
    fi

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

  grubModules = [
    "fat" "iso9660" "udf" "part_gpt" "part_msdos"
    "normal" "boot" "linux" "configfile" "loopback" "chain" "halt" "reboot"
    "search" "search_label" "search_fs_uuid" "search_fs_file"
    "ls" "echo" "test" "true"
    "gfxmenu" "gfxterm" "gfxterm_background" "gfxterm_menu"
    "all_video" "videoinfo" "png"
    "loadenv" "serial"
  ];

  biosModules = grubModules ++ [ "biosdisk" ];
  efiModules = grubModules ++ [ "efi_gop" "efifwsetup" ]
    ++ lib.optional (builtins.pathExists "${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget}/efi_uga.mod") "efi_uga";

  grubDir = pkgs.runCommand "grub-unified-directory"
    {
      nativeBuildInputs = [ pkgs.buildPackages.grub2 pkgs.buildPackages.grub2_efi ];
      strictDeps = true;
    }
    ''
      mkdir -p $out/boot/grub/i386-pc $out/boot/grub/x86_64-efi $out/EFI/BOOT

      touch $out/boot/grub/nixos-iso-marker
      cp ${grubCfg} $out/boot/grub/grub.cfg
      cp ${grubPkgs.grub2}/share/grub/unicode.pf2 $out/boot/grub/

      ${lib.optionalString (config.isoImage.grubTheme != null) ''
        mkdir -p $out/boot/grub/theme
        cp -r ${config.isoImage.grubTheme}/* $out/boot/grub/theme/
      ''}

      ${lib.optionalString (config.isoImage.efiSplashImage != null) ''
        cp ${config.isoImage.efiSplashImage} $out/boot/grub/background.png
      ''}

      echo "Building GRUB BIOS image (i386-pc)..."
      grub-mkimage \
        --directory=${pkgs.grub2}/lib/grub/i386-pc \
        --prefix=/boot/grub \
        --output=$out/boot/grub/i386-pc/core.img \
        --format=i386-pc \
        --compression=auto \
        ${toString biosModules}

      cat ${pkgs.grub2}/lib/grub/i386-pc/cdboot.img \
          $out/boot/grub/i386-pc/core.img \
          > $out/boot/grub/eltorito.img

      cp ${pkgs.grub2}/lib/grub/i386-pc/boot_hybrid.img $out/boot/grub/
      cp ${pkgs.grub2}/lib/grub/i386-pc/*.mod $out/boot/grub/i386-pc/
      cp ${pkgs.grub2}/lib/grub/i386-pc/*.lst $out/boot/grub/i386-pc/ 2>/dev/null || true

      echo "Building GRUB EFI image (${grubPkgs.grub2_efi.grubTarget})..."
      grub-mkimage \
        --directory=${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget} \
        --prefix=/boot/grub \
        --output=$out/EFI/BOOT/BOOT${lib.toUpper targetArch}.EFI \
        --format=${grubPkgs.grub2_efi.grubTarget} \
        ${toString efiModules}

      cp ${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget}/*.mod $out/boot/grub/x86_64-efi/
      cp ${grubPkgs.grub2_efi}/lib/grub/${grubPkgs.grub2_efi.grubTarget}/*.lst $out/boot/grub/x86_64-efi/ 2>/dev/null || true
      cp ${grubCfg} $out/EFI/BOOT/grub.cfg
    '';

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
      cp "${grubDir}"/EFI/BOOT/* ./EFI/BOOT/
      find . -exec touch --date=2000-01-01 {} +

      usage_size=$(( $(du -s --block-size=1M --apparent-size . | tr -cd '[:digit:]') * 1024 * 1024 ))
      image_size=$(( ($usage_size * 110) / 100 ))
      block_size=$((1024*1024))
      image_size=$(( ($image_size / $block_size + 1) * $block_size ))
      if [ $image_size -lt 2097152 ]; then
        image_size=2097152
      fi

      truncate --size=$image_size "$out"
      mkfs.vfat --invariant -i 12345678 -n EFIBOOT "$out"

      for d in $(find EFI -type d | sort); do
        faketime "2000-01-01 00:00:00" mmd -i "$out" "::/$d"
      done
      for f in $(find EFI -type f | sort); do
        mcopy -pvm -i "$out" "$f" "::/$f"
      done

      fsck.vfat -vn "$out"
    '';

  # Inline the ISO builder script instead of external file
  makeGrubIsoImageScript = ''
    stripSlash() {
        res="$1"
        if test "''${res:0:1}" = /; then res=''${res:1}; fi
    }

    escapeEquals() {
        echo "$1" | sed -e 's/\\/\\\\/g' -e 's/=/\\=/g'
    }

    addPath() {
        target="$1"
        source="$2"
        echo "$(escapeEquals "$target")=$(escapeEquals "$source")" >> pathlist
    }

    stripSlash "$bootImage"; bootImage="$res"

    if test -n "$bootable"; then
        for ((i = 0; i < ''${#targets[@]}; i++)); do
            stripSlash "''${targets[$i]}"
            if test "$res" = "$bootImage"; then
                echo "copying the boot image ''${sources[$i]}"
                cp "''${sources[$i]}" boot.img
                chmod u+w boot.img
                sources[$i]=boot.img
            fi
        done

        isoBootFlags="-eltorito-boot ''${bootImage}
                      -eltorito-catalog .boot.cat
                      -no-emul-boot -boot-load-size 4 -boot-info-table
                      --sort-weight 1 /boot/grub"
    fi

    if test -n "$usbBootable"; then
        usbBootFlags="-isohybrid-mbr ''${isohybridMbrImage}"
    fi

    if test -n "$efiBootable"; then
        efiBootFlags="-eltorito-alt-boot
                      -e $efiBootImage
                      -no-emul-boot
                      -isohybrid-gpt-basdat"
    fi

    touch pathlist

    for ((i = 0; i < ''${#targets[@]}; i++)); do
        stripSlash "''${targets[$i]}"
        addPath "$res" "''${sources[$i]}"
    done

    for i in $(< $closureInfo/store-paths); do
        addPath "''${i:1}" "$i"
    done

    if [[ -n "$squashfsCommand" ]]; then
        (out="nix-store.squashfs" eval "$squashfsCommand")
        addPath "nix-store.squashfs" "nix-store.squashfs"
    fi

    if [[ ''${#objects[*]} != 0 ]]; then
        cp $closureInfo/registration nix-path-registration
        addPath "nix-path-registration" "nix-path-registration"
    fi

    for ((n = 0; n < ''${#objects[*]}; n++)); do
        object=''${objects[$n]}
        symlink=''${symlinks[$n]}
        if test "$symlink" != "none"; then
            mkdir -p $(dirname ./$symlink)
            ln -s $object ./$symlink
            addPath "$symlink" "./$symlink"
        fi
    done

    mkdir -p $out/iso

    xorriso="xorriso
     -boot_image any gpt_disk_guid=$(uuid -v 5 daed2280-b91e-42c0-aed6-82c825ca41f3 $out | tr -d -)
     -volume_date all_file_dates =$SOURCE_DATE_EPOCH
     -as mkisofs
     -iso-level 3
     -volid ''${volumeID}
     -appid nixos
     -publisher nixos
     -graft-points
     -full-iso9660-filenames
     -joliet
     ''${isoBootFlags}
     ''${usbBootFlags}
     ''${efiBootFlags}
     -r
     -path-list pathlist
     --sort-weight 0 /
    "

    $xorriso -output $out/iso/$isoName

    if test -n "$compressImage"; then
        echo "Compressing image..."
        zstd -T$NIX_BUILD_CORES --rm $out/iso/$isoName
    fi

    mkdir -p $out/nix-support
    echo $system > $out/nix-support/system

    if test -n "$compressImage"; then
        echo "file iso $out/iso/$isoName.zst" >> $out/nix-support/hydra-build-products
    else
        echo "file iso $out/iso/$isoName" >> $out/nix-support/hydra-build-products
    fi
  '';

in
{
  options.isoImage.useUnifiedGrub = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Use unified GRUB2 bootloader for both BIOS and EFI boot.";
  };

  config = lib.mkIf config.isoImage.useUnifiedGrub {
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
      ++ [
        { source = "${grubDir}/boot/grub"; target = "/boot/grub"; }
        { source = "${grubDir}/EFI"; target = "/EFI"; }
        { source = efiImg; target = "/boot/efi.img"; }
      ]
      ++ lib.optionals (!config.boot.initrd.systemd.enable) [
        {
          source = (pkgs.writeTextDir "grub/loopback.cfg" "source /boot/grub/grub.cfg") + "/grub";
          target = "/boot/grub-loopback";
        }
      ]
    );

    system.build.isoImage = lib.mkForce (
      let
        needSquashfs = config.isoImage.storeContents != [ ];
        makeSquashfsDrv = pkgs.callPackage "${pkgs.path}/nixos/lib/make-squashfs.nix" {
          storeContents = config.isoImage.storeContents;
          comp = config.isoImage.squashfsCompression;
        };
      in
      pkgs.stdenv.mkDerivation {
        name = "${config.image.baseName}.iso";
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;

        buildCommand = makeGrubIsoImageScript;
        
        nativeBuildInputs = [
          pkgs.xorriso
          pkgs.zstd
          pkgs.libossp_uuid
        ] ++ lib.optionals needSquashfs makeSquashfsDrv.nativeBuildInputs;

        isoName = "${config.image.baseName}.iso";
        inherit (config.isoImage) compressImage volumeID;

        bootable = config.isoImage.makeBiosBootable;
        bootImage = "/boot/grub/eltorito.img";

        usbBootable = config.isoImage.makeUsbBootable && config.isoImage.makeBiosBootable;
        isohybridMbrImage = "${grubDir}/boot/grub/boot_hybrid.img";

        efiBootable = config.isoImage.makeEfiBootable;
        efiBootImage = "boot/efi.img";

        sources = map (x: x.source) config.isoImage.contents;
        targets = map (x: x.target) config.isoImage.contents;

        objects = [];
        symlinks = [];

        squashfsCommand = lib.optionalString needSquashfs makeSquashfsDrv.buildCommand;
        closureInfo = pkgs.closureInfo { rootPaths = []; };
      }
    );
  };
}
