#!/bin/bash
set -u -o pipefail

# this script should be run by root, by it may be also
# run by backup user

SCRIPT_DIR=$( cd ${0%/*} && pwd -P )
cd "${SCRIPT_DIR}"

if [[ $# -lt 1 ]]
then
        echo "Usage: borg-add-host.sh fqdn"
        exit 1
fi

if [[ ! -f ${SCRIPT_DIR}/borg-add-host.conf ]]
then
	echo "Please create and fill configuration script: "
	echo "cp borg-add-host.conf-dist borg-add-host.conf"
	echo "and edit borg-add-host.conf"
	exit 2
fi

# configuration is in config file. Changes to this file may be lost
# when updated

source "${SCRIPT_DIR}/borg-add-host.conf"

# local config
BORGLOCAL_FQDN=$1
BORGLOCAL_HOSTNAME=`echo $BORGLOCAL_FQDN | awk 'BEGIN {FS=".";} { print $1; } '`

su - $BORGLOCAL_USER <<EOSU
cd .ssh

if [[ -f ${BORGLOCAL_FQDN} ]]
then
    echo "Keyfile for this host already exists, remove it before continuing"
    exit 3
fi

ssh-keygen -t rsa -b 4096 -C "${BORGLOCAL_HOSTNAME}${BORGLOCAL_KEYCOMMENT}" -f ${BORGLOCAL_FQDN}
echo -en "command=\"cd ${BORGLOCAL_BACKUP_PATH}/${BORGLOCAL_FQDN};borg serve --restrict-to-path ${BORGLOCAL_BACKUP_PATH}/${BORGLOCAL_FQDN}/\",no-port-forwarding,no-X11-forwarding,no-pty,no-agent-forwarding,no-user-rc " >> authorized_keys
cat ${BORGLOCAL_FQDN}.pub >> authorized_keys
mkdir ${BORGLOCAL_BACKUP_PATH}/${BORGLOCAL_FQDN}

echo "     Your private key for ${BORGLOCAL_FQDN} is printed below"
echo "-----------------------------------------------------------------"
cat ${BORGLOCAL_FQDN}
echo "-----------------------------------------------------------------"
EOSU

#END
