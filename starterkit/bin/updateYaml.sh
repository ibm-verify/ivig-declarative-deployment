#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: updateYaml.sh"
	echo "When to run: After modifying a yaml file in the helm/templates directory."
	echo "Description:"
	echo "   Configuration script called automatically by the installer."
	echo "   It will turn a template into a fully filled out YAML file."
	echo "Example usage:"
	echo "   $ ./updateYaml.sh 000-namespace.yaml"
	echo ""
	exit 0
fi

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh

if [[ -z "$1" ]]; then
	echo "Error: Missing template filename!"
	exit 1
fi

FILE=$(basename "$1")

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

# Fill out the template
helm template ../helm -s "templates/$FILE" | tail -n +3 | grep -v Source: > "../yaml/$FILE"
if [[ $? -ne 0 ]]; then
	echo "helm was unable to process helm/templates/$FILE"
	exit 5
fi

check_for_missing() {
# Confirm all placeholders were replaced
# First, change field separator to newline
# Second, get list of replaceable values from template
# Third, check their corresponding line in full yaml
# If no value exists, retrieve replacement line from template, error out
# A flag is used to signal the exit after the loop completes to make sure
# we find all the missing entries in a file.
	OIFS=$IFS
	IFS=$'\n'
	MUSTEXIT=0
	errors=()
	REPLIST=$(grep "{{ .Values" "../helm/templates/$FILE")
	for REP in $REPLIST; do
		ATTR=$(echo "$REP" | cut -d ':' -f 1)
		NEWVAL=$(grep "${ATTR}:" "../yaml/$FILE")
		VALLC=0
		for LINE in $NEWVAL; do
			VALLC=$((VALLC+1))
			VAL=$(echo "$LINE" | awk '{ print $2 }')
			if [[ -z "$VAL" ]]; then
				# Must go back to template file to retrieve correct line
				# because if there were multiple (e.g. image), we need
				# to print the correct missing value.
				OLDVALS=$(grep "${ATTR}:" "../helm/templates/$FILE")
				OVALLC=0
				for OVAL in $OLDVALS; do
					OVALLC=$((OVALLC+1))
					if [[ $OVALLC -eq $VALLC ]]; then
						EMSG=$(echo "$OVAL" | cut -d ':' -f 2-)
						for error in "${errors[@]}"; do
							if [[ "$error" = "$EMSG" ]]; then
								break 2
							fi
						done
						MUSTEXIT=1
						echo "Yaml Error: Missing value in $FILE"
						MSG=$(echo "$OVAL" | awk '{ print $FILE }')
						echo "$MSG $EMSG"
						errors+=("$EMSG")
						break 2
					fi
				done
			fi
		done
	done
	IFS=$OIFS
	if [[ $MUSTEXIT -eq 1 ]]; then
		exit 34
	fi
} #check_for_missing

if [[ ! $FILE =~ operator ]]; then
	check_for_missing
fi

if [[ "$OFFLINE" != "1" ]]; then
	# Load configuration into kubernetes
	$kubectl apply -f "../yaml/$FILE"
	if [[ $? -ne 0 ]]; then
		echo "kubectl was unable to apply yaml/$FILE"
		exit 6
	fi
fi
exit 0
