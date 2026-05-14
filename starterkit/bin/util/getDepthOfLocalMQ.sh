#!/bin/bash

MQCFG="../getLocalQueueDepth.mqsc"
WAS_HOME="/logs"

if [[ "$1" = "--help" ]]; then
	echo "Name: getDepthOfLocalMQ.sh"
	echo "When to run: While deciding on whether to Scale Down the Pod or not"
	echo "Description:"
	echo "   We need to ensure that no processing is pending in POD before scaling it down."
	echo "   This script will provide you queue depth from Local MQ Container from each running POD."
	echo "   Which will help us in deciding whether to scale down that POD or not."
	echo "DepthOfLocalMQ usage:"
	echo "   $ ./getDepthOfLocalMQ.sh"
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

PODS=$($kubectl -n "$NS" get pods | grep isvgim | awk '{ print $1 }')
if [[ -z "$PODS" ]]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim | awk '{ print \$1 }'"
	exit 8
fi

cat <<EOF > "$MQCFG"
DISPLAY QUEUE('itim_ms')                CURDEPTH
DISPLAY QUEUE('itim_rs')                CURDEPTH
DISPLAY QUEUE('itim_wf')                CURDEPTH
DISPLAY QUEUE('itim_adhocSync')         CURDEPTH
DISPLAY QUEUE('itim_rs_pending')        CURDEPTH
DISPLAY QUEUE('itim_ps')                CURDEPTH
DISPLAY QUEUE('itim_import_export')     CURDEPTH
DISPLAY QUEUE('ivig_events')            CURDEPTH
DISPLAY QUEUE('DEV.DEAD.LETTER.QUEUE')  CURDEPTH
EOF

for POD in $PODS; do
	echo "$POD"
	RESULT=$($kubectl -n "$NS" cp "$MQCFG" "$POD":/tmp/getLocalQueueDepth.mqsc -c mqlocal)
	if [[ $? -ne 0 ]]; then
		echo "ERROR: Unable to upload script to the pod."
		echo "$RESULT"
		exit 1
	fi


	$kubectl -n "$NS" exec "$POD" -c mqlocal -- runmqsc -f /tmp/getLocalQueueDepth.mqsc | grep "CURDEPTH"
	if [[ $? -ne 0 ]]; then
		echo "ERROR: Unable to collect files in the pod."
	fi
done 

rm "$MQCFG"
