#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: ldapUUIDUpgrade.sh"
	echo "When to run: To Upgrade ldap data with UUID"
	echo "Description:"
	echo "   This tool upgrades the existing ldap data with UUID"
	echo "Usage:"
	echo "   $ ./ldapUUIDUpgrade.sh"
	echo ""
	exit 0
fi

IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh
get_namespace || die "Unable to get namespace" $?
NS=$REPLY

# Display list of available entities
echo "Select an entity to upgrade UUID:"
echo "1. Service"
echo "2. Person"
echo "3. BPPerson"
echo "4. Account"
echo "5. SystemRole"
echo "6. Organization"
echo "7. OrgUnit"
echo "8. Location"
echo "9. SecurityDomain"
echo "10. BPOrgItem"
echo "11. ServiceProfile"

# Prompt the user for entity selection
read -r -p "Enter the number of the entity you want to choose (1-11): " entityChoice

# Validate the entity choice
if ! [[ "$entityChoice" =~ ^[1-9]$|^10$|^11$ ]]; then
    echo "Error: Invalid selection. Please choose a number between 1 and 11."
    exit 1
fi

# Map entity choice to actual entity name
case "$entityChoice" in
    1) entity="erServiceItem" ;;
    2) entity="erPersonItem" ;;
    3) entity="erBPPersonItem" ;;
    4) entity="erAccountItem" ;;
    5) entity="erSystemRole" ;;
    6) entity="erOrganizationItem" ;;
    7) entity="erOrgUnitItem" ;;
    8) entity="erLocationItem" ;;
    9) entity="erSecurityDomainItem" ;;
    10) entity="erBPOrgItem" ;;
    11) entity="erServiceProfile" ;;
    *)
        echo "Error: Invalid entity choice."
        exit 1
        ;;
esac

read -r -p "Enter the page size (e.g., 1000): " pageSize

if [[ -z "$pageSize" ]]; then
    echo "Error: Page size is required. Please enter a valid number."
    exit 1
fi

if ! [[ "$pageSize" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid input. Page size must be a positive integer."
    exit 1
fi


kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

get_pod_name "$NS" isvgim && POD=$REPLY
if [[ $POD = isvgim-* ]]; then
	$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /work/ldapUUIDUpgrade.sh "$pageSize" "$entity" "$@"
else
	$kubectl -n "$NS" exec "$POD" -- /bin/bash /work/ldapUUIDUpgrade.sh "$pageSize" "$entity" "$@"
fi

if [[ ! -d ../logs ]]; then
	mkdir ../logs
fi

$kubectl -n "$NS" cp "$POD":"${IM_HOME}/install_logs/ldapUUIDUpgrade.stdout" ../logs/ldapUUIDUpgrade.stdout > /dev/null


if [[ $? -ne 0 ]]; then
	exit 1
fi
