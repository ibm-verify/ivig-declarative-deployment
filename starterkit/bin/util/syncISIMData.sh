#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: syncISIMData.sh"
	echo "When to run: On a regular basis to keep the Access Catalog up to date"
	echo "Description:"
	echo "   syncISIMData will update the Access Catalog for use in the Service Center."
	echo "Usage:"
	echo "  syncISIMData.sh [-syncOption value] [-dataType value]"
	echo "  -where:"
	echo "       -syncOption required. Value is 'Upgrade' or 'Maintenance'."
	echo "       -dataType   required. Value is 'ConfigData', 'AccessCatalog', or 'ALL'."
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

FILENAME="/opt/ibm/wlp/usr/servers/defaultServer/config/install_logs/syncISIMData.log"
POD=isvgim-0
$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /work/syncISIMData.sh "$@"
RC=$?

$kubectl -n "$NS" cp "${POD}":"$FILENAME" ../logs/syncISIMData.log > /dev/null
if [[ $? -ne 0 ]]; then
	echo "ERROR: Unable to copy logs from pod."
	exit 2
fi

exit "$RC"
