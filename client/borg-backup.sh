#!/bin/bash
set -u -o pipefail

if [[ $UID != 0 ]]; then
	exec sudo "$0" "$@"
fi

export PATH=$PATH:/sbin:/usr/sbin

SCRIPT_DIR=$( cd ${0%/*} && pwd -P )
cd "${SCRIPT_DIR}"

if [[ ! -f ${SCRIPT_DIR}/borg-backup.conf ]]
then
	echo "Please create and fill configuration script: "
	echo "cp borg-backup.conf-dist borg-backup.conf"
	echo "and edit borg-backup.conf"
	exit 2
fi

source "${SCRIPT_DIR}/borg-backup.conf"

#this part is for fixing UPGRADE path
[[ -z ${BORGLOCAL_RESULTDIR+1} ]] && export BORGLOCAL_RESULTDIR="${BORGLOCAL_CACHEDIR}/results"
[[ -z ${BORGLOCAL_STATEDIR+1} ]] && export  BORGLOCAL_STATEDIR="${BORGLOCAL_CACHEDIR}/state"

BORGLOCAL_FAILED=0

initrepo() {
	echo "Initializing backup repo: ${BORG_REPO}"
	${BORGLOCAL_EXEC} init --encryption=keyfile
	echo "This is your key backup, please print it and remember the password!!"
	echo "If the key is lost, all the data is lost too!"
	echo "-----------------------------------------------------------------------------"
	${BORGLOCAL_EXEC} key export --paper
	echo "-----------------------------------------------------------------------------"
}

backup_borg() {
	local -a options=(
		--verbose
		--numeric-owner
		--compression ${BORGLOCAL_COMPRESSION}
		--stats
		--exclude-from "${BORGLOCAL_CACHEDIR}/exclude-list-borg"
		)
	# timing part
	local START
	local STOP
	local DIFF
	local LASTRES
	if tty -s; then
		options+=(-v)
	fi
	START=$(date +%s.%N)
	
	if tty -s; then
		options+=(--progress)
	fi

	# do not continue on error!
	${BORGLOCAL_EXEC} create "${options[@]}" "::${BORGLOCAL_NAME}-$(date "+%Y%m%d-%H%M%S")" ${BORGLOCAL_SOURCE[@]} 
	LASTRES=$?
	END=$(date +%s.%N)
	DIFF=$(echo "$END - $START" | bc)
	echo "$DIFF" > "${BORGLOCAL_RESULTDIR}/create-time"
	echo "Create took $DIFF seconds"
	if [[ $LASTRES -eq 0 ]]
	then
		echo "0" > "${BORGLOCAL_RESULTDIR}/create"
	else
		echo "1" > "${BORGLOCAL_RESULTDIR}/create"
		return
	fi

	# prune only if check is ok
	echo "Starting check"
	START=$(date +%s.%N)
	${BORGLOCAL_EXEC} check --last ${BORGLOCAL_LAST_CHECK} 2>&1 | grep -Ev "^Remote:\s*(Checking segments.*)?$"
	# we don't care about real pipe result, as it will be usually 1 due to grep
	LASTRES=${PIPESTATUS[0]}
	END=$(date +%s.%N)
	DIFF=$(echo "$END - $START" | bc)
	echo "$DIFF" > "${BORGLOCAL_RESULTDIR}/check-time"
	echo "Check took $DIFF seconds"
	if [[ $LASTRES -eq 0 ]]
	then
		echo "0" > "${BORGLOCAL_RESULTDIR}/check"
		if [[ ${BORGLOCAL_NOPRUNE} -eq 0 ]]
		then 
			echo "Starting prune"
			START=$(date +%s.%N)
			${BORGLOCAL_EXEC} prune -s -v ${BORGLOCAL_PRUNE}
			END=$(date +%s.%N)
			DIFF=$(echo "$END - $START" | bc)
			echo "$DIFF" > "${BORGLOCAL_RESULTDIR}/prune-time"
			echo "Prune took $DIFF seconds"
		fi
	else
		echo "Borg check has failed. Please check manually"
		echo "1" > "$BORGLOCAL_RESULTDIR/check"
	fi
}

domysql() {
	local -a options=(
		--defaults-extra-file=${SCRIPT_DIR}/my.cnf
		--single-transaction
		--quick
		--flush-logs
		--all-databases
		--routines
		--triggers
		--events
	)
	local START
	local STOP
	local DIFF
	if tty -s; then
		options+=(-v)
	fi
	START=$(date +%s.%N)
	echo "Starting mysql backup"
	mkdir -p $BORGLOCAL_MYSQL_BACKUPPATH
	# remove previous, already stored in backup, no need to cumulate
	rm -f $BORGLOCAL_MYSQL_BACKUPPATH/mysql-backup-*
	touch ${SCRIPT_DIR}/my.cnf
	chmod 600 ${SCRIPT_DIR}/my.cnf
	echo -e "[mysqldump]\nuser=${BORGLOCAL_MYSQL_USER}\npassword=${BORGLOCAL_MYSQL_PASSWORD}" > ${SCRIPT_DIR}/my.cnf
	$BORGLOCAL_MYSQL_EXECDUMP "${options[@]}"  | gzip -c - > $BORGLOCAL_MYSQL_BACKUPPATH/mysql-backup-$(date "+%Y%m%d-%H%M%S").gz
	if [[ $? -ne 0 ]]
	then
		BORGLOCAL_FAILED=1
		echo "Mysql failed"
		echo "1" > "${BORGLOCAL_RESULTDIR}/mysql"
	else
		echo "0" > "${BORGLOCAL_RESULTDIR}/mysql"
	fi
	END=$(date +%s.%N)
	DIFF=$(echo "$END - $START" | bc)
	echo "MYSQL backup took: $DIFF seconds"
	echo "$DIFF" > "${BORGLOCAL_RESULTDIR}/mysql-time"
}


dobackup() {
	echo "Starting backup"
	mkdir -p "${BORGLOCAL_RESULTDIR}"

	if [[ $BORGLOCAL_DO_MYSQL -eq 1 ]]
	then
		domysql
		if [[ $BORGLOCAL_FAILED -ne 0 ]]
		then
			exit 2
		fi
	fi

	for fs in "${BORGLOCAL_EXCLUDEMOUNTS[@]}"; do
		BORGLOCAL_EXCLUDE+="sh:$fs/*"$'\n'
	done
	
	mkdir -p "${BORGLOCAL_STATEDIR}"
	echo "$BORGLOCAL_EXCLUDE" > "${BORGLOCAL_CACHEDIR}/exclude-list-borg"

	# this will make some more info about system layout
	fdisk -l > "${BORGLOCAL_STATEDIR}/fdisk"
	if which pvdisplay &>/dev/null
	then
			vgdisplay > "${BORGLOCAL_STATEDIR}/vgdisplay"
			pvdisplay > "${BORGLOCAL_STATEDIR}/pvdisplay"
			lvdisplay > "${BORGLOCAL_STATEDIR}/lvdisplay"
	fi
	df -a > "${BORGLOCAL_STATEDIR}/df"
	if which findmnt &>/dev/null
	then
		findmnt -l > "${BORGLOCAL_STATEDIR}/findmnt"
	else
		mount > "${BORGLOCAL_STATEDIR}/mount"
	fi

	# now make an actual backup
	backup_borg

	rm ${BORGLOCAL_CACHEDIR}/exclude-list-borg
	echo "Finished backup process"
}

usage() {
	echo    "-----------------------------------------"
	echo    "----------------- USAGE -----------------"
	echo -e "borg-backup.sh <command> \n"
	echo    "where: "
	echo    "   command: "
	echo    "   initrepo - initialize repo "
	echo    "   dobackup - do next backup "
	echo    "   list     - list archives "
	echo    "   listlast - list last archive content "
	echo    "   infolast - info about last archive "
	echo    "   checkall - check all archives "
	echo    "   borg     - issue any borg command with"
	echo    "              local configuration applied"
	echo    "-----------------------------------------"
	echo    "-----------------------------------------"
}

listarchives() {
	${BORGLOCAL_EXEC} list
}

listlast() {
	local LASTARCHIVE=$(${BORGLOCAL_EXEC} list | cut -f 1 -d " " | tail -n 1)
	if [ ! -z $LASTARCHIVE ]
	then
		if [[ "$1" = "list" ]]
		then
			${BORGLOCAL_EXEC} list "::${LASTARCHIVE}"
		else
			${BORGLOCAL_EXEC} info "::${LASTARCHIVE}"
		fi
	fi
}


checkall() {
	${BORGLOCAL_EXEC} check --info
}

wrapborg() {
	shift
	${BORGLOCAL_EXEC} $@
}


CMDLINE=
if [[ $# -ge 1 ]]
then
	CMDLINE=$1
fi

case $CMDLINE in
	"initrepo") initrepo ;;
	"dobackup") dobackup ;;
	"list") listarchives ;;
	"listlast") listlast list ;;
	"checkall") checkall ;;
	"infolast") listlast info ;;
	"borg") wrapborg $@ ;;
	*) usage ;;
esac

exit 0

#END