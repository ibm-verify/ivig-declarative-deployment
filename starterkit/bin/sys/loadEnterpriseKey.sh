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
	POD=$($kubectl -n $NS get pods | grep isvgim | head -n 1 | awk '{ print $1 }')
	$kubectl -n $NS exec $POD -- /bin/bash -c "/work/loadEnterpriseKey.sh $RISKKEY"
	if [ $(echo $?) -ne 0 ]; then
		echo "Failed to install the enterprise key.  See messages above"
		exit 48
	fi

} #install_key

# Start of main script
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

kubectl=$(./sys/preReqCheck.sh)
RC=($echo $?)
if [ $RC -ne 0 ]; then
	exit $RC
fi

NS=$(./sys/getNamespace.sh)
if [ $(echo $?) -ne 0 ]; then
	echo "Unable to determine namespace in use from values.yaml file"
	exit 7
fi

case $(awk -vs1="$1" 'BEGIN { print tolower(s1) }') in
	--help|-help)
		print_help
		;;
	*)
		install_key
		;;
esac
