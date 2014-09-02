alias centrifydc='sudo /usr/share/centrifydc/bin/centrifydc'
alias cdcdebug='sudo /usr/share/centrifydc/bin/cdcdebug'
export P4CONFIG=~/.p4config
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
export PATH=/usr/local/bin:${PATH}
export http_proxy=192.168.4.33:3128
export https_proxy=192.168.4.33:3128

# useful functions
cleanpam() { cd /etc/pam.d; for i in `ls *.pre_cdc`; do sudo mv $i ${i%.*}; done; }

when() { ls -ld $1 | awk '{print $6, $7, $8}'; }

vimpl()
{
    #Here we use the indirect referencing, example as below
    #ref=fruit
    #fruit=apple
    #echo ${ref}
    #>fruit
    #echo ${!ref}
    #>apple
    local plist_file=${!#}  #This command is equal to   eval echo \$$#
    sudo plutil -convert xml1 $plist_file
    vim $*
    sudo plutil -convert binary1 $plist_file
}

sysdbg()
{
    sudo bash -c 'sed "s/notice/debug/g" /etc/asl.conf > /etc/asl.conf.2; mv -f /etc/asl.conf.2 /etc/asl.conf'
    sudo launchctl unload /System/Library/LaunchDaemons/com.apple.syslogd.plist
    sudo launchctl load /System/Library/LaunchDaemons/com.apple.syslogd.plist
}

sysnot()
{
    sudo bash -c 'sed "s/debug/notice/g" /etc/asl.conf > /etc/asl.conf.2; mv -f /etc/asl.conf.2 /etc/asl.conf'
    sudo launchctl unload /System/Library/LaunchDaemons/com.apple.syslogd.plist
    sudo launchctl load /System/Library/LaunchDaemons/com.apple.syslogd.plist
}

authwrite()
{
    rules=('admin' 'allow' 'authenticate')
    for i in ${rules[@]}
    do
        if [ $2 = $i ]
        then
            sudo security authorizationdb write $1 $2
            return
        fi
    done
    sudo security authorizationdb write $1 < $2 
}

authread()
{
    security authorizationdb read $1
}
