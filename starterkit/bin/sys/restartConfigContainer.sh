#!/bin/bash

if [ "x$1" = "x--help" ]; then
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

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

SED=$(./sys/sedCheck.sh)
kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

NS=$(./sys/getNamespace.sh)
if [ $(echo $?) -ne 0 ]; then
	if [ "x$1" = "x" ]; then
		echo "Unable to determine namespace in use from values.yaml file"
	fi
	exit 7
fi

grep -q isvgimRootCA.crt $CFGFILE
if [ $(echo $?) -ne 0 ]; then
	if [ -f $CERTDIR/isvgimRootCA.crt ]; then
		LINE=$(grep -n truststore: $CFGFILE | cut -d ':' -f 1)
		LINE=$(($LINE+1))
		$SED "${LINE}i \ \ - \"@isvgimRootCA.crt\"" $CFGFILE
	fi
fi

./createConfigs.sh setup
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	if [ "x$1" = "x" ]; then
		echo "Errors creating ConfigMap for setup"
	fi
	exit $RC
else
	if [ $OFFLINE -eq 1 ]; then
		echo "Please load yaml/020-config-isvgimconfig.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

# The real work
$kubectl -n $NS scale --replicas=0 deployment isvgimconfig > /dev/null
sleep 5
$kubectl -n $NS scale --replicas=1 deployment isvgimconfig > /dev/null

POD=""
# Waiting for pod to be ready again
while [ "x$POD" = "x" ]; do
	sleep 5
	POD=$($kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print $1 }')
done
./sys/waitFor.sh $POD application
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	exit $RC
fi
