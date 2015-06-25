#!/bin/bash
#Author: billzhao
#This script is used to compare files in different folder

for file in `cd $1; find .`
do 
    diff $1/$file $2/$file; 
done
