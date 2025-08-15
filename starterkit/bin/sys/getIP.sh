#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: getIP.sh"
	echo "When to run: Never, called automatically by the installer"
	echo "Description:"
	echo "   Helper script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   It finds the IP address for the node in the kubernetes cluster."
	echo "Example usage:"
	echo "   $ ./getIP.sh"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

NS=$(./sys/getNamespace.sh)

kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi
NODE=$($kubectl -n $NS get pod isvgim-0 -o custom-columns=:.spec.nodeName --no-headers)
IP=$($kubectl get nodes -o wide --no-headers=true | grep $NODE | awk '{ print $6 }')
echo $IP
