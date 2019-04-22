set -eu -o pipefail

target_disk="/dev/mmcblk0"

# echo "Got ${target_disk} as target drive"
# echo ""
# echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
# echo ""
# read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

# ext_size="`blockdev --getsz ${target_disk}`"
# aroot_size=$((ext_size - 65600 - 33))
# parted --script ${target_disk} "mktable gpt"
# cgpt create ${target_disk}
# cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
# cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
# sync
# blockdev --rereadpt ${target_disk}
# partprobe ${target_disk}

if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p7"
  target_kern="${target_disk}p6"
else
  target_rootfs="${target_disk}7"
  target_kern="${target_disk}6"
fi

# dd if=alex-chrubuntu-rootfs.img of=${target_rootfs} bs=1M status=progress

#Mount Ubuntu rootfs and copy cgpt + modules over
echo "Copying modules, firmware and binaries to ${target_rootfs} for ChrUbuntu"
if [ ! -d /tmp/urfs ]
then
  mkdir /tmp/urfs
fi
mount -t ext4 ${target_rootfs} /tmp/urfs
cp /usr/bin/cgpt /tmp/urfs/usr/bin/
chmod a+rx /tmp/urfs/usr/bin/cgpt

# echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > kernel-config
echo "console=tty1 debug verbose root=/dev/sdb7 rootwait rw lsm.module_locking=0" > kernel-config

model="alex"
use_kernfs="$model-x64-kernel-partition"


# vbutil_kernel --repack $use_kernfs.new --oldblob $use_kernfs \
vbutil_kernel --repack $use_kernfs.new --oldblob alex-x64-kernel-partition-niklasdevice \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config niklasdevice-kernelconfig-modified
    # --config kernel-config

tar xjvvf $model-x64-modules.tar.bz2 --directory /tmp/urfs/lib/modules

umount /tmp/urfs

dd if=$use_kernfs.new of=${target_kern}

sync
