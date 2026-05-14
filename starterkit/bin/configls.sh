#!/bin/bash

if [[ "$1" = "--help" ]]; then
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

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config/data"

get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_pod_name "$NS" isvgim-0 && POD=$REPLY
if [[ -z "$POD" ]]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash -c "cd $IM_HOME; ls -lR $1"
if [[ $? -ne 0 ]]; then
	echo "Unable to exec into container."
	exit 19
fi

