#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: updateValues.sh"
	echo "When to run: Never, called automatically by the installer."
	echo "Description:"
	echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
	echo "   It will update values.yaml with info from config.yaml."
	echo "Example usage:"
	echo "   $ ./updateValues.sh"
	echo ""
	exit 0
fi

CFGFILE="../config/config.yaml"
VALFILE="../helm/values.yaml"
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

# Check for config.yaml existence
if [[ ! -f $CFGFILE ]]; then
	exit 36
fi

# Pull the namespace value
NS=$(grep namespace "$CFGFILE" | awk '{ print $2 }')
if [[ -z "$NS" ]]; then
	exit 37
fi

# Pull the clusterUrl value
CU=$(grep clusterUrl "$CFGFILE" | awk '{ print $2 }')
if [[ -z "$CU" ]]; then
	# Default to localhost
	CU="https://127.0.0.1:6433"
fi

# Pull the storageclass value
SC=$(grep storageclass "$CFGFILE" | awk '{ print $2 }')
if [[ -z "$SC" ]]; then
	exit 38
fi

# Pull the licenseType value
LT=$(grep licenseType "$CFGFILE" | awk '{ print tolower($2) }')
if [[ "$LT" = "uvu" ]]; then
	LT="USER"
else
	LT="PROCESSOR"
fi

# Pull the enableFips flag value
EF=$(grep enableFIPS "$CFGFILE" | awk '{ print tolower($2) }')
if [[ -z "$EF" ]]; then
	EF=false
fi

# Check for OpenShift
kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
else
	if [[ "$kubectl" = "oc" ]]; then
		OCP=true
		echo "Detected oc. Enabling OpenShift settings."
	else
		OCP=false
	fi
fi

get_sed_cmd && SED=$REPLY

# Check for cluster
SCM="ReadWriteOnce"
NODES=$($kubectl get nodes --no-headers | wc -l)
if [[ $NODES -gt 1 ]]; then
	SCM="ReadWriteMany"
fi

# Pull K8s API endpoint
K8SAPI=$($kubectl cluster-info | grep -i kubernetes | awk '{ print $NF }' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")

# Pull the LDAP audit value
AL=$(grep enableAuditLog "$CFGFILE" | awk '{ print $2 }')
if [[ -z "$AL" ]]; then
	AL="false"
fi

# Pull the timezone
USERTZ=$(ls -l /etc/localtime | grep zoneinfo | sed "s;.*zoneinfo/\(.*\)$;\1;")
VALTZ=$(grep timezone "$VALFILE" | awk '{ print $2 }')
if [[ -z "$USERTZ" ]]; then
	echo "Error reading timezone info from /etc/localtime, defaulting to UTC"
	USERTZ="Etc/UTC"
else
	echo "Configuring for timezone $USERTZ"
fi

# Update values.yaml
$SED "s/\(  className:\).*$/\1 $SC/" "$VALFILE"
$SED "s/\(namespace:\).*$/\1 $NS/" "$VALFILE"
$SED "s;\(clusterUrl:\).*;\1 $CU;" "$VALFILE"
$SED "s/\(    auditlog:\).*$/\1 $AL/" "$VALFILE"
$SED "s/\(isOpenShift:\).*$/\1 $OCP/" "$VALFILE"
$SED "s/\(licenseType:\).*$/\1 $LT/" "$VALFILE"
$SED "s/\(fips:\).*$/\1 $EF/" "$VALFILE"
$SED "s/REPLACE_MODE/$SCM/" "$VALFILE"
$SED "s;REPLACE_CLUSTER;$K8SAPI;" "$VALFILE"

# Only replace timezone if it has not been overridden
if [[ "$VALTZ" = "REPLACE_TIMEZONE" ]]; then
	$SED "s;\(timezone:\).*$;\1 $USERTZ;" "$VALFILE"
fi

# Remove entries from config.yaml
$SED '/namespace:/d' "$CFGFILE"
$SED '/clusterUrl:/d' "$CFGFILE"
$SED '/storageclass:/d' "$CFGFILE"
$SED '/licenseType:/d' "$CFGFILE"
$SED '/enableAuditLog:/d' "$CFGFILE"

exit 0
