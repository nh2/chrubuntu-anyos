{ stdenv, fetchFromGitHub, glibc_multi, glibc }:

stdenv.mkDerivation rec {
  pname = "plopkexec";
  version = "1.4.1"; # Note: Update `rev` below when changing this

  # We're not using the upstream tarball from the original author at
  #     https://download.plop.at/plopkexec
  # but instead a fork from `eugenesan`, because it implements the critical
  # feature to detect file systems on the fly:
  #     https://github.com/eugenesan/chrubuntu-script/blob/3247b0d4aefc9e75bee7b41eb4cb191e4a1f0852/plopkexec/Changelog#L43-L44
  #
  # Also note that for both the original tarball and the GitHub fork:
  # The code contains large prebuilt binaries for Linux kernel,
  # an .iso image, vendored source distributions and so on.
  # We use only the source code from the `src/` subdirectory of the tarball
  # (which is the `plopkexec/plop` subdirectory in the fork).
  src = fetchFromGitHub {
    owner = "eugenesan";
    repo = "chrubuntu-script";
    rev = "3247b0d4aefc9e75bee7b41eb4cb191e4a1f0852";
    sha256 = "0wck9bqqby20p1idhjxapbgzvirz1kbhrbmbvjwc82mhx3pak99h";
  };

  outputs = [ "out" "kernelconfig" ];

  nativeBuildInputs = [
    glibc.static
  ];

  enableParallelBuilding = true;

  preBuild = ''
    cd plopkexec/plop
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
