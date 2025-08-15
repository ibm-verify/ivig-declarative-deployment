#!/bin/bash

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"
LDAP_PROPS="../data/enRoleLDAPConnection.properties"
SYSINSTALL=0

if [ "x$1" = "x--help" ]; then
        echo "Name: ldapUpgrade.sh"
        echo "When to run: When upgrading to a new version of ISVG-IM."
        echo "Description:"
        echo "   Configuration script used to update the LDAP schema."
        echo "Example usage:"
        echo "   $ ./ldapUpgrade.sh"
        echo ""
        exit 0
fi

if [ "x$1" = "x--installer" ]; then
	SYSINSTALL=1
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xutil" ]; then
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
	echo "Unable to determine namespace from values.yaml file"
	exit 7
fi

if [ ! -f "$LDAP_PROPS" ]; then
	echo "Unable to find enRoleLDAPConnection.properties.  Is ISVG-IM installed?"
	exit 8
fi

# Make sure application is stopped during the upgrade
POD=$($kubectl -n $NS get pods | grep isvgim-0 | grep Running | awk '{ print $1 }')
if [ "x$POD" != "x" ]; then
	echo "The ISVG-IM application is still running.  Please stop it before running ldapUpgrade.sh"
	echo "e.g. kubectl -n $NS scale --replicas=0 statefulset isvgim"
	exit 1
fi

if [ $SYSINSTALL -eq 0 ]; then
	# Start the configuration pod
	printf "\n##### Deploying configuration pod #####\n"
	./updateYaml.sh 201-deployment-isvgimconfig.yaml

	POD=""
	TIMER=0
	# Waiting for pod to be scheduled
	while [ "x$POD" = "x" ]; do
		sleep 5
		POD=$($kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print $1 }')
		if [ $TIMER -gt 60 ]; then
			$kubectl -n $NS describe deployment isvgimconfig
			echo "Failed to schedule the ISVGIM Config pod after 5 minutes.  Aborting!"
			echo "Run \"$kubectl -n $NS describe rs theReplicaSetListedAbove\" for details."
			exit 8
		fi
		TIMER=$(($TIMER+1))
	done

	./sys/waitFor.sh $POD pod
	RC=$(echo $?)
	if [ $RC -ne 0 ]; then
		exit $RC
	fi
	./sys/waitFor.sh isvgimconfig application
	RC=$(echo $?)
	if [ $RC -ne 0 ]; then
		exit $RC
	fi
fi

POD=$($kubectl -n $NS get pods | grep isvgimconfig | grep Running | awk '{ print $1 }')
$kubectl -n $NS exec $POD -- /bin/bash -c "/work/ldapConfig.sh upgrade"
RESULT=$(echo $?)

if [ ! -d ../logs ]; then
	mkdir ../logs
fi

$kubectl -n $NS cp $POD:${IM_HOME}/install_logs/ldapUpgrade.stdout ../logs/ldapUpgrade.stdout > /dev/null

if [ $RESULT -ne 0 ]; then
	tail -n 25 ../logs/ldapConfig.stdout
	echo "Failed to upgrade LDAP.  See messages above"
	if [ $SYSINSTALL -eq 0 ]; then
		$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
	fi
	exit 13
fi

if [ $SYSINSTALL -eq 0 ]; then
	printf "\n##### Removing configuration pod #####\n"
	$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
	if [ $(echo $?) -ne 0 ]; then
		echo "Error removing ISVGIM config pod"
		exit 16
	fi
fi
