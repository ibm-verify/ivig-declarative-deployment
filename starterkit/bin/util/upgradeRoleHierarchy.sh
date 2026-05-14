#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: upgradeRoleHierarchy.sh"
	echo "When to run: Need to Upgrade Role Hierarchy data"
	echo "Description:"
	echo "   This tool upgrade all Role Hierarchy data to LDAP, existing role Hierarchy data" 
	echo "   present in database will not be deleted by this tool."
	echo "	 After upgrade All ascendent roles in the database will be added in the composition of descendent roles."
	echo "   Composition of Role will be stored in LDAP"
	echo "Usage:"
	echo "   $ ./upgradeRoleHierarchy"
	echo ""
	exit 0
fi

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"

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

get_pod_name "$NS" isvgim && POD=$REPLY
if [[ $POD = isvgim-* ]]; then
	$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /work/upgradeRoleHierarchy.sh "$@"
else
	$kubectl -n "$NS" exec "$POD" -- /bin/bash /work/upgradeRoleHierarchy.sh "$@"
fi

if [[ ! -d ../logs ]]; then
	mkdir -p ../logs
fi

$kubectl -n "$NS" cp "$POD":"${IM_HOME}/install_logs/upgradeRoleHierarchy.stdout" ../logs/upgradeRoleHierarchy.stdout > /dev/null


if [[ $? -ne 0 ]]; then
	exit 1
fi
