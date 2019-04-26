{ stdenv, fetchurl, glibc_multi, glibc }:

stdenv.mkDerivation rec {
  pname = "plopkexec";
  version = "1.4.1";

  # The tarball contains large prebuilt binaries for Linux kernel,
  # an .iso image, source distributions and so on.
  # We use only the source code from the `src/` subdirectory.
  src = fetchurl {
    url = "https://download.plop.at/plopkexec/plopkexec-${version}.tar.gz";
    sha256 = "0vkbmqy1n9i9vlkgy47cyd5xyjxz188xzsrbb8lakhzkigwzq5ny";
  };

  outputs = [ "out" "kernelconfig" ];

  nativeBuildInputs = [
    glibc.static
  ];

  patches = [
    ./plopkexec-fix-warnings.patch
    # We patch out the `-m32` that plopkexec defaults to because nixpkgs'
    # `glibc_multi` currently doesn't have a `.static` version yet; see:
    #     https://github.com/NixOS/nixpkgs/blob/526a406f11d0bd7077c83fc1e734dbb8e9a3061e/pkgs/development/libraries/glibc/multi.nix#L9
    ./plopkexec-dont-force-architecture.patch
  ];

  enableParallelBuilding = true;

  preBuild = ''
    cd src
  '';

  installPhase = ''
    mkdir ${placeholder "out"}
    install init ${placeholder "out"}/init

    mkdir ${placeholder "kernelconfig"}
    cp ../kernel/.config ${placeholder "kernelconfig"}/config
  '';

  meta = with stdenv.lib; {
    description = "Linux Kernel based boot manager for autodetecting and chainloading Linux distributions from USB and CD/DVD";
    license = licenses.gpl2;
    platforms = platforms.linux;
    maintainers = with maintainers; [ nh2 ];
  };
}
