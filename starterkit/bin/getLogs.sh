#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: getLogs.sh"
	echo "When to run: While troubleshooting"
	echo "Description:"
	echo "   Helper script to retrieve the IM and Liberty logs from the pod."
	echo "   It will create a datestamped tar/gzip file in the logs directory."
	echo "Example usage:"
	echo "   $ ./getLogs.sh"
	echo ""
	exit 0
fi

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh
get_namespace || die "Unable to get namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

PODS=$($kubectl -n "$NS" get pods | grep isvgim | awk '{ print $1 }')
if [[ -z "$PODS" ]]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim | awk '{ print \$1 }'"
	exit 8
fi

if [[ ! -d ../logs ]]; then
	mkdir -p ../logs
fi

for POD in $PODS; do
	FILE=$(date +"%Y%m%d_%H%M%S")
	$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash -c "mkdir /tmp/logs;cp -r /logs/* /tmp/logs;cd /tmp;tar zcf /tmp/${POD}-${FILE}.tgz logs/*" > /dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		echo "Unable to create tar file in pod."
		exit 21
	fi
	$kubectl -n "$NS" cp "${POD}":"/tmp/${POD}-${FILE}.tgz" "../logs/${POD}-${FILE}.tgz" > /dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		echo "Unable to copy logs from pod."
		exit 22
	fi
	echo "Created logs/${POD}-${FILE}.tgz"
	$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash -c "rm /tmp/${POD}-${FILE}.tgz;rm -rf /tmp/logs"
	if [[ $? -ne 0 ]]; then
		echo "Unable to remove tar file in pod ${POD}."
		exit 23
	fi
done
