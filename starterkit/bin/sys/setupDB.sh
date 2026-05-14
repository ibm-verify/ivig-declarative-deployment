#!/bin/bash

CONF="../config/config.yaml"
CERTDIR="../config/certs"
TBSCRIPT="../config/db/tbscript.sh"
PGCREDS="065-secret-pgcreds"
YMLDIR="../yaml"
EXT1="key crt csr"
EXT2="key crt srl"

if [[ "$1" = "--help" ]]; then
        echo "Name: setupDB.sh"
        echo "When to run: Never, called automatically by the installer."
        echo "Description:"
        echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
        echo "   It will setup the Postgres pod."
        echo "Example usage:"
        echo "   $ ./setupDB.sh"
        echo ""
        exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

get_pod_name "$NS" isvgimconfig && POD=$REPLY
if [[ -z "$POD" ]]; then
	./sys/startConfigContainer.sh
	sleep 5
	POD=$($kubectl -n "$NS" get pods | grep isvgimconfig | awk '{ print $1 }')
fi

# Make sure yaml dir exists
if [[ ! -d $YMLDIR ]]; then
	mkdir "$YMLDIR"
fi

# Setup SSL
get_pod_name "$NS" isvgimconfig && POD=$REPLY
if [[ -f $CERTDIR/isvgimRootCA.key ]]; then
	for EXT in $EXT2; do
		$kubectl -n "$NS" cp "$CERTDIR/isvgimRootCA.$EXT" "$POD":"/work/isvgimRootCA.$EXT"
	done
fi
$kubectl -n "$NS" exec "$POD" -- /work/certificateUtil.sh db
if [[ $? -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Unable to create certificates in config pod"
	fi
	exit 24
fi

for FILE in pgsql isvgimRootCA; do
	if [[ $FILE = isvgimRootCA ]]; then
		EXTS=$EXT2
	else
		EXTS=$EXT1
	fi
	for EXT in $EXTS; do
		$kubectl -n "$NS" cp "$POD":"/work/${FILE}.${EXT}" "${CERTDIR}/${FILE}.${EXT}" > /dev/null 2>&1
	done
done

# Generate configmap for certs
./createConfigs.sh db
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Error creating ConfigMap files.  Please review above messages for details"
	fi
	exit "$RC"
fi

# Verify user and password are filled out
PGUSER=$(grep "  user:" "$CONF" | awk '{ print $2 }')
if [[ -z "$PGUSER" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must specify a user for DB in config.yaml"
	fi
	exit 19
fi

# Add Quotes to username to preserve the case if it exists.
PGUSER=\"$PGUSER\"

PGPASS=$(grep "  password:" "$CONF" | awk '{ print $2 }')
if [[ -z "$PGPASS" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must specify a password for DB in config.yaml"
	fi
	exit 21
fi

# Turn credentials into a secret
if [[ $OFFLINE -eq 0 ]]; then
	$kubectl create secret generic pgcreds --from-literal=pguser="$PGUSER" --from-literal=pgpass="$PGPASS" --from-literal=admpass="$ADMPASS" --from-literal=admuser="$ADMUSER" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "../helm/templates/${PGCREDS}.yaml"
	if [[ $? -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Error creating pgcreds secret"
		fi
		exit 22
	fi
	./updateYaml.sh "${PGCREDS}.yaml"
else
	echo "Please create your pgcreds secret for your DB server"
	echo "An example command is: $kubectl -n $NS create secret generic pgcreds --from-literal=pguser=$PGUSER --from-literal=pgpass=pguser_pwd --from-literal=admpass=admin_pwd --from-literal=admuser=$ADMUSER"
	read -n 1 -s -r -p "Once loaded, press any key to continue..."
	printf "\n\n"
fi

# Create tablespace dir script
cat <<EOF > "$TBSCRIPT"
cd /var/lib/postgresql/data
mkdir isvgimdata
mkdir isvgimindexes
EOF

deploy_single() {
	YMLFILES="040-config-isvgimdb 080-pvc-postgres 130-service-postgres 220-deployment-postgres"
	for FILE in $YMLFILES; do
		./updateYaml.sh "${FILE}.yaml"
	done

	if [[ $OFFLINE -eq 0 ]]; then
		# Waiting for pod to be created
		sleep 5
		POD=$($kubectl -n "$NS" get pods | grep postgres | awk '{ print $1 }')
		./sys/waitFor.sh "$POD" pod
		RC=$?
		if [[ $RC -ne 0 ]]; then
			exit "$RC"
		fi

		# Waiting for replica-1 pod to be ready
		./sys/waitFor.sh "$POD" application
		RC=$?
		if [[ $RC -ne 0 ]]; then
			exit "$RC"
		fi
	else
		echo "Please load the following files to deploy postgres:"
		for FILE in $YMLFILES; do
			echo "yaml/${FILE}.yaml"
		done
		printf "\n"
		read -n 1 -s -r -p "Once postgres is Ready, press any key to continue..."
		printf "\n\n"
		POD=$($kubectl -n "$NS" get pods | grep postgres | awk '{ print $1 }')
	fi
	create_tablespace_dirs "$POD"
} # deploy_single

deploy_cluster() {
	YMLFILES="040-config-isvgimdb 405-operator-kubegres 410-crd-postgres"
	for FILE in $YMLFILES; do
		./updateYaml.sh "${FILE}.yaml"
	done

	if [[ $OFFLINE -eq 0 ]]; then
		# Waiting for pod to be created
		sleep 5
		./sys/waitFor.sh postgres-3-0 pod
		RC=$?
		if [[ $RC -ne 0 ]]; then
			exit "$RC"
		fi

		# Waiting for replica pods to be ready
		./sys/waitFor.sh postgres-3-0 application
		RC=$?
		if [[ $RC -ne 0 ]]; then
			exit "$RC"
		fi
	else
		echo "Please load the following files to deploy postgres HA:"
		for FILE in $YMLFILES; do
			echo "yaml/${FILE}.yaml"
		done
		printf "\n"
		read -n 1 -s -r -p "Once postgres-1-0, -2-0, and -3-0 are Ready, press any key to continue..."
		printf "\n\n"
	fi

	# Create ISVGIM tablespace directories
	PGPODS="postgres-1-0 postgres-2-0 postgres-3-0"
	for POD in $PGPODS; do
		create_tablespace_dirs "$POD"
	done
} # deploy_cluster

create_tablespace_dirs() {
	RESULT=$($kubectl -n "$NS" cp "$TBSCRIPT" "${1}":/tmp/tbscript.sh 2>&1)
	RC=$?
	if [[ $RC -ne 0 ]]; then
		echo "$RESULT"
		exit 43
	fi
	RESULT=$($kubectl -n "$NS" exec "$1" -- /bin/bash /tmp/tbscript.sh 2>&1)
	RC=$?
	if [[ $RC -ne 0 ]]; then
		echo "$RESULT"
		exit 44
	fi
} # create_tablespace_dirs

printf "\n  -- Deploying Postgres --\n"
if [[ $INSTALL_DB_HA -eq 0 ]]; then
	deploy_single
else
	deploy_cluster
fi
rm "$TBSCRIPT"
