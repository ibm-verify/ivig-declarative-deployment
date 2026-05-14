#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: pgRestore.sh"
	echo "When to run: If the DB ever needs to be restored from backup."
	echo "Description:"
	echo "   Helper utility to restore a backup generated with pgBackup.sh."
	echo "Options:"
	echo "   filename: path to the backup file to restore.  If not specified"
	echo "             the most recent backup in the backup directory will"
	echo "             be used."
	echo "Example usage:"
	echo "   $ ./pgRestore.sh [filename]"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh
get_namespace || die "Unable to get namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

# Check that the postgres pod is running
printf "Looking for primary PostgreSQL pod..."
POD=$($kubectl -n "$NS" get pods -l replicationRole=primary --no-headers -o custom-columns=":metadata.name")
if [[ -z "$POD" ]]; then
	printf "\n\n"
	echo "No primary PostgreSQL pod found running. Cannot continue."
	exit 1
fi
printf "Done!\n"

# Check the backup file exists
BKUPFILE=$(ls -t ../backup/pgbackup-*.tgz 2>/dev/null | head -n 1)
if [[ -n "$1" ]]; then
	BKUPFILE=$1
	if [[ ! -f $BKUPFILE ]]; then
		# Our CWD is bin not bin/util, so adjust the path
		BKUPFILE=$(sed 's;../\(.*\)$;\1;' <<< "$BKUPFILE")
		if [[ ! -f $BKUPFILE ]]; then
			printf "\nUnable to find user supplied backup file: %s\n" "$BKUPFILE"
			printf "Exiting.\n"
			exit 2
		fi
	fi
fi

printf "Uploading backup file %s to pod..." "$BKUPFILE"
$kubectl -n "$NS" cp "$BKUPFILE" "$POD":"/tmp/$(basename "$BKUPFILE")"
RC=$?
if [[ $RC -ne 0 ]]; then
	printf "\n\n"
	echo "RC = $RC"
	echo "Failed to upload the backup. Try it manually with:"
	BKUPFILE="../$BKUPFILE"
	echo "$kubectl -n $NS cp $BKUPFILE $POD:/tmp/$(basename "$BKUPFILE")"
	exit 3
fi

printf "Done!\nExtracting database SQL..."
$kubectl -n "$NS" exec "$POD" -- bash -c "cd /tmp; tar xzf $(basename "$BKUPFILE")"
if [[ $? -ne 0 ]]; then
	printf "\n\n"
	echo "Failed to expand the backup. Try it manually with:"
	echo "$kubectl -n $NS exec -it $POD -- bash"
	echo "cd /tmp"
	echo "tar xzf $(basename "$BKUPFILE")"
	exit 4
fi

printf "Done!\nLoading database (This will take awhile).."
$kubectl -n "$NS" exec "$POD" -- bash -c "psql < /tmp/pgbackup.sql" > /dev/null 2>&1 &
PID=$!

while [[ 0 -eq 0 ]]; do
	printf "."
	sleep 5
	kill -0 "$PID" > /dev/null 2>&1
	if [[ $? -eq 1 ]]; then
		wait "$PID"
		RC=$?
		if [[ $RC -ne 0 ]]; then
			printf "\n\n"
			echo "Failed to import the DB. Try it manually with:"
			echo "$kubectl -n $NS exec -it $POD -- bash"
			echo "psql < /tmp/pgbackup.sql"
			exit 5
		else
			break
		fi
	fi
done

printf "Done!\nRemoving backup from pod..."
$kubectl -n "$NS" exec "$POD" -- bash -c 'rm /tmp/pgbackup*.*'
if [[ $? -ne 0 ]]; then
	printf "\n\n"
	echo "Failed to remove the backup from pod. Try it manually with:"
	echo "$kubectl -n $NS exec -it $POD -- bash"
	echo "cd /tmp"
	echo 'rm pgbackup*.*'
	exit 6
fi
printf "Done!\n\n"

