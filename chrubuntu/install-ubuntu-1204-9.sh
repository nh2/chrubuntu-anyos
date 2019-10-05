# fw_type will always be developer for Mario.
# Alex and ZGB need the developer BIOS installed though.
fw_type="`crossystem mainfw_type`"
if [ ! "$fw_type" = "developer" ]
  then
    echo -e "\nYou're Chromebook is not running a developer BIOS!"
    echo -e "You need to run:"
    echo -e ""
    echo -e "sudo chromeos-firmwareupdate --mode=todev"
    echo -e ""
    echo -e "and then re-run this script."
    return
  else
    echo -e "\nOh good. You're running a developer BIOS...\n"
fi

# hwid lets us know if this is a Mario (Cr-48), Alex (Samsung Series 5), ZGB (Acer), etc
hwid="`crossystem hwid`"

echo -e "Chome OS model is: $hwid\n"

chromebook_arch="`uname -m`"
if [ ! "$chromebook_arch" = "x86_64" ]
then
  echo -e "This version of Chrome OS isn't 64-bit. We'll use an unofficial Chromium OS kernel to get around this...\n"
else
  echo -e "and you're running a 64-bit version of Chrome OS! That's just dandy!\n"
fi

read -p "Press [Enter] to continue..."

powerd_status="`initctl status powerd`"
if [ ! "$powerd_status" = "powerd stop/waiting" ]
then
  echo -e "Stopping powerd to keep display from timing out..."
  initctl stop powerd
fi

powerm_status="`initctl status powerm`"
if [ ! "$powerm_status" = "powerm stop/waiting" ]
then
  echo -e "Stopping powerm to keep display from timing out..."
  initctl stop powerm
fi

setterm -blank 0

if [ "$1" != "" ]; then
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
  crossystem dev_boot_usb=1
else
  target_disk="`rootdev -d -s`"
  # Do partitioning (if we haven't already)
  ckern_size="`cgpt show -i 6 -n -s -q ${target_disk}`"
  croot_size="`cgpt show -i 7 -n -s -q ${target_disk}`"
  state_size="`cgpt show -i 1 -n -s -q ${target_disk}`"

  max_ubuntu_size=$(($state_size/1024/1024/2))
  rec_ubuntu_size=$(($max_ubuntu_size - 1))
  # If KERN-C and ROOT-C are one, we partition, otherwise assume they're what they need to be...
  if [ "$ckern_size" =  "1" -o "$croot_size" = "1" ]
  then
    while :
    do
      read -p "Enter the size in gigabytes you want to reserve for Ubuntu. Acceptable range is 5 to $max_ubuntu_size  but $rec_ubuntu_size is the recommended maximum: " ubuntu_size
      if [ ! $ubuntu_size -ne 0 2>/dev/null ]
      then
        echo -e "\n\nNumbers only please...\n\n"
        continue
      fi
      if [ $ubuntu_size -lt 5 -o $ubuntu_size -gt $max_ubuntu_size ]
      then
        echo -e "\n\nThat number is out of range. Enter a number 5 through $max_ubuntu_size\n\n"
        continue
      fi
      break
    done
    # We've got our size in GB for ROOT-C so do the math...

    #calculate sector size for rootc
    rootc_size=$(($ubuntu_size*1024*1024*2))

    #kernc is always 16mb
    kernc_size=32768

    #new stateful size with rootc and kernc subtracted from original
    stateful_size=$(($state_size - $rootc_size - $kernc_size))

    #start stateful at the same spot it currently starts at
    stateful_start="`cgpt show -i 1 -n -b -q ${target_disk}`"

    #start kernc at stateful start plus stateful size
    kernc_start=$(($stateful_start + $stateful_size))

    #start rootc at kernc start plus kernc size
    rootc_start=$(($kernc_start + $kernc_size))

    #Do the real work
    
    echo -e "\n\nModifying partition table to make room for Ubuntu." 
    echo -e "Your Chromebook will reboot, wipe your data and then"
    echo -e "you should re-run this script..."
    umount /mnt/stateful_partition
    
    # stateful first
    cgpt add -i 1 -b $stateful_start -s $stateful_size -l STATE ${target_disk}

    # now kernc
    cgpt add -i 6 -b $kernc_start -s $kernc_size -l KERN-C ${target_disk}

    # finally rootc
    cgpt add -i 7 -b $rootc_start -s $rootc_size -l ROOT-C ${target_disk}

    reboot
    exit
  fi
fi

if [ ! -d /mnt/stateful_partition/ubuntu ]
then
  mkdir /mnt/stateful_partition/ubuntu
fi

cd /mnt/stateful_partition/ubuntu

# try mounting a USB / SD Card if it's there...
if [ ! -d /tmp/usb_files ]
  then
    mkdir /tmp/usb_files
  fi
mount /dev/sdb /tmp/usb_files > /dev/null 2>&1
mount /dev/sdb1 /tmp/usb_files > /dev/null 2>&1

# Copy /tmp/usb_files/ubuntu (.sha1 and foo.6 files) to SSD if they're there
if [ -d /tmp/usb_files/ubuntu ]
  then
    cp -rf /tmp/usb_files/ubuntu/* /mnt/stateful_partition/ubuntu/
  fi

if [[ "${target_disk}" =~ "mmcblk" ]]
then
  target_rootfs="${target_disk}p7"
  target_kern="${target_disk}p6"
else
  target_rootfs="${target_disk}7"
  target_kern="${target_disk}6"
fi

echo "Target Kernel Partition: $target_kern  Target Root FS: ${target_rootfs}"

# Download and copy ubuntu root filesystem, keep track of successful parts so we can resume
SEEK=0
FILESIZE=102400
for one in a b
do
  for two in a b c d e f g h i j k l m n o p q r s t u v w x y z
  do
    # last file is smaller than the rest...
    if [ "$one$two" = "bz" ]
    then
      FILESIZE=20480
    fi
    FILENAME="ubuntu-1204.bin$one$two.bz2"
    correct_sha1_is_valid=0
    while [ $correct_sha1_is_valid -ne 1 ]
    do
      if [ ! -f /mnt/stateful_partition/ubuntu/$FILENAME.sha1 ]
      then
        wget http://cr-48-ubuntu.googlecode.com/files/$FILENAME.sha1
      fi
      correct_sha1=`cat $FILENAME.sha1 | awk '{print $1}'`
      correct_sha1_length="${#correct_sha1}"
      if [ "$correct_sha1_length" -eq "40" ]
      then
        correct_sha1_is_valid=1
      else
        rm $FILENAME.sha1
      fi
    done
    current_sha1=`dd if=${target_rootfs} bs=1024 skip=$SEEK count=$FILESIZE status=noxfer | sha1sum | awk '{print $1}'`
    if [ "$correct_sha1" = "$current_sha1" ]
      then
        echo "$correct_sha1 equals $current_sha1 already written correctly..."
        SEEK=$(( $SEEK + $FILESIZE ))
        continue
      else
        echo -e "$FILENAME needs to be written because it's $current_sha1 not $correct_sha1"
    fi
    if [ -f /tmp/usb_files/$FILENAME ]
      then
        echo -e "Found $FILENAME on flash drive. Using it..."
        get_cmd="cat /tmp/usb_files/$FILENAME"
      else
        echo -e "\n\nDownloading $FILENAME\n\n"
        get_cmd="wget -O - http://cr-48-ubuntu.googlecode.com/files/$FILENAME"
      fi
    write_is_valid=0
    while [ $write_is_valid -ne 1 ]
      do
        $get_cmd | bunzip2 -c | dd bs=1024 seek=$SEEK of=${target_rootfs} status=noxfer > /dev/null 2>&1
        current_sha1=`dd if=${target_rootfs} bs=1024 skip=$SEEK count=$FILESIZE status=noxfer | sha1sum | awk '{print $1}'`
        if [ "$correct_sha1" = "$current_sha1" ]
          then
            echo -e "\n$FILENAME was written to ${target_rootfs} correctly...\n\n"
            write_is_valid=1
        else
          echo -e "\nError writing downloaded file $FILENAME. shouldbe: $correct_sha1 is:$current_sha1. Retrying...\n\n"
        fi
      done
    SEEK=$(( $SEEK + $FILESIZE ))
  done
done

#Mount Ubuntu rootfs and copy cgpt + modules over
echo "Copying modules, firmware and binaries to ${target_rootfs} for ChrUbuntu"
if [ ! -d /tmp/urfs ]
then
  mkdir /tmp/urfs
fi
mount -t ext4 ${target_rootfs} /tmp/urfs
cp /usr/bin/cgpt /tmp/urfs/usr/bin/
chmod a+rx /tmp/urfs/usr/bin/cgpt

echo "console=tty1 debug verbose root=${target_rootfs} rootwait rw lsm.module_locking=0" > kernel-config
if [ "$chromebook_arch" = "x86_64" ]  # We'll use the official Chrome OS kernel if it's x64
then
  cp -ar /lib/modules/* /tmp/urfs/lib/modules/
  vbutil_kernel --pack newkern \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config \
    --vmlinuz /boot/vmlinuz-`uname -r`
  use_kernfs=newkern
else # Otherwise we'll download a custom-built non-official Chromium OS kernel
  model="mario" # set a default
  if [[ $hwid =~ .*MARIO.* ]]
  then
    model="mario"
  else
    if [[ $hwid =~ .*ALEX.* ]]
    then
      model="alex"
    else
      if [[ $hwid =~ .*ZGB.* ]]
      then
        model="zgb"
      fi
    fi
  fi
  wget http://cr-48-ubuntu.googlecode.com/files/$model-x64-modules.tar.bz2
  wget http://cr-48-ubuntu.googlecode.com/files/$model-x64-kernel-partition.bz2
  bunzip2 $model-x64-kernel-partition.bz2
  use_kernfs="$model-x64-kernel-partition"
  vbutil_kernel --repack $use_kernfs \
    --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
    --version 1 \
    --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
    --config kernel-config
  tar xjvvf $model-x64-modules.tar.bz2 --directory /tmp/urfs/lib/modules
fi
umount /tmp/urfs

dd if=$use_kernfs of=${target_kern}






# Resize sda7 in order to "grow" filesystem to user's selected size
e2fsck -f ${target_rootfs}
resize2fs -p ${target_rootfs}

#Set Ubuntu partition as top priority for next boot
cgpt add -i 6 -P 5 -T 1 ${target_disk}

# reboot
reboot
