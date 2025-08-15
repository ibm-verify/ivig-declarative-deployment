#!/bin/bash

MKBACKUP="Invalid"
KSKEY="Invalid"
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"

if [ "x$1" = "x--help" ]; then
	echo "Name: migrateKeystore.sh"
	echo "When to run: When migrating to the IVIG Kubernetes deployment."
	echo "Description:"
	echo "   Configuration script used to setup the existing keystore."
	echo ""
	echo "Example usage:"
	echo "   $ ./migrateKeystore.sh"
	echo ""
	exit 0
fi

collect_ksfile() {
	printf "\nSpecify location of itimKeystore.jceks file.  Use an absolute path or one\n"
	printf "relative to `pwd`.\n\n"
	read -p 'Location: ' KSFILE
} #collect_ksfile

collect_mkbackup() {
	printf "\nSpecify location of masterkey backup file.  Use an absolute path or one\n"
	printf "relative to `pwd`. Leave blank if there is no masterkey.\n\n"
	read -p 'Location: ' MKBACKUP
} #collect_mkbackup

collect_encodedValue() {
	printf "\nSpecify value of enrole.encryption.password.encoded in\n"
	printf "enRole.properties from prior system.  true or false\n\n"
	read -p 'Value: ' ENCODED
} #collect_encodedValue

collect_key() {
	printf "\nSpecify location of encryptionKey.properties.  Use an absolute path or\n"
	printf "one relative to `pwd`. Leave blank if there is no\n"
	printf "encryptionKey.properties and you know the keystore password.\n\n"
	read -p 'Location: ' KSKEY
} #collect_key

collect_mkpass() {
	printf "\nSpecify password of masterkey backup file.\n"
	read -sp 'Password: ' MKPASS
	echo ""
	read -sp 'Confirm Password: ' MKPSWD
	echo ""
} #collect_mkpass

collect_kspass() {
	printf "\nSpecify password of keystore.\n"
	read -sp 'Password: ' KSPASS
	echo ""
	read -sp 'Confirm Password: ' KSPSWD
	echo ""
} #collect_kspass

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

# Make sure application is stopped during the migration
POD=$($kubectl -n $NS get pods | grep isvgim-0 | grep Running | awk '{ print $1 }')
if [ "x$POD" != "x" ]; then
	echo "The ISVG-IM application is still running.  Please stop it before running migrateKeystore.sh"
	echo "e.g. kubectl -n $NS scale --replicas=0 statefulset isvgim"
	exit 1
fi

# Start the configuration pod
printf "\n##### Deploying configuration pod #####\n"
./updateYaml.sh 201-deployment-isvgimconfig.yaml

POD=""
TIMER=0
# Waiting for pod to be ready again
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

# Collect the path to the keystore itimKeystore.jceks
while [ "x$KSFILE" = "x" ]; do
	collect_ksfile
	if [ ! -f $KSFILE ]; then
		printf "\nUnable to read file $KSFILE.\n\n"
		KSFILE=""
	fi
done

# Collect the path to encryptionKey.properties
while [ "$KSKEY" = "Invalid" ]; do
	collect_key
	if [ ! -f $KSKEY ] && [ "x$KSKEY" != "x" ]; then
		printf "\nUnable to read file $KSKEY.\n\n"
		KSKEY="Invalid"
	fi
done

# If no encryptionKey.properties was entered, ask for keystore password
if [ "x$KSKEY" = "x" ]; then
	while [ "x$KSPASS" = "x" ]; do
		collect_kspass
		if [ "x$KSPASS" != "x$KSPSWD" ]; then
			printf "\nPasswords don't match.\n\n"
			KSPASS=""
		fi
	done
	# Set default value to match kubernetes default
	ENCODED=true
else
# Otherwise ask if the password is encoded or not
	while [ "x$ENCODED" = "x" ]; do
		collect_encodedValue
		if [ "x$ENCODED" != "xtrue" ] && [ "x$ENCODED" != "xfalse" ]; then
			printf "\nMust specify true or false.\n\n"
			ENCODED=""
		fi
	done
fi

# Collect path to masterkey backup file
while [ "$MKBACKUP" = "Invalid" ]; do
	collect_mkbackup
	if [ ! -f $MKBACKUP ] && [ "x$MKBACKUP" != "x" ]; then
		printf "\nUnable to read file $MKBACKUP.\n\n"
		MKBACKUP="Invalid"
	fi
done

# If masterkey backup exists, ask for the password
if [ "x$MKBACKUP" != "x" ]; then
	while [ "x$MKPASS" = "x" ]; do
		collect_mkpass
		if [ "x$MKPASS" != "x$MKPSWD" ]; then
			printf "\nPasswords don't match.\n\n"
			MKPASS=""
		fi
	done
fi
echo ""

# Upload the keystore no matter what
$kubectl -n $NS cp $KSFILE $POD:/work/itimKeystore.jceks

# If user supplied keystore password, verify it can open the keystore
if [ "x$KSPASS" != "x" ]; then
	$kubectl -n $NS exec $POD -- /bin/bash -c "/work/migrateKeystore.sh check $KSPASS"
	if [ $(echo $?) -ne 0 ]; then
		exit 3
	fi 
fi

if [ "x$KSKEY" != "x" ] && [ "$KSKEY" != "Invalid" ]; then
	$kubectl -n $NS cp $KSKEY $POD:/work/encryptionKey.properties
fi
if [ "x$MKBACKUP" != "x" ]; then
	$kubectl -n $NS cp $MKBACKUP $POD:/work/mkbackup
	$kubectl -n $NS exec $POD -- /bin/bash -c "echo $MKPASS > /work/mkpass"
fi

$kubectl -n $NS exec $POD -- /bin/bash -c "/work/migrateKeystore.sh migrate $ENCODED"
RESULT=$(echo $?)

if [ ! -d ../logs ]; then
	mkdir ../logs
fi

$kubectl -n $NS cp $POD:${IM_HOME}/install_logs/migrateKeystore.stdout ../logs/migrateKeystore.stdout > /dev/null

if [ $RESULT -ne 0 ]; then
	tail -n 25 ../logs/migrateKeystore.stdout
	echo "Failed to migrate keystore.  See messages above"
	$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
	exit 15
fi

# Remove old master keystore
if [ -d ../data/keystore/kek* ]; then 
    rm -rf ../data/keystore/kek*
fi

# Download the new properties files
FILES="keystore encryptionKey.properties enRole.properties enRoleLDAPConnection.properties enRoleDatabase.properties"
for FILE in $FILES; do
	$kubectl -n $NS cp $POD:${IM_HOME}/data/$FILE ../data/$FILE > /dev/null 2>&1
done

./createConfigs.sh keystore
./createConfigs.sh

printf "\n##### Removing configuration pod #####\n"
$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
if [ $(echo $?) -ne 0 ]; then
	echo "Error removing ISVGIM config pod"
	exit 16
fi

