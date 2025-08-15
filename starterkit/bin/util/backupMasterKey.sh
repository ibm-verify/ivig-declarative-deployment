#!/bin/bash

if [ "x$1" = "x--help" ]; then
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
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xutil" ]; then
	cd $CDIR/..
fi

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config/data"
NS=$(./sys/getNamespace.sh)
NEWDIR=0

if [ "x$1" = "x" ]; then
	echo "Usage: $0 <password>"
	exit 1
fi

kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

POD=$($kubectl -n $NS get pods | grep isvgim-0 | awk '{ print $1 }')
if [ "x$POD" = "x" ]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

$kubectl -n $NS -c isvgim exec $POD -- /bin/bash -c "/work/backupRestoreMasterkey.sh backupMasterKey $1"
if [ $(echo $?) -ne 0 ]; then
    if [ "x$1" = "x" ]; then
        echo "Failed to backup the master key."
    fi
    exit 10
fi

$kubectl -n $NS -c isvgim cp "${POD}:$IM_HOME/masterkeyBackup" ../data/masterkey > /dev/null 2>&1
if [ $(echo $?) -ne 0 ]; then
    echo "Unable to copy masterkey from pod."
    exit 21
fi

masterkey=$(cat ../data/masterkey | tail -n 1 -) 
echo $masterkey > ../data/masterkey
