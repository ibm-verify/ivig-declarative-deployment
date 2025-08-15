#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: externalRegistryConfig.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   It will configure IVIG to use an external registry for athentication."
	echo "Example usage:"
	echo "   $ ./externalRegistryConfig.sh"
	echo ""
	exit 0
fi

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"
IM_FILES="enRoleAuthentication.properties enRole.properties"

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

NS=$(./sys/getNamespace.sh)
if [ $(echo $?) -ne 0 ]; then
	if [ "x$1" = "x" ]; then
		echo "Unable to determine namespace from values.yaml file"
	fi
	exit 7
fi

POD=$($kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print $1 }')
if [ "x$POD" = "x" ]; then
	if [ "x$1" = "x" ]; then
		echo "Unable to find name of ISVGIM Config pod using grep and awk"
	fi
	echo "Try manually running: $kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print \$1 }'"
	exit 8
fi

$kubectl -n $NS exec $POD -- /bin/bash -c "/work/externalRegistryConfig.sh"
RESULT=$(echo $?)

for FILE in $IM_FILES; do
        $kubectl -n $NS cp $POD:${IM_HOME}/data/$FILE ../data/$FILE > /dev/null
        if [ $(echo $?) -ne 0 ]; then
                echo "kubectl was unable to create data/$FILE"
                exit 9
        fi
done
./createConfigs.sh
RC=$(echo $?)
if [ $RC -ne 0 ]; then
        if [ "x$1" = "x" ]; then
                echo "Errors creating ConfigMap for properties files"
        fi
        exit $RC
else
	if [ $OFFLINE -eq 1 ]; then
		echo "Please load yaml/015-config-isvgimdata.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi
