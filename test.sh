############################################################
# Function:     GetHomeDir
# Parameter:    User name
# Return:       Path to home directory, or nothing if can't find.
# Description:
#   Locates user's home directory from NSS data.
GetHomeDir()
{
    # The home directory is the 6th field in the NSS data.
    getent passwd "$1" | cut -d : -f 6
    Flag=1
    if [ $Flag -eq 1 ]
    then
        echo Flag == 1
    fi
}

#Main Sub
main()
{
    GetHomeDir bill
}

main

