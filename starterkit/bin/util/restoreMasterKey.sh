#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: restoreMasterKey.sh"
	echo "When to run: When restoring a lost master key"
	echo "Description:"
	echo "   Helper script to restore the master key from the ISVGIM pod."
	echo "   It takes two parameter - 'masterKey_password' is same password that was used to back up the masterKey"
	echo "                            'masterKey' is the same encrypted string that was returned during the backup of masterKey."
	echo "Example usage:"
	echo "   $ ./restoreMasterKey.sh {masterKey_password} {masterKey}"
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

if [ $# -ne 2 ]; then
	echo "Usage: $0 <password> <masterkey>"
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

$kubectl -n $NS exec $POD -- /bin/bash -c "/work/backupRestoreMasterkey.sh restoreMasterKey $1 $2"
if [ $(echo $?) -ne 0 ]; then
	echo "Failed to restore the master key."
	exit 10
fi

# remove old master keystore
if [ -d ../data/keystore/kek* ]; then 
	rm -rf ../data/keystore/kek*
fi

./getConfig.sh keystore
./createConfigs.sh keystore
