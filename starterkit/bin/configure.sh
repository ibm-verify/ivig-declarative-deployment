#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: configure.sh"
	echo "When to run: Before running install.sh."
	echo "Description:"
	echo "   Prompts for the information needed in config.yaml. It makes it"
	echo "   easier to avoid formatting problems with the file."
	echo "Options:"
	echo "   -manual: Prevent any connection to kubernetes or the Internet"
	echo "Example usage:"
	echo "   $ ./configure.sh"
	echo "   $ ./configure.sh -manual"
	echo ""
	exit 0
fi

if [[ "$1" = "-manual" ]]; then
	OFFLINE=1
else
	OFFLINE=0
fi

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh
get_sed_cmd && SED=$REPLY
if [[ "$OFFLINE" -eq 0 ]]; then
	kubectl=$(./sys/preReqCheck.sh)
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		echo "$kubectl"
		exit "$RC"
	fi
fi

CFGBAK="../config/config.bak"
CFGFILE="../config/config.yaml"
LICENSE_SCRIPT_LOCATION="https://raw.githubusercontent.com/IBM/ibm-licensing-operator/latest/common/scripts/ibm_licensing_operator_install.sh"
LICENSE_SCRIPT_NAME=ibm_licensing_operator_install.sh

# As default flow of execution must have the tablespaces
CREATETABLESPACE=true

# Default value for Oracle connection type
ISORACLESERVICENAME=true

# Check if we're already installed or not
grep -q storageclass "$CFGFILE"
if [[ $? -eq 1 ]]; then
	printf "\nThe current config.yaml indicates IVIG is already installed.\n"
	exit 1
fi

if [[ "$OFFLINE" -eq 0 ]]; then
	# Collect the installed storage classes
	KUBE_SC=$($kubectl get sc | tail -n +2 | awk '{ print $1 }')
	NUM_NODES=$($kubectl get nodes --no-headers | wc -l)
else
	KUBE_SC=""
	NUM_NODES=2
fi

get_existing_value() {
	grep "${1}:" "$CFGFILE" | cut -d ':' -f 2- | xargs
} #get_existing_value

check_k8s_naming() {
	LENGTH=${#1}
	if [[ "$LENGTH" -gt 63 ]]; then
		printf "Identifiers are limited to 63 characters.\n\n"
		return 1
	fi
	if [[ ! "$1" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]{0,61}[a-zA-Z0-9]$ ]]; then
		printf "Identifiers must be alphanumeric or hyphen, and start and end with alphanumeric.\n\n"
		return 2
	fi
	if [[ "$1" =~ ^kube- ]]; then
		printf "Starting an identifier with \"kube-\" is reserved for kubernetes\n"
		printf "system objects.\n\n"
		return 3
	fi
} #check_k8s_naming

check_ldapuser_naming() {
	if [[ ! "$1" =~ ^.+[=].+$ ]]; then
		printf "LDAP admin DN must be in the format attribute=value.\n\n"
		return 1
	fi
} #check_ldapuser_naming

check_sc() {
	for SC in $KUBE_SC; do
		if [[ "$SC" = "$1" ]]; then
			return 0
		fi
	done
	return 1
} #check_sc

check_truefalse() {
	if [[ ! "$1" =~ ^(true|false)$ ]]; then
		return 1
	fi
} #check_truefalse

check_digits() {
	if [[ ! "$1" =~ ^[0-9]+$ ]] || [[ "$1" -gt "$2" ]]; then
		return 1
	fi
} #check_digits

check_cert_format() {
	if [[ ! "$1" =~ ^(@|B64:) ]]; then
		printf "\nIncorrect format. Must start with \"@\" or \"B64:\"\n\n"
		return 1
	fi
} #check_cert_format

# Used to make sure the correct security.protocol line in config.yaml is updated
find_ssl_line() {
	DBLINE=$(grep -n "db:" "$CFGFILE" | cut -d ':' -f 1)
	LDAPLINE=$(grep -n "ldap:" "$CFGFILE" | cut -d ':' -f 1)
	LINEA=$(grep -n "security.protocol" "$CFGFILE" | head -n 1 | cut -d ':' -f 1)
	LINEB=$(grep -n "security.protocol" "$CFGFILE" | tail -n 1 | cut -d ':' -f 1)
	if [[ "$DBLINE" -gt "$LDAPLINE" ]]; then
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

get_namespace() {
	printf "\nWhich namespace would you like to install into?\n"
	printf "Rules: Max 63 chars, alphanumeric and hyphen allowed.\n\n"
	DNAMESPACE=$(get_existing_value namespace)
	while [[ -z $NAMESPACE ]]; do
		read -r -p "Namespace [$DNAMESPACE]: " NAMESPACE
		NAMESPACE=${NAMESPACE:-$DNAMESPACE}
		check_k8s_naming "$NAMESPACE"
		if [[ $? -ne 0 ]]; then
			NAMESPACE=""
		fi
	done
} #get_namespace

get_clusterUrl() {
	DCLUSTERURL=$($kubectl cluster-info | grep -i "control plane" | awk '{ print $NF }' | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")
	LOOPCHECK=$(echo "$DCLUSTERURL" | cut -d '/' -f 3 | cut -d '.' -f 1)
	if [[ "$LOOPCHECK" = "127" ]]; then
		printf "\nFound Kubernetes cluster URL of: %s\n" "$DCLUSTERURL"
		printf "\nThis is a loopback address, which is not available from a pod.\n"
		printf "Please provide the URL with the externally accessible IP address.\n\n"
		read -r -p "ClusterUrl [$DCLUSTERURL]: " CLUSTERURL
		CLUSTERURL=${CLUSTERURL:-$DCLUSTERURL}
	else
		CLUSTERURL=$DCLUSTERURL
	fi
} #get_clusterUrl

get_storageclass() {
	printf "\nWhich storageclass will be used for volumes?\n"
	if [[ "$NUM_NODES" -gt 1 ]]; then
		printf "Rules: It must support dynamic provisioning and mode ReadWriteMany.\n"
	else
		printf "Rules: It must support dynamic provisioning.\n"
	fi
	printf "Currently installed options:\n\n"
	if [[ "$OFFLINE" -eq 1 ]]; then
		printf "List not available in manual mode\n"
	else
		for SC in $KUBE_SC; do
			printf "%s\n" "$SC"
		done
	fi
	printf "\n"
	DSTORAGECLASS=$(get_existing_value storageclass)
	while [[ -z "$STORAGECLASS" ]]; do
		read -r -p "Storageclass [$DSTORAGECLASS]: " STORAGECLASS
		STORAGECLASS=${STORAGECLASS:-$DSTORAGECLASS}
		if [[ "$OFFLINE" -eq 0 ]]; then
			check_sc "$STORAGECLASS"
			if [[ $? -ne 0 ]]; then
				read -r -p "Storageclass $STORAGECLASS is not installed. Are you sure (y/n)? " YESNO
				YESNO=$(awk '{ print tolower($1) }' <<< "$YESNO")
				if [[ "$YESNO" != "y" ]]; then
					STORAGECLASS=""
				fi
			fi
		fi
	done
} #get_storageclass

get_installType() {
	prompt_not_empty "Value for installType (local/cloud)" "$(get_existing_value installType)" && INSTALLTYPE=$VALUE
} #get_installType

get_waitTimeout() {
	printf "\nThe wait timeout is the number of 5-second units to wait for an operation\n"
	printf "to complete. Larger values can be helpful on slow or underpowered systems.\n"
	printf "The default 120 represents 10 minutes, which should be sufficient in most\n"
	printf "cases.\n\n"
	DWAITTIMEOUT=$(get_existing_value waitTimeout)
	while [[ -z "$WAITTIMEOUT" ]]; do
		read -r -p "Value for waitTimeout [$DWAITTIMEOUT]: " WAITTIMEOUT
		WAITTIMEOUT=${WAITTIMEOUT:-$DWAITTIMEOUT}
		check_digits "$WAITTIMEOUT" 1000
		if [[ $? -ne 0 ]]; then
			printf "\nInvalid value. Must be an integer less than 1000.\n\n"
			WAITTIMEOUT=""
		fi
	done
} #get_waitTimeout

get_customRepo() {
	printf "\nIn environments without Internet access, the images can be placed into\n"
	printf "a custom repository. If you are using a custom repository, you will need\n"
	printf "to supply the credentials and connection information.  The connection\n"
	printf "details are host:port, but :port can be left off if it's using 443.\n\n"

	prompt_not_empty "Are you using a custom image repository? (y/N)" "N"
	VALUE=$(awk '{ print tolower($1) }' <<< "$VALUE")
	if [[ "$VALUE" != "y" ]]; then
		return
	fi

	printf "\n"
	prompt_not_empty "Username" "$(get_existing_value customRepoUser)" && CRUSER=$VALUE
	pw_prompt "Password:" && CRPWD=$PWVALUE
	prompt_not_empty "Server" "$(get_existing_value customRepoURL)" && CRURL=$VALUE
} #get_customRepo

prompt_not_empty() {
	VALUE=""
	while [[ -z "$VALUE" ]]; do
		prompt "$1" "$2"
		if [[ -z "$VALUE" ]]; then
			printf "\nValue cannot be empty.\n\n"
		fi
	done
} #prompt_not_empty

prompt() {
	printf "\n"
	DVALUE="$2"
	read -r -p "${1} [$DVALUE]: " VALUE
	VALUE=${VALUE:-$DVALUE}
} #prompt

pw_prompt() {
	PWVALUE="1"
	PWVALUE2=""
	printf "\n"
	while [[ "$PWVALUE" != "$PWVALUE2" ]]; do
		read -r -sp "$1 " PWVALUE
		if [[ "$2" = "required" ]] && [[ -z "$PWVALUE" ]]; then
			printf "\nA value MUST be specified.\n\n"
			PWVALUE="1"
			continue
		fi
		printf "\n"
		read -r -sp "Re-enter $1 " PWVALUE2
		printf "\n"
		if [[ "$PWVALUE" != "$PWVALUE2" ]]; then
			printf "Passwords don't match.\n\n"
		fi
	done
} #pw_prompt

user_prompt() {
	printf "\nPlease provide the credentials IVIG will use to connect to %s.\n" "$1"
	prompt_not_empty "Username" "$(get_existing_value "$2")" && USER=$VALUE
} #user_prompt

get_mqPasswords() {
	printf "\nOptionally provide passwords for the MQ message queues.\n"
	printf "These are only needed if you setup your own shared MQ server. In most cases,\n"
	printf "these should be left blank and random values will be generated.\n"
	pw_prompt "MQ Share Password:" && MQSHARE=$PWVALUE
	pw_prompt "MQ Admin Password:" && MQADMIN=$PWVALUE
} #getMqPasswords

get_truefalse() {
	printf "\n"
	TFVALUE=""
	while [[ -z $TFVALUE ]]; do
		read -r -p "$1 (true/false) [$2]? " TFVALUE
		TFVALUE=${TFVALUE:-$2}
		TFVALUE=$(awk '{ print tolower($1) }' <<< "$TFVALUE")
		check_truefalse "$TFVALUE"
		if [[ $? -ne 0 ]]; then
			printf "\nInvalid value. Must be \"true\" or \"false\".\n\n"
			TFVALUE=""
		fi
		
	done
} # get_truefalse

get_activation_key() {
	printf "\nThe activation key is required to use the IVIG.\n"
	printf "It is available from your IVIG entitlement on Passport Advantage.\n\n"
	read -r -p "Activation Key: " ACTKEY
	if [[ -z $ACTKEY ]]; then
		printf "\nWARNING: Installation will FAIL without a valid activation key!\n"
		printf "         Please re-run this program or update config.yaml with a valid\n"
		printf "         activation key before running the installer.\n"
		sleep 5
	fi
} #get_activation_key

get_risk_key() {
	printf "\nThe Enterprise or Compliance key is required to activate the analytics module.\n"
	printf "It is available as an upgrade from your IVIG Lifecycle entitlement.\n"
	printf "If you do not have this key, please leave the value blank.\n\n"
	read -r -p "Enterprise or Compliance Key: " RISKKEY
} #get_risk_key

get_key() {
	printf "\n%s requires a license key.\n" "$1"
	printf "It can be found with your entitlement on Passport Advantage.\n"
	printf "IMPORTANT: The key must be a single line. To avoid problems with multi-lines\n"
	printf "           when copied from a document, <Enter> has been disabled and you\n"
	printf "           MUST use the semi-colon (;) character to submit the value.\n\n"
	read -r -d ";" -p "License Key: " KEY
	KEY=$(tr -d '\n' <<< "$KEY")
	if [[ -z "$KEY" ]]; then
		printf "\nWARNING: Installation will FAIL without a valid license key!\n"
		printf "         Please re-run this program or update config.yaml with a valid\n"
		printf "         %s license key before running the installer.\n" "$2"
		sleep 5
	fi
	printf "\n"
} #get_key

get_port(){
	PORT=""
	printf "\nPlease provide the port number of the %s server.\n\n" "$1"
	DPORT=$(get_existing_value "$2")
	if [[ -z $PORT ]]; then
		DPORT=$3
	fi
	while [[ -z $PORT ]]; do
		read -r -p "Port [$DPORT]: " PORT
		PORT=${PORT:-$DPORT}
		check_digits "$PORT" "$4"
		if [[ $? -ne 0 ]]; then
			printf "\nValue must be an integer less than %s.\n\n" "$4"
			PORT=""
		fi
	done
} #get_port

get_host() {
	HOST=""
	printf "\nPlease provide the hostname or IP address of the %s server.\n" "$1"
	prompt_not_empty "Hostname / IP" "$(get_existing_value "$2")" && HOST=$VALUE
} #get_host

get_ssl() {
	SSL=""
	find_ssl_line "$1"
	DSSL=$(sed -n "${LINE}p" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$DSSL" ]]; then
		DSSL="false"
	elif [[ "$DSSL" = "ssl" ]]; then
		DSSL="true"
	fi
	printf "\n"
	get_truefalse "Is the $2 server using SSL" "$DSSL"
	if [[ $TFVALUE = "true" ]]; then
		SSL=ssl
	fi
} #get_ssl

get_dbuser() {
	user_prompt database user && DBUSER=$USER
	pw_prompt "Password:" required && DBPASS=$PWVALUE
} #get_dbuser

get_dbadmin() {
	if [[ "$DEPLOYDB" = "true" ]]; then
		printf "\nOPTIONALLY: provide the admin credentials for the PostgreSQL pod.\n"
		printf "If left blank, the user will be \"postgres\" with a random password.\n\n"
	else
		printf "\nPlease provide the admin credentials for the database server.\n\n"
	fi
	DDBADM=$(get_existing_value "  admin")
	while [[ -z $DBADM ]]; do
		read -r -p "Admin Username [$DDBADM]: " DBADM
		if [[ "$DEPLOYDB" = "true" ]]; then
			break
		fi
		DBADM=${DBADM:-$DDBADM}
		if [[ -z "$DBADM" ]]; then
			printf "\nAdmin username cannot be empty.\n\n"
		fi
	done
	printf "\n"
	if [[ -n "$DBADM" ]]; then
		pw_prompt "Admin Password:" && DBADMPASS=$PWVALUE
	fi
} #get_dbadmin

get_dbname() {
	if [[ "$DEPLOYDB" = "true" ]]; then
		printf "\nOPTIONALLY: provide a name for the database.\n\n"
	else
		printf "\nPlease provide the name of the database.\n\n"
	fi
	DDBNAME=$(get_existing_value "  name")
	if [[ -z "$DDBNAME" ]]; then
		DDBNAME="ivig"
	fi
	while [[ -z $DBNAME ]]; do
		read -r -p "Database Name [$DDBNAME]: " DBNAME
		DBNAME=${DBNAME:-$DDBNAME}
	done
} #get_dbname

get_dbtype() {
	printf "\nPlease provide database type. Valid values are db2, oracle and postgres\n\n"
	DDBTYPE=$(get_existing_value dbtype)
	while [[ -z $DBTYPE ]]; do
		read -r -p "Database type [$DDBTYPE]: " DBTYPE
		DBTYPE=${DBTYPE:-$DDBTYPE}
		if [[ ! "$DBTYPE" =~ ^(db2|postgres|oracle)$ ]]; then
			printf "\nInvalid type: %s\n\n" "$DBTYPE"
			DBTYPE=""
		fi
	done
} #get_dbtype
get_oracle_service_name_flag() {
	printf "\nSpecify how Oracle database is configured.\n"
	printf "true  - Using Oracle SERVICE NAME\n"
	printf "false - Using Oracle SID\n\n"

	DORACLESERVICE=$(get_existing_value isOracleServiceName)

	if [[ -z "$DORACLESERVICE" ]]; then
		DORACLESERVICE="true"
	fi

	get_truefalse "Is Oracle configured using SERVICE NAME" "$DORACLESERVICE"
	ISORACLESERVICENAME=$TFVALUE
}

get_tablespaces() {
	printf "\nPlease specify the paths which will hold the tablespaces.\n\n"
	prompt_not_empty "Tablespace data path" "$(get_existing_value tablespace.location.data)" && DBTBLDATA=$VALUE
	prompt_not_empty "Tablespace index path" "$(get_existing_value tablespace.location.indexes)" && DBTBLIDX=$VALUE
	DBTBLDATA=$(echo "$DBTBLDATA" | sed 's/\\/\\\\/g');
	DBTBLIDX=$(echo "$DBTBLIDX" | sed 's/\\/\\\\/g');
} #get_tablespaces

get_ldap_admin_dn() {
	while [[ -z "$LDAPUSER" ]]; do
		user_prompt LDAP security.principal && LDAPUSER=$USER
		check_ldapuser_naming "$LDAPUSER"
		if [[ $? -ne 0 ]]; then
			LDAPUSER=""
		fi
	done
} #get_ldap_admin_dn


get_ldap_user() {
	if [[ "$DEPLOYLDAPHA" = "true" ]]; then
		printf "\nThe userid specified here will be the admin user on the replica servers.\n"
		printf "The proxy server admin will be cn=manager,cn=ibmpolicies.\n"
		printf "The specified password will be used for both accounts.\n"
	fi
	printf "\nThe format is attribute=value, where the attribute MUST exist in the schema. If\n"
	printf "in doubt, use cn=root.\n"
	get_ldap_admin_dn
	pw_prompt "Password:" required && LDAPPASS=$PWVALUE
} #get_ldap_user

get_tenant() {
	printf "\nPlease provide the Organization information.\n"
	printf "Tenant is the name of the OrgUnit in LDAP\n"
	printf "Organization is the name displayed in the IVIG user interface\n"
	printf "Root suffix is the base of the IVIG tree in LDAP\n"
	while [[ -z "$TENANT" ]]; do
		prompt_not_empty "Tenant" "$(get_existing_value defaulttenant.id)" && TENANT=$VALUE
		if [[ $TENANT =~ = ]]; then
			printf "\nThe value cannot contain the \"=\" sign\n"
			TENANT=""
		fi
	done
	prompt_not_empty "Organization" "$(get_existing_value organization.name)" && ORGNAME=$VALUE
} #get_tenant

get_suffix() {
	prompt_not_empty "Root suffix" "$(get_existing_value ldapserver.root)" && SUFFIX=$VALUE
	if [[ ! $SUFFIX =~ ^dc=[^=]+$ ]]; then
		printf "\nWARNING: ISVG IM is configured to accept a simple domain suffix.\n"
		printf "         You hve entered a more complex suffix. This is allowed, but\n"
		printf "         you will need to modify config/ldap_config.yaml to specify\n"
		printf "         additional objectclasses and/or attributes for your suffix.\n"
		if [[ "$DEPLOYLDAPHA" = "true" ]]; then
			printf "         You will also need to make the same changes to ldap2_config.yaml.\n"
		fi
	fi
} #get_suffix

get_extreg_type() {
	printf "\nWhich type of directory server are you using for the external registry?\n"
	printf "The supported options are Microsoft Active Directory and IBM Security\n"
	printf "Verify Directory Server. Specify either \"AD\" or \"IBM\"\n\n"
	DERTYPE=$(get_existing_value "  type")
	while [[ -z $ERTYPE ]]; do
		read -r -p "Type [$DERTYPE]: " ERTYPE
		ERTYPE=${ERTYPE:-$DERTYPE}
		ERTYPE=$(awk '{ print tolower($1) }' <<< "$ERTYPE")
		if [[ "$ERTYPE" = "ad" ]]; then
			ERTYPE="Microsoft Active Directory"
		elif [[ "$ERTYPE" = "ibm" ]]; then
			ERTYPE="IBM Tivoli Directory Server"
		else
			printf "\nInvalid option: %s\n\n" "$ERTYPE"
			ERTYPE=""
		fi
	done
} #get_extreg_type

get_filter_props() {
	printf "\nWhen defined, filters require an Attribute Value Assertion (AVA)\n"
	printf "containing a \"%%v\". e.g. uid=%%v. During searches, the %%v in the AVA\n"
	printf "is replaced with the user or group targeted by the search. Special\n"
	printf "characters in filters must be escaped to conform with XML syntax.\n\n"
	printf "Group Filter - filter for searching the registry for groups\n"
	printf "  default for AD: (&amp;(cn=%%v)(objectcategory=group))\n"
	printf "  default for IBM: (&amp;(cn=%%v)(|(objectclass=groupOfNames)(objectclass=groupOfUniqueNames)(objectclass=groupOfURLs)))\n\n"
	prompt "Group filter" "$(get_existing_value groupFilter)" && ERGRPFILTER=$VALUE
	printf "\n\nGroup ID Map - filter that maps a group name to an LDAP entry\n"
	printf "  default for AD: *:cn\n"
	printf "  default for IBM: *:cn\n\n"
	prompt "Group ID Map" "$(get_existing_value groupIdMap)" && ERGRPIDMAP=$VALUE
	printf "\n\nGroup Member Map - filter that identifies user to group memberships\n"
	printf "  default for AD: memberOf:member\n"
	printf "  default for IBM: ibm-allGroups:member;ibm-allGroups:uniqueMember;groupOfNames:member;groupOfUniqueNames:uniqueMember\n\n"
	prompt "Group Member Map" "$(get_existing_value groupMemberIdMap)" && ERGRPMBRMAP=$VALUE
	printf "\n\nUser Filter - filter for searching the registry for users\n"
	printf "  default for AD: (&amp;(sAMAccountName=%%v)(objectcategory=user))\n"
	printf "  default for IBM: (&amp;(uid=%%v)(objectclass=person))\n\n"
	prompt "User filter" "$(get_existing_value userFilter)" && ERUSERFILTER=$VALUE
	printf "\n\nUser ID Map - filter that maps a user name to an LDAP entry\n"
	printf "  default for AD: user:sAMAccountName\n"
	printf "  default for IBM: *:uid\n\n"
	prompt "User ID Map" "$(get_existing_value userIdMap)" && ERUSERIDMAP=$VALUE
} #get_filter_props

get_liberty_metrics() {
	printf "\nLibertyMetrics is an optional feature that will expose performance\n"
	printf "statistics in Prometheus format at https://server:30943/metrics. They can\n"
	printf "also be read with curl in JSON format.\n\n"

	# To work with options, we need to know the line number because the
	# only unique value to grep on is the option name.
	LMLINE=$(grep -n libertyMetrics "$CFGFILE" | cut -d ':' -f 1)
	LMENABLEDLINE=$((LMLINE+1))
	LMUSERLINE=$((LMLINE+4))
	LMPASSLINE=$((LMLINE+6))
	DLMENABLED=$(sed -n "${LMENABLEDLINE}p" "$CFGFILE" | awk '{ print $2 }')

	get_truefalse "Enable LibertyMetrics option" "$DLMENABLED" && LMENABLED=$TFVALUE
	if [[ $LMENABLED = "true" ]]; then
		printf "\n\nPlease provide the credentials that will be used to access the metrics.\n\n"
		DLMUSER=$(sed -n "${LMUSERLINE}p" "$CFGFILE" | awk '{ print $2 }')
		prompt_not_empty "Username" "$DLMUSER" && LMUSER=$VALUE
		pw_prompt "Password:" && LMPASS=$PWVALUE
		printf "\nAfter IVIG is running, please use the util/encryptLibertyPwd.sh\n"
		printf "utility to generate an encrypted value of this password.  Then edit\n"
		printf "config.yaml to update the value for the password for this option. Finally,\n"
		printf "run \"bin/createConfigs.sh setup\" to update the value in the pod.\n"
		sleep 5
	fi
} #get_liberty_metrics

# Options are a list of objects that also may contain a list of data
# We only support specific ones, and they need to be handled separately
# as there is no generic way to collect the specific data they might need.
get_options() {
	get_liberty_metrics
} #get_options

get_flags() {
	printf "\nThe IVIG server supports TLS v1.2 and v1.3 connections. Both are\n"
	printf "still considered secure, but v1.2 has been found vulnerable in certain\n"
	printf "situations.  On the other hand, not all network programs yet support\n"
	printf "v1.3.  Disabling v1.2 could cause some connections to fail.\n"

	get_truefalse "Should TLS v1.2 be disabled" "$(get_existing_value disableTLSv12)" && DISABLETLS12=$TFVALUE
	
	printf "\nFIPS 140-2 Mode Configuration. You must enable FIPS mode in order to\n"
	printf "comply with FIPS 140-2 and NIST 800131a. If you choose to enable FIPS mode\n"
	printf "now, you cannot disable it later.\n"
	
	get_truefalse "Should FIPS 140-2 be enabled" "$(get_existing_value enableFIPS)" && ENABLEFIPS=$TFVALUE

} #get_flags

get_hostnames() {
	printf "\nYou may provide a list of hostnames and/or IPs that will be used in the\n"
	printf "URL to reach the IVIG server. These values will be added to the subject\n"
	printf "alternative names field of the auto-generated SSL certificates.\n"
	printf "\nEnter a blank line to stop list collection.\n\n"
	HOSTNAMES=""
	HOST="x"
	while [[ -n $HOST ]]; do
		read -r -p "Hostname: " HOST
		if [[ -n "$HOST" ]]; then
			if [[ -n "$HOSTNAMES" ]]; then
				HOSTNAMES="$HOSTNAMES,$HOST"
			else
				HOSTNAMES=$HOST
			fi
		fi
	done
} #get_hostnames

get_truststore() {
	printf "\nYou may provide a list of CA certificates in PEM format that signed any\n"
	printf "of your endpoint SSL certificates. A default IVIG CA certificate will\n"
	printf "automatically be added during installation. If there is more than one level\n"
	printf "of trust, the file must contain the full chain of CA certificates.\n"
	printf "The format can be one of:\n"
	printf "@filename     where \"filename\" exists in the config/certs directory\n"
	printf "B64:Pz8fjWSN...    where \"B64:\" is the prefix, and the rest is the base64\n"
	printf "   encoded version of the file itself.\n\n"

	if { [[ $DEPLOYDB = "false" ]] && [[ "$DBSSL" = "ssl" ]] ;} \
	   || { [[ $DEPLOYLDAP = "false" ]] && [[ "$LDAPSSL" = "ssl" ]] ;}; then
		printf "Note: You have an external data tier configured for SSL. You MUST specify\n"
		printf "the CA certificate or the connection will fail.\n\n"
	fi

	printf "Enter a blank line to stop list collection.\n\n"
	CACERTS=""
	CERT="x"
	while [[ -n $CERT ]]; do
		read -r -p "Certificate: " CERT
		if [[ -n $CERT ]]; then
			check_cert_format "$CERT"
			if [[ $? -ne 0 ]]; then
				CERT="x"
				continue
			fi
			if [[ -n "$CACERTS" ]]; then
				CACERTS="$CACERTS,$CERT"
			else
				CACERTS=$CERT
			fi
		fi
	done
} #get_truststore

get_keystore() {
	printf "\nYou may provide a certificate and key in PEM format to use for IVIG SSL.\n"
	printf "The CAcert should be a concatenated PEM file of the full certificate signing\n"
	printf "chain. If not provided, a default certificate will be generated.\n\n"
	printf "The format can be one of:\n"
	printf "@filename where \"filename\" exists in the config/certs directory\n"
	printf "B64:Pz8fjWSN... where \"B64:\" is the prefix, and the rest is the base64\n"
	printf "   encoded version of the file itself.\n\n"

	printf "Enter a blank line to stop list collection.\n\n"
	KSCERTS=""
	KSCERT="x"
	while [[ -n "$KSCERT" ]]; do
		# Ask for cert, check format, and add to "array"
		prompt "Certificate" "" && KSCERT=$VALUE
		if [[ -n "$KSCERT" ]]; then
			check_cert_format "$KSCERT"
			if [[ $? -ne 0 ]]; then
				KSCERT=x
				continue
			fi
			KSCERTS=$KSCERT

			# Reset worker var and get valid key input
			KSCERT=""
			while [[ -z "$KSCERT" ]]; do
				prompt_not_empty "Key" "" && KSCERT=$VALUE
				check_cert_format "$KSCERT"
				if [[ $? -ne 0 ]]; then
					KSCERT=""
				fi
			done
			KSCERTS="$KSCERTS,$KSCERT"

			# One more value to collect
			KSCERT=""
			while [[ -z "$KSCERT" ]]; do
				prompt_not_empty "CA Certificate" "" && KSCERT=$VALUE
				check_cert_format "$KSCERT"
				if [[ $? -ne 0 ]]; then
					KSCERT=""
				fi
			done
			KSCERTS="$KSCERTS,$KSCERT"
			break
		fi
	done
} #get_keystore

do_installation() {
	printf "\n--> Installation\n"
	get_namespace
	get_storageclass
	get_clusterUrl
	get_installType
	get_waitTimeout
	get_mqPasswords
	get_customRepo

	echo "To utilize the regular IVIG user repository, answer \"false\" here."
	get_truefalse "Use external LDAP registry for authentication" "$(get_existing_value useExternalRegistry)" && EXTREG=$TFVALUE

	get_truefalse "Enable Mail Configuring options" "$(get_existing_value useSMTPMail)" && MAILREG=$TFVALUE

	get_truefalse "Will an OIDC provider be used for authentication" "false" && USEOIDC=$TFVALUE

	get_truefalse "Deploy ISVD LDAP Pod" "$(get_existing_value deployLdap)" && DEPLOYLDAP=$TFVALUE

	if [[ $DEPLOYLDAP = "true" ]]; then
		get_truefalse "Deploy LDAP in HA Configuration" "$(get_existing_value deployLdapHA)" && DEPLOYLDAPHA=$TFVALUE
		get_truefalse "Enable LDAP audit log" "$(get_existing_value enableAuditLog)" && AUDITLOG=$TFVALUE
	fi

	get_truefalse "Deploy PostgreSQL DB Pod" "$(get_existing_value deployDb)" && DEPLOYDB=$TFVALUE
	if [[ $DEPLOYDB = "true" ]]; then
		get_truefalse "Deploy DB in HA Configuration" "$(get_existing_value deployDbHA)" && DEPLOYDBHA=$TFVALUE
	fi

	get_truefalse "Deploy Adapter RMI Dispatcher Pod" "$(get_existing_value deployIsvdi)" && DEPLOYISVDI=$TFVALUE

} #do_installation

do_license() {
	printf "\n--> License\n"
	get_activation_key
	get_risk_key

	printf "\nPlease specify the type of license you will be using:\n"
	printf "\tPVU: Processor Value Unit, usage calculated based on CPU activity\n"
	printf "\tUVU: User Value Unit, usage calculated based on number of users managed\n"
	prompt_not_empty "License Type" "$(get_existing_value licenseType)" && LICTYPE=$VALUE
	if [[ $LICTYPE != "UVU" ]]; then
		LICTYPE=PVU
	else
		printf "\nFor UVU, you can specify criteria to identify External Users.  These are\n"
		printf "Person records that represent any users not employed by or contracted to\n"
		printf "work for your company.  You can provide either a comma delimited list of\n"
		printf "objectclasses (e.g. extPerson,publicUsers) or an attribute=value\n"
		printf "definition that External Users will have on their Person record (e.g.\n"
		printf "userType=external).  If both are specified, only objectclass will be used.\n"
		prompt "External User objectclass" "" && LICOBJC=$VALUE
		prompt "External User attribute and value" "" && LICATTR=$VALUE
		if [[ -z "$LICOBJC" ]] && [[ -z "$LICATTR" ]]; then
			printf "\nWARNING: No External User criteria specified.  All users will be considered\n"
			printf "         Internal Users.  Please update enRole.properties to specify either\n"
			printf "         enrole.license.externaluser.objectclass or\n"
			printf "         enrole.license.externaluser.attribute to define External User criteria.\n"
		fi
	fi

	get_truefalse "Do you accept the terms of the license in the license directory" "false" && LICENSE=$TFVALUE
	if [[ $LICENSE = "false" ]]; then
		printf "\nWARNING: Installation will FAIL if the license is not accepted!\n"
		printf "         Please re-run this program or update config.yaml with acceptance\n"
		printf "         before running the installer.\n"
		sleep 5
	fi

	if [[ $DEPLOYLDAP = "true" ]]; then
		get_key "IBM Security Verify Directory" LDAP && LDAPKEY=$KEY
	fi

	if [[ $DEPLOYISVDI = "true" ]]; then
		get_key "IBM Security Verify Directory Integrator" ISVDI && ISVDIKEY=$KEY
	fi

} #do_license

do_database() {
	get_dbuser
	get_dbadmin
	get_dbname

	if [[ $DEPLOYDB = "false" ]]; then
		get_dbtype
		if [[ "$DBTYPE" = "oracle" ]]; then
			get_oracle_service_name_flag
		fi
		get_host database "  ip" && DBHOST=$HOST
		get_port database "  port" 50000 65535 && DBPORT=$PORT
		get_ssl db database && DBSSL=$SSL

		if [[ "$DBTYPE" = "postgres" ]]; then
			get_truefalse "Do you want to create Tablespace?" "$(get_existing_value createTablespace)" && CREATETABLESPACE=$TFVALUE
		fi

		if [[ "$DBTYPE" = "postgres" ]] && [[ "$CREATETABLESPACE" = "true" ]]; then
			get_tablespaces
		fi
	else
		DBTBLDATA="/var/lib/postgresql/data/isvgimdata"
		DBTBLIDX="/var/lib/postgresql/data/isvgimindexes"
	fi
} #do_database

do_ldap() {
	get_ldap_user
	get_tenant
	get_suffix

	if [[ $DEPLOYLDAP = "false" ]]; then
		get_host "LDAP" "ldapserver.ip" && LDAPHOST=$HOST
		get_port LDAP "ldapserver.port" 389 65535 && LDAPPORT=$PORT
		get_ssl ldap LDAP && LDAPSSL=$SSL
	fi
} #do_ldap

do_server() {
	printf "\nPlease provide a password for the keystore that will hold the Identity Governance\n"
	printf "encryption key.  It cannot be blank.\n"
	pw_prompt "Keystore Password:" required && KEYPASS=$PWVALUE
	get_truststore
	get_keystore
	get_hostnames
	get_options
	get_flags
} #do_server

do_oidc() {
		cat << EOF > oidcinfo


--- OIDC Information ---

Once IVIG has been installed, follow these steps to configure the OIDC client
settings:

1. Edit config/config.yaml to add the following section (at the root level):

oidc:
  adminConsole:
  isc:
  rest:
  - attribute=value
  - attribute=value

Inside the three configurations (adminConsole, isc, rest) you must provide a
list of the attribute value pairs required by your OIDC provider.  Do not
include the clientID or client secret values, as those will be collected by
the utility and stored in a secret.  If they are provided here, they will be
ignored.

2. Run "bin/changePasswords.sh oidc" to provide the clientID and client secret
   values for your OIDC provider.  You will be prompted for credentials for
   each endpoint defined in config.yaml.

Then restart the isvgim pod(s) for the change to take effect.

e.g. $kubectl -n $NAMESPACE rollout restart sts isvgim

EOF
		cat oidcinfo
		rm oidcinfo
} #get_oidc

get_attribute_config() {
    printf "
provide attribute configuration for external user registry.
enter 'y' when prompted to end list collection.
"
    EURATTRIBUTES=""
    local attrconfigline
	attrconfigline=$(grep -n attributeConfiguration "$CFGFILE" | cut -d ':' -f 1)
    local attrstart=$((attrconfigline+2))
    local attrend=$((attrstart+5))
    while true; do
        # since there can be multiple attributes we need to grep only on the 5 lines which are currently relevent
        local view
		view=$(sed -n "${attrstart},${attrend}p" "$CFGFILE")
        printf "%s" "$view" | head -1 | grep -q '-' # test if the block is list item
        local isListEl=$?
        # only grep for existing values if this is a list element
        prompt "defaultValue" "$([[ "$isListEl" -eq 0 ]] && echo "$view" | grep defaultValue | cut -d ':' -f2-)" && EURATTRDEF=$VALUE
        prompt "entityType" "$([[ "$isListEl" -eq 0 ]] && echo "$view" | grep entityType | cut -d ':' -f2-)" && EURATTRENTTTYPE=$VALUE
        prompt "id" "$([[ "$isListEl" -eq 0 ]] && echo "$view" | grep id | cut -d ':' -f2-)" && EURATTRID=$VALUE
        prompt "name" "$([[ "$isListEl" -eq 0 ]] && echo "$view" | grep name | cut -d ':' -f2-)" && EURATTRNAME=$VALUE
        prompt "propertyName" "$([[ "$isListEl" -eq 0 ]] && echo "$view" | grep propertyName | cut -d ':' -f2-)" && EURATTRPROPNAME=$VALUE
        prompt "syntax" "$([[ "$isListEl" -eq 0 ]] && echo "$view" | grep syntax | cut -d ':' -f2-)" && EURATTRSYNTAX=$VALUE
        ATTR=$(printf "
    - defaultValue: $EURATTRDEF
      entityType: $EURATTRENTTTYPE
      id: $EURATTRID
      name: $EURATTRNAME
      propertyName: $EURATTRPROPNAME
      syntax: $EURATTRSYNTAX
")

        EURATTRIBUTES+="$ATTR"
        read -r -p "stop? [n] " STOP
        case "$STOP" in
            y|yes|Y|Yes|YES)
                break
                ;;
			*)
				continue
				;;
        esac
        [[ "$isListEl" -eq 0 ]] && attrstart=$((attrend+1)) # stop incrementing if list is over
        [[ "$isListEl" -eq 0 ]] && attrend=$((attrstart+5))
    done
} #get_attribute_config

do_external_registry() {
	get_extreg_type
	prompt_not_empty "User registry realm" "$(get_existing_value realm)" && ERREALM=$VALUE
	get_truefalse "Should case be ignored" "$(get_existing_value ignoreCase)" && ERIGNORECASE=$TFVALUE
	get_truefalse "Should ssl be used" "$(get_existing_value useSSL)" && ERUSESSL=$TFVALUE
	get_host "External Registry" "registryHost" && ERHOST=$HOST
	get_port "External Registry" "registryPort" 389 65535 && ERPORT=$PORT
	prompt_not_empty "Base DN for user searches" "$(get_existing_value baseDN)" && ERBASEDN=$VALUE
	prompt_not_empty "User DN for Registry Connection" "$(get_existing_value bindDN)" && ERBINDDN=$VALUE
	pw_prompt "User DN Password:" && ERBINDPASS=$PWVALUE
	pw_prompt "isimsystem user Password:" && ERIMSYSPASS=$PWVALUE
	get_filter_props
        get_attribute_config
} #do_external_registry

do_smtp_mail() {
    get_truefalse "Do you want to enable OAuth mail configuration? If true then Please use Additional Mail Properties in Admin Console to setup OAuth Configuration" "$(get_existing_value authentication.type)" && OAUTH_ENABLED=$TFVALUE
    if [[ "$OAUTH_ENABLED" = "true" ]]; then
        AUTH_TYPE="oauth"
    else
        AUTH_TYPE="basic"
        printf "\nURL to IVIG Login, example: https://<host_name>:<port_number>"
        prompt_not_empty "BaseURL" "$(get_existing_value baseurl)" && MAILBASEURL=$VALUE
        get_host "SMTP Mail host" "host" && MAILHOST=$HOST
        prompt_not_empty "Email From" "$(get_existing_value from)" && MAILFROM=$VALUE
        get_port "SMTP Mail Port" "smtp.port" 25 65535 && MAILPORT=$PORT
        get_truefalse "Enable StartTLS with Mail Server" "$(get_existing_value smtp.starttls.enable)" && MAILTLS=$TFVALUE
        get_truefalse "Enable Authentication with Mail Server" "$(get_existing_value smtp.auth)" && MAILAUTH=$TFVALUE
        if [[ "$MAILAUTH" = "true" ]]; then
            prompt_not_empty "Mail Username" "$(get_existing_value smtp.auth.user)" && MAILUSER=$VALUE
            pw_prompt "Mail user Password:" required && MAILPASSWORD=$PWVALUE
        fi
    fi
    
    printf "\n--- Email-based Approval Configuration ---\n"    
    get_truefalse "Do you want to enable Email-based Approval monitoring?" "$(get_existing_value monitoring.enabled)" && EMAIL_APPROVAL_ENABLED=$TFVALUE
    if [[ "$EMAIL_APPROVAL_ENABLED" = "true" ]]; then
        printf "\nConfiguring Office365 email approval monitoring...\n"
        printf "You will need Azure AD App Registration details.\n\n"
        
        prompt_not_empty "Exchange User Principal Name (mailbox to monitor)" "$(get_existing_value user.id)" && OFFICE365_USER=$VALUE
        prompt_not_empty "Azure AD Tenant ID" "$(get_existing_value tenant.id)" && OFFICE365_TENANT=$VALUE
        prompt_not_empty "Azure AD Client ID (Application ID)" "$(get_existing_value client.id)" && OFFICE365_CLIENT_ID=$VALUE
        prompt_not_empty "Azure AD Client Secret" "$(get_existing_value client.secret)" && OFFICE365_CLIENT_SECRET=$VALUE
        prompt_not_empty "Email scanning interval configuration in minutes (default: 30)" "$(get_existing_value scan.interval.minutes)" && OFFICE365_SCAN_INTERVAL=$VALUE

    fi
} #do_smtp_mail

# Ensure EMAIL_APPROVAL_ENABLED is always set to a valid boolean
if [[ "$MAILREG" != "true" ]]; then
    EMAIL_APPROVAL_ENABLED="false"
fi

do_ilmt_server() {
	printf "\nThe IBM License Service is a convenient way to monitor license usage in a\n"
	printf "kubernetes environment. If you install it prior to IVIG, everything will be\n"
	printf "configured automatically.  If you install afterwards, you will also need to run\n"
	printf "bin/util/getILMTInfo.sh and restart the ISVGIM pod for it to sync.\n"
	printf "\nFor more details, refer to: https://www.ibm.com/docs/en/cloud-paks/foundational-services/3.23?topic=platforms-tracking-license-usage-stand-alone-containerized-software\n"

	if [[ $OFFLINE -eq 0 ]]; then
		sleep 3
		printf "\nAttempting to download the installation script...\n"

		# Check for download tool
		wget -V > /dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			CMD=wget
		else
			curl -V > /dev/null 2>&1
			if [[ $? -eq 0 ]]; then
				CMD="curl -k -o $LICENSE_SCRIPT_NAME -s"
			else
				printf "\nUnable to find wget or curl, cannot download the script.\n"
				offline_ilmt
				return
			fi
		fi

		# Attempt to download the script
		if [[ -n "$CMD" ]]; then
			RESULT=$($CMD "$LICENSE_SCRIPT_LOCATION" 2>&1)
			if [[ $? -ne 0 ]]; then
				printf "\nFailed to download the script. See error below.\n"
				echo "$RESULT"
				offline_ilmt
				return
			else
				chmod +x "${LICENSE_SCRIPT_NAME}"
			fi
		fi

		printf "\nSuccessfully retrieved %s.\n" "$LICENSE_SCRIPT_NAME"
		printf "Install the IBM License Service by running bin/%s." "$LICENSE_SCRIPT_NAME"
	else
		offline_ilmt
	fi
} #do_ilmt_server

offline_ilmt() {
	printf "\nPlease retrieve the installation script from: %s\n" "$LICENSE_SCRIPT_LOCATION"
	printf "If this machine lacks Internet access, please refer to the offline instructions:\n"
	printf "https://www.ibm.com/docs/en/cloud-paks/foundational-services/3.23?topic=software-offline-installation\n"
} #offline_ilmt

write_config_yaml() {
	mv "$CFGFILE" "$CFGBAK"
	cat <<EOF > "$CFGFILE"
version: "24.12"
general:
  install:
    namespace: $NAMESPACE
    clusterUrl: $CLUSTERURL
    storageclass: $STORAGECLASS
    installType: $INSTALLTYPE
    licenseType: $LICTYPE
    licenseExternalObjectclass: $LICOBJC
    licenseExternalAttribute: $LICATTR
    waitTimeout: $WAITTIMEOUT
    useExternalRegistry: $EXTREG
    useSMTPMail: $MAILREG
    deployLdap: $DEPLOYLDAP
    deployLdapHA: $DEPLOYLDAPHA
    enableAuditLog: $AUDITLOG
    deployDb: $DEPLOYDB
    deployDbHA: $DEPLOYDBHA
    createTablespace: $CREATETABLESPACE
    deployIsvdi: $DEPLOYISVDI
    mqSharePwd: $MQSHARE
    mqAdminPwd: $MQADMIN
    customRepoUser: $CRUSER
    customRepoPwd: $CRPWD
    customRepoUrl: $CRURL
  license:
    activationKey: $ACTKEY
    accepted: $LICENSE
    ldapKey: $LDAPKEY
    isvdiKey: $ISVDIKEY
    riskKey: $RISKKEY
db:
  user: $DBUSER
  password: $DBPASS
  dbtype: $DBTYPE
  ip: $DBHOST
  port: $DBPORT
  name: $DBNAME
  admin: $DBADM
  adminPwd: $DBADMPASS
  isOracleServiceName: $ISORACLESERVICENAME
  security.protocol: $DBSSL
  tablespace.location.data: $DBTBLDATA
  tablespace.location.indexes: $DBTBLIDX
ldap:
  security.principal: $LDAPUSER
  security.credentials: $LDAPPASS
  defaulttenant.id: $TENANT
  organization.name: $ORGNAME
  ldapserver.ip: $LDAPHOST
  ldapserver.port: $LDAPPORT
  ldapserver.root: $SUFFIX
  security.protocol: $LDAPSSL
mail:
  authentication.type: $AUTH_TYPE
  baseurl: $MAILBASEURL
  from: $MAILFROM
  host: $MAILHOST
  smtp.port: $MAILPORT
  smtp.starttls.enable: $MAILTLS
  smtp.auth: $MAILAUTH
  smtp.auth.user: $MAILUSER
  smtp.auth.password: $MAILPASSWORD
office365:
  monitoring.enabled: $EMAIL_APPROVAL_ENABLED
  user.id: $OFFICE365_USER
  tenant.id: $OFFICE365_TENANT
  client.id: $OFFICE365_CLIENT_ID
  client.secret: $OFFICE365_CLIENT_SECRET
  scan.interval.minutes: $OFFICE365_SCAN_INTERVAL
externalRegistry:
  type: $ERTYPE
  realm: $ERREALM
  useSSL: $ERUSESSL
  ignoreCase: $ERIGNORECASE
  registryHost: $ERHOST
  registryPort: $ERPORT
  baseDN: $ERBASEDN
  bindDN: $ERBINDDN
  bindPassword: $ERBINDPASS
  isimsystemPassword: $ERIMSYSPASS
  filterProperties:
    groupFilter: "$ERGRPFILTER"
    groupIdMap: "$ERGRPIDMAP"
    groupMemberIdMap: "$ERGRPMBRMAP"
    userFilter: "$ERUSERFILTER"
    userIdMap: "$ERUSERIDMAP"
  attributeConfiguration:
    attributes: "$EURATTRIBUTES"
server:
  keypass: $KEYPASS
  options:
  - name: libertyMetrics
    enabled: $LMENABLED
    data:
    - name: "userName"
      value: $LMUSER
    - name: "password"
      value: $LMPASS
  flags:
    disableTLSv12: $DISABLETLS12
    enableFIPS: $ENABLEFIPS
  hostname:
EOF

# Now process the lists
if [[ -n $HOSTNAMES ]]; then
	IFS="," read -r -a hosts <<< "$HOSTNAMES"
	for host in "${hosts[@]}"; do
		echo "  - $host" >> "$CFGFILE"
	done
fi

echo "  truststore:" >> "$CFGFILE"
if [[ -n $CACERTS ]]; then
	IFS="," read -r -a certs <<< "$CACERTS"
		for cert in "${certs[@]}"; do
		echo "  - \"$cert\"" >> "$CFGFILE"
	done
fi

echo "  keystore:" >> "$CFGFILE"
if [[ -n $KSCERTS ]]; then
	IFS="," read -r cert key cacert <<< "$KSCERTS"
	echo "  - cert: \"$cert\"" >> "$CFGFILE"
	echo "    key: \"$key\"" >> "$CFGFILE"
	echo "    cacert: \"$cacert\"" >> "$CFGFILE"
fi

echo "" >> "$CFGFILE"
# Remove all spaces on empty lines
$SED 's/:\ $/:/g' "$CFGFILE"
} #write_config_yaml

# Start of main script
printf "##### IVIG Configuration Utility #####\n"

printf "\n--- General Section ---\n"
do_installation
do_license

printf "\n--- LDAP Section ---\n"
do_ldap

printf "\n--- Database Section ---\n"
do_database

if [[ "$EXTREG" = "true" ]]; then
	printf "\n--- External Registry Section ---\n"
	do_external_registry
fi

if [[ "$MAILREG" = "true" ]]; then
	printf "\n--- MAIL Configuration Section ---\n"
	do_smtp_mail
fi

printf "\n--- Server Section ---\n"
do_server

if [[ "$USEOIDC" = "true" ]]; then
	do_oidc
fi

do_ilmt_server

write_config_yaml
printf "\nConfiguration complete!\n"
