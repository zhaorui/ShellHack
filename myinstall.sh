#! /bin/sh

# Copyright (C) 2004-2015 Centrify Corporation. All rights reserved.
#
# install.sh - Centrify Server Suite install script.
#
usage () {
    cat <<-END_USAGE

This script installs (upgrades/uninstalls) Centrify Suite.
Only the superuser can run this script.

Usage:
  ${THIS_PRG_NAME} [-n|--ent-suite|--std-suite|--express] [-e] [-h] [-V] [-v ver] [-l log_file]

where:
  -n             Custom install/upgrade/uninstall in non-interactive mode.
  --ent-suite    Install Enterprise Suite in non-interactive mode.
  --std-suite    Install Standard Suite in non-interactive mode.
  --express      Install Centrify Express in non-interactive mode.
  --bundle       Install Centrify Suite using bundle.
  --suite-config <config_file>  
                 Override default suite config file with <config_file>.
  -e             Uninstall (erase) CentrifyDC.
  -h, --help     Print out this usage and then exit.
  -V             Print out installer version and then exit.
  -v <ver>       Install CentrifyDC <ver> version.
                 Format: x.x.x or x.x.x-xxx. x is number.
  -l <log_file>  Override default log-file PATH with <log_file>. 
  --rev <rev>    Package OS revision to install.
  --custom_rc    Return meaningful exit code.
  --override="<options>"
                 In non-interactive mode, override default options with <options> list.
                 Format: --override="CentrifyDC_openssh=n,CentrifyDA=R"
  --adjoin_opt="<adjoin_options>"
                 Override default adjoin command line options with <adjoin_options>.
  --enable-da    In non-interactive mode, once joined to a domain,
                 enable DA for all shells.
  --disable-da   In non-interactive mode, disable DA NSS mode after install.

Examples:
  ./install.sh        -n  --override="INSTALL=R,CentrifyDC_nis=Y,CentrifyDC_openssh=N,CentrifyDA=N"
  ./install.sh        --std-suite  --adjoin_opt="acme.test -p pass\\$ -z t_zone -c acme.test/My\ Servers"
  ./install-bundle.sh --std-suite "--adjoin_opt=\\"acme.test -p pass\\\\$ -z t_zone -c acme.test/My\\\\ Servers\\""

END_USAGE
}
### global variables
CDC_VER_YEAR="2015.1"
CDC_VER="5.2.4"
REV_YEAR="${CDC_VER_YEAR}-450"
REV="${CDC_VER}-450"
CDC_VER_SHORT="${CDC_VER}"

CDC_VER_MINIMUM_MAC="4"         # will bail on mac if CDC_VER is smaller than this
CDC_VER_INC_IDMAP="4.1"         # CDC_VER = or > than this will conflict with CDC-idmap
CDC_VER_INC_NIS_2="4.2"         # CDC_VER < than this will conflict with CDC-nis => 4.2
CDC_VER_INC_KRB5="5.1"          # CDC_VER = or > than this will conflict with CDC-krb5 < 5.1
CDC_VER_INC_SSH="5.2.3"         # CDC_VER = or > than this will conflict with CDC-openssh < or = 5.2.2

INSTALLED_VER=""
CUR_VER=""              ### core package currently installed version (short, no build bumber)
CDC_CUR_VER_FULL=""     ### cache upgrade needs full current version
CDC_CUR_CHECK_SUM=""    ### the cache dictionary checksum of currently installed version
CDA_VER=""              ### version of DirectAudit to be installed
SAMBA_VER=""
OPENSSH_OLD=""
SAMBA_PKGFILE=""
OPENSSH_PKGFILE=""

DEBUG="off"
DEBUG_OUT="/dev/null"   ### set by log_header() to =${LOG_FILE} if DEBUG=on (--debug)
TRUE=0			### shell uses negative logic.
FALSE=1
DELAY=15		### default reboot delay
REBOOT_CMD=/sbin/reboot ### reboot command
LINUX_OPTION=""
FORCE_OPTION=""
# some platforms have /bin/sh pointing to bash
ECHO_FLAG="-e" # bash
if [ -n "`echo -e "\n"`" ]; then ECHO_FLAG=""; fi
SEP="-"                 ### "." on AIX, CentrifyDC.core
TARGET_OS="unknown"
OS_REV="unknown"
ARCH="unknown"
OS_MODE=""
PKG_OS_REV="unknown"
FORCE_PKG_OS_REV=""
PKG_ARCH="unknown"
PKG_FILE=""
PKG_FILE_LIST=""
PKG_I_LIST=""           ### install list
PKG_I2_LIST=""          ### second round install list
PKG_E_LIST=""           ### erase list
PKG_DIR=""
BUNDLE_MODE="N"
CONTINUE=""
ORG_UMASK=""
X_OPTION_LIST=""
INIT_DIR=/etc/init.d
PID=$$
VAR=/var
VAR_TMP=${VAR}/centrify/install-tmp${PID}
LOG_FILE_DEF=${VAR}/log/centrifydc-install.log
LOG_FILE=""
PKGADD_LOG=${VAR_TMP}/pkgadd.log
SWCOPY_LOG=${VAR_TMP}/swcopy.log
SWINSTALL_LOG=${VAR_TMP}/swinstall.log
ADMIN_FILE=${VAR_TMP}/centrifydc-admin    ### need on solaris only
# ADMIN_FILE default installation actions (See admin(4))
# quit - abort installation if checking fails.
# nocheck - do not check.
ADMIN_IDEPEND=quit      ### the package to be installed depends on others
ADMIN_RDEPEND=quit      ### other packages depend on the package to be removed
ADMIN_CONFLICT=quit     ### file conflict between packages
ADD_ON_LIST="nis openssh krb5 web apache ldapproxy samba idmap adbindproxy db2 cda" # add krb5lib on AIX, add adfixid on Mac
CFG_FNAME="centrifydc-install.cfg"
CFG_FNAME_SUITE_DEF="centrify-suite.cfg"
CFG_FNAME_SUITE=""
COMPAT_LINK_LIST=""
DARWIN_PKG_NAME="new"
# Signals need to be caught: 1=SIGHUP 2=SIGINT 3=SIGQUIT 15=SIGTERM
SIGNAL_LIST="1 2 3 15"
#CHECK_ADCLIENT="/usr/share/centrifydc/bin/centrifydc status | grep \"is running\""
PS_OPTIONS="-ef"
CHECK_ADCLIENT="ps ${PS_OPTIONS} | grep -w adclient | grep -v tmp | grep -v grep"

### regular defaults, set_silent_cfg() overrides some variables
SILENT="NO"
OVERRIDE="N"
CLI_OPTIONS=            ### CLI options to override .cfg
QUESTION=
INPUT=
SUPPORTED=N             ### core package available for install or upgrade
SUPPORTED_PL=$FALSE     ### platform is supported
INSTALLED=
IS_AUDITING=$FALSE
INSTALL=
UNINSTALL=              ### Uninstall of all packages including add-on(s), works with INSTALL="E" only
GLOBAL_ZONE_ONLY="non_global"  ### Solaris 10 -G option, "Y" means install in global zone only
IPS=                    ### Solaris 11 or above support IPS package
INSTALLED_GZ_ONLY=      ### how CDC is installed
SUITE="Custom"
SILENT_SUITE_OPT=""
OS_CHECK=               ### option to skip initial OS check
ADCHECK=""
ADCHECK_FNAME="adcheck"
ADCHECK_RC="0"
EXPRESS_PL=$FALSE       ### platform supports express mode
EXPRESS=
ADLICENSE="Y"
ADJOINED=
ADJOIN=
ADJOIN_CMD_OPTIONS=
ADJ_LIC=                ### adjoin license type (-t,--licensetype server/workstation)
ADJ_FORCE=              ### forced adjoin (--force)
ADJ_TRUST=              ### "Trust for delegation" (--trust)
DOMAIN=
USERID=administrator    ### default Active Directory user
PASSWD=
COMPUTER=`hostname`
CONTAINER=Computers
ZONE=
SERVER=
DA_ENABLE=
DA_INST_NAME=
REBOOT=
DIR_LIST=
ENTERPRISE_PL=$FALSE

#keep track of whether the dsplugin has been enabled already
DSPLUGIN_HAS_BEEN_ENABLED=0

### return codes
CODE_SIN=0 # Successful install
CODE_SUP=0 # Successful upgrade
CODE_SUN=0 # Successful uninstall
CODE_NIN=24 # Did nothing during install
CODE_NUN=25 # Did nothing during uninstall
CODE_EIN=26 # Error during install
CODE_EUP=27 # Error during upgrade
CODE_EUN=28 # Error during uninstall
CODE_ESU=29 # Error during setup e.g. wrong UID, wrong platform, invalid number of arguments
CODE_SIG=30 # Signal received and therefore terminate

DATE_LIST="/bin/date /usr/bin/date /usr/xpg4/bin/date /sbin/date"
for i in ${DATE_LIST}
do
    if [ -x $i ]; then DATE=$i; break; fi
done

#SIP (System Integration Protection) is only for Mac for now
if [ `uname` = "Darwin" ];then
    USRBIN=/usr/local/bin
    USRSBIN=/usr/local/sbin
    DATADIR=/usr/local/share
else
    USRBIN=/usr/bin
    USRSBIN=/usr/sbin
    DATADIR=/usr/share
fi


set_custom_rc ()
{
    CODE_SIN=21 # Successful install
    CODE_SUP=22 # Successful upgrade
    CODE_SUN=23 # Successful uninstall
}

list_compat_os_rev ()
{
    # return a list of compatible OS_REV
    case "$1" in
        deb5)
            echo "deb3.1 deb3" ;;
        deb6)
            echo "deb5" ;;
        rhel3)
            echo "rh9" ;;
        rhel4)
            echo "rhel3" ;;
        suse10)
            echo "suse8 suse9" ;;
        10.5)
            echo "10.4" ;;
        aix5.3)
            echo "aix5.1" ;;
        aix6.1)
            echo "aix5.3" ;;
    esac
}

add_utest ()
{
    ADD_ON_LIST="${ADD_ON_LIST} utest"
}

### Check that this script is being run by a superuser (root)
uid_check()
{
    id | grep uid=0 > /dev/null
    if [ "$?" != "0" ]; then
        echo ERROR: Only the superuser can run this script.
        echo Exiting ...
        exit $CODE_ESU
    fi
    return $TRUE
}

### create and verify dir
create_verify_dir()
{
    CREATE_DIR="$1"
    if [ ! -d ${CREATE_DIR} ]; then
        rm -rf ${CREATE_DIR}
        mkdir ${CREATE_DIR}
    fi
    if [ ! -d ${CREATE_DIR} ]; then
        echo $ECHO_FLAG "\nERROR: Could not create ${CREATE_DIR}." | tee -a ${LOG_FILE}
        do_error $CODE_EIN
    fi
    if [ -h ${CREATE_DIR} ]; then
        echo $ECHO_FLAG "\nERROR: ${CREATE_DIR} is a symbolic link, directory is expected." | tee -a ${LOG_FILE}
        do_error $CODE_EIN
    fi
    if [ "`ls -ldn ${CREATE_DIR} | awk '{print $3}'`" != "0" ]; then
        echo $ECHO_FLAG "\nERROR: ${CREATE_DIR} must be owned by root." | tee -a ${LOG_FILE}
        do_error $CODE_EIN
    fi
    chmod 755 ${CREATE_DIR}
}

### disable watchdog before stopping adclient
disable_cdcwatch()
{
    CDCWATCH_PID=`ps ${PS_OPTIONS} | grep -w cdcwatch | grep -v tmp | grep -v grep | awk '{ print $2 }'`
    test -n "$CDCWATCH_PID" && kill $CDCWATCH_PID >> ${LOG_FILE} 2>> ${LOG_FILE}
}

### remove adclient pid file
remove_adclient_pid_file()
{
    rm -f /var/run/adclient.pid
}

### make sure we are not in sparse root zone (solaris 10)
detect_sparse()
{
    case ${OS_REV} in
    sol1* )
        if [ "$IPS" != "Y" ] && \
            [ -x /usr/sbin/zoneadm ] && [ "${GLOBAL_ZONE_ONLY}" = "non_global" ]; then
            PART_LIST="/usr /lib /var /etc"
            ERR=0
            for i in ${PART_LIST}
            do
                if [ `mount | grep -v 'read/write' | grep "^$i " > /dev/null; echo $?` -eq 0 ]; then
                    echo "ERROR: $i is a read-only resource" | tee -a ${LOG_FILE}
                    ERR=1
                fi
            done
            if [ "${ERR}" = "1" ];then
                echo "ERROR: This is a sparse root zone (it has read-only resource)." | tee -a ${LOG_FILE}
                echo "       Centrify DirectControl can be installed in a global or " | tee -a ${LOG_FILE}
                echo "       whole root non-global zones only. Exiting ..."           | tee -a ${LOG_FILE}
                exit $CODE_ESU
            fi
        fi
        ;;
    esac
    return $TRUE
}

detect_joined_zone()
{
    # check if it's Solaris 10+, global zone and installed in all zones
    if [ -x /usr/sbin/zoneadm ] && [ "`zonename`" = "global" ] && [ -f /var/sadm/install/gz-only-packages ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: detect_joined_zone: " >> ${LOG_FILE}
        # is_installed_gz_only() cannot be used because it exits
        cat /var/sadm/install/gz-only-packages | grep -v '#' | grep -v CentrifyDC- | grep CentrifyDC > /dev/null; RC=$?
        if [ ${RC} -eq 0 ]; then
            # installed in global zone only
            echo "\nINFO: Centrify DirectControl is installed in the global zone only." >> ${LOG_FILE}
            return $FALSE
        fi
        # installed in all zones
        for SOL_ZONE in `/usr/sbin/zoneadm list -c`
        do
            ZONE_PATH="`/usr/sbin/zoneadm -z ${SOL_ZONE} list -p | cut -d: -f4`"
            if [ "${ZONE_PATH}" != "/" ] && [ -d ${ZONE_PATH}/root/var/centrifydc ]; then
#                /usr/sbin/mount | grep "${ZONE_PATH}/root/usr" | grep -v "read/write" > /dev/null; RC1=$?
#                /usr/sbin/mount | grep "${ZONE_PATH}/root/lib" | grep -v "read/write" > /dev/null; RC2=$?
#                if [ $RC1 -eq 0 ] || [ $RC2 -eq 0 ]; then
                if [ -s ${ZONE_PATH}/root/var/centrifydc/kset.domain ]; then
                    echo "\nERROR: Could not uninstall Centrify DirectControl from non-global zone." | tee -a ${LOG_FILE}
                    echo "       Please run 'adleave' in zone <${SOL_ZONE}> first."                  | tee -a ${LOG_FILE}
                    do_error $CODE_NUN
                fi
#                fi
            fi
        done
    fi
    return $FALSE # not Solaris 10+ or no joined sparse zones
} # detect_joined_zone()

### check if CDC is installed in global zone only (solaris 10+)
is_installed_gz_only()
{
    echo "is_installed_gz_only: `${DATE}`" >> ${LOG_FILE}
    case ${OS_REV} in
        sol1* )
            if [ -f /var/sadm/install/gz-only-packages ] && [ "${GLOBAL_ZONE_ONLY}" != "non_global" ]; then
                cat /var/sadm/install/gz-only-packages | grep -v '#' | grep -v CentrifyDC- | grep CentrifyDC > /dev/null; RC=$?
                if [ ${RC} -eq 0 ]; then
                    # installed in global zone only
                    if [ "${SILENT}" = "NO" ]; then
                        echo "\nWARNING: Centrify DirectControl is installed in the global zone only."        | tee -a ${LOG_FILE}
                        echo "         If you continue (C|Y), all packages will be installed (upgraded)"      | tee -a ${LOG_FILE}
                        echo "         in the global zone only. If you want to install in all zones you"      | tee -a ${LOG_FILE}
                        echo "         must remove the existing package from the global zone first and"       | tee -a ${LOG_FILE}
                        echo "         then restart installation."                                            | tee -a ${LOG_FILE}
                        QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
                        if [ "${ANSWER}" != "Y" ]; then
                            do_quit
                        else
                            GLOBAL_ZONE_ONLY="Y"
                        fi
                    else
                        # silent mode
                        if [ "${GLOBAL_ZONE_ONLY}" = "N" ]; then
                            echo "\nERROR: Centrify DirectControl is installed in the global zone only."        | tee -a ${LOG_FILE}
                            echo "       GLOBAL_ZONE_ONLY is set to \"N\" which means to install in all zones." | tee -a ${LOG_FILE}
                            echo "       If you want to install in all zones you must remove the existing"      | tee -a ${LOG_FILE}
                            echo "       package from the global zone first and then restart installation."     | tee -a ${LOG_FILE}
                            echo "       Exiting ..."      | tee -a ${LOG_FILE}
                            do_error $CODE_ESU
                        fi
                    fi
                    return $TRUE # installed in global zone only
                else
                    echo "\nINFO: DirectControl is installed in all zones." | tee -a ${LOG_FILE}
                fi
            fi
            ;;
    esac
    return $FALSE # installed in all zones
} # is_installed_gz_only()

### make sure umask is to 002 or 022
umask_check()
{
    if [ "${TARGET_OS}" = "solaris" ]; then 
        UMASK="`umask`"
        case "${UMASK}" in
        "000"* | "002"* | "022")
            echo ${ECHO_FLAG} "INFO: current umask: ${UMASK}" >> ${LOG_FILE}
            ORG_UMASK=""
            ;;
        *)
            echo ${ECHO_FLAG} "WARNING: current umask: ${UMASK}" >> ${LOG_FILE}
            ORG_UMASK="${UMASK}"
            ;;
        esac

    fi
    return $TRUE
}

### restore umask to the original if it was changed
umask_restore()
{
    if [ "${TARGET_OS}" = "solaris" ]; then
        if [ "${ORG_UMASK}" != "" ]; then
            umask ${ORG_UMASK}
            ORG_UMASK=""
            echo ${ECHO_FLAG} "INFO: restoring umask to the original: `umask`" >> ${LOG_FILE}
        fi 
    fi
    return $TRUE
}

debug_echo ()
{
    if [ "${DEBUG}" = "on" ]; then
        echo ${ECHO_FLAG} "DEBUG: $1" >> ${LOG_FILE}
    fi
    return $TRUE
}

remove_last_0()
{
    case "$1" in
    *.0 )
        echo "$1" | sed 's/\.0$//'
        return 0
        ;;
    esac
    echo "$1"
    return 1
}

normalize_version()
{
    REDUCED=$1
    while REDUCED="`remove_last_0 \"$REDUCED\"`" ; do :; done
    echo "$REDUCED"
}

detect_esx()
{
    if vmware -v 2> /dev/null |grep "VMware ESX Server" >/dev/null; then
        echo ${ECHO_FLAG} "DEBUG: vmware -v:\n`vmware -v`" >> ${LOG_FILE}
        REVISION=`vmware -v |awk '{print $(4)}'`
    elif vmware -v 2> /dev/null |grep "VMware ESX " >/dev/null; then
        echo ${ECHO_FLAG} "DEBUG: vmware -v:\n`vmware -v`" >> ${LOG_FILE}
        REVISION=`vmware -v |awk '{print $(3)}'`
    elif grep -s "VMware ESX Server" /etc/issue > /dev/null; then
        echo ${ECHO_FLAG} "DEBUG: /etc/issue:\n`cat /etc/issue`" >> ${LOG_FILE}
        REVISION=`awk '/^VMware ESX Server/ {seen = 1; print $(4)} END {if (seen == 1) exit 1}' /etc/issue`
    elif [ -f /etc/vmware-release ]; then
        echo ${ECHO_FLAG} "DEBUG: /etc/vmware-release:\n`cat /etc/vmware-release`" >> ${LOG_FILE}
        RELEASE="`cat /etc/vmware-release`"
        case "${RELEASE}" in
        "VMware ESX Server 3"* )
            cat /etc/vmware-release | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        esac
        return $TRUE
    else
        return $FALSE
    fi
    
    REVISION="`normalize_version \"$REVISION\"`"
    case "$REVISION" in
    2.1.2 | 2.5 | 2.5.* | 3 | 3.0.[1-2] )
        echo ERROR: ESX ${REVISION} is not supported anymore. Exiting... | tee -a ${LOG_FILE}
        do_error $CODE_ESU;;
    3.5 | 3.5.* )
        PKG_OS_REV=rhel4
        OS_REV=esx3.5;;
    3.* )
        PKG_OS_REV=rhel4
        OS_REV=esx3;;           
    4 | 4.* )
        PKG_OS_REV=rhel4
        OS_REV=esx4;;
    esac
    return $TRUE
}

### Detect LINUX version (if OS kernel is unknown)
detect_linux ()
{
    if detect_esx ; then
        :
    elif [ -f /etc/enterprise-release ] || [ -f /etc/redhat-release -a -f /etc/oracle-release ]; then
        if [ -f /etc/enterprise-release ]; then
            echo ${ECHO_FLAG} "DEBUG: /etc/enterprise-release:\n`cat /etc/enterprise-release`" >> ${LOG_FILE}
            RELEASE="`cat /etc/enterprise-release`"
        else
            echo ${ECHO_FLAG} "DEBUG: /etc/oracle-release:\n`cat /etc/oracle-release`" >> ${LOG_FILE}
            echo ${ECHO_FLAG} "DEBUG: /etc/redhat-release:\n`cat /etc/redhat-release`" >> ${LOG_FILE}
            RELEASE="`cat /etc/redhat-release`"
        fi
        case "${RELEASE}" in
        *"Enterprise Linux"*"release 4"*)
            PKG_OS_REV=rhel4
            OS_REV=oracle4;;
        *"Enterprise Linux"*"release 5"*)
            PKG_OS_REV=rhel4
            OS_REV=oracle5;;
        *"Enterprise Linux"*"release 6"*)
            PKG_OS_REV=rhel4
            OS_REV=oracle6;;
        *"Enterprise Linux"*"release 7"*)
            PKG_OS_REV=rhel4
            OS_REV=oracle7;;
        esac
    elif [ -f /etc/redhat-release ]; then
        echo ${ECHO_FLAG} "DEBUG: /etc/redhat-release:\n`cat /etc/redhat-release`" >> ${LOG_FILE}
        DESKTOP=""
        if [ -n "`cat /etc/redhat-release | grep Client`" ]; then
            DESKTOP="d"
        fi
        RELEASE="`cat /etc/redhat-release`"
        case "${RELEASE}" in
        "Red Hat Linux release 7.2"* | "Red Hat Linux release 7.3"* | \
        "Red Hat Linux release 8"*   | "Red Hat Linux release 9"*   | \
        "Red Hat Enterprise Linux"*"release 2.1"* | "Red Hat Linux Advanced Server release 2.1AS"* | \
        "Red Hat Enterprise Linux"*"release 3"*)
            cat /etc/redhat-release | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        *"Enterprise Linux"*"release 4"*" Update 8)")
            # ignore this line but do not change or delete it "
            PKG_OS_REV=rhel4
            OS_REV=rhel4.8;;
        *"Enterprise Linux"*"release 4"*" Update 9)")
            # ignore this line but do not change or delete it "
            PKG_OS_REV=rhel4
            OS_REV=rhel4.9;;
        *"Enterprise Linux"*"release 4"*)
            PKG_OS_REV=rhel4
            OS_REV=rhel4;;
        *"Enterprise Linux"*"release 5"*)
            PKG_OS_REV=rhel4
            OS_REV=rhel${DESKTOP}5;;
        *"Enterprise Linux"*"release 6"*)
            PKG_OS_REV=rhel4
            OS_REV=rhel${DESKTOP}6;;
        *"Enterprise Linux"*"release 7"*)
            PKG_OS_REV=rhel4
            OS_REV=rhel${DESKTOP}7;;
        "Fedora Core release 2"* | "Fedora Core release 3"* | "Fedora Core release 4"* | "Fedora Core release 5"* | \
        "Fedora Core release 6"* | "Fedora"*"release 7"*    | "Fedora"*"release 8"*    | "Fedora"*"release 9"*    | \
        "Fedora"*"release 10"*   | "Fedora"*"release 11"*   | "Fedora"*"release 12"*   | "Fedora"*"release 13"* )
            cat /etc/redhat-release | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        "Fedora"*"release 14"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc14;;
        "Fedora"*"release 15"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc15;;
        "Fedora"*"release 16"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc16;;
        "Fedora"*"release 17"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc17;;
        "Fedora"*"release 18"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc18;;
        "Fedora"*"release 19"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc19;;
        "Fedora"*"release 20"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc20;;
        "Fedora"*"release 21"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc21;;
        "Fedora"*"release 22"*)
            PKG_OS_REV=rhel4
            OS_REV=rhfc22;;
        "CentOS release 3.8"* | "CentOS release 3.9"* )
            cat /etc/redhat-release | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        "CentOS release 4"*)
            PKG_OS_REV=rhel4
            OS_REV=centos4;;
        "CentOS release 5"*)
            PKG_OS_REV=rhel4
            OS_REV=centos5;;
        "CentOS Linux release 6"* | "CentOS release 6"*)
            PKG_OS_REV=rhel4
            OS_REV=centos6;;
        "CentOS Linux release 7"* | "CentOS release 7"*)
            PKG_OS_REV=rhel4
            OS_REV=centos7;;
        "Scientific Linux"*"release 3.0.8"* | "Scientific Linux"*"release 3.0.9"* )
            cat /etc/redhat-release | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        "Scientific Linux"*"release 4"*)
            PKG_OS_REV=rhel4
            OS_REV=scientific4;;
        "Scientific Linux"*"release 5"*)
            PKG_OS_REV=rhel4
            OS_REV=scientific5;;
        "Scientific Linux"*"release 6"*)
            PKG_OS_REV=rhel4
            OS_REV=scientific6;;
        "Scientific Linux"*"release 7"*)
            PKG_OS_REV=rhel4
            OS_REV=scientific7;;
        "Mandriva Linux release 2008"*)
            ### PKG_OS_REV=rhel3
            ### OS_REV=mdv2008;;
            echo ERROR: Mandriva Linux 2008 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        "Mandriva Linux release 2009"*)
            PKG_OS_REV=rhel4
            OS_REV=mdv2009;;
        "Mandriva Linux release 2010"*)
            PKG_OS_REV=rhel4
            OS_REV=mdv2010;;
        "Mandriva Linux release 2011"*)
            PKG_OS_REV=rhel4
            OS_REV=mdv2011;;
        "Mandriva Linux release 2012"*)
            PKG_OS_REV=rhel4
            OS_REV=mdv2012;;
        "Mandriva Linux Enterprise Server release 5"*)
            PKG_OS_REV=rhel4
            OS_REV=mdves5;;
        "XenServer release 4"*"xenenterprise"*)
            PKG_OS_REV=rhel4
            OS_REV=xen4;;
        "XenServer release 5"*"xenenterprise"*)
            PKG_OS_REV=rhel4
            OS_REV=xen5;;
        "XenServer release 6"*"xenenterprise"*)
            PKG_OS_REV=rhel4
            OS_REV=xen6;;
        *)
            if [ -f /etc/system-release ]; then
                echo ${ECHO_FLAG} "DEBUG: /etc/system-release:\n`cat /etc/system-release`" >> ${LOG_FILE}
                RELEASE1="`cat /etc/system-release`"
                case "${RELEASE1}" in
                "Amazon Linux AMI release 1"*)
                    PKG_OS_REV=rhel4
                    OS_REV=amazon;;
                "Amazon Linux AMI"*)
                    PKG_OS_REV=rhel4
                    OS_REV=amazon;;
                esac
            fi
            ;;
        esac
    elif [ -f /etc/SuSE-release ]; then
        echo ${ECHO_FLAG} "DEBUG: /etc/SuSE-release:\n`cat /etc/SuSE-release`" >> ${LOG_FILE}
        OPEN=""
        DESKTOP=""
        if [ -n "`cat /etc/SuSE-release | grep open`" ]; then
            OPEN="open"
        elif [ -n "`cat /etc/SuSE-release | grep Desktop`" ]; then
            DESKTOP="d"
        else
            echo ${ECHO_FLAG} "checking if release rpm is installed..." >> ${LOG_FILE}
            rpm -q "sles-release" >> ${LOG_FILE} 2>> ${LOG_FILE}
            rpm -q "sled-release" >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ $? -eq 0 ]; then
                DESKTOP="d"
            fi
        fi
        RELEASE="`grep VERSION /etc/SuSE-release | sed s'/VERSION = //'`"
        RELEASE="`normalize_version \"$RELEASE\"`"
        if [ -z "$OPEN" ]; then
            if [ -n "$DESKTOP" ]; then
                case "${RELEASE}" in
                8 | 8.* | 9 | 9.* )
                    ### PKG_OS_REV=suse8
                    ### OS_REV=suse${DESKTOP}${RELEASE}
                    echo "ERROR: SuSE Desktop ${RELEASE} is not supported anymore. Exiting..." | tee -a ${LOG_FILE}
                    do_error $CODE_ESU;;
                10 | 10.* )
                    PKG_OS_REV=suse10
                    OS_REV=suse${DESKTOP}10;;
                11 | 11.* )
                    PKG_OS_REV=suse10
                    OS_REV=suse${DESKTOP}11;;
                12 | 12.* )
                    PKG_OS_REV=suse10
                    OS_REV=suse${DESKTOP}12;;
                esac
            else
                case "${RELEASE}" in
                8 | 8.* )
                    ### OS_REV=suse8;;
                    echo "ERROR: SuSE ${RELEASE} is not supported anymore. Exiting..." | tee -a ${LOG_FILE}
                    do_error $CODE_ESU;;
                9 | 9.* )
                    ### PKG_OS_REV=suse8
                    ### OS_REV=suse9;;
                    echo "ERROR: SuSE ${RELEASE} is not supported anymore. Exiting..." | tee -a ${LOG_FILE}
                    do_error $CODE_ESU;;
                10 | 10.* )
                    PKG_OS_REV=suse10
                    OS_REV=suse10;;
                11 | 11.* )
                    PKG_OS_REV=suse10
                    OS_REV=suse11;;
                12 | 12.* )
                    PKG_OS_REV=suse10
                    OS_REV=suse12;;
               esac
            fi
        else
            case "${RELEASE}" in
            10 | 10.* )
                ### PKG_OS_REV=suse8
                ### OS_REV=opensuse${RELEASE};;
                echo "ERROR: openSUSE ${RELEASE} is not supported anymore. Exiting..." | tee -a ${LOG_FILE}
                do_error $CODE_ESU;;
            11 | 11.* )
                PKG_OS_REV=suse10
                OS_REV=opensuse11;;
            12 | 12.* )
                PKG_OS_REV=suse10
                OS_REV=opensuse12;;
            13 | 13.* )
                PKG_OS_REV=suse10
                OS_REV=opensuse13;;
            esac
        fi
    elif [ -f /etc/UnitedLinux-release ]; then
        echo ${ECHO_FLAG} "DEBUG: /etc/UnitedLinux-release:\n`cat /etc/UnitedLinux-release`" >> ${LOG_FILE}
        RELEASE="`cat /etc/UnitedLinux-release | grep VERSION`"
        case "${RELEASE}" in
        "VERSION = 1."*)
            ### OS_REV=suse8;;
            echo "ERROR: UnitedLinux ${RELEASE} is not supported anymore. Exiting..." | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        esac
    elif [ -f /etc/lsb-release ]; then
        echo ${ECHO_FLAG} "INFO: /etc/lsb-release:\n`cat /etc/lsb-release`" >> ${LOG_FILE}
        if [ "`grep DISTRIB_ID /etc/lsb-release | sed 's/DISTRIB_ID=//'`" = "LinuxMint" ]; then
            # Linux Mint
            RELEASE="`grep DISTRIB_RELEASE /etc/lsb-release | sed 's/DISTRIB_RELEASE=//'`"
            case "${RELEASE}" in
            12 | 14 | 15 | 16 )
                cat /etc/lsb-release | tee -a ${LOG_FILE}
                echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
                do_error $CODE_ESU;;
            esac
            PKG_OS_REV=deb6
            OS_REV=mint${RELEASE}
        else
            # Ubuntu
            if [ "`uname -r | grep generic >> ${LOG_FILE}; echo $?`" = "0" ]; then
                if [ "`uname -r | grep pae >> ${LOG_FILE}; echo $?`" = "0" ]; then
                    KERNEL_CFG="s" # server with Physical Address Extension
                else
                    KERNEL_CFG="d" # desktop
                fi
            else
                KERNEL_CFG="s" # server
            fi
            RELEASE="`grep DISTRIB_RELEASE /etc/lsb-release | sed 's/DISTRIB_RELEASE=//'`"
            RELEASE_YEAR="`echo \"$RELEASE\" | sed -e 's/\..*//'`"
            RELEASE_MONTH="`echo \"$RELEASE\" | sed -e 's/[^\.]*\.//' -e 's/\..*//'`"
            case "${RELEASE_YEAR}" in
            [6-9] | 1[0-5] )
                if [ "$RELEASE_YEAR" = 6 ]; then
                    case "${RELEASE_MONTH}" in
                    0[7-9] | 1[0-2] )
                        RELEASE_YEAR=`expr $RELEASE_YEAR + 1`
                        RELEASE_MONTH=04;;
                    0[1-6] | * )
                        RELEASE_MONTH=06;;
                    esac
                else
                    case "${RELEASE_MONTH}" in
                    1[1-2]* )
                        RELEASE_YEAR=`expr $RELEASE_YEAR + 1`
                        RELEASE_MONTH=04;;
                    0[1-4]* )
                        RELEASE_MONTH=04;;
                    0[5-9]* | 10 | * )
                        RELEASE_MONTH=10;;
                    esac
                fi
                PKG_OS_REV=deb6
                case "${RELEASE_YEAR}" in
                1[2-9] )
                    KERNEL_CFG="s" # server
                    ;;
                esac
                OS_REV=ubuntu${KERNEL_CFG}${RELEASE_YEAR}.${RELEASE_MONTH};;
            esac
        fi # Mint or Ubuntu

        case "${OS_REV}" in
        ubuntud6.06 | ubuntus6.06 | "ubuntud7."* | "ubuntus7."* | \
        "ubuntud8."* | "ubuntus8."* | "ubuntud9."* | "ubuntus9."* | \
        "ubuntud10."* | "ubuntus10."* | "ubuntud11."* | "ubuntus11."* | \
        "ubuntud12.10"* | "ubuntus12.10"* | "ubuntud13."* | "ubuntus13."* )
            cat /etc/lsb-release | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        esac
    elif [ -f /etc/debian_version ] && [ "${OS_REV}" = "unknown" ]; then
        echo ${ECHO_FLAG} "DEBUG: /etc/debian_version:\n`cat /etc/debian_version`" >> ${LOG_FILE}
        RELEASE="`cat /etc/debian_version`"
        case "${RELEASE}" in
        "3.0"* | "3.1"* | "4."* | "5."* )
            cat /etc/debian_version | tee -a ${LOG_FILE}
            echo ERROR: Above OS release is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        "6."*)
            OS_REV=deb6;;
        "7."*)
            PKG_OS_REV=deb6
            OS_REV=deb7;;
        "8."*)
            PKG_OS_REV=deb6
            OS_REV=deb8;;
        esac
    elif [ -f /etc/system-release ]; then
        echo ${ECHO_FLAG} "DEBUG: /etc/system-release:\n`cat /etc/system-release`" >> ${LOG_FILE}
        RELEASE1="`cat /etc/system-release`"
        case "${RELEASE1}" in
        "Amazon Linux AMI release 1"*)
            PKG_OS_REV=rhel4
            OS_REV=amazon;;
        "Amazon Linux AMI"*)
            PKG_OS_REV=rhel4
            OS_REV=amazon;;
        esac
    fi
    if [ "${OS_REV}" = "unknown" ]; then return $FALSE; fi
    return $TRUE
} # detect_linux()

### Check 64 bits support on Mac
darwin_support_64bits()
{
    # Is it 64 bits architecture?
    is_64bits=`sysctl -n hw.optional.x86_64 2> /dev/null`
    if [ -n "$is_64bits" ] && [ "$is_64bits" -eq 1 ]; then
        return 0
    fi

    return 1
}

### Detect OS, OS revision, architecture (hardware-platform)
detect_os ()
{
    ### run detect_os only once, if PKG_OS_REV is set already then just return
    if [ "${PKG_OS_REV}" != "unknown" ]; then return ${TRUE}; fi
    if [ "${BUNDLE_MODE}" != "Y" ]; then
        echo Detecting local platform ...
    fi
    case "`uname -s`" in
    Linux*)
        TARGET_OS=linux
        EXPRESS_PL=$TRUE
        log_header
        detect_linux
        if [ "${OS_REV}" = "unknown" ]; then
            echo ERROR: Unknown OS revision: "`uname -r`". Exiting ... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        fi
        if [ "`uname -m`" = "i686" ]; then
            ARCH=i386
        elif [ "`uname -m`" = "ia64" ]; then
            ARCH=ia64
        elif [ "`uname -m`" = "ppc" -o "`uname -m`" = "ppc64" ]; then
            ARCH=ppc
        elif [ "`uname -m`" = "x86_64" ]; then
            ARCH=x86_64
        elif [ "`uname -m`" = "s390x" ]; then
            ARCH=s390x
            case ${OS_REV} in
            rhel5 | rhel6 | rhel7 )
                PKG_OS_REV=rhel5;;
            esac
        else
            echo ERROR: Unknown hardware-platform: "`uname -m`". Exiting ... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        fi
        case ${OS_REV} in
        rhfc2 )
            EXPRESS_PL=$FALSE
        esac
        ;;
    SunOS*)
        TARGET_OS=solaris
        EXPRESS_PL=$TRUE
        REBOOT_CMD=/usr/sbin/reboot
        REVISION="`uname -r`"
        log_header
        if [ "$REVISION" = "5.6" ]; then
            ### OS_REV=sol2.6
            echo ERROR: Solaris 2.6 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "$REVISION" = "5.7" ]; then
            ### OS_REV=sol7
            echo ERROR: Solaris 2.7 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "$REVISION" = "5.8" ]; then
            OS_REV=sol8
        elif [ "$REVISION" = "5.9" ]; then
            OS_REV=sol9
        elif [ "$REVISION" = "5.10" ]; then
            OS_REV=sol10
        elif [ "$REVISION" = "5.11" ]; then
            OS_REV=sol11
        fi
        if [ -r /etc/release ]; then
            REVISION="`grep Solaris /etc/release | awk '{ print $2 }'`"
            case "$REVISION" in
            2008.* )
                OS_REV=sol2008.11;;
            2009.* )
                OS_REV=sol2009.06;;
            Express )
                REVISION="`grep Assembled /etc/release | awk '{ print $NF }'`"
                case "$REVISION" in
                2008 )
                    OS_REV=sol2008.11;;
                2009 )
                    OS_REV=sol2009.06;;
                esac
            esac
            case "${OS_REV}" in
            sol200* )
                echo ERROR: OpenSolaris is not supported anymore. Exiting... | tee -a ${LOG_FILE}
                do_error $CODE_ESU;;
            esac
        fi
        if [ "${OS_REV}" = "unknown" ]; then
            echo ERROR: Unknown OS revision: "$REVISION". Exiting ... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        fi
        if [ "`uname -p`" = "i386" ]; then
            ARCH=x86
            case "${OS_REV}" in
            sol1* )
                PKG_OS_REV=sol9;;
            esac
            isainfo -v | grep 64-bit >> ${LOG_FILE}
            if [ $? -eq 0 ]; then
                ARCH=x86_64
                PKG_ARCH=x86
            fi
        elif [ "`uname -p`" = "sparc" ]; then
            ARCH=sparc
            case "${OS_REV}" in
            sol9 | sol1* )
                PKG_OS_REV=sol8;;
            esac
        else
            echo ERROR: Unknown processor: "`uname -p`". Exiting ... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        fi
        if [ -x /usr/bin/pkg ]; then
            # IPS package manager is found.
            IPS="Y"
            if [ -x /usr/sbin/zoneadm ] && \
                [ "`/usr/sbin/zoneadm list -p | grep 0:global > /dev/null; echo $?`" = "0" ]; then
                ### global zone
                PS_OPTIONS="-f -z global"
                CHECK_ADCLIENT="ps ${PS_OPTIONS} | grep -w adclient | grep -v tmp | grep -v grep"
            fi
            # Do not set GLOBAL_ZONE_ONLY so that there will be no global zone handling on Solaris 11+.
        elif [ -x /usr/sbin/zoneadm ] && \
            [ "`/usr/sbin/zoneadm list -p | grep 0:global > /dev/null; echo $?`" = "0" ]; then
            ### global zone
            PS_OPTIONS="-f -z global"
            CHECK_ADCLIENT="ps ${PS_OPTIONS} | grep -w adclient | grep -v tmp | grep -v grep"
            GLOBAL_ZONE_ONLY="N"
        fi
        ;;
    HP-UX*)
        TARGET_OS=hpux
        LOG_FILE_DEF=/var/adm/syslog/centrifydc-install.log
        REBOOT_CMD=/usr/sbin/reboot
        INIT_DIR=/sbin/init.d
        log_header
        if [ "`uname -r`" = "B.11.00" ]; then
            ### OS_REV=hp11.00
            echo ERROR: HP-UX 11.00 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "`uname -r`" = "B.11.11" ]; then
            OS_REV=hp11.11
        elif [ "`uname -r`" = "B.11.22" ]; then
            ### OS_REV=hp11.22
            echo ERROR: HP-UX 11.22 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "`uname -r`" = "B.11.23" ]; then
            OS_REV=hp11.23
        elif [ "`uname -r`" = "B.11.31" ]; then
            EXPRESS_PL=$TRUE
            OS_REV=hp11.31
            PKG_OS_REV=hp11.23
        else
            echo ERROR: Unknown OS revision: "`uname -r`". Exiting ... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        fi
        if [ -d /tcb ]; then OS_MODE="trusted"; fi
        case "`uname -m`" in
        9000/7* | 9000/8*)
            ARCH=pa;;
        ia64)
            ARCH=ia64;;
        *)
            echo ERROR: Unknown hardware-platform: "`uname -m`". Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        esac
        ;;
    AIX*)
        TARGET_OS=aix
        SEP="."
        REBOOT_CMD=/usr/sbin/reboot
        ADD_ON_LIST=`echo ${ADD_ON_LIST} | sed 's/krb5/krb5 krb5lib/'`
        log_header
        if [ "`uname -rv`" = "3 4" ]; then
            ### OS_REV=aix4.3
            echo ERROR: AIX 4.3 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "`uname -rv`" = "1 5" ]; then
            ### OS_REV=aix5.1
            echo ERROR: AIX 5.1 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "`uname -rv`" = "2 5" ]; then
            ### PKG_OS_REV=aix5.1
            ### OS_REV=aix5.2
            echo ERROR: AIX 5.2 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "`uname -rv`" = "3 5" ]; then
            #OS_REV=aix5.3
            echo ERROR: AIX 5.3 is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        elif [ "`uname -rv`" = "1 6" ]; then
            OS_REV=aix6.1
        elif [ "`uname -rv`" = "1 7" ]; then
            EXPRESS_PL=$TRUE
            PKG_OS_REV=aix6.1
            OS_REV=aix7.1
        else
            echo ERROR: unknown OS revision: "`uname -rv`". Exiting ... | tee -a ${LOG_FILE}
            do_error $CODE_ESU
        fi
        if [ "${OS_REV}" = "aix4.3" ]; then
            ARCH=ppc
        else
            if [ "`uname -p`" = "powerpc" ]; then
                ARCH=ppc
            else
                echo ERROR: Unknown hardware-platform: "`uname -p`". Exiting ... | tee -a ${LOG_FILE}
                do_error $CODE_ESU
            fi
        fi
        ;;
    IRIX*)
        ### TARGET_OS=irix
        echo ERROR: IRIX OS is not supported anymore. Exiting... 
        do_error $CODE_ESU
        ;;
    Darwin*)
        TARGET_OS=darwin
        EXPRESS_PL=$TRUE
        VAR=/private/var
        VAR_TMP=/private/var/centrify/install-tmp${PID}
        LOG_FILE_DEF=/private/var/log/centrifydc-install.log
        ADD_ON_LIST="${ADD_ON_LIST} adfixid"
        log_header
        SERVER=""
        sw_vers -productName | grep Server > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            SERVER="s"
        fi
        
        echo "INFO: Full Mac OS version: `sw_vers -productVersion`" >> ${LOG_FILE}
        PRODUCT_VERS=`sw_vers -productVersion | cut -d '.' -f1,2`
        case "$PRODUCT_VERS" in
        10.[2-7] | 10.[2-7].* )
            echo ERROR: Mac OS version $PRODUCT_VERS is not supported anymore. Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        10.[89] | 10.[89].* | 10.1[01] | 10.1[01].*)
            PKG_OS_REV=10.8
            OS_REV=${PRODUCT_VERS}${SERVER};;
        *)
            echo ERROR: unknown OS revision: "$PRODUCT_VERS". Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        esac
        SERVER=""
        case "`uname -p`" in
        powerpc)
            ARCH=ppc;;
        i386)
            if darwin_support_64bits; then
                ARCH=x86_64
            else
                ARCH=i386
            fi
            ;;
        *)
            echo ERROR: Unknown hardware-platform: "`uname -p`". Exiting... | tee -a ${LOG_FILE}
            do_error $CODE_ESU;;
        esac
        ;;
    *)
        echo ERROR: Unknown target OS: "`uname -s`". Exiting ... | tee -a ${LOG_FILE}
        do_error $CODE_ESU;;
    esac
    if [ "${PKG_OS_REV}" = "unknown" ]; then PKG_OS_REV=${OS_REV}; fi
    if [ "${PKG_ARCH}" = "unknown" ]; then PKG_ARCH=${ARCH}; fi
    ADCHECK_FNAME="adcheck-${PKG_OS_REV}-${PKG_ARCH}"
    if [ "${TARGET_OS}" = "darwin" ]; then ADCHECK_FNAME="adcheck-mac${PKG_OS_REV}"; fi
    if [ "${FORCE_PKG_OS_REV}" != "" ]; then
        if [ "${TARGET_OS}" != "darwin" ] || \
           [ "${OS_REV}" != "10.6" -a "${OS_REV}" != "10.6s" -a "${OS_REV}" != "10.7" -a "${OS_REV}" != "10.7s" ]; then 
            echo "ERROR: --rev option is not supported on this platform."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU
        fi
    fi
    echo "INFO: TARGET_OS=${TARGET_OS}" >> ${LOG_FILE}
    echo "INFO: OS_REV=${OS_REV}" >> ${LOG_FILE}
    echo "INFO: ARCH=${ARCH}" >> ${LOG_FILE}
    if [ "${EXPRESS_PL}" -eq $TRUE ]; then
        echo "INFO: Express mode is supported" >> ${LOG_FILE}
    else
        echo "INFO: Express mode is not supported" >> ${LOG_FILE}
    fi
} # detect_os()

### WPAR workaround
fix_wpar()
{
    if [ "${TARGET_OS}" != "aix" ] || [ `uname -v` -lt 6 ]; then
        echo $ECHO_FLAG "\nERROR:" | tee -a ${LOG_FILE}
        echo $ECHO_FLAG "WPARs are not supported on `uname -sv` platform.\n" | tee -a ${LOG_FILE}
        do_exit ${CODE_ESU}
    elif [ ! -h /usr/sbin/adjoin ]; then
        echo $ECHO_FLAG "\nERROR:" | tee -a ${LOG_FILE}
        echo $ECHO_FLAG "Could not find /usr/sbin/adjoin." | tee -a ${LOG_FILE}
        echo $ECHO_FLAG "Centrify DirectControl must be installed before using --wpar option.\n" | tee -a ${LOG_FILE}
        do_exit ${CODE_ESU}
    fi
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: fix_wpar: " >> ${LOG_FILE}
    get_cur_version
    if [ "${UNINSTALL}" != "Y" ]; then
        ### install
        if [ `mount | grep " /dev/hd" > /dev/null; echo $?` -eq 0 ]; then
            ### global environment
            if [ "`compare_ver ${CUR_VER} 4.2.2; echo ${COMPARE}`" = "lt" ]; then
                echo "CDC version is less than 4.2.2 so keep /usr/lib/security/methods.cfg in place." >> ${LOG_FILE}
            else
                if [ -h /usr/lib/security/methods.cfg ] && \
                   [ "`ls -l /usr/lib/security/methods.cfg | grep '/etc/centrifydc/methods.cfg'`" != "" ]; then
                    echo $ECHO_FLAG "\nWARNING: /usr/lib/security/methods.cfg is a symlink pointing to" | tee -a ${LOG_FILE}
                    echo $ECHO_FLAG "/etc/centrifydc/methods.cfg and it needs to be fixed!" | tee -a ${LOG_FILE}
                    echo $ECHO_FLAG "To do so please call \"install.sh --fix-methods-cfg\"" | tee -a ${LOG_FILE}
                elif [ ! -h /usr/lib/security/methods.cfg ]; then
                    if [ ! -f /etc/methods.cfg.org ]; then
                        echo "INFO: copying /etc/methods.cfg to /etc/methods.cfg.org" >> ${LOG_FILE}
                        cp -p /etc/methods.cfg /etc/methods.cfg.org
                    elif [ -f /etc/methods.cfg.org ] && [ `diff /etc/methods.cfg.org /etc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
                        echo "INFO: copying /etc/methods.cfg to /etc/methods.cfg.org2" >> ${LOG_FILE}
                        cp -p /etc/methods.cfg /etc/methods.cfg.org2
                    fi
                    echo "INFO: restoring /usr/lib/security/methods.cfg as a symlink pointing to /etc/methods.cfg ..." >> ${LOG_FILE}
                    mv -f /usr/lib/security/methods.cfg /etc/methods.cfg && ln -s /etc/methods.cfg /usr/lib/security/methods.cfg
                    if [ -f /usr/lib/security/methods.cfg.pre_cdc ] || [ -f /usr/lib/security/methods.cfg.pre_cda ] || \
                       [ -f /usr/lib/security/methods.cfg.pre_cdc_wpar ] || [ -f /usr/lib/security/methods.cfg.pre_cdc_wpar2 ]; then
                        mv -f /usr/lib/security/methods.cfg.pre_cd* /etc/
                    fi
                fi
            fi
            echo "copying /etc/centrifydc to /usr/share/centrifydc/wpar ..." >> ${LOG_FILE}
            mkdir -p /usr/share/centrifydc/wpar/etc/centrifydc
            ( cd /etc/centrifydc && tar cf - ./ ) | ( cd /usr/share/centrifydc/wpar/etc/centrifydc && tar xf - )
            cp -f /etc/centrifydc/defaults.conf /usr/share/centrifydc/wpar/etc/centrifydc/centrifydc.conf
            cp -f ${THIS_PRG} /usr/share/centrifydc/bin/fix_wpar.sh
            cp -f ${THIS_PRG} /usr/share/centrifydc/bin/uninstall.sh
            chmod 550 /usr/share/centrifydc/bin/fix_wpar.sh
            if [ ! -d /etc/centrifydc/openldap ]; then
                echo "/etc/centrifydc/openldap doesn't exist, relocating /usr/share/centrifydc/etc/openldap" >> ${LOG_FILE}
                mkdir /etc/centrifydc/openldap
                mv /usr/share/centrifydc/etc/openldap/ldap.conf /etc/centrifydc/openldap
                rm -Rf /usr/share/centrifydc/etc/openldap
                ln -s /etc/centrifydc/openldap /usr/share/centrifydc/etc/openldap
            fi
        elif [ -n "`mount | grep -v ' /dev/' | grep ' /usr ' | grep ro`" ]; then
            ### WPAR environment with read-only /usr
            if [ -f /etc/centrifydc/INSTALLED ]; then
                wpar_pre_rm # upgrade only
            else
                mkdir -p /etc/centrifydc/openldap
                touch /etc/centrifydc/openldap/ldap.conf
                rm -Rf /var/centrifydc/upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
                rm -f /var/centrifydc/INSTALL-START
            fi
            if [ -f /etc/centrifydc/ssh/INSTALLED ]; then
                wpar_pre_rm_ssh # upgrade only
            fi
            echo "copying /usr/share/centrifydc/wpar/etc/centrifydc to /etc/ ..." >> ${LOG_FILE}
            ( cd /usr/share/centrifydc/wpar/etc/centrifydc && tar cf - ./ ) | ( cd /etc/centrifydc && tar xf - )
            if [ "`compare_ver ${CUR_VER} 4.2.2; echo ${COMPARE}`" = "lt" ]; then
                ### /etc/centrifydc/methods.cfg is not needed in WPAR
                echo "CDC version is less than 4.2.2 so disable autoedit." >> ${LOG_FILE}
                cat /etc/centrifydc/centrifydc.conf | grep -v '^#' | grep 'adclient.autoedit.methods:' | grep true > /dev/null 2> /dev/null
                if [ $? -eq 0 ]; then
                    cat /etc/centrifydc/centrifydc.conf | sed '/^[ ]*adclient.autoedit.methods/d' > /etc/centrifydc/centrifydc.conf.tmp
                    mv /etc/centrifydc/centrifydc.conf.tmp /etc/centrifydc/centrifydc.conf
                fi
                cat /etc/centrifydc/centrifydc.conf | grep -v '^#' | grep 'adclient.autoedit.methods:' | grep false > /dev/null 2> /dev/null
                if [ $? -ne 0 ]; then
                    echo "adclient.autoedit.methods: false" >> /etc/centrifydc/centrifydc.conf
                fi
            else
                ### ensure there is /etc/methods.cfg in WPAR
                if [ -f /etc/centrifydc/methods.cfg ]; then
                    echo "WARNING: found /etc/centrifydc/methods.cfg, should use /etc/methods.cfg instead." >> ${LOG_FILE}
                fi
                if [ ! -f /etc/methods.cfg ]; then
                    echo "ERROR: could not find /etc/methods.cfg" >> ${LOG_FILE}
                fi
            fi
            if [ ! -f /etc/centrifydc/INSTALLED ]; then
                wpar_post_i # fresh install only
                touch /etc/centrifydc/INSTALLED
            fi
            wpar_config # install and upgrade
            if [ -d /usr/share/centrifydc/wpar/etc/centrifydc/ssh ]; then
                # install/upgrade CDC-openssh into wpar
                if [ ! -f /etc/centrifydc/ssh/INSTALLED ]; then
                    wpar_post_i_ssh # fresh install only
                    touch /etc/centrifydc/ssh/INSTALLED
                fi
                wpar_config_ssh # install and upgrade
            fi
        fi
    else
        ### pre-uninstall
        if [ -x /usr/sbin/lswpar ] && [ `/usr/sbin/lswpar -q -c -a name > /dev/null 2> /dev/null; echo $?` -eq 0 ]; then
            ### global environment
            WPAR_LIST="`/usr/sbin/lswpar -q -c -a name 2> /dev/null`"
            WPAR_NOT_CLEAN=""
            for WPAR_NAME in ${WPAR_LIST}
            do
                WPAR_DIR="`/usr/sbin/lswpar -q -c -a directory ${WPAR_NAME}`"
                if [ -d ${WPAR_DIR}/etc/centrifydc ] && [ `mount | grep " ${WPAR_DIR}/usr" | grep " ro" > /dev/null; echo $?` -eq 0 ]; then
                    WPAR_NOT_CLEAN="${WPAR_NOT_CLEAN} ${WPAR_NAME}"
                fi
            done
            if [ -n "${WPAR_NOT_CLEAN}" ]; then
                echo "\nERROR: Could not perform WPAR clean-up." | tee -a ${LOG_FILE}
                echo "Please run '/usr/share/centrifydc/bin/uninstall.sh --wpar' in the next WPAR(s):" | tee -a ${LOG_FILE}
                for WPAR_NAME in ${WPAR_NOT_CLEAN}
                do
                    echo "    ${WPAR_NAME}" | tee -a ${LOG_FILE}
                done
                do_error ${CODE_EUN}
            fi
            # /usr/lib/security/methods.cfg should be checked and fixed by .unpost_i (pre-deinstall) script
        elif [ -n "`mount | grep -v ' /dev/' | grep ' /usr ' | grep ro`" ]; then
            ### WPAR environment with read-only /usr
            if [ -f /etc/centrifydc/ssh/INSTALLED ]; then
                wpar_unpost_i_ssh
                wpar_unpre_i_ssh
            fi
            wpar_pre_d
            wpar_unpost_i
            echo "removing /etc/centrifydc and /var/centrifydc ..." >> ${LOG_FILE}
            rm -Rf /etc/centrifydc
            rm -Rf /var/centrifydc
            wpar_unpre_i
        fi
    fi
    if [ "${WPAR}" = "yes" ]; then do_exit 0; fi
    return $TRUE
} # fix_wpar

wpar_pre_rm()
{
    echo "wpar_pre_rm (pre-remove of the old package): `${DATE}`" >> ${LOG_FILE}

    echo "Upgrading from ${CUR_VER} ..." >> ${LOG_FILE}
    mkdir -p /var/centrifydc/upgrade/custom >> ${LOG_FILE}

    echo "preserving centrifydc.conf ..." >> ${LOG_FILE}
    cp -p /etc/centrifydc/*.* /var/centrifydc/upgrade/custom >> ${LOG_FILE}

    STATUS="off"

    # The START file will inform the package script (preinstall)
    # that install.sh is used during the upgrade (and adclient was
    # running). Note that this file will be removed by package
    # script (preinstall) when it checks whether adclient is runnning.
    rm -f /var/centrifydc/upgrade/START

    # The INSTALL-START is used by this install.sh script only. It
    # indicates whether adclient was running before running this
    # script.
    rm -f /var/centrifydc/INSTALL-START

    # CDC-nis
    # stop ypbind if it is started, and remember that
    YP_STOPPED=/tmp/cdc_inst_yp_stopped
    /usr/bin/rm -f $YP_STOPPED
    /usr/bin/lssrc -s ypbind | grep active >> ${LOG_FILE}
    if [ "$?" = "0" ]; then
        echo stopping ypbind ... >> ${LOG_FILE}
        /usr/bin/stopsrc -s ypbind >> ${LOG_FILE}
        /usr/bin/touch $YP_STOPPED
    fi
    mkdir -p /var/centrifydc/nis/upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
    ps -ef | grep /usr/sbin/adnisd | grep -v grep >> ${LOG_FILE}
    if [ "$?" = "0" ]; then
        echo stopping adnisd ... >> ${LOG_FILE}
        /usr/bin/stopsrc -s adnisd >> ${LOG_FILE}
        /usr/bin/touch /var/centrifydc/nis/upgrade/START >> ${LOG_FILE}
    fi

    # CentrifyDC.core
    eval $CHECK_ADCLIENT >> ${LOG_FILE}
    if [ "$?" = "0" ]; then
        echo "stopping adclient ..." >> ${LOG_FILE}
        touch /var/centrifydc/upgrade/START >> ${LOG_FILE}
        touch /var/centrifydc/INSTALL-START >> ${LOG_FILE}
        disable_cdcwatch
        /usr/bin/stopsrc -s centrifydc >> ${LOG_FILE}
    fi
    # remove pid file to avoid cache flush when adclient starts next time
    remove_adclient_pid_file

    # Stop Centrify-KCM if it's running
    if [ -x /usr/share/centrifydc/bin/centrify-kcm ]; then
        /usr/share/centrifydc/bin/centrify-kcm status | grep "is running" >> ${LOG_FILE} 2>> ${LOG_FILE}
        if [ $? -eq 0 ]; then
            echo stop Centrify-KCM by centrify-kcm stop ... >> ${LOG_FILE}
            /usr/share/centrifydc/bin/centrify-kcm stop >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
    fi

    if [ -f /etc/krb5.keytab ] && [ ! -h /etc/krb5.keytab ]; then
        echo "moving /etc/krb5.* into /etc/krb5 dir ..." >> ${LOG_FILE}
        if [ ! -d /etc/krb5 ]; then
            if [ -f /etc/krb5 ]; then mv -f /etc/krb5 /etc/krb5.pre_cdc; fi
            mkdir /etc/krb5
        else
            if [ -h /etc/krb5/krb5.keytab ]; then
                mv -f /etc/krb5/krb5.keytab /etc/krb5/krb5.keytab.pre_cdc
            fi
            if [ -h /etc/krb5/krb5.ccache ]; then
                mv -f /etc/krb5/krb5.ccache /etc/krb5/krb5.ccache.pre_cdc
            fi
        fi
        mv -f /etc/krb5.* /etc/krb5
        ln -s /etc/krb5/krb5.keytab /etc/krb5.keytab
        ln -s /etc/krb5/krb5.ccache /etc/krb5.ccache
    fi

    if [ -s /etc/centrifydc/openldap/ldap.conf ]; then 
        echo "preserving /etc/centrifydc/openldap/ldap.conf ..." >> ${LOG_FILE}
        cp /etc/centrifydc/openldap/ldap.conf /etc/centrifydc/openldap/ldap.conf.cdc_upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
    fi
    return $TRUE
} # wpar_pre_rm

wpar_pre_rm_ssh()
{
    echo "wpar_pre_rm_ssh (pre-remove of the old package): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.openssh | grep CentrifyDC.openssh >> ${LOG_FILE} 2>> ${LOG_FILE}

    SSH_ETC_DIR=/etc/centrifydc/ssh

    # backup previous ssh_config file
    if [ -f ${SSH_ETC_DIR}/ssh_config ]; then
        cp -p ${SSH_ETC_DIR}/ssh_config ${SSH_ETC_DIR}/ssh_config.cdcsave
    fi
    # backup previous sshd_config file
    if [ -f ${SSH_ETC_DIR}/sshd_config ]; then
        cp -p ${SSH_ETC_DIR}/sshd_config ${SSH_ETC_DIR}/sshd_config.cdcsave
    fi

    return $TRUE
} # wpar_pre_rm_ssh

wpar_post_i()
{
    mkdir -p /var/run
    echo "wpar_post_i (post-install): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.core | grep CentrifyDC.core >> ${LOG_FILE} 2>> ${LOG_FILE}

    if [ -f /etc/rc.tcpip ]; then
        if [ ! -f /etc/rc.tcpip.pre_cdc ]; then
            cp /etc/rc.tcpip /etc/rc.tcpip.pre_cdc
        fi
        # CentrifyDC.core
        cat /etc/rc.tcpip | grep CentrifyDC > /dev/null 2> /dev/null
        RC=$?
        if [ "${RC}" != "0" ]; then
            echo "Fixing file /etc/rc.tcpip ..." >> ${LOG_FILE}
            echo ""                                    >> /etc/rc.tcpip
            echo "# Start up CentrifyDC adclient"      >> /etc/rc.tcpip
            echo "\tif [ -n \"\$src_running\" ]; then" >> /etc/rc.tcpip
            echo "\t\tstartsrc -e LIBPATH=/usr/share/centrifydc/lib:/usr/share/centrifydc/kerberos/lib -s centrifydc" >> /etc/rc.tcpip
            echo "\tfi"                                >> /etc/rc.tcpip
            echo "# last CentrifyDC line"              >> /etc/rc.tcpip
        fi
        # CDC-nis
        if [ -f /etc/centrifydc/scripts/functions.adnisd ]; then
            cat /etc/rc.tcpip | grep "Centrify adnisd" > /dev/null 2> /dev/null
            RC=$?
            if [ "${RC}" != "0" ]; then
                echo "Fixing file /etc/rc.tcpip for CentrifyDC adnisd ..." >> ${LOG_FILE}
                echo ""                                    >> /etc/rc.tcpip
                echo "# Start up Centrify adnisd"          >> /etc/rc.tcpip
                echo "\tif [ -n \"\$src_running\" ]; then" >> /etc/rc.tcpip
                echo "\t\tstartsrc -e LIBPATH=/usr/share/centrifydc/lib:/usr/share/centrifydc/kerberos/lib -s adnisd" >> /etc/rc.tcpip
                echo "\tfi"                                >> /etc/rc.tcpip
                echo "# last Centrify adnisd line"         >> /etc/rc.tcpip
            fi
        fi
        # CDC-ldapproxy
        if [ -f /etc/centrifydc/openldap/ldapproxy.slapd.conf ]; then
            cat /etc/rc.tcpip | grep "CentrifyDC ldapproxy" > /dev/null 2> /dev/null
            RC=$?
            if [ "${RC}" != "0" ]; then
                echo "Fixing file /etc/rc.tcpip for CentrifyDC ldapproxy ..." >> ${LOG_FILE}
                echo ""                                    >> /etc/rc.tcpip
                echo "# Start up CentrifyDC ldapproxy"     >> /etc/rc.tcpip
                echo "\tif [ -n \"\$src_running\" ]; then" >> /etc/rc.tcpip
                echo "\t\tstartsrc -e LIBPATH=/usr/share/centrifydc/lib:/usr/share/centrifydc/kerberos/lib -s centrify-ldapproxy" >> /etc/rc.tcpip
                echo "\tfi"                                >> /etc/rc.tcpip
                echo "# last Centrify ldapproxy line"      >> /etc/rc.tcpip
            fi
        fi

    else
        echo "WARNING: Could not find /etc/rc.tcpip."
    fi

    mkssys -s centrifydc -p /usr/sbin/adclient -u 0 -S -n 15 -f 9
    mkssys -s centrify-kcm -p /usr/share/centrifydc/kerberos/sbin/kcm -u 0 -S -n 15 -f 9
    # CDC-nis
    if [ -f /etc/centrifydc/scripts/functions.adnisd ]; then
        mkssys -s adnisd -p /usr/sbin/adnisd -u 0 -a "-d" -S -n 15 -f 9 -R
    fi
    # CDC-ldapproxy
    if [ -f /etc/centrifydc/openldap/ldapproxy.slapd.conf ]; then
        mkssys -s centrify-ldapproxy -p /usr/share/centrifydc/libexec/slapd -u 0 -a "-d 0" -S -n 15 -f 9
    fi

    if [ ! -d /etc/krb5 ]; then mkdir -p /etc/krb5; fi
    if [ -f /etc/krb5.keytab ] && [ ! -h /etc/krb5.keytab ]; then
        echo "moving /etc/krb5.* into /etc/krb5 dir ..." >> ${LOG_FILE}
        mv -f /etc/krb5.* /etc/krb5
    fi
    ln -sf /etc/krb5/krb5.keytab /etc/krb5.keytab
    ln -sf /etc/krb5/krb5.ccache /etc/krb5.ccache

    if [ ! -d /var/krb5/security/creds ]; then mkdir -p /var/krb5/security/creds; fi
    # make sure the directory creds has correct permissions
    chmod 1777 /var/krb5/security/creds

    if [ ! -d /etc/skel ];                then mkdir -p /etc/skel; fi
    if [ ! -f /etc/skel/.profile ];       then ln -s /etc/security/.profile /etc/skel; fi

    # setup the crontab for rotating centrify_client.log
    create_verify_dir "${VAR_TMP}"
    crontab -l |  grep -v "/usr/share/centrifydc/bin/logrotate.sh" > ${VAR_TMP}/cron.$$
    echo "0 0 * * 0-6 /usr/share/centrifydc/bin/logrotate.sh 2>&1 >> /var/log/centrify_logrotate.log"  >> ${VAR_TMP}/cron.$$
    crontab ${VAR_TMP}/cron.$$
    rm -f ${VAR_TMP}/cron.$$

    return $TRUE
} # wpar_post_i

wpar_post_i_ssh()
{
    mkdir -p /var/run
    echo "wpar_post_i_ssh (post-install): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.openssh | grep CentrifyDC.openssh >> ${LOG_FILE} 2>> ${LOG_FILE}

    mkdir -p -m 755 /var/empty > /dev/null 2> /dev/null
    chown root:system /var/empty > /dev/null 2> /dev/null

    lsgroup sshd > /dev/null 2> /dev/null
    STATUS=$?
    if [ ! $STATUS = 0 ]; then
        CDCSSHD_GID=74
        while true; do
            mkgroup id=$CDCSSHD_GID sshd > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                        break
            fi
            if [ $CDCSSHD_GID -gt 999 ]; then
                echo "Warning: Exceeded the GID scope that typically reserved for system accounts."
                echo "Please create group manually."
                break
            fi
            CDCSSHD_GID=`expr $CDCSSHD_GID + 1`
        done
    fi

    lsuser sshd > /dev/null 2> /dev/null
    STATUS=$?
    if [ ! $STATUS = 0 ]; then
        CDCSSHD_UID=74
        while true; do
            mkuser id=$CDCSSHD_UID pgrp=sshd groups=sshd home=/var/empty/sshd login=false sshd > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
            if [ $CDCSSHD_UID -gt 999 ]; then
                echo "Warning: Exceeded the UID scope that typically reserved for system accounts."
                echo "Please create user manually."
                break
            fi
            CDCSSHD_UID=`expr $CDCSSHD_UID + 1`
        done
    fi

    if [ -f /etc/rc.tcpip ]; then
        if [ ! -f /etc/rc.tcpip.pre_cdc ]; then
            cp -p /etc/rc.tcpip /etc/rc.tcpip.pre_cdc
        fi
        cat /etc/rc.tcpip | grep "Centrify sshd" > /dev/null 2> /dev/null
        RC=$?
        if [ "${RC}" != "0" ]; then
            echo "Fixing file /etc/rc.tcpip ..." >> ${LOG_FILE}
            echo ""                                    >> /etc/rc.tcpip
            echo "# Start up Centrify sshd"            >> /etc/rc.tcpip
            echo "\tif [ -n \"\$src_running\" ]; then" >> /etc/rc.tcpip
            echo "\t\tstartsrc -s centrify-sshd"       >> /etc/rc.tcpip
            echo "\tfi"                                >> /etc/rc.tcpip
            echo "# last Centrify sshd line"           >> /etc/rc.tcpip
        else
            echo "Info: No changes made in /etc/rc.tcpip."
        fi
    else
        echo "Warning: Could not find /etc/rc.tcpip."
    fi

    mkssys -s centrify-sshd -p /usr/share/centrifydc/sbin/sshd -u 0 -S -n 15 -f 9 -a "-D" -G tcpip 2>> ${LOG_FILE}

    # add sshd to pam.conf
    grep sshd /etc/pam.conf > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        # adding centrify pam when ad joined
        echo "" >> /etc/pam.conf
        echo "# lines inserted by Centrify OpenSSH" >> /etc/pam.conf
        echo "# sshd" >> /etc/pam.conf
        echo "" >> /etc/pam.conf
        if [ -f /var/centrifydc/kset.domain ]; then
            echo "sshd     auth sufficient         pam_centrifydc" >> /etc/pam.conf
            echo "sshd     auth requisite          pam_centrifydc deny" >> /etc/pam.conf
            echo "sshd     account sufficient      pam_centrifydc" >> /etc/pam.conf
            echo "sshd     account requisite       pam_centrifydc deny" >> /etc/pam.conf
            echo "sshd     password sufficient     pam_centrifydc try_first_pass" >> /etc/pam.conf
            echo "sshd     session required        pam_centrifydc" >> /etc/pam.conf
        fi
        echo "sshd     auth    required        pam_aix" >> /etc/pam.conf
        echo "sshd     account required        pam_aix" >> /etc/pam.conf
        echo "sshd     password  required      pam_aix" >> /etc/pam.conf
        echo "sshd     session required        pam_aix" >> /etc/pam.conf
    fi

    # Generate or import keys
    KEYGEN=/usr/share/centrifydc/bin/ssh-keygen
    RSA1_KEY=/etc/centrifydc/ssh/ssh_host_key
    RSA_KEY=/etc/centrifydc/ssh/ssh_host_rsa_key
    DSA_KEY=/etc/centrifydc/ssh/ssh_host_dsa_key
    ECDSA_KEY=/etc/centrifydc/ssh/ssh_host_ecdsa_key

    STOCK_RSA1_KEY=/etc/ssh/ssh_host_key
    STOCK_RSA_KEY=/etc/ssh/ssh_host_rsa_key
    STOCK_DSA_KEY=/etc/ssh/ssh_host_dsa_key
    STOCK_ECDSA_KEY=/etc/ssh/ssh_host_ecdsa_key

    if [ ! -s $RSA1_KEY ]; then
        if [ -s $STOCK_RSA1_KEY ]; then
            cp $STOCK_RSA1_KEY.pub $RSA1_KEY.pub > /dev/null 2>&1
            cp $STOCK_RSA1_KEY $RSA1_KEY > /dev/null 2>&1
            if [ $? = 0 ]; then
                chmod 600 $RSA1_KEY
                chmod 644 $RSA1_KEY.pub
            fi
        else
            if $KEYGEN -q -t rsa1 -f $RSA1_KEY -C '' -N '' ; then
                chmod 600 $RSA1_KEY
                chmod 644 $RSA1_KEY.pub
            fi
        fi
    fi
    if [ ! -s $RSA_KEY ]; then
        if [ -s $STOCK_RSA_KEY ]; then
            cp $STOCK_RSA_KEY.pub $RSA_KEY.pub > /dev/null 2>&1
            cp $STOCK_RSA_KEY $RSA_KEY > /dev/null 2>&1
            if [ $? = 0 ]; then
                chmod 600 $RSA_KEY
                chmod 644 $RSA_KEY.pub
            fi
        else
            if $KEYGEN -q -t rsa -f $RSA_KEY -C '' -N '' ; then
                chmod 600 $RSA_KEY
                chmod 644 $RSA_KEY.pub
            fi
        fi
    fi
    if [ ! -s $DSA_KEY ]; then
        if [ -s $STOCK_DSA_KEY ]; then
            cp $STOCK_DSA_KEY.pub $DSA_KEY.pub > /dev/null 2>&1
            cp $STOCK_DSA_KEY $DSA_KEY > /dev/null 2>&1
            if [ $? = 0 ]; then
                chmod 600 $DSA_KEY
                chmod 644 $DSA_KEY.pub
            fi
        else
            if $KEYGEN -q -t dsa -f $DSA_KEY -C '' -N '' ; then
                chmod 600 $DSA_KEY
                chmod 644 $DSA_KEY.pub
            fi
        fi
    fi
    if [ ! -s $ECDSA_KEY ]; then
        if [ -s $STOCK_ECDSA_KEY ]; then
            cp $STOCK_ECDSA_KEY.pub $ECDSA_KEY.pub > /dev/null 2>&1
            cp $STOCK_ECDSA_KEY $ECDSA_KEY > /dev/null 2>&1
            if [ $? = 0 ]; then
                chmod 600 $ECDSA_KEY
                chmod 644 $ECDSA_KEY.pub
            fi
        else
            if $KEYGEN -q -t dsa -f $ECDSA_KEY -C '' -N '' ; then
                chmod 600 $ECDSA_KEY
                chmod 644 $ECDSA_KEY.pub
            fi
        fi
    fi

    # Stop existing ssh instances
    /usr/bin/stopsrc -s opensshd > /dev/null 2>&1
    /usr/bin/stopsrc -s sshd > /dev/null 2>&1

    # build-in sshd can not start at boot time
    if [ -f /etc/rc.d/rc2.d/Ksshd ]; then
        mv /etc/rc.d/rc2.d/Ksshd /etc/rc.d/Ksshd.pre_cdcssh
    fi
    if [ -f /etc/rc.d/rc2.d/Ssshd ]; then
        mv /etc/rc.d/rc2.d/Ssshd /etc/rc.d/Ssshd.pre_cdcssh
    fi

    # Check if CDC version < 4.2.0.0, then needs to link /etc/krb5.keytab to /etc/krb5/krb5.keytab.
    # The reason is TOPCAT/POPCAT create krb5.keytab at /etc/krb5.keytab.
    basever="4.2.0.0"
    cdcver=`lslpp -i CentrifyDC.core | grep core | awk '{print $2}'`
    minver=`printf "$basever\n$cdcver\n" | sort | head -1`
    if [ "$minver" = "$cdcver" ]; then
        rm -f /etc/krb5/krb5.keytab
        ln -s /etc/krb5.keytab /etc/krb5/krb5.keytab
    fi

    return $TRUE
} # wpar_post_i_ssh

wpar_config()
{
    echo "wpar_config (post-post-install): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.core | grep CentrifyDC.core >> ${LOG_FILE} 2>> ${LOG_FILE}

    if [ -f /etc/shells ]; then
        grep "\/usr\/bin\/dzsh" /etc/shells > /dev/null
        if [ $? -ne 0 ]; then
            echo "adding /usr/bin/dzsh to /etc/shells ..." >> ${LOG_FILE}
            echo /usr/bin/dzsh >> /etc/shells
        fi
    fi

    if [ -d /var/centrifydc/upgrade ]; then
        echo "Upgrading ..." >> ${LOG_FILE}
        mkdir -p /etc/centrifydc/custom >> ${LOG_FILE}
        cp -p /var/centrifydc/upgrade/custom/* /etc/centrifydc/custom >> ${LOG_FILE}

        # Save new files
        mkdir -p /etc/centrifydc/new >> ${LOG_FILE} 2>&1
        cp -pf /etc/centrifydc/*.* /etc/centrifydc/new/. >> ${LOG_FILE} 2>&1

        # Restore customized files
        cp -pf /etc/centrifydc/custom/*.* /etc/centrifydc/. >> ${LOG_FILE} 2>&1
        
        # Output directory
        rm -rf /etc/centrifydc/merge >> ${LOG_FILE} 2>&1
        mkdir -p /etc/centrifydc/merge >> ${LOG_FILE} 2>&1

        echo "merging centrifydc.conf ..." >> ${LOG_FILE}
        /usr/share/centrifydc/bin/upgradeconf -r -c /etc/centrifydc/new/upgradeconf.conf \
                                                 /etc/centrifydc/custom/centrifydc.conf \
                                                 /etc/centrifydc/new/centrifydc.conf \
                                                 /etc/centrifydc/merge/centrifydc.conf \
                                                 >> ${LOG_FILE} 2>> ${LOG_FILE}

        # If upgrade successfully, update the config files
        if [ $? -eq 0 ] ; then
            echo "Replacing configuration files ..." >> ${LOG_FILE}
            for FILE in /etc/centrifydc/merge/*.* ; do
                if [ -f "$FILE" -a -s "$FILE" ]; then
                    echo "  moving $FILE to /etc/centrifydc/" >> ${LOG_FILE}
                    mv -f "$FILE" /etc/centrifydc/. >> ${LOG_FILE} 2>&1
                fi
            done
            rm -rf /etc/centrifydc/merge >> ${LOG_FILE} 2>&1
        else
            echo "Failed to merge configuration files." >> ${LOG_FILE}
        fi

        # flush the AIX shared library cache
        /usr/sbin/slibclean

        if [ -f /etc/centrifydc/openldap/ldap.conf.cdc_upgrade ]; then
            echo "restoring original ldap.conf ..." >> ${LOG_FILE}
            mv -f /etc/centrifydc/openldap/ldap.conf.cdc_upgrade /etc/centrifydc/openldap/ldap.conf >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi

        if [ -f /var/centrifydc/INSTALL-START ]; then
            upgrade_cache
            echo "starting adclient ..." >> ${LOG_FILE}
            /usr/bin/startsrc -e LIBPATH=/usr/share/centrifydc/lib:/usr/share/centrifydc/kerberos/lib -s centrifydc >> ${LOG_FILE}
        fi
        rm -Rf /var/centrifydc/upgrade >> ${LOG_FILE}
        rm -f /var/centrifydc/INSTALL-START
        echo "... done" >> ${LOG_FILE}

        # CDC-nis
        if [ -f /var/centrifydc/nis/upgrade/START ]; then
            YP_STOPPED=/tmp/cdc_inst_yp_stopped
            echo "starting adnisd ..." >> ${LOG_FILE}
            /usr/bin/startsrc -e LIBPATH=/usr/share/centrifydc/lib:/usr/share/centrifydc/kerberos/lib -s adnisd >> ${LOG_FILE} 2>> ${LOG_FILE}
            # If we stopped ypbind, restart it.  Wait for 10 seconds so adnisd could answer
            # ypbind. Otherwise, the system will grind to a halt if adnisd is not answering.
            if [ -f $YP_STOPPED ]; then
                sleep 10
                /usr/bin/startsrc -s ypbind >> ${LOG_FILE} 2>> ${LOG_FILE}
                /usr/bin/rm -f $YP_STOPPED
            fi
            rm -rf /var/centrifydc/nis/upgrade >> ${LOG_FILE}
            echo "... done" >> ${LOG_FILE}
        fi

        # CDC-ldapproxy
        # Preserve configuration in slapd.conf when upgrade.
        # Note that: slapd.conf is not created in fresh install.

        # If machine is currently joined to a domain, call adreload to trigger auto-edit
        # script to update configuration file slapd.conf.
        /usr/bin/adinfo -d > /dev/null 2> /dev/null
        if [ $? = 0 ]; then
            # adclient might not be started up. The error from adreload during installation is useless.
            echo "Running adreload -c -u ..." >> ${LOG_FILE}
            /usr/sbin/adreload -c -u > /dev/null 2> /dev/null
        fi

        echo "Checking /etc/syslog.conf for user.debug entry" >> ${LOG_FILE}
        cat /etc/syslog.conf | grep /var/log/centrifydc.log | grep '^user.debug' >> ${LOG_FILE} 2>> ${LOG_FILE}
        if [ "$?" = "0" ]; then
            echo "turning debug off" >> ${LOG_FILE}
            /usr/share/centrifydc/bin/addebug off >> ${LOG_FILE} 2>> ${LOG_FILE}

            echo "Checking /etc/syslog.conf for user.debug entry one more time" >> ${LOG_FILE}
            cat /etc/syslog.conf | grep /var/log/centrifydc.log | grep '^user.debug' >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" = "0" ]; then
                echo "Deleting user.debug entry from /etc/syslog.conf" >> ${LOG_FILE}
                cp -p /etc/syslog.conf /etc/syslog.conf.pre_cdc_upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
                sed -e "/user.debug[ 	]*\/var\/log\/centrifydc.log/d" /etc/syslog.conf > /etc/syslog.conf.tmp_upgrade
                mv -f /etc/syslog.conf.tmp_upgrade /etc/syslog.conf >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi

            echo "turning debug back on" >> ${LOG_FILE}
            /usr/share/centrifydc/bin/addebug on >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi

        # configure syslog-ng.conf when the syslog-ng has been installed
        SYSLOGNG_CONF="";
        if [ -s "/etc/syslog-ng/syslog-ng.conf" ] ; then
            SYSLOGNG_CONF="/etc/syslog-ng/syslog-ng.conf"
        fi
        if [ "X${SYSLOGNG_CONF}" != "X" ]; then
            echo "Checking $SYSLOGNG_CONF for centrifydc.log" >> ${LOG_FILE}
            cat $SYSLOGNG_CONF | grep /var/log/centrifydc.log  | grep "^destination centrify"  >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" = "0" ]; then
                echo "turning debug off" >> ${LOG_FILE}
                /usr/share/centrifydc/bin/addebug off >> ${LOG_FILE} 2>> ${LOG_FILE}

                echo "Checking $SYSLOGNG_CONF for centrifydc.log one more time" >> ${LOG_FILE}
                cat $SYSLOGNG_CONF | grep /var/log/centrifydc.log  | grep "^destination centrify" >> ${LOG_FILE} 2>> ${LOG_FILE}
                if [ "$?" = "0" ]; then
                    echo "Deleting centrifydc.log from $SYSLOGNG_CONF" >> ${LOG_FILE}
                    cp -p $SYSLOGNG_CONF ${SYSLOGNG_CONF}.pre_cdc_upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
                    sed -e "/\/var\/log\/centrifydc.log/d" -e "/f_centrify/d" $SYSLOGNG_CONF > ${SYSLOGNG_CONF}.tmp_upgrade
                    mv -f ${SYSLOGNG_CONF}.tmp_upgrade ${SYSLOGNG_CONF} >> ${LOG_FILE} 2>> ${LOG_FILE}
                fi

                echo "turning debug back on" >> ${LOG_FILE}
                /usr/share/centrifydc/bin/addebug on >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi       
        fi
        if [ -f /usr/share/centrifydc/wpar/etc/centrifydc/express ]; then
            /usr/bin/adlicense --express >> ${LOG_FILE}
        elif [ -f /usr/share/centrifydc/wpar/etc/centrifydc/licensed ]; then
            /usr/bin/adlicense --licensed >> ${LOG_FILE}
        fi
        echo "\nWARNING:"
        echo "To complete the update of Centrify DirectControl,"
        echo "you may need to restart some services that rely upon PAM and NSS or simply"
        echo "reboot the computer for proper operation. Failure to do so may result in"
        echo "login problems for AD users.\n"
    fi

    return $TRUE
} # wpar_config

wpar_config_ssh()
{
    echo "wpar_config_ssh (post-post-install): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.openssh | grep CentrifyDC.openssh >> ${LOG_FILE} 2>> ${LOG_FILE}

    SSH_BIN_DIR=/usr/share/centrifydc/bin
    SSH_ETC_DIR=/etc/centrifydc/ssh

    # Determine where xauth is
    xauthloc=`which xauth 2> /dev/null`
    if [ -z "$xauthloc" ]; then
        for loc in /usr/bin /usr/bin/X11 /usr/X11R6/bin /usr/openwin/bin ; do
            if [ -x "$loc/xauth" ]; then
                xauthloc="$loc/xauth"
                break
            fi
        done
    fi
    # Add the xauth location to the new sshd_config file
    if [ -n "$xauthloc" ] && [ -x "$xauthloc" ]; then
        echo "Found xauth, location is $xauthloc." >> ${LOG_FILE}
        echo "XAuthLocation $xauthloc" >> ${SSH_ETC_DIR}/sshd_config
    fi
    # merge previous ssh_config into current ssh_config
    if [ -f ${SSH_ETC_DIR}/ssh_config.cdcsave -a -f ${SSH_ETC_DIR}/ssh_config ]; then
            ${SSH_BIN_DIR}/ssh-mergeconf ${SSH_ETC_DIR}/ssh_config.cdcsave ${SSH_ETC_DIR}/ssh_config >> ${LOG_FILE}
    fi
    # merge previous sshd_config into current sshd_config
    if [ -f ${SSH_ETC_DIR}/sshd_config.cdcsave -a -f ${SSH_ETC_DIR}/sshd_config ]; then
            ${SSH_BIN_DIR}/ssh-mergeconf ${SSH_ETC_DIR}/sshd_config.cdcsave ${SSH_ETC_DIR}/sshd_config >> ${LOG_FILE}
    fi

    # Start our ssh instance
    echo starting centrify-sshd ... >> ${LOG_FILE}
    /usr/bin/startsrc -s centrify-sshd

    return $TRUE
} # wpar_config_ssh

wpar_pre_d()
{
    echo "wpar_pre_d (pre-pre-deinstall): `${DATE}`" >> ${LOG_FILE}

    if test -s /var/centrifydc/kset.domain; then
        echo "\nWARNING:" | tee -a ${LOG_FILE}
        echo "Could not uninstall Centrify DirectControl. Please run 'adleave' first.\n" | tee -a ${LOG_FILE}
        do_exit ${CODE_EUN}
    fi

    # Stop Centrify-KCM if it's running
    if [ -x /usr/share/centrifydc/bin/centrify-kcm ]; then
        /usr/share/centrifydc/bin/centrify-kcm status | grep "is running" >> ${LOG_FILE} 2>> ${LOG_FILE}
        if [ $? -eq 0 ]; then
            echo stop Centrify-KCM by centrify-kcm stop ... >> ${LOG_FILE}
            /usr/share/centrifydc/bin/centrify-kcm stop >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
    fi

    if [ -f /etc/centrifydc/openldap/slapd.conf ]; then
        rm -f /etc/centrifydc/openldap/slapd.conf >> ${LOG_FILE}
    fi

    if [ -f /etc/shells ]; then
        echo removing /usr/bin/dzsh from /etc/shells ... >> ${LOG_FILE}
        cp -pf /etc/shells /etc/shells.tmp
        cat /etc/shells | sed '/\/usr\/bin\/dzsh/d' > /etc/shells.tmp
        mv -f /etc/shells.tmp /etc/shells
        awk '/^\//{ exit 1 }' /etc/shells
        if [ $? -eq 0 ]; then
            echo "WARNING: /etc/shells is empty, all ftp access will be disabled" >> ${LOG_FILE}
        fi
    fi

    return $TRUE
} # wpar_pre_d

wpar_unpost_i()
{
    echo "wpar_unpost_i (pre-deinstall): `${DATE}`" >> ${LOG_FILE}

    # Stop Centrify-ldapproxy if it's running
    if [ -x /usr/share/centrifydc/bin/centrify-ldapproxy ]; then
        /usr/share/centrifydc/bin/centrify-ldapproxy status | grep "is running" >> ${LOG_FILE} 2>> ${LOG_FILE}
        if [ $? -eq 0 ]; then
            echo "stopping Centrify-ldapproxy by centrify-ldapproxy stop ..." >> ${LOG_FILE}
            /usr/share/centrifydc/bin/centrify-ldapproxy stop >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
    fi

    if [ -f /etc/rc.tcpip ]; then
        # CDC-nis
        cat /etc/rc.tcpip | grep "Centrify adnisd" > /dev/null 2> /dev/null
        RC=$?
        if [ "${RC}" = "0" ]; then
            /usr/bin/stopsrc -s adnisd >> ${LOG_FILE}
            rmssys -s adnisd >> ${LOG_FILE}
            cp /etc/rc.tcpip /etc/rc.tcpip.cdc
            cat /etc/rc.tcpip.cdc | sed -e '/Start up Centrify adnisd/,/last Centrify adnisd line/d' > /etc/rc.tcpip
        fi

        # CDC-ldapproxy
        cat /etc/rc.tcpip | grep "CentrifyDC ldapproxy" > /dev/null 2> /dev/null
        RC=$?
        if [ "${RC}" = "0" ]; then
            # Copy to preserve file ownership and permissions
            cp -pf /etc/rc.tcpip /etc/rc.tcpip.tmp
            sed '/Start up CentrifyDC ldapproxy/,/last CentrifyDC ldapproxy line/d' /etc/rc.tcpip > /etc/rc.tcpip.tmp 2>> ${LOG_FILE}
            mv -f /etc/rc.tcpip.tmp /etc/rc.tcpip 2>> ${LOG_FILE}
        fi

        # CentrifyDC
        cat /etc/rc.tcpip | grep CentrifyDC > /dev/null 2> /dev/null
        RC=$?
        if [ "${RC}" = "0" ]; then
            cp /etc/rc.tcpip /etc/rc.tcpip.cdc
            cat /etc/rc.tcpip.cdc | sed -e '/Start up CentrifyDC adclient/,/last CentrifyDC line/d' > /etc/rc.tcpip
        fi
    else
        echo "Warning: Could not find /etc/rc.tcpip."
    fi
 
    # remove the rotating centrify_client.log from crontab
    crontab -l |  grep -v "/usr/share/centrifydc/bin/logrotate.sh" > cron.$$
    crontab cron.$$
    rm -f cron.$$

    /usr/bin/rmssys -s centrifydc
    /usr/bin/rmssys -s centrify-kcm
    /usr/bin/rmssys -s centrify-ldapproxy

    if [ -f /etc/centrifydc/passwd.ovr ]; then rm -f /etc/centrifydc/passwd.ovr; fi
    if [ -f /etc/centrifydc/group.ovr ]; then rm -f /etc/centrifydc/group.ovr; fi

    return $TRUE
} # wpar_unpost_i

wpar_unpost_i_ssh()
{
    echo "wpar_unpost_i_ssh (pre-deinstall): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.openssh | grep CentrifyDC.openssh >> ${LOG_FILE} 2>> ${LOG_FILE}

    if [ -f /etc/rc.tcpip ]; then
        cat /etc/rc.tcpip | grep "Centrify sshd" > /dev/null 2> /dev/null
        RC=$?
        if [ "${RC}" = "0" ]; then
            cp -p /etc/rc.tcpip /etc/rc.tcpip.cdc
            cat /etc/rc.tcpip.cdc |
                sed -e '/Start up Centrify sshd/,/last Centrify sshd line/d' > /etc/rc.tcpip
        else
            echo "Info: No changes made in /etc/rc.tcpip."
        fi
    else
        echo "Warning: Could not find /etc/rc.tcpip."
    fi

    # Stop our ssh instance
    echo stopping centrify-sshd ... >> ${LOG_FILE}
    /usr/bin/stopsrc -s centrify-sshd
    /usr/bin/rmssys -s centrify-sshd 2>> ${LOG_FILE}
    rm -f /etc/centrifydc/ssh/ssh_host_*

    # restore build-in sshd to start at boot time
    lssrc -s sshd > /dev/null 2>&1
    STATUS=$?
    if [ -f /etc/rc.d/Ksshd.pre_cdcssh ]; then
        if [ $STATUS -eq 0 ]; then
            mv /etc/rc.d/Ksshd.pre_cdcssh /etc/rc.d/rc2.d/Ksshd
        else
            rm -f /etc/rc.d/Ksshd.pre_cdcssh
        fi
    fi
    if [ -f /etc/rc.d/Ssshd.pre_cdcssh ]; then
        if [ $STATUS -eq 0 ]; then
            mv /etc/rc.d/Ssshd.pre_cdcssh /etc/rc.d/rc2.d/Ssshd
        else
            rm -f /etc/rc.d/Ssshd.pre_cdcssh
        fi
    fi

    # Enable built-in service
    STATUS=1
    if [ $STATUS -ne 0 ]; then
        /usr/bin/startsrc -s sshd > /dev/null 2>&1
        STATUS=$?
    fi
    if [ $STATUS -ne 0 ]; then
        /usr/bin/startsrc -s opensshd > /dev/null 2>&1
        STATUS=$?
    fi

    return $TRUE
} # wpar_unpost_i_ssh

wpar_unpre_i()
{
    echo "wpar_unpre_i (post-deinstall): `${DATE}`" >> ${LOG_FILE}

    if [ -d /var/centrify/cloud ]; then
        echo "INFO: found /var/centrify/cloud directory, skipping /var/centrify clean-up ..." >> ${LOG_FILE}
    elif [ -d /var/centrify ]; then
        echo "INFO: Removing /var/centrify directory ..." >> ${LOG_FILE}
        ls -laR /var/centrify >> ${LOG_FILE}
        rm -Rf /var/centrify >> ${LOG_FILE}
    fi
    rm -Rf /var/centrifydc
    rm -Rf /etc/centrifydc

    #remove the Centrifydc debug from syslog-ng.conf
    SYSLOGNG_CONF="";
    if [ -s "/etc/syslog-ng/syslog-ng.conf" ] ; then
        SYSLOGNG_CONF="/etc/syslog-ng/syslog-ng.conf"
    fi
    if [ "X${SYSLOGNG_CONF}" != "X" ]; then
       echo Checking $SYSLOGNG_CONF for centrifydc.log >> ${LOG_FILE}
       cat $SYSLOGNG_CONF | grep /var/log/centrifydc.log  | grep "^destination centrify" >> ${LOG_FILE} 2>> ${LOG_FILE}
       if [ "$?" = "0" ]; then
          echo Deleting centrifydc.log from $SYSLOGNG_CONF >> ${LOG_FILE}
          cp -p $SYSLOGNG_CONF ${SYSLOGNG_CONF}.pre_cdc_uninstall >> ${LOG_FILE} 2>> ${LOG_FILE}
          sed -e "/\/var\/log\/centrifydc.log/d" -e "/f_centrify/d" $SYSLOGNG_CONF > ${SYSLOGNG_CONF}.tmp_uninstall
          mv -f ${SYSLOGNG_CONF}.tmp_uninstall ${SYSLOGNG_CONF} >> ${LOG_FILE} 2>> ${LOG_FILE}
       fi
    fi

    return $TRUE
} # wpar_unpre_i

wpar_unpre_i_ssh()
{
    echo "wpar_unpre_i_ssh (post-deinstall): `${DATE}`" >> ${LOG_FILE}
    lslpp -l CentrifyDC.openssh | grep CentrifyDC.openssh >> ${LOG_FILE} 2>> ${LOG_FILE}

    rm -Rf /etc/centrifydc/ssh

    # Check if CDC version < 4.2.0.0, then needs to link /etc/krb5.keytab to /etc/krb5/krb5.keytab.
    # The reason is TOPCAT/POPCAT create krb5.keytab at /etc/krb5.keytab.
    basever="4.2.0.0"
    cdcver=`lslpp -i CentrifyDC.core | grep core | awk '{print $2}'`
    minver=`printf "$basever\n$cdcver\n" | sort | head -1`
    if [ "$minver" = "$cdcver" ]; then
        [ -s /etc/krb5/krb5.keytab ] && rm -f /etc/krb5/krb5.keytab
    fi

    return $TRUE
} # wpar_unpre_i_ssh

### 
fix_methods_cfg ()
{
    if [ "${TARGET_OS}" != "aix" ] || [ `uname -v` -lt 6 ]; then
        echo $ECHO_FLAG "\nERROR:" | tee -a ${LOG_FILE}
        echo $ECHO_FLAG "No need to fix /usr/lib/security/methods.cfg on `uname -sv` platform.\n" | tee -a ${LOG_FILE}
        do_exit ${CODE_ESU}
    fi
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: fix_methods_cfg: `${DATE}`" >> ${LOG_FILE}

    # step 1: check environmenr, do not fix 
    echo $ECHO_FLAG "INFO: checking environment for misplaced methods.cfg ...\n" | tee -a ${LOG_FILE}
    if [ -h /usr/lib/security/methods.cfg ] &&
       [ "`ls -l /usr/lib/security/methods.cfg | grep '/etc/methods.cfg'`" != "" ]; then
        echo "INFO: /usr/lib/security/methods.cfg looks good:" | tee -a ${LOG_FILE}
        ls -l /usr/lib/security/methods.cfg | tee -a ${LOG_FILE}
    elif [ -h /usr/lib/security/methods.cfg ] &&
         [ "`ls -l /usr/lib/security/methods.cfg | grep '/etc/centrifydc/methods.cfg'`" != "" ]; then
        echo "ATTENTION: /usr/lib/security/methods.cfg symlink needs to be fixed." | tee -a ${LOG_FILE}
    elif [ ! -h /usr/lib/security/methods.cfg ]; then
        echo "ATTENTION: /usr/lib/security/methods.cfg is a file and it needs to be fixed." | tee -a ${LOG_FILE}
    fi

    if [ -x /usr/sbin/lswpar ] && [ `/usr/sbin/lswpar -q -c -a name > /dev/null 2> /dev/null; echo $?` -eq 0 ]; then
        ### global environment on AIX 6.1+
        WPAR_LIST="`/usr/sbin/lswpar -q -c -a name 2> /dev/null`"
        WPAR_NOT_CLEAN=""
        for WPAR_NAME in ${WPAR_LIST}
        do
            echo "checking ${WPAR_NAME}: " | tee -a ${LOG_FILE}
            WPAR_DIR="`/usr/sbin/lswpar -q -c -a directory ${WPAR_NAME}`"
            #if [ -f ${WPAR_DIR}/etc/centrifydc/methods.cfg ] && [ `mount | grep " ${WPAR_DIR}/usr" | grep " ro" > /dev/null; echo $?` -eq 0 ]; then
            if [ -f ${WPAR_DIR}/etc/centrifydc/methods.cfg ]; then
                WPAR_NOT_CLEAN="${WPAR_NOT_CLEAN} ${WPAR_NAME}"
                echo "ATTENTION: found ${WPAR_DIR}/etc/centrifydc/methods.cfg, should be moved into /etc." | tee -a ${LOG_FILE}
            fi
            if [ -h ${WPAR_DIR}/usr/lib/security/methods.cfg ] &&
               [ "`ls -l ${WPAR_DIR}/usr/lib/security/methods.cfg | grep '/etc/centrifydc/methods.cfg'`" != "" ]; then
                echo "ATTENTION: ${WPAR_DIR}/usr/lib/security/methods.cfg symlink needs to be fixed." | tee -a ${LOG_FILE}
                if [ `mount | grep " ${WPAR_DIR}/usr" | grep " ro" > /dev/null; echo $?` -eq 0 ]; then
                    echo "         : ${WPAR_DIR}/usr is a read-only partition so it will be fixed in global environment." | tee -a ${LOG_FILE}
                fi
            elif [ ! -h ${WPAR_DIR}/usr/lib/security/methods.cfg ]; then
                echo "ATTENTION: ${WPAR_DIR}/usr/lib/security/methods.cfg is a file and it needs to be fixed." | tee -a ${LOG_FILE}
                if [ `mount | grep " ${WPAR_DIR}/usr" | grep " ro" > /dev/null; echo $?` -eq 0 ]; then
                    echo "         : ${WPAR_DIR}/usr is a read-only partition so it will be fixed in global environment." | tee -a ${LOG_FILE}
                fi
            fi
            echo "`ls -l ${WPAR_DIR}/usr/lib/security/methods.cfg*`" | tee -a ${LOG_FILE}
            echo "`ls -l ${WPAR_DIR}/etc/methods.cfg*`" | tee -a ${LOG_FILE}
        done
    fi

    if [ "${SILENT}" = "NO" ]; then
        QUESTION="\nDo you want to continue and fix? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
        if [ "${ANSWER}" != "Y" ]; then do_quit; fi
    fi

    # step 2 (prepare):
    # In each WPAR copy /etc/centrifydc/methods.cfg to /etc/methods.cfg 
    # and fix (!) /usr/lib/security/methods.cfg if /usr is read-write partition
    for WPAR_NAME in ${WPAR_LIST}
    do
        echo "fixing ${WPAR_NAME}: " | tee -a ${LOG_FILE}
        WPAR_DIR="`/usr/sbin/lswpar -q -c -a directory ${WPAR_NAME}`"
        if [ -h ${WPAR_DIR}/usr/lib/security/methods.cfg ] &&
           [ "`ls -l ${WPAR_DIR}/usr/lib/security/methods.cfg | grep '/etc/methods.cfg'`" != "" ]; then
            echo "INFO: ${WPAR_DIR}/usr/lib/security/methods.cfg looks good:" | tee -a ${LOG_FILE}
            ls -l ${WPAR_DIR}/usr/lib/security/methods.cfg | tee -a ${LOG_FILE}
        elif [ -h ${WPAR_DIR}/usr/lib/security/methods.cfg ] &&
           [ "`ls -l ${WPAR_DIR}/usr/lib/security/methods.cfg | grep '/etc/centrifydc/methods.cfg'`" != "" ]; then
            if [ -f ${WPAR_DIR}/etc/methods.cfg ] && [ `diff ${WPAR_DIR}/etc/methods.cfg ${WPAR_DIR}/etc/centrifydc/methods.cfg > /dev/null; echo $?` -eq 0 ]; then
                echo "INFO: ${WPAR_DIR}/etc/methods.cfg and ${WPAR_DIR}/etc/centrifydc/methods.cfg are identical." | tee -a ${LOG_FILE}
            elif [ -f ${WPAR_DIR}/etc/methods.cfg ] && [ `diff ${WPAR_DIR}/etc/methods.cfg ${WPAR_DIR}/etc/centrifydc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
                # backup ${WPAR_DIR}/etc/methods.cfg
                if [ ! -f ${WPAR_DIR}/etc/methods.cfg.org ]; then
                    echo "INFO: copying ${WPAR_DIR}/etc/methods.cfg to ${WPAR_DIR}/etc/methods.cfg.org" | tee -a ${LOG_FILE}
                    cp -p ${WPAR_DIR}/etc/methods.cfg ${WPAR_DIR}/etc/methods.cfg.org
                elif [ -f ${WPAR_DIR}/etc/methods.cfg.org ] && [ `diff ${WPAR_DIR}/etc/methods.cfg.org ${WPAR_DIR}/etc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
                    echo "INFO: copying ${WPAR_DIR}/etc/methods.cfg to ${WPAR_DIR}/etc/methods.cfg.org2" | tee -a ${LOG_FILE}
                    cp -p ${WPAR_DIR}/etc/methods.cfg ${WPAR_DIR}/etc/methods.cfg.org2
                fi
                echo "INFO: replacing ${WPAR_DIR}/etc/centrifydc/methods.cfg with symlink to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
                mv -f ${WPAR_DIR}/etc/centrifydc/methods.cfg ${WPAR_DIR}/etc/methods.cfg && ln -s -f /etc/methods.cfg ${WPAR_DIR}/etc/centrifydc/methods.cfg
            elif [ ! -f /etc/methods.cfg ]; then
                echo "INFO: replacing ${WPAR_DIR}/etc/centrifydc/methods.cfg with symlink to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
                mv -f ${WPAR_DIR}/etc/centrifydc/methods.cfg ${WPAR_DIR}/etc/methods.cfg && ln -s -f /etc/methods.cfg ${WPAR_DIR}/etc/centrifydc/methods.cfg
            fi
            if [ `mount | grep " ${WPAR_DIR}/usr" | grep " ro" > /dev/null; echo $?` -eq 0 ]; then
                echo "INFO: ${WPAR_DIR}/usr is a read-only partition so /usr/lib/security/methods.cfg will be fixed in global environment." | tee -a ${LOG_FILE}
            else
                echo "INFO: restoring ${WPAR_DIR}/usr/lib/security/methods.cfg as a symlink pointing to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
                rm -f ${WPAR_DIR}/usr/lib/security/methods.cfg && ln -s -f /etc/methods.cfg ${WPAR_DIR}/usr/lib/security/methods.cfg
            fi
        elif [ -f ${WPAR_DIR}/usr/lib/security/methods.cfg ]; then
            # backup ${WPAR_DIR}/etc/methods.cfg
            if [ ! -f ${WPAR_DIR}/etc/methods.cfg.org ]; then
                echo "INFO: copying ${WPAR_DIR}/etc/methods.cfg to ${WPAR_DIR}/etc/methods.cfg.org" | tee -a ${LOG_FILE}
                cp -p ${WPAR_DIR}/etc/methods.cfg ${WPAR_DIR}/etc/methods.cfg.org
            elif [ -f ${WPAR_DIR}/etc/methods.cfg.org ] && [ `diff ${WPAR_DIR}/etc/methods.cfg.org ${WPAR_DIR}/etc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
                echo "INFO: copying ${WPAR_DIR}/etc/methods.cfg to ${WPAR_DIR}/etc/methods.cfg.org2" | tee -a ${LOG_FILE}
                cp -p ${WPAR_DIR}/etc/methods.cfg ${WPAR_DIR}/etc/methods.cfg.org2
            fi
            # copy current methods.cfg
            cp -f -p ${WPAR_DIR}/usr/lib/security/methods.cfg ${WPAR_DIR}/etc/methods.cfg
            if [ -f ${WPAR_DIR}/usr/lib/security/methods.cfg.pre_cdc ] || [ -f ${WPAR_DIR}/usr/lib/security/methods.cfg.pre_cda ] || \
               [ -f ${WPAR_DIR}/usr/lib/security/methods.cfg.pre_cdc_wpar ]; then
                cp -f -p ${WPAR_DIR}/usr/lib/security/methods.cfg.pre_cd* ${WPAR_DIR}/etc/
            fi
            # fix ${WPAR_DIR}/usr/lib/security/methods.cfg
            if [ `mount | grep " ${WPAR_DIR}/usr" | grep " ro" > /dev/null; echo $?` -eq 0 ]; then
                echo "INFO: ${WPAR_DIR}/usr is a read-only partition so /usr/lib/security/methods.cfg will be fixed in global environment." | tee -a ${LOG_FILE}
            else
                echo "INFO: restoring ${WPAR_DIR}/usr/lib/security/methods.cfg as a symlink pointing to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
                rm -f ${WPAR_DIR}/usr/lib/security/methods.cfg && ln -s -f /etc/methods.cfg ${WPAR_DIR}/usr/lib/security/methods.cfg
                rm -f ${WPAR_DIR}/usr/lib/security/methods.cfg.pre_cd*
            fi
        fi
    done

    # step 3: fix global environment
    echo "INFO: fixing global environment ..." | tee -a ${LOG_FILE}
    if [ -h /usr/lib/security/methods.cfg ] &&
       [ "`ls -l /usr/lib/security/methods.cfg | grep '/etc/methods.cfg'`" != "" ]; then
        echo "INFO: /usr/lib/security/methods.cfg looks good:" | tee -a ${LOG_FILE}
        ls -l /usr/lib/security/methods.cfg | tee -a ${LOG_FILE}
    elif [ -h /usr/lib/security/methods.cfg ] &&
       [ "`ls -l /usr/lib/security/methods.cfg | grep '/etc/centrifydc/methods.cfg'`" != "" ]; then
        if [ -f /etc/methods.cfg ] && [ `diff /etc/methods.cfg /etc/centrifydc/methods.cfg > /dev/null; echo $?` -eq 0 ]; then
            echo "INFO: /etc/methods.cfg and /etc/centrifydc/methods.cfg are identical." | tee -a ${LOG_FILE}
        elif [ -f /etc/methods.cfg ] && [ `diff /etc/methods.cfg /etc/centrifydc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
            # backup /etc/methods.cfg
            if [ ! -f /etc/methods.cfg.org ]; then
                echo "INFO: copying /etc/methods.cfg to /etc/methods.cfg.org" | tee -a ${LOG_FILE}
                cp -p /etc/methods.cfg /etc/methods.cfg.org
            elif [ -f /etc/methods.cfg.org ] && [ `diff /etc/methods.cfg.org /etc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
                echo "INFO: copying /etc/methods.cfg to /etc/methods.cfg.org2" | tee -a ${LOG_FILE}
                cp -p /etc/methods.cfg /etc/methods.cfg.org2
            fi
            echo "INFO: replacing /etc/centrifydc/methods.cfg with symlink to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
            mv -f /etc/centrifydc/methods.cfg /etc/methods.cfg && ln -s -f /etc/methods.cfg /etc/centrifydc/methods.cfg
        elif [ ! -f /etc/methods.cfg ]; then
            echo "INFO: replacing /etc/centrifydc/methods.cfg with symlink to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
            mv -f /etc/centrifydc/methods.cfg /etc/methods.cfg && ln -s -f /etc/methods.cfg /etc/centrifydc/methods.cfg
        fi
        echo "INFO: restoring /usr/lib/security/methods.cfg as a symlink pointing to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
        rm -f /usr/lib/security/methods.cfg && ln -s -f /etc/methods.cfg /usr/lib/security/methods.cfg
    elif [ -f /usr/lib/security/methods.cfg ]; then
        # backup /etc/methods.cfg
        if [ ! -f /etc/methods.cfg.org ]; then
            echo "INFO: copying /etc/methods.cfg to /etc/methods.cfg.org" | tee -a ${LOG_FILE}
            cp -p /etc/methods.cfg /etc/methods.cfg.org
        elif [ -f /etc/methods.cfg.org ] && [ `diff /etc/methods.cfg.org /etc/methods.cfg > /dev/null; echo $?` -ne 0 ]; then
            echo "INFO: copying /etc/methods.cfg to /etc/methods.cfg.org2" | tee -a ${LOG_FILE}
            cp -p /etc/methods.cfg /etc/methods.cfg.org2
        fi
        # fix /usr/lib/security/methods.cfg
        echo "INFO: restoring /usr/lib/security/methods.cfg as a symlink pointing to /etc/methods.cfg ..." | tee -a ${LOG_FILE}
        mv -f /usr/lib/security/methods.cfg /etc/methods.cfg && ln -s -f /etc/methods.cfg /usr/lib/security/methods.cfg
        if [ -f /usr/lib/security/methods.cfg.pre_cdc ] || [ -f /usr/lib/security/methods.cfg.pre_cda ] || \
           [ -f /usr/lib/security/methods.cfg.pre_cdc_wpar ]; then
            mv -f /usr/lib/security/methods.cfg.pre_cd* /etc/
        fi
    fi

    # step 4 (clean-up):
    # In each WPAR rename /etc/centrifydc/methods.cfg
    # and move /etc/centrifydc/methods.cfg.pre_cdc* into /etc
    for WPAR_NAME in ${WPAR_LIST}
    do
        echo "fixing ${WPAR_NAME}: " | tee -a ${LOG_FILE}
        WPAR_DIR="`/usr/sbin/lswpar -q -c -a directory ${WPAR_NAME}`"
        if [ -f ${WPAR_DIR}/etc/centrifydc/methods.cfg ]; then
            echo "INFO: renaming ${WPAR_DIR}/etc/centrifydc/methods.cfg ..." | tee -a ${LOG_FILE}
            mv -f ${WPAR_DIR}/etc/centrifydc/methods.cfg ${WPAR_DIR}/etc/centrifydc/methods.cfg.BK
        fi
        if [ -f ${WPAR_DIR}/etc/centrifydc/methods.cfg.pre_cdc ] || [ -f ${WPAR_DIR}/etc/centrifydc/methods.cfg.pre_cda ] || \
           [ -f ${WPAR_DIR}/etc/centrifydc/methods.cfg.pre_cdc_wpar ]; then
            echo "INFO: moving ${WPAR_DIR}/etc/centrifydc/methods.cfg.pre_cd* into ${WPAR_DIR}/etc/ ..." | tee -a ${LOG_FILE}
            mv -f ${WPAR_DIR}/etc/centrifydc/methods.cfg.pre_cd* ${WPAR_DIR}/etc/
        fi
    done
 
    if [ "${FIX_METHODS_CFG}" = "yes" ]; then do_exit 0; fi
    return $TRUE
} # fix_methods_cfg

### adjust list of supported add-on packages
check_exceptions ()
{
    if [ "${BUNDLE_MODE}" = "Y" ]; then return; fi # skip in bundle mode
    if [ ! -f ${CFG_FNAME_SUITE} ]; then
        if [ "${TARGET_OS}" != "darwin" -a "${UNINSTALL}" != "Y" ]; then
            echo "WARNING: Could not find ${CFG_FNAME_SUITE}, skipping exception check." | tee -a ${LOG_FILE}
        fi
        return $FALSE
    else
        EXC_LIST=`cat ${CFG_FNAME_SUITE} | grep "target_os,os_rev,arch" | grep cdc-${CDC_VER_SHORT}`
        EXCEPTIONS=`cat ${CFG_FNAME_SUITE} | sed  's/\#.*$//' | grep "${TARGET_OS},${OS_REV}${OS_MODE},${ARCH}" | grep cdc-${CDC_VER_SHORT}`
        debug_echo EXCEPTIONS=${EXCEPTIONS}
        i=2
        ADD_ON=`echo ${EXC_LIST} | cut -d',' -f$i`
        while [ "${ADD_ON}" != "" ]
        do
            EXC_KEY=`echo ${EXCEPTIONS} | cut -d',' -f$i`   
            if [ "${EXC_KEY}" = "0" ]; then
                ADD_ON_LIST=`echo ${ADD_ON_LIST} | sed "s/${ADD_ON}//" | sed "s/  / /g"`
            fi
            i=`expr $i + 1`
            ADD_ON=`echo ${EXC_LIST} | cut -d',' -f$i`   
        done
        debug_echo "ADD_ON_LIST=${ADD_ON_LIST}"
        return $TRUE
    fi
} # check_exceptions()

### set silent mode configuration
set_silent_cfg()
{
    VAR_LIST="ADCHECK ADJOIN ADJ_LIC ADJ_FORCE ADJ_TRUST DOMAIN USERID PASSWD COMPUTER CONTAINER ZONE SERVER REBOOT ADLICENSE"
    if [ "${CDC_VER}" = "${CDC_VER_SHORT}" ]; then # CLI -v option was not used, so read CDC_VER from config file
        VAR_LIST="CDC_VER ${VAR_LIST}"
    fi
    for VAR3 in ${ADD_ON_LIST}; do
        if [ "${VAR3}" = "cda" ]; then
            VAR_LIST="${VAR_LIST} CentrifyDA DA_INST_NAME"
        else
            VAR_LIST="${VAR_LIST} CentrifyDC_${VAR3}"
        fi
    done
    # default settings
    ADCHECK="N"
    INSTALL="U"
    # Y - (yes) install if it's not installed
    # U - same as Y plus: update if it's installed but older version; keep current if the same version is installed
    # to be implemented: R - (repair, reinstall) same as U plus: update even if the same version is installed    
    if [ "${UNINSTALL}" = "Y" ]; then
        # it's uninstall.sh or install.sh -e
        echo $ECHO_FLAG "\nINFO: Non-interactive uninstall, ignoring INSTALL and UNINSTALL settings in config file." >> ${LOG_FILE}
        INSTALL="E"
    else
        # read INSTALL and UNINSTALL from config file
        VAR_LIST="${VAR_LIST} INSTALL UNINSTALL"
    fi
    if [ -n "${DA_ENABLE}" ]; then
        # DA is set to be enabled (or disabled) using command line option
        echo $ECHO_FLAG "\nINFO: DA is enabled (or disabled) in command line, ignoring DA_ENABLE setting in config file." >> ${LOG_FILE}
    else
        # read DA_ENABLE from config file
        DA_ENABLE="K" # Keep current state on upgrade (disable on fresh install). It will be reset according to cfg file (non-interactive) or user's response (interactive mode).
        VAR_LIST="${VAR_LIST} DA_ENABLE"        
    fi
    case "${TARGET_OS}" in
    solaris)
        if [ "${GLOBAL_ZONE_ONLY}" != "non_global" ]; then
            # global zone
            VAR_LIST="${VAR_LIST} GLOBAL_ZONE_ONLY"
        fi
        ;;
    esac
    ADJOIN="N"
    ADJ_LIC=
    ADJ_FORCE=
    ADJ_TRUST=
    DOMAIN=
    USERID=administrator
    PASSWD=
    COMPUTER=`hostname`
    CONTAINER=Computers
    ZONE=
    SERVER=
    REBOOT="N"
    # override defaults with values from config file 
    if [ "${SUITE}" != "Custom" ]; then
        CFG_FNAME=${CFG_FNAME_SUITE}
    fi 
    if [ "${UNINSTALL}" != "Y" ]; then
        read_cfg_file
        if [ "${OVERRIDE}" = "Y" ]; then
            validate_override
        fi
    fi
    if [ "${SUITE}" = "Standard" ]; then
        CentrifyDA="N"
    fi
    if [ "${UNINSTALL}" = "Y" ] && [ "${INSTALL}" != "E" ]; then
        echo $ECHO_FLAG "\nERROR: Variable UNINSTALL=${UNINSTALL} conflicts with INSTALL=${INSTALL}." >> ${LOG_FILE}
        echo $ECHO_FLAG   "       Please sort it out then restart installer. Exiting ... "            >> ${LOG_FILE}
        return $FALSE
    fi
    if [ -n "${ADJOIN_CMD_OPTIONS}" ]; then
        ### ignore separate adjoin variables and just use adjoin options provided with --adjoin_opt=<...>
        ADJOIN="N"
    fi
    return $TRUE
} # set_silent_cfg()

### read install setting from config file
read_cfg_file ()
{
    if [ -f ${CFG_FNAME} ]; then
        IFS_ORG="${IFS}"
        if [ "${ECHO_FLAG}" = "-e" ]; then
            # bash
            IFS=$'\012'
        else
            IFS=$"`echo $ECHO_FLAG '\012\001'`"
        fi
        for LINE in `cat ${CFG_FNAME} | sed '/\#\#\# manifest \#\#\#/,$d' | sed  's/\#.*$//' | sed '/^$/d'`
        do
            IFS=$' '
            for VAR2 in ${VAR_LIST}
            do
                case "${LINE}" in
                ${VAR2}*)
                    if [ "${VAR2}" = "PASSWD" ]; then
                        PASSWD="`cat ${CFG_FNAME} | grep "PASSWD=" | sed 's/PASSWD=//' | sed 's/\"//g' | tail -1`"
                    else
                        eval ${VAR2}=`echo ${LINE} | sed "s/${VAR2}=//"`
                    fi
                    if [ "${VAR2}" = "CDC_VER" ]; then # we read CDC_VER from config file
                        echo $ECHO_FLAG "\nINFO: using config file value to set CDC_VER=${CDC_VER}" >> ${LOG_FILE}
                    fi
                    ;;
                esac
            done
            if [ "${ECHO_FLAG}" = "-e" ]; then
                # bash
                IFS=$'\012'
            else
                IFS=$"`echo $ECHO_FLAG '\012\001'`"
            fi
        done
        IFS="${IFS_ORG}"
        echo $ECHO_FLAG "\nINFO: Silent mode settings:" >> ${LOG_FILE}
        for VAR1 in ${VAR_LIST}; do
            ### translate some parameters to upper case
            TMP_VAR1=\$"${VAR1}"
            TMP_VAR2=`eval "expr \"\${TMP_VAR1}\" "`
            case "${TMP_VAR2}" in
            y | n | k | u | e | r )
                eval ${VAR1}=`echo ${TMP_VAR2} | tr abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ`
                ;;
            esac
            ### dump all parameters into the log
            if [ "${VAR1}" = "PASSWD" ]; then
                echo $ECHO_FLAG "    PASSWD=********" >> ${LOG_FILE}
            else
                echo $ECHO_FLAG "    ${VAR1}=\c" >> ${LOG_FILE}
                eval echo \$$VAR1 >> ${LOG_FILE}
            fi
        done
    else
        echo $ECHO_FLAG "\nWARNING: could not find ${CFG_FNAME} config file, using defaults ..." | tee -a ${LOG_FILE}
        return $FALSE
    fi
    return $TRUE
} # read_cfg_file

### Find location of the packages
find_pkg_dir () {
    if [ "${BUNDLE_MODE}" = "Y" ]; then
        echo $ECHO_FLAG "INFO: installer is running in bundle mode ..." >> ${LOG_FILE}
        BUNDLE_DIR="`dirname ${THIS_PRG}`/"
        debug_echo BUNDLE_DIR=${BUNDLE_DIR}
        return $TRUE
    fi
    PKG_DIR="`dirname ${THIS_PRG}`/"
    debug_echo PKG_DIR=${PKG_DIR}
    ADCHECK_FNAME="${PKG_DIR}${ADCHECK_FNAME}"
    CFG_FNAME="${PKG_DIR}${CFG_FNAME}"
    
    # If user does not provide suite config file with --suite-config, then use default.    
    if [ -z "${CFG_FNAME_SUITE}" ]; then
        CFG_FNAME_SUITE="${PKG_DIR}${CFG_FNAME_SUITE_DEF}"            
    else 
        # If user only provides suite config file name, the use PKG_DIR as directory.    
        if [ "`basename ${CFG_FNAME_SUITE}`" = "${CFG_FNAME_SUITE}" ]; then    
            CFG_FNAME_SUITE="${PKG_DIR}${CFG_FNAME_SUITE}"
        fi
        # If user provides a path for suite config file, then use it directly.
        
        # Make sure the suite config exists.
        [ -f "${CFG_FNAME_SUITE}" ] || { echo "ERROR: ${CFG_FNAME_SUITE} was not found."; do_error $CODE_ESU; }
        # Make sure the suite config has compatibility manifest
        if [ `cat ${CFG_FNAME_SUITE} | grep core-${CDC_VER_SHORT} > /dev/null; echo $?` -ne 0 ]; then
            echo "ERROR: ${CFG_FNAME_SUITE} has no compatibility manifest for ${CDC_VER_SHORT}."
            do_error $CODE_ESU
        fi
    fi
} # find_pkg_dir

###
install_bundle ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: install_bundle: " >> ${LOG_FILE}
    set_bundle_name
    debug_echo BUNDLE_FILE=${BUNDLE_FILE}
    ls ${BUNDLE_FILE} >> ${LOG_FILE} 2>> ${LOG_FILE}
    if [ $? -ne 0 ]; then
        echo  $ECHO_FLAG "ERROR: could not find ${BUNDLE_FILE} bundle in directory. Exiting..."
        do_error $CODE_EIN
    fi

    # clean any prev temp dirs 
    rm -rf ${VAR}/tmp/centrify*-bundle
    rm -rf ${VAR}/centrify/install-tmp*-bundle

    # prep ${VAR_TMP_BUNDLE}
    VAR_TMP_BUNDLE=${VAR_TMP}-bundle
    create_verify_dir "${VAR_TMP_BUNDLE}"

    # open bundle into ${VAR_TMP_BUNDLE}
    gunzip -c ${BUNDLE_FILE} | ( cd ${VAR_TMP_BUNDLE} && tar -xf - )
    echo  $ECHO_FLAG "\nINFO: bundle content (${VAR_TMP_BUNDLE}): " >> ${LOG_FILE}
    ls -l ${VAR_TMP_BUNDLE} >> ${LOG_FILE}

    # run regullar install from ${VAR_TMP_BUNDLE}
    OPTIONS=""
    if [ -n "${SILENT_SUITE_OPT}" ]; then 
        #OPTIONS=" --debug ${SILENT_SUITE_OPT}"
        OPTIONS=" ${SILENT_SUITE_OPT}"
    elif [ "${SILENT}" = "Y" ]; then 
        OPTIONS=" -n"
    fi
    if [ "${FORCE_PKG_OS_REV}" = "10.8" ]; then OPTIONS="${OPTIONS} --rev 10.8"; fi
    if [ -n "${ADJOIN_CMD_OPTIONS}" ] && [ -n "${CLI_OPTIONS}" ]; then
        eval "${VAR_TMP_BUNDLE}/install.sh ${OPTIONS} --adjoin_opt=${ADJOIN_CMD_OPTIONS} --override=${CLI_OPTIONS}"
    elif [ -n "${CLI_OPTIONS}" ]; then
        eval "${VAR_TMP_BUNDLE}/install.sh ${OPTIONS} --override=${CLI_OPTIONS}"
    elif [ -n "${ADJOIN_CMD_OPTIONS}" ]; then
        eval "${VAR_TMP_BUNDLE}/install.sh ${OPTIONS} --adjoin_opt=${ADJOIN_CMD_OPTIONS}"
    else
        ${VAR_TMP_BUNDLE}/install.sh ${OPTIONS}
    fi
    if [ $? -eq 0 ]; then
        rm -rf ${VAR_TMP_BUNDLE}
        exit 0
    else
        exit 1
    fi
} # install_bundle

set_bundle_name ()
{
    BASE_BUNDLE=centrify-suite-${CDC_VER_YEAR}
    BUNDLE_FILE=${BASE_BUNDLE}-${PKG_OS_REV}-${PKG_ARCH}.tgz
    case "${TARGET_OS}" in
    darwin)
        BUNDLE_FILE=${BASE_BUNDLE}-mac${PKG_OS_REV}.tgz
        ;;
    esac

    return $TRUE
} # set_bundle_name

###
set_package_name ()
{
    BASE_PKG=centrifydc
    if [ "$1" = "" ]; then 
        ADD_ON_PKG1=""
    elif [ "$1" = "samba" -a "${SAMBA_VER}" != "" ]; then
        ADD_ON_PKG1="-$1-${SAMBA_VER}"
        debug_echo ADD_ON_PKG1=${ADD_ON_PKG1}
    elif [ "$1" = "cda" -o "$1" = "CentrifyDA" ]; then
        BASE_PKG=centrifyda
        ADD_ON_PKG1=""
    else 
        ADD_ON_PKG1="-$1"
    fi
    case "${TARGET_OS}" in
    linux)
        PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}.rpm
        if [ "${PKG_OS_REV}" = "deb6" ]; then PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}.deb; fi
        ;;
    solaris)
        if [ "$1" = "openssh" ]; then
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}-local.gz # .gz
        elif [ "$1" = "samba" ] && [ "${OS_REV}" = "sol10" -o  "${OS_REV}" = "sol11" ]; then
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-sol10-${PKG_ARCH}-local.gz         # sol-10 .gz
        elif [ "$1" = "samba" ]; then
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}-local.gz # .gz
        elif [ "$1" = "adbindproxy" ] && [ "${OS_REV}" = "sol10" -o  "${OS_REV}" = "sol11" ]; then
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-sol10-${PKG_ARCH}-local.tgz        # sol-10 .tgz 
        else
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}-local.tgz # regular
        fi
        ;;
    hpux)
        PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}.depot.gz
        ;;
    aix)
        if [ "$1" = "samba" -a "${SAMBA_PKGFILE}" = "old" ] || [ "$1" = "openssh" -a "${OPENSSH_PKGFILE}" = "old" ]; then
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}.bff.gz
        elif [ "$1" = "openssh" ] && [ "${OS_REV}" != "aix4.3" ] && \
             [ "`compare_ver ${CDC_VER} 4.4; echo ${COMPARE}`" != "lt" ]; then
            if [ "`cat /etc/security/login.cfg | sed 's/\*.*$//' | sed 's/ //g' | grep -v '^#' | grep -v '#auth_type=PAM_AUTH' | grep 'auth_type=PAM_AUTH'`" != "" ]; then
                PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}-pam-bff.gz
            else
                PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}-lam-bff.gz
            fi
        else
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-${PKG_OS_REV}-${PKG_ARCH}-bff.gz
        fi
        ;;
    darwin)
        if [ "$BASE_PKG" = centrifydc ]; then
            BASE_PKG=CentrifyDC
        fi
        if [ "${DARWIN_PKG_NAME}" = "old" ]; then
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-mac${PKG_OS_REV}-${PKG_ARCH}.tgz
        else
            PKG_FILE=${BASE_PKG}${ADD_ON_PKG1}-${CDC_VER}-mac${PKG_OS_REV}.dmg
        fi
        ;;
    esac
    if [ "${COMPAT_LINK_LIST}" != "" ]; then
        for link in ${COMPAT_LINK_LIST}; do
            LINK_SOURCE=`echo $link | cut -d'=' -f1`
            LINK_DEST=`echo $link | cut -d'=' -f2`
            if [ "${PKG_FILE}" = "${LINK_SOURCE}" ]; then
                debug_echo "!!! found link from ${PKG_FILE} to ${LINK_DEST}"
                PKG_FILE=${LINK_DEST}
            fi
        done
    fi 
} # set_package_name()

### Check that current platform is supported
is_supported ()
{
    set_package_name $1
    LS_PKG_DIR="`ls ${PKG_DIR}`"

    ### find compatible add-on packages

    COMPAT_OS_REV="`list_compat_os_rev ${PKG_OS_REV}`"
    PKG_FILE_1=${PKG_FILE}
    PKG_FILES=""
    for i in ${PKG_OS_REV} ${COMPAT_OS_REV}; do
        if [ "${TARGET_OS}" = "darwin" ]; then
            PKG_FILE_TMP="`echo ${PKG_FILE_1} | sed "s/-mac${PKG_OS_REV}/-mac$i/"`"
        else
            PKG_FILE_TMP="`echo ${PKG_FILE_1} | sed "s/-${PKG_OS_REV}-/-$i-/"`"
        fi
        if [ -x /usr/sbin/zfs ]; then
            /usr/sbin/zfs list / >/dev/null 2>/dev/null
            if [ "${TARGET_OS}" = "solaris" -a "$1" = "samba" -a  $? -eq 0  ]; then
                PKG_FILE_TMP="`echo ${PKG_FILE_1} | sed "s/-${PKG_OS_REV}-/-sol10-/"`"
            fi
        fi

        PKG_FILES="${PKG_FILES} ${PKG_FILE_TMP}"
    done
    for PKG_FILE in ${PKG_FILES} ; do

        ### check if there is an exact match
        for i in ${LS_PKG_DIR}; do
            if [ "${PKG_FILE}" = "$i" ]; then
                return $TRUE
            fi
        done

        if [ "$1" != "" ] && [ -f ${CFG_FNAME_SUITE} ]; then
            ### find any packages version other than $CDC_VER
            PKG_FILE_TMP="`echo ${PKG_FILE} | sed "s/-${CDC_VER}-/-\*-/" `"
            PKG_FILE_LS="`ls -r ${PKG_DIR}${PKG_FILE_TMP} 2>/dev/null | sed 's/\.\///'`"
            if [ "${PKG_FILE_LS}" = "" ]; then
                if [ "$1" = "samba" -o "$1" = "openssh" ]; then
                    PKG_FILE_TMP="`echo ${PKG_FILE_TMP} | sed "s/-bff/.bff/" `"
                    PKG_FILE_LS="`ls -r ${PKG_DIR}${PKG_FILE_TMP} 2>/dev/null | sed 's/\.\///'`"
                fi
            fi
            if [ "${PKG_FILE_LS}" = "" ]; then
                debug_echo "Could not find ${PKG_FILE_TMP} in local directory"
            else
                debug_echo "PKG_FILE_LS=${PKG_FILE_LS}" #####
            
                if [ "$1" = "cda" ]; then
                    PKG=CentrifyDA
                else
                    PKG=CentrifyDC-$1
                fi
                COMPAT_LIST=`cat ${CFG_FNAME_SUITE} | sed  's/\#.*$//' | grep core-${CDC_VER_SHORT} | grep ${PKG} | grep ':+:' | sed 's/ //g'`
                debug_echo "COMPAT_LIST=${COMPAT_LIST}"
                if [ "${COMPAT_LIST}" != "" ]; then
                    for path_file in ${PKG_FILE_LS}; do
                        file="`basename $path_file`"
                        if [ "$1" = "cda" ]; then
                            PKG_FILE_VER=`echo $file | cut -d '-' -f2`
                        elif [ "$1" = "samba" -o "$1" = "openssh" ]; then
                            PKG_FILE_VER=`echo $file | cut -d '-' -f4`
                        else
                            PKG_FILE_VER=`echo $file | cut -d '-' -f3`
                        fi
                        for line in ${COMPAT_LIST}; do
                            COMPAT_VER_LOW=`echo $line | cut -d ':' -f5`
                            COMPAT_VER_HIGH=`echo $line | cut -d ':' -f6`
                            if [ "`compare_ver ${PKG_FILE_VER} ${COMPAT_VER_LOW}; echo ${COMPARE}`" != "lt" ] && \
                                [ "`compare_ver ${PKG_FILE_VER} ${COMPAT_VER_HIGH}; echo ${COMPARE}`" != "gt" ]; then
                                COMPAT_LINK_LIST="${COMPAT_LINK_LIST} ${PKG_FILE_1}=${file}"
                                PKG_FILE=${file}
                                debug_echo "COMPAT_LINK_LIST=${COMPAT_LINK_LIST}"
                                return $TRUE
                            fi
                        done
                    done
                else
                    debug_echo "Found unsupported: PKG_FILE_LS=${PKG_FILE_LS}"
                fi
            fi
        fi

    done
    PKG_FILE=${PKG_FILE_1}

    ### try old package name on MacOS X for backward compatibility (before universal)
    if [ "${TARGET_OS}" = "darwin" ]; then
        PKG_FILE="`echo ${PKG_FILE} | sed "s/.tgz/-${PKG_ARCH}.tgz/"`"
        debug_echo "PKG_FILE=${PKG_FILE}"
        for i in ${LS_PKG_DIR}; do
            if [ "${PKG_FILE}" = "$i" ]; then
                DARWIN_PKG_NAME=old
                return $TRUE
            fi
        done
        ### set back to the new package name if we failed to find the old one
        set_package_name
    fi
    return $FALSE
} # is_supported()

### Find add-on packages
find_supported_addon ()
{
    FOUND_S=$FALSE
    for ADD_ON_PKG2 in ${ADD_ON_LIST}; do
        is_supported ${ADD_ON_PKG2}
        RC=$?
        if [ "$RC" = "0" ]; then
            if [ "${ADD_ON_PKG2}" = "cda" ]; then
                echo INFO: CentrifyDA is supported >> ${LOG_FILE}
            else
                echo INFO: CentrifyDC${SEP}${ADD_ON_PKG2} is supported >> ${LOG_FILE}
            fi
            eval ${ADD_ON_PKG2}=S
            FOUND_S=$TRUE
            debug_echo "${ADD_ON_PKG2}=\c"
            eval echo \$$ADD_ON_PKG2 >> ${DEBUG_OUT}
        fi
    done
    set_package_name
    return ${FOUND_S}
}

### is DA auditing enabled
is_auditing ()
{
        if [ ! -x /usr/sbin/dacontrol ]; then
            DA_NSS=$FALSE
            IS_AUDITING=$FALSE
            if [ "${SILENT}" = "Y" ]; then # in interactive mode user will be asked to enable auditing or not
                if [ "${DA_ENABLE}" = "K" ]; then # on fresh DA install "K" (keep) means do not enable auditing
                    DA_ENABLE="N"
                fi
            fi
            return $TRUE
        fi

        if [ `echo ${CDA_CUR_VER} | cut -d'.' -f1` -ge 3 ]; then
            # DA v.3+ supports NSS
            DA_NSS=$TRUE
            if [ `/usr/bin/dainfo -s > /dev/null 2>&1; echo $?` -ne 0 ]; then
                echo "INFO: Centrify DirectAudit auditing is currently enabled (symlink hooked)." >> ${LOG_FILE}
                IS_AUDITING=$TRUE # means needs to be disabled during upgrade
                if [ "${SILENT}" = "Y" ]; then # in interactive mode user will be asked to enable auditing or not
                    if [ "${DA_ENABLE}" = "K" ]; then # "K" to keep current mode so needs to be re-enabled after upgrade
                        echo "INFO: setting DA_ENABLE=Y ..." >> ${LOG_FILE}
                        DA_ENABLE="Y" # enable after upgrade
                    fi
                fi
            else
                IS_AUDITING=$FALSE # means no need to disable for upgrade
                # in interactive mode user will be asked to enable auditing or not
                if [ "${SILENT}" = "Y" ] && [ "${DA_ENABLE}" = "K" ]; then # "K" to keep current mode, in interactive mode user will be asked
                    if [ `/usr/bin/dainfo | grep " module: Active" >> ${LOG_FILE}; echo $?` -eq 0 ]; then
                        echo "INFO: setting DA_ENABLE=enabled ..." >> ${LOG_FILE}
                        DA_ENABLE="enabled" # override config file value to ensure we don't disable it after upgrade
                    fi
                fi
            fi
            if [ "${SILENT}" = "Y" ] && [ "${DA_ENABLE}" = "K" ]; then # "K" to keep current mode, in interactive mode user will be asked
                # "${DA_ENABLE}" = "K" means auditing is not enabled (neither case above has DA_ENABLE changed)
                echo "INFO: setting DA_ENABLE=N ..." >> ${LOG_FILE}
                DA_ENABLE="N" # override config file value to ensure we disable it after upgrade
            fi
            return $TRUE
        fi

        # fallback to old DA CLI
        DA_NSS=$FALSE
        echo checking DirectAudit status using old CLI ... >> ${LOG_FILE}
        list=`/usr/sbin/dacontrol`

        IFS_ORG="${IFS}"
        if [ -n "`echo -e "\n"`" ]; then
            IFS=$"`echo '\012\001'`"
        else
            IFS=$'\012'
        fi
        IS_AUDITING=$FALSE
        IN_AUDITING_LIST=$FALSE

        for e in $list
        do
            # loop until the begining of the enabled list
            if [ $IN_AUDITING_LIST -eq $FALSE ]; then
                echo $e | grep "is enabled on the following" > /dev/null
                if [ $? -eq 0 ]; then
                    IN_AUDITING_LIST=$TRUE
                fi
                continue
            fi

            # if we come to the end of the auditing list without encounter any audited shell
            echo $e | grep "is NOT enabled on the following" > /dev/null
            if [ $? -eq 0 ]; then
                IS_AUDITING=$FALSE
                if [ "${SILENT}" = "Y" ] && [ "${DA_ENABLE}" = "K" ]; then # in interactive mode user will be asked to enable auditing or not
                    DA_ENABLE="N" # needs to be disabled after upgrade to DA v.3+
                fi
                break
            fi

            # if the line is not begins with a space, it is not one the result
            echo $e | grep "^ " > /dev/null
            if [ $? -eq 1 ]; then
                continue
            fi

            # if the line ends with '/dash', there is a chance that it is not an
            # audited shell, but only due to the name conflict
            echo $e | grep "/dash$" > /dev/null
            if [ $? -eq 0 ]; then
                # Is it a link?
                if [ ! -h $e ]; then
                    # Not a link, but report as auditing. Sign of affected by conflict. Skip it
                    continue
                fi
            fi

            IS_AUDITING=$TRUE
            if [ "${SILENT}" = "Y" ] && [ "${DA_ENABLE}" = "K" ]; then # in interactive mode user will be asked to enable auditing or not
                DA_ENABLE="Y" # needs to be enabled after upgrade
            fi
            break
        done
        IFS="${IFS_ORG}"
        # the next "if" block will be executed only when upgrading from DA v.1+ or v.2+
        if [ "${IS_AUDITING}" = "$FALSE" ]; then
            if [ "${SILENT}" = "Y" ] && [ "${DA_ENABLE}" = "K" ]; then # in interactive mode user will be asked to enable auditing or not
                DA_ENABLE="N" # needs to be disabled after upgrade to DA v.3+
            fi
        fi

    return $TRUE
} # is_auditing()

disable_auditing()
{
    if [ `/usr/bin/dainfo -s > /dev/null 2>&1; echo $?` -ne 0 ]; then
        echo "Disabling auditing (-a) ..." | tee -a ${LOG_FILE}
        /usr/sbin/dacontrol -d -a >> ${LOG_FILE}
        DA_ENABLE=
        IS_AUDITING=$FALSE
    elif [ `/usr/bin/dainfo -m > /dev/null 2>&1; echo $?` -eq 9 ]; then
        echo "Disabling auditing ..." | tee -a ${LOG_FILE}
        /usr/sbin/dacontrol -d >> ${LOG_FILE}
        DA_ENABLE=
        IS_AUDITING=$FALSE
    else
        echo "ERROR: Unknown auditing mode ..." | tee -a ${LOG_FILE}
        return $FALSE
    fi
    return $TRUE
} # disable_auditing()

set_nonglobal_auditing()
{
    if [ "${GLOBAL_ZONE_ONLY}" = "N" ]; then
        for SOL_ZONE in `/usr/sbin/zoneadm list -c`
        do
            ZONE_PATH="`/usr/sbin/zoneadm -z ${SOL_ZONE} list -p | cut -d: -f4`"
            if [ "${ZONE_PATH}" != "/" ] && [ -d ${ZONE_PATH}/root/var ]; then
                echo "INFO: creating ${ZONE_PATH}/root/var/centrify/DA_ENABLE ..." | tee -a ${LOG_FILE}
                rm -f ${ZONE_PATH}/root/var/centrify/DA_ENABLE
                create_verify_dir ${ZONE_PATH}/root/var/centrify
                echo ${DA_ENABLE} > ${ZONE_PATH}/root/var/centrify/DA_ENABLE
            fi
        done
    fi
} # set_nonglobal_auditing()

### Find installed add-on packages
is_addon_installed ()
{
    ADD_ON_INSTALLED=
    for ADD_ON_PKG3 in ${ADD_ON_LIST}; do
        is_installed ${ADD_ON_PKG3}
        RC=$?
        if [ "$RC" = "0" ]; then
            FIELD=3 # version field in the package file-name
            if [ "${ADD_ON_PKG3}" = "openssh" -o "${ADD_ON_PKG3}" = "samba" ]; then FIELD=4; fi
            if [ "${ADD_ON_PKG3}" = "cda" ]; then
                FIELD=2
                echo INFO: CentrifyDA-${INSTALLED_VER} is installed >> ${LOG_FILE}
                echo checking DirectAudit status ... >> ${LOG_FILE}
                is_auditing
            else
                echo INFO: CentrifyDC${SEP}${ADD_ON_PKG3}-${INSTALLED_VER} is installed >> ${LOG_FILE}
            fi
            VAR1=\$"${ADD_ON_PKG3}"
            VAR2=`eval "expr \"\${VAR1}\" "`
            if [ "${VAR2}" = "S" ]; then
                # check if installed and supported versions of add-on package are the same
                set_package_name ${ADD_ON_PKG3}
                SUPPORTED_VER=`echo ${PKG_FILE} | cut -d '-' -f${FIELD}`
                debug_echo "SUPPORTED_VER=${SUPPORTED_VER}"
                if [ "`compare_ver ${SUPPORTED_VER} ${INSTALLED_VER}; echo ${COMPARE}`" = "gt" ]; then
                    eval ${ADD_ON_PKG3}=\$$ADD_ON_PKG3+I # supported is newer than installed
                else
                    eval ${ADD_ON_PKG3}=\$$ADD_ON_PKG3=I # supported is same or older than installed
                fi
            else
                eval ${ADD_ON_PKG3}=I
            fi
            if [ "${ADD_ON_PKG3}" = "cda" ]; then
                ADD_ON_INSTALLED="${ADD_ON_INSTALLED} CentrifyDA-${INSTALLED_VER}"
            else
                ADD_ON_INSTALLED="${ADD_ON_INSTALLED} CentrifyDC${SEP}${ADD_ON_PKG3}-${INSTALLED_VER}"
            fi
            debug_echo "${ADD_ON_PKG3}=\c"
            eval echo \$$ADD_ON_PKG3 >> ${DEBUG_OUT}
        else # not installed
            if [ "${ADD_ON_PKG3}" = "cda" ] && [ "${SILENT}" = "Y" ]; then # in interactive mode user will be asked to enable auditing or not
                if [ "${DA_ENABLE}" = "K" ]; then # on fresh DA install "K" (keep) means do not enable auditing
                    DA_ENABLE="N"
                fi
            fi
        fi
    done
    if [ "${TARGET_OS}" = "linux" -a "${PKG_OS_REV}" = "deb6" ]; then
        ADD_ON_INSTALLED="`echo ${ADD_ON_INSTALLED} | sed 's/CentrifyDC/centrifydc/g' | sed 's/CentrifyDA/centrifyda/g'`"
    elif [ "${TARGET_OS}" = "aix" -a "${OPENSSH_OLD}" = "Y" ]; then
        ADD_ON_INSTALLED="`echo ${ADD_ON_INSTALLED} | sed 's/CentrifyDC\.openssh/CentrifyDC-openssh\.base/g'`"
        debug_echo "ADD_ON_INSTALLED=${ADD_ON_INSTALLED}"
    fi
    set_package_name
    if [ "${ADD_ON_INSTALLED}" = "" ]; then
        return $FALSE
    else
        return $TRUE
    fi
} # is_addon_installed()

### Check if CentrifyDC (or add-on) is installed already
is_installed ()
{
    BASE_PKG=CentrifyDC
    if [ "$1" = "" ]; then 
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: is_installed: " >> ${LOG_FILE}
        ADD_ON_PKG4=""
    elif [ "$1" = "cda" ]; then
        BASE_PKG=CentrifyDA
        ADD_ON_PKG4=""
    else
        ADD_ON_PKG4="-$1"
    fi
    case "${TARGET_OS}" in
    linux)
        if [ "${PKG_OS_REV}" = "deb6" ]; then
            BASE_PKG=`echo ${BASE_PKG} | tr  ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz`
            ### check for "broken" package first
            dpkg -s ${BASE_PKG}${ADD_ON_PKG4} 2> /dev/null | grep Status: | grep unpacked >> ${LOG_FILE} && \
                    {
                        if [ "${SILENT}" = "NO" ]; then
                            echo $ECHO_FLAG "\nWARNING: found unpacked ${BASE_PKG}${ADD_ON_PKG4} which should be removed." | tee -a ${LOG_FILE}
                            QUESTION="\nDo you want to uninstall it now? (Y|N|Q) [Y]:\c"; do_ask_YorN
                        else
                            ANSWER="Y"
                        fi
                        if [ "${ANSWER}" = "Y" ]; then
                            do_remove ${BASE_PKG}${ADD_ON_PKG4} \
                                      || { echo "uninstalling ${BASE_PKG}${ADD_ON_PKG4} failed ..."; do_error $CODE_EUN; }
                        else
                            do_error
                        fi
                    }
            dpkg -s ${BASE_PKG}${ADD_ON_PKG4} 2> /dev/null | grep Status: | grep installed | grep -v not-installed >> ${LOG_FILE} \
                    && { INSTALLED="Y"; } || { INSTALLED="N"; }
        else
            rpm -q ${BASE_PKG}${ADD_ON_PKG4} >> ${LOG_FILE} 2> /dev/null \
                    && { INSTALLED="Y"; } || { INSTALLED="N"; }
        fi;;
    solaris)
        pkginfo -l ${BASE_PKG}${ADD_ON_PKG4} >> ${LOG_FILE} 2> /dev/null \
                && { INSTALLED="Y"; } || { INSTALLED="N"; } 
        ;;
    hpux)
        /usr/sbin/swlist -a revision ${BASE_PKG}${ADD_ON_PKG4} >> ${LOG_FILE} 2> /dev/null \
                && { INSTALLED="Y"; } || { INSTALLED="N"; } 
        ;;
    aix)
        if [ "$1" = "" -o "$1" = "cda" ]; then ADD_ON_PKG4=".core"; else ADD_ON_PKG4=".$1"; fi
        lslpp -l ${BASE_PKG}${ADD_ON_PKG4} >> ${LOG_FILE} 2> /dev/null \
                && { INSTALLED="Y"; } || { INSTALLED="N"; } 
        if [ "$1" = "openssh" -a "${INSTALLED}" = "N" ]; then # try to find old cdc-openss package
            lslpp -l CentrifyDC-openssh.base >> ${LOG_FILE} 2> /dev/null \
                    && { INSTALLED="Y"; OPENSSH_OLD="Y"; } || { INSTALLED="N"; }
        fi
        ;;
    darwin)
        if [ "$1" = "" ]; then
            if [ -x $USRBIN/adinfo -a -x $USRSBIN/adjoin ]; then INSTALLED="Y"; else INSTALLED="N"; fi
        elif [ "$1" = "krb5" ]; then
            if [ "`ls ${DATADIR}/centrifydc-$1-*.tgz.lst 2> /dev/null | wc -w | sed 's/^[ ^t]*//'`" != "0" ] || \
               [ -x ${DATADIR}/centrifydc/kerberos/bin/ftp -a -x ${DATADIR}/centrifydc/kerberos/sbin/ftpd ]; then INSTALLED="Y"; else INSTALLED="N"; fi
        elif [ "$1" = "ldapproxy" ]; then
            if [ "`ls ${DATADIR}/centrifydc/centrifydc-$1-*.tgz.lst 2> /dev/null | wc -w | sed 's/^[ ^t]*//'`" != "0" ] || \
               [ -x ${DATADIR}/centrifydc/libexec/slapd -a -f ${DATADIR}/centrifydc/etc/openldap/ldapproxy.slapd.conf ]; then INSTALLED="Y"; else INSTALLED="N"; fi
        elif [ "$1" = "adfixid" ]; then
            if [ "`ls ${DATADIR}/centrifydc/centrifydc-$1-*.tgz.lst 2> /dev/null | wc -w | sed 's/^[ ^t]*//'`" != "0" ]; then
                INSTALLED="Y"; else INSTALLED="N"; fi
        elif [ "$1" = "utest" ]; then
            if [ "`ls ${DATADIR}/centrifydc/centrifydc-$1-*.tgz.lst 2> /dev/null | wc -w | sed 's/^[ ^t]*//'`" != "0" ] || \
               [ "`ls ${DATADIR}/centrifydc/tests/bin/ 2> /dev/null | wc -w | sed 's/^[ ^t]*//'`" != "0" ]; then INSTALLED="Y"; else INSTALLED="N"; fi
        elif [ "$1" = "cda" ]; then
            # CDA is not supported on Mac OS
            INSTALLED="N"
        else
            INSTALLED="N"
        fi
        ;;
    esac
    if [ "${INSTALLED}" = "Y" ]; then
        get_cur_version $1
        if [ "$1" = "" ]; then
            # Check licensed mode
            if [ "`compare_ver ${CUR_VER} 4.4; echo ${COMPARE}`" = "lt" ]; then
                ADLICENSE="Y"
            else
                if [ -x ${USRBIN}/adlicense ]; then
                    if [ "${SILENT}" = "NO" ]; then
                        ${USRBIN}/adlicense | grep licensed > /dev/null 2> /dev/null
                        if [ $? -eq 0 ]; then
                            ADLICENSE="Y"
                        else
                            ADLICENSE="N"
                            echo $ECHO_FLAG "\n${THIS_PRG_NAME}: Upgrading Express, license=N" >> ${LOG_FILE}
                        fi
                    else
                        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: Non-interactive mode, ADLICENSE=${ADLICENSE}" >> ${LOG_FILE}
                    fi
                else
                    # Express mode is not supported
                    ADLICENSE="Y"
                fi
            fi
            # Check if already joined
            if [ -s ${VAR}/centrifydc/kset.domain ]; then
                ADJOINED="Y"
            fi
        fi
        return $TRUE
    else
        return $FALSE
    fi
} # is_installed()

### Detect version of the currently installed package (detect_version() replacement)
get_cur_version ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: get_cur_version: " >> ${LOG_FILE}
    INSTALLED_VER="0.0.0-000" # unknown version
    BASE_PKG=CentrifyDC
    FIELD="2-3"
    if [ "$1" = "" ]; then
        ADD_ON_PKG9=""
    elif [ "$1" = "cda" ]; then
        BASE_PKG=CentrifyDA
        ADD_ON_PKG9=""
    elif [ "$1" = "samba" -o "$1" = "openssh" ]; then
        ADD_ON_PKG9="-$1"
        FIELD="4-5"
    else
        ADD_ON_PKG9="-$1"
        FIELD="3-4"
    fi
    case "${TARGET_OS}" in
    linux)
        if [ "${PKG_OS_REV}" = "deb6" ]; then
            BASE_PKG=`echo ${BASE_PKG} | tr  ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz`
            INSTALLED_VER=`dpkg -s ${BASE_PKG}${ADD_ON_PKG9} 2> /dev/null | grep Version | cut -d ' ' -f2`
        else
            # On platforms other than i386, the package info may include
            # the arch like this: <pkg-name>-x.x.x-xxx.<arch>
            # Remove both the package name and arch here,
            # where the arch must contain alphabet char or '_'.
            INSTALLED_VER=`rpm -q ${BASE_PKG}${ADD_ON_PKG9} 2> /dev/null | sed -e "s/${BASE_PKG}${ADD_ON_PKG9}-//" -e 's/\.[^\.]*[a-zA-Z_][^\.]*$//'`
        fi
        if [ "$FIELD" = "4-5" ]; then
            # <upstream-ver>-<cdc-ver>.<build> or
            # <upstream-ver>-<cdc-ver>-<build>
            INSTALLED_VER=`echo ${INSTALLED_VER} | sed -e 's/^[^-]*-//' -e 's/^\([0-9]*\.[0-9]*\.[0-9]*\)\./\1-/'`
        fi
        ;;
    solaris)
        INSTALLED_VER=`pkginfo -l ${BASE_PKG}${ADD_ON_PKG9} 2> /dev/null | grep VERSION | cut -d ' ' -f6`
        if [ "$FIELD" = "4-5" ]; then
            if echo "$INSTALLED_VER" | grep "-" > /dev/null 2>&1 ; then
                INSTALLED_VER=`echo ${INSTALLED_VER} | sed 's/^[^-]*-//'`
            elif [ "$1" = "openssh" ]; then
                # Openssh version number does not contain CDC version
                # Run ssh command to get the installed version
                INSTALLED_VER=`/usr/share/centrifydc/bin/ssh -V 2>&1 | sed 's/.*build \([0-9\.-]*\).*/\1/'`
            fi
        fi 
        ;;
    hpux)
        INSTALLED_VER=`/usr/sbin/swlist -a revision ${BASE_PKG}${ADD_ON_PKG9} 2> /dev/null | grep "# ${BASE_PKG}" | sed "s/[[:space:]]\{1,\}/ /g" | cut -d ' ' -f3`
        if [ "$FIELD" = "4-5" ]; then
            # <upstream-ver>-<cdc-ver>.<build> or
            # <upstream-ver>-<cdc-ver>-<build>
            INSTALLED_VER=`echo ${INSTALLED_VER} | sed -e 's/^[^-]*-//' -e 's/^\([0-9]*\.[0-9]*\.[0-9]*\)\./\1-/'`           
        fi
        ;;
    aix)
        if [ "$1" = "" -o "$1" = "cda" ]; then ADD_ON_PKG9=".core"; else ADD_ON_PKG9=".$1"; fi
        INSTALLED_VER=`lslpp -l ${BASE_PKG}${ADD_ON_PKG9} 2> /dev/null | grep ${BASE_PKG} | \
                                     sed s/${BASE_PKG}${ADD_ON_PKG9}// | sed s/" "//g | sed s/COMMITTED/F/ | cut -d 'F' -f1`
        if [ "$FIELD" = "4-5" ]; then
            # <upstream-ver-major>.<upstream-ver-minor>.<cdc-short-ver>.<build>
            INSTALLED_BUILD=`echo ${INSTALLED_VER} | cut -d '.' -f4`
            INSTALLED_VER=`echo ${INSTALLED_VER} | cut -d '.' -f3 | sed 's/\([0-9]\)/\1./g' | sed "s/\.\$/.${INSTALLED_BUILD}/"`
        fi
        INSTALLED_VER=`echo ${INSTALLED_VER} | sed 's/\.\([0-9]*\)$/-\1/'`
        ;;
    darwin)
        BASE_PKG=`echo ${BASE_PKG} | tr  ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz`
        if [ "`ls /usr/share/centrifydc/${BASE_PKG}${ADD_ON_PKG9}-*.tgz.lst 2> /dev/null | wc -w | sed 's/^[ ^t]*//'`" = "1" ]; then
            FULL_LST_FILE_NAME=`ls /usr/share/centrifydc/${BASE_PKG}${ADD_ON_PKG9}-*.tgz.lst`
            LST_FILE_NAME=`basename ${FULL_LST_FILE_NAME}`
            INSTALLED_VER=`echo ${LST_FILE_NAME} | cut -d '-' -f${FIELD}`
        elif [ "$1" = "" ]; then
            echo $ECHO_FLAG "WARNING: using adinfo -v to get current version ... " >> ${LOG_FILE}
            INSTALLED_VER=`${USRBIN}/adinfo -v | cut -d ' ' -f 3 | sed 's/)//'`
        else
            echo $ECHO_FLAG "WARNING: cannot get <${ADD_ON_PKG9}> package version ... " >> ${LOG_FILE}
            return $FALSE
        fi
        ;;
    esac
    # cache upgrade needs full current version
    if [ "$1" = "" ]; then
        CDC_CUR_VER_FULL=${INSTALLED_VER}
        debug_echo "INFO: CDC_CUR_VER_FULL=${CDC_CUR_VER_FULL}"
    fi
    # pick up the checksum number
    CDC_CUR_CHECK_SUM=`/usr/share/centrifydc/bin/adcache -s 2>/dev/null | grep 0x`
    # cut off build bumber
    INSTALLED_VER=`echo ${INSTALLED_VER} | cut -d '-' -f1`
    # to be backward compatible with detect_version()
    if [ "$1" = "" ]; then
        CUR_VER=${INSTALLED_VER}
        echo $ECHO_FLAG "INFO: CUR_VER=${CUR_VER}" >> ${LOG_FILE}
    elif [ "$1" = "cda" ]; then
        CDA_CUR_VER=${INSTALLED_VER}
        echo $ECHO_FLAG "INFO: CDA_CUR_VER=${CDA_CUR_VER}" >> ${LOG_FILE}
    fi
    return $TRUE
} # get_cur_version()

### find Perl
is_perl_installed () 
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: is_perl_installed: " >> ${LOG_FILE}
    echo "looking for Perl ..." >> ${LOG_FILE}
    PERL_DIRS="/bin /usr/bin /usr/local/bin /opt/bin /opt/perl/bin /opt/perl5/bin"
    for dir in `(IFS=:; set -- $PATH; echo "$@")` ${PERL_DIRS}
    do
        # If this file is a plain executable, we found it.
        if [ -x "$dir/perl" -a -f "$dir/perl" ]; then
            # Some systems have a broken perl earlier in the path;
            # test this one to make sure it works.
            if "$dir/perl" -e 'use 5.008;' > /dev/null 2>&1; then
                perl="$dir/perl"
                echo "found Perl: ${perl}" >> ${LOG_FILE}
                break
	    fi
        fi
    done

    if [ "$perl" = "" ]; then
        echo $ECHO_FLAG "\nWARNING:" | tee -a ${LOG_FILE}
        echo $ECHO_FLAG "Could not find Perl required by Group Policy (GP) functionality.\n" | tee -a ${LOG_FILE}
        return ${FALSE}
    fi
}

### disable GP in centrifydc.conf
disable_GP ()
{
    echo $ECHO_FLAG "\nWARNING: disabling GP in /etc/centrifydc/centrifydc.conf" >> ${LOG_FILE}
    cp -p /etc/centrifydc/centrifydc.conf /etc/centrifydc/centrifydc.conf.tmp
    sed -e "s/[# ]gp.disable.all: true/gp.disable.all: true/" \
        /etc/centrifydc/centrifydc.conf.tmp > /etc/centrifydc/centrifydc.conf
    echo $ECHO_FLAG "WARNING:" | tee -a ${LOG_FILE}
    echo $ECHO_FLAG "Group Policy (GP) functionality has been disabled.\n" | tee -a ${LOG_FILE}
    return ${TRUE}
}

### update keytab file
update_keytab ()
{
    
    # Update keytab if adclient is in connected status
    echo $ECHO_FLAG "start to update keytab ..." >> ${LOG_FILE}
    ADCLIENT_MODE=""
    for i in 1 2 3 4
    do
        ADCLIENT_MODE="`/usr/bin/adinfo -m`"
        if [ "X${ADCLIENT_MODE}" = "Xstarting" -o "X${ADCLIENT_MODE}" = "X<unavailable>" ]; then
            echo $ECHO_FLAG "Adclient is ${ADCLIENT_MODE}. Wait for $i second(s)." >> ${LOG_FILE}
            sleep $i
        else
            break
        fi
    done

    if [ "X${ADCLIENT_MODE}" = "Xconnected" ]; then
        echo $ECHO_FLAG "updating keytab ..." >> ${LOG_FILE}
        /usr/sbin/adkeytab -C -m >> ${LOG_FILE} 2>> ${LOG_FILE}
    else
        echo $ECHO_FLAG "skip to update keytab. Adclient is ${ADCLIENT_MODE}." >> ${LOG_FILE}
    fi

    if [ $? -eq 0 ]; then
        return ${TRUE}
    fi
    
    debug_echo "Updating keytab failed. Checking ${LOG_FILE} to get detail error."
    return ${FALSE}
}

### find adcheck utility
search_adcheck ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: search_adcheck: " >> ${LOG_FILE}
    debug_echo "ADCHECK_FNAME=${ADCHECK_FNAME}"
    if [ -x "${ADCHECK_FNAME}" ]; then
        echo "... found" >> ${LOG_FILE}
    else
        if [ -f "${ADCHECK_FNAME}" ]; then
            echo $ECHO_FLAG "\nFound ${ADCHECK_FNAME} but it's not executable." | tee -a ${LOG_FILE}
        else
            echo $ECHO_FLAG "\nCould not find ${ADCHECK_FNAME} utility in local directory." | tee -a ${LOG_FILE}
        fi
        if [ "${SILENT}" = "NO" -a "${OS_CHECK}" != "skip" ]; then
            QUESTION="\nDo you want to continue installation? (Q|Y|N) [Y]:\c"; do_ask_YorN
            if [ ${ANSWER} != "Y" ]; then do_quit; fi
        fi
        ADCHECK_FNAME=""
        return ${FALSE}
    fi
    return ${TRUE}
}

### run adcheck utility
run_adcheck ()
{
    echo $ECHO_FLAG "\nRunning ${ADCHECK_FNAME} ..." | tee -a ${LOG_FILE}
    if [ "$1" = "" ]; then
        ${ADCHECK_FNAME} "patch.test" -t os -t net; ADCHECK_RC=$?
    else
        ${ADCHECK_FNAME} $1 -t ad; ADCHECK_RC=$?
    fi
    if [ "${ADCHECK_RC}" = "0" ]; then
        return ${TRUE}
    elif [ "${ADCHECK_RC}" = "1" -o "${ADCHECK_RC}" = "2" ]; then
        echo $ECHO_FLAG "\nWARNING: adcheck exited with warning(s)." | tee -a ${LOG_FILE}
        return ${TRUE}
    else
        echo $ECHO_FLAG "\nWARNING: adcheck exited with error(s)." | tee -a ${LOG_FILE}
        return ${FALSE}
    fi
}

### ask "YES or NO" QUESTION and read the ANSWER
do_ask_YorN () 
{
    ANSWER=""
    while [ "${ANSWER}" != "Y" -a "${ANSWER}" != "y" -a "${ANSWER}" != "N" -a "${ANSWER}" != "n" ]
    do
        echo ${ECHO_FLAG} "${QUESTION}"
        read ANSWER
        if [ "${ANSWER}" = "q" -o "${ANSWER}" = "Q" ]; then do_quit; fi
        if [ "$1" = "N" ]; then # default answer "N"
            if [ "${ANSWER}" = "" -o "${ANSWER}" = "n" ]; then ANSWER="N"; fi
            if [ "${ANSWER}" = "y" ]; then ANSWER="Y"; fi
        else
            if [ "${ANSWER}" = "" -o "${ANSWER}" = "y" ]; then ANSWER="Y"; fi
            if [ "${ANSWER}" = "n" ]; then ANSWER="N"; fi
        fi
        if [ "$2" = "C" ] && [ "${ANSWER}" = "c" -o "${ANSWER}" = "C" ]; then ANSWER="Y"; fi
    done
}

### ask about already installed package with available upgrade
do_ask_EorUorK ()
{
            QUESTION="\n${1}${2} is installed. Do you want to erase it (E), \nupdate (U) to ${3} or keep (K) current ${1} package? (Q|E|U|K) [K]:\c"
            ANSWER=""
            while [ "${ANSWER}" != "E" -a "${ANSWER}" != "U" -a "${ANSWER}" != "K" ]
            do
                echo ${ECHO_FLAG} ${QUESTION}
                read ANSWER
                if [ "${ANSWER}" = "q" -o "${ANSWER}" = "Q" ]; then do_quit; fi
                if [ "${ANSWER}" = "e" -o "${ANSWER}" = "E" ]; then
                    if [ "${1}" = "CentrifyDC" ]; then
                        UNINSTALL="Y"
                        do_remove_main
                        # do_remove_main() never returns
                    else
                        ANSWER="E"
                    fi
                fi
                if [ "${ANSWER}" = "u" ]; then ANSWER="U"; fi
                if [ "${ANSWER}" = "" -o "${ANSWER}" = "k" ]; then ANSWER="K"; fi
            done
}

### ask about already installed package with available reinstall
do_ask_EorRorK ()
{
            QUESTION="\n${1}${2} is already installed. Do you want to erase it (E), \nreinstall (R) ${3} or keep (K) current ${1} package? (Q|E|R|K) [K]:\c"
            ANSWER=""
            while [ "${ANSWER}" != "E" -a "${ANSWER}" != "R" -a "${ANSWER}" != "K" ]
            do
                echo ${ECHO_FLAG} ${QUESTION}
                read ANSWER
                if [ "${ANSWER}" = "q" -o "${ANSWER}" = "Q" ]; then do_quit; fi
                if [ "${ANSWER}" = "e" -o "${ANSWER}" = "E" ]; then
                    if [ "${1}" = "CentrifyDC" ]; then
                        UNINSTALL="Y"
                        do_remove_main
                        # do_remove_main() never returns
                    else
                        ANSWER="E"
                    fi
                fi
                if [ "${ANSWER}" = "r" ]; then ANSWER="R"; fi
                if [ "${ANSWER}" = "" -o "${ANSWER}" = "k" ]; then ANSWER="K"; fi
            done
}

### ask about already installed package (no upgrade)
do_ask_EorK ()
{
            QUESTION="\n${1}${2} is installed. Do you want to erase it (E) or keep (K)\n current ${1} package? (Q|E|K) [K]:\c"
            ANSWER=""
            while [ "${ANSWER}" != "E" -a "${ANSWER}" != "K" ]
            do
                echo ${ECHO_FLAG} ${QUESTION}
                read ANSWER
                if [ "${ANSWER}" = "q" -o "${ANSWER}" = "Q" ]; then do_quit; fi
                if [ "${ANSWER}" = "e" -o "${ANSWER}" = "E" ]; then
                    if [ "${1}" = "CentrifyDC" ]; then
                        UNINSTALL="Y"
                        do_remove_main
                        # do_remove_main() never returns
                    else
                        ANSWER="E"
                    fi
                fi
                if [ "${ANSWER}" = "" -o "${ANSWER}" = "k" ]; then ANSWER="K"; fi
            done
}

### ask the QUESTION and read the ANSWER (accept empty input)
do_ask () 
{
    ANSWER=""
    echo ${ECHO_FLAG} "${QUESTION}"
    read ANSWER
    if [ "${ANSWER}" = "q" -o "${ANSWER}" = "Q" ]; then do_quit; fi
}

### Suite prompt
do_suite_prompt ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_suite_prompt: " >> ${LOG_FILE}

    echo ""
    echo "With this script, you can perform the following tasks:"
    if [ -f ${CFG_FNAME_SUITE} -a "${SUPPORTED}" = "Y" ] && \
       [ "${INSTALLED}" != "Y" -o "`compare_ver ${CDC_VER} ${CUR_VER}; echo ${COMPARE}`" = "gt" ]; then
        SUITE=""
        QUESTION="How do you want to proceed? ("; QUESTION_SEP=""
        QUESTION_DEFAULT="S"
        if [ "${ENTERPRISE_PL}" -eq $TRUE ]; then
            QUESTION="${QUESTION}${QUESTION_SEP}E"; QUESTION_SEP="|"
            echo "    - Install (update) Centrify Suite Enterprise Edition (License required) [E]"
            QUESTION_DEFAULT="E"
        fi
        QUESTION="${QUESTION}${QUESTION_SEP}S"; QUESTION_SEP="|"
        echo "    - Install (update) Centrify Suite Standard Edition (License required) [S]"

        if [ "${EXPRESS_PL}" -eq $TRUE ]; then
            QUESTION="${QUESTION}${QUESTION_SEP}X"; QUESTION_SEP="|"
            echo "    - Install (update) Centrify Suite Express Edition [X]"
            if [ "${EXPRESS_QUESTION_DEFAULT}" = "X" ]; then
                QUESTION_DEFAULT="X"
            fi
        fi
        QUESTION="${QUESTION}${QUESTION_SEP}C"; QUESTION_SEP="|"
        echo "    - Custom install (update) of individual packages [C]"
        if [ "${INSTALLED}" = "Y" ]; then
            QUESTION="${QUESTION}${QUESTION_SEP}U"; QUESTION_SEP="|"
            echo "    - Uninstall of all Centrify packages [U]"
        fi
        QUESTION="${QUESTION}${QUESTION_SEP}Q) [${QUESTION_DEFAULT}]: \c"
    else
        SUITE="Custom"
        echo "    - Install, update or remove the Centrify DirectControl packages"
        echo "    - Check OS, network and Active Directory configuration"
        echo "    - Join an Active Directory domain"
        echo "    - Restart the local computer after installation"
        QUESTION=""
    fi

    echo ""
    echo "You can type Q at any prompt to quit the installation and exit"
    echo "the script without making any changes to your environment."
    echo ""

    show_installed
    if [ "${SUITE}" != "Custom" ]; then
        CONTINUE="N"
        while [ "${CONTINUE}" = "N" ]; do
            do_ask
            ANSWER=`echo ${ANSWER} | tr abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ`
            if [ "${ANSWER}" = "" ]; then
                ANSWER="${QUESTION_DEFAULT}"
            fi
            if [ "${ANSWER}" = "E" -a "${ENTERPRISE_PL}" -eq $TRUE ]; then
                SUITE="Enterprise"
                EXPRESS="N"
                set_silent_cfg
                CONTINUE="Y"
            elif [ "${ANSWER}" = "S" ]; then
                SUITE="Standard"
                EXPRESS="N"
                set_silent_cfg
                CONTINUE="Y"
            elif [ "${ANSWER}" = "X" -a "${EXPRESS_PL}" -eq $TRUE ]; then
                SUITE="Standard"
                EXPRESS="Y"
                set_silent_cfg
                CONTINUE="Y"
            elif [ "${ANSWER}" = "C" ]; then
                SUITE="Custom"
                CONTINUE=""
            elif [ "${ANSWER}" = "U" -a "${INSTALLED}" = "Y" ]; then
                UNINSTALL="Y"
                do_remove_main
                # do_remove_main() never returns
            else
                echo "Unexpected input ..."
            fi
        done
        CONTINUE="N"
    fi
    return $TRUE
} # do_suite_prompt()

### Prompt user for relevant information
do_prompt ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_prompt: " >> ${LOG_FILE}

    # INSTALL
    while [ "${INSTALL}" != "Y" ]; do
        if [ "${INSTALLED}" = "Y" ]; then
            if [ "${SUPPORTED}" = "Y" -a "`compare_ver ${CDC_VER} ${CUR_VER}; echo ${COMPARE}`" = "gt" ]; then
                do_ask_EorUorK CentrifyDC -${CUR_VER} ${CDC_VER}
            elif [ "${SUPPORTED}" = "Y" ]; then
                do_ask_EorRorK CentrifyDC -${CUR_VER} ${CDC_VER}
            else
                do_ask_EorK CentrifyDC -${CUR_VER}
            fi
            if [ ${ANSWER} = "U" ]; then
                INSTALL="U"
                break
            elif [ ${ANSWER} = "R" ]; then
                INSTALL="R"
                if [ "${TARGET_OS}" = "aix" ]; then
                    FORCE_OPTION="-F" # Force reinstall
                elif [ "${TARGET_OS}" = "hpux" ]; then
                    FORCE_OPTION="-x reinstall=true" # Force reinstall
                fi
                break
            else
                INSTALL="K"
                break
            fi
        else
            QUESTION="\nInstall the Centrify DirectControl ${CDC_VER} package? (Q|Y|N) [Y]:\c"; do_ask_YorN
            if [ ${ANSWER} = "Y" ]; then
                INSTALL="Y"
            else
                QUESTION="Do you want to exit the installation? (Q|Y|N) [Y]:\c"; do_ask_YorN
                if [ ${ANSWER} = "Y" ]; then
                    do_quit
                else
                    echo Centrify DirectControl agent is not installed. Please install it first.
                    ANSWER=""
                fi
            fi
        fi
    done

    # bail on mac if asked to install/upgrade 3.x or earlier
    min_version_required || { echo $ECHO_FLAG "\nERROR: This version of ${THIS_PRG_NAME} cannot be used with CentrifyDC $CDC_VER"; do_error; }

    if [ "${INSTALL}" = "Y" -o "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then
        PKG_FILE_LIST=${PKG_DIR}${PKG_FILE}
        PKG_I_LIST="CentrifyDC"
        if [ "${TARGET_OS}" = "aix" ]; then PKG_I_LIST="CentrifyDC.core"; fi
    fi
    # ADD ON PACKAGES
    for ADD_ON_PKG5 in ${ADD_ON_LIST}; do
        if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "cda" ]; then
            ADD_ON_PKG_FULL="CentrifyDA.core"
            FIELD=2
            CUR_ADD_ON_VER=${CDA_CUR_VER}
        elif [ "${ADD_ON_PKG5}" = "cda" ]; then
            ADD_ON_PKG_FULL="CentrifyDA"
            FIELD=2
            CUR_ADD_ON_VER=${CDA_CUR_VER}
        else
            FIELD=3 # version field in the package file-name
            if [ "${ADD_ON_PKG5}" = "openssh" -o "${ADD_ON_PKG5}" = "samba" ]; then FIELD=4; fi
            ADD_ON_PKG_FULL="CentrifyDC${SEP}${ADD_ON_PKG5}"
            # find currently installed add-on package version
            for ADD_ON_PKG10 in ${ADD_ON_INSTALLED}; do
                CUR_ADD_ON_VER=""
                ADD_ON_PKG10=`echo ${ADD_ON_PKG10} | sed "s/DC\./DC-/"`
                if [ `echo ${ADD_ON_PKG10} | cut -d '-' -f2` = "${ADD_ON_PKG5}" ]; then
                    CUR_ADD_ON_VER=`echo ${ADD_ON_PKG10} | cut -d '-' -f3`     # x.x.x
                    #CUR_ADD_ON_VER=`echo ${ADD_ON_PKG10} | cut -d '-' -f3-4`   # x.x.x-xxx
                    break
                fi
            done
        fi
        set_package_name ${ADD_ON_PKG5}
        ADD_ON_VER=`echo ${PKG_FILE} | cut -d '-' -f${FIELD}`
        if [ "${ADD_ON_PKG5}" = "cda" ]; then CDA_VER=${ADD_ON_VER}; fi

        VAR1=\$"${ADD_ON_PKG5}"
        VAR2=`eval "expr \"\${VAR1}\" "`

        if [ "${VAR2}" = "S" ]; then # supported, not installed
            if [ "${ADD_ON_PKG5}" = "cda" ]; then
                QUESTION="\nInstall the Centrify DirectAudit ${ADD_ON_VER} package? (Q|Y|N) [N]:\c"; do_ask_YorN "N"
            elif [ "${ADD_ON_PKG5}" = "openssh" ]; then
                QUESTION="\nInstall the CentrifyDC-${ADD_ON_PKG5} ${ADD_ON_VER} package? (Q|Y|N) [Y]:\c"; do_ask_YorN
            else
                QUESTION="\nInstall the CentrifyDC-${ADD_ON_PKG5} ${ADD_ON_VER} package? (Q|Y|N) [N]:\c"; do_ask_YorN "N"
            fi
            if [ "${ANSWER}" = "Y" ]; then
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+Y
                PKG_FILE_LIST="${PKG_FILE_LIST} ${PKG_DIR}${PKG_FILE}"
                PKG_I_LIST="${PKG_I_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+N
            fi
        elif [ "${VAR2}" = "S+I" ]; then # supported and installed (different versions)
            if [ "${ADD_ON_PKG5}" = "cda" ]; then
                do_ask_EorUorK CentrifyDA -${CUR_ADD_ON_VER} ${ADD_ON_VER}
            else
                do_ask_EorUorK CentrifyDC-${ADD_ON_PKG5} -${CUR_ADD_ON_VER} ${ADD_ON_VER}
            fi
            if [ "${ANSWER}" = "U" ]; then
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+U
                PKG_FILE_LIST="${PKG_FILE_LIST} ${PKG_DIR}${PKG_FILE}"
                PKG_I_LIST="${PKG_I_LIST} ${ADD_ON_PKG_FULL}"
            elif [ "${ANSWER}" = "E" ]; then
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+E
                if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "openssh" -a "${OPENSSH_OLD}" = "Y" ]; then
                    ADD_ON_PKG_FULL="CentrifyDC-openssh.base"
                fi
                PKG_E_LIST="${PKG_E_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+K
            fi
        elif [ "${VAR2}" = "S=I" ]; then # supported and installed (same versions)
            if [ "${ADD_ON_PKG5}" = "cda" ]; then
                do_ask_EorRorK CentrifyDA -${CUR_ADD_ON_VER} ${ADD_ON_VER}
            else
                do_ask_EorRorK CentrifyDC-${ADD_ON_PKG5} -${CUR_ADD_ON_VER} ${ADD_ON_VER}
            fi
            if [ "${ANSWER}" = "R" ]; then
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+R
                PKG_FILE_LIST="${PKG_FILE_LIST} ${PKG_DIR}${PKG_FILE}"
                PKG_I_LIST="${PKG_I_LIST} ${ADD_ON_PKG_FULL}"
                if [ "${TARGET_OS}" = "aix" ]; then
                    FORCE_OPTION="-F" # Force reinstall
                elif [ "${TARGET_OS}" = "hpux" ]; then
                    FORCE_OPTION="-x reinstall=true" # Force reinstall
                fi
            elif [ "${ANSWER}" = "E" ]; then
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+E
                if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "openssh" -a "${OPENSSH_OLD}" = "Y" ]; then
                    ADD_ON_PKG_FULL="CentrifyDC-openssh.base"
                fi
                PKG_E_LIST="${PKG_E_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+K
            fi
        elif [ "${VAR2}" = "I" ]; then # installed, not supported
            if [ "${ADD_ON_PKG5}" = "cda" ]; then
                do_ask_EorK CentrifyDA -${CUR_ADD_ON_VER}
            else
                do_ask_EorK CentrifyDC-${ADD_ON_PKG5} -${CUR_ADD_ON_VER}
            fi
            if [ "${ANSWER}" = "E" ]; then
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+E
                if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "openssh" -a "${OPENSSH_OLD}" = "Y" ]; then
                    ADD_ON_PKG_FULL="CentrifyDC-openssh.base"
                fi
                PKG_E_LIST="${PKG_E_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG5}=\$$ADD_ON_PKG5+K
            fi
        fi
        set_package_name
    done
    debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
    debug_echo "PKG_I_LIST=${PKG_I_LIST}"
    debug_echo "PKG_E_LIST=${PKG_E_LIST}"
    debug_echo INSTALL=${INSTALL}
    return $TRUE
} # do_prompt()

### set GLOBAL_ZONE_ONLY
do_prompt_gz ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_prompt_gz: " >> ${LOG_FILE}
    if [ "${GLOBAL_ZONE_ONLY}" != "non_global" -a "${INSTALLED}" = "Y" -a "${PKG_FILE_LIST}" != "" ]; then
        is_installed_gz_only || INSTALLED_GZ_ONLY="N"
    fi
    if [ "${INSTALLED}" = "Y" -a "${PKG_FILE_LIST}" != "" -a "${INSTALLED_GZ_ONLY}" = "N" ] || \
       [ "${INSTALLED}" = "N" -a "${PKG_FILE_LIST}" != "" ]; then
        if [ "${GLOBAL_ZONE_ONLY}" != "non_global" ]; then
            QUESTION="\nSolaris 10 global zone detected.\nDo you want to install CentrifyDC in the current Solaris zone only? (Q|Y|N) [N]:\c"
            do_ask_YorN "N"; GLOBAL_ZONE_ONLY=${ANSWER}
        fi
    fi
    return $TRUE
} # do_prompt_gz()

###
determine_license ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: determine_license: " >> ${LOG_FILE}
    if [ "${EXPRESS_PL}" -eq $TRUE ]; then
        if [ -z "${EXPRESS}" ]; then
            # even if licensed, it is possible to downgrade to express edition
            # let user to decide which mode to use
            return $FALSE
        else
            # selected edition always override preset value of ADLICENSE 
            if [ "${EXPRESS}" = "Y" ]; then
                ADLICENSE="N"
            fi
        fi
    else
        ADLICENSE="Y"
    fi
    return $TRUE
} # determine_license()

###
warn_express()
{
    echo
    echo "The Express mode license allows you to install a total of 200 agents."
    echo "The Express mode license does not allow the use of licensed features for"
    echo "advanced authentication, access control, auditing, and centralized"
    echo "management.  This includes, but is not limited to features such as"
    echo "SmartCard authentication, DirectAuthorize, DirectAudit, Group Policy,"
    echo "Login User Filtering, and NSS overrides."
} # warn_express()

###
do_prompt_license ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_prompt_license: " >> ${LOG_FILE}

    if [ "${ADLICENSE}" = "N" ] || [ "${EXPRESS_QUESTION_DEFAULT}" = "X" ]; then
        QUESTION_DEFAULT="Y"
    else
        QUESTION_DEFAULT="N"
    fi
    warn_express | tee -a ${LOG_FILE}
    QUESTION="\nDo you want to install in Express mode? (Q|Y|N) [${QUESTION_DEFAULT}]: \c"
    do_ask_YorN ${QUESTION_DEFAULT}

    # The question is the opposite logic to the state of ADLICENSE.
    # If the user answers Y to Express authentication then ADLICENSE should be "N"
    if [ "${ANSWER}" = "Y" ]; then
        ADLICENSE="N"
    else
        ADLICENSE="Y"
    fi
    return $TRUE
} # do_prompt_license()

###
express_continue()
{
    if [ "${EXPRESS}" = "Y" ]; then
        if [ "${SILENT}" = "NO" ]; then
            warn_express | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue to install in Express mode? (C|Y|Q|N) [Y]:\c"; do_ask_YorN "Y" "C"
            if [ ${ANSWER} != "Y" ]; then do_quit; fi
        else
            warn_express >> ${LOG_FILE}
        fi
    fi
} # express_continue

### ask adcheck, adjoin, reboot ...
do_prompt_join ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_prompt_join: " >> ${LOG_FILE}
    echo ""
    # ADCHECK
    if [ -n "${ADCHECK_FNAME}" ]; then
        QUESTION="Do you want to run adcheck to verify your AD environment? (Q|Y|N) [Y]:\c"; do_ask_YorN; ADCHECK=${ANSWER}
        if [ "${ADCHECK}" = "Y" ]; then
            # DOMAIN
            QUESTION="\nPlease enter the Active Directory domain to check [${DOMAIN}]: \c"; do_ask
            if [ "${ANSWER}" != "" ]; then DOMAIN=${ANSWER}; fi
            while [ "${DOMAIN}" = "" -o "${DOMAIN}" = "company.com" ]
            do
                QUESTION="\nPlease enter the Active Directory domain to check [${DOMAIN}]: \c"; do_ask
                if [ "${ANSWER}" != "" ]; then DOMAIN=${ANSWER}; fi
            done
        else
            ADCHECK_RC=""
        fi
    fi

    # ADJOIN
    if [ "${ADJOINED}" = "Y" ]; then
        ANSWER="n"; ADJOIN=${ANSWER}
        # If the machine is joined and krb5.cache.type: KCM
        if [ `/usr/bin/adinfo -c | grep 'krb5.cache.type:' | grep KCM > /dev/null; echo $?` -eq 0 ]; then
            (
                echo
                echo "WARNING: KCM will be restarted during upgrade and the in-memory"
                echo "         Kerberos cache credentials will be lost."
                echo
            ) | tee -a ${LOG_FILE}
        fi
    elif [ -n "${ADJOIN_CMD_OPTIONS}" ]; then
        ANSWER="n"; ADJOIN=${ANSWER}
    else
        QUESTION="Join an Active Directory domain? (Q|Y|N) [Y]:\c"; do_ask_YorN; ADJOIN=${ANSWER}
    fi
    if [ "${ADJOIN}" = "Y" ]; then
        # DOMAIN
        QUESTION="    Enter the Active Directory domain to join [${DOMAIN}]: \c"; do_ask
        if [ "${ANSWER}" != "" ]; then DOMAIN=${ANSWER}; fi
        while [ "${DOMAIN}" = "" -o "${DOMAIN}" = "company.com" ]
        do
            QUESTION="    Enter the Active Directory domain to join [${DOMAIN}]: \c"; do_ask
            if [ "${ANSWER}" != "" ]; then DOMAIN=${ANSWER}; fi
        done
        # USERID
        QUESTION="    Enter the Active Directory authorized user [administrator]: \c"; do_ask
        if [ "${ANSWER}" != "" ]; then USERID=${ANSWER}; fi
        # PASSWD
        PASSWD=""
        while [ "${PASSWD}" = "" ]
        do
            echo $ECHO_FLAG "    Enter the password for the Active Directory user: \c"
            STTY_SAVE=`stty -g`
            stty -echo
            read PASSWD;
            stty ${STTY_SAVE}
            echo ""
            if [ "${PASSWD}" = "q" -o "${PASSWD}" = "Q" ]; then do_quit; fi
        done
        # COMPUTER
        QUESTION="    Enter the computer name [${COMPUTER}]: \c"; do_ask
        if [ "${ANSWER}" != "" ]; then COMPUTER=${ANSWER}; fi
        # CONTAINER
        QUESTION="    Enter the container DN [Computers]: \c"; do_ask
        if [ "${ANSWER}" != "" ]; then CONTAINER=${ANSWER}; fi
        if [ "${ADLICENSE}" != "N" ]; then
            # ZONE
            ZONE=""
            while [ "${ZONE}" = "" ]
            do
                QUESTION="    Enter the name of the zone: \c"; do_ask
                if [ "${ANSWER}" != "" ]; then ZONE=${ANSWER}; fi
            done
            # License type (server/workstation)
            QUESTION="    Join domain using workstation license type? (N for server license) (Q|Y|N) [N]: \c"; do_ask_YorN "N"
            if [ "${ANSWER}" = "Y" ]; then ADJ_LIC="workstation"; fi
        fi
        # SERVER
        QUESTION="    Enter the name of the domain controller [auto detect]: \c"; do_ask
        if [ "${ANSWER}" != "" ]; then SERVER=${ANSWER}; fi
    fi

    # CDA auditing
    check_auditing

    if [ "${DA_ENABLE}" != "enabled" ]; then
        if [ "${cda}" = "S=I+K" -o "${cda}" = "S=I+R" -o "${cda}" = "S+Y" ] || \
           [ "${cda}" = "S+I+K" -o "${cda}" = "S+I+U" -o "${cda}" = "I+K" ]; then
            if [ "${cda}" = "S=I+K" -o "${cda}" = "S+I+K" -o "${cda}" = "I+K" ]; then
                CDA_VER_AFTER=${CDA_CUR_VER} # "keep" so current CDA ver
            else
                CDA_VER_AFTER=${CDA_VER} # use new CDA ver
            fi
            if [ "`compare_ver ${CDA_VER_AFTER} 2.1.0; echo ${COMPARE}`" = "lt" ]; then
                # Only DA 2.0 (or older) requires to join domain
                if [ "${ADJOIN}" = "Y" -o "${ADJOINED}" = "Y" -o -n "${ADJOIN_CMD_OPTIONS}" ]; then
                    QUESTION="Enable auditing for all shells on this computer? (Q|Y|N) [Y]:\c"; do_ask_YorN; DA_ENABLE=${ANSWER}
                fi
            else
                QUESTION="Enable auditing on this computer (DirectAudit NSS mode)? (Q|Y|N) [Y]:\c"; do_ask_YorN; DA_ENABLE=${ANSWER}
            fi 
        fi 
    fi

    # REBOOT
    if [ "${ADJOIN}" = "Y" -o "${ADJOINED}" = "Y" -o -n "${ADJOIN_CMD_OPTIONS}" ]; then
        QUESTION="Reboot the computer after installation? (Q|Y|N) [Y]:\c"; do_ask_YorN; REBOOT=${ANSWER}
    fi
    return $TRUE
} # do_prompt_join()

### Verify input
do_verify () 
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_verify: " >> ${LOG_FILE}
    echo ""
    SUITE_NAME=${SUITE}
    [ "${EXPRESS}" = "Y" ] && SUITE_NAME=Express
    echo "You chose Centrify Suite ${SUITE_NAME} Edition and entered the following:"

    if [ "${INSTALL}" = "Y" ]; then
        echo "    Install CentrifyDC ${CDC_VER} package : ${INSTALL}"
    elif [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" -o "${SUPPORTED}" = "Y" ]; then
        if [ "`compare_ver ${CDC_VER} ${CUR_VER}; echo ${COMPARE}`" = "gt" ]; then
            echo "    (E)rase/(U)pdate to ${CDC_VER}/(K)eep CentrifyDC-${CUR_VER} package: ${INSTALL}"
        else
            echo "    (E)rase/(R)einstall ${CDC_VER}/(K)eep CentrifyDC-${CUR_VER} package: ${INSTALL}"
        fi
    else
        echo "    (E)rase/(K)eep CentrifyDC-${CUR_VER} package: ${INSTALL}"
    fi
    for ADD_ON_PKG6 in ${ADD_ON_LIST}; do
        # set full add-on package name and FIELD to find supported add-on version
        if [ "${ADD_ON_PKG6}" = "cda" ]; then
            ADD_ON_PKG_FULL="CentrifyDA"
            FIELD=2
            CUR_ADD_ON_VER=${CDA_CUR_VER}
        else
            ADD_ON_PKG_FULL="CentrifyDC-${ADD_ON_PKG6}"
            FIELD=3 # version field in the package file-name
            if [ "${ADD_ON_PKG6}" = "openssh" -o "${ADD_ON_PKG6}" = "samba" ]; then FIELD=4; fi
            # find currently installed add-on package version
            for ADD_ON_PKG10 in ${ADD_ON_INSTALLED}; do
                CUR_ADD_ON_VER=""
                ADD_ON_PKG10=`echo ${ADD_ON_PKG10} | sed "s/DC\./DC-/"`
                if [ `echo ${ADD_ON_PKG10} | cut -d '-' -f2` = "${ADD_ON_PKG6}" ]; then
                    CUR_ADD_ON_VER=`echo ${ADD_ON_PKG10} | cut -d '-' -f3`      # x.x.x
                    #CUR_ADD_ON_VER=`echo ${ADD_ON_PKG10} | cut -d '-' -f3-4`    # x.x.x-xxx
                    break
                fi
            done
        fi
        # find supported add-on version
        set_package_name ${ADD_ON_PKG6}
        ADD_ON_VER=`echo ${PKG_FILE} | cut -d '-' -f${FIELD}`
        # show answers
        VAR1=\$"${ADD_ON_PKG6}"
        VAR2=`eval "expr \"\${VAR1}\" "`
        if [ "${VAR2}" = "S+Y" -o "${VAR2}" = "S+N" ]; then
            ANSWER=`echo ${VAR2} | cut -c3-`
            echo "    Install ${ADD_ON_PKG_FULL} ${ADD_ON_VER} package: ${ANSWER}"
        elif [ "${VAR2}" = "S+I+U" -o "${VAR2}" = "S+I+E" -o "${VAR2}" = "S+I+K" ]; then
            ANSWER=`echo ${VAR2} | cut -c5-`
            echo "    (E)rase/(U)pdate to ${ADD_ON_VER}/(K)eep ${ADD_ON_PKG_FULL}-${CUR_ADD_ON_VER} package: ${ANSWER}"
        elif [ "${VAR2}" = "S=I+R" -o "${VAR2}" = "S=I+E" -o "${VAR2}" = "S=I+K" ]; then
            ANSWER=`echo ${VAR2} | cut -c5-`
            echo "    (E)rase/(R)einstall ${ADD_ON_VER}/(K)eep ${ADD_ON_PKG_FULL}-${CUR_ADD_ON_VER} package: ${ANSWER}"
        elif [ "${VAR2}" = "I+E" -o "${VAR2}" = "I+K" ]; then
            ANSWER=`echo ${VAR2} | cut -c3-`
            echo "    (E)rase/(K)eep ${ADD_ON_PKG_FULL}-${CUR_ADD_ON_VER} package: ${ANSWER}"
        fi
        set_package_name
    done

    if [ "${GLOBAL_ZONE_ONLY}" != "non_global" ]; then
        echo "    Install CentrifyDC in the global Solaris zone only : ${GLOBAL_ZONE_ONLY}"
    fi
    if [ "${EXPRESS_PL}" -eq $TRUE -a -z "${EXPRESS}" ]; then
	# Express mode is the inverse of ADLICENSE
	if [ "${ADLICENSE}" = "Y" ]; then
	    EXPRESS_MODE="N"
	else
	    EXPRESS_MODE="Y"
	fi
        echo "    Express mode                     : ${EXPRESS_MODE}"
    fi
    if [ -n "${ADCHECK_FNAME}" ]; then
        echo "    Run adcheck                      : ${ADCHECK}"
    fi
    if [ "${ADJOINED}" != "Y" -a -z "${ADJOIN_CMD_OPTIONS}" ]; then
        echo "    Join an Active Directory domain  : ${ADJOIN}"
    fi
    if [ "${ADJOIN}" = "Y" ]; then
        echo "    Active Directory domain to join  : ${DOMAIN}"
        echo "    Active Directory authorized user : ${USERID}"
        echo "    computer name                    : ${COMPUTER}"
        echo "    container DN                     : ${CONTAINER}"
        if [ "${ADLICENSE}" != "N" ]; then
            echo "    zone name                        : ${ZONE}"
            if [ "${ADJ_LIC}" = "" ]; then
                echo "    license type                     : server"
            else
                echo "    license type                     : ${ADJ_LIC}"
            fi
        fi
        if [ "${SERVER}" = "" ]; then
            echo "    domain controller name           : auto detect"
        else
            echo "    domain controller name           : ${SERVER}"
        fi
    elif [ -n "${ADJOIN_CMD_OPTIONS}" ]; then
        echo "    Join an Active Directory domain using the next options:"
        echo "    ${ADJOIN_CMD_OPTIONS}"
    fi
    if [ "${DA_ENABLE}" != "enabled" ]; then
        if [ "${cda}" = "S=I+K" -o "${cda}" = "S=I+R" -o "${cda}" = "S+Y" ] || \
           [ "${cda}" = "S+I+K" -o "${cda}" = "S+I+U" -o "${cda}" = "I+K" ]; then
            if [ "${cda}" = "S=I+K" -o "${cda}" = "S+I+K" -o "${cda}" = "I+K" ]; then
                CDA_VER_AFTER=${CDA_CUR_VER} # "keep" so current CDA ver
            else
                CDA_VER_AFTER=${CDA_VER} # use new CDA ver
            fi
            if [ "`compare_ver ${CDA_VER_AFTER} 2.1.0; echo ${COMPARE}`" = "lt" ]; then
                # Only DA 2.0 (or older) requires to join domain
                if [ "${ADJOIN}" = "Y" -o "${ADJOINED}" = "Y" -o -n "${ADJOIN_CMD_OPTIONS}" ]; then
                    echo "    Enable auditing                  : ${DA_ENABLE}"
                fi
            else
                echo "    Enable auditing                  : ${DA_ENABLE}"
            fi
        fi
    fi

    if [ "${ADJOIN}" = "Y" -o "${ADJOINED}" = "Y" -o -n "${ADJOIN_CMD_OPTIONS}" ]; then
        echo "    Reboot computer                  : ${REBOOT}"
    fi 
    echo ""
    echo ""
    echo "If this information is correct and you want to proceed, type \"Y\"."
    echo "To change any information, type \"N\" and enter new information."
    QUESTION="Do you want to continue (Y) or re-enter information? (Q|Y|N) [Y]:\c"; do_ask_YorN; CONTINUE=${ANSWER}
    if [ "${ANSWER}" != "Y" ]; then
        # reset to the default
        echo ""
        ADCHECK=""; ADJOIN=""; ADJ_LIC=""; ADJ_FORCE=""; ADJ_TRUST=""; DOMAIN=""; USERID="administrator"; PASSWD=""; CONTAINER="Computers"
        SERVER=""; ZONE=""; COMPUTER=`hostname`; REBOOT=""
        INPUT=""; INSTALL=""; SUITE="Custom"; EXPRESS=""; ADLICENSE="Y"
        if [ "${DA_ENABLE}" != "enabled" ]; then DA_ENABLE=""; fi
        PKG_FILE_LIST=""; PKG_I_LIST=""; PKG_E_LIST=""
        set_package_name
        for ADD_ON_PKG6 in ${ADD_ON_LIST}; do
            VAR1=\$"${ADD_ON_PKG6}"
            VAR2=`eval "expr \"\${VAR1}\" "`
            if [ "${VAR2}" = "S+Y" -o "${VAR2}" = "S+N" -o "${VAR2}" = "I+E" -o "${VAR2}" = "I+K" ]; then
                VAR3=`echo ${VAR2} | cut -c1`
                eval ${ADD_ON_PKG6}=${VAR3}
            elif [ "${VAR2}" = "S+I+U" -o "${VAR2}" = "S+I+E" -o "${VAR2}" = "S+I+K" ] || \
                 [ "${VAR2}" = "S=I+R" -o "${VAR2}" = "S=I+E" -o "${VAR2}" = "S=I+K" ]; then
                VAR3=`echo ${VAR2} | cut -c1-3`
                eval ${ADD_ON_PKG6}=${VAR3}
            fi
        done
    fi
    return $TRUE
} # do_verify()

do_silent_prompt ()
{
    ### configure silent mode for the agent
    INSTALL=`echo ${INSTALL} | tr abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ`
    if [ "${INSTALL}" = "N" -a "${INSTALLED}" = "N" ]; then
        echo "Silent mode: INSTALLED=${INSTALLED} and INSTALL=${INSTALL}" 
        do_quit
    fi
    if [ "${INSTALL}" = "E" -a "${INSTALLED}" = "Y" ]; then
        if [ "${ADD_ON_INSTALLED}" != "" ]; then
            echo $ECHO_FLAG "\nWARNING:" | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "The following Centrify DirectControl add-on package(s) depend on CentrifyDC" | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "core package and should be also removed:" | tee -a ${LOG_FILE}
            for ADD_ON_PKG in ${ADD_ON_INSTALLED}; do
                echo $ECHO_FLAG ${ADD_ON_PKG} | tee -a ${LOG_FILE}
            done
            echo $ECHO_FLAG "To uninstall all Centrify DirectControl packages set UNINSTALL=Y in" | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "${CFG_FNAME} or use -e option." | tee -a ${LOG_FILE}
            do_quit
        fi
    fi
    if [ "${INSTALL}" = "Y" -a "${INSTALLED}" = "Y" ]; then INSTALL="N"; fi # only fresh install, no upgrade
    if [ "${INSTALL}" = "U" -a "${INSTALLED}" = "Y" ] && [ "`compare_ver ${CDC_VER} ${CUR_VER}; echo ${COMPARE}`" != "gt" ]; then INSTALL="N"; fi # update only, no reinstall
    if [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ] && [ "${INSTALLED}" = "N" ]; then INSTALL="Y"; fi # not installed yet so just install (skip upgrade steps)
    if [ "${INSTALL}" = "Y" -o "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then
        # bail on mac if asked to install/upgrade 3.x or earlier
        min_version_required || { echo ; echo "This version of ${THIS_PRG_NAME} cannot be used with CentrifyDC $CDC_VER"; do_error; }

        PKG_FILE_LIST=${PKG_DIR}${PKG_FILE}
        PKG_I_LIST="CentrifyDC"
        if [ "${TARGET_OS}" = "aix" ]; then PKG_I_LIST="CentrifyDC.core"; fi
    fi
    if [ "${INSTALL}" = "R" ]; then
        if [ "${TARGET_OS}" = "aix" ]; then
            FORCE_OPTION="-F" # Force reinstall
        elif [ "${TARGET_OS}" = "hpux" ]; then
            FORCE_OPTION="-x reinstall=true" # Force reinstall
        fi
    fi
    ### configure silent mode for add-on packages
    for ADD_ON_PKG8 in ${ADD_ON_LIST}; do
        if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG8}" = "cda" ]; then
            ADD_ON_PKG_FULL="CentrifyDA.core"
        elif [ "${ADD_ON_PKG8}" = "cda" ]; then
            ADD_ON_PKG_FULL="CentrifyDA"
        else
            ADD_ON_PKG_FULL="CentrifyDC${SEP}${ADD_ON_PKG8}"
        fi
        VAR1=\$"${ADD_ON_PKG8}"
        VAR2=`eval "expr \"\${VAR1}\" "`
        if [ "${ADD_ON_PKG8}" = "cda" ]; then
            VAR3=\$"CentrifyDA"
        else
            VAR3=\$"CentrifyDC_${ADD_ON_PKG8}"
        fi
        VAR4=`eval "expr \"\${VAR3}\" " | tr abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ`
        debug_echo "${VAR1} ${VAR2} ${VAR3} ${VAR4}"
        if [ "${VAR2}" = "S" ]; then
            # Install? No?
            if [ "${VAR4}" = "Y" -o "${VAR4}" = "U" ]; then
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+Y
                set_package_name ${ADD_ON_PKG8}
                PKG_FILE_LIST="${PKG_FILE_LIST} ${PKG_DIR}${PKG_FILE}"
                PKG_I_LIST="${PKG_I_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+N
            fi
        elif [ "${VAR2}" = "S+I" ]; then
            # Erase? Upgrade? Keep?
            if [ "${VAR4}" = "U" ]; then
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+U
                set_package_name ${ADD_ON_PKG8}
                PKG_FILE_LIST="${PKG_FILE_LIST} ${PKG_DIR}${PKG_FILE}"
                PKG_I_LIST="${PKG_I_LIST} ${ADD_ON_PKG_FULL}"
            elif [ "${VAR4}" = "E" ]; then
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+E
                if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "openssh" -a "${OPENSSH_OLD}" = "Y" ]; then
                    ADD_ON_PKG_FULL="CentrifyDC-openssh.base"
                fi
                PKG_E_LIST="${PKG_E_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+K
            fi
        elif [ "${VAR2}" = "S=I" ]; then
            # Erase? Reinstall? Keep?
            if [ "${VAR4}" = "U" ]; then # update only, no reinstall
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+K
            elif [ "${VAR4}" = "R" ]; then
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+R
                set_package_name ${ADD_ON_PKG8}
                PKG_FILE_LIST="${PKG_FILE_LIST} ${PKG_DIR}${PKG_FILE}"
                PKG_I_LIST="${PKG_I_LIST} ${ADD_ON_PKG_FULL}"
                if [ "${TARGET_OS}" = "aix" ]; then
                    FORCE_OPTION="-F" # Force reinstall
                elif [ "${TARGET_OS}" = "hpux" ]; then
                    FORCE_OPTION="-x reinstall=true" # Force reinstall
                fi
            elif [ "${VAR4}" = "E" ]; then
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+E
                if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "openssh" -a "${OPENSSH_OLD}" = "Y" ]; then
                    ADD_ON_PKG_FULL="CentrifyDC-openssh.base"
                fi
                PKG_E_LIST="${PKG_E_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+K
            fi
        elif [ "${VAR2}" = "I" ]; then
            # Erase? Keep?
            if [ "${VAR4}" = "E" ]; then
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+E
                if [ "${TARGET_OS}" = "aix" -a "${ADD_ON_PKG5}" = "openssh" -a "${OPENSSH_OLD}" = "Y" ]; then
                    ADD_ON_PKG_FULL="CentrifyDC-openssh.base"
                fi
                PKG_E_LIST="${PKG_E_LIST} ${ADD_ON_PKG_FULL}"
            else
                eval ${ADD_ON_PKG8}=\$$ADD_ON_PKG8+K
            fi
        fi
        set_package_name
    done
    debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
    debug_echo "PKG_I_LIST=${PKG_I_LIST}"
    debug_echo "PKG_E_LIST=${PKG_E_LIST}"
    debug_echo INSTALL=${INSTALL}
    return $TRUE
} # do_silent_prompt

create_admin () 
{
    create_verify_dir "${VAR_TMP}"
    echo mail= > ${ADMIN_FILE}
    echo instance=overwrite >> ${ADMIN_FILE}
    echo partial=nocheck >> ${ADMIN_FILE}
    echo runlevel=nocheck >> ${ADMIN_FILE}
    echo idepend=${ADMIN_IDEPEND} >> ${ADMIN_FILE}
    echo rdepend=${ADMIN_RDEPEND} >> ${ADMIN_FILE}
    echo space=quit >> ${ADMIN_FILE}
    echo setuid=nocheck >> ${ADMIN_FILE}
    echo conflict=${ADMIN_CONFLICT} >> ${ADMIN_FILE}
    echo action=nocheck >> ${ADMIN_FILE}
    echo basedir=default >> ${ADMIN_FILE}
}

### Pre-install steps
do_preinstall () 
{
    if [ "$1" = "" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preinstall: " >> ${LOG_FILE}

        if [ "${TARGET_OS}" = "darwin" ]; then
            debug_echo "will use pkg for installation, skipping..."
            return ${TRUE}
        else
            echo skipping ... >> ${LOG_FILE}
        fi

    elif [ "$1" = "openssh" -a "${TARGET_OS}" = "linux" ] &&
         [ "`compare_ver ${CDC_VER} 4.4; echo ${COMPARE}`" = "lt" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preinstall: $1: " >> ${LOG_FILE}
        if [ -f /etc/pam.d/sshd ]; then
            echo "INFO: found non-centrify /etc/pam.d/sshd, renaming to /etc/pam.d/sshd.pre_cdc" >> ${LOG_FILE}
            mv /etc/pam.d/sshd /etc/pam.d/sshd.pre_cdc
            if [ "${PKG_OS_REV}" = "deb6" ]; then
                LINUX_OPTION="${LINUX_OPTION} --force-overwrite"
            else
                LINUX_OPTION="${LINUX_OPTION} --replacefiles"
            fi

        fi
    else ### add-on
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preinstall: $1: skipping ..." >> ${LOG_FILE}
    fi
    return ${TRUE}
} # do_preinstall()

### Post-install steps
do_postinstall () 
{
    if [ "$1" = "" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postinstall: " >> ${LOG_FILE}

        if [ "${TARGET_OS}" = "darwin" ]; then
            debug_echo "will use pkg for installation, skipping..."
            return ${TRUE}

        elif [ "${TARGET_OS}" = "solaris" ]; then
            # clean up temp files
            rm -f /lib/*centrify*.BK
            rm -f /usr/lib/*centrify*.BK
            rm -f /usr/lib/security/*centrify*.BK

        elif [ "${TARGET_OS}" = "aix" ] && [ `uname -v` -ge 6 ]; then
            fix_wpar
        fi
        is_perl_installed       || { disable_GP; }
    else ### add-on
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postinstall: $1: skipping ..." >> ${LOG_FILE}
    fi
    return ${TRUE}
} # do_postinstall()
            

save_admin_settings ()
{
    ADMIN_SAVE_IDEPEND=$ADMIN_IDEPEND
    ADMIN_SAVE_RDEPEND=$ADMIN_RDEPEND
    ADMIN_SAVE_CONFLICT=$ADMIN_CONFLICT
}

restore_admin_settings ()
{
    ADMIN_IDEPEND=$ADMIN_SAVE_IDEPEND
    ADMIN_RDEPEND=$ADMIN_SAVE_RDEPEND
    ADMIN_CONFLICT=$ADMIN_SAVE_CONFLICT
}

### Force install Solaris package for fix_install_solaris()
force_install_pkg ()
{
    rm -rf ${VAR_TMP}/*

    PKG_I2_LIST="`echo \"${PKG_I3_LIST} \" ${PKG_I2_LIST} | sed \"s/ $1 //\" `"
    if echo " $PKG_I3_LIST " | grep " $1 " > /dev/null 2>&1; then
        PKG_I3_LIST="`echo \"${PKG_I3_LIST} \" | sed \"s/ $1 //\" `"
        PKG_I_LIST=$1
        set_package_name `echo ${PKG_I_LIST} | sed s/CentrifyDC// | sed s/-// | sed 's/\.//' | sed s/core//`
        do_install ${PKG_I_LIST}
        RC_INSTALL=$?
    else
        RC_INSTALL=0
    fi
    restore_admin_settings
    return $RC_INSTALL
}

### check whether $1 covers all elements of $2 that seperated by ','
left_cover_right ()
{
    relements="`echo $2 | tr ',' ' '`"
    
    for relement in $relements; do
        if echo "$1" | grep -v "${relement}," > /dev/null 2>&1; then
            return $FALSE
        fi
    done
    return $TRUE
}

### Fix installation problem in Solaris
fix_install_solaris ()
{
    # Remove package from the list if it was installed successfully
    PKG_I3_LIST=""
    echo "Checking installation results ..."  | tee -a ${LOG_FILE}
    for i in ${PKG_I_LIST}; do
        PKG_I_RESULT="`get_pkgadd_result $i`"
        echo "  $i: $PKG_I_RESULT" >> ${LOG_FILE}
        eval "`echo ${i} | sed -e 's/-/_/' -e 's/\./_/'`_PKG_I_RESULT=$PKG_I_RESULT" # record get_pkgadd_result
        if [ "$PKG_I_RESULT" != "successful" ]; then
            PKG_I3_LIST="${PKG_I3_LIST} $i"
        fi
    done

    ### CentrifyDC
    IGNORE_I_ERROR="conflict,inc=CentrifyDC-nis,inc=CentrifyDC-ldapproxy," # Warnings and errors which can be ignored
    # if CentrifyDC installation is failed and
    # all warnings in $CentrifyDC_PKG_I_RESULT can be ignored
    if echo " $PKG_I3_LIST " | grep " CentrifyDC " > /dev/null 2>&1 && \
                left_cover_right "$IGNORE_I_ERROR" "$CentrifyDC_PKG_I_RESULT"; then
        if echo "$CentrifyDC_PKG_I_RESULT" | grep "conflict,"; then
            echo "INFO: Conflicts detected while installing CentrfiyDC package." | tee -a ${LOG_FILE}
            echo "Installing core package without conflict checking to fix conflicts ..." | tee -a ${LOG_FILE}

            save_admin_settings; ADMIN_CONFLICT=nocheck
            force_install_pkg "CentrifyDC" || return
            
        elif echo " $PKG_I_LIST " | grep " CentrifyDC-nis " > /dev/null 2>&1 && \
                echo "$CentrifyDC_PKG_I_RESULT" | grep "inc=CentrifyDC-nis," > /dev/null 2>&1; then
            echo "INFO: Incompatible CentrifyDC-nis detected when installing CentrifyDC." | tee -a ${LOG_FILE}
            echo "INFO: It is known issue when upgrading CentrifyDC and CentrifyDC-nis" | tee -a ${LOG_FILE}
            echo "Installing CentrifyDC package without dependency checking ..." | tee -a ${LOG_FILE}

            save_admin_settings; ADMIN_IDEPEND=nocheck
            force_install_pkg "CentrifyDC" || return

        elif echo " $PKG_I_LIST " | grep " CentrifyDC-ldapproxy " > /dev/null 2>&1 && \
                echo "$CentrifyDC_PKG_I_RESULT" | grep "inc=CentrifyDC-ldapproxy," > /dev/null 2>&1; then
            echo "INFO: Incompatible CentrifyDC-ldapproxy detected when installing CentrifyDC." | tee -a ${LOG_FILE}
            echo "INFO: It is known issue when upgrading CentrifyDC and CentrifyDC-ldapproxy" | tee -a ${LOG_FILE}
            echo "Installing CentrifyDC package without dependency checking ..." | tee -a ${LOG_FILE}

            save_admin_settings; ADMIN_IDEPEND=nocheck
            force_install_pkg "CentrifyDC" || return
        fi
    fi

    ### CentrifyDA (resolve file conflict caused by DA bug in Suite 2013 beta release)
    if [ -f /lib/nss_centrifyda.so.1 -o -f /lib/64/nss_centrifyda.so.1 ] && \
           /usr/sbin/pkgchk -l -p /lib/nss_centrifyda.so.1 2> /dev/null | grep CentrifyDC > /dev/null; then
        IGNORE_I_ERROR="conflict," # Warnings and errors which can be ignored
        # if CentrifyDA installation is failed and
        # all warnings in $CentrifyDC_PKG_I_RESULT can be ignored
        if echo " $PKG_I3_LIST " | grep " CentrifyDA " > /dev/null 2>&1 && \
                    left_cover_right "$IGNORE_I_ERROR" "$CentrifyDA_PKG_I_RESULT"; then
            if echo "$CentrifyDA_PKG_I_RESULT" | grep "conflict,"; then
                echo "INFO: Conflicts detected while installing CentrfiyDA package." | tee -a ${LOG_FILE}
                echo "Installing CentrfiyDA package without conflict checking to fix conflicts ..." | tee -a ${LOG_FILE}

                save_admin_settings; ADMIN_CONFLICT=nocheck
                force_install_pkg "CentrifyDA" || return
            fi
        fi
    fi
} # fix_install_solaris()

### Install Centrify DirectControl suite
do_install_main ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_install_main: " >> ${LOG_FILE}

    rm -rf ${VAR_TMP}
    create_verify_dir "${VAR_TMP}"
    
    if  [ "${TARGET_OS}" = "solaris" -o "${TARGET_OS}" = "aix" -o "${TARGET_OS}" = "hpux" ]; then
        if [ "`echo ${PKG_I_LIST} | wc -w | sed 's/^[ ^t]*//'`" = "1" ]; then
            # install single package
            set_package_name `echo ${PKG_I_LIST} | sed s/CentrifyDC// | sed s/-// | sed 's/\.//' | sed s/core//`
            do_install ${PKG_I_LIST}
            RC_INSTALL=$?
            if [ "$RC_INSTALL" != "0" ]; then
                if [ "${TARGET_OS}" = "solaris" -a "$RC" = "4" ]; then
                    # Administration error
                    fix_install_solaris
                fi
                if [ "$RC_INSTALL" != "0" ]; then print_df; return ${FALSE}; fi
            fi
        else
            # multi-package install
            PKG_I2_LIST=""
            for ADD_ON_PKG7 in ${PKG_I_LIST}; do
                set_package_name `echo ${ADD_ON_PKG7} | sed s/CentrifyDC// | sed s/-// | sed 's/\.//' | sed s/core//`
                do_install ${ADD_ON_PKG7} spool
                if [ "$?" != "0" ]; then print_df; return ${FALSE}; fi
            done
            do_install all
            RC_INSTALL=$?
            if [ "$RC_INSTALL" != "0" ]; then
                if [ "${TARGET_OS}" = "solaris" -a "$RC" = "4" ]; then
                    # Administration error
                    fix_install_solaris
                fi
                if [ "$RC_INSTALL" != "0" ]; then print_df; return ${FALSE}; fi
            fi
            # second round to avoid dependency conflicts in Sol10 zones
            if [ "${PKG_I2_LIST}" != "" ]; then
                PKG_I_LIST=${PKG_I2_LIST}
                PKG_I2_LIST=""
                rm -rf ${VAR_TMP}/*
                for ADD_ON_PKG7 in ${PKG_I_LIST}; do
                    set_package_name `echo ${ADD_ON_PKG7} | sed s/CentrifyDC// | sed s/-// | sed 's/\.//' | sed s/core//`
                    do_install ${ADD_ON_PKG7} spool
                    if [ "$?" != "0" ]; then print_df; return ${FALSE}; fi
                done
                do_install all
                RC_INSTALL=$?
                if [ "$RC_INSTALL" != "0" ]; then
                    if [ "${TARGET_OS}" = "solaris" -a "$RC" = "4" ]; then
                        # Administration error
                        fix_install_solaris
                    fi
                    if [ "$RC_INSTALL" != "0" ] || [ "${PKG_I2_LIST}" != "" ]; then print_df; return ${FALSE}; fi
                fi
            fi
        fi
    else
        # install on LINUX, IRIX and Mac OS using PKG_FILE_LIST
        do_install
        if [ "$?" != "0" ]; then print_df; return ${FALSE}; fi
    fi
    rm -rf ${VAR_TMP}
    return ${TRUE}
} # do_install_main()

### pkgadd wrapper that will save the output from pkgadd
do_pkgadd ()
{
    /usr/sbin/pkgadd "$@" > ${PKGADD_LOG} 2>&1
    RC=$?
    cat ${PKGADD_LOG} >> ${LOG_FILE}
    return ${RC}
}

### check whether swcopy/swinstall has exrequisite conflicts
### use swcopy/swinstall output file as first argument
check_sw_exrequisite ()
{
    if grep 'fileset(s) have been excluded due to exrequisite' "$1" > /dev/null; then
        return ${TRUE}
    fi
    return ${FALSE}
}

### swcopy that checks the warnings caused by exrequisites conflicts
### and return 2 if exrequisites conflicts found
### info: swcopy may not return error exit code when exrequisites conflicts
do_swcopy ()
{
    /usr/sbin/swcopy $@ > ${SWCOPY_LOG} 2> ${SWCOPY_LOG}
    RC=$?
    cat ${SWCOPY_LOG} >> ${LOG_FILE}
    if [ "${RC}" = "0" ] && \
        check_sw_exrequisite ${SWCOPY_LOG}; then
            return 2
    fi
    return ${RC}
}

### swinstall that checks the warnings caused by exrequisites conflicts
### and return 2 if exrequisites conflicts
### info: swinstall may not return error exit code when exrequisites conflicts
do_swinstall ()
{
    /usr/sbin/swinstall $@ > ${SWINSTALL_LOG} 2> ${SWINSTALL_LOG}
    RC=$?
    cat ${SWINSTALL_LOG} >> ${LOG_FILE}
    if [ "${RC}" = "0" ] && \
        check_sw_exrequisite ${SWINSTALL_LOG}; then
            return 2
    fi
    return ${RC}
}

### Check package installation result in the pkgadd log file
### get_pkgadd_result [package]
get_pkgadd_result ()
{
    if [ -f "${PKGADD_LOG}" ]; then
        # Read the block of log for this package only
        # Note that the tail -r option is supported by
        # /usr/bin/tail or /usr/xpg4/bin/tail only.
        /usr/bin/tail -r "${PKGADD_LOG}" | awk "
BEGIN {
    started=0; current_status=\"\"; result=\"notfound\"
}
{
    if (started == 0) {
        if (\$0 ~ /Installation of <$1> was/ || \
            \"$1\" == \"\" && \$0 ~ /Installation of </) {
            started=1
            result=\"\"
            if (\$0 ~ /successful/) { result=\"successful\"; exit }
        }
        else if (\$0 !~ /Dependency checking issues for package/) {
            # sample matching line 1:
            # The package <CentrifyDC> is a prerequisite package and should be
            # installed for package <CentrifyDC-ldapproxy> on zone <myzone>.
            # sample matching line 2:
            # pkgadd: ERROR: unknown preinstallation dependency check line <incompat=CentrifyDC-nis> for package <CentrifyDC> zone <myzone>: ignored
            if (\$0 ~ /for package <$1>.* zone/ || \
                \"$1\" == \"\" && \
                \$0 ~ /for package </) { # shown when checking zones
                started=1
                result=\"\"
            }
        }
    }
    else if (started == 1) {
        if (\$0 ~ /^## Verifying /) { exit }
        # exit if switch to the message of another package
        if (\$0 ~ /Installation of </) { exit }
        if (\$0 ~ /for package <.*>.* zone/ && \$0 !~ /for package <$1>.* zone/) { exit }
    }

    if (started == 1) {
        if (\$0 ~ /files are already installed/) { current_status=\"conflict\"; result=result \"conflict,\" }
        if (\$0 ~ /which is incompatible with/ || \$0 ~ /unknown preinstallation dependency check line/) { current_status=\"inc\"; result=result \"inc\" }
        if (\$0 ~ /prerequisite package/) { current_status=\"prer\"; result=result \"prer\" }
        if ((current_status == \"inc\" || current_status == \"prer\" || current_status == \"inc-zone\") && \$0 ~ /<.*>/) {
            x=index(\$0,\"<\")
            y=index(\$0,\">\")
            info=\"\"
            if (x > 0 && y > 0) { info=substr(\$0,x+1,y-x-1) }
            # the format inside <> may be <incompat=CentrifyDC>
            x=index(info,\"=\")
            if (x > 0) { info=substr(info,x+1) }
            if (info != \"\") { result=result \"=\" info \",\" }
            current_status=\"\"
        }
    }
}
END {
    if (result == \"\") {
        print \"unknown\"
    } else {
        print result
    }
}
"
    else
        echo "nolog"
    fi
}

attach_dmg()
{
    local DMG_PATH=$1
    local MOUNT_PATH=$2

    echo "Mounting $DMG_PATH to $MOUNT_PATH"
    hdiutil attach -quiet $DMG_PATH -readonly -noautoopen -mountpoint $MOUNT_PATH

    return $?
}

detach_dmg()
{
    local MOUNT_PATH=$1
    local COUNTER=0
    local RV=0
    local MAX_RETRIES=5

    # try up to $MAX_RETRIES times
    while [ $COUNTER -lt $MAX_RETRIES ]; do
	echo "Unmounting $MOUNT_PATH"
	hdiutil detach -quiet "$MOUNT_PATH"

	RV=$?

	[ $RV -eq 0 ] && break

	let COUNTER=COUNTER+1

        # Wait a bit
	sleep 3
    done
     
    return $RV
}

### Install Centrify DirectControl package(s)
do_install () 
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_install: " >> ${LOG_FILE}
    FLAG=""
    case "${TARGET_OS}" in
    linux)
        echo List of ${CDC_VER} packages to be installed: >> ${LOG_FILE}
        for i in ${PKG_I_LIST}; do
            echo "    ${i}" >> ${LOG_FILE}
        done
        if [ "${PKG_OS_REV}" = "deb6" ]; then
            CMD="dpkg -i"
            if [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then
                FLAG="--force-confnew --force-confmiss"
            else
                # Do not force using default configurations if --force-xxx option is given
                echo "$LINUX_OPTION" | grep '\-\-force\-' > /dev/null 2>&1 || FLAG="--force-confdef"
            fi
        else
            CMD="rpm -Uv"
            FLAG="--replacepkgs"
        fi
        
        ${CMD} ${FLAG} ${LINUX_OPTION} ${PKG_FILE_LIST} 2>> ${LOG_FILE}; RC=$?
        ;;
    solaris)
        if [ "$1" != "all" ]; then
            echo "Unzipping/unpackaging ${PKG_DIR}${PKG_FILE} to ${VAR}/centrify/install-tmp* ..." | tee -a ${LOG_FILE}
            case "${PKG_FILE}" in
            *".tgz")
                gunzip -c ${PKG_DIR}${PKG_FILE} | ( cd ${VAR_TMP} && tar -xf - )
                ;;
            *".gz")
                gunzip -c ${PKG_DIR}${PKG_FILE} > ${VAR_TMP}/${1}
                ;;
            *)
                echo ${ECHO_FLAG} "WARNING: Unexpected package file extension: ${PKG_FILE}" >> ${LOG_FILE}
                ;;
            esac
            if [ "$?" != "0" ]; then return ${FALSE}; fi
        fi
        if [ "$2" = "spool" ]; then
            # spool single package
            echo Spooling ${1} ... | tee -a ${LOG_FILE}
            mkdir -p ${VAR_TMP}/tmp
            mv ${VAR_TMP}/${1} ${VAR_TMP}/tmp
            do_pkgadd -s ${VAR_TMP} -d ${VAR_TMP}/tmp/${1} ${1} >> ${LOG_FILE} 2>> ${LOG_FILE}
            RC=$?
            rm -rf ${VAR_TMP}/tmp
        elif [ "$2" = "" -a "$1" != "" -a "$1" != "all" ]; then
            # install single package
            echo Installing ${1} ... | tee -a ${LOG_FILE}
            create_admin
            if [ "${GLOBAL_ZONE_ONLY}" = "Y" ]; then FLAG="-G"; fi
            do_pkgadd ${FLAG} -a ${ADMIN_FILE} -n -d ${VAR_TMP}/${1} ${1} 2>> ${LOG_FILE}
            RC=$?
            sleep 5
        elif [ "$1" = "all" ]; then
            # install all from spool dir
            echo Installing all from spool dir ... | tee -a ${LOG_FILE}
            create_admin
            if [ "${GLOBAL_ZONE_ONLY}" = "Y" ]; then FLAG="-G"; fi
            if [ "${INSTALL}" = "Y" -o "${INSTALL}" = "U" ]; then
                # CentrifyDC is prerequisite for Add-on packages.
                # The add-on packages may have dependency failures
                # therefore we install/upgrade CentrifyDC first.
                RC=0
                PKG_TEMP_LIST=`echo "${PKG_I_LIST} " | sed 's/CentrifyDC //'`
                if [ "$PKG_TEMP_LIST" != "${PKG_I_LIST} " ]; then
                    do_pkgadd ${FLAG} -a ${ADMIN_FILE} -n -d ${VAR_TMP} CentrifyDC 2>> ${LOG_FILE}
                    RC=$?
                fi
                if [ $RC -eq 0 ]; then
                    if [ -n "`echo $PKG_TEMP_LIST`" ]; then # if PKG_TEMP_LIST still has characters
                        do_pkgadd ${FLAG} -a ${ADMIN_FILE} -n -d ${VAR_TMP} ${PKG_TEMP_LIST} 2>> ${LOG_FILE}
                        RC=$?
                    fi
                fi
            else
                do_pkgadd ${FLAG} -a ${ADMIN_FILE} -n -d ${VAR_TMP} ${PKG_I_LIST} 2>> ${LOG_FILE}
                RC=$?
            fi
            sleep 5
        fi
        ;;
    hpux)
        if [ "$1" != "all" ]; then
            if [ "${samba}" = "S+I+U" -o "${samba}" = "S=I+R" ] && \
               [ "`echo ${PKG_FILE} |grep centrifydc-samba-3.5.11 > /dev/null; echo $?`" = "0" ] && \
               [ "${X_OPTION_LIST}" = "" -o "`echo ${X_OPTION_LIST} |grep allow_downdate > /dev/null; echo $?`" != "0" ]; then
                X_OPTION_LIST="${X_OPTION_LIST}-x allow_downdate=true"
            fi
            echo "Unzipping ${PKG_DIR}${PKG_FILE} to ${VAR}/centrify/install-tmp* ..." | tee -a ${LOG_FILE}
            PKG_DEPOT="`echo ${PKG_FILE} | sed 's/\.gz//'`"
            cp ${PKG_DIR}${PKG_FILE} ${VAR_TMP}
            if [ "$?" != "0" ]; then return ${FALSE}; fi
            ( cd ${VAR_TMP} && gunzip ${PKG_FILE} )
            if [ "$?" != "0" ]; then return ${FALSE}; fi
        fi
        if [ "$2" = "spool" ]; then
            # spool single package
            echo Spooling ${1} ... | tee -a  ${LOG_FILE}
            # If CentrifyDC is not going to be reinstalled or upgraded,
            # enforce_dependencies must be set to false. As swcopy or
            # swinstall will check the dependency packages in the spool dir.
            if [ "${INSTALL}" = "K" ] || \
                [ "${INSTALL}" = "N" -a "${INSTALLED}" = "Y" ] ; then 
                SWCOPY_X_OPTION="-x enforce_dependencies=false"
            else
                SWCOPY_X_OPTION=""
            fi
            do_swcopy -s ${VAR_TMP}/${PKG_DEPOT} ${SWCOPY_X_OPTION} ${1}
            RC=$?
        elif [ "$2" = "" -a "$1" != "" -a "$1" != "all" ]; then
            # install single package
            echo Installing ${1} ... | tee -a ${LOG_FILE}
            do_swinstall -s ${VAR_TMP}/${PKG_DEPOT} ${X_OPTION_LIST} ${FORCE_OPTION} ${1}
            RC=$?
        elif [ "$1" = "all" ]; then
            # install all from spool dir
            echo Installing all from spool dir ... | tee -a ${LOG_FILE}
            do_swinstall ${X_OPTION_LIST} ${FORCE_OPTION} ${PKG_I_LIST}
            RC=$?
            rm -r /var/spool/sw/*
        fi
        ;;
    aix)
        if [ "$1" != "all" ]; then
            echo "Unzipping ${PKG_DIR}${PKG_FILE} to ${VAR}/centrify/install-tmp* ..." | tee -a ${LOG_FILE}
            if [ -f ${VAR_TMP}/.toc ]; then rm -f ${VAR_TMP}/.toc; fi
            cp ${PKG_DIR}${PKG_FILE} ${VAR_TMP}
            if [ "$?" != "0" ]; then return ${FALSE}; fi
            ( cd ${VAR_TMP} && gunzip ${PKG_FILE} )
            if [ "$?" != "0" ]; then return ${FALSE}; fi
        fi
        if [ "${OS_REV}" != "aix4.3" ]; then FLAG="Y"; fi
        if [ "$2" = "spool" ]; then
            # spool single package
            echo no spooling on AIX ... >> ${LOG_FILE}
            RC=0
        elif [ "$2" = "" -a "$1" != "" -a "$1" != "all" ]; then
            # install single package
            if [ "${1}" = "CentrifyDA.core" ]; then
                echo Installing ${1} ${ADD_ON_VER} ... | tee -a ${LOG_FILE}
            else
                echo Installing ${1} ${CDC_VER} ... | tee -a ${LOG_FILE}
            fi
            installp ${FORCE_OPTION} -a${FLAG} -d ${VAR_TMP} $1                >> ${LOG_FILE} 2>> ${LOG_FILE}
            RC=$?
            if [ "${RC}" != "0" ]; then
                echo "Please review log file for any ERRORS" 
            fi
        elif [ "$1" = "all" ]; then
            # install all from spool dir
            echo Installing all from spool dir ... | tee -a ${LOG_FILE}
            installp ${FORCE_OPTION} -a${FLAG} -d ${VAR_TMP} all               >> ${LOG_FILE} 2>> ${LOG_FILE}
            RC=$?
            if [ "${RC}" != "0" ]; then
                echo "Please review log file for any ERRORS"
            fi
        fi
        ;;
    darwin)
        echo $ECHO_FLAG "\nUnzipping packages to ${VAR}/centrify/install-tmp* ..." | tee -a ${LOG_FILE}
        cp ${PKG_FILE_LIST} ${VAR_TMP}
        if [ "$?" != "0" ]; then rm -rf ${VAR_TMP}; return ${FALSE}; fi

        CDC_DMG_PATH=${VAR_TMP}/CentrifyDC-*${CDC_VER}-mac${PKG_OS_REV}*.dmg
        debug_echo "Checking DMG exists..."
        if [ ! -f $CDC_DMG_PATH ]; then rm -rf ${VAR_TMP}; return ${FALSE}; fi

        debug_echo "Making temp mount directory..."
        TEMP_MOUNT_PATH=`mktemp -d "${VAR_TMP}/dmg.mount.XXXXXX"`
        if [ "$?" != "0" ]; then rm -rf ${VAR_TMP}; return ${FALSE}; fi

        debug_echo "Mounting $CDC_DMG_PATH to $TEMP_MOUNT_PATH..."
        attach_dmg "$CDC_DMG_PATH" "$TEMP_MOUNT_PATH"
        if [ "$?" != "0" ]; then rm -rf ${VAR_TMP}; return ${FALSE}; fi

        debug_echo "Checking .pkg exists..."
        CDC_PKG_PATH=`find $TEMP_MOUNT_PATH -name "*.pkg"`
        if [ "$?" != "0" ]; then detach_dmg "$TEMP_MOUNT_PATH"; rm -rf ${VAR_TMP}; return ${FALSE}; fi

        debug_echo "Copying $CDC_PKG_PATH to $VAR_TMP..."
        cp -pR "$CDC_PKG_PATH" "${VAR_TMP}"
        if [ "$?" != "0" ]; then detach_dmg "$TEMP_MOUNT_PATH"; rm -rf ${VAR_TMP}; return ${FALSE}; fi

        debug_echo "Unmounting..."
        detach_dmg "$TEMP_MOUNT_PATH"

        for file in `ls ${VAR_TMP} | egrep "\.(tar|pkg)$"`
        do
            ADJOIN_APP_PATH="/Applications/Utilities/Centrify/Centrify\ Join\ Assistant.app"
            if [ -L "${ADJOIN_APP_PATH}" ]; then
                echo $ECHO_FLAG "\nRemoving symbolic link of Centrify Join Assistant.app ${ADJOIN_APP_PATH}" | tee -a ${LOG_FILE}
                rm -f $ADJOIN_APP_PATH
            fi

            echo $ECHO_FLAG "\nInstalling from $file ..." | tee -a ${LOG_FILE}

            RET=1
            case $file in
            *.pkg)
                /usr/sbin/installer -pkg "${VAR_TMP}/$file" -target /
                RET=$?
                ;;
            *.tar)
                tar -C / ${FLAG} -xf $file
                RET=$?
                if [ $RET -eq 0 ]; then
                    tar -tf $file | sed 's/\.\//\//g' > $file.lst
                    rm -f $file
                    check_list_file $file
                fi
                ;;
            esac

            if [ $RET -ne 0 ]; then
                RC=1
            else
                RC=0
            fi
        done
        ;;
    esac
    echo INFO: install/upgrade RC=${RC} >> ${LOG_FILE}
    if [ "${RC}" != "0" ]; then return ${FALSE}; fi
    return ${TRUE}
} # do_install()

### check if installed package has a list file (mac os)
check_list_file ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: check_list_file: " >> ${LOG_FILE}
        if [ "`echo ${CDC_VER} | grep '-' 2> /dev/null`" != "" ]; then
            ### installing package with long version number
            LIST_FILE_NAME="`basename $1 | sed s/tar/tgz/`.lst"
            if [ "`cat ${1}.lst | grep ${LIST_FILE_NAME} 2> /dev/null`" != "" ]; then
                debug_echo "Found package list file /usr/share/centrifydc/${LIST_FILE_NAME}"
            else
                echo "Could not find list file in the package." >> ${LOG_FILE}
                echo "Generating package list file ..." >> ${LOG_FILE}
                echo "/usr/share/centrifydc/${LIST_FILE_NAME}" >> ${1}.lst
                cp ${1}.lst /usr/share/centrifydc/`basename ${1} | sed s/tar/tgz/`.lst
            fi
        else
            if [ "`basename $1 | cut -d'-' -f2`" = "${CDC_VER}" ]; then
                ### installing core package with short version number
                BUILD_NUMBER="`/usr/bin/adinfo --version | cut -d' ' -f3 | cut -d- -f2`"
                LIST_FILE_NAME_FIRST="`basename $1 | cut -d'-' -f1-2`"
                LIST_FILE_NAME_SECOND="`basename $1 | cut -d'-' -f3-4 | sed s/tar/tgz/`"
            else
                ### installing add-on package with short version number
                if [ "`basename $1 | cut -d'-' -f2`" = "adfixid" ]; then
                    BUILD_NUMBER="`/usr/share/centrifydc/bin/adfixid --version | cut -d' ' -f2 | cut -d- -f2`"
                else
                    BUILD_NUMBER=000
                fi
                LIST_FILE_NAME_FIRST="`basename $1 | cut -d'-' -f1-3`"
                LIST_FILE_NAME_SECOND="`basename $1 | cut -d'-' -f4-5 | sed s/tar/tgz/`"
            fi
            LIST_FILE_NAME=`cat ${1}.lst | grep ${LIST_FILE_NAME_FIRST} 2> /dev/null | grep ${LIST_FILE_NAME_SECOND} 2> /dev/null`
            if [ "${LIST_FILE_NAME}" != "" ]; then
                debug_echo "Found package list file ${LIST_FILE_NAME}"
            else
                echo "Could not find list file in the package." >> ${LOG_FILE}
                echo "Generating package list file ..." >> ${LOG_FILE}
                echo "/usr/share/centrifydc/`basename ${1} | sed -e s/${CDC_VER}/${CDC_VER}-${BUILD_NUMBER}/ -e s/tar/tgz/`.lst" >> ${1}.lst
                cp ${1}.lst /usr/share/centrifydc/`basename ${1} | sed s/${CDC_VER}/${CDC_VER}-${BUILD_NUMBER}/ | sed s/tar/tgz/`.lst
            fi
        fi
    return $TRUE
}

### Pre-uninstall steps
do_preremove () 
{
    if [ "$1" = "" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preremove: " >> ${LOG_FILE}

        if [ "${TARGET_OS}" = "darwin" ]; then
            if [ -e /usr/sbin/pcscd-original ]; then
                echo "Copying back original pcscd binary ..." >> ${LOG_FILE}
                mv /usr/sbin/pcscd-original /usr/sbin/pcscd >> ${LOG_FILE}
            fi

            OLD_TOKDIR="/System/Library/Security/tokend"
            NEW_TOKDIR="/Library/Security/tokend"

            for TOKDIR in $OLD_TOKDIR $NEW_TOKDIR
            do
                if [ -d ${TOKDIR}/tokend-original ]; then
                    echo "Copying back original tokend binaries ..." >> ${LOG_FILE}
                    rm -rf ${TOKDIR}/CAC.tokend >> ${LOG_FILE}
                    rm -rf ${TOKDIR}/CACNG.tokend >> ${LOG_FILE}
                    rm -rf ${TOKDIR}/BELPIC.tokend >> ${LOG_FILE}
                    rm -rf ${TOKDIR}/PIV.tokend >> ${LOG_FILE}
                    if [ -d ${TOKDIR}/tokend-original/CAC.tokend ]; then
                        mv ${TOKDIR}/tokend-original/CAC.tokend ${TOKDIR}/CAC.tokend >> ${LOG_FILE}
                    fi
                    if [ -d ${TOKDIR}/tokend-original/CACNG.tokend ]; then
                        mv ${TOKDIR}/tokend-original/CACNG.tokend ${TOKDIR}/CACNG.tokend >> ${LOG_FILE}
                    fi
                    if [ -d ${TOKDIR}/tokend-original/BELPIC.tokend ]; then
                        mv ${TOKDIR}/tokend-original/BELPIC.tokend ${TOKDIR}/BELPIC.tokend >> ${LOG_FILE}
                    fi
                    if [ -d ${TOKDIR}/tokend-original/PIV.tokend ]; then
                        mv ${TOKDIR}/tokend-original/PIV.tokend ${TOKDIR}/PIV.tokend >> ${LOG_FILE}
                    fi
                    rm -rf ${TOKDIR}/tokend-original >> ${LOG_FILE}
                fi
            done

            echo "Removing /etc/centrifydc/*.ovr files ..." >> ${LOG_FILE}
            if [ -f /etc/centrifydc/passwd.ovr ]; then rm -f /etc/centrifydc/passwd.ovr >> ${LOG_FILE}; fi
            if [ -f /etc/centrifydc/group.ovr ]; then rm -f /etc/centrifydc/group.ovr >> ${LOG_FILE}; fi

            if [ -f /etc/shells ]; then
                echo removing /usr/bin/dzsh from /etc/shells ... >> ${LOG_FILE}
                cp -pf /etc/shells /etc/shells.tmp
                cat /etc/shells | sed '/\/usr\/bin\/dzsh/d' > /etc/shells.tmp
                mv /etc/shells.tmp /etc/shells
            fi
        elif [ "${TARGET_OS}" = "aix" ] && [ `uname -v` -ge 6 ]; then
            fix_wpar
        fi

        # turn addebug off
        ADDEBUG="${DATADIR}/centrifydc/bin/addebug"
        ${ADDEBUG} | grep off  >> ${LOG_FILE} 2>> ${LOG_FILE}
        if [ $? -ne 0 ]; then
            echo $ECHO_FLAG "Disabling addebug ..." >> ${LOG_FILE}
            if [ "${TARGET_OS}" = "darwin" ]; then
                if [ -f ${DATADIR}/centrifydc/bin/cdcdebug ]; then
                    ADDEBUG="${DATADIR}/centrifydc/bin/cdcdebug"
                fi
            fi
            ${ADDEBUG} off >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ $? -ne 0 ]; then
                echo $ECHO_FLAG "\nWARNING: Cannot disable addebug" >> ${LOG_FILE}
            fi
        fi
        if [ -f /etc/centrifydc/prev_log_setting_off ]; then
            rm -f /etc/centrifydc/prev_log_setting_off
        fi

        # disable Smart Card support
        if [ "${TARGET_OS}" = "darwin" ]; then
            SCTOOL="${USRBIN}/sctool"
            ${SCTOOL} -s | grep -i enable  >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" = "0" ]; then
                echo $ECHO_FLAG "Disabling Smart Card support ..." >> ${LOG_FILE}
                ${SCTOOL} -d >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
        fi

    elif [ "$1" = "cda" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preremove: $1: " >> ${LOG_FILE}
        if [ -f /usr/share/centrifydc/bin/uninstall-da.sh ]; then rm -f /usr/share/centrifydc/bin/uninstall-da.sh; fi
    elif [ "$1" = "CentrifyDC-nis" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preremove: $1: " >> ${LOG_FILE}
        case "${TARGET_OS}" in
        hpux)
            # need to stop adnisd on HP-UX because we uninstall cdc-nis during upgrade
            /sbin/init.d/adnisd stop >> ${LOG_FILE} 2>> ${LOG_FILE}
            ;;
        solaris)
            # on Solaris 10+ need to check adnisd is disabled in global zone to avoid partial removal (from non-global zones only)
            if [ -x /usr/sbin/zoneadm ] && [ "`zonename`" = "global" ]; then
                check_adnisd_status
                if [ "$?" = "$TRUE" ]; then
                    echo "ERROR: CentrifyDC NIS server is online."  | tee -a ${LOG_FILE}
                    echo "       Please disable it before uninstalling CentrifyDC-nis."  | tee -a ${LOG_FILE}
                    do_error $CODE_EUN
                fi                
            fi
            ;;
        *)
            echo "no need to stop adnisd, we stop adnisd by adleave before uninstall" >> ${LOG_FILE} 2>> ${LOG_FILE}
            ;;
        esac
    else ### add-on
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preremove: $1: skipping ..." >> ${LOG_FILE}
    fi
    return ${TRUE}
} # do_preremove()

### Post-uninstall steps
do_postremove () 
{
    if [ "$1" = "" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postremove: " >> ${LOG_FILE}
        if [ -f ${DATADIR}/centrifydc/bin/uninstall.sh ]; then rm -f ${DATADIR}/centrifydc/bin/uninstall.sh; fi
    elif [ "$1" = "CentrifyDA" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postremove: $1: " >> ${LOG_FILE}
		for tries in 1 2 3 4 5; do
            echo $ECHO_FLAG "making sure dad is not running ... " >> ${LOG_FILE}
		    dadPid=`ps -ae | awk '$4 ~ /^dad$/ { print $1; }'`
		    if [ ! -z "$dadPid" ]; then
		        case "$tries" in
		        1)
                    SMF=no
                    if [ -f /usr/sbin/svccfg -a -f /usr/sbin/svcadm ]; then SMF=yes; fi
		            if [ "${SMF}" = "yes" ]; then
		                /usr/sbin/svcadm disable -s centrifyda >> ${LOG_FILE}
		            else
		                /etc/init.d/centrifyda stop >> ${LOG_FILE} 2>> ${LOG_FILE}
		            fi
		            ;;
		        2)
		            /usr/sbin/dastop >> ${LOG_FILE} 2>> ${LOG_FILE}
		            ;;
		        3 | 4)
		            kill $dadPid >> ${LOG_FILE} 2>> ${LOG_FILE}
		            ;;
		        5)
		            kill -9 $dadPid >> ${LOG_FILE} 2>> ${LOG_FILE}
		            ;;
		        esac
		        sleep 5
		    else
		        break
		    fi
		done
    elif [ "$1" = "CentrifyDC-openssh" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postremove: $1: " >> ${LOG_FILE}
        if [ -f /etc/pam.d/sshd.pre_cdc ]; then
            echo "INFO: restoring /etc/pam.d/sshd from /etc/pam.d/sshd.pre_cdc ..." >> ${LOG_FILE}
            mv /etc/pam.d/sshd.pre_cdc /etc/pam.d/sshd
        fi
    else ### add-on
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postremove: $1: skipping ..." >> ${LOG_FILE}
    fi
    return ${TRUE}
}

### ask to confirm then do uninstall/remove/erase
do_remove_main ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_remove_main: " >> ${LOG_FILE}
    echo preparing  for uninstall ... | tee -a ${LOG_FILE}
    if [ "${INSTALLED}" != "Y" ]; then is_installed; fi
    if [ "${INSTALLED}" = "Y" ]; then
        if [ -z "${ADD_ON_INSTALLED}" ]; then is_addon_installed; fi
        INSTALLED="Y" # core is installed so keep it set to "Y"
        if [ "${SILENT}" = "NO" ]; then
            if [ "${ADD_ON_INSTALLED}" != "" ]; then
                echo $ECHO_FLAG "\nWARNING:" | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "The following Centrify DirectControl add-on package(s) depend on CentrifyDC" | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "core package and will be also removed:" | tee -a ${LOG_FILE}
                for ADD_ON_PKG in ${ADD_ON_INSTALLED}; do
                    echo $ECHO_FLAG ${ADD_ON_PKG} | tee -a ${LOG_FILE}
                done
            fi
            QUESTION="Do you want to uninstall Centrify DirectControl (CentrifyDC-${CUR_VER}) \nfrom this computer? (Q|Y|N) [N]:\c"
            ANSWER=""
            while [ "${ANSWER}" != "Y" -a "${ANSWER}" != "y" ]
            do
                echo ${ECHO_FLAG} "${QUESTION}"
                read ANSWER
                if [ "${ANSWER}" = "q" -o "${ANSWER}" = "Q" ]; then do_quit; fi
                if [ "${ANSWER}" = "" -o "${ANSWER}" = "n" -o "${ANSWER}" = "N" ]; then umask_restore; do_exit $CODE_NUN; fi
            done
            detect_joined_zone
            QUESTION="Reboot the computer after uninstall? (Q|Y|N) [Y]:\c"; do_ask_YorN; REBOOT=${ANSWER}
        else
            if [ "${ADD_ON_INSTALLED}" != "" -a "${UNINSTALL}" = "" ]; then
                ### silent mode, add-on(s) installed, config file has INSTALL=E but UNINSTALL is not set
                echo $ECHO_FLAG "\nERROR:" | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "Found the next add-on package:" | tee -a ${LOG_FILE}
                for ADD_ON_PKG in ${ADD_ON_INSTALLED}; do
                    echo $ECHO_FLAG ${ADD_ON_PKG}
                done
                echo $ECHO_FLAG "Please define UNINSTALL=Y in config file to allow" | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "complete uninstall of all Centrify DirectControl packages." | tee -a ${LOG_FILE}
                do_error $CODE_ESU
            fi
            detect_joined_zone
            ### force to leave domain if computer joined
            if test -s ${VAR}/centrifydc/kset.domain; then
                echo $ECHO_FLAG "\nWARNING: non-interactive uninstall, forcing to leave domain ..." | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "\nADINFO:" >> ${LOG_FILE}
                ${USRBIN}/adinfo >> ${LOG_FILE}
                ${USRSBIN}/adleave -f
            fi
            if [ "${ADD_ON_INSTALLED}" != "" ]; then
                echo $ECHO_FLAG "\nWARNING:" | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "The following Centrify DirectControl add-on package(s) depend on CentrifyDC" | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "core package and will be also removed:" | tee -a ${LOG_FILE}
                for ADD_ON_PKG in ${ADD_ON_INSTALLED}; do
                    echo $ECHO_FLAG ${ADD_ON_PKG}
                done
            fi
        fi
        if [ "${ADD_ON_INSTALLED}" != "" ]; then
            ### remove add-on packages first
            echo ""
            for ADD_ON_PKG in ${ADD_ON_INSTALLED}; do
                ADD_ON_PKG_NAME="`echo ${ADD_ON_PKG} | cut -d '-' -f1`"
                if [ "${TARGET_OS}" != "aix" ] && \
                   [ "${ADD_ON_PKG_NAME}" != "CentrifyDA" -a "${ADD_ON_PKG_NAME}" != "centrifyda" ]; then
                    ADD_ON_PKG_NAME="`echo ${ADD_ON_PKG} | cut -d '-' -f1-2`"
                fi
                do_preremove  ${ADD_ON_PKG_NAME}   || { echo "pre-uninstall script failed ...";    do_error $CODE_EUN; }
                do_remove     ${ADD_ON_PKG_NAME}   || { echo "uninstalling CentrifyDC failed ..."; do_error $CODE_EUN; }
                do_postremove ${ADD_ON_PKG_NAME}   || { echo "post-uninstall script failed ...";   do_error $CODE_EUN; }
            done
        fi
        ### remove core package
        do_preremove     || { echo "pre-uninstall script failed ...";    do_error $CODE_EUN; }
        do_remove        || { echo "uninstalling CentrifyDC failed ..."; do_error $CODE_EUN; }
        do_postremove    || { echo "post-uninstall script failed ...";   do_error $CODE_EUN; }
        echo Uninstall successful. | tee -a ${LOG_FILE}
        if [ "${REBOOT}" = "Y" ]; then
            do_reboot   || { echo "rebooting failed ..."; do_error $CODE_EUN; }
        else
            # On Mac, kill loginwindow if no user loged in via console
            if [ "${TARGET_OS}" = "darwin" ]; then
                who | grep console > /dev/null 2>&1
                if [ $? -ne 0 ]; then
                    echo "Killing loginwindow..."| tee -a ${LOG_FILE}
                    killall loginwindow
                    if [ $? -ne 0 ]; then
                        echo "Failed to kill loginwindow."| tee -a ${LOG_FILE}
                    else
                        echo "Succeeded in killing loginwindow."| tee -a ${LOG_FILE}
                    fi
                fi
            fi
        fi
        do_exit $CODE_SUN
        # do_exit() never returs
    elif [ "${ADD_ON_INSTALLED}" != "" ]; then
        ### CDC agent is not installed but found add-on(s)
        missing_agent
        # missing_agent() never returs
    else
        echo ${ECHO_FLAG} "ERROR: Centrify DirectControl is not installed." | tee -a ${LOG_FILE}
        do_error $CODE_NUN
        # do_error() never returns
    fi
} # do_remove_main()

### Uninstall Centrify DirectControl suite
do_remove () 
{
    if [ "$1" = "" ]; then
        ### removing core package
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_remove: " >> ${LOG_FILE}
        rm -rf ${VAR_TMP}
        create_verify_dir "${VAR_TMP}"
        if test -s ${VAR}/centrifydc/kset.domain; then
            echo
            echo This computer is currently joined to the Active Directory domain. | tee -a ${LOG_FILE}
            echo To remove the software cleanly you should leave the domain. | tee -a ${LOG_FILE}
            echo To do so you need to provide AD user name and password. Running 'adleave' ... | tee -a ${LOG_FILE}
            USERID=administrator
            QUESTION="    Enter the Active Directory authorized user [administrator]: \c"; do_ask
            if [ "${ANSWER}" != "" ]; then USERID=${ANSWER}; fi
            ${USRSBIN}/adleave -u ${USERID}
        fi
        if test -s ${VAR}/centrifydc/kset.domain; then
            echo The attempt to leave the domain failed. Do you want to retry? | tee -a ${LOG_FILE}
            echo Running 'adleave' ... | tee -a ${LOG_FILE}
            USERID=administrator
            QUESTION="    Enter the Active Directory authorized user [administrator]: \c"; do_ask
            if [ "${ANSWER}" != "" ]; then USERID=${ANSWER}; fi
            ${USRSBIN}/adleave -u ${USERID}
        fi
        if test -s ${VAR}/centrifydc/kset.domain; then
            echo The attempt to leave the domain failed. The adleave command will run | tee -a ${LOG_FILE}
            echo using the --force option. This option removes and resets only local DirectControl files. | tee -a ${LOG_FILE}
            echo After uninstalling, you will need to manually disable the computer account in Active Directory. | tee -a ${LOG_FILE}
            echo Forcing to leave AD domain now ... | tee -a ${LOG_FILE}
            ${USRSBIN}/adleave -f
        fi
    
        #now that we left the domain, we can safely deregister dsplugin...    
        if [ "${TARGET_OS}" = "darwin" ]; then
            echo ${ECHO_FLAG} "Unregistering Directory Service plugin ..." | tee -a ${LOG_FILE}
            ${DATADIR}/centrifydc/bin/dsconfig off | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "" | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "WARNING: The Centrify DirectControl DirectoryService plugin has been removed" | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "If you had Directory Access (or Directory Utility) running during uninstall,"   | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "the list of plugins might not reflect that change."                           | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "To see the correct state, please quit (CMD-q) and restart Directory Access"   | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "(or Directory Utility) after CentrifyDC removal is complete"                  | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "" | tee -a ${LOG_FILE}
        fi
        
        echo Uninstalling Centrify DirectControl ... | tee -a ${LOG_FILE}
        case "${TARGET_OS}" in
        linux)
            if [ "${PKG_OS_REV}" = "deb6" ]; then
                dpkg -P centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
            else
                rpm -e CentrifyDC
            fi
            if [ "$?" != "0" ]; then do_error; fi
            ;;
        solaris)
            create_admin
            /usr/sbin/pkgrm -a ${ADMIN_FILE} -n CentrifyDC  2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then do_error; fi
            sleep 5
            ;;
        hpux)
            /usr/sbin/swremove CentrifyDC >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then do_error; fi
            ;;
        aix)
            installp -u CentrifyDC.core >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then do_error; fi
            ;;
        darwin)
            remove_tar_package || { remove_tar_package_old; }
            ;;
        esac
        rm -rf ${VAR_TMP}
    else ### if [ "$1" = "" ]
        ### removing add-on package
        echo Uninstalling $1 ... | tee -a ${LOG_FILE}
        case "${TARGET_OS}" in
        linux)
            if [ "${PKG_OS_REV}" = "deb6" ]; then
                dpkg -P $1 >> ${LOG_FILE} 2>> ${LOG_FILE}
            else
                rpm -e $1 >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            if [ "$?" != "0" ]; then do_error; fi
            ;;
        solaris)
            create_admin
            /usr/sbin/pkgrm -a ${ADMIN_FILE} -n $1  2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then do_error; fi
            sleep 5
            ;;
        hpux)
            /usr/sbin/swremove $1 >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then do_error; fi
            ;;
        aix)
            installp -u $1 >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then do_error; fi
            ;;
        darwin)
            remove_tar_package $1 || { remove_tar_package_old $1; }
            ;;
        esac
    fi ### if [ "$1" = "" ]
    return ${TRUE}
} # do_remove()

# mac os uninstall
remove_tar_package ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: remove_tar_package: " >> ${LOG_FILE}
    if [ "$1" = "" ]; then
        LIST_FILE="${DATADIR}/centrifydc/centrifydc-[0-9]*-mac${PKG_OS_REV}.tgz.lst"
        if [ -f /private/etc/centrifydc/centrifydc.conf.bak ]; then rm -f /private/etc/centrifydc/centrifydc.conf.bak; fi # GP backup
        if [ -d /private/etc/centrifydc/new ]; then rm -Rf /private/etc/centrifydc/new; fi # upgrade temp dir
        if [ -d /private/etc/centrifydc/custom ]; then rm -Rf /private/etc/centrifydc/custom; fi # upgrade temp dir
        if [ -d /private/var/centrifydc/previous ]; then rm -Rf /private/var/centrifydc/previous; fi # previous adjoin files
    else
        LIST_FILE="${DATADIR}/centrifydc/`echo $1 | tr A-Z a-z`-[0-9]*-mac${PKG_OS_REV}.tgz.lst"
    fi
    LIST_FILE_NAME="`ls -t ${LIST_FILE} 2>> /dev/null`"
    LIST_FILE_NUMBER="`echo ${LIST_FILE_NAME} | wc -w | sed 's/^[ ^t]*//'`"
    debug_echo LIST_FILE_NAME=${LIST_FILE_NAME}
    if [ ${LIST_FILE_NUMBER} -eq 0 ]; then
        ### try old .lst file with ARCH
        echo $ECHO_FLAG "\nINFO: Couldn't find package list file ${LIST_FILE}, trying old name ..." >> ${LOG_FILE}
        if [ "$1" = "" ]; then
            LIST_FILE="${DATADIR}/centrifydc/centrifydc-[0-9]*-mac${PKG_OS_REV}-${PKG_ARCH}.tgz.lst"
        else
            LIST_FILE="${DATADIR}/centrifydc/`echo $1 | tr A-Z a-z`-[0-9]*-mac${PKG_OS_REV}-${PKG_ARCH}.tgz.lst"
        fi
        LIST_FILE_NAME="`ls -t ${LIST_FILE} 2>> /dev/null`"
        LIST_FILE_NUMBER="`echo ${LIST_FILE_NAME} | wc -w | sed 's/^[ ^t]*//'`"
        debug_echo LIST_FILE_NAME=${LIST_FILE_NAME}
        if [ ${LIST_FILE_NUMBER} -eq 0 ]; then
            echo $ECHO_FLAG "\nWARNING: Couldn't find package list file ${LIST_FILE} ..." >> ${LOG_FILE}
            return ${FALSE}
        fi
        echo $ECHO_FLAG "      ... found ${LIST_FILE}" >> ${LOG_FILE}
    fi
    if [ ${LIST_FILE_NUMBER} -gt 1 ]; then
        echo $ECHO_FLAG "\nWARNING: Found more than one package list file:" >> ${LOG_FILE}
        echo $ECHO_FLAG "`ls -l ${LIST_FILE}`"                              >> ${LOG_FILE}
        echo $ECHO_FLAG "Using the latest list file for uninstal ..."       >> ${LOG_FILE}
        LIST_FILE_NAME_LATEST=
        for j in ${LIST_FILE_NAME}
        do 
            if [ "${LIST_FILE_NAME_LATEST}" = "" ]; then
                ### take first name from the list (the latest)
                LIST_FILE_NAME_LATEST=$j
            else
                ### remove all .lst files but the laters one
                rm -f $j
            fi
        done
        LIST_FILE_NUMBER=1
        LIST_FILE_NAME=${LIST_FILE_NAME_LATEST}
    fi
    if [ ${LIST_FILE_NUMBER} -eq 1 ]; then
        for file in `cat ${LIST_FILE_NAME}`
        do
            if [ -f $file -o -h $file ]; then
                debug_echo "removing file: $file"
                rm -f $file
            fi
            DIR_NAME="`dirname $file | grep entrify 2> /dev/null`"
            ### removing empty dirs recursively, one round for each dir level in the path
            for i in `echo ${DIR_NAME} | sed 's/\// /g'`
            do
                if [ "${DIR_NAME}" != "" ] && [ -d ${DIR_NAME} ]; then
                    if [ "${DIR_NAME}" = "StartupItems" ]; then break; fi
                    ### remove dir if it's empty
                    if [ `ls ${DIR_NAME}  | wc -w | sed 's/^[ ^t]*//'` -eq 0 ]; then
                        debug_echo "removing dir: ${DIR_NAME}"
                        rmdir ${DIR_NAME}
                    else
                        break
                    fi
                    ### shift to the parent dir
                    DIR_NAME="`dirname ${DIR_NAME} | grep entrify 2> /dev/null`"
                fi
            done
        done
        rm -f ${LIST_FILE_NAME}
        if [ "$1" = "" ]; then
            LIST_FILE_NAME="`ls ${DATADIR}/centrifydc/centrifydc-krb5lib-[0-9]*.tgz.lst 2> /dev/null`"
            if [ "${LIST_FILE_NAME}" != "" ]; then rm -f ${DATADIR}/centrifydc/centrifydc-krb5lib-[0-9]*-mac${PKG_OS_REV}-${PKG_ARCH}.tgz.lst; fi
            RC=0
            if [ -d ${DATADIR}/centrifydc ]; then rmdir ${DATADIR}/centrifydc >> ${LOG_FILE} 2>> /dev/null; RC=$?; fi
            if [ $RC -ne 0 ]; then
                echo "\nWARNING: ${DATADIR}/centrifydc is not empty:" >> ${LOG_FILE} 2>> ${LOG_FILE}
                ls -lR ${DATADIR}/centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
                echo "removing ${DATADIR}/centrifydc anyway ...\n" >> ${LOG_FILE} 2>> ${LOG_FILE}
                rm -Rf ${DATADIR}/centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            RC=0
            if [ -d /Applications/Utilities/Centrify ]; then rmdir /Applications/Utilities/Centrify >> ${LOG_FILE} 2>> /dev/null; RC=$?; fi
            if [ $RC -ne 0 ]; then
                echo "\nWARNING: /Applications/Utilities/Centrify is not empty:" >> ${LOG_FILE} 2>> ${LOG_FILE}
                ls -lR /Applications/Utilities/Centrify >> ${LOG_FILE} 2>> ${LOG_FILE}
                 echo "removing /Applications/Utilities/Centrify anyway ...\n" >> ${LOG_FILE} 2>> ${LOG_FILE}
                rm -Rf /Applications/Utilities/Centrify >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            RC=0
            if [ -d /private/var/centrifydc ]; then rmdir /private/var/centrifydc >> ${LOG_FILE} 2>> /dev/null; RC=$?; fi
            if [ $RC -ne 0 ]; then
                echo "\nWARNING: /private/var/centrifydc is not empty:" >> ${LOG_FILE} 2>> ${LOG_FILE}
                ls -lR /private/var/centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
                echo "removing /private/var/centrifydc anyway ...\n" >> ${LOG_FILE} 2>> ${LOG_FILE}
                rm -Rf /private/var/centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            RC=0
            if [ -d /private/etc/centrifydc ]; then rmdir /private/etc/centrifydc >> ${LOG_FILE} 2>> /dev/null; RC=$?; fi
            if [ $RC -ne 0 ]; then
                echo "\nWARNING: /private/etc/centrifydc is not empty:" >> ${LOG_FILE} 2>> ${LOG_FILE}
                ls -lR /private/etc/centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
                echo "removing /private/etc/centrifydc anyway ...\n" >> ${LOG_FILE} 2>> ${LOG_FILE}
                rm -Rf /private/etc/centrifydc >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            RC=0
            if [ -d "/Library/Application Support/Centrify" ]; then rmdir "/Library/Application Support/Centrify" >> ${LOG_FILE} 2>> /dev/null; RC=$?; fi
            if [ $RC -ne 0 ]; then
                echo "\nWARNING: /Library/Application Support/Centrify is not empty:" >> ${LOG_FILE} 2>> ${LOG_FILE}
                ls -lR "/Library/Application Support/Centrify" >> ${LOG_FILE} 2>> ${LOG_FILE}
                echo "removing /Library/Application Support/Centrify anyway ...\n" >> ${LOG_FILE} 2>> ${LOG_FILE}
                rm -Rf "/Library/Application Support/Centrify" >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            RC=0
            rm -Rf /private/etc/cma.d/S_CENTDC*
            if [ -d /private/etc/cma.d ]; then rmdir /private/etc/cma.d >> ${LOG_FILE} 2>> /dev/null; RC=$?; fi
            if [ $RC -ne 0 ]; then
                echo "\nINFO: /private/etc/cma.d is not empty:" >> ${LOG_FILE} 2>> ${LOG_FILE}
                ls -lR /private/etc/cma.d >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
        fi
    fi

    if [ "${TARGET_OS}" = "darwin" ]; then
        #remove the package receipt, in case we were installed from dmg...
        rm -Rf /Library/Receipts/CentrifyDC*.pkg 
        rm -f /var/db/receipts/com.centrify.centrifydc.*
    fi
    return ${TRUE}
} # remove_tar_package()

# mac os uninstall
remove_tar_package_old ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: remove_tar_package_old: " >> ${LOG_FILE}
    if [ "$1" = "" ]; then
        rm -f  /Library/LaunchDaemons/centrifydc.plist 2>> ${LOG_FILE}
        rm -Rf /Library/StartupItems/CentrifyDC/ 2>> ${LOG_FILE}
        rm -Rf /Library/DirectoryServices/PlugIns/CentrifyDC.dsplug 2>> ${LOG_FILE}
        rm -f  /private/etc/pam.d/centrifydc 2>> ${LOG_FILE}
        rm -f  /usr/local/lib/pam/pam_centrifydc.* 2>> ${LOG_FILE}
        rm -Rf /private/etc/centrifydc 2>> ${LOG_FILE}
        rm -Rf /private/var/centrifydc 2>> ${LOG_FILE}
        rm -Rf ${DATADIR}/centrifydc 2>> ${LOG_FILE}
        rm -f  ${USRBIN}/adgpresult 2>> ${LOG_FILE}
        rm -f  ${USRBIN}/adgpupdate 2>> ${LOG_FILE}
        rm -f  ${USRBIN}/adinfo 2>> ${LOG_FILE}
        rm -f  ${USRBIN}/adfinddomain 2>> ${LOG_FILE}
        rm -f  ${USRBIN}/adpasswd 2>> ${LOG_FILE}
        rm -f  ${USRSBIN}/adclient 2>> ${LOG_FILE}
        rm -f  ${USRSBIN}/adflush 2>> ${LOG_FILE}
        rm -f  ${USRSBIN}/adjoin 2>> ${LOG_FILE}
        rm -f  ${USRSBIN}/adleave 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/addebug.1 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/adgpupdate.1 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/adinfo.1 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/adfixid.1 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/adjoin.1 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/adleave.1 2>> ${LOG_FILE}
        rm -f  ${DATADIR}/man/man1/adpasswd.1 2>> ${LOG_FILE}
    elif [ "$1" = "CentrifyDC-krb5" ]; then
        rm -f ${DATADIR}/centrifydc/kerberos/bin/[cfgrstuv]* 2>> ${LOG_FILE}
        rm -f ${DATADIR}/centrifydc/kerberos/bin/k[ers]* 2>> ${LOG_FILE}
        rm -f ${DATADIR}/centrifydc/kerberos/lib/libkadm* 2>> ${LOG_FILE}
        rm -f ${DATADIR}/centrifydc/kerberos/man/man1/[cfrstv]* 2>> ${LOG_FILE}
        rm -f ${DATADIR}/centrifydc/kerberos/man/man1/k[ers]* 2>> ${LOG_FILE}
        rm -Rf ${DATADIR}/centrifydc/kerberos/include 2>> ${LOG_FILE}
        rm -Rf ${DATADIR}/centrifydc/kerberos/man/man5 2>> ${LOG_FILE}
        rm -Rf ${DATADIR}/centrifydc/kerberos/man/man8 2>> ${LOG_FILE}
        rm -Rf ${DATADIR}/centrifydc/kerberos/sbin 2>> ${LOG_FILE}
        rm -Rf ${DATADIR}/centrifydc/kerberos/share 2>> ${LOG_FILE}
    elif [ "$1" = "CentrifyDC-krb5lib" ]; then
        echo $ECHO_FLAG "\nWARNING: CentrifyDC-$1 should be removed by removing CentrifyDc agent." >> ${LOG_FILE}
    elif [ "$1" = "CentrifyDC-adfixid" ]; then
        rm -f ${DATADIR}/centrifydc/bin/adfixid 2>> ${LOG_FILE}
        rm -f ${DATADIR}/man/man1/adfixid.1 2>> ${LOG_FILE}
    elif [ "$1" = "CentrifyDC-utest" ]; then
        rm -Rf ${DATADIR}/centrifydc/tests 2>> ${LOG_FILE}
    else
        echo $ECHO_FLAG "\nERROR: Unknown package $1; Don't know how to remove ..." >> ${LOG_FILE}
        return $FALSE
    fi
    #remove the package receipt, in case we were installed from dmg...
    rm -Rf /Library/Receipts/CentrifyDC*.pkg 
    rm -f /var/db/receipts/com.centrify.centrifydc.*
    return $TRUE
}

copy_installer () {
    cp -f ${THIS_PRG} ${DATADIR}/centrifydc/bin/uninstall.sh >> ${LOG_FILE}
    chmod 550 ${DATADIR}/centrifydc/bin/uninstall.sh >> ${LOG_FILE}
    if [ -f ${DATADIR}/centrifydc/bin/install.sh ]; then rm -f ${DATADIR}/centrifydc/bin/install.sh; fi
}

check_adnisd_status()
{
    case "${TARGET_OS}" in
    darwin)
        # no CDC-nis on Mac OS
        ;;
    aix)
        /usr/bin/lssrc -s adnisd >> ${LOG_FILE} 2>> ${LOG_FILE} && return $TRUE
        ;;
    hpux)
        /sbin/init.d/adnisd status >> ${LOG_FILE} 2>> ${LOG_FILE} && return $TRUE
        ;;
    solaris)
        # Use SMF on Solaris 10.
        if [ -x /usr/bin/svcs ]; then
            /usr/bin/svcs nis/centrifydc-server | grep "online" >> ${LOG_FILE} 2>> ${LOG_FILE} && return $TRUE
        else
            /etc/init.d/adnisd status >> ${LOG_FILE} 2>> ${LOG_FILE} && return $TRUE
        fi
        ;;
    *)
        /etc/init.d/adnisd status >> ${LOG_FILE} 2>> ${LOG_FILE} && return $TRUE
        ;;
    esac
    return $FALSE
}

upgrade_cache()
{
    if [ -f /var/centrifydc/tmp/CENTRIFY_FORCE_CACHE_DELETE ]; then
        echo "INFO: found /var/centrifydc/tmp/CENTRIFY_FORCE_CACHE_DELETE, removing cache ..." >> ${LOG_FILE}
        ls -l /var/centrifydc/*.cache /var/centrifydc/*.idx  >> ${LOG_FILE} 2> /dev/null
        rm -f /var/centrifydc/*.cache /var/centrifydc/*.idx  >> ${LOG_FILE} 2>> ${LOG_FILE}
        rm -f /var/centrifydc/tmp/CENTRIFY_FORCE_CACHE_DELETE >> ${LOG_FILE} 2>> ${LOG_FILE}
    elif [ `/usr/bin/adinfo -c | grep 'adclient.cache.encrypt:' | grep true > /dev/null; echo $?` -eq 0 ]; then
        echo "WARNING: cache is encrypted and it cannot be upgraded" | tee -a ${LOG_FILE}
        ls -l /var/centrifydc/*.cache >> ${LOG_FILE} 2> /dev/null
        if [ "$?" = "0" ]; then
            echo removing *.cache files ... >> ${LOG_FILE}
            rm -f /var/centrifydc/*.cache >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
    elif [ "`echo ${CDC_CUR_VER_FULL} | sed 's/[^0-9]*//g'`" -lt "510000" ]; then
        echo "WARNING: cache cannot be upgraded from ${CDC_CUR_VER_FULL}" | tee -a ${LOG_FILE}
        ls -l /var/centrifydc/*.cache >> ${LOG_FILE} 2> /dev/null
        if [ "$?" = "0" ]; then
            echo removing *.cache files ... >> ${LOG_FILE}
            rm -f /var/centrifydc/*.cache >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
    else
        if [ "${CDC_CUR_CHECK_SUM}" = "" ]; then
            echo upgrading cache from version ${CDC_CUR_VER_FULL} ... >> ${LOG_FILE} 2>> ${LOG_FILE}
            /usr/share/centrifydc/bin/adcache -F "${CDC_CUR_VER_FULL}" >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then
                echo "cache upgrade exited with error, please check log file for details"
            fi
        else
            echo upgrading cache from checksum ${CDC_CUR_CHECK_SUM} ... >> ${LOG_FILE} 2>> ${LOG_FILE}
            /usr/share/centrifydc/bin/adcache -F "${CDC_CUR_CHECK_SUM}" >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ "$?" != "0" ]; then
                echo "cache upgrade exited with error, please check log file for details"
            fi
        fi
    fi
}

### Prepare for upgrade
do_preupgrade () 
{
    if [ "$1" = "" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preupgrade: " >> ${LOG_FILE}

        # check upgrade from 5.0.x in disconnected mode
        UPGRADE_ENFORCEMENT_FILE="/var/centrifydc/tmp/CENTRIFY_FORCE_DISCONNECTED_UPGRADE"
        UPGRADE_FROM_VER4_ERR_MSG="ERROR: Upgrade from CDC version 5.0.X (or below) in disconnected mode is not recommended. To force upgrade please create an empty file $UPGRADE_ENFORCEMENT_FILE."
        UPGRADE_FROM_VER4_WARN_MSG="WARNING: Upgrade from CDC version 5.0.X (or below) in disconnnected mode is not recommended. AD user may have problem to login after upgrade."

        SKIP_UPGRADE_ENFORCEMENT_TEST="NO"
        CDC_VER_ORIG="`/usr/bin/adinfo -v | cut -d ' ' -f 3 | sed 's/[^0-9]*//g'`"
        if [ ${CDC_VER_ORIG} -lt 510000 ]; then
            # CDC_VER_ORIG is below 5.1.x so check if adclient is in connected mode
            CDC_MODE="`/usr/bin/adinfo -m`"
            if [ -n "${CDC_MODE}" ]; then
                if [ "${CDC_MODE}" = "connected" ]; then
                    # connected mode so it is safe to perform upgrade
                    SKIP_UPGRADE_ENFORCEMENT_TEST="YES"
                fi
            else
                # CDC_MODE returns nothing (not joined) so it is safe to perfrom upgrade
                SKIP_UPGRADE_ENFORCEMENT_TEST="YES"
            fi
        else
            # CDC_VER_ORIG is 5.1.x or higher so it is safe to perform upgrade
            SKIP_UPGRADE_ENFORCEMENT_TEST="YES"
        fi

        if [ "${SKIP_UPGRADE_ENFORCEMENT_TEST}" = "NO" ]; then
            echo " " >> ${LOG_FILE}
            if [ ! -f $UPGRADE_ENFORCEMENT_FILE ]; then
                # terminate upgrade
                echo "$UPGRADE_FROM_VER4_ERR_MSG" | tee -a ${LOG_FILE}
                echo Exiting ... | tee -a ${LOG_FILE}
                exit 1
            fi
        fi

        if [ -x /usr/sbin/dacontrol ]; then
            echo $ECHO_FLAG checking DirectAudit status ... >> ${LOG_FILE}
            is_auditing
            if [ ${IS_AUDITING} -eq $FALSE ]; then
                if [ ${DA_NSS} -eq $TRUE ]; then
                    /usr/sbin/dacontrol --cdashContWithoutDad >> ${LOG_FILE} 2>> ${LOG_FILE}
                else
                    echo $ECHO_FLAG DirectAudit is not enabled >> ${LOG_FILE}
                fi
            else
                echo $ECHO_FLAG WARNING: | tee -a ${LOG_FILE}
                echo $ECHO_FLAG Upgrading from ${CDA_CUR_VER} requires disabling DirectAudit so that the new | tee -a ${LOG_FILE}
                echo $ECHO_FLAG DirectAudit mechanism for hooking shells can be installed. | tee -a ${LOG_FILE}
                echo $ECHO_FLAG "Please run 'dacontrol -d -a' to disable auditing, and then restart upgrading." | tee -a ${LOG_FILE}
                echo $ECHO_FLAG Exiting ... | tee -a ${LOG_FILE}
                return ${FALSE}
            fi
        fi

        if [ "${TARGET_OS}" = "darwin" ]; then
            debug_echo "will use pkg for installation, skipping..."
            return ${TRUE}
        elif [ "${TARGET_OS}" = "aix" ]; then
            echo skipping ... >> ${LOG_FILE}
        else
            if [ "${TARGET_OS}" = "solaris" ]; then
                if [ -d /usr/share/centrifydc/libexec ]; then
                    /usr/sbin/pkgchk -l -p /usr/share/centrifydc/libexec | grep CentrifyDC-openssh > /dev/null
                    if [ "$?" = "0" ]; then
                        /usr/sbin/removef CentrifyDC-openssh /usr/share/centrifydc/libexec > /dev/null
                        /usr/sbin/removef -f CentrifyDC-openssh
                    fi
                    /usr/sbin/installf CentrifyDC /usr/share/centrifydc/libexec
                    INSTALLF="run"
                fi
                if [ "`compare_ver ${CDC_VER} 4; echo ${COMPARE}`" != "lt" ] &&
                   [ "`compare_ver ${CUR_VER} 4; echo ${COMPARE}`" = "lt" ]; then
                    if [ -f /usr/share/centrifydc/bin/adfixid ]; then
                        /usr/sbin/installf CentrifyDC /usr/share/centrifydc/bin/adfixid
                        INSTALLF="run"
                    fi
                    if [ -f /usr/share/man/man1/adfixid.1 ]; then
                        /usr/sbin/installf CentrifyDC /usr/share/man/man1/adfixid.1
                        INSTALLF="run"
                    fi
                    if [ -f /usr/sbin/adkeytab ]; then
                        /usr/sbin/installf CentrifyDC /usr/sbin/adkeytab
                        INSTALLF="run"
                    fi
                    if [ -f /usr/share/man/man1/adkeytab.1 ]; then
                        /usr/sbin/installf CentrifyDC /usr/share/man/man1/adkeytab.1
                        INSTALLF="run"
                    fi
                fi
                if [ "`compare_ver ${CDC_VER} 4.2; echo ${COMPARE}`" != "lt" ] &&
                   [ "`compare_ver ${CUR_VER} 4.2; echo ${COMPARE}`" = "lt" ]; then
                    if [ -f /usr/share/centrifydc/java/lib/centrifydc_japi.jar ]; then
                        /usr/sbin/pkgchk -l -p /usr/share/centrifydc/java/lib/centrifydc_japi.jar | grep CentrifyDC-web > /dev/null
                        if [ "$?" = "0" ]; then
                            /usr/sbin/removef CentrifyDC-web /usr/share/centrifydc/java/lib/centrifydc_japi.jar \
                                                   /usr/share/centrifydc/java/lib/centrifydc_jazman.jar \
                                                   /usr/share/centrifydc/java/lib/libcentrifydc_japi.so > /dev/null 2>> ${LOG_FILE}
                            /usr/sbin/removef -f CentrifyDC-web 2>> ${LOG_FILE}
                        fi
                        /usr/sbin/installf CentrifyDC /usr/share/centrifydc/java/lib/centrifydc_japi.jar 2>> ${LOG_FILE}
                        /usr/sbin/installf CentrifyDC /usr/share/centrifydc/java/lib/centrifydc_jazman.jar 2>> ${LOG_FILE}
                        /usr/sbin/installf CentrifyDC /usr/share/centrifydc/java/lib/libcentrifydc_japi.so 2>> ${LOG_FILE}
                        INSTALLF="run"
                    fi
                    if [ -f /usr/bin/adsmb ]; then
                        /usr/sbin/removef CentrifyDC /usr/bin/adsmb > /dev/null 2>> ${LOG_FILE}
                        /usr/sbin/removef -f CentrifyDC > /dev/null 2>> ${LOG_FILE}
                        mv -f /usr/bin/adsmb /usr/bin/adsmb.BK
                        ln -s /usr/bin/adsmb.BK /usr/bin/adsmb
                        /usr/sbin/installf CentrifyDC /usr/bin/adsmb > /dev/null 2>> ${LOG_FILE}
                        INSTALLF="run"
                    fi
                fi
                if [ "${INSTALLF}" = "run" ]; then
                    # installf is slow so run it once
                    /usr/sbin/installf -f CentrifyDC 2>> ${LOG_FILE}
                fi
            fi

            # The START file will inform the package script (preinstall)
            # that install.sh is used during the upgrade (and adclient was
            # running). Note that this file will be removed by package
            # script (preinstall) when it checks whether adclient is runnning.
            rm -f ${VAR}/centrifydc/upgrade/START

            # The INSTALL-START is used by this install.sh script only. It
            # indicates whether adclient was running before running this
            # script.
            rm -f ${VAR}/centrifydc/INSTALL-START

            eval $CHECK_ADCLIENT >> ${LOG_FILE}
            if [ "$?" = "0" ]; then
                echo stopping adclient ... >> ${LOG_FILE}
                mkdir -p ${VAR}/centrifydc/upgrade >> ${LOG_FILE}
                touch ${VAR}/centrifydc/upgrade/START >> ${LOG_FILE}
                touch ${VAR}/centrifydc/INSTALL-START >> ${LOG_FILE}
                disable_cdcwatch

                # The centrifydc script checks svc.startd, we check the
                # same file here.
                if [ -x "/lib/svc/bin/svc.startd" ]; then
                    # For some versions of svcadm (like Solaris 11 Express),
                    # stop timeout doesn't work with -s option.
                    # To avoid hanging here when stop timeout occurs,
                    # run centrifydc (svcadm) in background and kill it when
                    # we no longer see the adclient process.
                    echo "Running 'centrifydc stop' in background ..." >> ${LOG_FILE}

                    # First of all, kill unexpected adclient if we find one.
                    # What we consider as unexpected adclient:
                    # adclient process is found by "ps" but SMF state of centrifydc  is "maintenance" or "disabled"
                    ADCLIENT_SMF_STATE=`/usr/bin/svcs -H -o state,nstate centrifydc | awk '{ print $1 }'`
                    if [ "$ADCLIENT_SMF_STATE" = "maintenance" ] || [ "$ADCLIENT_SMF_STATE" = "disabled" ] ; then
                        ADCLIENT_PID=`ps ${PS_OPTIONS} | grep -w adclient | grep -v tmp | grep -v grep | awk '{ print $2 }'`
                        test -n "$ADCLIENT_PID" && kill -9 $ADCLIENT_PID >> ${LOG_FILE} 2>> ${LOG_FILE}
                    fi
                
                    # To recover from "maintenance" state, we can simply "svcadm disable centrifydc". 
                    # Since there's no adclient process, the SMF state should be "disable".
                    if [ "$ADCLIENT_SMF_STATE" = "maintenance" ] ; then
                        /usr/sbin/svcadm disable centrifydc
                    fi                    

                    /usr/share/centrifydc/bin/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE} &
                    STOP_PID=$!
                    echo "background pid = $STOP_PID" >> ${LOG_FILE}

                    # We also need a timeout here for safe. The default stop
                    # timeout is 60s for svcadm, we need a timeout longer than
                    # that. As we should not timeout here in any cases so we
                    # should make it large.
                    # Note that we loop once per 2 seconds.
                    echo "Waiting for adclient to stop ..." >> ${LOG_FILE}
                    STOP_COUNT=60
                    while eval $CHECK_ADCLIENT >> ${LOG_FILE}; do
                        sleep 2
                        STOP_COUNT=`expr $STOP_COUNT - 1`
                        if test $STOP_COUNT -eq 0 ; then
                            echo "cannot stop adclient" >> ${LOG_FILE}
                            # No idea how to stop it, just get out of the loop.
                            break
                        fi
                    done

                    # Wait a while to let svcadm completes gracefully
                    sleep 2
                    echo "Stopping background process $STOP_PID ..." >> ${LOG_FILE}
                    kill $STOP_PID 2> /dev/null

                    # TBD: Clear centrifydc state?
                    # svcadm clear centrifydc 2> /dev/null
                    
                elif [ -x /usr/share/centrifydc/bin/centrifydc ]; then
                    # Check whether systemd exists
                    HAVE_SYSTEMD=$FALSE
                    # On Fedora 20 systemd is located under /lib/systemd/, which may not in root user default path
                    # On SLES 12 systemd is located under /usr/lib/systemd/
                    if [ -x "`which systemd 2>/dev/null`" ] || [ -x '/lib/systemd/systemd' ] || [ -x '/usr/lib/systemd/systemd' ]; then
                        if [ -d '/lib/systemd/system' ] || [ -d '/usr/lib/systemd/system' ]; then
                            echo "systemd found" >> ${LOG_FILE}
                            HAVE_SYSTEMD=$TRUE
                        fi
                    fi
                    # stop centrifydc
                    if [ "$HAVE_SYSTEMD" = "$TRUE" ] && \
                        [ -n "$CDC_VER_ORIG" ] && [ "$CDC_VER_ORIG" -lt "522000" ] && \
                        [ -f /etc/init.d/centrifydc ]; then
                        # Known problem in /usr/share/centrifydc/bin/centrifydc (See bug 72705)
                        # /usr/share/centrifydc/bin/centrifydc choosed systemctl to
                        # stop adclient, but it failed.
                        /etc/init.d/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                    else
                        /usr/share/centrifydc/bin/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                    fi
                else
                    if [ "${TARGET_OS}" = "hpux" ]; then
                        /sbin/init.d/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                    else
                        /etc/init.d/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                    fi
                fi
                sleep 2
                eval $CHECK_ADCLIENT >> ${LOG_FILE}
                if [ "$?" = "0" ]; then
                    echo "ERROR: failed to stop adclient, exiting ..." >> ${LOG_FILE}
                    do_error $CODE_EUP
                fi
                if [ -f "/etc/nsswitch.conf.pre_cdc" ]; then
                    echo backing out /etc/nsswitch.conf ... >> ${LOG_FILE}
                    cp -p /etc/nsswitch.conf /etc/nsswitch.conf.upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
                    if [ $? -ne 0 ]; then
                       return ${FALSE}
                    fi
                    cp -p /etc/nsswitch.conf.pre_cdc /etc/nsswitch.conf >> ${LOG_FILE} 2>> ${LOG_FILE}
                    if [ $? -ne 0 ]; then
                        return ${FALSE}
                    fi
                fi
            fi
            # remove pid file to avoid cache flush when adclient starts next time
            remove_adclient_pid_file
        fi
    elif [ "$1" = "CentrifyDA" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preupgrade: $1: " >> ${LOG_FILE}
        echo $ECHO_FLAG checking DirectAudit status ... >> ${LOG_FILE}
        is_auditing
        if [ ${IS_AUDITING} -eq $FALSE ]; then
            if [ ${DA_NSS} -eq $TRUE ]; then
                /usr/sbin/dacontrol --cdashContWithoutDad >> ${LOG_FILE} 2>> ${LOG_FILE}
            else
                echo $ECHO_FLAG DirectAudit is not enabled >> ${LOG_FILE}
            fi
            if [ -d /bin/centrifyda ]; then
                rm -Rf /bin/centrifyda >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
        else
            echo $ECHO_FLAG WARNING: | tee -a ${LOG_FILE}
            echo $ECHO_FLAG Upgrading from ${CDA_CUR_VER} requires disabling DirectAudit so that the new | tee -a ${LOG_FILE}
            echo $ECHO_FLAG DirectAudit mechanism for hooking shells can be installed. | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "Please run 'dacontrol -d -a' to disable auditing, and then restart upgrading." | tee -a ${LOG_FILE}
            echo $ECHO_FLAG Exiting ... | tee -a ${LOG_FILE}
            return ${FALSE}
        fi
    elif [ "$1" = "CentrifyDC-nis" ]; then
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preupgrade: $1: " >> ${LOG_FILE}
        check_adnisd_status
        NIS_was_running="$?"
    else ### add-on
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_preupgrade: $1: skipping ..." >> ${LOG_FILE}
    fi
    return ${TRUE}
} # do_preupgrade()

### Post-upgrade configuration
do_postupgrade () 
{
    if [ "$1" = "" ]; then

    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postupgrade: " >> ${LOG_FILE}

    # Run virtual registry migration tool
    echo "Running virtual registry migration tool ..." >> ${LOG_FILE}
    if [ -x /usr/share/centrifydc/mappers/extra/migreg.pl ]; then
        /usr/share/centrifydc/mappers/extra/migreg.pl -d /var/centrifydc/reg >> ${LOG_FILE} 2>> ${LOG_FILE}
    fi

    if [ "${TARGET_OS}" = "darwin" ]; then
        debug_echo "will use pkg for installation, skipping..."
        rm -f ${VAR}/centrifydc/INSTALL-START
        return ${TRUE}
    elif [ "${TARGET_OS}" = "aix" ]; then
        echo skipping ... >> ${LOG_FILE}
    else
        if test -s ${VAR}/centrifydc/kset.domain; then
            if [ -f /etc/nsswitch.conf.upgrade ]; then
                echo restoring /etc/nsswitch.conf ... >> ${LOG_FILE}
                mv /etc/nsswitch.conf.upgrade /etc/nsswitch.conf >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
            if [ -f ${VAR}/centrifydc/INSTALL-START ]; then
                echo restarting adclient ... >> ${LOG_FILE}
                disable_cdcwatch
                if [ -x /usr/share/centrifydc/bin/centrifydc ]; then
                    /usr/share/centrifydc/bin/centrifydc restart >> ${LOG_FILE} 2>> ${LOG_FILE}
                    update_keytab
                else
                    if [ "${TARGET_OS}" = "hpux" ]; then
                        /sbin/init.d/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                        /sbin/init.d/centrifydc start >> ${LOG_FILE} 2>> ${LOG_FILE}
                    else
                        /etc/init.d/centrifydc stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                        /etc/init.d/centrifydc start >> ${LOG_FILE} 2>> ${LOG_FILE}
                    fi
                fi
            fi
        fi
    fi
    rm -f ${VAR}/centrifydc/INSTALL-START

    # Are we using encrypted cache file ?
    # if yes, throw warning
    if [ ! -f /var/centrifydc/kset.domain ]; then
        echo "This machine has not been joined in AD domain" >> ${LOG_FILE}
    elif [ `/usr/bin/adinfo -c | grep 'adclient.cache.encrypt:' | grep true > /dev/null; echo $?` -eq 0 ]; then
        if [ "${INSTALL}" = "R" ]; then
            echo "WARNING: cache is encrypted and it cannot be upgraded" >> ${LOG_FILE}
        else
            echo "WARNING: cache is encrypted and it cannot be upgraded" | tee -a ${LOG_FILE}
        fi
    fi

    elif [ "$1" = "CentrifyDC-nis" ]; then
        # restart adnisd, if it was running before update/reinstall
        check_adnisd_status
        NIS_is_running="$?"
        echo "NIS_is_running ${NIS_is_running}" >> ${LOG_FILE}
        echo "NIS_was_running ${NIS_was_running}" >> ${LOG_FILE}
        if [ "${NIS_was_running}" -eq $TRUE -a "${NIS_is_running}" -ne $TRUE ]; then
            echo "running nisflush -r ..." >> ${LOG_FILE} 2>> ${LOG_FILE}
            if [ -x /usr/share/centrifydc/bin/nisflush ]; then
                /usr/share/centrifydc/bin/nisflush -r >> ${LOG_FILE} 2>> ${LOG_FILE}
            fi
        fi

    else ### add-on
        echo $ECHO_FLAG "\n${THIS_PRG_NAME}: do_postupgrade: $1: skipping ..." >> ${LOG_FILE}
    fi
    return ${TRUE}
} # do_postupgrade()

###
set_license_mode ()
{
if [ "${ADLICENSE}" != "" ]; then
# no need to set license mode when ADLICENSE=""
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: set_license_mode: " >> ${LOG_FILE}
    if [ -x $USRBIN/adlicense ]; then

        if [ "${TARGET_OS}" = "solaris" ] && \
            [ "$IPS" != "Y" ] && \
            [ -x /usr/sbin/zoneadm ] && \
            SOL_ZONES=`/usr/sbin/zoneadm list -cp` && \
            [ "${GLOBAL_ZONE_ONLY}" != "Y" -a "${GLOBAL_ZONE_ONLY}" != "non_global" ]; then
            # Solaris global zone, installing to all zones
            
            echo "Setting zones licensed/express mode from global zone ..." >> ${LOG_FILE}
            echo "$SOL_ZONES" | \
                while read SOL_ZONE ; do
                SOL_ZONENAME=`echo "$SOL_ZONE" | awk -F: '{ print $2 }'`
                SOL_ZONESTATE=`echo "$SOL_ZONE" | awk -F: '{ print $3 }'`
                SOL_ZONEPATH=`echo "$SOL_ZONE" | awk -F: '{ print $4 }'`
                if [ -n "$SOL_ZONENAME" ]; then
                    
                    # On OpenSolaris, ready installed zone to access zone path
                    SOL_NEEDREADY=0
                    if [ "$SOL_ZONESTATE" = "installed" ]; then
                        case ${OS_REV} in
                            sol20* )
                                SOL_NEEDREADY=1
                                ;;
                        esac
                    fi
                    
                    test "$SOL_NEEDREADY" = "1" && \
                        /usr/sbin/zoneadm -z "$SOL_ZONENAME" ready  >> ${LOG_FILE}
                    # TBD: Do this on certain zone states only?
                    echo "  $SOL_ZONENAME: Root path $SOL_ZONEPATH" \
                        >> ${LOG_FILE}
                    if [ -d "$SOL_ZONEPATH" ]; then
                        test "$SOL_ZONEPATH" = "/" && SOL_ZONEROOT= || \
                            SOL_ZONEROOT="$SOL_ZONEPATH/root"
                        if [ "${ADLICENSE}" = "N" ]; then
                            # adlicense does not accept -R and --express
                            # to be used together. To change to express
                            # mode for non-global zones, we need to remove
                            # the license file explicitly.
                            rm -f "$SOL_ZONEROOT/var/centrifydc/kset.licensemode" >> ${LOG_FILE} 2>> ${LOG_FILE}
                        else
                            TMP_MSG="`/usr/bin/adlicense -R "$SOL_ZONEROOT" --licensed 2>> ${LOG_FILE}`"
                            echo "${TMP_MSG}" >> ${LOG_FILE}
                        fi
                    else
                        echo "  Zone $SOL_ZONENAME: Root path $SOL_ZONEPATH does not exist." >> ${LOG_FILE}
                    fi
                    
                    test "$SOL_NEEDREADY" = "1" && \
                        /usr/sbin/zoneadm -z "$SOL_ZONENAME" halt >> ${LOG_FILE}
                fi
            done
        else
            if [ "${ADLICENSE}" = "N" ]; then
                ${USRBIN}/adlicense --express >> ${LOG_FILE}
                if [ "${TARGET_OS}" = "aix" ] && [ `uname -v` -ge 7 ]; then
                    rm -f /usr/share/centrifydc/wpar/etc/centrifydc/licensed
                    touch /usr/share/centrifydc/wpar/etc/centrifydc/express
                fi
            else
                ${USRBIN}/adlicense --licensed >> ${LOG_FILE}
                if [ "${TARGET_OS}" = "aix" ] && [ `uname -v` -ge 7 ]; then
                    rm -f /usr/share/centrifydc/wpar/etc/centrifydc/express
                    touch /usr/share/centrifydc/wpar/etc/centrifydc/licensed
                fi
            fi
        fi
    else
        if [ "${EXPRESS_PL}" -eq $TRUE ]; then
            echo ${ECHO_FLAG} "WARNING: Could not find ${USRBIN}/adlicense." | tee -a ${LOG_FILE}
        fi
    fi
fi
    return ${TRUE}
} # set_license_mode

### Join domain
do_join () 
{
    U_USERID=
    N_COMPUTER=
    S_SERVER=
    W_MODE=
    echo Joining the Active Directory domain ${DOMAIN} ... | tee -a ${LOG_FILE}
    echo ADJ_LIC=${ADJ_LIC} >> ${LOG_FILE}
    echo ADJ_FORCE=${ADJ_FORCE} >> ${LOG_FILE}
    echo ADJ_TRUST=${ADJ_TRUST} >> ${LOG_FILE}
    echo USERID=${USERID} >> ${LOG_FILE}
    echo COMPUTER=${COMPUTER} >> ${LOG_FILE}
    echo CONTAINER=${CONTAINER} >> ${LOG_FILE}
    echo SERVER=${SERVER} >> ${LOG_FILE}
    if [ "${EXPRESS_PL}" -eq $TRUE -a "${ADLICENSE}" = "N" ]; then
        W_MODE="-w"
        ZONE="" # no zone in express mode
    fi
    echo ZONE=${ZONE} >> ${LOG_FILE}
    if [ "${ADJ_LIC}" = "workstation" ]; then ADJ_LIC="--licensetype workstation"; else ADJ_LIC=""; fi
    if [ "${ADJ_FORCE}" = "Y" ]; then ADJ_FORCE="-f"; else ADJ_FORCE=""; fi
    if [ "${ADJ_TRUST}" = "Y" ]; then ADJ_TRUST="-T"; else ADJ_TRUST=""; fi
    if [ "${USERID}" != "" -a "${USERID}" != "administrator" ]; then U_USERID="-u ${USERID}"; fi
    if [ "${COMPUTER}" != "" -a "${COMPUTER}" != "`hostname`" ]; then N_COMPUTER="-n ${COMPUTER}"; fi
    if [ "${SERVER}" != "" ]; then S_SERVER="-s ${SERVER}"; fi
    if [ "${W_MODE}" = "" -a "${CONTAINER}" != "" -a "${CONTAINER}" != "Computers" ]; then
        /usr/sbin/adjoin ${DOMAIN} ${ADJ_LIC} ${ADJ_FORCE} ${ADJ_TRUST} ${U_USERID} -p "`echo ${PASSWD}`" ${N_COMPUTER} ${S_SERVER} -c "`echo ${CONTAINER}`" -z "`echo ${ZONE}`" \
                                          && echo "" || { echo "join failed"; return $FALSE; }
    elif [ "${CONTAINER}" != "" -a "${CONTAINER}" != "Computers" ]; then
        /usr/sbin/adjoin ${DOMAIN} ${ADJ_LIC} ${ADJ_FORCE} ${ADJ_TRUST} ${U_USERID} -p "`echo ${PASSWD}`" ${N_COMPUTER} ${S_SERVER} -c "`echo ${CONTAINER}`" ${W_MODE} \
                                          && echo "" || { echo "join failed"; return $FALSE; }
    elif [ "${W_MODE}" = "" ]; then
        /usr/sbin/adjoin ${DOMAIN} ${ADJ_LIC} ${ADJ_FORCE} ${ADJ_TRUST} ${U_USERID} -p "`echo ${PASSWD}`" ${N_COMPUTER} ${S_SERVER} -z "`echo ${ZONE}`" \
                                          && echo "" || { echo "join failed"; return $FALSE; }
    else
        /usr/sbin/adjoin ${DOMAIN} ${ADJ_LIC} ${ADJ_FORCE} ${ADJ_TRUST} ${U_USERID} -p "`echo ${PASSWD}`" ${N_COMPUTER} ${S_SERVER} ${W_MODE} \
                                          && echo "" || { echo "join failed"; return $FALSE; }
    fi
} # do_join()

### Reboot the computer
do_reboot () {
    umask_restore
    echo "Rebooting the computer ..."
    while [ "${DELAY}" != "0" ]
    do
        echo ${ECHO_FLAG} "You have ${DELAY} seconds left before rebooting. Press CTRL-C to terminate  \r\c"
        sleep 1
        DELAY=`expr ${DELAY} - 1`
    done
    echo "Rebooting now ...                                                                     "
    sync; sync
    ${REBOOT_CMD}
    return $TRUE
}

### print drive space information
print_df ()
{
    echo $ECHO_FLAG "\nERROR: Installation error" >> ${LOG_FILE}
    echo $ECHO_FLAG "\nChecking file system before exit...\n" >> ${LOG_FILE}
    if [ "${TARGET_OS}" = "hpux" ]; then
        bdf >> ${LOG_FILE}
    else
        df -k >> ${LOG_FILE}
    fi
    return ${TRUE}
}

### print error message about missing CDC agent while add-on(s) installed
missing_agent()
{
    echo $ECHO_FLAG "\nERROR: Broken dependencies!" | tee -a ${LOG_FILE}
    echo "Centrify DirectControl (CentrifyDC) is not installed on this computer but" | tee -a ${LOG_FILE}
    echo "it is required by the next already installed add-on package(s):" | tee -a ${LOG_FILE}
    for i in ${ADD_ON_INSTALLED}; do
        echo "    ${i}" | tee -a ${LOG_FILE}
    done
    echo "Please resolve dependency issue and then rerun this installer." | tee -a ${LOG_FILE}
    do_error $CODE_ESU
    # do_error() never returs
}

### Exit with error
do_error () {
    umask_restore
    if [ "$1" = "" ]; then
        if [ "${INSTALL}" = "Y" ]; then
            RC=$CODE_EIN
        elif [ "${INSTALL}" = "U" ]; then
            RC=$CODE_EUP
        else
            RC=$FALSE
        fi
    else
        RC=$1
    fi
    
    if [ -n "${LOG_FILE}" ]; then    
        echo ${ECHO_FLAG} "\nError detected." >> ${LOG_FILE}
        echo ${ECHO_FLAG} "\nError detected. More information may be found in the logfile"
        echo "(location is ${LOG_FILE})."
        echo $ECHO_FLAG "Exiting ..." | tee -a ${LOG_FILE}
        echo $ECHO_FLAG "EXIT CODE: $RC" >> ${LOG_FILE}
    fi
    
    exit $RC
}

### Exit by user request
do_quit () {
    umask_restore
    echo Installation terminated. Exiting ... | tee -a ${LOG_FILE}
    exit 2
}

### Exit gracefully
do_exit () {
    umask_restore
    if [ "$1" = "" ]; then 
        if [ -z "${PKG_I_LIST}" -a -z "${PKG_E_LIST}" ]; then
            RC=$CODE_NIN # nothing on install
        elif [ "${INSTALL}" = "Y" ]; then
            RC=$CODE_SIN # fresh install
        elif [ "${INSTALL}" = "U" ] || [ "${INSTALL}" = "K" -a -n "${PKG_I_LIST}" ]; then
            RC=$CODE_SUP # upgrade or add-on install
        elif [ -n "${PKG_E_LIST}" -a -z "${PKG_I_LIST}" ]; then
            RC=$CODE_SUN # partial uninstall
        else
            RC=$TRUE 
        fi
    else
        RC=$1
    fi
    if [ "$RC" = "$CODE_NIN" -o "$RC" = "$CODE_NUN" ]; then
        echo $ECHO_FLAG "Install.sh completed successfully. Nothing was installed or uninstalled." | tee -a ${LOG_FILE}
    else
        echo $ECHO_FLAG "Install.sh completed successfully." | tee -a ${LOG_FILE}
    fi
    echo $ECHO_FLAG "EXIT CODE: $RC" >> ${LOG_FILE}
    exit $RC
}

do_clean ()
{
    if [ "${TARGET_OS}" = "darwin" ]; then 
        if [ -f /Users/vadim/BUILD/centrifydc/usr/share/centrifydc/ldapproxy/libexec/openldap/libback_centrifydc.la ]; then
            rm -f /Users/vadim/BUILD/centrifydc/usr/share/centrifydc/ldapproxy/libexec/openldap/libback_centrifydc.* \
                           >> ${LOG_FILE} 2>> ${LOG_FILE}
            CUR_DIR="`pwd`"
            cd /Users/vadim/BUILD/centrifydc/usr/share/centrifydc/ldapproxy/libexec
            DIR_LIST="openldap libexec ldapproxy centrifydc share usr centrifydc BUILD vadim"
            for dir in ${DIR_LIST}; do
                echo removing ${dir} >> ${LOG_FILE} 2>> ${LOG_FILE}
                rmdir ${dir} >> ${LOG_FILE} 2>> ${LOG_FILE}
                if [ $? -ne 0 ]; then
                    cd ${CUR_DIR}
                    return $FALSE
                else
                    cd ..
                fi
            done
            cd ${CUR_DIR}
        fi
    fi
    return $TRUE
}

### repair files and dirs conflicts
fix_conflicts ()
{
    if [ "${TARGET_OS}" = "solaris" ] && \
        [ "$IPS" != "Y" ]; then
        # CentrifyDC-openssh
        for dir in /etc/centrifydc/ssh /usr/share/centrifydc/man/man8
        do
            if [ -d ${dir} ]; then
                if echo "${openssh}" | grep "I" > /dev/null ; then
                    /usr/sbin/pkgchk -l -p ${dir} | grep CentrifyDC-openssh > /dev/null
                    if [ "$?" != "0" ]; then
                        /usr/sbin/installf CentrifyDC-openssh ${dir} > /dev/null
                        /usr/sbin/installf -f CentrifyDC-openssh 2>> ${LOG_FILE}
                    fi
                else
                    echo "removing directory $dir ..." >> ${LOG_FILE}
                    rm -r ${dir}
                fi
            fi
        done
        # CentrifyDC-krb5
        if [ -f /usr/share/centrifydc/kerberos/sbin/ktutil ] && \
            [ -x /usr/sbin/zoneadm ] && [ "${GLOBAL_ZONE_ONLY}" = "non_global" ]; then
            /usr/sbin/pkgchk -l -p /usr/share/centrifydc/kerberos/sbin/ktutil | grep CentrifyDC-krb5 > /dev/null
            if [ "$?" = "0" ]; then
                echo "moving files from CentrifyDC-krb5 to CentrifyDC package ..." >> ${LOG_FILE}
                FILE_LIST="\
                bin/krb5-config bin/ksu sbin sbin/ktutil \
                man/man1/kerberos.1 man/man1/krb5-config.1 man/man1/ksu.1 \ 
                man/man5 man/man5/kdc.conf.5 man/man5/krb5.conf.5 \ 
                man/man8 man/man8/ktutil.8 \ 
                "
                for file in ${FILE_LIST}; do
                    path_name="/usr/share/centrifydc/kerberos/${file}"
                    if [ -s ${path_name} ]; then
                        /usr/sbin/removef  CentrifyDC-krb5 ${path_name} > /dev/null
                        /usr/sbin/installf CentrifyDC      ${path_name} > /dev/null
                        INSTALLF="run"
                    fi
                done
                if [ "${INSTALLF}" = "run" ]; then
                    /usr/sbin/removef  -f CentrifyDC-krb5 2>> ${LOG_FILE}
                    /usr/sbin/installf -f CentrifyDC      2>> ${LOG_FILE}
                fi
            fi
        fi
    fi
    return $TRUE
} # fix_conflicts()

### Check if custom log-file exists and writable or could be created
check_log_file ()
{
    if [ "${LOG_FILE}" = "" ]; then
        LOG_FILE=${LOG_FILE_DEF}
    fi
    if [ ! -f ${LOG_FILE} ]; then
        LOG_DIR="`dirname ${LOG_FILE}`/"
        mkdir -p ${LOG_DIR}
        touch ${LOG_FILE}
        if [ "$?" != "0" ]; then
            echo $ECHO_FLAG "\nERROR: Could not create the log-file ${LOG_FILE}."
            if [ "${LOG_FILE}" = "${LOG_FILE_DEF}" ]; then
                LOG_FILE=""
            else
                LOG_FILE=${LOG_FILE_DEF}
                echo "Using default log-file ${LOG_FILE_DEF} instead."
            fi
            return $FALSE
        fi
    fi
    if [ ! -w ${LOG_FILE} ]; then
        echo $ECHO_FLAG "\nWARNING: The log-file ${LOG_FILE} is not writable."
        chmod +w ${LOG_FILE}
        if [ "$?" != "0" ]; then
            echo $ECHO_FLAG "\nERROR: Could not make the log-file ${LOG_FILE} writable."
            if [ "${LOG_FILE}" = "${LOG_FILE_DEF}" ]; then
                LOG_FILE=""
            else
                LOG_FILE=${LOG_FILE_DEF}
                echo "Using default log-file ${LOG_FILE_DEF} instead."
            fi
            return $FALSE
        fi
    fi
    return $TRUE
} # check_log_file()

### Log file header
log_header ()
{
    check_log_file
    if [ "$?" != "0" ]; then
        if [ "${LOG_FILE}" = "" ]; then echo ${ECHO_FLAG} "\nError detected. Exiting ..."; exit $CODE_ESU; fi
        check_log_file   || { echo ${ECHO_FLAG} "\nError detected. Exiting ..."; exit $CODE_ESU; }
    fi
    if [ "${DEBUG}" = "on" ]; then DEBUG_OUT=${LOG_FILE}; fi
    echo $ECHO_FLAG "\n\n${THIS_PRG_NAME} ************** rev = ${CDC_VER_YEAR} (${REV}) *****************" >> ${LOG_FILE}
    ${DATE} >> ${LOG_FILE}
    debug_echo "current dir: `pwd`"
    if [ "${DEBUG}" = "on" ]; then
        ls -l >> ${LOG_FILE}
        echo "`uname -a`" >> ${LOG_FILE} 2>> ${LOG_FILE}
    fi
}

###
logo ()
{
    cat <<-END_LOGO

*****                                     ${SPACES}                            *****
*****             WELCOME to the Centrify ${LOGO_STRING} installer!            *****
*****                                     ${SPACES}                            *****

END_LOGO
}

validate_override ()
{
    echo $ECHO_FLAG "\n${THIS_PRG_NAME}: validate_override: " >> ${LOG_FILE}
    COUNTER=0
    while [ $TRUE ]
    do
        COUNTER=`expr ${COUNTER} + 1`
        OPTION=`echo ${CLI_OPTIONS} | cut -d',' -f${COUNTER}`
        if [ "${OPTION}" = "" ]; then break; fi # no more options, end of list
        OPTION_NAME=`echo ${OPTION} | cut -d'=' -f1`
        OPTION_VAL=`echo ${OPTION} | cut -d'=' -f2`
        VALID_NAME=""
        VALID_VAL=""
        # check if it is known option
        for VAR1 in ${VAR_LIST}; do
            if [ "${VAR1}" = "${OPTION_NAME}" ]; then
                VALID_NAME=$TRUE
            fi
        done
        case ${OPTION_NAME} in
        ADJ_LIC | ADJ_FORCE | ADJ_TRUST | DOMAIN | USERID | PASSWD | COMPUTER | CONTAINER | ZONE | SERVER )
            VALID_NAME=$FALSE
            echo $ECHO_FLAG "---\nWARNING: invalid option: ${OPTION_NAME}, should be used with --adjoin_opt, ignoring ..." | tee -a ${LOG_FILE}
            ;;
        INSTALL | CentrifyDC_* | CentrifyDA )
            # add-on package options with limited valid values
            case ${OPTION_VAL} in
            Y | y | N | n | U | u | R | r | K | k | E | e )
                VALID_VAL=$TRUE ;;
            *)
                VALID_VAL=$FALSE ;;
            esac
            ;;
        ADCHECK | ADJOIN | REBOOT | ADLICENSE | UNINSTALL | DA_ENABLE | GLOBAL_ZONE_ONLY )
            # add-on package options with Y or N only valid values
            case ${OPTION_VAL} in
            Y | y | N | n )
                VALID_VAL=$TRUE ;;
            *)
                VALID_VAL=$FALSE ;;
            esac
            ;;
        *)
            ;;
        esac
        if [ "${VALID_NAME}" = "" ]; then
            echo $ECHO_FLAG "---\nWARNING: unknown option: ${OPTION_NAME}, ignoring ..." | tee -a ${LOG_FILE}
        elif [ "${VALID_VAL}" = "$FALSE" ]; then
            echo $ECHO_FLAG "---\nWARNING: option ${OPTION_NAME} has invalid value ${OPTION_VAL}, ignoring ..." | tee -a ${LOG_FILE}
        elif [ "${VALID_NAME}" = "$TRUE" ]; then
            case "${OPTION_VAL}" in
            y | n | k | u | e | r )
                OPTION_VAL=`echo ${OPTION_VAL} | tr abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ`
                ;;
            esac
            echo $ECHO_FLAG "INFO: current : ${OPTION_NAME}=\c" >> ${LOG_FILE}
            eval echo \$$OPTION_NAME >> ${LOG_FILE}
            # assign new value 
            eval ${OPTION_NAME}=${OPTION_VAL}
            echo $ECHO_FLAG "INFO: new     : ${OPTION_NAME}=\c" >> ${LOG_FILE}
            eval echo \$$OPTION_NAME >> ${LOG_FILE}
        fi
        # check if there is only one option in the list
        if [ "${OPTION}" = "${CLI_OPTIONS}" ]; then break; fi
    done
    return ${TRUE}
} # validate_override()

validate_x_opt ()
{
    uid_check
    detect_os
    case "${TARGET_OS}" in
    hpux)
        if [ "$1" = "enforce_dependencies=false" ]; then X_OPTION_LIST="${X_OPTION_LIST}-x $1 "
        elif [ "$1" = "enforce_scripts=false" ]; then X_OPTION_LIST="${X_OPTION_LIST}-x $1 "
        elif [ "$1" = "allow_downdate=true" ]; then X_OPTION_LIST="${X_OPTION_LIST}-x $1 "
        else
            echo ERROR: invalid extra option: $1
            do_error $CODE_ESU
        fi
        echo "extra options: ${X_OPTION_LIST}" >> ${LOG_FILE}
        ;;
    *)
        echo ERROR: invalid extra option: $1
        do_error $CODE_ESU
        ;;
    esac

    return ${TRUE} 
}

version_weight ()
{
    VERSION_NUMBER=$1
    if [ "`echo ${VERSION_NUMBER} | grep '-'`" != "" ]; then return 4; fi
    if [ "`echo ${VERSION_NUMBER} | grep '\.'`" = "" ]; then return 1
    else
        VERSION_NUMBER=`echo ${VERSION_NUMBER} | sed 's/\./\:/' | cut -d ':' -f2`
        if [ "`echo ${VERSION_NUMBER} | grep '\.'`" = "" ]; then return 2
        else  return 3
        fi
    fi
    # wrong format
    return 0
}

# compare version strings, accept next formats: x.x.x-xxx, x.x.x, x.x or x ( 4.1.0 and: 4 are "eq" )
compare_ver ()
{
    if [ -z "${1}" -o -z "${2}" ]; then echo "ERROR: compare_ver() needs two parameters to compare"; return $FALSE; fi
    V_W_1=`version_weight $1; echo $?`
    V_W_2=`version_weight $2; echo $?`
    ONE=`echo $1 | sed 's/[a-z]//g'`
    TWO=`echo $2 | sed 's/[a-z]//g'`
      if [ `echo $ONE | cut -d. -f1` -lt `echo $TWO | cut -d. -f1` ]; then COMPARE="lt"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f1` -gt `echo $TWO | cut -d. -f1` ]; then COMPARE="gt"; return ${TRUE}
    elif [ ${V_W_1} -eq 1 -o ${V_W_2} -eq 1 ]; then COMPARE="eq"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f2` -lt `echo $TWO | cut -d. -f2` ]; then COMPARE="lt"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f2` -gt `echo $TWO | cut -d. -f2` ]; then COMPARE="gt"; return ${TRUE}
    elif [ ${V_W_1} -eq 2 -o ${V_W_2} -eq 2 ]; then COMPARE="eq"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f3 | cut -d '-' -f1` -lt `echo $TWO | cut -d. -f3 | cut -d '-' -f1` ]; then COMPARE="lt"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f3 | cut -d '-' -f1` -gt `echo $TWO | cut -d. -f3 | cut -d '-' -f1` ]; then COMPARE="gt"; return ${TRUE}
    elif [ ${V_W_1} -eq 3 -o ${V_W_2} -eq 3 ]; then COMPARE="eq"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f3 | cut -d '-' -f2` -lt `echo $TWO | cut -d. -f3 | cut -d '-' -f2` ]; then COMPARE="lt"; return ${TRUE}
    elif [ `echo $ONE | cut -d. -f3 | cut -d '-' -f2` -gt `echo $TWO | cut -d. -f3 | cut -d '-' -f2` ]; then COMPARE="gt"; return ${TRUE}
    else return ${FALSE}
    fi
}

# check if we're asked to install a previous version, which we don't know
# how to handle anymore. mac os x only, at this point.
min_version_required ()
{
    if [ "${UNINSTALL}" = "Y" ]; then #always support uninstall
        return ${TRUE};
    fi

    if [ "${TARGET_OS}" = "darwin" ]; then
        compare_ver ${CDC_VER} ${CDC_VER_MINIMUM_MAC}
        if [ "${COMPARE}" = "lt" ] ; then return ${FALSE}; fi
    fi

    
    return ${TRUE};
}

check_auditing ()
{
    if [ "${cda}" = "S+I+U" -o "${cda}" = "S=I+R" ]; then
        # Warn about session data loss on upgrade
        if [ "`compare_ver ${CDA_CUR_VER} "1.3.0"; echo ${COMPARE}`" = "lt" ]; then
            echo $ECHO_FLAG "\nWARNING:" | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "The upgrade (reinstall) procedure will stop DirectAudit agent." | tee -a ${LOG_FILE}
            echo $ECHO_FLAG Any session data cached locally will be lost.      | tee -a ${LOG_FILE}
            echo $ECHO_FLAG Existing sessions will not be captured until       | tee -a ${LOG_FILE}
            echo $ECHO_FLAG the upgrade is successful and the agent is active. | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "" | tee -a ${LOG_FILE}
        else
            echo $ECHO_FLAG "\nWARNING:" | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "The upgrade (reinstall) procedure will stop DirectAudit agent." | tee -a ${LOG_FILE}
            echo $ECHO_FLAG Existing sessions will not be captured until       | tee -a ${LOG_FILE}
            echo $ECHO_FLAG the upgrade is successful and the agent is active. | tee -a ${LOG_FILE}
            echo $ECHO_FLAG "" | tee -a ${LOG_FILE}
        fi
    fi

    if [ ${IS_AUDITING} -eq $TRUE ] && [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ] \
                                    && [ "${cda}" = "S+I+U" -o "${cda}" = "S=I+R" ]; then
        # Auditing must be disabled during both CDC and DA upgrade/reinstall
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: Centrify DirectAudit auditing is currently enabled"         | tee -a ${LOG_FILE}
        echo "         but must be disabled during upgrade/reinstall."             | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you choose \"N\" to continue without disabling auditing,"        | tee -a ${LOG_FILE}
            echo "         both CentrifyDC and CentrifyDA packages will be excluded from upgrade."  | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to disable auditing now? (Y|N|Q) [Y]:\c"; do_ask_YorN
            if [ "${ANSWER}" = "Y" ]; then
                disable_auditing
            else
                # exclude CDC from upgrade/reinstall
                INSTALL="K"
                if [ "${TARGET_OS}" = "aix" ]; then
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC\.core //'`"
                else
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC //'`"
                fi
                PKG_FILE_LIST_TMP=
                for package_file in ${PKG_FILE_LIST}
                do
                    case "${package_file}" in
                    *"centrifydc-${CDC_VER}"* )
                        echo "excluding $package_file from PKG_FILE_LIST" >> ${LOG_FILE}
                        ;;
                    *)
                        PKG_FILE_LIST_TMP="${PKG_FILE_LIST_TMP} $package_file"
                        ;;
                    esac
                done
                PKG_FILE_LIST=${PKG_FILE_LIST_TMP}
                debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
                debug_echo "PKG_I_LIST=${PKG_I_LIST}"

                # exclude CDA from upgrade/reinstall
                cda="`echo ${cda} | sed 's/[UR]/K/'`"
                if [ "${TARGET_OS}" = "aix" ]; then
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDA\.core//'`"
                else
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDA//'`"
                fi
                PKG_FILE_LIST_TMP=
                for package_file in ${PKG_FILE_LIST}
                do
                    case "${package_file}" in
                    *"centrifyda"* )
                        echo "excluding $package_file from PKG_FILE_LIST" >> ${LOG_FILE}
                        ;;
                    *)
                        PKG_FILE_LIST_TMP="${PKG_FILE_LIST_TMP} $package_file"
                        ;;
                    esac
                done
                PKG_FILE_LIST=${PKG_FILE_LIST_TMP}
                debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
                debug_echo "PKG_I_LIST=${PKG_I_LIST}"
            fi
        else
            echo "         Please disable auditing then restart installation. Exiting ..." | tee -a ${LOG_FILE}
            do_error ${CODE_EUP}
        fi
    elif [ ${IS_AUDITING} -eq $TRUE ] && [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then
        # Auditing must be disabled during CDC upgrade/reinstall
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: Centrify DirectAudit auditing is currently enabled"         | tee -a ${LOG_FILE}
        echo "         but must be disabled during upgrade/reinstall."             | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you choose \"N\" to continue without disabling auditing,"        | tee -a ${LOG_FILE}
            echo "         the CentrifyDC package will be excluded from upgrade."  | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to disable auditing now? (Y|N|Q) [Y]:\c"; do_ask_YorN
            if [ "${ANSWER}" = "Y" ]; then
                disable_auditing
            else
                if [ "${PKG_I_LIST}" = "CentrifyDC" ]; then
                    # Only one package in the list so nothing to install
                    echo $ECHO_FLAG "\nPlease disable auditing then restart installation. Exiting ..." | tee -a ${LOG_FILE}
                    do_exit $CODE_NIN
                else
                    # exclude CDC from upgrade/reinstall
                    INSTALL="K"
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC //'`"
                    PKG_FILE_LIST_TMP=
                    for package_file in ${PKG_FILE_LIST}
                    do
                        case "${package_file}" in
                        *"centrifydc-${CDC_VER}"* )
                            echo "excluding $package_file from PKG_FILE_LIST" >> ${LOG_FILE}
                            ;;
                        *)
                            PKG_FILE_LIST_TMP="${PKG_FILE_LIST_TMP} $package_file"
                            ;;
                        esac
                    done
                    PKG_FILE_LIST=${PKG_FILE_LIST_TMP}
                    debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
                    debug_echo "PKG_I_LIST=${PKG_I_LIST}"
                fi
            fi
        else
            echo "         Please disable auditing then restart installation. Exiting ..." | tee -a ${LOG_FILE}
            do_error ${CODE_EUP}
        fi
    elif [ ${IS_AUDITING} -eq $TRUE ] && [ "${cda}" = "S+I+U" -o "${cda}" = "S=I+R" ]; then
        # Auditing must be disabled during CDA upgrade/reinstall
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: Centrify DirectAudit auditing is currently enabled"         | tee -a ${LOG_FILE}
        echo "         but must be disabled during upgrade/reinstall."             | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you choose \"N\" to continue without disabling auditing,"  | tee -a ${LOG_FILE}
            echo "         the CentrifyDA package will be excluded from upgrade."        | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to disable auditing now? (Y|N|Q) [Y]:\c"; do_ask_YorN
            if [ "${ANSWER}" = "Y" ]; then
                disable_auditing
            else
                # exclude CDA from upgrade/reinstall
                cda="`echo ${cda} | sed 's/[UR]/K/'`"
                PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDA//'`"
                PKG_FILE_LIST_TMP=
                for package_file in ${PKG_FILE_LIST}
                do
                    case "${package_file}" in
                    *"centrifyda"* )
                        echo "excluding $package_file from PKG_FILE_LIST" >> ${LOG_FILE}
                        ;;
                    *)
                        PKG_FILE_LIST_TMP="${PKG_FILE_LIST_TMP} $package_file"
                        ;;
                    esac
                done
                PKG_FILE_LIST=${PKG_FILE_LIST_TMP}
                debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
                debug_echo "PKG_I_LIST=${PKG_I_LIST}"
            fi
        else
            echo "         Please disable auditing or exclude the CentrifyDA package from" | tee -a ${LOG_FILE}
            echo "         upgrade and then restart installation. Exiting ..."             | tee -a ${LOG_FILE}
            do_error ${CODE_EUP}
        fi
    fi
    return ${TRUE}
}

check_dependencies ()
{
    RC=${TRUE}
    
    ### CDC-nis
    ASK_REMOVE_NIS=$FALSE # whether ask user to remove NIS
    NEED_REMOVE_NIS=$FALSE # whether remove NIS
    ### CDC-nis (1) upgrading CDC without CDC-nis
    # For CDC version != CDC-nis version (upgrading CDC only)
    # It is incompatible with older version NIS (only compare the first version number of x.x.x)
    # Ask users to remove NIS if users select to keep current NIS version
    if [ "${INSTALL}" = "U" ] && [ "${nis}" = "I+K" -o "${nis}" = "S+I+K" -o "${nis}" = "S+I+U" ] &&
       [ "`compare_ver ${CDC_VER} ${CUR_VER}; echo ${COMPARE}`" != "lt" ]; then # CUR_VER means currently installed CDC & NIS version
        if [ "${nis}" = "S+I+U" ]; then # if upgrading both CDC and CDC-nis
            # HP-UX and Debian 5 is unable to upgrade CDC and NIS directly (simultaneously)
            if [ "${PKG_OS_REV}" = "deb6" ]; then
                # Workaround: ignore dependency of centrifydc-nis
                LINUX_OPTION="${LINUX_OPTION} --ignore-depends=centrifydc-nis"
            elif [ "${TARGET_OS}" = "hpux" ]; then
                # Workaround: remove NIS add-on package before upgrade
                NEED_REMOVE_NIS=$TRUE
            fi
        else # if keeping NIS
            ASK_REMOVE_NIS=$TRUE
        fi
    fi
    ### CDC-nis (2) upgrading CDC-nis without CDC
    # For CDC version != CDC-nis version (upgrading or installing CDC-nis only)
    # It is incompatible with new version NIS (only compare the major/first version number of x.x.x)
    # Ask users to exclude NIS from upgrade or add CDC to upgrade list
    if [ "${INSTALL}" = "K" ] && [ "${nis}" = "S+I+U" -o "${nis}" = "S+Y" ] &&
       [ "`compare_ver ${CUR_VER} ${CDC_VER}; echo ${COMPARE}`" != "eq" ]; then # CUR_VER means currently installed CDC & NIS version
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: A version of the Centrify DirectControl (CentrifyDC)"                  | tee -a ${LOG_FILE}
        echo "         has been detected that is not compatible with the version of"          | tee -a ${LOG_FILE}
        echo "         DirectControl NIS Server (CentrifyDC-nis) you are installing."         | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC-nis package will be excluded"   | tee -a ${LOG_FILE}
            echo "         from upgrade. You may also quit (Q|N), restart installation and"      | tee -a ${LOG_FILE}
            echo "         select CentrifyDC for upgrade."                                       | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            else
                # exclude CentrifyDC-nis from install/upgrade
                nis="`echo ${nis} | sed 's/Y/N/' | sed 's/[UR]/K/'`"
                if [ "${TARGET_OS}" = "aix" ]; then
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC.nis//'`"
                else
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC-nis//'`"
                fi
                PKG_FILE_LIST_TMP=
                for package_file in ${PKG_FILE_LIST}
                do
                    case "${package_file}" in
                    *"centrifydc-nis"* )
                        echo "excluding $package_file from PKG_FILE_LIST" >> ${LOG_FILE}
                        ;;
                    *)
                        PKG_FILE_LIST_TMP="${PKG_FILE_LIST_TMP} $package_file"
                        ;;
                    esac
                done
                PKG_FILE_LIST=${PKG_FILE_LIST_TMP}
            fi
        else
            echo "         Please mark CentrifyDC for upgrade and then restart installation."  | tee -a ${LOG_FILE}
            echo "         Exiting ..."                                                        | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    ### CDC-nis (Final)
    if [ "$ASK_REMOVE_NIS" = "$TRUE" ]; then
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: A version of the Centrify DirectControl NIS Server (CentrifyDC-nis)"   | tee -a ${LOG_FILE}
        echo "         has been detected that is not compatible with the version of"          | tee -a ${LOG_FILE}
        echo "         DirectControl you are installing."                                     | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC-nis package will be removed."   | tee -a ${LOG_FILE}
            echo "         You may also quit (Q|N), restart installation and select"             | tee -a ${LOG_FILE}
            echo "         CentrifyDC-nis for upgrade (via Custom install option)."              | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            else
                NEED_REMOVE_NIS=$TRUE
            fi
        else
            echo "         Please modify config file to mark CentrifyDC-nis for removal"   | tee -a ${LOG_FILE}
            echo "         or upgrade and then restart installation. Exiting ..."          | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    if [ "$NEED_REMOVE_NIS" = "$TRUE" ]; then
        if [ "${nis}" = "I+K" ]; then nis="I+E"; fi
        if [ "${nis}" = "S+I+K" ]; then nis="S+I+E"; fi
        if [ "${TARGET_OS}" = "aix" ]; then
            PKG_E_LIST="${PKG_E_LIST} CentrifyDC.nis"
        else
            PKG_E_LIST="${PKG_E_LIST} CentrifyDC-nis"
        fi
    fi
    ### end of CDC-nis dependency check

    ### CDC-ldapproxy
    ASK_REMOVE_LDAP=$FALSE # whether ask user to remove CDC-ldapproxy
    NEED_REMOVE_LDAP=$FALSE # whether remove CDC-ldapproxy
    ### CDC-ldapproxy (1) upgrading CDC without CDC-ldapproxy
    # For CDC version != CDC-ldapproxy version (upgrading CDC only)
    # It is incompatible with older version CDC-ldapproxy (only compare the first version number of x.x.x)
    # Ask users to remove CDC-ldapproxy if users select to keep current CDC-ldapproxy version
    if [ "${INSTALL}" = "U" ] && [ "${ldapproxy}" = "I+K" -o "${ldapproxy}" = "S+I+K" -o "${ldapproxy}" = "S+I+U" ] &&
       [ "`compare_ver ${CDC_VER} ${CUR_VER}; echo ${COMPARE}`" != "lt" ]; then # CUR_VER means currently installed CDC & CDC-ldapproxy version
        if [ "${ldapproxy}" = "S+I+U" ]; then # if upgrading both CDC and CDC-ldapproxy
            # HP-UX and Debian 5 is unable to upgrade CDC and CDC-ldapproxy directly (simultaneously)
            if [ "${PKG_OS_REV}" = "deb6" ]; then
                # Workaround: ignore dependency of centrifydc-ldapproxy
                LINUX_OPTION="${LINUX_OPTION} --ignore-depends=centrifydc-ldapproxy"
            elif [ "${TARGET_OS}" = "hpux" ]; then
                # Workaround: remove CDC-ldapproxy add-on package before upgrade
                NEED_REMOVE_LDAP=$TRUE
            fi
        else # if keeping CDC-ldapproxy
            ASK_REMOVE_LDAP=$TRUE
        fi
    fi
    ### CDC-ldapproxy (2) upgrading CDC-ldapproxy without CDC
    # For CDC version != CDC-ldapproxy version (upgrading or installing CDC-ldapproxy only)
    # It is incompatible with new version CDC-ldapproxy
    # Ask users to exclude CDC-ldapproxy from upgrade or add CDC to upgrade list
    if [ "${INSTALL}" = "K" ] && [ "${ldapproxy}" = "S+I+U" -o "${ldapproxy}" = "S+Y" ] &&
       [ "`compare_ver ${CUR_VER} ${CDC_VER}; echo ${COMPARE}`" != "eq" ]; then # CUR_VER means currently installed CDC & CDC-ldapproxy version
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: A version of the Centrify DirectControl (CentrifyDC)"                  | tee -a ${LOG_FILE}
        echo "         has been detected that is not compatible with the version of"          | tee -a ${LOG_FILE}
        echo "         CentrifyDC LDAP Proxy (CentrifyDC-ldapproxy) you are installing."      | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC-ldapproxy package will be"       | tee -a ${LOG_FILE}
            echo "         excluded from upgrade. You may also quit (Q|N), restart installation"  | tee -a ${LOG_FILE}
            echo "         and select CentrifyDC for upgrade."                                    | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            else
                # exclude CentrifyDC-ldapproxy from install/upgrade
                ldapproxy="`echo ${ldapproxy} | sed 's/Y/N/' | sed 's/[UR]/K/'`"
                if [ "${TARGET_OS}" = "aix" ]; then
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC.ldapproxy//'`"
                else
                    PKG_I_LIST="`echo ${PKG_I_LIST} | sed 's/CentrifyDC-ldapproxy//'`"
                fi
                PKG_FILE_LIST_TMP=
                for package_file in ${PKG_FILE_LIST}
                do
                    case "${package_file}" in
                    *"centrifydc-ldapproxy"* )
                        echo "excluding $package_file from PKG_FILE_LIST" >> ${LOG_FILE}
                        ;;
                    *)
                        PKG_FILE_LIST_TMP="${PKG_FILE_LIST_TMP} $package_file"
                        ;;
                    esac
                done
                PKG_FILE_LIST=${PKG_FILE_LIST_TMP}
            fi
        else
            echo "         Please mark CentrifyDC for upgrade and then restart installation."  | tee -a ${LOG_FILE}
            echo "         Exiting ..."                                                        | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    ### CDC-ldapproxy (Final)
    if [ "$ASK_REMOVE_LDAP" = "$TRUE" ]; then
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: A version of the CentrifyDC LDAP Proxy (CentrifyDC-ldapproxy)"         | tee -a ${LOG_FILE}
        echo "         has been detected that is not compatible with the version of"          | tee -a ${LOG_FILE}
        echo "         DirectControl you are installing."                                     | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC-ldapproxy package will be"      | tee -a ${LOG_FILE}
            echo "         removed. You may also quit (Q|N), restart installation and select"    | tee -a ${LOG_FILE}
            echo "         CentrifyDC-ldapproxy for upgrade (via Custom install option)."        | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            else
                NEED_REMOVE_LDAP=$TRUE
            fi
        else
            echo "         Please modify config file to mark CentrifyDC-ldapproxy for removal"   | tee -a ${LOG_FILE}
            echo "         or upgrade and then restart installation. Exiting ..."          | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    if [ "$NEED_REMOVE_LDAP" = "$TRUE" ]; then
        if [ "${ldapproxy}" = "I+K" ]; then ldapproxy="I+E"; fi
        if [ "${ldapproxy}" = "S+I+K" ]; then ldapproxy="S+I+E"; fi
        if [ "${TARGET_OS}" = "aix" ]; then
            PKG_E_LIST="${PKG_E_LIST} CentrifyDC.ldapproxy"
        else
            PKG_E_LIST="${PKG_E_LIST} CentrifyDC-ldapproxy"
        fi
    fi
    ### end of CDC-ldapproxy dependency check
    
    ### CDC-openssh
    if [ "${openssh}" = "S+Y" ] && [ "${TARGET_OS}" = "linux" ] && [ -f /etc/pam.d/sshd ] &&
       [ "`compare_ver ${CDC_VER} 4.4; echo ${COMPARE}`" = "lt" ]; then
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: Non-centrify version of /etc/pam.d/sshd has been found." | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), /etc/pam.d/sshd will be renamed (moved) to"    | tee -a ${LOG_FILE}
            echo "         /etc/pam.d/sshd.pre_cdc to allow CentrifyDC-openssh to be installed." | tee -a ${LOG_FILE}
            echo "         You may also quit (Q|N), restart installation in Custom mode and"     | tee -a ${LOG_FILE}
            echo "         choose to not install the CentrifyDC-openssh package."                | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [Y]:\c"; do_ask_YorN "Y" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            fi
        else
            echo "         It will be renamed (moved) to /etc/pam.d/sshd.pre_cdc prior to CentrifyDC-openssh installation."     | tee -a ${LOG_FILE}
            RC=${TRUE}
        fi
    fi
    ### CDC-openssh (2) upgrading CDC without CDC-openssh on AIX
    # CDC version 5.2.3(+) is incompatible with CDC-openssh version 5.2.2(-)
    # Ask users to remove CDC-openssh if users select to keep current CDC-openssh version
    if [ "${TARGET_OS}" = "aix" ] && [ "${INSTALL}" = "U" ] && [ "${openssh}" = "I+K" -o "${openssh}" = "S+I+K" ] && 
       [ "`compare_ver ${CUR_VER} ${CDC_VER_INC_SSH}; echo ${COMPARE}`" = "lt" ]; then
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: A version of the CentrifyDC OpenSSH (CentrifyDC.openssh)"         | tee -a ${LOG_FILE}
        echo "         has been detected that is not compatible with the version of"          | tee -a ${LOG_FILE}
        echo "         DirectControl you are installing."                                     | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC.openssh package will be"      | tee -a ${LOG_FILE}
            echo "         removed. You may also quit (Q|N), restart installation and select"    | tee -a ${LOG_FILE}
            echo "         CentrifyDC.openssh for upgrade (via Custom install option)."        | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            else
                if [ "${openssh}" = "I+K" ]; then openssh="I+E"; fi
                if [ "${openssh}" = "S+I+K" ]; then openssh="S+I+E"; fi
                PKG_E_LIST="${PKG_E_LIST} CentrifyDC.openssh"
            fi
        else
            echo "         Please modify config file to mark CentrifyDC.openssh for removal"   | tee -a ${LOG_FILE}
            echo "         or upgrade and then restart installation. Exiting ..."          | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    ### end of CDC-ldapproxy dependency check

    ### CDC-krb5
    if [ "${INSTALL}" = "U" ] && [ "${krb5}" = "I+K" -o "${krb5}" = "S+I+K" ] &&
       [ "`compare_ver ${CDC_VER} ${CDC_VER_INC_KRB5}; echo ${COMPARE}`" != "lt" ] && 
       [ "`compare_ver ${CUR_VER} ${CDC_VER_INC_KRB5}; echo ${COMPARE}`" = "lt" ]; then
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: A version of the Centrify MIT Kerberos Tools (CentrifyDC-krb5)"        | tee -a ${LOG_FILE}
        echo "         has been detected that is not compatible with the version of"          | tee -a ${LOG_FILE}
        echo "         DirectControl you are installing."                                     | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC-krb5 package will be removed."  | tee -a ${LOG_FILE}
            echo "         You may also quit (Q|N), download the latest version of"              | tee -a ${LOG_FILE}
            echo "         CentrifyDC-krb5 and then restart installation."                       | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then 
                do_quit
            else
                if [ "${krb5}" = "I+K" ]; then krb5="I+E"; fi
                if [ "${krb5}" = "S+I+K" ]; then krb5="S+I+E"; fi
                if [ "${TARGET_OS}" = "aix" ]; then
                    PKG_E_LIST="${PKG_E_LIST} CentrifyDC.krb5"
                else
                    PKG_E_LIST="${PKG_E_LIST} CentrifyDC-krb5"
                fi
            fi
        else
            echo "         Please mark CentrifyDC-krb5 for removal or upgrade and then"     | tee -a ${LOG_FILE}
            echo "         restart installation. Exiting ..."                               | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    ### CDC-krb5 (2), upgrading
    if [ "${INSTALL}" = "U" ] && [ "${krb5}" = "S+I+U" ] &&
       [ "`compare_ver ${CDC_VER} ${CDC_VER_INC_KRB5}; echo ${COMPARE}`" != "lt" ] &&
       [ "`compare_ver ${CUR_VER} ${CDC_VER_INC_KRB5}; echo ${COMPARE}`" = "lt" ]; then

        if [ "${TARGET_OS}" = "hpux" ]; then
            PKG_E_LIST="${PKG_E_LIST} CentrifyDC-krb5"
        elif [ "${TARGET_OS}" = "solaris" ] &&
            [ "${GLOBAL_ZONE_ONLY}" != "non_global" ]; then
            PKG_E_LIST="${PKG_E_LIST} CentrifyDC-krb5"
        fi
    fi
    ### CDC-idmap
    if [ "${INSTALL}" = "U" ] && [ "${idmap}" = "I+K" -o "${idmap}" = "S+I+K" ] &&
       [ "`compare_ver ${CDC_VER} ${CDC_VER_INC_IDMAP}; echo ${COMPARE}`" != "lt" ]; then
        # backup samba init script for 4.1.0 upgrade
        INIT_SCRIPT=${INIT_DIR}/centrifydc-samba
        if [ -f ${INIT_SCRIPT} ] && [ ! -f ${INIT_SCRIPT}.upgrade ]; then
            cp -p ${INIT_SCRIPT} ${INIT_SCRIPT}.upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
        # HP-UX only
        RC_SAMBA_FILE=/etc/rc.config.d/centrifydc-samba.rc
        if [ -f ${RC_SAMBA_FILE} ] && [ ! -f ${RC_SAMBA_FILE}.upgrade ]; then
            cp -p ${RC_SAMBA_FILE} ${RC_SAMBA_FILE}.upgrade >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
        echo "" | tee -a ${LOG_FILE}
        echo "WARNING: This version of the CentrifyDC package includes functionality" | tee -a ${LOG_FILE}
        echo "         previously delivered in the CentrifyDC-idmap package."         | tee -a ${LOG_FILE}
        if [ "${SILENT}" = "NO" ]; then
            echo "         If you continue (C|Y), the CentrifyDC-idmap package will be removed." | tee -a ${LOG_FILE}
            QUESTION="\nDo you want to continue installation? (C|Y|Q|N) [N]:\c"; do_ask_YorN "N" "C"
            if [ "${ANSWER}" != "Y" ]; then
                do_quit
            else
                if [ "${idmap}" = "I+K" ]; then idmap="I+E"; fi
                if [ "${idmap}" = "S+I+K" ]; then idmap="S+I+E"; fi
                if [ "${TARGET_OS}" = "aix" ]; then
                    PKG_E_LIST="${PKG_E_LIST} CentrifyDC.idmap"
                else
                    PKG_E_LIST="${PKG_E_LIST} CentrifyDC-idmap"
                fi
            fi
        else
            echo "         Please mark CentrifyDC-idmap for removal and then"               | tee -a ${LOG_FILE}
            echo "         restart installation. Exiting ..."                               | tee -a ${LOG_FILE}
            RC=${FALSE}
        fi
    fi
    debug_echo "PKG_FILE_LIST=${PKG_FILE_LIST}"
    debug_echo "PKG_I_LIST=${PKG_I_LIST}"
    debug_echo "PKG_E_LIST=${PKG_E_LIST}"
    debug_echo INSTALL=${INSTALL}
    return ${RC}
} # check_dependencies

# show installed packages with versions
show_installed ()
{
    ### unknown version
    for ADD_ON_PKG10 in ${ADD_ON_INSTALLED}; do
        case "${ADD_ON_PKG10}" in
        *"0.0.0")
            echo ${ECHO_FLAG} "\nWARNING:" | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "${ADD_ON_PKG10} is installed but version cannot be determined." | tee -a ${LOG_FILE}
            ;;
        esac
    done

    if [ "${INSTALLED}" = "Y" ]; then
        echo ${ECHO_FLAG} "\nCurrently installed:"  | tee -a ${LOG_FILE}
        echo ${ECHO_FLAG} "CentrifyDC-${CUR_VER}" | tee -a ${LOG_FILE}
        for ADD_ON_PKG11 in ${ADD_ON_INSTALLED}; do
            echo ${ECHO_FLAG} "${ADD_ON_PKG11}" | tee -a ${LOG_FILE}
        done
        echo ""
    fi
    return $TRUE
}

warnings ()
{
    ### CDC-openssh (bug 72992 comment 3)
    if [ "${openssh}" = "S+I+U" ]; then
        echo ${ECHO_FLAG} "\nWARNING:" | tee -a ${LOG_FILE}
        echo ${ECHO_FLAG} "The configuration files of the current SSH package may not be entirely"     | tee -a ${LOG_FILE}
        echo ${ECHO_FLAG} "preserved during upgrade. Additional manual configuration may be required." | tee -a ${LOG_FILE}
        QUESTION="\nDo you want installer to back up the current configuration now? (Y|N|Q) [Y]:\c"; do_ask_YorN "Y"
        if [ "${ANSWER}" = "Y" ]; then
            echo ${ECHO_FLAG} "\nPlease remove ${VAR}/centrify/cdc-openssh-backup after recovering your files."   | tee -a ${LOG_FILE}
            echo ${ECHO_FLAG} "Making backup copy in ${VAR}/centrify/cdc-openssh-backup/ ..."                     | tee -a ${LOG_FILE}
            mkdir -p ${VAR}/centrify/cdc-openssh-backup
            chmod 750 ${VAR}/centrify/cdc-openssh-backup
            cp -f /etc/centrifydc/ssh/* ${VAR}/centrify/cdc-openssh-backup
        fi
    fi
    return ${TRUE}
}

# Cleanup if signal is received.
signal_handler ()
{
    trap "" ${SIGNAL_LIST}  
    echo "Signal received." | tee -a ${LOG_FILE}
    if [ -f /etc/nsswitch.conf.upgrade ]; then
        echo "Restoring /etc/nsswitch.conf ..." >> ${LOG_FILE}
        mv /etc/nsswitch.conf.upgrade /etc/nsswitch.conf >> ${LOG_FILE} 2>> ${LOG_FILE}
    fi
    if [ -d "${VAR_TMP}" ]; then
        echo "Cleaning up temporary directory ${VAR_TMP} ..." >> ${LOG_FILE}
    fi
    # always delete it even if it's not a dir
    rm -rf ${VAR_TMP} >> ${LOG_FILE} 2>> ${LOG_FILE}
    do_error ${CODE_SIG}
}

### check_argument_value
check_argument_value ()
{
    # Value can't be null, can't be another option.
    [ -n "${1}" ] && [ -z "`echo "${1}X" | grep '^-'`" ] && return $TRUE

    return $FALSE
}

### check_version_format
check_version_format ()
{
    # Format of the CDC_VER: x.x.x or x.x.x-xxx, x is a number.
    
    if [ -n "${1}" ]; then
        # For format: x.x.x
        echo "${1}" | grep '^[0-9]\.[0-9]\.[0-9]$' > /dev/null 2>&1 && return $TRUE
        
        # For format: x.x.x-xxx
        echo "${1}" | grep '^[0-9]\.[0-9]\.[0-9]-[0-9]\{1,3\}$' > /dev/null 2>&1 && return $TRUE
    fi

    return $FALSE
}

###
### MAIN program
###
main () 
{
    if [ "${BUNDLE_MODE}" != "Y" ]; then logo; fi
    uid_check
    detect_os		|| { echo "detecting platform failed ..."; do_error; }
    # detect_os sets ECHO_FLAG and LOG_FILE, so the first echo to the log-file should be after this point 
    echo ${ECHO_FLAG} "INFO: script_name=${THIS_PRG_NAME}" >> ${LOG_FILE}
    create_verify_dir "${VAR}/centrify"
    find_pkg_dir
    detect_sparse
    if [ "${WPAR}" = "yes" ]; then fix_wpar; fi
    if [ "${FIX_METHODS_CFG}" = "yes" ]; then fix_methods_cfg; fi
    check_exceptions
    umask_check
    trap signal_handler ${SIGNAL_LIST}
    if [ "${BUNDLE_MODE}" = "Y" ]; then install_bundle; fi
    if [ "${SILENT}" = "Y" ]; then set_silent_cfg || do_error $CODE_ESU; fi
    if [ "${UNINSTALL}" = "Y" ] || [ "${SILENT}" = "Y" -a "${INSTALL}" = "E" -a "${UNINSTALL}" = "" ]; then 
        do_remove_main
        # do_remove_main() never returns
    fi
    is_supported         && { SUPPORTED="Y"; SUPPORTED_PL=$TRUE; }
    find_supported_addon && { SUPPORTED_PL=$TRUE; }
    is_installed         && { SUPPORTED_PL=$TRUE; }
    if [ "${INSTALLED}" = "Y" ]; then
        is_addon_installed && { SUPPORTED_PL=$TRUE; }
        INSTALLED="Y" # core is installed so keep it set to "Y"
    elif [ "${SUPPORTED}" = "Y" ]; then
        # agent is not installed and available for install
        is_addon_installed && { missing_agent; }
    elif [ "${SUPPORTED}" = "N" ]; then
        SUPPORTED_PL=$FALSE
    fi
    if [ ${SUPPORTED_PL} -eq $FALSE ]; then
        echo Centrify DirectControl is not installed on this computer. | tee -a ${LOG_FILE}
        echo Could not find ${PKG_FILE} in ${PKG_DIR} directory. | tee -a ${LOG_FILE}
        echo Current platform ${PLATFORM} is not supported or package file is missing. | tee -a ${LOG_FILE}
        do_error $CODE_ESU
    else
        do_clean
        # echo Current platform ${PLATFORM} is supported. | tee -a ${LOG_FILE}; echo "" | tee -a ${LOG_FILE}

        search_adcheck
        if [ "${ADCHECK_FNAME}" != "" -a "${OS_CHECK}" != "skip" ]; then
            ### check OS patches only
            run_adcheck
            if [ "${ADCHECK_RC}" = "3" ]; then
                if [ "${SILENT}" = "NO" ]; then
                    QUESTION="\nDo you want to continue installation? (Q|Y|N) [Y]:\c"; do_ask_YorN
                    if [ "${ANSWER}" != "Y" ]; then do_quit; fi
                else
                    echo "WARNING: adcheck failed ..." | tee -a ${LOG_FILE}
                    do_error $CODE_ESU 
                fi
            fi
        fi

        debug_echo SUPPORTED=$SUPPORTED
        debug_echo INSTALLED=$INSTALLED
        if [ "${SILENT}" = "NO" ]; then
            case "${cda}" in
                S*)
                    ENTERPRISE_PL=$TRUE
                    ;;
            esac
            do_suite_prompt
            CONTINUE="N"
            if [ "${SUITE}" != "Custom" ]; then
                ### go through ENT or STD suite installation only once
                do_silent_prompt
                check_dependencies
                determine_license || do_prompt_license
                express_continue
                do_prompt_join  || { echo "do_prompt_join() failed ..."; do_error; }
                do_prompt_gz
                warnings
                do_verify       || { echo "do_verify() failed ..."; do_error; }
            fi
            while [ "${CONTINUE}" != "Y" ]
            do
                ### loop through custom prompt until confirmed or terminated
                do_prompt       || { echo "do_prompt() failed ..."; do_error; }
                check_dependencies
                determine_license || do_prompt_license
                do_prompt_join  || { echo "do_prompt_join() failed ..."; do_error; }
                do_prompt_gz
                warnings
                do_verify       || { echo "do_verify() failed ..."; do_error; }
            done
        else
            do_silent_prompt
            if [ "${INSTALLED}" = "Y" -a "${PKG_FILE_LIST}" != "" ]; then
                is_installed_gz_only
            fi
            check_dependencies || { do_error; }
            determine_license
            express_continue
            check_auditing
        fi
        if [ "${ADCHECK}" = "Y" -a "${DOMAIN}" != "" -a "${DOMAIN}" != "company.com" ]; then
            ### check AD environment, skip OS tests
            run_adcheck ${DOMAIN}
            if [ "${ADCHECK_RC}" = "3" ] && [ "${SILENT}" = "NO" ]; then
                QUESTION="\nDo you want to continue installation? (Q|Y|N) [Y]:\c"; do_ask_YorN
                if [ "${ANSWER}" != "Y" ]; then do_quit; fi
            fi
        fi
        fix_conflicts

        ### fix me, this is just a workaround
        ### for old version like 5.0.2, we may remove adnisd without stopping it on HP_UX.
        ### So, we need check adnisd status before remove/upgrade it.
        ### We 'd better remove CentrifyDC-nis from PKG_E_LIST
        if [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ] && [ "${nis}" = "S+I+U" -o "${nis}" = "S=I+R" ]; then ### may need restart adnisd after update/reinstall
            do_preupgrade CentrifyDC-nis || { echo "NIS pre-upgrade failed ..."; }
        fi
        if [ "${PKG_E_LIST}" != "" ]; then
            echo ""
            for ADD_ON_PKG in ${PKG_E_LIST}; do
                do_preremove  ${ADD_ON_PKG}   || { echo "pre-uninstall script failed ...";    do_error $CODE_EUN; }
                do_remove     ${ADD_ON_PKG}   || { echo "uninstalling CentrifyDC failed ..."; do_error $CODE_EUN; }
                do_postremove ${ADD_ON_PKG}   || { echo "post-uninstall script failed ...";   do_error $CODE_EUN; }
            done
        fi
        if [ "${cda}" = "S+I+U" -o "${cda}" = "S=I+R" ]; then ### DA needs to check audit is not enabled before upgrade
            do_preupgrade CentrifyDA || { echo "CDA pre-upgrade failed ..."; do_error; }
            set_nonglobal_auditing
        fi
        if [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then ### core package only
            do_preupgrade       || { echo "Pre-upgrade failed ..."; do_error; }
        fi
        if [ "${cda}" = "S+Y" ]; then
            set_nonglobal_auditing
        fi
        if [ "${openssh}" = "S+Y" ]; then
            do_preinstall openssh || { echo "CDC-openssh pre-install failed ..."; do_error; }
        fi
        if [ "${INSTALL}" = "Y" -o "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then ### core package only
            do_preinstall       || { echo "pre-install script failed ..."; do_error; }
        fi
        if [ "${PKG_FILE_LIST}" != "" ]; then
            do_install_main     || { echo "installation failed ..."; do_error; }
        fi
        if [ "${INSTALL}" = "Y" -o "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then ### core package only
            do_postinstall      || { echo "post-install script failed ..."; do_error; }
        fi
        if [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ]; then ### core package only
            do_postupgrade      || { echo "Post-upgrade failed ..."; do_error; }
            # On HP-UX, hash cannot run inside a function. See bug 73031
            hash -r >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
        if [ "${INSTALL}" = "U" -o "${INSTALL}" = "R" ] && [ "${nis}" = "S+I+U" -o "${nis}" = "S=I+R" ]; then ### restrat adnisd
            do_postupgrade CentrifyDC-nis || { echo "Nis Post-upgrade failed ..."; do_error; }
            # On HP-UX, hash cannot run inside a function. See bug 73031
            hash -r >> ${LOG_FILE} 2>> ${LOG_FILE}
        fi
        set_license_mode
        copy_installer
        if [ "${ADJOIN}" = "Y" -o -n "${ADJOIN_CMD_OPTIONS}" ]; then
            if [ "${ADCHECK_RC}" = "3" ]; then
                echo "WARNING: adcheck failed, skipping adjoin ..." | tee -a ${LOG_FILE}
            else
                if [ "${ADJOIN}" = "Y" ]; then
                    do_join	|| { echo ""; do_error; } ### exit if do_join() failed
                    ADJOINED="Y"
                else
                    eval "/usr/sbin/adjoin ${ADJOIN_CMD_OPTIONS}"
                fi
                if [ -s ${VAR}/centrifydc/kset.domain ]; then ADJOINED="Y"; fi
            fi
        fi
        if [ "${DA_ENABLE}" = "Y" ]; then
            if [ "${cda}" = "S=I+K" -o "${cda}" = "S+I+K" -o "${cda}" = "I+K" ]; then
                CDA_VER_AFTER=${CDA_CUR_VER} # "keep" so use current CDA ver
            else
                CDA_VER_AFTER=${CDA_VER} # use new CDA ver
            fi
            if [ "`compare_ver ${CDA_VER_AFTER} 2.1.0; echo ${COMPARE}`" = "lt" ]; then
                if [ "${ADJOINED}" = "Y" ]; then
                    echo "Enabling DirectAudit for all shells ..." | tee -a ${LOG_FILE}
                    /usr/sbin/dacontrol -e -a >> ${LOG_FILE} || { echo "ERROR: DirectAudit enabling failed ..."; do_error; }
                fi
            elif [ -x /usr/sbin/dacontrol ]; then
                ### Even DirectAudit NSS mode is enabled by default in 2.1.0+ ...
                echo "Enabling DirectAudit NSS mode ..." | tee -a ${LOG_FILE}
                /usr/sbin/dacontrol -e >> ${LOG_FILE} || { echo "ERROR: DirectAudit enabling failed ..."; do_error; }
            fi
            DA_ENABLE="enabled"
        elif [ "${DA_ENABLE}" = "N" ]; then
            if [ "${cda}" = "S=I+K" -o "${cda}" = "S=I+R" -o "${cda}" = "S+Y" ] || \
               [ "${cda}" = "S+I+K" -o "${cda}" = "S+I+U" -o "${cda}" = "I+K" ]; then
                if [ "${cda}" = "S=I+K" -o "${cda}" = "S+I+K" -o "${cda}" = "I+K" ]; then
                    CDA_VER_AFTER=${CDA_CUR_VER} # "keep" so use current CDA ver
                else
                    CDA_VER_AFTER=${CDA_VER} # use new CDA ver
                fi
                if [ "`compare_ver ${CDA_VER_AFTER} 2.1.0; echo ${COMPARE}`" = "lt" ]; then
                    echo "No need to diasable auditing with DA ${CDA_VER_AFTER}." >> ${LOG_FILE}
                else
                    echo "Disabling DirectAudit NSS mode ..." | tee -a ${LOG_FILE}
                    /usr/sbin/dacontrol -d >> ${LOG_FILE} || { echo "ERROR: DirectAudit disabling failed ..."; do_error; }
                fi
            fi
        fi
        if [ -x /usr/sbin/dad ]; then
            echo "Restarting DirectAudit daemon ..." | tee -a ${LOG_FILE}
            if [ -x /usr/share/centrifydc/bin/centrifyda ]; then
                /usr/share/centrifydc/bin/centrifyda restart >> ${LOG_FILE} 2>> ${LOG_FILE}
            else
                if [ "${TARGET_OS}" = "hpux" ]; then
                    /sbin/init.d/centrifyda stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                    /sbin/init.d/centrifyda start >> ${LOG_FILE} 2>> ${LOG_FILE}
                else
                    /etc/init.d/centrifyda stop >> ${LOG_FILE} 2>> ${LOG_FILE}
                    /etc/init.d/centrifyda start >> ${LOG_FILE} 2>> ${LOG_FILE}
                fi                    
            fi
        fi
        if [ -x /usr/sbin/dacontrol -a "${DA_INST_NAME}" != "" -a "${ADJOINED}" = "Y" ]; then
            echo setting up DA installation "${DA_INST_NAME}" ... >> ${LOG_FILE}
            /usr/sbin/dacontrol -i "${DA_INST_NAME}"
            if [ $? -ne 0 ]; then echo "WARNING: failed to set DA installation "${DA_INST_NAME}" ..." | tee -a ${LOG_FILE}; fi
        fi
        if [ "${REBOOT}" = "Y" ]; then
            do_reboot	|| { echo "rebooting failed ..."; do_error; }
        fi
        do_exit
    fi
}

THIS_PRG="`echo $0`"
THIS_PRG_NAME="`basename ${THIS_PRG}`"
LOGO_STRING="Suite" ; SPACES=""
EXPRESS_QUESTION_DEFAULT=""

case ${THIS_PRG_NAME} in
uninstall*)
    UNINSTALL="Y" ;;
fix_wpar.sh)
    WPAR="yes" ;;
fix_methods_cfg.sh)
    FIX_METHODS_CFG="yes" ;;
install-bundle*)
    BUNDLE_MODE="Y" ;;
install-express*)
    LOGO_STRING="Express" ; SPACES="  "
    EXPRESS_QUESTION_DEFAULT="X" ;;
esac

### Parse argument list
while [ $# -ge 1 ]; do
    case $1 in
    -V)    echo Centrify ${LOGO_STRING} installer \(${THIS_PRG_NAME}\) rev=${REV_YEAR}; exit 0 ;;
    -v)    shift; CDC_VER=$1 ;
           check_argument_value "$CDC_VER" || { echo "ERROR: invalid version."; do_error $CODE_ESU; };
           # Checking version format
           check_version_format "$CDC_VER" || { echo "ERROR: invalid version format."; do_error $CODE_ESU; };
           CDC_VER_SHORT="`echo ${CDC_VER} | cut -d'-' -f1`";;
    -v*)   CDC_VER=`echo $1 | cut -c3-` ;
           check_argument_value "$CDC_VER" || { echo "ERROR: invalid version."; do_error $CODE_ESU; };
           # Checking version format
           check_version_format "$CDC_VER" || { echo "ERROR: invalid version format."; do_error $CODE_ESU; };
           CDC_VER_SHORT="`echo ${CDC_VER} | cut -d'-' -f1`";;
    -h | --help)    usage; exit 0 ;;
    -e | --erase)   UNINSTALL="Y"; BUNDLE_MODE="N" ;;
    -l)    shift; LOG_FILE=$1 ;
           check_argument_value "$LOG_FILE" || { echo "ERROR: invalid log file."; LOG_FILE=""; do_error $CODE_ESU; };;
    -l*)   LOG_FILE=`echo $1 | cut -c3-` ;
           check_argument_value "$LOG_FILE" || { echo "ERROR: invalid log file."; LOG_FILE=""; do_error $CODE_ESU; };;
    -n)        [ "${SILENT}" = "NO" ] || { echo "ERROR: invalid combination of two non-interactive mode options."; LOG_FILE=""; do_error $CODE_ESU; };
               SILENT="Y";;
    --rev)     shift; FORCE_PKG_OS_REV=$1 ;
               check_argument_value "${FORCE_PKG_OS_REV}" || { echo "ERROR: invalid OS revision."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU; };
#               if [ "${FORCE_PKG_OS_REV}" != "10.7" ]; then echo "ERROR: invalid OS revision."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU; fi;;
               if [ "${FORCE_PKG_OS_REV}" != "10.8" ]; then echo "ERROR: invalid OS revision."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU; fi;;
    --rev*)    FORCE_PKG_OS_REV=`echo $1 | cut -c6-` ;
               check_argument_value "${FORCE_PKG_OS_REV}" || { echo "ERROR: invalid OS revision."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU; };
#               if [ "${FORCE_PKG_OS_REV}" != "10.7" ]; then echo "ERROR: invalid OS revision."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU; fi;;
               if [ "${FORCE_PKG_OS_REV}" != "10.8" ]; then echo "ERROR: invalid OS revision."; FORCE_PKG_OS_REV=""; do_error $CODE_ESU; fi;;
    --ent-suite)    [ "${SILENT}" = "NO" ] || { echo "ERROR: invalid combination of two non-interactive mode options."; LOG_FILE=""; do_error $CODE_ESU; };
                    SUITE="Enterprise"; SILENT="Y"; EXPRESS="N"; SILENT_SUITE_OPT="--ent-suite" ;;
    --std-suite)    [ "${SILENT}" = "NO" ] || { echo "ERROR: invalid combination of two non-interactive mode options."; LOG_FILE=""; do_error $CODE_ESU; };
                    SUITE="Standard"; SILENT="Y"; EXPRESS="N"; SILENT_SUITE_OPT="--std-suite" ;;
    --express)      SUITE="Standard"; SILENT="Y"; EXPRESS="Y"; SILENT_SUITE_OPT="--express" ;;
    --bundle)       BUNDLE_MODE="Y" ;;
    --suite-config) shift; CFG_FNAME_SUITE=$1;
                    check_argument_value "$CFG_FNAME_SUITE" || { echo "ERROR: invalid suite config file."; do_error $CODE_ESU; };;
    --custom_rc)    set_custom_rc ;;
    --utest)        add_utest ;;
    --wpar)         WPAR="yes" ;;
    --fix-methods-cfg)   FIX_METHODS_CFG="yes" ;;
    --no_os_check)  OS_CHECK="skip" ;;
    -x)             shift; validate_x_opt $1 ;;
    -x*)            validate_x_opt "`echo $1 | cut -c3-`" ;;
    --override=*)   OVERRIDE="Y"; CLI_OPTIONS="`echo $1 | cut -c12-`" ;;
    --adjoin_opt=*) ADJOIN="N"; ADJOIN_CMD_OPTIONS="`echo $1 | cut -c14-`" ;;
    --enable-da)    DA_ENABLE="Y" ;;
    --disable-da)   DA_ENABLE="N" ;;
    --debug)        DEBUG="on" ;;
    *)     echo $1: unknown option; usage; uid_check; do_error $CODE_ESU ;;
    esac
    shift
done

# Validate options
if [ "${CLI_OPTIONS}" != "" -a "${SILENT}" = "NO" ]; then
    echo "ERROR: Option --override can be used in non-interactive mode only (-n)."; do_error $CODE_ESU
elif [ "${OVERRIDE}" = "Y" ]; then
    if [ "${CLI_OPTIONS}" = "" ]; then
        echo "ERROR: Empty --override list."; do_error $CODE_ESU
    elif [ `echo ${CLI_OPTIONS} | grep ' ' > /dev/null; echo $?` -eq 0 ]; then
        echo "ERROR:"; echo "Options list has space(s), comma-separated list is expected."; do_error $CODE_ESU
    elif [ "${SUITE}" != "Custom" ]; then
        echo "ERROR:"; echo "Option --override cannot be used with --ent-suite, --std-suite or --express."; echo "Use -n option instead."; do_error $CODE_ESU
    elif [ "${UNINSTALL}" = "Y" ]; then
        echo "ERROR:"; echo "Option --override cannot be used in uninstall mode."; do_error $CODE_ESU
    fi
fi
if [ "${DA_ENABLE}" = "Y" -a "${SILENT}" = "NO" ]; then
    echo "!!!"; echo "WARNING: Option --enable-da is ignored in interactive mode."; echo "!!!"
fi
if [ "${DA_ENABLE}" = "N" -a "${SILENT}" = "NO" ]; then
    echo "!!!"; echo "WARNING: Option --disable-da is ignored in interactive mode."; echo "!!!"
fi

main

