# Build with:
#     NIX_PATH=nixpkgs=$HOME/src/nixpkgs nix-build --no-link '<nixpkgs/nixos>' -A config.system.build.tarball -I nixos-config=thisfile.nix
# You can also use
#     -A config.system.build.toplevel
# to build something you can browse locally (that uses symlinks into your nix store).

{config, pkgs, ...}:
{
  # We need no bootloader, because the Chromebook can't use that anyway.
  boot.loader.grub.enable = false;

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
    ];
    contents = [];
    compressCommand = "cat";
    compressionExtension = "";
  };

  nixpkgs.overlays = [
    (self: super: {

      # Add package to create EFI boot stub
      chromiumos-efi-bootstub = super.callPackage ./chromiumos-efi-bootstub.nix {};

      # Override kernel to use config options that ChromiumOS build uses;
      # otherwise the Chromebook does not boot.
      # TODO: Figure out what config settings make it boot, and enable those
      #       in addition to the normal NixOS kernel settings (using
      #       `kernelPatches.extraConfig`) instead of using ChromiumOS's
      #       upstream ones as a base and adding NixOS's settings on top.
      #       Adding just the ones from ChromeOS's file
      #         src/third_party/kernel/v4.4/chromeos/config/x86_64/chromiumos-x86_64.flavour.config
      #       was not sufficient.
      xxx = super.linuxManualConfig {
      # linux_4_4 = super.linuxManualConfig {
        inherit (super) stdenv;
        inherit (super.linux_4_4) src version;
        configfile =
          let
            # Almost upstream; I've added KEXEC and some console settings
            # so that kernel messages are printed on boot for debugging.
            upstreamConfigFile = ./chromebook-kernel-config;
            # upstreamConfigFile = ./galliumos-v4.16.18-galliumos-kernel-config; # also black screen

            # What to append to the kernel `chromebook-kernel-config`:
            # Things that NixOS requires in addition in order to build/run.
            # `kernelPatches` doesn't seem to work here for unknown reason.
            appendConfigFile = pkgs.writeText "kernel-append-config" ''
              CONFIG_AUTOFS4_FS=y
            '';
          in
            pkgs.runCommand "kernel-config" {} ''
              cat ${upstreamConfigFile} ${appendConfigFile} > $out
            '';
        allowImportFromDerivation = true;
      };

    })
  ];

  # Select the kernel that we've overridden with custom config above.
  boot.kernelPackages = pkgs.linuxPackages_4_4;

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
      kernelPath =
        "${config.boot.kernelPackages.kernel}/" +
        "${config.system.boot.loader.kernelFile}";
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-1; # display output works, boot hangs
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-2; # display output works, boot hangs
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-3; # display does not work
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-4; # display does not work
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-5; # display output works, boot hangs
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-6; # display does not work
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-7;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-sdhci-pci;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-sdhci-pci-mmc-block;
      # kernelPath = /home/niklas/src/chrubuntu/alex-tmp/kerneltree/bzImage-linux-4.4.178-ubuntubuild-chromiumosconfig-8;
      kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
        console=tty0
        init=/bin/init
        initrd=/bin/initrd
        cros_efi
        oops=panic
        panic=0
        root=PARTUUID=%U/PARTNROFF=1
        rootwait
        ro
        noinitrd
        cros_debug
        kern_guid=%U
        add_efi_memmap
        boot=local
        noresume
        noswap
        i915.modeset=1
        nmi_watchdog=panic,lapic
        nosplash
      '';

      # TODO comment on /dev/disk/by-label/NIXOS_ROOT_SD not appearing

      # kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
      #   console=tty0
      #   init=/bin/init
      #   initrd=/bin/initrd
      #   cros_efi
      #   oops=panic
      #   panic=0
      #   root=/dev/disk/by-label/NIXOS_ROOT_SD
      #   rootwait
      #   ro
      #   noinitrd
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
    # https://cateee.net/lkddb/web-lkddb/BLK_DEV_SD.html
    #   Do not compile this driver as a module if your root file system
    #   (the one containing the directory /) is located on a SCSI disk.
    #   In this case, do not compile the driver for your SCSI host
    #   adapter (below) as a module either.

    # IOSF_MBI y
    #

    # extraConfig = ''
    #   SCSI y
    #   SCSI_MOD y
    #   BLK_DEV_SD y
    #   SCSI_SPI_ATTRS y
    #   ATA y
    #   SATA_AHCI y
    #   ATA_GENERIC y

    #   BLK_DEV_DM y
    #   DM_BUFIO y
    #   DM_BIO_PRISON y
    #   DM_PERSISTENT_DATA y
    #   DM_CRYPT y
    #   DM_THIN_PROVISIONING y
    #   DM_VERITY y

    #   #USB_NET_DRIVERS y

    #   INPUT_EVDEV y

    #   #KEYBOARD_CROS_EC y

    #   SERIO y
    #   SERIO_I8042 y
    #   SERIO_LIBPS2 y

    #   HW_RANDOM y
    #   HW_RANDOM_TPM y
    #   HW_RANDOM_INTEL y
    #   NVRAM y
    #   TCG_TPM y
    #   TCG_TIS y
    #   DEVPORT y

    #   ITCO_WDT y
    #   ITCO_VENDOR_SUPPORT y

    #   SSB_SDIOHOST y

    #   AGP y
    #   AGP_INTEL y
    #   INTEL_GTT y
    #   DRM y
    #   DRM_KMS_HELPER y
    #   # important:
    #   DRM_I915 y

    #   FB_SYS_FILLRECT y
    #   FB_SYS_COPYAREA y
    #   FB_SYS_IMAGEBLIT y
    #   FB_SYS_FOPS y
    #   BACKLIGHT_GENERIC y

    #   #USB_STORAGE y
    #   #USB_STORAGE_REALTEK y
    #   #USB_UAS y
    #   #USB_SERIAL y

    #   MMC y
    #   MMC_BLOCK y
    #   MMC_BLOCK_MINORS 16

    #   MMC_SDHCI y
    #   MMC_SDHCI_PCI y
    #   MMC_SDHCI_ACPI y
    #   LEDS_CLASS y

    #   #DMA_OF y

    #   #ASHMEM y
    #   #ANDROID_TIMED_OUTPUT y
    #   #ANDROID_TIMED_GPIO y
    #   #SYNC y
    #   #SW_SYNC y
    #   #SW_SYNC_USER y
    #   #ION y
    #   #ION_DUMMY y
    #   #ACPI_WMI y
    #   #MXM_WMI y

    #   CHROMEOS_LAPTOP y
    #   CHROMEOS_PSTORE y
    #   #CROS_EC_CHARDEV y
    #   #CROS_EC_LPC y

    #   GOOGLE_FIRMWARE y

    #   EFI_VARS y
    #   #EFI_VARS_PSTORE y
    #   EXT4_FS y
    #   EXT4_USE_FOR_EXT2 y
    #   EXT4_ENCRYPTION y
    #   JBD2 y
    #   FS_MBCACHE y
    #   AUTOFS4_FS y

    #   #PSTORE_RAM y

    #   ENCRYPTED_KEYS y

    #   LSM_MMAP_MIN_ADDR 32768
    #   SECURITY_SELINUX_BOOTPARAM_VALUE 1
    #   #DEFAULT_SECURITY selinux

    #   EXT2_FS n

    #   #CONFIG_REGMAP_I2C y
    #   #CONFIG_REGMAP_SPI y
    # '';

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

    # For unknown reason, the below rejected the following entries with weird
    # errors when creating the config:
    #     DRM_NOUVEAU y
    #     DRM_GMA500 y
    #     DRM_CIRRUS_QEMU y
    #     DRM_VIRTIO_GPU y
    #     DRM_TTM y
    #     CPU_FREQ_DEFAULT_GOV_ONDEMAND y
    # extraConfig = ''
    #   ACERHDF m
    #   ACPI_WMI y
    #   B43 m
    #   B43_BCMA y
    #   B43_BCMA_PIO y
    #   B43_BUSES_BCMA_AND_SSB y
    #   B43_HWRNG y
    #   B43_LEDS y
    #   B43_PCICORE_AUTOSELECT y
    #   B43_PCI_AUTOSELECT y
    #   B43_PHY_G y
    #   B43_PHY_HT y
    #   B43_PHY_LP y
    #   B43_PHY_N y
    #   B43_PIO y
    #   B43_SDIO y
    #   B43_SSB y
    #   BCMA m
    #   BCMA_BLOCKIO y
    #   BCMA_DRIVER_PCI y
    #   BCMA_HOST_PCI y
    #   BCMA_HOST_PCI_POSSIBLE y
    #   DRM_GMA3600 y
    #   DRM_GMA600 y
    #   DRM_NOUVEAU_BACKLIGHT y
    #   DRM_RADEON m
    #   DW_DMAC m
    #   DW_DMAC_CORE m
    #   FB_BACKLIGHT y
    #   IWL3945 m
    #   IWL4965 m
    #   IWLEGACY m
    #   MOUSE_BCM5974 m
    #   MOUSE_SYNAPTICS_USB m
    #   MXM_WMI y
    #   NOUVEAU_DEBUG 5
    #   NOUVEAU_DEBUG_DEFAULT 3
    #   NR_CPUS 64
    #   RT2800PCI_RT33XX y
    #   RT2800PCI_RT35XX y
    #   RT2800PCI_RT53XX y
    #   RTL8187 m
    #   RTL8187_LEDS y
    #   RTL8192CU m
    #   RTL8192DE m
    #   RTL8192SE m
    #   RTLLIB m
    #   RTLLIB_CRYPTO_CCMP m
    #   RTLLIB_CRYPTO_TKIP m
    #   RTLLIB_CRYPTO_WEP m
    #   RTLWIFI_USB m
    #   SKGE m
    #   SKY2 m
    #   SND_SOC_INTEL_BYTCR_RT5640_MACH m
    #   SND_SOC_INTEL_CHT_BSW_RT5672_MACH m
    #   SND_SOC_RT5640 m
    #   SND_SOC_RT5670 m
    #   SSB m
    #   SSB_B43_PCI_BRIDGE y
    #   SSB_BLOCKIO y
    #   SSB_DRIVER_PCICORE y
    #   SSB_DRIVER_PCICORE_POSSIBLE y
    #   SSB_PCIHOST y
    #   SSB_PCIHOST_POSSIBLE y
    #   SSB_SDIOHOST y
    #   SSB_SDIOHOST_POSSIBLE y
    #   SSB_SPROM y
    #   THERMAL_GOV_BANG_BANG y
    #   DRM_FBDEV_EMULATION y
    #   KEXEC y
    #   IKCONFIG y
    #   IKCONFIG_PROC y
    #   VT y
    #   VT_CONSOLE y
    #   FRAMEBUFFER_CONSOLE y
    # '';
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
  # boot.kernelModules = [ "kvm-intel" ];
}
