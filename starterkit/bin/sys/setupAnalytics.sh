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
	VAL=$(grep $1 $2 | cut -d '=' -f 2)
	echo "$VAL"
}

# Pass filename, first signpost, addiitional signposts using ; delimeter
rowSearch() {
	rowSearchImpl "$1" 0 "$2" "$3"
} # rowSearch

# The recursive function needs to know the current line number as well
rowSearchImpl() {
	fileName="$1"
	LINES=$(cat $fileName)
	oldLineNum=$2
	searchValue="$3"
	lineNum=0
	FLAG=0
	while IFS= read -r LINE; do
		lineNum=$(($lineNum + 1))
		if [ $lineNum -lt $oldLineNum ]; then
			continue
		fi
		if [ $FLAG -eq 1 ]; then
			break
		fi
		# Ignore comments
		grep "^ *#" <<< $LINE > /dev/null 2>&1
		if [ $(echo $?) -eq 0 ]; then
			continue
		fi
		grep "$searchValue" <<< $LINE > /dev/null 2>&1
		if [ $(echo $?) -eq 0 ]; then
			if [ "x$4" = "x" ]; then
				FLAG=1
				echo $lineNum
				break
			else
				newArg=$(echo $4 | cut -d ';' -f 1)
				grep ";" <<< $4 > /dev/null 2>&1
				if [ $(echo $?) -eq 0 ]; then
					newRest=$(echo $4 | cut -d ';' -f 2-)
				else
					newRest=""
				fi
				rowSearchImpl "$fileName" $lineNum "$newArg" "$newRest"
			fi
		fi
	done <<< "$LINES"
} # rowSearchImpl

check_config_values() {
	if [ "x$DBTYPE" = "x" ]; then
		DBTYPE=$(get_prop database.db.type $DBPROPS | awk '{ print tolower($1) }')
	fi
	URL=$(get_prop database.jdbc.driverUrl $DBPROPS)
	if [ "x$DBHOST" = "x" ]; then
		DBHOST=$(echo $URL | cut -d '/' -f 3 | cut -d ':' -f 1)
	fi
	if [ "x$DBPORT" = "x" ]; then
		DBPORT=$(echo $URL | cut -d '/' -f 3 | cut -d ':' -f 2)
	fi
	if [ "x$DBNAME" = "x" ]; then
		DBNAME=$(echo $URL | cut -d '/' -f 4 | cut -d '?' -f 1 | cut -d ':' -f 1)
	fi
	if [ "x$DBUSER" = "x" ]; then
		DBUSER=$(get_prop database.db.user $DBPROPS)
	fi
 	if [ "x$DBOWNER" = "x" ]; then
		DBOWNER=$(get_prop database.db.owner $DBPROPS)
	fi
 	if [ "x$DBSSL_VALUE" = "x" ]; then
		DBSSL_VALUE=$(get_prop database.db.security.protocol $DBPROPS)
  		if [ -z "$DBSSL_VALUE" ]; then
			DBSSL_VALUE="false"
		elif [ "$DBSSL_VALUE" = "ssl" ]; then
			DBSSL_VALUE="true"
		fi
	fi
	if [ "x$DBPASS" = "x" ]; then
		PWENC=$(get_prop enrole.password.database.encrypted $ERPROPS | awk '{ print tolower($1) }')
		DBPASS=$(get_prop database.db.password $DBPROPS)
		if [ "$PWENC" = "true" ]; then
			DBPASS=$($kubectl -n $NS exec isvgim-0 -c isvgim -- /bin/bash -c "/work/encryptionHelper.sh decrypt $DBPASS")
		fi
	fi
	if [ "x$MQSHAREPWD" = "x" ]; then
		MQSHAREPWD=$($kubectl -n $NS get secret mqcreds -o yaml | grep mqshare: | cut -d ' ' -f 4 | base64 -d)
	fi
} #check_config_values

update_config_values() {
	$SED "s/\(streaming.datasource=\).*$/\1$DBTYPE/" $APPCONF
	$SED "s/\(db.servername=\).*$/\1$DBHOST/" "$INFCONF"
	$SED "s/\(db.port=\).*$/\1$DBPORT/" "$INFCONF"
	$SED "s/\(db.database.name=\).*$/\1$DBNAME/" "$INFCONF"
	$SED "s/\(db.username=\).*$/\1$DBUSER/" "$INFCONF"

	# It is required to be uppercase if DBTYPE is DB2 for analytics engine
 	if [ "x$DBTYPE" = "xdb2" ]; then
		DBOWNER=$(echo "$DBOWNER" | awk '{ print toupper($0) }')
  	fi
 	$SED "s/\(db.schema=\).*$/\1$DBOWNER/" "$INFCONF"
  	$SED "s/\(db.sslEnabled=\).*$/\1$DBSSL_VALUE/" "$INFCONF"

	./getConfig.sh enRoleAnalytics.properties
	$SED "s/\(analytics.enable=\).*$/\1true/" $APROPS
} #update_config_values

update_queue_values() {
	# Only update the file if the queues are not already defined
	grep -q sharedAnalyticsRiskInputQueue $ERPROPS
	if [ $? -eq 0 ]; then
		return
	fi
	LINENUM=$(rowSearch $ERPROPS enrole.messaging.managers '.*[^\]$')
	LINE=$(sed "${LINENUM}!d" $ERPROPS)
	$SED "s/\($LINE\)/\1 \\\\/" $ERPROPS
	LINENUM=$(($LINENUM+1))
	# Lines entered in reverse order so we don't have to adjust the LINENUM each time
	$SED "${LINENUM}ienrole.messaging.sharedAnalyticsRiskViolationsQueue=sharedAnalyticsRiskViolationsQueue" $ERPROPS
	$SED "${LINENUM}ienrole.messaging.sharedAnalyticsRiskOutputQueue=sharedAnalyticsRiskOutputQueue" $ERPROPS
	$SED "${LINENUM}ienrole.messaging.sharedAnalyticsRiskInputQueue=sharedAnalyticsRiskInputQueue" $ERPROPS
	$SED "${LINENUM}i\\\\tenrole.messaging.sharedAnalyticsRiskViolationsQueue" $ERPROPS
	$SED "${LINENUM}i\\\\tenrole.messaging.sharedAnalyticsRiskOutputQueue \\\\" $ERPROPS
	$SED "${LINENUM}i\\\\tenrole.messaging.sharedAnalyticsRiskInputQueue \\\\" $ERPROPS
} #update_queue_values

create_secret() {
	if [ "x$OFFLINE" != "x1" ]; then
		$kubectl create secret generic riskcreds --from-literal=dbuser=$DBUSER --from-literal=dbpass=$DBPASS --from-literal=mqpass=$MQSHAREPWD --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > ../helm/templates/${RISKCREDS}.yaml
		./updateYaml.sh ${RISKCREDS}.yaml
	else
		echo "Please create your riskcreds secret for your Spark server"
		echo "An example command is: $kubectl -n $NS create secret generic riskcreds --from-literal=dbuser=$DBUSER --from-literal=dbpass=dbuser_pwd --from-literal=mqpass=mqshare_pwd"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
} #create_secret

generate_configs() {
	./createConfigs.sh risk
	RC=$(echo $?)
	if [ $RC -ne 0 ]; then
		echo "Error creating ConfigMap for Enterprise Analytics.  Please review above messages for details"
		exit $RC
	else
		if [ "x$OFFLINE" = "x1" ]; then
			echo "Please load yaml/031-config-ivigrisk.yaml"
			read -n 1 -s -r -p "Once loaded, press any key to continue..."
			printf "\n\n"
		fi
	fi

	./createConfigs.sh
	RC=$(echo $?)
	if [ $RC -ne 0 ]; then
		echo "Error creating ConfigMap for data files.  Please review above messages for details"
		exit $RC
	else
		if [ "x$OFFLINE" = "x1" ]; then
			echo "Please load yaml/015-config-isvgimdata.yaml"
			read -n 1 -s -r -p "Once loaded, press any key to continue..."
			printf "\n\n"
		fi
	fi

} #generate_configs

# Update annotations on ISVGIM pod
update_annotations() {
	POD=$($kubectl -n $NS get pods | grep isvgim | grep Running | awk '{ print $1 }')
	LICTYPE=$($kubectl -n $NS exec $POD -- bash -c "/opt/ibm/java/jre/bin/java -cp /opt/ibm/wlp/usr/servers/defaultServer/apps/EAR_STANDARD.ear/lib/itim_install_1.0.0.jar com.ibm.isvgim.installer.util.KeyChecker $RISKKEY")
	case $LICTYPE in
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
	$SED "s/\(productId: \).*$/\1\"$PRDID\"/" $VALUESYAML
	$SED "s/\(productName: \).*$/\1\"$PRDNAME\"/" $VALUESYAML
} #update_annotations


deploy() {
	check_config_values
	update_config_values
	update_queue_values
	create_secret
	generate_configs

	./sys/loadEnterpriseKey.sh $RISKKEY
	update_annotations

	if [ "x$OFFLINE" != "x1" ]; then
		for FILE in $YMLFILES; do
			./updateYaml.sh ${FILE}.yaml
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
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

kubectl=$(./sys/preReqCheck.sh)
RC=($echo $?)
if [ $RC -ne 0 ]; then
	exit $RC
fi

SED=$(./sys/sedCheck.sh)

NS=$(./sys/getNamespace.sh)
if [ $(echo $?) -ne 0 ]; then
	echo "Unable to determine namespace in use from values.yaml file"
	exit 7
fi

if [ "x$1" = "x" ]; then
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
