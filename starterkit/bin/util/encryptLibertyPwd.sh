#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: encryptLibertyPwd.sh"
	echo "When to run: When specifying a password used by the Liberty server"
	echo "Description:"
	echo "   encryptLibertyPwd will take a plain text password and return an AES"
	echo "   encrypted string."
	echo "Usage:"
	echo "  encryptLibertyPwd.sh thePassword"
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

POD=isvgim-0
$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /opt/ibm/wlp/bin/securityUtility encode --encoding=aes "$@"
exit $?
