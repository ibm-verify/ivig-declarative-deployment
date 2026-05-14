#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: restartConfigContainer.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   Restarts the config pod after setting up LDAP and/or DB."
	echo "Example usage:"
	echo "   $ ./resetConfigContainer.sh"
	echo ""
	exit 0
fi

CERTDIR="../config/certs"
CFGFILE="../config/config.yaml"
YMLDIR="../yaml"

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

get_sed_cmd && SED=$REPLY
get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi


grep -q isvgimRootCA.crt "$CFGFILE"
if [[ $? -ne 0 ]]; then
	if [[ -f "$CERTDIR/isvgimRootCA.crt" ]]; then
		LINE=$(grep -n truststore: "$CFGFILE" | cut -d ':' -f 1)
		LINE=$((LINE+1))
		$SED "${LINE}i \ \ - \"@isvgimRootCA.crt\"" "$CFGFILE"
	fi
fi

./createConfigs.sh setup
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors creating ConfigMap for setup"
	fi
	exit "$RC"
else
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Please load yaml/020-config-isvgimconfig.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

./createConfigs.sh
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors creating ConfigMap for data"
	fi
	exit "$RC"
else
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Please load yaml/015-config-isvgimdata.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

# The real work
$kubectl delete -f "${YMLDIR}/200-deployment-isvgimconfig.yaml"
sleep 5
./updateYaml.sh 201-deployment-isvgimconfig.yaml

POD=""
# Waiting for pod to be ready again
while [[ -z "$POD" ]]; do
	sleep 5
	get_pod_name "$NS" isvgimconfig && POD=$REPLY
done
./sys/waitFor.sh "$POD" application
RC=$?
if [[ $RC -ne 0 ]]; then
	exit "$RC"
fi
