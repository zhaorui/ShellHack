#!/bin/bash

Birth="1990-1-24"
xLastDay="2070-1-24"
xDays=$(($(($(date -d $xLastDay "+%s") - $(date -d $Birth "+%s"))) / 86400))
liveDays=$(($(($(date "+%s") - $(date -d $Birth "+%s"))) / 86400))
Passed=`echo "scale=2; $liveDays / $xDays * 100" | bc -l `

printf "Birth:            %s\n" $Birth
printf "Maybe Last Day:   %s\n" $xLastDay
printf "Maybe Live Days:  %s days\n" $xDays
printf "Live:             %s days\n" $liveDays
printf "Life Passed:      %s%%\n" $Passed
