#!/bin/bash

DB_PROPS="../data/enRoleDatabase.properties"
TSTAMP=$(date +"%Y%m%d_%H%M%S")
BKUPFILE="pgbackup-$TSTAMP.tgz"

if [[ "$1" = "--help" ]]; then
	echo "Name: pgBackup.sh"
	echo "When to run: Periodically to generate a backup of the DB."
	echo "Description:"
	echo "   Helper utility to collect a database backup of PostgreSQL."
	echo "   It will place the result with a timestamp in the backup"
	echo "   directory."
	echo "Example usage:"
	echo "   $ ./pgBackup.sh"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_namespace || die "Unable to get namespace" $?
NS=$REPLY

if [[ ! -f "$DB_PROPS" ]]; then
	echo "Unable to find enRoleDatabase.properties.  Is ISVG-IM installed?"
	exit 8
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


# Collect DB info
DBNAME=$(grep driverUrl "$DB_PROPS" | cut -d '/' -f 4 | cut -d '?' -f 1)

printf "Dumping database %s..." "${DBNAME}"
$kubectl -n "$NS" exec "$POD" -- pg_dump -f /tmp/pgbackup.sql -cC --if-exists "$DBNAME"
if [[ $? -ne 0 ]]; then
	printf "\n\n"
	echo "Failed to export the DB. Try it manually with:"
	echo "$kubectl -n $NS exec -it $POD -- bash"
	echo "pg_dump -f /tmp/pgbackup.sql -cC --if-exists $DNBAME"
	printf "sed -i 's/\(DROP DATABASE IF EXISTS .*\);$/\1 with (FORCE);/' /tmp/pgbackup.sql\n"
	exit 2
fi
$kubectl -n "$NS" exec "$POD" -- sed -i 's/\(DROP DATABASE IF EXISTS .*\);$/\1 with (FORCE);/' /tmp/pgbackup.sql
printf "Done!\nCompressing database output..."

$kubectl -n "$NS" exec "$POD" -- bash -c "cd /tmp; tar czf $BKUPFILE pgbackup.sql"
if [[ $? -ne 0 ]]; then
	printf "\n\n"
	echo "Failed to compress the backup. Try it manually with:"
	echo "$kubectl -n $NS exec -it $POD -- bash"
	echo "cd /tmp"
	echo "tar czf $BKUPFILE pgbackup.sql"
	exit 3
fi
printf "Done!\nDownloading backup..."

$kubectl -n "$NS" cp "$POD":"/tmp/$BKUPFILE" "../backup/$BKUPFILE" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
	printf "\n\n"
	echo "Failed to download the backup. Try it manually with:"
	echo "$kubectl -n $NS cp $POD:/tmp/$BKUPFILE ../../backup/$BKUPFILE"
	exit 4
fi
printf "Done!\nRemoving backup from pod..."

$kubectl -n "$NS" exec "$POD" -- bash -c 'rm /tmp/pgbackup*.*'
if [[ $? -ne 0 ]]; then
	printf "\n\n"
	echo "Failed to remove the backup from pod. Try it manually with:"
	echo "$kubectl -n $NS exec -it $POD -- bash"
	echo "cd /tmp"
	echo 'rm pgbackup*.*'
	exit 4
fi
printf "Done!\n\n"
echo "Saved PostgreSQL backup to <starter_dir>/backup/$BKUPFILE"
