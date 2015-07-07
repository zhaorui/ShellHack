#!/bin/bash

while read line
do
    echo $line
    file=`echo $line | cut -d: -f1`  
    origin=`echo $line | cut -d: -f2` 
    origin=`echo $origin | sed -e 's/"/\\"/g'`
    current=`echo $origin | sed -e "s#/usr/share#/usr/local/share#"`
    p4 edit -c 124193 $file
    sed -e "s|$origin|$current|" $file > $file
done
