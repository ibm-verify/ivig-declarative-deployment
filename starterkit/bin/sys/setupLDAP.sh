#!/bin/bash

YMLFILES="005-serviceaccount-isvd 025-config-isvgimldap 070-pvc-isvd 105-service-isvd 205-deployment-isvd"
REPLICAFILES="106-service-isvd2 206-deployment-isvd2"
PROXYFILES="072-pvc-isvd-proxy 110-service-proxy 210-deployment-proxy"
YMLDIR="../yaml"
CONF="../config/config.yaml"
LDAPCONF="../config/ldap/ldap_config.yaml"
PROXYCONF="../config/ldap/proxy_config.yaml"
SEEDCONF="../config/ldap/seed_config.yaml"
LDAPREPLCONF="../config/ldap/ldap2_config.yaml"
INSTALL_MARKER=../.ldapsetup
CERTDIR=../config/certs
EXT1="key crt csr"
EXT2="key crt srl"
USERLDIF="../config/ldap/ldif1"
GROUPLDIF="../config/ldap/ldif2"
SCHEMAREPL="../config/ldap/ldif3"
ISVDCRED="055-secret-isvdcred"

if [[ "$1" = "--help" ]]; then
        echo "Name: setupLDAP.sh"
        echo "When to run: Never, called automatically by the installer."
        echo "Description:"
        echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
        echo "   It will setup the Verify Directory pod."
        echo "Example usage:"
        echo "   $ ./setupLDAP.sh"
        echo ""
        exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

if [[ -f $INSTALL_MARKER ]]; then
	echo "LDAP already deployed!"
	exit
fi

# Used to create LDIF files for global admin account
create_ldif() {
	cat <<EOF > "$USERLDIF"
dn: cn=manager,cn=ibmpolicies
changetype: add
objectclass: inetOrgPerson
sn: manager
cn: manager
userpassword: $ADMINPWD

EOF
	cat <<EOF > "$GROUPLDIF"
dn: globalGroupName=GlobalAdminGroup,cn=ibmpolicies
changetype: modify
add: member
member: cn=manager,cn=ibmpolicies

EOF

	cat <<EOF > "$SCHEMAREPL"
dn: ibm-replicaServerId=isvd-replica-1,ibm-replicaGroup=default,cn=ibmpolicies
changetype: add
objectclass: top
objectclass: ibm-replicaSubentry
ibm-replicaServerId: isvd-replica-1
ibm-replicationServerIsMaster: true
cn: isvd-replica-1
description: server 1 (peer master) ibm-replicaSubentry 

dn: ibm-replicaServerId=isvd-replica-2,ibm-replicaGroup=default,cn=ibmpolicies
changetype: add
objectclass: top
objectclass: ibm-replicaSubentry
ibm-replicaServerId: isvd-replica-2
ibm-replicationServerIsMaster: true
cn: isvd-replica-2
description: server2 (peer master) ibm-replicaSubentry 

dn: cn=isvd-replica-2,ibm-replicaServerId=isvd-replica-1,ibm-replicaGroup=default,cn=ibmpolicies
changetype: add
objectclass: top
objectclass: ibm-replicationAgreement
cn: isvd-replica-2
ibm-replicaConsumerId: isvd-replica-2
ibm-replicaUrl: ldaps://isvd-replica-2:$PORT
ibm-replicaCredentialsDN: cn=replcred,cn=replication,cn=ibmpolicies
description: server1(master) to server2(master) agreement

dn: cn=isvd-replica-1,ibm-replicaServerId=isvd-replica-2,ibm-replicaGroup=default,cn=ibmpolicies
changetype: add
objectclass: top
objectclass: ibm-replicationAgreement
cn: isvd-replica-1
ibm-replicaConsumerId: isvd-replica-1
ibm-replicaUrl: ldaps://isvd-replica-1:$PORT
ibm-replicaCredentialsDN: cn=replcred,cn=replication,cn=ibmpolicies
description: server2(master) to server1(master) agreement

EOF
} #create_ldif

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_sed_cmd && SED=$REPLY
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
	mkdir -p "$YMLDIR"
fi

# Verify Tenant and Org are filled out
TENANT=$(grep defaulttenant.id "$CONF" | awk '{ print $2 }')
if [[ -z "$TENANT" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must specify a tenant id for LDAP in config.yaml"
	fi
	exit 27
fi

ORG=$(grep organization.name "$CONF" | awk '{ print $2 }')
if [[ -z "$ORG" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must specify an organization name for LDAP in config.yaml"
	fi
	exit 28
fi

# Pull admin dn and password from ldap section of config.yaml
ADMINPWD=$(grep security.credentials "$CONF" | awk '{ print $2 }')
if [[ -z "$ADMINPWD" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must specify a password for the LDAP admin in config.yaml"
	fi
	exit 26
fi
ADMINDN=$(grep security.principal "$CONF" | awk '{ print $2 }')
if [[ -z "$ADMINDN" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must specify a DN for the LDAP admin in config.yaml"
	fi
	exit 26
fi
# Make sure the local DN is not set to our global admin user
if [[ $INSTALL_LDAP_HA -eq 1 ]]; then
	grep -qi "ibmpolicies" <<< "$ADMINDN"
	if [[ $? -eq 0 ]]; then
		ADMINDN="cn=root"
	fi
fi

# Turn password into a secret
if [[ $OFFLINE -eq 0 ]]; then
	$kubectl create secret generic isvdcred --from-literal=adminpwd="$ADMINPWD" --from-literal=admindn="$ADMINDN" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "../helm/templates/${ISVDCRED}.yaml"
	if [[ $? -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Error creating isvdcred secret"
		fi
		exit 32
	fi
	./updateYaml.sh "${ISVDCRED}.yaml"
else
	echo "Please create your isvdcred secret for your LDAP server"
	echo "An example command is: $kubectl -n $NS create secret generic isvdcred --from-literal=adminpwd=your_password --from-literal=admindn=$ADMINDN"
	read -n 1 -s -r -p "Once loaded, press any key to continue..."
	printf "\n\n"
fi

# Pull ISVD license key from config.yaml
ISVDKEY=$(grep ldapKey "$CONF" | awk '{ print $2 }')
if [[ -z "$ISVDKEY" ]]; then
	if [[ -z "$1" ]]; then
		echo "You must supply a valid ISVD license key in config.yaml"
	fi
	exit 29
fi

# Set license key in ldap config.yamls if not already present
RESULT=$(grep "accept: limited" "$LDAPCONF")
RC=$?
if [[ $RC -ne 0 ]]; then
	for FILE in $LDAPCONF $PROXYCONF $SEEDCONF $LDAPREPLCONF; do
		LINENUM=$(grep -n "license:" "$FILE" | cut -d ':' -f 1)
		LINENUM=$((LINENUM+1))
		$SED "${LINENUM}i \ \ \ \ key: $ISVDKEY" "$FILE"
		$SED "${LINENUM}i \ \ \ \ accept: limited" "$FILE"
	done
fi

# Setup SSL
get_pod_name "$NS" isvgimconfig && POD=$REPLY
if [[ -f $CERTDIR/isvgimRootCA.key ]]; then
	for EXT in $EXT2; do
		$kubectl -n "$NS" cp "$CERTDIR/isvgimRootCA.$EXT" "$POD:/work/isvgimRootCA.$EXT"
	done
fi
$kubectl -n "$NS" exec "$POD" -- /work/certificateUtil.sh ldap
if [[ $? -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Unable to create certificates in config pod"
	fi
	exit 24
fi

for FILE in isvd isvd2 proxy isvgimRootCA; do
	if [[ $FILE = isvgimRootCA ]]; then
		EXTS=$EXT2
	else
		EXTS=$EXT1
	fi
	for EXT in $EXTS; do
		$kubectl -n "$NS" cp "$POD":"/work/${FILE}.${EXT}" "${CERTDIR}/${FILE}.${EXT}" > /dev/null 2>&1
	done
done

# Combine cert and key for ISVD consumption
for FILE in isvd proxy isvd2; do
	cat "$CERTDIR/${FILE}.crt" "$CERTDIR/${FILE}.key" > "$CERTDIR/${FILE}.pem"
done

# Remove unneeded certificates
if [[ $INSTALL_LDAP_HA -eq 0 ]]; then
	rm "$CERTDIR"/isvd2.*
	rm "$CERTDIR"/proxy.*
fi

# Generate configmap for ldap_config.yaml
./createConfigs.sh ldap
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Error creating ConfigMap files.  Please review above messages for details"
	fi
	exit "$RC"
else
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Please load yaml/025-config-isvgimldap.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

# Deploy the first backend replica
printf "\n  -- Deploying LDAP server --\n"
for FILE in $YMLFILES; do
	./updateYaml.sh "${FILE}.yaml"
done

if [[ $OFFLINE -eq 0 ]]; then
	# Waiting for pod to be created
	sleep 5
	POD=$($kubectl -n "$NS" get pods | grep isvd-replica-1 | awk '{ print $1 }')
	./sys/waitFor.sh "$POD" pod
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi

	# Waiting for replica-1 pod to be ready
	./sys/waitFor.sh isvd-replica-1 application
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi
else
	echo "Please load the following files to deploy isvd-replica-1:"
	for FILE in $YMLFILES; do
		echo "yaml/${FILE}.yaml"
	done
	printf "\n"
	read -n 1 -s -r -p "Once isvd-replica-1 is Ready, press any key to continue..."
	printf "\n\n"
fi

# If HA is disabled, we're done
if [[ $INSTALL_LDAP_HA -eq 0 ]]; then
	exit 0
fi

# Create global admin account
printf "\n  -- Creating admin user --\n"
printf "Loading LDIF files..."
POD=$($kubectl -n "$NS" get pods | grep isvd-replica-1 | awk '{ print $1 }')
PORT=$(grep ldaps ../helm/values.yaml | grep -v "ldaps:" | awk '{ print $2 }')
create_ldif
$kubectl -n "$NS" cp "$USERLDIF" "${POD}":/tmp/ldif1
$kubectl -n "$NS" cp "$GROUPLDIF" "${POD}":/tmp/ldif2
$kubectl -n "$NS" cp "$SCHEMAREPL" "${POD}":/tmp/ldif3
RESULT=$($kubectl -n "$NS" exec "$POD" -- idsldapadd -h localhost -p "$PORT" -D "$ADMINDN" -w "$ADMINPWD" -f /tmp/ldif1 -K /home/idsldap/idsslapd-idsldap/etc/server.kdb)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "Error: $RC - $RESULT"
	if [[ -z "$1" ]]; then
		echo "Error creating admin user.  Please review above message for details"
	fi
	exit 30
fi
RESULT=$($kubectl -n "$NS" exec "$POD" -- idsldapmodify -h localhost -p "$PORT" -D "$ADMINDN" -w "$ADMINPWD" -f /tmp/ldif2 -K /home/idsldap/idsslapd-idsldap/etc/server.kdb)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "Error: $RC - $RESULT"
	if [[ -z "$1" ]]; then
		echo "Error adding user to admin group.  Please review above message for details"
	fi
	exit 31
fi
rm "$USERLDIF"
rm "$GROUPLDIF"
printf "Done!\n"

# Create replication agreement
printf "\n  -- Creating Replication Agreement --\n"
./updateYaml.sh 071-pvc-isvd2.yaml
RESULT=$($kubectl -n "$NS" exec "$POD" -- isvd_manage_replica -ap -z -h isvd-replica-2 -p "$PORT" -i isvd-replica-2 -ph isvd-replica-1 -pp "$PORT")
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "Error: $RC - $RESULT"
	if [[ -z "$1" ]]; then
		echo "Error creating replication agreement.  Please review above message for details"
	fi
	exit 40
fi
RESULT=$($kubectl -n "$NS" exec "$POD" -- idsldapadd -h localhost -p "$PORT" -D "$ADMINDN" -w "$ADMINPWD" -f /tmp/ldif3 -K /home/idsldap/idsslapd-idsldap/etc/server.kdb)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "Error: $RC - $RESULT"
	if [[ -z "$1" ]]; then
		echo "Error loading replication agreement LDIF.  Please review above messages for details"
	fi
	exit 41
fi
rm "$SCHEMAREPL"
printf "Agreement created.  Shutting down the primary server.\n"
$kubectl -n "$NS" scale --replicas=0 deployment/isvd-replica-1 > /dev/null

# Copy the filesystem
printf "\n -- Starting Seed Job --\n"
./updateYaml.sh 400-job-isvdseed.yaml
if [[ $OFFLINE -eq 1 ]]; then
	echo "Please load the yaml/400-job-isvdseed.yaml to start the seed job"
	read -n 1 -s -r -p "Once loaded, press any key to continue..."
	printf "\n\n"
fi
printf "Waiting for job to complete..."
$kubectl -n "$NS" wait --for=condition=complete --timeout=300s job/isvd-seed > /dev/null 2>&1
printf "..Done!\n"
$kubectl delete -f ../yaml/400-job-isvdseed.yaml


# Deploy the second backend replica
printf "\n  -- Deploying LDAP Replica --\n"
for FILE in $REPLICAFILES; do
	./updateYaml.sh "${FILE}.yaml"
done

if [[ $OFFLINE -eq 0 ]]; then
	sleep 5
	POD=$($kubectl -n "$NS" get pods | grep isvd-replica-2 | awk '{ print $1 }')
	./sys/waitFor.sh "$POD" pod
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi

	# Waiting for replica-2 pod to be ready
	./sys/waitFor.sh isvd-replica-2 application
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi
else
	echo "Please load the following files to deploy isvd-replica-2:"
	for FILE in $REPLICAFILES; do
		echo "yaml/${FILE}.yaml"
	done
	printf "\n"
	read -n 1 -s -r -p "Once isvd-replica-2 is Ready, press any key to continue..."
	printf "\n\n"
fi

POD=$($kubectl -n "$NS" get pods | grep isvd-replica-2 | awk '{ print $1 }')
RESULT=$($kubectl -n "$NS" exec "$POD" -- isvd_manage_replica -ar -z -h isvd-replica-1 -p "$PORT" -i isvd-replica-1 -s isvd-replica-1)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "Error: $RC - $RESULT"
	if [[ -z "$1" ]]; then
		echo "Error creating replication agreement.  Please review above message for details"
	fi
	exit 40
fi
printf "Replication Agreement created.\n"
$kubectl -n "$NS" scale --replicas=1 deployment/isvd-replica-1 > /dev/null
$kubectl -n "$NS" scale --replicas=0 deployment/isvd-replica-2 > /dev/null
$kubectl -n "$NS" scale --replicas=1 deployment/isvd-replica-2 > /dev/null
printf "Restarting replicas..."
$kubectl -n "$NS" wait deployment/isvd-replica-1 deployment/isvd-replica-2 --for=condition=available > /dev/null 2>&1
printf "...Done!\n"

# Deploy proxy server
printf "\n  -- Deploying Proxy server --\n"
for FILE in $PROXYFILES; do
	./updateYaml.sh "${FILE}.yaml"
done

if [[ $OFFLINE -eq 0 ]]; then
	# Waiting for proxy server to be created
	sleep 5
	POD=$($kubectl -n "$NS" get pods | grep isvd-proxy | awk '{ print $1 }')
	./sys/waitFor.sh "$POD" pod
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi

	# Waiting for proxy server to be ready
	./sys/waitFor.sh isvd-proxy application
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi
else
	echo "Please load the following files to deploy isvd-replica-2:"
	for FILE in $PROXYFILES; do
		echo "yaml/${FILE}.yaml"
	done
	printf "\n"
	read -n 1 -s -r -p "Once isvd-proxy is Ready, press any key to continue..."
	printf "\n\n"
fi

touch "$INSTALL_MARKER"
