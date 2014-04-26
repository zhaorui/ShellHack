alias centrifydc='sudo /usr/share/centrifydc/bin/centrifydc'
alias cdcdebug='sudo /usr/share/centrifydc/bin/cdcdebug'
export P4CONFIG=~/.p4config
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced
export PATH=/usr/local/bin:${PATH}
export http_proxy=192.168.4.12:8080
export https_proxy=192.168.4.12:8080

# useful functions
when() { ls -ld $1 | awk '{print $6, $7, $8}'; }
