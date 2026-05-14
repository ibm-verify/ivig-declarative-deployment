#!/bin/bash

if [[ "$1" = "--help" ]]; then
		echo "Name: waitFor.sh"
		echo "When to run: Never, called automatically by the installer."
		echo "Description:"
		echo "   Helper script called automatically by the installer.  It should never be called directly."
		echo "   It will wait for a pod or its application to start."
		echo "Parameters:"
		echo "   pod_name: the name of the pod to wait on"
		echo "   type: whether to wait for pod to start or application to be ready"
		echo "Example usage:"
		echo "   $ ./waitFor.sh isvgim-0 application"
		echo ""
		exit 0
fi

if [[ $# -ne 2 ]]; then
	echo "Invalid arguments!"
	echo "$0 <podName> <application|pod>"
	exit 44
fi

POD=$1
TYPE=$2
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

TIMEOUT=${TIMEOUT:-120}
PRINTDONE=0
TIMER=0

if [[ "$TYPE" = "pod" ]]; then
	# Waiting for pod to be created
	CMD=$($kubectl -n "$NS" get pods | grep "$POD" | grep Running)
	while [[ $? -ne 0 ]]; do
		if [[ $TIMER -eq 0 ]]; then
			printf "Waiting for pod %s to start" "$POD"
			PRINTDONE=1
		else
			printf "."
		fi
		sleep 5
		TIMER=$((TIMER+1))
		if [[ $TIMER -gt $TIMEOUT ]]; then
			printf "\nPod %s is taking a very long time to start\n" "$POD"
			$kubectl -n "$NS" describe pod "$POD"
			$kubectl -n "$NS" logs "$POD"
			exit 100
		else
			CMD=$($kubectl -n "$NS" get pods | grep "$POD" | grep -E "(Err|BackOff)")
			if [[ $? -eq 0 ]]; then
				printf "\nPod %s failed to start\n" "$POD"
				$kubectl -n "$NS" describe pod "$POD"
				$kubectl -n "$NS" logs "$POD"
				exit 100
			else
				CMD=$($kubectl -n "$NS" get pods | grep "$POD" | grep Running)
			fi
		fi
	done
fi


# Waiting for application to be ready
if [[ "$TYPE" = "application" ]]; then
	while [[ 0 -eq 0 ]]; do
		if [[ $TIMER -eq 0 ]]; then
			printf "Waiting for application to start"
			PRINTDONE=1
		else
			printf "."
		fi
		sleep 5
		TIMER=$((TIMER+1))
		PODS=$($kubectl -n "$NS" get pods | grep "$POD" | awk '{ print $2 }')
		for P in $PODS; do
			RUNNING=$(echo "$P" | tr '/' ' ' | awk '{ print $2-$1}')
			if [[ $RUNNING -eq 0 ]]; then
				break 2
			fi
			if [[ $TIMER -gt $TIMEOUT ]]; then
				BADPODS=$($kubectl -n "$NS" get pods | grep "$POD" | awk '{ print $1 }')
				printf "\nApplication is taking a very long time to start\n"
				for BP in $BADPODS; do
					$kubectl -n "$NS" describe pod "$BP"
					$kubectl -n "$NS" logs "$BP"
					exit 100
				done
			fi
		done
	done
fi

if [[ $PRINTDONE -eq 1 ]]; then
	printf "...Done!\n"
fi
