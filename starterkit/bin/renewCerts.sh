#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: renewCerts.sh"
	echo "When to run: Annually to update auto-generated SSL certificates."
	echo "Description:"
	echo "   Certificates will expire in just over one year.  This utility will renew them."
	echo "   The updated certificates will be added to the ConfigMap, but all pods"
	echo "   must be restarted for the change to take effect."
	echo "Options:"
	echo "   -check: Will report on the current expiration date for each certificate"
	echo "Example usage:"
	echo "   $ ./renewCerts.sh"
	echo "   $ ./renewCerts.sh -check"
	echo ""
	exit 0
fi

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh

CERTFILE="../config/certs.tgz"
CONTAINER="-c isvgim"
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
	get_pod_name "$NS" isvgimconfig && POD=$REPLY
	CONTAINER=""
fi
if [[ -z "$POD" ]]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

# Collect the certs and upload them to the pod
(cd ../config || exit 1; tar zcf certs.tgz certs)
$kubectl -n "$NS" $CONTAINER cp "$CERTFILE" "$POD":/work/certs.tgz
rm "$CERTFILE"
$kubectl -n "$NS" $CONTAINER exec "$POD" -- /work/renewCerts.sh "$1"
if [[ $? -ne 0 ]]; then
	echo "Unable to exec into pod."
	exit 19
fi

# Download the results and store them in ConfigMap
if [[ -z "$1" ]]; then
	$kubectl -n "$NS" $CONTAINER cp "$POD":/work/certs.tgz "$CERTFILE" > /dev/null 2>&1
	$kubectl -n "$NS" $CONTAINER exec "$POD" -- /bin/bash -c "rm /work/certs.tgz"
	(cd ../config || exit 1; tar zxf "$CERTFILE")
	rm "$CERTFILE"

	printf "Updating pem files..."
	cd ../config/certs || exit 1
	FILES=$(ls *.pem)
	for FILE in $FILES; do
		NAME=$(echo "$FILE" | cut -d '.' -f 1)
		cat "$NAME.crt" "$NAME.key" > "$NAME.pem"
	done
	printf "Done!\n"
	cd ../../bin || exit 1

	printf "Generating ConfigMaps..."
	for TYPE in setup ldap db isvdi mq; do
		./createConfigs.sh "$TYPE" > /dev/null
		RC=$?
		if [[ "$RC" -ne 0 ]]; then
			if [[ -z "$1" ]]; then
				echo "Errors creating ConfigMap for $TYPE"
			fi
			exit "$RC"
		fi
		printf "."
	done
	printf "Done!\n"
fi
