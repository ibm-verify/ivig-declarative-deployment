#!/bin/bash

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"

if [ "x$1" = "x--help" ]; then
	echo "Name: dbConfig.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   It will initialize the IVIG database for first use."
	echo "Example usage:"
	echo "   $ ./dbConfig.sh"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

if [ -f ../data/enRoleDatabase.properties ]; then
	echo "DB already configured!"
	exit
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

$kubectl -n $NS exec $POD -- /bin/bash -c "/work/dbConfig.sh install"
RESULT=$(echo $?)

if [ ! -d ../logs ]; then
	mkdir ../logs
fi

$kubectl -n $NS cp $POD:${IM_HOME}/install_logs/dbConfig.stdout ../logs/dbConfig.stdout > /dev/null

if [ $RESULT -ne 0 ]; then
	tail -n 25 ../logs/dbConfig.stdout
	if [ "x$1" = "x" ]; then
		echo "Failed to configure DB.  See messages above"
	fi
	exit 15
fi

$kubectl -n $NS cp $POD:${IM_HOME}/data/enRoleDatabase.properties ../data/enRoleDatabase.properties > /dev/null
if [ $(echo $?) -ne 0 ]; then
	echo "kubectl was unable to create data/enRoleDatabase.properties"
	exit 9
fi

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

