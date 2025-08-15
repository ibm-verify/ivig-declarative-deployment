#!/bin/bash

CONF="../config/config.yaml"
DBPROPS="../data/enRoleDatabase.properties"
LDAPPROPS="../data/enRoleLDAPConnection.properties"
MAILPROPS="../data/enRoleMail.properties"
AUTHPROPS="../data/enRoleAuthentication.properties"
ERPROPS="../data/enRole.properties"
ISVDCRED="055-secret-isvdcred"
MQCRED="060-secret-mqcreds"
PGCREDS="065-secret-pgcreds"
OIDCCRED="070-secret-oidccreds"

print_help() {
	echo "Name: changePasswords.sh"
	echo "When to run: Whenever a data tier password needs to be changed."
	echo "Description:"
	echo "   Passwords for endpoints the ISVG IM server needs to connect to need to"
	echo "   be changed periodically.  This utility will update the necessary"
	echo "   fields for the change to take effect.  Pods must also be restarted."
	echo "Options:"
	echo "   db - change the database password"
	echo "   ldap - change the LDAP password"
	echo "   mail - set/change the MAIL credentials"
	echo "   isimsystem - set/change the isimsystem user credentials"
	echo "   eurbind - set/change the EUR bind user credentials"
	echo "   mq - change the MQ passwords"
	echo "   oidc - change the OIDC credentials"
	echo "   customrepo - change the custom image repository credentials"
	echo "Example usage:"
	echo "   $ ./changePasswords.sh ldap"
	echo ""
	exit 0
} #print_help

cd $(dirname ${BASH_SOURCE[0]})
NS=$(./sys/getNamespace.sh)
SED=$(./sys/sedCheck.sh)
kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

if [ "x$1" = "x" ]; then
	echo "Must specify one of: db, ldap, mq, oidc, mail, isimsystem, eurbind, customrepo"
	exit 1
fi

POD=$($kubectl -n $NS get pods | grep isvgim-0 | awk '{ print $1 }')
if [ "x$POD" = "x" ]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: $kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

add_or_replace() {
    file_name=$1
    prop_name=$2
    prop_value=$3
    prop=$(grep $prop_name $file_name)
    if [ "x$prop" = "x" ]; then
        echo "${prop_name}=${prop_value}" >> ${file_name}
        return
    fi
    $SED "s;\(${prop_name}=\).*\$;\1${prop_value};" ${file_name}
}

prompt_not_empty() {
	VALUE=""
	while [ "x$VALUE" = "x" ]; do
		prompt "$1" "$2"
		if [ "x$VALUE" = "x" ]; then
			printf "\nValue cannot be empty.\n\n"
		fi
	done
} #prompt_not_empty

prompt() {
	printf "\n"
	DVALUE="$2"
	read -p "${1} [$DVALUE]: " VALUE
	VALUE=${VALUE:-$DVALUE}
} #prompt

pw_prompt() {
	PWVALUE="1"
	PWVALUE2=""
	printf "\n"
	while [ "x$PWVALUE" != "x$PWVALUE2" ]; do
		read -sp "$1 " PWVALUE
		printf "\n"
		read -sp "Re-enter $1 " PWVALUE2
		printf "\n"
		if [ "x$PWVALUE" != "x$PWVALUE2" ]; then
			printf "Passwords don't match.\n\n"
		fi
	done
} #pw_prompt

change_customrepo() {
	printf "\nChanging credentials for custom image repository\n"
	prompt_not_empty "Repository URL" "" && URL=$VALUE
	prompt_not_empty "User" "" && USER=$VALUE
	pw_prompt "Password: " && PWD=$PWVALUE
	$kubectl -n $NS delete secret regcred --ignore-not-found
	$kubectl create secret docker-registry regcred --docker-server="$URL" --docker-username="$USER" --docker-password="$PWD" --docker-email="$USER" --namespace="$NS"
} #change_customrepo


change_db() {
	# Check for type and location of DB and encryption
	INTERNAL=0
	DBTYPE=$(grep database.db.type $DBPROPS | cut -d '=' -f 2)
	if [ "$DBTYPE" = "POSTGRESQL" ]; then
		$kubectl -n $NS get deployments | grep -q postgres > /dev/null 2>&1
		if [ $(echo $?) -eq 0 ]; then
			INTERNAL=1
		fi
	fi
	ENCRYPTED=$(grep enrole.password.database.encrypted $ERPROPS | cut -d '=' -f 2)

	# Prompt for DB credentials
	USER=$(grep database.db.user $DBPROPS | cut -d '=' -f 2)
	prompt_not_empty "DB User" $USER && USER=$VALUE
	pw_prompt "$USER Password:" && PASS=$PWVALUE

	# Store them in properties and if needed, secret
	if [ $INTERNAL -eq 1 ]; then
		ADMUSER=$(grep "database.db.admin=" $DBPROPS | cut -d '=' -f 2)
		pw_prompt "$ADMUSER Password:" && ADMPASS=$PWVALUE
		$kubectl create secret generic pgcreds --from-literal=pguser=$USER --from-literal=pgpass=$PASS --from-literal=admpass=$ADMPASS --from-literal=admuser=$ADMUSER --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > ../helm/templates/${PGCREDS}.yaml
		./updateYaml.sh ${PGCREDS}.yaml
		ADMPASS=$($kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh encrypt $ADMPASS")
		$SED "s;\(database.db.adminPwd=\).*$;\1$ADMPASS;" $DBPROPS
	fi

	$SED "s/\(database.db.user=\).*$/\1$USER/" $DBPROPS
	if [ "x$ENCRYPTED" = "xtrue" ]; then
		PASS=$($kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh encrypt $PASS")
	fi
	$SED "s;\(database.db.password=\).*$;\1$PASS;" $DBPROPS
	./createConfigs.sh
	if [ $INTERNAL -eq 1 ]; then
		echo "Please restart the ISVGIM and Postgres pods for the change to take effect."
	else
		echo "Please restart the ISVGIM pod for the change to take effect."
	fi
} #change_db

change_ldap() {
	# Check for location of LDAP and encryption
	INTERNAL=0
	$kubectl -n $NS get deployments | grep -q isvd-replica > /dev/null 2>&1
	if [ $(echo $?) -eq 0 ]; then
		INTERNAL=1
	fi
	ENCRYPTED=$(grep enrole.password.ldap.encrypted $ERPROPS | cut -d '=' -f 2)

	# Prompt for LDAP credentials
	USER=$(grep security.principal $LDAPPROPS | cut -d '=' -f 2-)
	prompt_not_empty "LDAP User" $USER && USER=$VALUE
	pw_prompt "$USER Password:" && PASS=$PWVALUE

	# Store them in properties and if needed, secret
	if [ $INTERNAL -eq 1 ]; then
		$kubectl create secret generic isvdcred --from-literal=adminpwd=$PASS --from-literal=admindn=$USER --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > ../helm/templates/${ISVDCRED}.yaml
		./updateYaml.sh ${ISVDCRED}.yaml
	fi

	$SED "s/\(java.naming.security.principal=\).*$/\1$USER/" $LDAPPROPS
	if [ "x$ENCRYPTED" = "xtrue" ]; then
		PASS=$($kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh encrypt $PASS")
	fi
	$SED "s;\(java.naming.security.credentials=\).*$;\1$PASS;" $LDAPPROPS
	./createConfigs.sh
	if [ $INTERNAL -eq 1 ]; then
		echo "Please restart the ISVGIM and LDAP pods for the change to take effect."
	else
		echo "Please restart the ISVGIM pod for the change to take effect."
	fi
} #change_ldap

change_mail(){
	# Prompt for Mail credentials
	USER=$(grep mail.smtp.auth.user= $MAILPROPS | cut -d '=' -f 2)
	pw_prompt "$USER Password:" && PASS=$PWVALUE
	PASS=$($kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh encrypt $PASS")
	$SED "s|mail.smtp.auth.password=.*|mail.smtp.auth.password=$PASS|" $MAILPROPS
	./createConfigs.sh
	echo "Please restart the ISVGIM pod for the change to take effect."
}

change_isimsystem() {
	# Prompt for isimsystem credentials
	pw_prompt "isimsystem Password:" && PASS=$PWVALUE

	# Store them in properties and if needed, secret
        PASS=$($kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh encrypt $PASS")
	$SED "s;\(enrole.appServer.ejbuser.credentials=\).*$;\1$PASS;" $ERPROPS
	./createConfigs.sh
        echo "Please restart the ISVGIM pod for the change to take effect."
} #change_isimsystem

change_eurbind() {
	# Prompt for EUR bind credentials
	USER=$(grep enrole.authentication.registry.bindDN $AUTHPROPS | cut -d '=' -f 2-)
	prompt_not_empty "Bind DN" $USER && USER=$VALUE
	pw_prompt "$USER Password:" && PASS=$PWVALUE

	# Store them in properties and if needed, secret
        PASS=$($kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/opt/ibm/wlp/bin/securityUtility encode --encoding=aes $PASS")
        add_or_replace $AUTHPROPS "enrole.authentication.registry.bindPassword" $PASS
	./createConfigs.sh
        echo "Please restart the ISVGIM pod for the change to take effect."
} #change_eurbind

change_mq() {
	pw_prompt "MQ Local Password:" && MQLOCAL=$PWVALUE
	pw_prompt "MQ Shared Password:" && MQSHARE=$PWVALUE
	pw_prompt "MQ Admin Password:" && MQADMIN=$PWVALUE
	$kubectl create secret generic mqcreds --from-literal=mqlocal=$MQLOCAL --from-literal=mqshare=$MQSHARE --from-literal=mqadmin=$MQADMIN --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > ../helm/templates/${MQCRED}.yaml
	./updateYaml.sh ${MQCRED}.yaml
	echo "Please restart the ISVGIM and MQ pods for the change to take effect."
} # change_mq

change_oidc() {
	# Check for any endpoints defined in config.yaml
	OIDC=0
	ENDPOINTS=""
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "x$line" = "xoidc:" ] && [ $OIDC -eq 0 ]; then
			OIDC=1
			continue
		fi
		if [ $OIDC -eq 1 ]; then
			if [[ $line == "  "*":" ]]; then
				ENDPOINTS="$ENDPOINTS `echo $line | cut -d ':' -f 1`"
			fi
		fi
		if [ $OIDC -eq 1 ] && [[ $line != "  "* ]]; then
			OIDC=0
			break
		fi
	done < $CONF

	if [ "x$ENDPOINTS" = "x" ]; then
		echo "No OIDC endpoints found in config.yaml"
		return
	fi

	./createConfigs.sh setup

	validate_yaml

	for ENDPOINT in $ENDPOINTS; do
		echo "Please provide the credentials for the $ENDPOINT provider"
		prompt_not_empty "ClientID" ""
		declare ${ENDPOINT}user=$VALUE
		pw_prompt "Client Secret:"
		declare ${ENDPOINT}secret=$PWVALUE
		echo ""
	done

	$kubectl create secret generic oidccreds --from-literal=restuser=$restuser --from-literal=restsecret=$restsecret --from-literal=adminConsoleuser=$adminConsoleuser --from-literal=adminConsolesecret=$adminConsolesecret --from-literal=iscuser=$iscuser --from-literal=iscsecret=$iscsecret --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > ../helm/templates/${OIDCCRED}.yaml

	./updateYaml.sh ${OIDCCRED}.yaml

	echo "Please restart the ISVGIM pods for the change to take effect."
} #change_oidc

# Before prompting for passwords, verify the new OIDC yaml will parse ok
validate_yaml() {
	printf "\nVerifying OIDC yaml definition parses successfully...\n"
	printf "Please wait while the files are mounted into the container.\n\n"
	sleep 30
	$kubectl -n $NS exec $POD -c isvgim -- /bin/bash -c "/work/checkYaml.sh"
	if [ $(echo $?) -ne 0 ]; then
		printf "\nYAML parsing failed!\n"
		printf "Please correct your OIDC section in config.yaml and try again.\n"
		exit 2
	fi
	printf "\nOIDC yaml was successfully parsed.\n\n"
} #validate_yaml

case $(awk -vs1="$1" 'BEGIN { print tolower(s1) }') in
	db)
		change_db
		;;
	ldap)
		change_ldap
		;;
	mail)
		change_mail
		;;
	mq)
		change_mq
		;;
	oidc)
		change_oidc
		;;
	isimsystem)
		change_isimsystem
		;;
	eurbind)
		change_eurbind
		;;
	customrepo)
		change_customrepo
		;;
	--help|-help)
		print_help
		;;
esac
