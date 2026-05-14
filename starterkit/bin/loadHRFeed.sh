#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: loadHRFeed.sh"
	echo "When to run: When loading in new HR data from a file"
	echo "Description:"
	echo "   Copies a DSML file into the ISVGIM pods for access by an HR Feed service."
	echo "Example usage:"
	echo "   $ ./loadHRFeed.sh myHRFeed.dsml"
	echo ""
	exit 0
fi

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh

if [[ -z "$1" ]]; then
	echo "Usage: $0 <HRFeed_file>"
	exit 1
fi
if [[ ! -f "$1" ]]; then
	echo "HR Feed file $1 not found."
	exit 2
fi

get_namespace || die "Unable to determine namespace" $?
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

PODFILE=$(basename "$1")
for POD in $PODS; do
	$kubectl -n "$NS" -c isvgim cp "$1" "${POD}:/tmp/$PODFILE" > /dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		echo "Unable to copy file into pod $POD."
		exit 21
	fi
	echo "Created /tmp/$PODFILE in $POD"
done
