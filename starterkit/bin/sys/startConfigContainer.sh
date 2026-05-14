#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: startConfigContainer.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Helper script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   It will create the isvgimconfig pod for use during installation."
	echo "Example usage:"
	echo "   $ ./startConfigContainer.sh"
	echo ""
	exit 0
fi

VALFILE="../helm/values.yaml"
JFROGSVR=docker-na-public.artifactory.swg-devops.com
CERTDIR=../config/certs
CONF="../config/config.yaml"
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

YMLS="020-config-isvgimconfig 200-deployment-isvgimconfig"
kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_sed_cmd && SED=$REPLY
get_namespace || die "Unable to get namespace" $?
NS=$REPLY

if [[ ! -d ../yaml ]]; then
	mkdir ../yaml
fi

# Used to make sure the correct security.protocol line in config.yaml is updated
find_ssl_line() {
	DBLINE=$(grep -n "db:" "$CONF" | cut -d ':' -f 1)
	LDAPLINE=$(grep -n "ldap:" "$CONF" | cut -d ':' -f 1)
	LINEA=$(grep -n "security.protocol" "$CONF" | head -n 1 | cut -d ':' -f 1)
	LINEB=$(grep -n "security.protocol" "$CONF" | tail -n 1 | cut -d ':' -f 1)
	if [[ $DBLINE -gt $LDAPLINE ]]; then
		if [[ "$1" = "ldap" ]]; then
			LINE=$LINEA
		else
			LINE=$LINEB
		fi
	else
		if [[ "$1" = "ldap" ]]; then
			LINE=$LINEB
		else
			LINE=$LINEA
		fi
	fi
} #find_ssl_line

# Update config.yaml with preconfigured settings for LDAP
if [[ $INSTALL_LDAP -eq 1 ]]; then
	find_ssl_line ldap
	$SED "${LINE}s/\(security.protocol:\).*\$/\1 ssl/" "$CONF"
	if [[ $INSTALL_LDAP_HA -eq 1 ]]; then
		PORT=$(grep ldapsproxy "$VALFILE" | awk '{ print $2 }')
		$SED "s/\(ldapserver.ip:\).*\$/\1 isvd-cluster/" "$CONF"
		$SED "s/\(ldapserver.port:\).*\$/\1 $PORT/" "$CONF"
		$SED "s/\(security.principal:\).*\$/\1 cn=manager,cn=ibmpolicies/" "$CONF"
	else
		PORT=$(grep "ldaps:" "$VALFILE" | awk '{ print $2 }')
		$SED "s/\(ldapserver.ip:\).*\$/\1 isvd-replica-1/" "$CONF"
		$SED "s/\(ldapserver.port:\).*\$/\1 $PORT/" "$CONF"
	fi
	# Handle configurable suffix name
	ROOT_SUFFIX=$(grep ldapserver.root "$CONF" | awk '{ print $2 }')
	if [[ -n "$ROOT_SUFFIX" ]]; then
		$SED "s/\(\ \ \ \ rootSuffix:\).*$/\1 $ROOT_SUFFIX/" "$VALFILE"
	else
		DEF_ROOT_SUFFIX=$(grep "rootSuffix:" "$VALFILE" | awk '{ print $2 }')
		$SED "s/\(\ \ ldapserver.root:\).*\$/\1 $DEF_ROOT_SUFFIX/" "$CONF"
	fi
fi

# Update config.yaml with preconfigured settings for DB
if [[ $INSTALL_DB -eq 1 ]]; then

	# Verify user and password are filled out
	PGUSER=$(grep "user:" "$CONF" | awk '{ print $2 }')
	if [[ -z "$PGUSER" ]]; then
		if [[ -z "$1" ]]; then
			echo "You must specify a user for DB in config.yaml"
		fi
		exit 19
	fi

	PGPASS=$(grep "password:" "$CONF" | awk '{ print $2 }')
	if [[ -z "$PGPASS" ]]; then
		if [[ -z "$1" ]]; then
			echo "You must specify a password for DB in config.yaml"
		fi
		exit 21
	fi

	# Handle configurable database name
	DBNAME=$(grep "^  name:" "$CONF" | awk '{ print $2 }')
	if [[ -n "$DBNAME" ]]; then
		$SED "s/\(\ \ \ \ dbName:\).*$/\1 $DBNAME/" "$VALFILE"
	else
		DEF_DBNAME=$(grep "    dbName:" "$VALFILE" | awk '{ print $2 }')
		$SED "s/\(\ \ name:\).*\$/\1 $DEF_DBNAME/" "$CONF"
	fi

	PORT=$(grep "pg:" "$VALFILE" | awk '{ print $2 }')
	find_ssl_line db
	$SED "${LINE}s/\(security.protocol:\).*\$/\1 ssl/" "$CONF"
	$SED "s/\(^  dbtype:\).*\$/\1 postgres/" "$CONF"
	$SED "s/\(^  ip:\).*\$/\1 postgres/" "$CONF"
	$SED "s/\(^  port:\).*\$/\1 $PORT/" "$CONF"
	$SED "s/\(^  admin:\).*\$/\1 $ADMUSER/" "$CONF"
	$SED "s/\(^  adminPwd:\).*\$/\1 $ADMPASS/" "$CONF"
	$SED "s;\(tablespace.location.data:\).*\$;\1 /var/lib/postgresql/data/isvgimdata;" "$CONF"
	$SED "s;\(tablespace.location.indexes:\).*\$;\1 /var/lib/postgresql/data/isvgimindexes;" "$CONF"
fi

# Check if namespace exists.  If not, create it.
if [[ $kubectl = "oc" ]]; then
	$kubectl get projects -o name | grep -q -e "namespace/${NS}$"
else
	$kubectl get ns -o name | grep -q -e "namespace/${NS}$"
fi
if [[  $? -ne 0 ]]; then
	./updateYaml.sh 000-namespace.yaml
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Transformed namespace template into yaml/000-namespace.yaml"
		read -n 1 -s -r -p "Please load your namespace yaml, then press any key to continue..."
		printf "\n\n"
	fi
fi

# If custom repository is used, create the credentials
if [[ $CUSTOMREPO_LOGIN -eq 1 ]]; then
	if [[ $OFFLINE -eq 0 ]]; then
		$kubectl create secret docker-registry regcred --docker-server="$CUSTOMREPOURL" --docker-username="$CUSTOMREPOUSER" --docker-password="$CUSTOMREPOPWD" --docker-email="$CUSTOMREPOUSER" --namespace="$NS"
	else
		echo "Please create your regcred secret for your custom registry"
		echo "An example command is: $kubectl -n $NS create secret docker-registry regcred --docker-server=\"$CUSTOMREPOURL\" --docker-username=\"$CUSTOMREPOUSER\" --docker-password=your_password --docker-email=\"$CUSTOMREPOUSER\" --namespace=\"$NS\""
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

# If image is from artifactory, create the credentials
if [[ $JFROG_LOGIN -eq 1 ]]; then
	$kubectl create secret docker-registry regcred --docker-server="$JFROGSVR" --docker-username="$JFROGUSER" --docker-password="$JFROGPWD" --docker-email="$JFROGUSER" --namespace="$NS"
fi
if [[ -n "$JFROGBLD" ]]; then
	$SED "s;\(  isvgim:\) [a-zA-Z0-9]\+.*$;\1 ${JFROGSVR}/${JFROGBLD};" "$VALFILE"
fi

./createConfigs.sh setup
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors creating ConfigMap for setup"
	fi
	exit "$RC"
fi

for FILE in $YMLS; do
	./updateYaml.sh "${FILE}.yaml"
done

if [[ $OFFLINE -eq 0 ]]; then
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
else
		echo "Please load the yaml/020-config-isvgimconfig.yaml and yaml/200-deployment-isvgimconfig.yaml to start the configuration container"
		read -n 1 -s -r -p "Once isvgimconfig is Ready, press any key to continue..."
		printf "\n\n"
		get_pod_name "$NS" isvgimconfig && POD=$REPLY
fi

if [[ ! -d $CERTDIR ]]; then
	mkdir -p "$CERTDIR"
fi

#Creating certificates for mq and copying them to the starter for FIPS & SSL support
$kubectl -n "$NS" exec "$POD" -- /work/certificateUtil.sh mq
if [[ $? -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Unable to create mq certificates in config pod"
	fi
	exit 24
fi

$kubectl -n "$NS" cp "${POD}":/work/mq.crt "$CERTDIR/mq.crt" > /dev/null 2>&1
RC=$?
$kubectl -n "$NS" cp "${POD}":/work/mq.key "$CERTDIR/mq.key" > /dev/null 2>&1
RC=$((RC+$?))
$kubectl -n "$NS" cp "${POD}":/work/mq.csr "$CERTDIR/mq.csr" > /dev/null 2>&1
RC=$((RC+$?))
if [[ $RC -ne 0 ]]; then
	echo "kubectl failed to copy key & certificate for mq"
	exit 11
fi

# Retrieve auto CA cert if it exists
if [[ ! -f $CERTDIR/isvgimRootCA.key ]]; then
	get_pod_name "$NS" isvgimconfig && POD=$REPLY
	$kubectl -n "$NS" cp "${POD}":/work/isvgimRootCA.key "$CERTDIR/isvgimRootCA.key" > /dev/null 2>&1
	RC=$?
	$kubectl -n "$NS" cp "${POD}":/work/isvgimRootCA.crt "$CERTDIR/isvgimRootCA.crt" > /dev/null 2>&1
	RC=$((RC+$?))
	$kubectl -n "$NS" cp "${POD}":/work/isvgimRootCA.srl "$CERTDIR/isvgimRootCA.srl" > /dev/null 2>&1
	RC=$((RC+$?))
	if [[ $RC -ne 0 ]]; then
		echo "Failed to download root CA certificate from pod"
		exit 11
	fi
fi

