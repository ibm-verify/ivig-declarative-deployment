#!/bin/bash

YMLDIR="../yaml"
DATADIR="../data"
LOGDIR="../logs"
CUSTOMDIR="../custom"
EXTENSIONSDIR="../extensions"
BACKUPDIR="../backup"

if [[ "$1" = "--help" ]]; then
		echo "Name: cleanup.sh"
		echo "When to run: Never, called automatically by the installer, if needed."
		echo "Description:"
		echo "   Script called automatically by the installer if the installation fails."
		echo "   It will remove the yaml and data directories and remove any k8s objects that were deployed."
		echo "Options:"
		echo "   -force: Will remove all data from an installed system"
		echo "Example usage:"
		echo "   $ ./cleanup.sh"
		echo "   $ ./cleanup.sh -force"
		echo ""
		exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "sys" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

printf "\n##### Cleaning Up #####\n"
get_sed_cmd && SED=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

if [[ -f ../.installed ]] && [[ "$1" != "-force" ]]; then
	echo "Not removing an installed system.  Use -force to override."
	exit 1
fi

K8SREMOVED=0
RMKUBEGRES=0
if [[ -d $YMLDIR ]]; then
	get_namespace || die "Unable to get namespace" $?
	NS=$REPLY
	ls "$YMLDIR" | grep .yaml > /dev/null 2>&1
	if [[ $? -eq 0 ]]; then
		cd ..
		# If kubegres operator is not installed, remove CRD yaml to avoid not found error
		$kubectl -n "$NS" get kubegres -o name 2>&1 | grep -q postgres
		if [[ $? -ne 0 ]]; then
			if [[ -r yaml/410-crd-postgres.yaml ]]; then
				rm yaml/410-crd-postgres.yaml
			fi
		else
			RMKUBEGRES=1
		fi
		# kubectl refused to delete a relative path
		$kubectl delete --ignore-not-found=true -f yaml 2>&1 &
		PID=$!
		cd bin || exit 1
		TIMER=0
		K8SREMOVED=1

		while [[ 0 -eq 0 ]]; do
			if [[ "$TIMER" -eq 0 ]]; then
				printf "Removing objects from kubernetes...\n"
			fi
			sleep 5
			kill -0 "$PID" > /dev/null 2>&1
			if [[ $? -eq 1 ]]; then
				wait "$PID"
				RC=$?
				if [[ "$RC" -ne 0 ]]; then
					printf "\nError removing objects. Please remove them manually, and also\n"
					printf "remove the yaml directory.\n"
					K8SREMOVED=0
					break
				else
					break
				fi
			fi
			TIMER=$((TIMER+1))
			if [[ "$TIMER" -gt 100 ]]; then
				printf "\nTimed out: Removing objects has taken a very long time.\n"
				printf "Please check if any still exist.\n"
				break
			fi
		done

		# If namespace still exists, it was created manually.  Just remove the mqlocal and postgres HA PVCs.
		if [[ $kubectl = "oc" ]]; then
			CMD=$($kubectl get projects -o name | grep -e "namespace/${NS}$")
		else
			CMD=$($kubectl get ns -o name | grep -e "namespace/${NS}$")
		fi
		if [[ $? -eq 0 ]]; then
			PVCS=$($kubectl -n "$NS" get pvc -o name | grep datadir-isvgim)
			for PVC in $PVCS; do
				$kubectl -n "$NS" delete "$PVC"
			done
			PVCS=$($kubectl -n "$NS" get pvc -o name | grep postgres-db-postgres)
			for PVC in $PVCS; do
				$kubectl -n "$NS" delete "$PVC"
			done
			if [[ "$RMKUBEGRES" -eq 1 ]]; then
				$kubectl -n "$NS" delete cm base-kubegres-config
			fi

			# Remove license errata if present
			$kubectl -n "$NS" delete --ignore-not-found=true cm ibm-licensing-upload-config
			$kubectl -n "$NS" delete --ignore-not-found=true secret ibm-licensing-upload-token

			# If any spark pods still exist, delete them
			DRIVERPODS=$($kubectl -n "$NS" get pods | grep spark-csr | grep driver | awk '{ print $1 }')
			for POD in $DRIVERPODS; do
				$kubectl -n "$NS" delete pod "$POD"
			done
			EXECPODS=$($kubectl -n "$NS" get pods | grep spark-csr | grep executor | awk '{ print $1 }')
			for POD in $EXECPODS; do
				$kubectl -n "$NS" delete pod "$POD"
			done
		fi

		if [[ "$K8SREMOVED" -eq 1 ]]; then
			printf "\nDone!\n"
		fi
	fi
fi

printf "Removing obsolete local files..."
if [[ ! -d $BACKUPDIR ]]; then
	mkdir -p "$BACKUPDIR"
fi
if [[ -d $DATADIR ]]; then
	FILE=$(date +"%Y%m%d_%H%M%S")
	DIRS="data"
	if [[ -d $LOGDIR ]]; then
		DIRS="$DIRS logs"
	fi
	if [[ -d $CUSTOMDIR ]]; then
		DIRS="$DIRS custom"
	fi
	cd ..
	tar czf "backup/${FILE}.tgz" $DIRS
	rm -rf data
	cd bin || exit 1
fi
if [[ -d "$YMLDIR" ]] && [[ "$K8SREMOVED" -eq 1 ]]; then
	rm -rf "$YMLDIR"
fi
if [[ -d "$CUSTOMDIR" ]]; then
	rm -rf "$CUSTOMDIR"
fi
if [[ -d $LOGDIR ]]; then
	rm -rf "$LOGDIR"
fi
if [[ -d $EXTENSIONSDIR ]]; then
	rm -rf "$EXTENSIONSDIR"
fi
if [[ -f ../helm/templates/020-config-isvgimconfig.yaml ]]; then
	for FILE in ../helm/templates/*; do
		FILE=$(basename "$FILE")
		if [[ "$FILE" == *-config-* ]]; then
			rm "../helm/templates/$FILE"
		fi
	done
fi

if [[ -r ../config/mq/isvgqm.ini.bak ]]; then
	mv ../config/mq/isvgqm.ini.bak ../config/mq/isvgqm.ini
fi

if [[ -r ../config/mq/ISVGContainerQMgr.mqsc.bak ]]; then
	mv ../config/mq/ISVGContainerQMgr.mqsc.bak ../config/mq/ISVGContainerQMgr.mqsc
fi

if [[ -r ../config/mq/ISVGContainerQMgr-shared.mqsc.bak ]]; then
	mv ../config/mq/ISVGContainerQMgr-shared.mqsc.bak ../config/mq/ISVGContainerQMgr-shared.mqsc
fi

if [[ -r ../config/config.bak ]]; then
	mv ../config/config.bak ../config/config.yaml
fi
if [[ -r ../helm/values.bak ]]; then
	mv ../helm/values.bak ../helm/values.yaml
fi

# Clean up the certs
if [[ -f ../.preserveCertsOnCleanup ]]; then
	CERTLIST=$(cat ../.preserveCertsOnCleanup)
	FILES=$(ls ../config/certs)
	for FILE in $FILES; do
		REMOVE=1
		for CERT in $CERTLIST; do
			if [[ "$CERT" = "$FILE" ]]; then
				REMOVE=0
				break
			fi
		done
		if [[ $REMOVE -eq 1 ]]; then
			rm "../config/certs/$FILE"
		fi
	done
	rm ../.preserveCertsOnCleanup
fi

if [[ -f ../config/ldap/ldif1 ]]; then
	rm ../config/ldap/ldif?
fi

for FILE in $(find ../config -type f -name "*_config.yaml"); do
	$SED '/\ \ \ \ accept:/d' "$FILE"
	LICENSE_LINE=$(grep -n "  license:" "$FILE" | cut -d ':' -f 1)
	KEY_LINE=$((LICENSE_LINE+3))
	$SED "$LICENSE_LINE,$KEY_LINE{/\ \ \ \ key:/d}" "$FILE"
done

if [[ -f ../config/db/tbscript.sh ]]; then
	rm ../config/db/tbscript.sh
fi
if [[ -f ../.installed ]]; then
	rm ../.installed
fi
if [[ -f ../.ldapsetup ]]; then
	rm ../.ldapsetup
fi
echo "Done!"
