#!/bin/bash

if [[ "$1" = "--help" ]]; then
        echo "Name: ldapConfig.sh"
        echo "When to run: Never, called automatically by the installer."
        echo "Description:"
        echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
        echo "   It will initialize the IVIG LDAP server for first use."
        echo "   The config/ldapConfig.properties must be filled in before calling this script."
        echo "Example usage:"
        echo "   $ ./ldapConfig.sh"
        echo ""
        exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

if [[ -f ../data/enRoleLDAPConnection.properties ]]; then
	echo "LDAP already configured!"
	exit
fi

IM_FILES="enRoleLDAPConnection.properties enRole.properties"
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"

get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_pod_name "$NS" isvgimconfig && POD=$REPLY
if [[ -z "$POD" ]]; then
	if [[ -z "$1" ]]; then
		echo "Unable to find name of ISVGIM Config pod using grep and awk"
	fi
	echo "Try manually running: $kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print \$1 }'"
	exit 8
fi

$kubectl -n "$NS" exec "$POD" -- /bin/bash -c "/work/ldapConfig.sh install"
RESULT=$?

if [[ ! -d ../logs ]]; then
	mkdir ../logs
fi

$kubectl -n "$NS" cp "$POD":"${IM_HOME}/install_logs/ldapConfig.stdout" ../logs/ldapConfig.stdout > /dev/null

if [[ $RESULT -ne 0 ]]; then
	tail -n 25 ../logs/ldapConfig.stdout
	if [[ -z "$1" ]]; then
		echo "Failed to configure LDAP.  See messages above"
	fi
	exit 13
fi

for FILE in $IM_FILES; do
	$kubectl -n "$NS" cp "$POD":"${IM_HOME}/data/$FILE" "../data/$FILE" > /dev/null
	if [[ $? -ne 0 ]]; then
		echo "kubectl was unable to create data/$FILE"
		exit 9
	fi
done

./createConfigs.sh
RC=$?
if [[ "$RC" -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors creating ConfigMap for properties files"
	fi
	exit "$RC"
else
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Please load yaml/015-config-isvgimdata.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi
