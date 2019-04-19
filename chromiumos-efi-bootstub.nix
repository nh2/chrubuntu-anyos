{ stdenv, fetchgit, gnu-efi }:

stdenv.mkDerivation rec {
  pname = "chromiumos-efi-bootstub";
  version = "20180711";

  src = fetchgit {
    url = https://chromium.googlesource.com/chromiumos/third_party/bootstub;
    rev = "6697fe6404055443d7c754b365907a0604f14111";
    sha256 = "1ppf5i0rjgn2rvwhvl23snx4kfvqixj4ky1s7h855phm5v7haxka";
  };

  makeFlags = [
    "EFIINC=${gnu-efi}/include/efi"
    "EFILIB=${gnu-efi}/lib"
    "EFICRT0=${gnu-efi}/lib"
    "DESTDIR=${placeholder "out"}"
  ];

  meta = with stdenv.lib; {
    description = "UEFI bootstub for loading Chromium OS kernels from EFI BIOSes";
    license = licenses.gpl3;
    platforms = platforms.linux;
    maintainers = with maintainers; [ nh2 ];
  };
}
