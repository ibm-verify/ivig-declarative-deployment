#!/bin/bash

YMLFILES="007-serviceaccount-hazelcast 020-config-isvgimconfig 030-config-mqcfg 060-secret-mqcreds 070-secret-oidccreds 075-pvc-mqshare 100-service-isvgim 120-service-mqlocal 121-service-hazelcast 125-service-mqshare 215-deployment-mqshare 300-statefulset-isvgim"
YMLDIR="../yaml"
CFGDIR="../config"
CFGFILE="${CFGDIR}/config.yaml"
MQCRED="060-secret-mqcreds"
OIDCCRED="070-secret-oidccreds"
CERTDIR="${CFGDIR}/certs"
PROPFILE="../data/enRole.properties"
MQLOCAL_MQSC=$CFGDIR/mq/ISVGContainerQMgr.mqsc
MQSHARED_MQSC=$CFGDIR/mq/ISVGContainerQMgr-shared.mqsc

if [[ "$1" = "--help" ]]; then
        echo "Name: setupISVGIM.sh"
        echo "When to run: Never, called automatically by the installer."
        echo "Description:"
        echo "   Configuration script called automatically by the installer.  It should only be called directly when troubleshooting."
        echo "   It will remove the isvgimconfig pod and start the main isvgim pod."
        echo "Example usage:"
        echo "   $ ./setupISVGIM.sh"
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

get_sed_cmd && SED=$REPLY
get_namespace || die "Unable to determine namespace" $?
NS=$REPLY
get_pod_name "$NS" isvgimconfig && POD=$REPLY
$kubectl -n "$NS" cp "$POD":/work/config.yaml "$CFGFILE" > /dev/null
if [[ $? -ne 0 ]]; then
	echo "kubectl was unable to download config/config.yaml"
	exit 9
fi

# Remove extra license key info from IM config.yaml
$SED '/ldapKey/d' "$CFGFILE"
$SED '/isvdiKey/d' "$CFGFILE"

# Make sure root CA is listed
grep -q isvgimRootCA.crt "$CFGFILE"
if [[ $? -ne 0 ]]; then
	if [[ -f $CERTDIR/isvgimRootCA.crt ]]; then
		LINE=$(grep -n truststore: "$CFGFILE" | cut -d ':' -f 1)
		LINE=$((LINE+1))
		$SED "${LINE}i \ \ - '@isvgimRootCA.crt'" "$CFGFILE"
		$SED '/truststore/ s/ null//' "$CFGFILE"
	fi
fi

# Regenerate configmap with abbreviated config.yaml
./createConfigs.sh setup
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors creating ConfigMap for setup"
	fi
	exit "$RC"
else
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Please load yaml/020-config-isvgimconfig.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

if [[ $ENABLE_FIPS = "true" ]]; then
	LINENUMBER=$(grep -n SSLFIPS "$MQLOCAL_MQSC" | cut -d ':' -f 1)
	$SED "${LINENUMBER}s/NO/YES/" "$MQLOCAL_MQSC"

	LINENUMBER=$(grep -n SSLFIPS "$MQSHARED_MQSC" | cut -d ':' -f 1)
	$SED "${LINENUMBER}s/NO/YES/" "$MQSHARED_MQSC"
fi

# Create MQ config data
./createConfigs.sh mq
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors creating ConfigMap for mq"
	fi
	exit "$RC"
else
	if [[ $OFFLINE -eq 1 ]]; then
		echo "Please load yaml/011-config-mqcfg-ssl.yaml and yaml/030-config-mqcfg.yaml"
		read -n 1 -s -r -p "Once loaded, press any key to continue..."
		printf "\n\n"
	fi
fi

# Generate MQ passwords
if [[ $OFFLINE -eq 0 ]]; then
	$kubectl create secret generic mqcreds --from-literal=mqlocal="$MQLOCALPWD" --from-literal=mqshare="$MQSHAREPWD" --from-literal=mqadmin="$MQADMINPWD" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "../helm/templates/${MQCRED}.yaml"
	if [[ $? -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Error creating mqcreds secret"
		fi
		exit 35
	fi
else
	echo "Please create your mqcreds secret for your MQ servers"
	echo "An example command is: $kubectl -n $NS create secret generic mqcreds --from-literal=mqlocal=local_pwd --from-literal=mqshare=share_pwd --from-literal=mqadmin=admin_pwd"
	read -n 1 -s -r -p "Once loaded, press any key to continue..."
	printf "\n\n"
fi

# Generate OIDC passwords - this is a placeholder until real ones are entered
if [[ $OFFLINE -eq 0 ]]; then
	$kubectl create secret generic oidccreds --from-literal=restuser=restuser --from-literal=restsecret=none --from-literal=adminConsoleuser=adminuser --from-literal=adminConsolesecret=none --from-literal=iscuser=iscuser --from-literal=iscsecret=none --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "../helm/templates/${OIDCCRED}.yaml"
	if [[ $? -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Error creating OIDC placeholder secret"
		fi
		exit 44
	fi
else
	echo "Please create your oidccreds secret for your OIDC server"
	echo "If you are not using an OIDC server, then the values you enter will not matter.  The secret just needs to exist."
	echo "An example command is: $kubectl -n $NS create secret generic oidccreds --from-literal=restuser=restuser --from-literal=restsecret=none --from-literal=adminConsoleuser=adminuser --from-literal=adminConsolesecret=none --from-literal=iscuser=iscuser --from-literal=iscsecret=none"
	read -n 1 -s -r -p "Once loaded, press any key to continue..."
	printf "\n\n"
fi

if [[ $OFFLINE -eq 0 ]]; then
	$kubectl delete -f "${YMLDIR}/201-deployment-isvgimconfig.yaml"
	if [[ $? -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Error removing ISVGIM config pod"
		fi
		exit 16
	fi
else
	echo "Please delete the isvgimconfig deployment."
	read -n 1 -s -r -p "Once removed, press any key to continue..."
	printf "\n\n"
fi

REPACK_CM=0
# If License information was provided, update enRole.properties
if [[ -z "$LICENSE_EXT_OC" ]]; then
	$SED "s/#\(enrole.license.externaluser.objectclass=\).*$/\1${LICENSE_EXT_OC}/" "$PROPFILE"
	REPACK_CM=1
fi
if [[ -n "$LICENSE_EXT_ATTR" ]]; then
	$SED "s/#\(enrole.license.externaluser.attribute=\).*$/\1${LICENSE_EXT_ATTR}/" "$PROPFILE"
	REPACK_CM=1
fi
if [[ $REPACK_CM -eq 1 ]]; then
	./createConfigs.sh
	RC=$?
	if [[ $RC -ne 0 ]]; then
		if [[ -z "$1" ]]; then
			echo "Errors creating data config map"
		fi
		exit "$RC"
	else
		if [[ $OFFLINE -eq 1 ]]; then
			echo "Please load yaml/015-config-isvgimdata.yaml"
			read -n 1 -s -r -p "Once loaded, press any key to continue..."
			printf "\n\n"
		fi
	fi
fi

# Copy License Server info into ISVGIM namespace
# It might not have been installed yet, so don't exit if there's an error
./util/getILMTInfo.sh

./createConfigs.sh templates
RC=$?
if [[ $RC -ne 0 ]]; then
	if [[ -z "$1" ]]; then
		echo "Errors generating yaml from the templates directory"
	fi
	exit "$RC"
fi

if [[ $OFFLINE -eq 0 ]]; then
	for FILE in $YMLFILES; do
		./updateYaml.sh "${FILE}.yaml"
	done

	# Waiting for pod to be created
	sleep 5
	./sys/waitFor.sh isvgim-0 pod
	RC=$?
	if [[ $RC -ne 0 ]]; then
		exit "$RC"
	fi

	# Waiting for pod to be ready
	./sys/waitFor.sh isvgim-0 application
	RC=$?
	if [[ $RC -ne 0 ]]; then
		./getLogs.sh
		exit "$RC"
	fi
else
	echo "Please load the following files to deploy IVIG: (the secret files will not exist)"
	for FILE in $YMLFILES; do
		echo "yaml/${FILE}.yaml"
	done
	printf "\n"
	read -n 1 -s -r -p "Once isvgim-0 is Ready, press any key to continue..."
	printf "\n\n"
fi

# Retrieve auto cert if it exists
if [[ ! -d $CERTDIR ]]; then
	mkdir "$CERTDIR"
fi
if [[ ! -f $CERTDIR/isvgim.key ]]; then
	POD=isvgim-0
	$kubectl -n "$NS" cp "${POD}":/work/isvgim.key "$CERTDIR/isvgim.key" > /dev/null 2>&1
	$kubectl -n "$NS" cp "${POD}":/work/isvgim.cert "$CERTDIR/isvgim.crt" > /dev/null 2>&1
	$kubectl -n "$NS" cp "${POD}":/work/isvgim.csr "$CERTDIR/isvgim.csr" > /dev/null 2>&1

	# The files above might not exist, but the command still exits with 0
	# So we need to check if the file was copied before creating a new
	# configmap.
	if [[ -f $CERTDIR/isvgim.key ]]; then
		./createConfigs.sh setup
		RC=$?
		if [[ $RC -ne 0 ]]; then
			if [[ -z "$1" ]]; then
				echo "Errors creating ConfigMap for setup"
			fi
			exit "$RC"
		else
			if [[ $OFFLINE -eq 1 ]]; then
				echo "Please load yaml/020-config-isvgimconfig.yaml"
				read -n 1 -s -r -p "Once loaded, press any key to continue..."
				printf "\n\n"
			fi
		fi
	fi
fi

