alias centrifydc='sudo /usr/share/centrifydc/bin/centrifydc'
alias cdcdebug='sudo /usr/share/centrifydc/bin/cdcdebug'
export P4CONFIG=~/.p4config
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
export PATH=/usr/local/bin:${PATH}
export http_proxy=192.168.4.12:8080
export https_proxy=192.168.4.12:8080

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
    local plist_file=${!#}
    sudo plutil -convert xml1 $plist_file
    vim $*
    sudo plutil -convert binary1 $plist_file
}
