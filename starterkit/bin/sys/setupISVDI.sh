#!/bin/bash

YMLFILES="045-config-adapters 085-pvc-isvdi 135-service-isvdi 225-deployment-isvdi"
CERTDIR="../config/certs"
CONF="../config/config.yaml"
ISVDICONF="../config/adapters/isvdi_config.yaml"
EXT1="key crt csr"
EXT2="key crt srl"
DEPLOYMENT="isvdi"


print_help() {
        echo "Name: setupISVDI.sh"
        echo "When to run: When creating a new ISVDI Disaptcher cluster."
        echo "Description:"
        echo "   Configuration script called automatically during install, and when manually adding ISVDI clusters."
        echo "   It will deploy the ISVDI server running the RMI Dispatcher for adapters. When deploying a new cluster,"
	echo "   you must specify a name for the deployment."
	echo "Options:"
	echo "   --install  DO NOT USE, ONLY for new installations by the installer"
	echo "   --deploy deployment_name"
        echo "Example usage:"
        echo "   $ ./setupISVDI.sh --deploy isvdi-2"
        echo ""
        exit 0
} #print_help

get_truefalse() {
	printf "\n"
	TFVALUE=""
	while [[ -z "$TFVALUE" ]]; do
		read -r -p "$1 (true/false) [$2]? " TFVALUE
		TFVALUE=${TFVALUE:-$2}
		TFVALUE=$(awk '{ print tolower($1) }' <<< "$TFVALUE")
		validate_boolean "$TFVALUE"
		if [[ $? -ne 0 ]]; then
			printf "\nInvalid value. Must be \"true\" or \"false\".\n\n"
			TFVALUE=""
		fi
		
	done
} # get_truefalse

setup_ssl() {
	DNAME=$1
	get_pod_name "$NS" isvgim && POD=$REPLY
	if [[ $POD != isvgimconfig* ]]; then
		CONTAINER="-c isvgim"
	fi
	if [[ -f $CERTDIR/isvgimRootCA.key ]]; then
		for EXT in $EXT2; do
			$kubectl -n "$NS" $CONTAINER cp "$CERTDIR/isvgimRootCA.$EXT" "$POD":"/work/isvgimRootCA.$EXT"
		done
	fi

	$kubectl -n "$NS" exec $CONTAINER "$POD" -- /work/certificateUtil.sh "$DNAME"
	if [[ $? -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Unable to create certificates in isvgim pod"
		fi
		exit 24
	fi

	for FILE in $DNAME isvgimRootCA; do
		if [[ $FILE = isvgimRootCA ]]; then
			EXTS=$EXT2
		else
			EXTS=$EXT1
		fi
		for EXT in $EXTS; do
			$kubectl -n "$NS" $CONTAINER cp "$POD":"/work/${FILE}.${EXT}" "${CERTDIR}/${FILE}.${EXT}" > /dev/null 2>&1
		done
	done

	# Combine cert and key for ISVDI consumption
	for FILE in $DNAME; do
		cat "$CERTDIR/${FILE}.crt" "$CERTDIR/${FILE}.key" > "$CERTDIR/${FILE}.pem"
	done

	# If the rootCA isn't already trusted, add it
	RESULT=$(grep isvgimRootCA.crt "$CONF")
	if [[ $? -ne 0 ]]; then
		LINE=$(grep -n truststore: "$CONF" | cut -d ':' -f 1)
		LINE=$((LINE+1))
		$SED "${LINE}i \ \ - \"@isvgimRootCA.crt\"" "$CONF"
	fi

	# Generate configmap for certs
	./createConfigs.sh isvdi
	RC=$?
	if [[ $RC -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Error creating ConfigMap for adapter dispatcher.  Please review above messages for details"
		fi
		exit "$RC"
	fi
} #setup_ssl

setup_license() {
	LINENUM=$(grep -n "license:" "$ISVDICONF" | cut -d ':' -f 1)
	LINENUM=$((LINENUM+1))
	$SED "${LINENUM}i \ \ \ \ key: $ISVDIKEY" "$ISVDICONF"
	$SED "${LINENUM}i \ \ \ \ accept: true" "$ISVDICONF"
} #setup_license

prompt_for_license() {
	printf "\nISVDI requires a license key.\n"
	printf "It can be found with your entitlement on Passport Advantage.\n"
	printf "IMPORTANT: The key must be a single line. To avoid problems with multi-lines\n"
	printf "           when copied from a document, <Enter> has been disabled and you\n"
	printf "           MUST use the semi-colon (;) character to submit the value.\n\n"
	read -d ";" -r -p "License Key: " KEY
	ISVDIKEY=$(tr -d '\n' <<< "$KEY")
	if [[ -z "$ISVDIKEY" ]]; then
		printf "\nERROR: Installation will FAIL without a valid license key!\n"
		exit 1
	fi
	printf "\n"
	get_truefalse "Do you accept the terms of the license in the license directory" "false" && LICENSE=$TFVALUE
	if [[ $LICENSE = "false" ]]; then
		printf "\nERROR: Installation will FAIL if the license is not accepted!\n"
		exit 1
	fi
} #prompt_for_license

wait_for_startup() {
	DEPLOYNAME=$1
	# Waiting for pod to be created
	sleep 5
	POD=$($kubectl -n "$NS" get pods | grep "$DEPLOYNAME" | awk '{ print $1 }')
	./sys/waitFor.sh "$POD" pod
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi

	# Waiting for pod to be ready
	./sys/waitFor.sh "$DEPLOYNAME" application
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi
} #wait_for_startup

process_files() {
	for FILE in $YMLFILES; do
		./updateYaml.sh "${FILE}.yaml"
	done
} #process_files

finish_up() {
	process_files
	if [[ "$OFFLINE" != "1" ]]; then
		wait_for_startup "$DEPLOYMENT"
	else
		echo "Please load the following files to deploy isvdi:"
		for FILE in $YMLFILES; do
			echo "yaml/${FILE}.yaml"
		done
		printf "\n"
		read -n 1 -s -r -p "Once isvdi is Ready, press any key to continue..."
		printf "\n\n"
	fi
} #finish_up

create_new_deployment() {
	DNAME=$1
	TPDIR="../helm/templates"
	YMLFILES="085-pvc-$DNAME 135-service-$DNAME 225-deployment-$DNAME"
	for FILE in 085-pvc 135-service 225-deployment; do
		cp "${TPDIR}/${FILE}-isvdi.yaml" "${TPDIR}/${FILE}-${DNAME}.yaml"
		$SED "s/ isvdi/ ${DNAME}/" "${TPDIR}/${FILE}-${DNAME}.yaml"
	done

	cp ../config/adapters/isvdi_config.yaml "../config/adapters/${DNAME}_config.yaml"
	$SED "s/isvdi.pem/${DNAME}.pem/" "$ISVDICONF"
	$SED "s/isvdi_config/${DNAME}_config/" "$TPDIR/225-deployment-${DNAME}.yaml"
} #create_new_deployment

install() {
	# Pull ISVDI license key from config.yaml
	ISVDIKEY=$(grep isvdiKey "$CONF" | awk '{ print $2 }')
	if [[ -z "$ISVDIKEY" ]]; then
		exit 47
	fi

	# Set license key in adapters config.yaml if not already present
	RESULT=$(grep "accept: true" "$ISVDICONF")
	if [[ $? -ne 0 ]]; then
		setup_license
	fi

	setup_ssl "$DEPLOYMENT"

	finish_up
} #install

deploy() {
	if [[ -n "$1" ]]; then
		validate_k8s_name "$1"
		if [[ $? -eq 0 ]]; then
			DEPLOYMENT=$1
			ISVDICONF="../config/adapters/${DEPLOYMENT}_config.yaml"
		else
			exit 3
		fi
	fi

	RESULT=$($kubectl -n "$NS" get pods | grep -q "$DEPLOYMENT")
	if [[ $? -eq 0 ]]; then
		printf "\nDeployment %s already exists!  Please choose a unique name.\n" "$DEPLOYMENT"
		exit 2
	fi

	if [[ "$DEPLOYMENT" != "isvdi" ]]; then
		create_new_deployment "$DEPLOYMENT"
	fi

	# Set license key in adapters config.yaml if not already present
	RESULT=$(grep "accept: true" "$ISVDICONF")
	if [[ $? -ne 0 ]]; then
		prompt_for_license
		setup_license
	fi

	if [[ ! -f $CERTDIR/${DEPLOYMENT}.pem ]]; then
		setup_ssl "$DEPLOYMENT"
	fi

	finish_up
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

case $(awk -vs1="$1" 'BEGIN { print tolower(s1) }') in
	-install|--install)
		install
		;;
	-deploy|--deploy)
		deploy "$2"
		;;
	--help|-help)
		print_help
		;;
	*)
		echo "Invalid option: $1"
		print_help
		;;
esac
