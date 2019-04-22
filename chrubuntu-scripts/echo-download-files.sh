set -e

for one in a b
do
  for two in a b c d e f g h i j k l m n o p q r s t u v w x y z
  do
    FILENAME="ubuntu-1204.bin$one$two.bz2"
    echo https://web.archive.org/web/20151230180503/http://cr-48-ubuntu.googlecode.com/files/$FILENAME
  done
done
