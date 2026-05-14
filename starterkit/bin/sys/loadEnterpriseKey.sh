#!/bin/bash

RISKKEY=$1

print_help() {
        echo "Name: loadEnterpriseKey.sh"
        echo "When to run: When upgrading to the Enterprise Analytics license."
        echo "Description:"
        echo "   Configuration script called automatically during install, and when manually adding Enterprise license."
        echo "   All pods must be restarted for the change to take effect."
	echo "Options:"
	echo "   <license_key> provide the Enterprise license key you received."
        echo "Example usage:"
        echo "   $ ./loadEnterpriseKey.sh <license_key>"
        echo ""
        exit 0
} #print_help

install_key() {
	get_pod_name "$NS" isvgim && POD=$REPLY
	$kubectl -n "$NS" exec "$POD" -- /bin/bash -c "/work/loadEnterpriseKey.sh $RISKKEY"
	if [[ $? -ne 0 ]]; then
		echo "Failed to install the enterprise key.  See messages above"
		exit 48
	fi

} #install_key

# Start of main script
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	exit "$RC"
fi

get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

case $(awk -vs1="$1" 'BEGIN { print tolower(s1) }') in
	--help|-help)
		print_help
		;;
	*)
		install_key
		;;
esac
