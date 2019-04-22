set -e

target_rootfs="chrubuntu-rootfs.img"

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
      correct_sha1=`cat ../shas/$FILENAME.sha1 | awk '{print $1}'`
      correct_sha1_length="${#correct_sha1}"
      if [ "$correct_sha1_length" -eq "40" ]
      then
        correct_sha1_is_valid=1
      else
        echo "bad"
        # rm $FILENAME.sha1
      fi
    done
    write_is_valid=0
    while [ $write_is_valid -ne 1 ]
      do
        cat $FILENAME | bunzip2 -c | dd bs=1024 seek=$SEEK of=${target_rootfs} status=noxfer > /dev/null 2>&1
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
