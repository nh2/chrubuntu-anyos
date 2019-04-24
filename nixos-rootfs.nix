# Build with:
#     NIX_PATH=nixpkgs=$HOME/src/nixpkgs nix-build --no-link '<nixpkgs/nixos>' -A config.system.build.tarball -I nixos-config=thisfile.nix
# You can also use
#     -A config.system.build.toplevel
# to build something you can browse locally (that uses symlinks into your nix store).

{config, pkgs, ...}:
let
  kernelImageFullPath =
    "${config.boot.kernelPackages.kernel}/" +
    "${config.system.boot.loader.kernelFile}";

  initrdFullPath =
    "${config.system.build.initialRamdisk}/initrd";
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

  system.build.initial-grub-config = pkgs.writeText "initial-grub.cfg" ''
    menuentry "NixOS" {
      set root=(hd1,gpt3)
      linux ${kernelImageFullPath}
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
    })
  ];

  # Select the kernel that we've overridden with custom config above.
  boot.kernelPackages = pkgs.linuxPackages_4_4;
  # boot.kernelPackages = pkgs.linuxPackages_4_9; # doesn't work (no modeflash) (but fine when kexec'd)
  # boot.kernelPackages = pkgs.linuxPackages_4_14;
  # boot.kernelPackages = pkgs.linuxPackages; # 4.19 doens't boot directly (but fine when kexec'd)

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
      kernelPath = ./stock-4.7.1-plopkexec; # from https://github.com/eugenesan/chrubuntu-script/tree/3247b0d4aefc9e75bee7b41eb4cb191e4a1f0852/images
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
  system.build.unsigned-chromiumos-kernel = config.boot.kernelPackages.kernel;
  system.build.nixos-kernel = (import <nixpkgs> {}).linux_4_4;

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

  boot.kernelPatches = [ {
    name = "chromiumos-inspired";
    patch = null;
    # TODO Comment and explain other possible workarounds (special "kexec bootloader kernel" or vmlinux-patching)
    extraConfig = ''
      AGP y
      BLK_DEV_SD y
      DRM y
      DRM_I915 y
      EXT4_FS y
      KEYBOARD_ATKBD y
      SCSI y
      USB y
      USB_EHCI_HCD y
      USB_STORAGE y
      USB_STORAGE_REALTEK y
    '';

  } ];

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

  # boot.initrd.availableKernelModules = [
  boot.initrd.kernelModules = [
    "uhci_hcd"
    "ehci_pci" # detected on NixOS kernel with a few `y`s inserted by me, so `lsmod` shows a lot
    "ahci"
    "ums_realtek"

    # "intel-agp"
    "intel_agp" # TODO check whether this makes a difference
    "i915"

    "ext2"
    "ext4"

    # Taken from working lsmod (TODO more comments)
    "chromeos_pstore"
    "chromeos_laptop"
    "efi_pstore"
    "serio_raw"
    "uas"
    "i2c_i801"
    "lpc_ich"
    "efivarfs"
    "sd_mod"
    "vfio_mdev"
    "kvmgt"

    # Googled for "linux sdcard module"
    "sdhci"
    "sdhci_pci"
    "mmc_core"
    "mmc_block"

    # Found via long bisection that the SD card needs this because the reader is connected via USB
    "ehci_hcd"
  ];
  boot.initrd.supportedFilesystems = [
    "ext2"
    "ext4"
  ];
}
