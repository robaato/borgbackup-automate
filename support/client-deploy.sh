#!/bin/bash

BORGLOCAL_RELEASE=1.0.9
BORGLOCAL_ARCH=64
BORGLOCAL_ORIGIN='https://github.com/robaato/borgbackup-automate.git'
BORGLOCAL_BRANCH=master

mkdir /opt/borg/
wget -O /opt/borg/borg https://github.com/borgbackup/borg/releases/download/${BORGLOCAL_RELEASE}/borg-linux${BORGLOCAL_ARCH}
chmod 755 /opt/borg/borg
mkdir /etc/borg
chmod 700 /etc/borg
cd /etc/borg

# requires git v.1.9 or newer
git init .
git remote add origin ${BORGLOCAL_ORIGIN}
git config core.sparsecheckout true
echo "client/*" >> .git/info/sparse-checkout
git pull --depth=1 origin ${BORGLOCAL_BRANCH}
git branch --set-upstream-to=origin/master master

[[ ! -f borg-backup.sh ]] && ln -s client/borg-backup.sh borg-backup.sh
[[ ! -f borg-backup.conf ]] &&	cp client/borg-backup.conf-dist borg-backup.conf	

chmod 600 borg-backup.conf
chmod 700 borg-backup.sh
touch host_key
chmod 600 host_key

echo "Deployment done, next steps:"
echo "* put your host key into: host_key"
echo "* edit configuration borg-backup.conf"
echo "* initialize repository ./borg-backup.sh initrepo"
echo "* do first backup ./borg-backup.sh dobackup"

