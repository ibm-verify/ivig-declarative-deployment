#!/bin/bash

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"
DB_PROPS="../data/enRoleDatabase.properties"
DB_CONF="../data/dbConfig.properties"
IF_DATA="../.installedFixes"
SYSINSTALL=0

if [[ "$1" = "--help" ]]; then
	echo "Name: dbUpgrade.sh"
	echo "When to run: When upgrading to a new version of ISVG-IM."
	echo "Description:"
	echo "   Configuration script used to update the database schema."
	echo "Example usage:"
	echo "   $ ./dbUpgrade.sh"
	echo ""
	exit 0
fi

if [[ "$1" = "--installer" ]]; then
	SYSINSTALL=1
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_namespace || die "Unable to get namespace" $?
NS=$REPLY

if [[ ! -f "$DB_PROPS" ]]; then
	echo "Unable to find enRoleDatabase.properties.  Is ISVG-IM installed?"
	exit 8
fi

if [[ -f "$IF_DATA" ]]; then
	OLD_VERSION=$(cat ../.installedFixes | cut -f2 | grep -v F | tail -n 1)
else
	OLD_VERSION=10.0.2.0
fi

# Make sure application is stopped during the upgrade
get_pod_name "$NS" isvgim-0 0 && POD=$REPLY
if [[ -n "$POD" ]]; then
	echo "The ISVG-IM application is still running.  Please stop it before running dbUpgrade.sh"
	echo "e.g. kubectl -n $NS scale --replicas=0 statefulset isvgim"
	exit 1
fi

# Start the configuration pod
if [[ $SYSINSTALL -eq 0 ]]; then
	printf "\n##### Deploying configuration pod #####\n"
	./updateYaml.sh 201-deployment-isvgimconfig.yaml

	POD=""
	TIMER=0
	# Waiting for pod to be ready again
	while [[ -z "$POD" ]]; do
		sleep 5
		get_pod_name "$NS" isvgimconfig 0 && POD=$REPLY
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
fi

get_pod_name "$NS" isvgimconfig && POD=$REPLY
# Collect admin credentials for database
printf "\nCollecting DB Administrator credentials\n"
printf "Leave blank to use value from original install.\n\n"
read -r -p 'DB Admin: ' ADMUSER
read -r -sp 'DB Admin Password: ' ADMPASS
echo ""

if [[ -z "$ADMUSER" ]]; then
	ADMUSER=$(grep "database.db.admin=" "$DB_PROPS" | cut -d '=' -f 2)
fi
if [[ -z "$ADMPASS" ]]; then
	ADMPASS=$(grep database.db.adminPwd "$DB_PROPS" | cut -d '=' -f 2-)
	ADMPASS=$($kubectl -n "$NS" exec "$POD" -- /bin/bash -c "/work/encryptionHelper.sh decrypt $ADMPASS")
fi

echo "dbConfigResponse.database.db.admin=$ADMUSER" > "$DB_CONF"
echo "dbConfigResponse.database.db.adminPwd=$ADMPASS" >> "$DB_CONF"

TBLDATA=$(grep database.tablespace.location.data "$DB_PROPS" | cut -d '=' -f 2)
if [[ -n "$TBLDATA" ]]; then
	echo "dbConfigResponse.tablespace.location.data=$TBLDATA" >> "$DB_CONF"
	TBLINDX=$(grep database.tablespace.location.indexes "$DB_PROPS" | cut -d '=' -f 2)
	echo "dbConfigResponse.tablespace.location.indexes=$TBLINDX" >> "$DB_CONF"
fi

$kubectl -n "$NS" cp "$DB_CONF" "$POD":/work/dbConfig.properties
rm "$DB_CONF"

$kubectl -n "$NS" exec "$POD" -- /bin/bash -c "/work/dbConfig.sh upgrade $OLD_VERSION"
RESULT=$?

if [[ ! -d ../logs ]]; then
	mkdir ../logs
fi

$kubectl -n "$NS" cp "$POD":"${IM_HOME}/install_logs/dbUpgrade.stdout" ../logs/dbUpgrade.stdout > /dev/null

if [[ $RESULT -ne 0 ]]; then
	tail -n 25 ../logs/dbUpgrade.stdout
	echo "Failed to upgrade DB.  See messages above"
	if [[ $SYSINSTALL -eq 0 ]]; then
		$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
	fi
	exit 15
fi

if [[ $SYSINSTALL -eq 0 ]]; then
	printf "\n##### Removing configuration pod #####\n"
	$kubectl delete -f ../yaml/201-deployment-isvgimconfig.yaml
	if [[ $? -ne 0 ]]; then
		echo "Error removing ISVGIM config pod"
		exit 16
	fi
fi

