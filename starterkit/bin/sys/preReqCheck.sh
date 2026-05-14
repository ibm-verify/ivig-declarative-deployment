#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: preReqCheck.sh"
	echo "When to run: Never, called automatically by other scripts."
	echo "Description:"
	echo "   Wrapper for checking helm and kubectl exist.  It never needs to be run by the user."
	echo "Example usage:"
	echo "   $ ./preReqCheck.sh"
	echo ""
	exit 0
fi

KCTL="oc kubectl minikube"
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi


#Check for helm
helm version > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
	echo "Helm not found in PATH.  Please include it in PATH or"
	echo "download it from: https://github.com/helm/helm/releases"
	exit 3
fi

# Check for kubectl variants
for CMD in $KCTL; do
	RESULT=$($CMD version 2>&1)
	RC=$?
	if [[ $RC -eq 0 ]]; then
		if [[ "$CMD" = "minikube" ]]; then
			echo "minikube kubectl --"
		else
			echo "$CMD"
		fi
		exit 0
	elif [[ $RC -eq 1 ]]; then
		echo "$RESULT"
		exit 1
	fi
done

if [[ $RC -eq 127 ]]; then
	echo "kubectl not found in PATH.  Please include it in PATH or install it"
	echo "from: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
fi
exit 2
