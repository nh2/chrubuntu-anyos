# chrubuntu-anyos

With this project you can can run any Linux distro on your legacy (pre-Coreboot) Chromebook.

So far the following hardware has been tested:

* [Samsung 500C](https://www.chromium.org/chromium-os/developer-information-for-chrome-os-devices/samsung-series-5-chromebook) (codename `alex`)

It provides:

* A version of the [PlopKexec](https://www.plop.at/en/plopkexec/full.html) boot manager, which you can put on the hard drive, USB or SD card, which can then load any normal Linux OS, or OS installer.
* Handy hard drive partitioning scripts.
* A a fully automated way to put [NixOS](https://nixos.org) Linux on the Chromebook, in case you want to use this distro.

Note that on newer Chromebooks you likely don't need this; they can boot Linux without much effort.

## Motivation

[ChrUbuntu](http://chromeos-cr48.blogspot.com/) ([archive link](https://web.archive.org/web/20190809090331/http://chromeos-cr48.blogspot.com/); see also [here](https://github.com/iantrich/ChrUbuntu-Guides/blob/d5996a3c1fd58a02973d50437ed35d735964932f/Guides/Installing%20ChrUbuntu.md)) made it possible to install Ubuntu on older Chromebooks, thus turning them into normal computers without "expiration date" (Google ends supporting older Chromebooks in ChromeOS after a few years).

You can find my backup of the original ChrUbuntu in [`./chrubuntu/`]()

While awesome, had some drawbacks:

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

## Technical details

* TODO: Describe in detail what the problem with running unmodified distros (their kernel updates) is with the Chromebook disk format, and how PlopKexec solves that.
* TODO: Link my patches for:
  * The `kexec` tool itself:
    * [Patch submission](http://lists.infradead.org/pipermail/kexec/2019-April/022964.html)
    * [Patch 1](https://github.com/horms/kexec-tools/commit/23aaa44614a02d2184951142125cb55b36cef40a), [Patch 2](https://github.com/horms/kexec-tools/commit/c072bd13abbe497d28e4235e2cf416f4aee65754)
* TODO: Link my investigation document
