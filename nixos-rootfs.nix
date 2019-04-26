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

      plopkexec = super.callPackage ./plopkexec.nix {};

      plopkexec-image-linux_4_4 = super.linuxManualConfig {
        inherit (super) stdenv;
        inherit (super.linux_4_4) src version;
        configfile =
          let
            # upstreamConfigFile = "${self.plopkexec.kernelconfig}/config";
            upstreamConfigFile = self.fetchurl {
              url = https://raw.githubusercontent.com/eugenesan/chrubuntu-script/3247b0d4aefc9e75bee7b41eb4cb191e4a1f0852/images/stock-4.7.1-plopkexec.config;
              sha256 = "1v5k3dshgshix6jjdw60xgjj5l9rqi8sidif8dmnkgb7zkslfi1d";
            };

            initramfs-description = self.writeText "plopkexec-initramfs-description" ''
              dir /dev 755 0 0
              nod /dev/console 644 0 0 c 5 1
              nod /dev/kmsg 644 0 0 c 1 11
              nod /dev/tty0 644 0 0 c 4 0
              nod /dev/loop0 644 0 0 b 7 0
              nod /dev/sda 660 0 0 b 8 0
              nod /dev/sda1 660 0 0 b 8 1
              nod /dev/sda2 660 0 0 b 8 2
              nod /dev/sda3 660 0 0 b 8 3
              nod /dev/sda4 660 0 0 b 8 4
              nod /dev/sdb 660 0 0 b 8 16
              nod /dev/sdb1 660 0 0 b 8 17
              nod /dev/sdb2 660 0 0 b 8 18
              nod /dev/sdb3 660 0 0 b 8 19
              nod /dev/sdb4 660 0 0 b 8 20
              dir /bin 755 1000 1000
              dir /proc 755 0 0
              dir /sys 755 0 0
              dir /mnt 755 0 0
              file /init ${self.plopkexec}/init 755 0 0
            '';
          in
            # TODO Add static kexec binary to CONFIG_INITRAMFS_SOURCE

            # See https://www.kernel.org/doc/Documentation/filesystems/ramfs-rootfs-initramfs.txt
            # for a description how `CONFIG_INITRAMFS_SOURCE` works, and an
            # explanation of the `initramfs-description` format.
            pkgs.runCommand "kernel-config" {} ''
              cat ${upstreamConfigFile} > $out
              substituteInPlace "$out" --replace \
                'CONFIG_INITRAMFS_SOURCE="initramfs/"' \
                'CONFIG_INITRAMFS_SOURCE="${initramfs-description} ${plopkexec-busybox}"'
            '';
              # substituteInPlace "$out" --replace \
              #   '# CONFIG_64BIT is not set' \
              #   'CONFIG_64BIT=y'

              # substituteInPlace "$out" --replace \
              #   'CONFIG_X86_32=y' \
              #   'CONFIG_X86_32=n'

              # substituteInPlace "$out" --replace \
              #   'CONFIG_DRM_I915=m' \
              #   'CONFIG_DRM_I915=y'

              # substituteInPlace "$out" --replace \
              #   'CONFIG_AGP_INTEL=m' \
              #   'CONFIG_AGP_INTEL=y'
        allowImportFromDerivation = true;
      };

    })
  ];

  # Select the kernel that we've overridden with custom config above.
  # boot.kernelPackages = pkgs.linuxPackages_4_4;
  # boot.kernelPackages = pkgs.linuxPackages_4_9; # doesn't work (no modeflash) (but fine when kexec'd)
  # boot.kernelPackages = pkgs.linuxPackages_4_14;
  boot.kernelPackages = pkgs.linuxPackages; # 4.19 doens't boot directly (but fine when kexec'd)

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
      # kernelPath = ./stock-4.7.1-plopkexec; # from https://github.com/eugenesan/chrubuntu-script/tree/3247b0d4aefc9e75bee7b41eb4cb191e4a1f0852/images
      # kernelPath = /home/niklas/src/plopkexec/plopkexec-1.4.1/build/plopkexec;
      kernelPath = "${pkgs.plopkexec-image-linux_4_4}/bzImage";
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
      kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
        initrd=/bin/initrd
        cros_efi
        oops=panic
        panic=0
        root=PARTUUID=%U/PARTNROFF=1
        rootwait
        ro
        add_efi_memmap
        i915.modeset=1
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
  system.build.plopkexec-image = pkgs.plopkexec-image-linux_4_4;
  system.build.plopkexec-busybox = plopkexec-busybox;

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
