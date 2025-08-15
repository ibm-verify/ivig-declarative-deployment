#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: configls.sh"
	echo "When to run: When updating configuration files in data directory"
	echo "Description:"
	echo "   Provides a directory listing of the ISVGIM_HOME/data directory inside the pod."
	echo "   This allows you to see which files are available to retrieve with getConfig.sh."
	echo "   You can optionally pass in a filter to limit the list of files returned."
	echo "Example usage:"
	echo "   $ ./configls.sh *.properties"
	echo ""
	exit 0
fi

cd $(dirname ${BASH_SOURCE[0]})
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config/data"
NS=$(./sys/getNamespace.sh)

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

$kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "cd $IM_HOME; ls -lR $1"
if [ $(echo $?) -ne 0 ]; then
	echo "Unable to exec into container."
	exit 19
fi

