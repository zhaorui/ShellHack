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
}

#Main Sub
main()
{
    GetHomeDir bill
}

main

