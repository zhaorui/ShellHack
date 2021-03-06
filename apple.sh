#!/bin/bash


# -e option used to multi-process for one line
#echo "hello world" | sed  -e 's/^\(.\{5\}\).*/\1/' -e 's/.*\(.\{2\}\)$/\1/'
# if only one process is needed, there's no need for -e option
#echo "hello world" | sed 's/^\(.\{5\}\).*/\1/'


#echo `adquery user afp1 --attribute _ObjectExtended | sed -e 's|^\(^[0-9a-f]\{8\}\).*|\1|'`
#uuid=`adquery user afp1 --attribute _ObjectExtended`
uuid=a756f4ad
echo $uuid
uuid=`echo ${uuid:0:8} | tr '[a-f]' '[A-F]' | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/'`
uuid=`echo "ibase=16; $uuid" | bc`
mask=`echo "ibase=16; 7FFFFFFF" | bc`
echo uuid: $uuid
echo mask: $mask

#printf "%d\n" 0x$uuid
#
echo $(($uuid&$mask))
