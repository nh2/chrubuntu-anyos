# chrubuntu-anyos

With this project you can can run any Linux distro on your legacy (pre-Coreboot) Chromebook.

So far the following hardware has been tested:

* [Samsung 500C](https://www.chromium.org/chromium-os/developer-information-for-chrome-os-devices/samsung-series-5-chromebook) (codename `alex`)

It provides:

* A version of the [PlopKexec](https://www.plop.at/en/plopkexec/full.html) boot manager, which you can put on the hard drive, USB or SD card, which can then load any normal Linux OS, or OS installer (caveats apply, see [support list below](#linux-distros-bootable-by-plopkexec)).
* Handy hard drive partitioning scripts.
* A a fully automated way to put [NixOS](https://nixos.org) Linux on the Chromebook, in case you want to use this distro.

Note that on newer Chromebooks you likely don't need this; they can boot Linux without much effort.


## Motivation

[ChrUbuntu](http://chromeos-cr48.blogspot.com/) ([archive link](https://web.archive.org/web/20190809090331/http://chromeos-cr48.blogspot.com/); see also [here](https://github.com/iantrich/ChrUbuntu-Guides/blob/d5996a3c1fd58a02973d50437ed35d735964932f/Guides/Installing%20ChrUbuntu.md)) made it possible to install Ubuntu on older Chromebooks, thus turning them into normal computers without "expiration date" (Google ends supporting older Chromebooks in ChromeOS after a few years).

ChrUbuntu, while awesome, had some drawbacks:

* The last update is from 2013. It installed Ubuntu <= 13.10, now vastly outdated.
* It downloaded a disk image from the Internet.
  * While there's no reason to distrust the ChrUbuntu author, there's no reason to trust anyone on the Internet not to provide a backdoored system. Methods that allow installing from upstream distros or verifyable source are always better.
  * The download occurred over unencrypted HTTP.
  * In summary, could not seriously be considered a "secure" system.
* While you could perform distribution upgrades to newer Ubuntu versions, that often broke and you'd have to start from scratch at Ubuntu <= 13.10.

I considered [crouton](https://github.com/dnschneid/crouton) as an alternative, but found it no good, because it kept ChromeOS's vastly outdated (and thus insecure) kernel, and it also didn't work on my hardware because of a bug in the ChromeOS kernel [I discovered](https://github.com/systemd/systemd/issues/11974#issuecomment-473754055).

So I set out to do what ChrUbuntu did, but with instructions to build it from scratch instead of providing a binary disk image.
I learned about the [disk format](https://www.chromium.org/chromium-os/chromiumos-design-docs/disk-format) that the Chromebooks expected, and read the code of how ChrUbuntu set them up.
I finally figured how to automate it, use upstream kernels, and that I could use [`kexec`](https://wiki.archlinux.org/index.php/kexec)/[PlopKexec](https://www.plop.at/en/plopkexec/full.html) to use normal Linux distributions (any, not only Ubuntu) on the Chromebook without them having to understand its custom disk layout.

I started this quest for my mother, as she used this Chromebook with ChrUbuntu and at some point updating broke.

It then turned into a fight against obsolescence of perfectly good (and fast) hardware.

I hope this project will allow many Chromebooks to continue being used, instead of thrown away prematurely due to artificial "end of life"s.


## Backup of the original ChrUbuntu

You can find my backup of the original ChrUbuntu scripts in [`chrubuntu/`](./chrubuntu/).

The files it tries to download are now no longer available.

But I found that [archive.org](https://archive.org) still hosted those files, made adapted the scripts to download them from there. See [`chrubuntu-scripts/`](./chrubuntu-scripts/).


## Technical details

* TODO: Describe in detail what the problem with running unmodified distros (their kernel updates) is with the Chromebook disk format, and how PlopKexec solves that.
* TODO: Link my patches for:
  * The `kexec` tool itself:
    * [Patch submission](http://lists.infradead.org/pipermail/kexec/2019-April/022964.html)
    * [Patch 1](https://github.com/horms/kexec-tools/commit/23aaa44614a02d2184951142125cb55b36cef40a), [Patch 2](https://github.com/horms/kexec-tools/commit/c072bd13abbe497d28e4235e2cf416f4aee65754)
* TODO: Link the kernel bug: https://bugzilla.kernel.org/show_bug.cgi?id=203463
* TODO: Link my investigation document


## Building

Install the [nix](https://nixos.org/nix/) build tool.

In the below invocations I pin the `nixpkgs` commit for full reproducibility; you may also use a stable release branch instead, e.g. `NIX_PATH=nixpkgs=https://github.com/NixOS/nixpkgs/archive/release-19.09.tar.gz`. You must use one >= 19.09, because previous versions do not have the necessary `kexec` fixes I submitted upstream.

### Step 1: Partitioning a device (usually SD-card or USB)

To create a partitioning scheme that the Chromebook will read, run:

```bash
DEVICE=/dev/mmcblk0  # This is my SD card; change this to your target device!
SCRIPT=$(NIX_PATH=nixpkgs=https://github.com/nh2/nixpkgs/archive/95aa1b3c8b.tar.gz nix-build --no-link '<nixpkgs/nixos>' -A config.system.build.chromebook-removable-media-partitioning-script -I nixos-config=nixos-rootfs.nix) && $SCRIPT "$DEVICE"
```

Note you can also use this to partition a Chromebook's hard drive directly if desired.
But using an SD-card or USB is recommended instead so you can check if it works first, before altering your Chromebook's hard drive.

The script creates two partitions:

* A _kernel partition_ called `KERN-A`
* An _OS root partition_ called `ROOT-A`

Their purposes:

* `KERN-A`
  * This is where you can put either PlopKexec (recommended), or a normal kernel for booting the OS root partition directly (for testing).
* `ROOT-A`
  * This is where you can optionally put a Linux distribution like NixOS. Otherwise, it will stay empty.
  * If you use PlopKexec (recommended), it'll show it in the list for you to pick at boot.
  * If you use a normal kernel for direct boot (for testing), it will be booted without prompt. Note that in this case, the kernel modules in the `initramfs` of the root partition must be binary-compatible with the kernel on the kernel partition (e.g. same version).


### Step 2: Putting PlopKexec on the device

```bash
KERNEL_DEVICE=/dev/mmcblk0p2  # For my SD card; change this to your target device's kernel partition!
KERNEL_FLAVOUR=plopkexec
IMAGE=$(NIX_PATH=nixpkgs=https://github.com/NixOS/nixpkgs/archive/95aa1b3c8b.tar.gz nix-build --no-link '<nixpkgs/nixos>' -A "config.system.build.signed-chromiumos-kernel-$KERNEL_FLAVOUR" -I nixos-config=nixos-rootfs.nix) && test -b "$KERNEL_DEVICE" && sudo dd "if=$IMAGE" "of=$KERNEL_DEVICE" conv=fsync
```

You can now put the device into your Chromebook and boot it (e.g. pressing `Ctrl+U` to boot form SD-card or USB).

(Note sometimes the Chromebook firmware does not find the SD-card or USB when booting when you press `Ctrl+U`, complaining with a beep. I've found that in those situations, re-plugging the device and pressing `Ctrl+U` again helps.)

### Optional/alternative steps: Putting NixOS on the device

If you additionally want a NixOS installation on the OS partition of the device, run:

```bash
OS_DEVICE=/dev/mmcblk0p3  # For my SD card; change this to your target device's OS root partition!
mkdir -p os-device-mount
TARBALL=$(NIX_PATH=nixpkgs=https://github.com/NixOS/nixpkgs/archive/95aa1b3c8b.tar.gz nix-build --no-link '<nixpkgs/nixos>' -A config.system.build.tarball -I nixos-config=nixos-rootfs.nix) && test -b "$OS_DEVICE" && sudo mkfs.ext4 -L NIXOS_ROOT_SD "$OS_DEVICE" && sudo mount "$OS_DEVICE" os-device-mount && (test -d os-device-mount/var/empty && sudo chattr -i os-device-mount/var/empty || true) && sudo rm -rf os-device-mount/* && sudo tar xf "$TARBALL/tarball/nixos-system-x86_64-linux.tar" -C os-device-mount && sudo umount os-device-mount && sync
```

Note we set the ext4 file system label to `NIXOS_ROOT_SD`; usually this would have to agree with the NixOS config's `fileSystems."/".label` setting, because that's how the initramfs decides what to mount as root partition, but I patched PlopKexec to pass the selected device `root=`, which the NixOS `stage-1-init.sh` takes as priority over the default config.
It will show up under `/dev/disk/by-label/`.

If you want to use a direct booting kernel instead of PlopKexec, run:

```bash
KERNEL_DEVICE=/dev/mmcblk0p2  # For my SD card; change this to your target device's kernel partition!
KERNEL_FLAVOUR=normal
IMAGE=$(NIX_PATH=nixpkgs=https://github.com/NixOS/nixpkgs/archive/95aa1b3c8b.tar.gz nix-build --no-link '<nixpkgs/nixos>' -A "config.system.build.signed-chromiumos-kernel-$KERNEL_FLAVOUR" -I nixos-config=nixos-rootfs.nix) && test -b "$KERNEL_DEVICE" && sudo dd "if=$IMAGE" "of=$KERNEL_DEVICE" conv=fsync
```

Note that direct booting kernels have a drawback:
You'll be using _that_ kernel version, no matter what updates you install in NixOS (unless you set it up some hook to also copy new kernels into the Chromebook's kernel partition).


## Linux distros bootable by PlopKexec

The project intro says PlopKexec can "load any normal Linux OS, or OS installer".
This is correct in theory, because it can start any kernel image + initrd, but in practice a successful boot also depends on what the Linux distro does in its initrd and whether the kernel supplied in the installer supports the hardware.

For my Samsung 500C `alex` Chromebook, here's a list of what works:

* :heavy_check_mark: Ubuntu 18.04 / 19.04 installer
  * Installation will fail at last step but there's an easy workaround ([see below](#installing-ubuntu-with-plopkexec))
* :heavy_check_mark: NixOS when configured as shown in this project.
* :heavy_check_mark: NixOS 19.03 installer CLI
  * :x: But starting the GUI doesn't work on the C
* :x: Debian 10.1 installer
  * Screen freeze at kexec time. Probably the Intel driver is not provided in the installer's kernel:
  * My machine can't start with the `framebuffer` driver, but needs the native Intel driver (`i915`). This is included in the Ubuntu installer's initrd but not in the Debian installer's initrd, hence the Debian installer cannot use the screen.

For systems where the installer doesn't work, you may want to try installing it on another machine, and copying the contents over (after ensuring the initrd you've built contains the display driver).

### Installing Ubuntu with PlopKexec

* Boot into the graphical live system and start the installer.
* When asked whether to unmount a device (that's the SD card if you haven't ejected it yet if you started PlopKexec from that), it doesn't matter if you choose Yes or No.
* When asked whether to format the device, choose the last step (`I want to do something else`), pick the Chromebook hard drive's _OS root partition_ (usually `/dev/sda2`), and configure it to use it as `/` mount point with `ext4` file system (enable the formatting checkbox).
  * Do NOT use a separate `/boot` partition or something like that.
* Select as `Device for boot loader installation` the same partition you chose for `/`.
* Let the installer finish. It will fail with some error about the bootloader failing to install. That's OK, close the windows.
* The installer will have failed to a `grub.cfg`. If we reboot now, PlopKexec won't find it. We'll generate it now.
* Open a terminal. Go into the installed system and generate `grub.cfg` by running:
  ```bash
  sudo mount -o bind /dev /target/dev
  sudo mount -o bind /proc /target/proc
  sudo mount -o bind /sys /target/sys
  sudo chroot /target /bin/bash
  update-grub
  ```
  It should print:
  ```
  grub-probe: error: cannot find a GRUB device for /dev/sdb1.  Check your device map.
  done
  ```
  Despite the error, the `grub.cfg` we need will have been generated.
* You can now reboot and choose your installed system in PlopKexec.
* Future `apt` operations will continue to complain about the grub package. For example, you may see when installing something trivial like `sudo apt install htop`:
  ```
  grub-install: error: cannot copy `/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed` to `/boot/efi/EFI/ubuntu/grubx64.efi`: No space left on device.
  ```
  This is because the EFI partition on the Chromebook is too small to hold more than its default kernels:
  `df -h` shows `/dev/sda12` being mounted at `/boot/efi`, being 100% full in my case.
  Note we don't need GRUB in EFI because we boot via PlopKexec. So:
* Fix it using `sudo apt remove grub-efi-amd64-signed`.

You should now have a working Ubuntu that you can update as usual.

## Optional: Putting plopkexec on the Chromebook hard disk

Once you've got your target OS to boot, if you do not want your plopkexec bootloader to live on the external device, but the Chromebook hard disk instead, so that you can use your device fully without an external device, you can copy it over via a shell of your running OS.

1. Verify with `lsblk` that `/dev/sda` and `/dev/sdb` are the Chromebook hard drive and the external device respectively.
2. Copy plopkexec from the _kernel partition_ on the external device to the corresponding _kernel partition_ on the hard disk:
   ```bash
   sudo dd if=/dev/sdb1 of=/dev/sda1 bs=1M
   ```
3. Give that _kernel partition_ on the hard disk highest priorities and infinite boot tries with the `cgpt` tool (get it with e.g. `sudo apt-get install cgpt` on Ubuntu):
   ```
   cgpt add -i 2 -P 1 -S 1
   ```
   Here, `-i 2` is partition number 2 (counting from 1) which corresponds to the `1` (counting from 0) in `/dev/sda1`.

You should now be able to boot completely from the hard disk.
