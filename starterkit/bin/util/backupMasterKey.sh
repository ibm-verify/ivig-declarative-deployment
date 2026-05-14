#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: backupMasterKey.sh"
	echo "When to run: After installation completes"
	echo "Description:"
	echo "   Helper script to backup the master key from the ISVGIM pod."
	echo "   It takes one parameter - The 'masterKey_password' is a password of user's choice."
    echo "   Ensure to save this password in a secure location as you must provide the same password to restore this masterKey"
	echo "Example usage:"
	echo "   $ ./backupMasterKey.sh {masterkey_password}"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config/data"
get_namespace || die "Unable to get namespace" $?
NS=$REPLY
NEWDIR=0

if [[ -z "$1" ]]; then
	echo "Usage: $0 <password>"
	exit 1
fi

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_pod_name "$NS" isvgim-0 && POD=$REPLY
if [[ -z "$POD" ]]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

$kubectl -n "$NS" -c isvgim exec "$POD" -- /bin/bash -c "/work/backupRestoreMasterkey.sh backupMasterKey $1"
if [[ $? -ne 0 ]]; then
    if [[ -z "$1" ]]; then
        echo "Failed to backup the master key."
    fi
    exit 10
fi

$kubectl -n "$NS" -c isvgim cp "${POD}:$IM_HOME/masterkeyBackup" ../data/masterkey > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "Unable to copy masterkey from pod."
    exit 21
fi

masterkey=$(tail -n 1 ../data/masterkey) 
echo "$masterkey" > ../data/masterkey
