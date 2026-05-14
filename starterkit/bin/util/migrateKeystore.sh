#!/bin/bash

MKBACKUP="Invalid"
KSKEY="Invalid"
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"

if [[ "$1" = "--help" ]]; then
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
	printf "relative to %s.\n\n" "$PWD"
	read -r -p 'Location: ' KSFILE
} #collect_ksfile

collect_mkbackup() {
	printf "\nSpecify location of masterkey backup file.  Use an absolute path or one\n"
	printf "relative to %s. Leave blank if there is no masterkey.\n\n" "$PWD"
	read -r -p 'Location: ' MKBACKUP
} #collect_mkbackup

collect_encodedValue() {
	printf "\nSpecify value of enrole.encryption.password.encoded in\n"
	printf "enRole.properties from prior system.  true or false\n\n"
	read -r -p 'Value: ' ENCODED
} #collect_encodedValue

collect_key() {
	printf "\nSpecify location of encryptionKey.properties.  Use an absolute path or\n"
	printf "one relative to %s. Leave blank if there is no\n" "$PWD"
	printf "encryptionKey.properties and you know the keystore password.\n\n"
	read -r -p 'Location: ' KSKEY
} #collect_key

collect_mkpass() {
	printf "\nSpecify password of masterkey backup file.\n"
	read -r -sp 'Password: ' MKPASS
	echo ""
	read -r -sp 'Confirm Password: ' MKPSWD
	echo ""
} #collect_mkpass

collect_kspass() {
	printf "\nSpecify password of keystore.\n"
	read -r -sp 'Password: ' KSPASS
	echo ""
	read -r -sp 'Confirm Password: ' KSPSWD
	echo ""
} #collect_kspass

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib.common.sh
PWD=$(pwd)

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

# Make sure application is stopped during the migration
get_pod_name "$NS" isvgim-0 && POD=$REPLY
if [[ -n "$POD" ]]; then
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
while [[ -z "$POD" ]]; do
	sleep 5
	get_pod_name "$NS" isvgimconfig && POD=$REPLY

	if [[ $TIMER -gt 60 ]]; then
		$kubectl -n "$NS" describe deployment isvgimconfig
		echo "Failed to schedule the ISVGIM Config pod after 5 minutes.  Aborting!"
		echo "Run \"$kubectl -n $NS describe rs theReplicaSetListedAbove\" for details."
		exit 8
	fi
	TIMER=$((TIMER+1))
done

./sys/waitFor.sh "$POD" pod
RC=$?
if [[ $RC -ne 0 ]]; then
	exit "$RC"
fi
./sys/waitFor.sh isvgimconfig application
RC=$?
if [[ $RC -ne 0 ]]; then
	exit "$RC"
fi

# Collect the path to the keystore itimKeystore.jceks
while [[ -z "$KSFILE" ]]; do
	collect_ksfile
	if [[ ! -f $KSFILE ]]; then
		printf "\nUnable to read file %s.\n\n" "$KSFILE"
		KSFILE=""
	fi
done

# Collect the path to encryptionKey.properties
while [[ "$KSKEY" = "Invalid" ]]; do
	collect_key
	if [[ ! -f $KSKEY ]] && [[ -n "$KSKEY" ]]; then
		printf "\nUnable to read file %s.\n\n" "$KSKEY"
		KSKEY="Invalid"
	fi
done

# If no encryptionKey.properties was entered, ask for keystore password
if [[ -z "$KSKEY" ]]; then
	while [[ -z "$KSPASS" ]]; do
		collect_kspass
		if [[ "$KSPASS" != "$KSPSWD" ]]; then
			printf "\nPasswords don't match.\n\n"
			KSPASS=""
		fi
	done
	# Set default value to match kubernetes default
	ENCODED=true
else
# Otherwise ask if the password is encoded or not
	while [[ -z "$ENCODED" ]]; do
		collect_encodedValue
		if [[ "$ENCODED" != "true" ]] && [[ "$ENCODED" != "false" ]]; then
			printf "\nMust specify true or false.\n\n"
			ENCODED=""
		fi
	done
fi

# Collect path to masterkey backup file
while [[ "$MKBACKUP" = "Invalid" ]]; do
	collect_mkbackup
	if [[ ! -f $MKBACKUP ]] && [[ -n "$MKBACKUP" ]]; then
		printf "\nUnable to read file %s.\n\n" "$MKBACKUP"
		MKBACKUP="Invalid"
	fi
done

# If masterkey backup exists, ask for the password
if [[ -n "$MKBACKUP" ]]; then
	while [[ -z "$MKPASS" ]]; do
		collect_mkpass
		if [[ "$MKPASS" != "$MKPSWD" ]]; then
			printf "\nPasswords don't match.\n\n"
			MKPASS=""
		fi
	done
fi
echo ""

# Upload the keystore no matter what
$kubectl -n "$NS" cp "$KSFILE" "$POD":/work/itimKeystore.jceks

# If user supplied keystore password, verify it can open the keystore
if [[ -n "$KSPASS" ]]; then
	$kubectl -n "$NS" exec "$POD" -- /bin/bash -c "/work/migrateKeystore.sh check $KSPASS"
	if [[ $? -ne 0 ]]; then
		exit 3
	fi 
fi

if [[ -n "$KSKEY" ]] && [[ "$KSKEY" != "Invalid" ]]; then
	$kubectl -n "$NS" cp "$KSKEY" "$POD":/work/encryptionKey.properties
fi
if [[ -n "$MKBACKUP" ]]; then
	$kubectl -n "$NS" cp "$MKBACKUP" "$POD":/work/mkbackup
	$kubectl -n "$NS" exec "$POD" -- /bin/bash -c "echo $MKPASS > /work/mkpass"
fi

$kubectl -n "$NS" exec "$POD" -- /bin/bash -c "/work/migrateKeystore.sh migrate $ENCODED"
RESULT=$?

if [[ ! -d ../logs ]]; then
	mkdir -p ../logs
fi

$kubectl -n "$NS" cp "$POD":"${IM_HOME}/install_logs/migrateKeystore.stdout" ../logs/migrateKeystore.stdout > /dev/null

if [[ $RESULT -ne 0 ]]; then
	tail -n 25 ../logs/migrateKeystore.stdout
	echo "Failed to migrate keystore.  See messages above"
	$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
	exit 15
fi

# Remove old master keystore
for FILE in ../data/keystore/kek*; do
	rm -rf "$FILE"
done

# Download the new properties files
FILES="keystore encryptionKey.properties enRole.properties enRoleLDAPConnection.properties enRoleDatabase.properties"
for FILE in $FILES; do
	$kubectl -n "$NS" cp "$POD":"${IM_HOME}/data/$FILE" "../data/$FILE" > /dev/null 2>&1
done

./createConfigs.sh keystore
./createConfigs.sh

printf "\n##### Removing configuration pod #####\n"
$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
if [[ $? -ne 0 ]]; then
	echo "Error removing ISVGIM config pod"
	exit 16
fi

