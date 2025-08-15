#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: getConfig.sh"
	echo "When to run: When updating configuration files in data directory"
	echo "Description:"
	echo "   Helper script to retrieve configuration files from the ISVGIM pod."
	echo "   To persist changes, configuration files must be edited on the host and turned into a ConfigMap."
	echo "   After retrieving and editing the files, run createConfigs.sh and restart isvgim pods for changes to take effect."
	echo "   It takes one parameter - the name of the file to retrieve from the pod."
	echo "Example usage:"
	echo "   $ ./getConfig.sh enRoleMail.properties"
	echo ""
	exit 0
fi

cd $(dirname ${BASH_SOURCE[0]})
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config/data"
NS=$(./sys/getNamespace.sh)
NEWDIR=0

if [ "x$1" = "x" ]; then
	echo "Usage: $0 <properties file name>"
	echo "e.g. $0 enRoleMail.properties"
	echo "or $0 workflow_systemprocess/addpolicy.xml"
	exit 1
fi

kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

POD=$($kubectl -n $NS get pods | grep isvgim-0 | awk '{ print $1 }')
if [ "x$POD" = "x" ]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

$(grep -q "/" <<< "$1")
if [ $(echo $?) -eq 0 ]; then
	DIR=${1%/*}
	if [ ! -d ../data/$DIR ]; then
		mkdir -p ../data/$DIR
		NEWDIR=1
	fi
fi

RESULT=$($kubectl -n $NS cp ${POD}:${IM_HOME}/$1 ../data/$1)
if [ $(echo $?) -ne 0 ]; then
	echo "Unable to copy from container."
	echo "$RESULT"
	exit 9
fi

# Check if the file exists
ls ../data/$1 > /dev/null 2>&1
if [ $(echo $?) -eq 2 ]; then
	echo "Configuration file $1 not found."
	if [ $NEWDIR -eq 1 ]; then
		cd ../data
		rmdir -p $DIR
	fi
	exit 2
else
	echo "Retrieved file data/$1"
fi
