#!/bin/bash

YMLFILES="006-serviceaccount-ivigrisk 064-secret-ivigrisk 090-pvc-riskengine 300-statefulset-isvgim 415-job-riskstart"
APPCONF="../config/analytics/store/config/applicationConfig.properties"
INFCONF="../config/analytics/store/config/infrastructureConfig.properties"
DBPROPS="../data/enRoleDatabase.properties"
ERPROPS="../data/enRole.properties"
APROPS="../data/enRoleAnalytics.properties"
VALUESYAML="../helm/values.yaml"
RISKCREDS="064-secret-ivigrisk"
RISKKEY=$1

print_help() {
		echo "Name: setupAnalytics.sh"
		echo "When to run: When upgrading to the Enterprise Analytics license."
		echo "Description:"
		echo "   Configuration script called automatically during install, and when manually adding Enterprise license."
		echo "   It will deploy the Analytics Risk Engine."
		echo "   All pods must be restarted for the change to take effect."
		echo "Options:"
		echo "   <license_key> provide the Enterprise Analytics license key you received."
		echo "Example usage:"
		echo "   $ ./setupAnalytics.sh <license_key>"
		echo ""
		exit 0
} #print_help

get_prop() {
	VAL=$(grep "$1" "$2" | cut -d '=' -f 2)
	echo "$VAL"
}

# Pass filename, first signpost, addiitional signposts using ; delimeter
rowSearch() {
	rowSearchImpl "$1" 0 "$2" "$3"
} # rowSearch

# The recursive function needs to know the current line number as well
rowSearchImpl() {
	fileName="$1"
	LINES=$(cat "$fileName")
	oldLineNum=$2
	searchValue="$3"
	lineNum=0
	FLAG=0
	while IFS= read -r LINE; do
		lineNum=$((lineNum + 1))
		if [[ $lineNum -lt $oldLineNum ]]; then
			continue
		fi
		if [[ $FLAG -eq 1 ]]; then
			break
		fi
		# Ignore comments
		grep "^ *#" <<< "$LINE" > /dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			continue
		fi
		grep "$searchValue" <<< "$LINE" > /dev/null 2>&1
		if [[ $? -eq 0 ]]; then
			if [[ -z "$4" ]]; then
				FLAG=1
				echo "$lineNum"
				break
			else
				newArg=$(echo "$4" | cut -d ';' -f 1)
				grep ";" <<< "$4" > /dev/null 2>&1
				if [[ $? -eq 0 ]]; then
					newRest=$(echo "$4" | cut -d ';' -f 2-)
				else
					newRest=""
				fi
				rowSearchImpl "$fileName" "$lineNum" "$newArg" "$newRest"
			fi
		fi
	done <<< "$LINES"
} # rowSearchImpl

check_config_values() {
	if [[ -z "$DBTYPE" ]]; then
		DBTYPE=$(get_prop database.db.type "$DBPROPS" | awk '{ print tolower($1) }')
	fi
	URL=$(get_prop database.jdbc.driverUrl "$DBPROPS")
	USE_SID="false"
	if [[ "$DBTYPE" == "oracle" ]]; then
	        CLEAN_URL=$(grep driverUrl "$DBPROPS" | cut -d '=' -f2-)
	        # SSL / DESCRIPTION Format
	        if [[ "$CLEAN_URL" == *"DESCRIPTION="* ]]; then
		      DBHOST=$(echo "$CLEAN_URL" | sed -n 's/.*(HOST=\([^)]*\)).*/\1/p')
		      DBPORT=$(echo "$CLEAN_URL" | sed -n 's/.*(PORT=\([^)]*\)).*/\1/p')

		      if [[ "$CLEAN_URL" == *"SERVICE_NAME="* ]]; then
		           DBNAME=$(echo "$CLEAN_URL" | sed -n 's/.*SERVICE_NAME=\([^)]*\).*/\1/p')
		      else
		           DBNAME=$(echo "$CLEAN_URL" | sed -n 's/.*SID=\([^)]*\).*/\1/p')
				   USE_SID="true"
		      fi
	        else
		      # Non-SSL format
		      if [[ "$CLEAN_URL" == *"@//"* ]]; then
					# Service Name format jdbc:oracle:thin:@//<host>:<port>/<serviceName>
					DBHOST=$(echo "$CLEAN_URL" | cut -d '/' -f 3 | cut -d ':' -f 1)
					DBPORT=$(echo "$CLEAN_URL" | cut -d '/' -f 3 | cut -d ':' -f 2)
					DBNAME=$(echo "$CLEAN_URL" | cut -d '/' -f 4 | cut -d '?' -f 1)
				else
					# SID format jdbc:oracle:thin:@<host>:<port>:<SID>
					DBHOST=$(echo "$CLEAN_URL" | cut -d '@' -f 2 | cut -d ':' -f 1)
					DBPORT=$(echo "$CLEAN_URL" | cut -d '@' -f 2 | cut -d ':' -f 2)
					DBNAME=$(echo "$CLEAN_URL" | cut -d '@' -f 2 | cut -d ':' -f 3)
					USE_SID="true"
				fi
	        fi
        else
	        if [[ -z "$DBHOST" ]]; then
		     DBHOST=$(echo "$URL" | cut -d '/' -f 3 | cut -d ':' -f 1)
	        fi
	        if [[ -z "$DBPORT" ]]; then
		     DBPORT=$(echo "$URL" | cut -d '/' -f 3 | cut -d ':' -f 2)
	        fi
	        if [[ -z "$DBNAME" ]]; then
		     DBNAME=$(echo "$URL" | cut -d '/' -f 4 | cut -d '?' -f 1 | cut -d ':' -f 1)
	        fi
	fi
	if [[ -z "$DBUSER" ]]; then
		DBUSER=$(get_prop database.db.user "$DBPROPS")
	fi
 	if [[ -z "$DBOWNER" ]]; then
		DBOWNER=$(get_prop database.db.owner "$DBPROPS")
	fi
 	if [[ -z "$DBSSL_VALUE" ]]; then
		DBSSL_VALUE=$(get_prop database.db.security.protocol "$DBPROPS")
  		if [[ -z "$DBSSL_VALUE" ]]; then
			DBSSL_VALUE="false"
		elif [[ "$DBSSL_VALUE" = "ssl" ]]; then
			DBSSL_VALUE="true"
		fi
	fi
	if [[ -z "$DBPASS" ]]; then
		PWENC=$(get_prop enrole.password.database.encrypted "$ERPROPS" | awk '{ print tolower($1) }')
		DBPASS=$(get_prop database.db.password "$DBPROPS")
		if [[ "$PWENC" = "true" ]]; then
			DBPASS=$($kubectl -n "$NS" exec isvgim-0 -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh decrypt $DBPASS")
		fi
	fi
	if [[ -z "$MQSHAREPWD" ]]; then
		MQSHAREPWD=$($kubectl -n "$NS" get secret mqcreds -o yaml | grep mqshare: | cut -d ' ' -f 4 | base64 -d)
	fi
} #check_config_values

update_config_values() {
	$SED "s/\(streaming.datasource=\).*$/\1$DBTYPE/" "$APPCONF"
	$SED "s/\(db.servername=\).*$/\1$DBHOST/" "$INFCONF"
	$SED "s/\(db.port=\).*$/\1$DBPORT/" "$INFCONF"
	$SED "s/\(db.database.name=\).*$/\1$DBNAME/" "$INFCONF"
	$SED "s/\(db.username=\).*$/\1$DBUSER/" "$INFCONF"

	# It is required to be uppercase if DBTYPE is DB2 for analytics engine
 	if [[ "$DBTYPE" = "db2" || "$DBTYPE" = "oracle" ]]; then
		DBOWNER=$(echo "$DBOWNER" | awk '{ print toupper($0) }')
  	fi
	# Only update db.service.name if it is already present in INFCONF; otherwise append it
        if grep -q "db.service.name=" "$INFCONF"; then
                # update existing value
                $SED "s/\(db.service.name=\).*$/\1$DBNAME/" "$INFCONF"
        else
                # append in the same key=value format
                printf '\n%s=%s\n' "db.service.name" "$DBNAME" >> "$INFCONF"
        fi
	# Only update db.sid.name if it is already present in INFCONF; otherwise append it
        if grep -q "db.sid.name=" "$INFCONF"; then
                # update existing value
                $SED "s/\(db.sid.name=\).*$/\1$DBNAME/" "$INFCONF"
        else
                # append in the same key=value format
                printf '\n%s=%s\n' "db.sid.name" "$DBNAME" >> "$INFCONF"
        fi
	# Only update db.use.sid if it is already present in INFCONF; otherwise append it
        if grep -q "db.use.sid=" "$INFCONF"; then
                # update existing value
                $SED "s/\(db.use.sid=\).*$/\1$USE_SID/" "$INFCONF"
        else
                # append in the same key=value format
                printf '\n%s=%s\n' "db.use.sid" "$USE_SID" >> "$INFCONF"
        fi
	
 	$SED "s/\(db.schema=\).*$/\1$DBOWNER/" "$INFCONF"
  	$SED "s/\(db.sslEnabled=\).*$/\1$DBSSL_VALUE/" "$INFCONF"

	./getConfig.sh enRoleAnalytics.properties
	$SED "s/\(analytics.enable=\).*$/\1true/" "$APROPS"
} #update_config_values

update_queue_values() {
	# Only update the file if the queues are not already defined
	grep -q sharedAnalyticsRiskInputQueue "$ERPROPS"
	if [[ $? -eq 0 ]]; then
		return
	fi
	LINENUM=$(rowSearch "$ERPROPS" enrole.messaging.managers '.*[^\]$')
	LINE=$(sed "${LINENUM}!d" "$ERPROPS")
	$SED "s/\($LINE\)/\1 \\\\/" "$ERPROPS"
	LINENUM=$((LINENUM+1))
	# Lines entered in reverse order so we don't have to adjust the LINENUM each time
	$SED "${LINENUM}ienrole.messaging.sharedAnalyticsRiskViolationsQueue=sharedAnalyticsRiskViolationsQueue" "$ERPROPS"
	$SED "${LINENUM}ienrole.messaging.sharedAnalyticsRiskOutputQueue=sharedAnalyticsRiskOutputQueue" "$ERPROPS"
	$SED "${LINENUM}ienrole.messaging.sharedAnalyticsRiskInputQueue=sharedAnalyticsRiskInputQueue" "$ERPROPS"
	$SED "${LINENUM}i\\\\tenrole.messaging.sharedAnalyticsRiskViolationsQueue" "$ERPROPS"
	$SED "${LINENUM}i\\\\tenrole.messaging.sharedAnalyticsRiskOutputQueue \\\\" "$ERPROPS"
	$SED "${LINENUM}i\\\\tenrole.messaging.sharedAnalyticsRiskInputQueue \\\\" "$ERPROPS"
} #update_queue_values

create_secret() {
	if [[ "$OFFLINE" != "1" ]]; then
		$kubectl create secret generic riskcreds --from-literal=dbuser="$DBUSER" --from-literal=dbpass="$DBPASS" --from-literal=mqpass="$MQSHAREPWD" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "../helm/templates/${RISKCREDS}.yaml"
		./updateYaml.sh "${RISKCREDS}.yaml"
	else
		echo "Please create your riskcreds secret for your Spark server"
		echo "An example command is: $kubectl -n $NS create secret generic riskcreds --from-literal=dbuser=$DBUSER --from-literal=dbpass=dbuser_pwd --from-literal=mqpass=mqshare_pwd"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
} #create_secret

generate_configs() {
	./createConfigs.sh risk
	RC=$?
	if [[ $RC -ne 0 ]]; then
		echo "Error creating ConfigMap for Enterprise Analytics.  Please review above messages for details"
		exit "$RC"
	else
		if [[ "$OFFLINE" = "1" ]]; then
			echo "Please load yaml/031-config-ivigrisk.yaml"
			read -n 1 -s -r -p "Once loaded, press any key to continue..."
			printf "\n\n"
		fi
	fi

	./createConfigs.sh
	RC=$?
	if [[ $RC -ne 0 ]]; then
		echo "Error creating ConfigMap for data files.  Please review above messages for details"
		exit "$RC"
	else
		if [[ "$OFFLINE" = "1" ]]; then
			echo "Please load yaml/015-config-isvgimdata.yaml"
			read -n 1 -s -r -p "Once loaded, press any key to continue..."
			printf "\n\n"
		fi
	fi

} #generate_configs

# Update annotations on ISVGIM pod
update_annotations() {
	get_pod_name "$NS" isvgim && POD=$REPLY
	LICTYPE=$($kubectl -n "$NS" exec "$POD" -- bash -c "/opt/ibm/java/jre/bin/java -cp /opt/ibm/wlp/usr/servers/defaultServer/apps/EAR_STANDARD.ear/lib/itim_install_1.0.0.jar com.ibm.isvgim.installer.util.KeyChecker $RISKKEY")
	case "$LICTYPE" in
		1) # update with compliance annotation
			PRDID="5a6909cef7c04434814c44642e031a44"
			PRDNAME="IBM Verify Identity Governance Compliance"
			;;
		2) # update with enterprise annotation
			PRDID="b4e21aac6fca426ebbb6927d47cbf635"
			PRDNAME="IBM Verify Identity Governance Enterprise"
			;;
		*) # leave at lifecycle annotation
			;;
	esac
	$SED "s/\(productId: \).*$/\1\"$PRDID\"/" "$VALUESYAML"
	$SED "s/\(productName: \).*$/\1\"$PRDNAME\"/" "$VALUESYAML"
} #update_annotations


deploy() {
	check_config_values
	update_config_values
	update_queue_values
	create_secret
	generate_configs

	./sys/loadEnterpriseKey.sh "$RISKKEY"
	update_annotations

	if [[ "$OFFLINE" != "1" ]]; then
		for FILE in $YMLFILES; do
			./updateYaml.sh "${FILE}.yaml"
		done
	else
		echo "Please load the following files to deploy Analytics:"
		for FILE in $YMLFILES; do
			echo "yaml/${FILE}.yaml"
		done
		printf "\n"
		read -n 1 -s -r -p "Once the risk-start job has started, press any key to continue..."
		printf "\n\n"
	fi
} #deploy


# Start of main script
CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	exit "$RC"
fi

get_sed_cmd && SED=$REPLY
get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

if [[ -z "$1" ]]; then
	print_help
fi

case $(awk -vs1="$1" 'BEGIN { print tolower(s1) }') in
	--help|-help)
		print_help
		;;
	*)
		deploy
		;;
esac
