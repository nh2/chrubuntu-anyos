# Build with:
#     NIX_PATH=nixpkgs=$HOME/src/nixpkgs nix-build --no-link '<nixpkgs/nixos>' -A config.system.build.tarball -I nixos-config=thisfile.nix
# You can also use
#     -A config.system.build.toplevel
# to build something you can browse locally (that uses symlinks into your nix store).
# You can use
#     -A config.system.build.initialRamdisk
# to build directly the initrd if you want to iterate on that.

{config, pkgs, ...}:
let
  kernelImageFullPath =
    "${config.boot.kernelPackages.kernel}/" +
    "${config.system.boot.loader.kernelFile}";

  initrdFullPath =
    "${config.system.build.initialRamdisk}/initrd";

  # PlopKexec needs a static busybox build.
  plopkexec-busybox = pkgs.busybox.override { enableStatic = true; };

  # kexec
  # PlopKexec needs a static `kexec` build.
  # We offer 2 approaches below, one using glibc and one using musl.

  fix-kexectools-package = kexectools-package:
    let
      # Given a kexectools derivation, applies the backport fix to it if necessary:
      #     https://github.com/NixOS/nixpkgs/pull/60291
      # Delete that once the README of this project recommends a version
      # of nixpkgs >= 19.09.
      applyBuildFixBackport = kexectoolsDrv:
        if pkgs.lib.versionAtLeast config.system.stateVersion "19.09"
          then kexectoolsDrv
          else kexectoolsDrv.overrideAttrs (old: {
            depsBuildBuild = [ pkgs.buildPackages.stdenv.cc ];
            nativeBuildInputs = [];
          });
      # Delete this once patches are merged upstream and available in nixpkgs.
      applyBugfixes = kexectoolsDrv:
        kexectoolsDrv.overrideAttrs (old: {
          patches = (old.patches or []) ++ [
            # Fix kexec not reading and setting EFI variables when
            # /etc/mtab is absent (it's absent PlopKexec's initramfs).
            (pkgs.fetchpatch {
              url = "https://github.com/nh2/kexec-tools/commit/08981adb06ef90f1ebd6b262378ad0f8099632b8.patch";
              sha256 = "1hji2bkf9z6qqr6r41zq3dv8jc4138jrrbw94qg9iykvq31b88gm";
            })
            # Fix kexec not reading and setting EFI variables when
            # the sysfs mount is not named "sysfs" (PlopKexec names it "none").
            (pkgs.fetchpatch {
              url = "https://github.com/nh2/kexec-tools/commit/4a9547c96fbdbcab8032de07f429a92312994096.patch";
              sha256 = "0ww5ld9d1g3m6xrmhhhd8giz37731zm783zyjql0svsh52vw93ap";
            })
          ];
        });
    in
      applyBugfixes (applyBuildFixBackport kexectools-package);

  # Static `kexec` binary, overriding the normal dynamic (as of writing)
  # glibc based build.
  static-kexectools-glibc =
    (fix-kexectools-package pkgs.kexectools).override {
      stdenv = pkgs.stdenvAdapters.makeStaticBinaries pkgs.stdenv;
    };

  # Static `kexec` binary using `pkgsStatic` (this uses musl).
  static-kexectools-musl = fix-kexectools-package pkgs.pkgsStatic.kexectools;

  # We default to the musl build because the resulting kexec binary
  # is much smaller (300 KB vs 1 MB at time of writing).
  static-kexectools =
    static-kexectools-musl;
    # static-kexectools-glibc;

  # Linux kernel that boots directly on the Chromebook.
  # Useful for testing various Linux config options quickly
  # (though building incrementally with `make` in a kernel source
  # is still much faster).
  linux_custom = pkgs.linuxManualConfig {
    inherit (pkgs) stdenv;
    # The same kernel versions as in plopkexec-linux-image work here.
    inherit (pkgs.linux_4_14) src version;
    allowImportFromDerivation = true;
    configfile =
      let
        # Almost upstream; I've added KEXEC and some console settings
        # so that kernel messages are printed on boot for debugging.
        upstreamConfigFile = ./chromebook-kernel-configs/chromebook-config-release-R58-9334.B-6e05ef7-alex.config;
        # For testing:
        # upstreamConfigFile = "${pkgs.plopkexec.kernelconfig}/config";

        # What to append to the kernel `upstreamConfigFile`:
        # Things that NixOS requires in addition in order to build/run.
        # `kernelPatches` doesn't seem to work here for unknown reason.
        # The format is the normal kernel format, like `CONFIG_BLA=y`.
        appendConfigFile = pkgs.writeText "kernel-append-config" ''
        '';
      in
        pkgs.runCommand "kernel-config" {} (''
          cat ${upstreamConfigFile} ${appendConfigFile} > $out
        ''
        # When using the PlopKexec kernel config, this is needed
        # to use it as a normal kernel, otherwise it cannot compile
        # because no `initramfs/` dir is present.
        # + ''
        #   substituteInPlace "$out" --replace \
        #     'CONFIG_INITRAMFS_SOURCE="initramfs/"' \
        #     'CONFIG_INITRAMFS_SOURCE=""'
        # ''
        );
  };

in
{
  # We need no bootloader, because the Chromebook can't use that anyway.
  boot.loader.grub = {
    enable = true;
    # From docs: The special value `nodev` means that a GRUB boot menu
    # will be generated, but GRUB itself will not actually be installed.
    device = "nodev";
  };

  fileSystems = {
    # Mounts whatever device has the NIXOS_ROOT label on it as /
    # (but it's only really there to make systemd happy, so it wont try to remount stuff).
    # "/".label = "NIXOS_ROOT";
    # "/".label = "ROOT-A";
    "/".label = "NIXOS_ROOT_SD"; # TODO important comment about double lables
    # TODO: Mention busybox FEATURE* problem (TODO: This is wrong, comment about it that it's irrelevant for busybox because another option controls that)
    "/".noCheck = true;
  };

  # Trim locales a lot to save disk space (but sacrifice translations).
  # Unfortunately currently only gets rid of the large `glibc-locales`
  # package (120 MB as of writing);
  # the individual packages still have all their big `.mo` files.
  i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

  # Note that as of writing, PlopKexec (1.4.1) does not support
  # entries with variables
  # (see its `scan_grub2.cpp`, `ScanGrub2::ScanConfigFile`).
  # That also means we couldn't use GRUB2's `search` directive,
  # if we wanted to, or something like `set root=(hd1,gpt3)`.
  # But we don't need to, because in PlopKexec the partition is
  # chosen upfront in its menu, and all paths that PlopKexec parses
  # out of GRUB config files are interpreted as being on that partition.
  system.build.initial-grub-config = pkgs.writeText "initial-grub.cfg" ''
    menuentry "NixOS" {
      linux ${kernelImageFullPath} init=${config.system.build.toplevel}/init
      initrd ${initrdFullPath}
    }
  '';

  system.build.tarball = pkgs.callPackage <nixpkgs/nixos/lib/make-system-tarball.nix> {
    storeContents = [
      {
        symlink = "/bin/init";
        object = "${config.system.build.toplevel}/init";
      }
      {
        symlink = "/bin/initrd";
        object = "${config.system.build.toplevel}/initrd";
      }
      {
        symlink = "/bin/kernel";
        object = "${config.system.build.toplevel}/kernel";
      }
    ];
    contents = [
      # grub.cfg must not be a symlink for PlopKexec to load it.
      {
        target = "/boot/grub/grub.cfg";
        source = config.system.build.initial-grub-config;
      }
    ];
    # Disable compression, as we want to immediately unpack it
    # onto a device.
    compressCommand = "cat";
    compressionExtension = "";
  };

  nixpkgs.overlays = [
    (self: super: {
      # Add package to create EFI boot stub
      chromiumos-efi-bootstub = super.callPackage ./chromiumos-efi-bootstub.nix {};

      plopkexec = super.callPackage ./plopkexec.nix { mountDevtmpfs = true; };

      plopkexec-linux-image = super.linuxManualConfig {
        # Select which kernel to use.
        # Using an older kernel is no problem with PlopKexec, because
        # it's only used as a bootloader and disappears from memory
        # as soon as it calls `kexec.

        # inherit (super.linux_4_4) src version; # works
        # inherit (super.linux_4_9) src version; # does not work, hangs at black screen (power button immediately turns off)
        inherit (super.linux_4_14) src version; # works
        # inherit (super.linux_4_19) src version; # does not work, immediately reboots
        # inherit (super.linux_5_0) src version; # does not work, immediately reboots

        inherit (super) stdenv;
        allowImportFromDerivation = true;
        configfile =
          let
            # Use ChromiumOS's kernel config instead of the one provided
            # by PlopKexec, for maximum hardware compatibility.
            upstreamConfigFile =
              # "${self.plopkexec.kernelconfig}/config";
              ./chromebook-kernel-configs/chromebook-config-release-R58-9334.B-6e05ef7-alex.config;

            # PlopKexec upstream and eugenesan's fork both use a tarball
            # containing device files to pre-populate `/dev`.
            # That is rather ugly, because making device files (`mknod`)
            # or unpacking them from an archive requires root, which is not
            # nice for building things (requires fakeroot or building as root).
            # We take a different approach:
            # * We use the kernel's functionality to create device files using
            #   a text description as described in the CONFIG_INITRAMFS_SOURCE
            #   documentation.
            # * We patched PlopKexec to do the equivalent of
            #   `mount -t devtmpfs devtmpfs /dev` next to its usual mounts of
            #   `/proc` and `/sys`.
            #   That makes Linux populate `/dev` automatically.
            #
            # Creating `/dev/console` manually is still needed, otherwise
            # PlopKexec's UI is invisible (it still boots its default action
            # after the timeout and you can see that in the dmesg output).
            initramfs-description = self.writeText "plopkexec-initramfs-description" ''
              dir /dev 755 0 0
              nod /dev/console 644 0 0 c 5 1
              dir /bin 755 1000 1000
              dir /proc 755 0 0
              dir /sys 755 0 0
              dir /mnt 755 0 0
              file /init ${self.plopkexec}/init 755 0 0
              file /kexec ${static-kexectools}/bin/kexec 755 0 0
            '';

            initramfs-source = "${initramfs-description} ${plopkexec-busybox}";
          in
            # See https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
            # for a description how `CONFIG_INITRAMFS_SOURCE` works, and an
            # explanation of the `initramfs-description` format.
            pkgs.runCommand "kernel-config" {} ''
              cat ${upstreamConfigFile} > $out

              # Ensure fields to override are present as expected
              grep --extended-regexp '^CONFIG_INITRAMFS_SOURCE=' "$out"

              sed --in-place --regexp-extended \
                's:^CONFIG_INITRAMFS_SOURCE=.*$:CONFIG_INITRAMFS_SOURCE="${initramfs-source}":g' \
                "$out"
            '';
      };

    })
  ];

  # Select the kernel that we've overridden with custom config above.
  # boot.kernelPackages = pkgs.linuxPackages_4_4;
  # boot.kernelPackages = pkgs.linuxPackages_4_9; # doesn't work (no modeflash) (but fine when kexec'd)
  # boot.kernelPackages = pkgs.linuxPackages_4_14;
  boot.kernelPackages = pkgs.linuxPackages; # 4.19 doesn't boot directly (but fine when kexec'd)

  # The custom kernel config currently doesn't allow the firewall;
  # getting this when it's on:
  #     This kernel does not support rpfilter
  networking.firewall.enable = false;

  # A ChromeOS kernel is a normal `vmlinux` bzImage with some extra
  # signatures created by the `vbutil_kernel` tool.
  # It also include the kernel command line parameters.
  system.build.signed-chromiumos-kernel =
    let
      # Build Chrome OS bootstub that handles the handoff from the custom BIOS to the kernel.
      bootstub = "${pkgs.chromiumos-efi-bootstub}/bootstub.efi";
      # TODO mention kernel regression commit 9479c7cebf
      #      https://bugzilla.kernel.org/show_bug.cgi?id=197895
      # kernelPath = kernelImageFullPath;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.9.170-ubuntubuild;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-upstream-bisection;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-kexec-loader-upstreamkernel-v4.4;
      # kernelPath = ./stock-4.7.1-plopkexec; # from https://github.com/eugenesan/chrubuntu-script/tree/3247b0d4aefc9e75bee7b41eb4cb191e4a1f0852/images
      # kernelPath = /home/niklas/src/plopkexec/plopkexec-1.4.1/build/plopkexec;
      kernelPath = "${pkgs.plopkexec-linux-image}/bzImage";
      # kernelPath = "${linux_custom}/bzImage";
      # kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
      #   console=tty0
      #   init=/bin/init
      #   initrd=/bin/initrd
      #   cros_efi
      #   oops=panic
      #   panic=0
      #   root=PARTUUID=%U/PARTNROFF=1
      #   rootwait
      #   ro
      #   cros_debug
      #   kern_guid=%U
      #   add_efi_memmap
      #   boot=local
      #   noresume
      #   noswap
      #   i915.modeset=1
      #   nmi_watchdog=panic,lapic
      #   nosplash
      # '';
      # kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
      #   initrd=/bin/initrd
      #   cros_efi
      #   oops=panic
      #   panic=0
      #   root=PARTUUID=%U/PARTNROFF=1
      #   rootwait
      #   ro
      #   add_efi_memmap
      #   i915.modeset=1
      # '';

      # Minimal working command line arguments.
      kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
        initrd=/bin/initrd
        root=PARTUUID=%U/PARTNROFF=1
        rootwait
        add_efi_memmap
      '';

      # kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
      #   cros_efi
      #   oops=panic
      #   panic=0
      #   add_efi_memmap
      #   boot_delay=500
      #   rootdelay=5
      #   rdinit=/init
      #   i915.modeset=1
      # '';
    in
      pkgs.runCommand "signed-chromiumos-kernel" {} ''
        ${pkgs.vboot_reference}/bin/vbutil_kernel \
          --pack $out \
          --version 1 \
          --keyblock ${pkgs.vboot_reference}/share/vboot/devkeys/kernel.keyblock \
          --signprivate ${pkgs.vboot_reference}/share/vboot/devkeys/kernel_data_key.vbprivk \
          --bootloader ${bootstub} \
          --vmlinuz ${kernelPath} \
          --config ${kernelCommandLineParametersFile}
      '';

  # For convenience if people want to build only the bootstub
  # using `-A config.system.build.bootstub`.
  system.build.bootstub = pkgs.chromiumos-efi-bootstub;

  system.build.plopkexec = pkgs.plopkexec;
  system.build.plopkexec-image = pkgs.plopkexec-linux-image;
  system.build.plopkexec-busybox = plopkexec-busybox;
  system.build.static-kexectools = static-kexectools;

  # From ChrUbuntu's `tynga` script and
  #   * https://github.com/keithzg/chrubuntu-script/blob/cae7ea8c956a9e49d3dc619bf6c3b0b04cd5f7a8/chrubuntu-install.sh#L44
  #   * https://gist.github.com/bodil/b14a398189e5643ee03e#partitioning-your-internal-drive
  #   * http://www.chromium.org/chromium-os/chromiumos-design-docs/disk-format#TOC-GUID-Partition-Table-GPT-
  # Adapted to pin all programs to nixpkgs versions for full reproducibility.
  system.build.chromebook-removable-media-partitioning-script =
    pkgs.writeScript "chromebook-removable-media-partitioning-script" ''
      #!${pkgs.bash}/bin/bash
      set -eu -o pipefail

      if [ -z "''${1+x}" ]; then
        >&2 echo 'Missing device path argument'
        exit 1
      fi

      target_disk="$1"

      echo "Got $target_disk as target drive"
      echo ""
      echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
      echo ""
      read -p "Press [Enter] to continue on $target_disk or CTRL+C to quit: "

      ext_size=$(${pkgs.libuuid}/bin/blockdev --getsz "$target_disk")
      aroot_size=$((ext_size - 65600 - 33))

      ${pkgs.parted}/bin/parted --script "$target_disk" "mktable gpt"
      ${pkgs.vboot_reference}/bin/cgpt create "$target_disk"
      ${pkgs.vboot_reference}/bin/cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" "$target_disk"
      ${pkgs.vboot_reference}/bin/cgpt add -i 7 -b 65600 -s "$aroot_size" -l ROOT-A -t "rootfs" "$target_disk"
      sync
      ${pkgs.libuuid}/bin/blockdev --rereadpt "$target_disk"
      ${pkgs.parted}/bin/partprobe "$target_disk"

      if [[ "$target_disk" =~ "mmcblk" ]]
      then
        target_rootfs="''${target_disk}p7"
        target_kern="''${target_disk}p6"
      else
        target_rootfs="''${target_disk}7"
        target_kern="''${target_disk}6"
      fi

      echo "Target Kernel  Partition: $target_kern"
      echo "Target Root FS Partition: $target_rootfs"

      if ${pkgs.utillinux}/bin/mount | grep "$target_rootfs"
      then
        echo >&2 "Refusing to create file system since $target_rootfs is formatted and mounted"
        exit 1
      fi

      ${pkgs.e2fsprogs.bin}/bin/mkfs.ext4 "$target_rootfs"
    '';

  # Install new init script; this ensures that /init is updated after every
  # `nixos-rebuild` run on the machine (the kernel can run init from a
  # symlink).
  system.activationScripts.installInitScript = ''
    ln -fs $systemConfig/init /bin/init
    ln -fs $systemConfig/initrd /bin/initrd
  '';

  boot.postBootCommands =
    # Import Nix DB, so that nix commands work and know what's installed.
    # The `rm` ensures it's done only once; `/nix-path-registration`
    # is a file created in the tarball by `make-system-tarball.nix`.
    ''
      if [ -f /nix-path-registration ]; then
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration && rm /nix-path-registration
      fi
    ''
    +
    # Create the system profile to make nixos-rebuild happy
    ''
      ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
    '';

  # Configuration of the contents of the NixOS system below:

  # Empty root password so people can easily use the live image.
  # Note that changing this requires *wiping* the root file system
  # (or at least /etc/shadow?) on the SD card because
  # the password `/etc/shadow` is created from this only *once*;
  # see <nixos/modules/config/update-users-groups.pl>.
  users.users.root.password = "";

  # Disable DHCP so that the boot doesn't hang for it.
  networking.dhcpcd.enable = false;

  # When testing without networking
  services.timesyncd.enable = false;

  # Turn on nginx as an example
  # services.nginx.enable = true;

  environment.systemPackages = [
    pkgs.beep
    pkgs.dhcpcd
    pkgs.vim
    pkgs.usbutils # lsusb
    pkgs.pciutils # lspci
    pkgs.utillinux # lsblk
    pkgs.file # the `file` utility
    # Custom name `kexec-static` four our static kexec build
    # so that it can be conveniently tested from NixOS.
    (pkgs.runCommand "kexec-static" {} ''
      mkdir -p $out/bin
      ln -s ${static-kexectools}/bin/kexec $out/bin/kexec-static
    '')
  ];

  # networking.interfaces."enp0s29f7u1".ipv4.addresses = [
  #   { address = "192.168.2.4"; prefixLength = 24; }
  # ];
  # networking.defaultGateway = {
  #   address = "192.168.2.1"; interface = "enp0s29f7u1";
  # };
  # networking.nameservers = [ "8.8.8.8" ];

  # # Enable the OpenSSH server.
  # services.sshd.enable = true;
  # services.openssh.permitRootLogin = "yes";

  # TODO comment on busybox problem, get rid of equivalent in `fileSystems`
  boot.initrd.checkJournalingFS = false;

  boot.initrd.availableKernelModules = [
    # "uhci_hcd"
    # "ehci_pci" # detected on NixOS kernel with a few `y`s inserted by me, so `lsmod` shows a lot
    # "ahci"
    "ums_realtek"

    # "intel-agp"
    # "intel_agp" # TODO check whether this makes a difference
    "i915"

    # "ext2"
    # "ext4"

    # # Taken from working lsmod (TODO more comments)
    # "chromeos_pstore"
    # "chromeos_laptop"
    # "efi_pstore"
    # "serio_raw"
    # "uas"
    # "i2c_i801"
    # "lpc_ich"
    # "efivarfs"
    # "sd_mod"
    # "vfio_mdev"
    # "kvmgt"

    # # Googled for "linux sdcard module"
    # "sdhci"
    # "sdhci_pci"
    # "mmc_core"
    # "mmc_block"

    # # Found via long bisection that the SD card needs this because the reader is connected via USB
    # "ehci_hcd"

    # # Keyboard
    # "atkbd"
    # "cros_ec_keyb"
  ];
  boot.initrd.kernelModules = [
    "i8042" # this makes keyboard and touchpad work
  ];
  boot.initrd.supportedFilesystems = [
    "ext2"
    "ext4"
  ];
}
