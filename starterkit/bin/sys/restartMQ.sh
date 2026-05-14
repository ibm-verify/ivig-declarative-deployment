#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: restartMQ.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Configuration script called automatically by the installer only once."
	echo "   It will restart the queue managers in MQ pods for first use to configure the queue managers."
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh
get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

queue_manager_name="$1"

if [[ "$queue_manager_name" = "ISVGQMgrShared" ]]; then
	container_name=$($kubectl get pods -n "$NS" -o name | grep "mqshare-" | head -n 1 | cut -d'/' -f2)

	$kubectl exec -it -n "$NS" "$container_name" -- bash -c "endmqm $queue_manager_name"
	sleep 5
	$kubectl exec -it -n "$NS" "$container_name" -- bash -c "strmqm $queue_manager_name"
elif [[ "$queue_manager_name" = "ISVGQueueMgr" ]]; then
	container_name="isvgim-0"
	container_command="mqlocal"

	$kubectl exec -it -n "$NS" "$container_name" -c "$container_command" -- bash -c "endmqm $queue_manager_name"
	sleep 5
	$kubectl exec -it -n "$NS" "$container_name" -c "$container_command" -- bash -c "strmqm $queue_manager_name"
fi
