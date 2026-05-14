#!/bin/bash

DATADIR=../data
YAMLDIR=../helm/templates
CFGDIR=../config
CFGFILE=${CFGDIR}/config.yaml
ISIMTAR=/tmp/data.tgz
KEYTAR=/tmp/ks.tgz
RISKTAR=/tmp/risk.tgz

if [[ "$1" = "--help" ]]; then
	echo "Name: createConfigs.sh"
	echo "When to run: After updating configuration files or the data directory"
	echo "Description:"
	echo "   Helper script to generate the ConfigMap object holding all the IVIG configuration data."
	echo "   It must be run after editing any files in the config or data directores,"
	echo "   and will create the necessary YAML file."
	echo "   The changes will not take effect until you restart your ISVGIM pods."
	echo ""
	echo "Options:"
	echo "  [blank]  - packages the files in the data directory"
	echo "  keystore - packages the ISIM keystore files"
	echo "  db       - packages postgresql configuration and certs"
	echo "  ldap     - packages LDAP configuration and certs"
	echo "  mq       - packages queue manager configuration and certs"
	echo "  isvdi    - packages RMI Dispatcher configuration and certs"
	echo "  setup    - packages config.yaml and IM server certs"
	echo "  risk     - packages the analytics store directory"
	echo ""
	echo "Example usage:"
	echo "   $ ./createConfigs.sh"
	echo "   $ ./createConfigs.sh db"
	echo ""
	exit 0
fi

generate_setup() {
	FILE=020-config-isvgimconfig.yaml
	if [[ ! -d $CFGDIR/certs ]]; then
		mkdir -p "$CFGDIR/certs"
	fi
	$kubectl create configmap isvgimconfig --from-file="$CFGDIR/config.yaml" --from-file="$CFGDIR/certs" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap for setup"
		exit 11
	fi
	./updateYaml.sh "$FILE"
	exit $?
} #generate_setup

generate_risk() {
	cd "$CFGDIR/analytics" || exit 11
	FILE=031-config-ivigrisk.yaml
	tar czf "$RISKTAR" store/*
	if [[ $? -ne 0 ]]; then
		echo "Unable to create $RISKTAR"
		exit 11
	fi
	cd ..
	$kubectl create configmap ivigrisk --from-file="$RISKTAR" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap for risk engine"
		exit 11
	fi
	rm "$RISKTAR"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to remove $RISKTAR file"
		exit 11
	fi
	../bin/updateYaml.sh "$FILE"
	exit $?
}

generate_ldap() {
	FILE=025-config-isvgimldap.yaml
	$kubectl create configmap isvgimldap --from-file="$CFGDIR/ldap" --from-file="$CFGDIR/certs" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap for ldap"
		exit 11
	fi
	./updateYaml.sh "$FILE"
	exit $?
} #generate_ldap

generate_mq() {
	FILE=011-config-mqcfg-ssl.yaml
	$kubectl create configmap tlsmqcfg --from-file="$CFGDIR/certs/mq.key" --from-file="$CFGDIR/certs/mq.crt" --from-file="$CFGDIR/certs/isvgimRootCA.crt" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate TLSCerts ConfigMap for mq"
		exit 11
	fi
	./updateYaml.sh "$FILE"

	FILE=030-config-mqcfg.yaml
	$kubectl create configmap mqcfg --from-file="$CFGDIR/mq/ISVGContainerQMgr.mqsc" --from-file="$CFGDIR/mq/ISVGContainerQMgr-shared.mqsc" --from-file="$CFGDIR/mq/mqwebuser.xml" --from-file="$CFGDIR/mq/isvgqm.ini" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate SSLConfigMap for mq"
		exit 11
	fi
	./updateYaml.sh "$FILE"
	exit $?
} #generate_mq

generate_isvdi() {
	FILE=045-config-adapters.yaml
	$kubectl create configmap isvgimsdi --from-file="$CFGDIR/adapters" --from-file="$CFGDIR/certs" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap for adapter dispatcher"
		exit 11
	fi
	./updateYaml.sh "$FILE"
	exit $?
} #generate_isvdi

generate_db() {
	FILE=040-config-isvgimdb.yaml
	$kubectl create configmap isvgimdb --from-file="$CFGDIR/db/pg_hba.conf" --from-file="$CFGDIR/db/postgres.conf" --from-file="$CFGDIR/certs" --from-file="$CFGDIR/db/primary_init_script.sh" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap for db"
		exit 11
	fi
	./updateYaml.sh "$FILE"
	exit $?
} #generate_db

generate_keystore() {
	cd "$DATADIR" || exit 11
	FILE=010-config-isvgimks.yaml
	tar czf "$KEYTAR" encryptionKey.properties keystore/*
	if [[ $? -ne 0 ]]; then
		echo "Unable to create $KEYTAR"
		exit 11
	fi
	$kubectl create configmap isvgimks --from-file="$KEYTAR" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap from $KEYTAR file"
		exit 11
	fi
	rm "$KEYTAR"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to remove $KEYTAR file"
		exit 11
	fi
	../bin/updateYaml.sh "$FILE"
	exit $?
} #generate_keystore


generate_main_config() {
	cd "$DATADIR" || exit 11
	FILE=015-config-isvgimdata.yaml
	tar czf "$ISIMTAR" --exclude=encryptionKey.properties --exclude=keystore *
	if [[ $? -ne 0 ]]; then
		echo "Unable to create $ISIMTAR"
		exit 11
	fi
	$kubectl create configmap isvgimdata --from-file="$ISIMTAR" --dry-run=client -o yaml --namespace=isvg-temp | sed 's/isvg-temp/{{ .Values.namespace }}/g' > "$YAMLDIR/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to generate ConfigMap from $ISIMTAR file"
		exit 11
	fi
	rm "$ISIMTAR"
	if [[ $? -ne 0 ]]; then
		echo "kubectl failed to remove $ISIMTAR file"
		exit 11
	fi
	../bin/updateYaml.sh "$FILE"
	exit $?
} #generate_main_config

process_templates() {
	printf "Evaluating templates"
	for FILE in "$YAMLDIR"/*; do
		FILE=$(basename "$FILE")
		if [[ "$FILE" = "000-namespace.yaml" ]]; then
			continue
		fi
		helm template ../helm -s "templates/$FILE" | tail -n +3 | grep -v Source: > "../yaml/$FILE"
		if [[ $? -ne 0 ]]; then
			echo "helm was unable to process helm/templates/${FILE}.yaml"
			exit 5
		fi
		printf "."
	done
	printf "Done!\n"
} #process_templates

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

echo "Generating Configs"
case $(awk -vs1="$1" 'BEGIN { print tolower(s1) }') in
	keystore)
		generate_keystore
		;;
	templates)
		process_templates
		;;
	setup)
		generate_setup
		;;
	ldap)
		generate_ldap
		;;
	db)
		generate_db
		;;
	mq)
		generate_mq
		;;
	isvdi)
		generate_isvdi
		;;
	risk)
		generate_risk
		;;
	*)
		generate_main_config
		;;
esac

exit 0
