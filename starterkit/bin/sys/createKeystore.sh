#!/bin/bash

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config/data"
IM_FILES="keystore/ encryptionKey.properties enRole.properties"
EXISTS=0

if [ "x$1" = "x--help" ]; then
	echo "Name: createKeystore.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   It will connect to the isvgimconfig pod and generate a new itimKeystore.jceks and encryptionKey.properties file,"
	echo "     provided one does not already exist.  It will not overwrite an existing ISVGIM keystore."
	echo "Example usage:"
	echo "   $ ./createKeystore.sh"
	echo ""
	exit 0
fi

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

if [ ! -d ../data ]; then
	mkdir ../data
else
	EXISTS=1
	for FILE in ../data/keystore/itimKeystore.jceks ../data/encryptionKey.properties ../data/enRole.properties; do
	if [ ! -f $FILE ]; then
		EXISTS=0
	fi
	done
fi

NS=$(./sys/getNamespace.sh)
if [ $(echo $?) -ne 0 ]; then
	if [ "x$1" = "x" ]; then
		echo "Unable to determine namespace in use from values.yaml file"
	fi
	exit 7
fi

POD=$($kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print $1 }')
if [ "x$POD" = "x" ]; then
	./sys/startConfigContainer.sh
	sleep 5
	POD=$($kubectl -n $NS get pods | grep isvgimconfig | awk '{ print $1 }')
fi

if [ $EXISTS -eq 1 ]; then
	echo "Keystore already exists!"
	for FILE in $IM_FILES; do
		$kubectl -n $NS cp ../data/$FILE $POD:${IM_HOME}/$FILE > /dev/null
		if [ $(echo $?) -ne 0 ]; then
			echo "kubectl was unable to create data/$FILE"
			exit 9
		fi
	done
else
	$kubectl -n $NS exec $POD -- /bin/bash -c "/work/createKeystore.sh"
	if [ $(echo $?) -ne 0 ]; then
		if [ "x$1" = "x" ]; then
			echo "Failed to create the keystore.  See messages above"
		fi
		exit 10
	fi
	for FILE in $IM_FILES; do
		$kubectl -n $NS cp $POD:${IM_HOME}/$FILE ../data/$FILE > /dev/null
		if [ $(echo $?) -ne 0 ]; then
			echo "kubectl was unable to create data/$FILE"
			exit 9
		fi
	done
fi

./createConfigs.sh keystore
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	if [ "x$1" = "x" ]; then
		echo "Errors creating ConfigMap for keystore"
	fi
	exit $RC
else
	if [ $OFFLINE -eq 1 ]; then
		echo "Please load yaml/010-config-isvgimks.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi
