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
    "/".label = "NIXOS_ROOT";
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
      linux_4_4 = super.linuxManualConfig {
        inherit (super) stdenv;
        inherit (super.linux_4_4) src version;
        configfile =
          let
            # Almost upstream; I've added KEXEC and some console settings
            # so that kernel messages are printed on boot for debugging.
            upstreamConfigFile = ./chromebook-kernel-config;
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
      kernelCommandLineParametersFile = pkgs.writeText "kernel-args" ''
        console=tty0
        init=/bin/init
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

  # Install new init script; this ensures that /init is updated after every
  # `nixos-rebuild` run on the machine (the kernel can run init from a
  # symlink).
  system.activationScripts.installInitScript = ''
    ln -fs $systemConfig/init /bin/init
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

  # Turn on nginx as an example
  services.nginx.enable = true;

}
