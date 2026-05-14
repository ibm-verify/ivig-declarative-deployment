#!/bin/bash


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

POD=isvgim-0
$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /work/IGIMigration/bin/migration.sh "$@"
if [[ $? -ne 0 ]]; then
	exit 1
fi
