set -e

target_disk=$1
echo "Got ${target_disk} as target drive"
echo ""
echo "WARNING! All data on this device will be wiped out! Continue at your own risk!"
echo ""
read -p "Press [Enter] to install ChrUbuntu on ${target_disk} or CTRL+C to quit"

ext_size="`blockdev --getsz ${target_disk}`"
aroot_size=$((ext_size - 65600 - 33))
parted --script ${target_disk} "mktable gpt"
cgpt create ${target_disk}
cgpt add -i 6 -b 64 -s 32768 -S 1 -P 5 -l KERN-A -t "kernel" ${target_disk}
cgpt add -i 7 -b 65600 -s $aroot_size -l ROOT-A -t "rootfs" ${target_disk}
sync
blockdev --rereadpt ${target_disk}
partprobe ${target_disk}
