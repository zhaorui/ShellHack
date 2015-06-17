#!/bin/bash
set -e

ADQUERY="/usr/bin/adquery"
ADFLUSH="/usr/sbin/adflush"
DSCL="/usr/bin/dscl"
SED="/usr/bin/sed"

usage () {
    echo "usage: $0 [-a|--auto] [names ...]"
    exit 1;
}

if test $# = 0
then
    usage
fi

case "$1" in
    -a|--auto)
        names=`dscl . -list /Users AuthenticationAuthority | grep "LocalCachedUser" | awk -F ';' '{print $1}' | sed -e 's/\ *$//'`
        ;;
    -*)
        usage
        ;;
    *)
        names=$@
        ;;
esac

sudo $ADFLUSH -f

for user in $names
do
    new_guid=$($ADQUERY user --guid $user)
    old_guid=$($DSCL . -read /Users/$user GeneratedUID | $SED -e 's/^GeneratedUID: //' )
    sudo $DSCL . -change /Users/$user GeneratedUID "$old_guid" "$new_guid"
done
echo "guid update successfully!"
