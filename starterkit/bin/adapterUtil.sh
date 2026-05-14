#!/bin/bash
# *****************************************************************************
# *
# * IBM Confidential
# *
# * OCO Source Materials
# *
# * (C) COPYRIGHT IBM Corp.2025
# *
# * The source code for this program is not published or otherwise
# * divested of its trade secrets, irrespective of what has been
# * deposited with the U.S. Copyright Office.
# *
# *****************************************************************************

#=================================================================
# FILE:
#       adapterUtil.sh
#
# USAGE:
#       adapterUtil.sh -help
#       adapterUtil.sh [ deploymentNameOption ] [ deploymentNameArg1 ] loadOption laodArg1 loadArg2
#       adapterUtil.sh [ deploymentNameOption ] [ deploymentNameArg1 ] infoOption infoArg1
#       adapterUtil.sh [ deploymentNameOption ] [ deploymentNameArg1 ] copyOption copyArg1 [ copyArg2 ]
#       adapterUtil.sh [ deploymentNameOption ] [ deploymentNameArg1 ] listOption [ listArg1 ]
#       adapterUtil.sh [ deploymentNameOption ] [ deploymentNameArg1 ] removeOption removeArg1
#
# DESCRIPTION:
#       This script helps to manage adapter and its releated files
# inside the ISVDI dispatcher container instance.
#
# VERSION       Revision        DATE            CHANGES
# 10.0.1     	000             03/27/2025      Initial release
#
#=================================================================

RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR" || exit 1
source ./lib/common.sh

# Variable Defaults
declare ADAPTER_PV=/opt/IBM/svgadapters
declare CONFIG_PV=/tmp/isvgimsdi
declare DEPLOYMENT=isvdi
declare PROCESS_ITEM
declare FUNCTION_NAME
declare NUMBER_OF_PARAMS_REQUIRED=0
declare PARAMS=()
declare DEPLOYMENTPARAMS=()
declare OPTIONS_ARRAY=()
declare COUNT_OF_OPTIONS=0

function displayHelp() {
	echo ""
	echo "Name: adapterUtil.sh"
	echo "When to run: Whenever an adapter is to be installed or updated."
	echo ""
	echo "Description:"
	echo "   This script will load the necessary files for a given adapter into the ISVDI pod."
	echo "   It can also be used to list the currently installed adapters, and retrieve details"
	echo "   about a given adapter. To support multiple clusters of ISVDI servers, where each cluster"
	echo "   can run different adapters, an optional deployment name can be provided, and the script"
	echo "   will connect to a pod in the specified cluster. If not supplied, the default \"isvdi\""
	echo "   deployment will be used."
	echo ""
	echo "Options:"
	echo " Script options:"
	echo "   --help"
	echo "   --version"
	echo ""
	echo " Container options:"
	echo "   -deploymentName DEPLOYMENT_NAME"
	echo "     Note: MUST be included in all commands directed to custom deployment names."
	echo ""
	echo " Adapter options:"
	echo "   -loadAdapter /path/to/Adapter.zip accept"
	echo "   -infoAdapter Adapter_Name"
	echo "   -listAdapters"
	echo "   -removeAdapter Adapter_Name"
	echo ""
	echo " Adapter specific file options:"
	echo "   -copyToExternalKeystore /path/to/keystore_file"
	echo "   -listExternalKeystoreFiles"
	echo "   -removeFromExternalKeystore keystore_filename"
	echo ""
	echo "   -copyTo3rdpartyOthers /path/to/jar_file"
	echo "   -list3rdpartyOthersFiles"
	echo "   -removeFrom3rdpartyOthers jar_filename"
	echo ""
	echo "   -copyToPatches /path/to/jar_file"
	echo "   -listPatchesFiles"
	echo "   -removeFromPatches jar_filename"
	echo ""
	echo "   -copyToConnectors /path/to/connector/jar_file"
	echo "   -listConnectorsFiles"
	echo "   -removeFromConnectors connector_jar_filename"
	echo ""
	echo "   -copyToFunctions /path/to/functions/jar_file"
	echo "   -listFunctionsFiles"
	echo "   -removeFromFunctions functions_jar_filename"
	echo ""
	echo "   -copyToLibs /path/to/lib_file"
	echo "   -listLibsFiles"
	echo "   -removeFromLibs lib_filename"
	echo ""
	echo "   -copyToProperties /path/to/properties_file"
	echo "   -listPropertiesFiles"
	echo "   -viewPropertiesFile properties_filename"
	echo "   -removeFromProperties properties_filename"
	echo ""
	echo "   -copyToXsl /path/to/xsl_file"
	echo "   -listXslFiles"
	echo "   -removeFromXsl xsl_filename"
	echo ""
	echo "   -copyToScripts /path/to/script_file"
	echo "   -listScriptsFiles"
	echo "   -removeFromScripts scripts_filename"
	echo ""
	echo "   -copyToSwidtag /path/to/swid_tag_file"
	echo "   -listSwidtagFiles"
	echo "   -removeFromSwidtag swidtag_filename"
	echo ""
	echo " Generic options:"
	echo "   -copyFile localFile containerPath"
	echo "   -listFiles containerPath"
	echo "   -removeFile containerPath"
	echo ""
	echo ""
	echo "Example usage:"
	echo "   $ ./adapterUtil.sh -loadAdapter \"/path/to/Adapter.zip\" accept"
	echo "   $ ./adapterUtil.sh -deploymentName isvdi2 -loadAdapter \"/path/to/Adapter.zip\" accept"
	echo "   $ ./adapterUtil.sh -infoAdapter Adapter-AzureAD"
	echo "   $ ./adapterUtil.sh -listAdapters"
	echo "   $ ./adapterUtil.sh -removeAdapter Adapter-AzureAD"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToExternalKeystore ../keystore.jks"
	echo "   $ ./adapterUtil.sh -listExternalKeystoreFiles"
	echo "   $ ./adapterUtil.sh -removeFromExternalKeystore keystore.jks"
	echo ""
	echo "   $ ./adapterUtil.sh -copyTo3rdpartyOthers ./httpcore-4.4.16.jar"
	echo "   $ ./adapterUtil.sh -list3rdpartyOthersFiles"
	echo "   $ ./adapterUtil.sh -removeFrom3rdpartyOthers httpcore-4.4.16.jar"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToPatches ../httpcore-4.4.16.jar"
	echo "   $ ./adapterUtil.sh -listPatchesFiles"
	echo "   $ ./adapterUtil.sh -removeFromPatches httpcore-4.4.16.jar"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToConnectors ./connector/CustomConnector.jar"
	echo "   $ ./adapterUtil.sh -listConnectorsFiles"
	echo "   $ ./adapterUtil.sh -removeFromConnectors CustomConnector.jar"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToFunctions ./CustomFunctions.jar"
	echo "   $ ./adapterUtil.sh -listFunctionsFiles"
	echo "   $ ./adapterUtil.sh -removeFromFunctions CustomFunctions.jar"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToLibs ../lib.so"
	echo "   $ ./adapterUtil.sh -listLibsFiles"
	echo "   $ ./adapterUtil.sh -removeFromLibs lib.so"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToProperties ./CustomAdapter.properties"
	echo "   $ ./adapterUtil.sh -listPropertiesFiles"
	echo "   $ ./adapterUtil.sh -viewPropertiesFile CustomAdapter.properties"
	echo "   $ ./adapterUtil.sh -removeFromProperties CustomAdapter.properties"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToXsl /tmp/customrequest.xsl"
	echo "   $ ./adapterUtil.sh -listXslFiles"
	echo "   $ ./adapterUtil.sh -removeFromXsl customrequest.xsl"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToScripts /tmp/scripts/customScript.sh"
	echo "   $ ./adapterUtil.sh -listScriptsFiles"
	echo "   $ ./adapterUtil.sh -removeFromScripts customScript.sh"
	echo ""
	echo "   $ ./adapterUtil.sh -copyToSwidtag /tmp/ibm.com_IBM_Security_Verify_Governance_Compliance-10.0.2.swidtag"
	echo "   $ ./adapterUtil.sh -listSwidtagFiles"
	echo "   $ ./adapterUtil.sh -removeFromSwidtag ibm.com_IBM_Security_Verify_Governance_Compliance-10.0.2.swidtag"
	echo ""
	echo "   $ ./adapterUtil.sh -copyFile ../testFile.sh /home/isvdi"
	echo "   $ ./adapterUtil.sh -listFiles /home/isvdi/"
	echo "   $ ./adapterUtil.sh -removeFile /home/isvdi/testFile.sh"
	echo ""
} #displayHelp

function displayVersion() {
	echo "Version is : 10.0.1"
} #displayVersion

function optionsArrayContains() {
	if [[ -z "$1" ]]; then
		echo "Specify option to be found in OPTIONS_ARRAY."
		exit 7
	fi

	ITEM="$1"
	OPTIONS_ARRAY_CONTAINS_ITEM="false"

	for OPTION in "${OPTIONS_ARRAY[@]}"
	do
		if [[ "${OPTION}" = "${ITEM}" ]]; then
			OPTIONS_ARRAY_CONTAINS_ITEM="true"
		fi
	done

	echo "${OPTIONS_ARRAY_CONTAINS_ITEM}"
} #optionsArrayContains

function setup() {

	kubectl=$(./sys/preReqCheck.sh)
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		echo "$kubectl"
		exit "$RC"
	fi
	get_namespace || die "Unable to get namespace" $?
	NS=$REPLY

	PODNAME=$(${kubectl} -n "${NS}" get pods | grep "${DEPLOYMENT}-" | grep Running | head -n 1 | awk '{ print $1 }')
	if [[ -z "${PODNAME}" ]]; then
		printf "\nUnable to find name of adapters pod using grep and awk\n"
		printf "Try manually running: kubectl -n %s get pods | grep \"%s-\" | grep Running | awk '{ print \$1 }'" "$NS" "$DEPLOYMENT"
		exit 10
	fi
} #setup

function checkIfFileExists() {
	if [[ ! -f "$1" ]]; then
		printf "\nUnable to read file: %s. Please ensure to provide complete path to the file.\n\n" "$1"
		exit 11
	fi
} #checkIfFileExists

function getPersistentVolumeDirectoryPath() {
	case "$1" in
		EXTERNAL_KEYSTORE)
			echo "${ADAPTER_PV}/timsol/keystores"
			;;
		3RDPARTY_OTHERS)
			echo "${ADAPTER_PV}/jars/3rdparty/others"
			;;
		PATCHES)
			echo "${ADAPTER_PV}/jars/patches"
			;;
		CONNECTORS)
			echo "${ADAPTER_PV}/jars/connectors"
			;;
		FUNCTIONS)
			echo "${ADAPTER_PV}/jars/functions"
			;;
		LIBS)
			echo "${ADAPTER_PV}/libs"
			;;
		PROPERTIES)
			echo "${ADAPTER_PV}/timsol/properties"
			;;
		XSL)
			echo "${ADAPTER_PV}/timsol/xsl"
			;;
		SCRIPTS)
			echo "${ADAPTER_PV}/timsol/scripts"
			;;
		SWIDTAG)
			echo "${ADAPTER_PV}/swidtag"
			;;
		*)
			echo "Invalid option!"
			exit 12
			;;
	esac
} #getPersistentVolumeDirectoryPath

function loadFile() {
	if [[ ${PROCESS_ITEM} = "ADAPTER" ]]; then
		if [[ "${PARAMS[1]}" != "accept" ]]; then
			printf "\nYou must indicate acceptance of the included license before you can install the adapter."
			printf "\ne.g. $ ./adapterUtil.sh -loadAdapter \"/path/to/Adapter.zip\" accept\n\n"
			exit 13
		fi
	fi

	printf "\nLoading file %s ...\n\n" "${PARAMS[0]}"

	copyFile "${PARAMS[0]}" "/tmp"
	${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "/home/isvdi/adapterContainerScripts/loadAdapter.sh $(basename "${PARAMS[0]}")"

	if [[ $? -ne 0 ]]; then
		echo "Failed to load file ${PARAMS[0]}.  See messages above for details."
		exit 14
	else
		printf "File %s loaded successfully!\n\n" "${PARAMS[0]}"
	fi
} #loadFile

function displayInfo() {
	printf "\nDispaying info for %s ...\n\n" "${PARAMS[0]}"

	${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "/home/isvdi/adapterContainerScripts/adapterInfo.sh \"${PARAMS[0]}\""

	if [[ $? -ne 0 ]]; then
		echo "Failed to display info for ${PARAMS[0]}.  See messages above for details."
		exit 15
	else
		printf "Info for %s displayed successfully!\n\n" "${PARAMS[0]}"
	fi
} #displayInfo

function listFiles() {
	printf "\nDisplaying list ...\n\n"

	if [[ ${PROCESS_ITEM} = "ADAPTER" ]]; then
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "/home/isvdi/adapterContainerScripts/listAdapters.sh"
	elif [[ ${PROCESS_ITEM} = "SDI_KEYS" ]] || [[ ${PROCESS_ITEM} = "SDI_TRUSTED_CERTS" ]]; then
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "/home/isvdi/adapterContainerScripts/listCerts.sh \"${PROCESS_ITEM}\""
	elif [[ ${PROCESS_ITEM} = "CUSTOM_FILE" ]]; then
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "ls -ltr \"${PARAMS[0]}\""
	else
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "ls -ltr \"$(getPersistentVolumeDirectoryPath "${PROCESS_ITEM}")\""
	fi

	if [[ $? -ne 0 ]]; then
		echo "Failed to display list.  See messages above for details."
		exit 16
	else
		printf "List displayed successfully!\n\n"
	fi
} #listFiles

function copyFile() {
	local fileToCopy
	local fileToCopyTo
	if [[ -z "$1" ]]; then
		fileToCopy="${PARAMS[0]}"
		if [[ "${PROCESS_ITEM}" = "CUSTOM_FILE" ]]; then
				fileToCopyTo="${PARAMS[1]}"
		else
				fileToCopyTo=$(getPersistentVolumeDirectoryPath "${PROCESS_ITEM}")
		fi
	else
		fileToCopy="$1"
		fileToCopyTo="$2"
	fi

	printf "\nCopying file %s to ISVDI pod ... " "$(basename "${fileToCopy}")"
	checkIfFileExists "${fileToCopy}"

	${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "mkdir -p ${fileToCopyTo}"

	RESULT=$(${kubectl} -n "${NS}" cp "${fileToCopy}" "${PODNAME}":"${fileToCopyTo}")

	if [[ $? -ne 0 ]]; then
		echo "Failed to copy file ${fileToCopy} to ISVDI pod.  See messages above for details."
		exit 17
	fi
	printf "Done! \n\n"
} #copyFile

function viewFile() {
	printf "\nViewing file %s...\n\n" "${PARAMS[0]}"

	${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "/home/isvdi/adapterContainerScripts/viewFile.sh \"${PROCESS_ITEM}\" \"${PARAMS[0]}\""

	if [[ $? -ne 0 ]]; then
		echo "Failed to view file ${PARAMS[0]}.  See messages above for details."
		exit 18
	else
		printf "File %s viewed successfully!\n\n" "${PARAMS[0]}"
	fi
} #viewFile

function removeFile() {
	printf "\nRemoving file %s...\n\n" "${PARAMS[0]}"

	if [[ ${PROCESS_ITEM} = "ADAPTER" ]]; then
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "/home/isvdi/adapterContainerScripts/removeAdapter.sh \"${PARAMS[0]}\""
	elif [[ ${PROCESS_ITEM} = "CUSTOM_FILE" ]]; then
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "rm \"${PARAMS[0]}\""
	else
		${kubectl} -n "${NS}" exec "${PODNAME}" -- /bin/bash -c "rm \"$(getPersistentVolumeDirectoryPath "${PROCESS_ITEM}")/${PARAMS[0]}\""
	fi

	if [[ $? -ne 0 ]]; then
		echo "Failed to remove file ${PARAMS[0]}.  See messages above for details."
		exit 20
	fi
	printf "\nFile %s removed successfully!\n\n" "${PARAMS[0]}"
} #removeFile

for ARGS in "$@"; do
	COUNT_OF_OPTIONS=$((COUNT_OF_OPTIONS + 1))
	case "${ARGS}" in
		-deploymentName|--deploymentName)
			OPTIONS_ARRAY+=("DEPLOYMENT");					COUNT_OF_OPTIONS=$((COUNT_OF_OPTIONS - 1))
			;;
		-loadAdapter|--loadAdapter)
			PROCESS_ITEM="ADAPTER";							FUNCTION_NAME="loadFile";				NUMBER_OF_PARAMS_REQUIRED=2
			;;
		-infoAdapter|--infoAdapter)
			PROCESS_ITEM="ADAPTER";							FUNCTION_NAME="displayInfo";			NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listAdapters|--listAdapters)
			PROCESS_ITEM="ADAPTER";							FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeAdapter|--removeAdapter)
			PROCESS_ITEM="ADAPTER";							FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToExternalKeystore|--copyToExternalKeystore)
			PROCESS_ITEM="EXTERNAL_KEYSTORE";				FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listExternalKeystoreFiles|--listExternalKeystoreFiles)
			PROCESS_ITEM="EXTERNAL_KEYSTORE";				FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromExternalKeystore|--removeFromExternalKeystore)
			PROCESS_ITEM="EXTERNAL_KEYSTORE";				FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyTo3rdpartyOthers|--copyTo3rdpartyOthers)
			PROCESS_ITEM="3RDPARTY_OTHERS";					FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-list3rdpartyOthersFiles|--list3rdpartyOthersFiles)
			PROCESS_ITEM="3RDPARTY_OTHERS";					FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFrom3rdpartyOthers|--removeFrom3rdpartyOthers)
			PROCESS_ITEM="3RDPARTY_OTHERS";					FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToPatches|--copyToPatches)
			PROCESS_ITEM="PATCHES";							FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listPatchesFiles|--listPatchesFiles)
			PROCESS_ITEM="PATCHES";							FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromPatches|--removeFromPatches)
			PROCESS_ITEM="PATCHES";							FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToConnectors|--copyToConnectors)
			PROCESS_ITEM="CONNECTORS";						FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listConnectorsFiles|--listConnectorsFiles)
			PROCESS_ITEM="CONNECTORS";						FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromConnectors|--removeFromConnectors)
			PROCESS_ITEM="CONNECTORS";						FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToFunctions|--copyToFunctions)
			PROCESS_ITEM="FUNCTIONS";						FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listFunctionsFiles|--listFunctionsFiles)
			PROCESS_ITEM="FUNCTIONS";						FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromFunctions|--removeFromFunctions)
			PROCESS_ITEM="FUNCTIONS";						FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToLibs|--copyToLibs)
			PROCESS_ITEM="LIBS";							FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listLibsFiles|--listLibsFiles)
			PROCESS_ITEM="LIBS";							FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromLibs|--removeFromLibs)
			PROCESS_ITEM="LIBS";							FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToProperties|--copyToProperties)
			PROCESS_ITEM="PROPERTIES";						FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listPropertiesFiles|--listPropertiesFiles)
			PROCESS_ITEM="PROPERTIES";						FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-viewPropertiesFile|--viewPropertiesFile)
			PROCESS_ITEM="PROPERTIES";						FUNCTION_NAME="viewFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-removeFromProperties|--removeFromProperties)
			PROCESS_ITEM="PROPERTIES";						FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToXsl|--copyToXsl)
			PROCESS_ITEM="XSL";								FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listXslFiles|--listXslFiles)
			PROCESS_ITEM="XSL";								FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromXsl|--removeFromXsl)
			PROCESS_ITEM="XSL";								FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToScripts|--copyToScripts)
			PROCESS_ITEM="SCRIPTS";							FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listScriptsFiles|--listScriptsFiles)
			PROCESS_ITEM="SCRIPTS";							FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromScripts|--removeFromScripts)
			PROCESS_ITEM="SCRIPTS";							FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyToSwidtag|--copyToSwidtag)
			PROCESS_ITEM="SWIDTAG";							FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-listSwidtagFiles|--listSwidtagFiles)
			PROCESS_ITEM="SWIDTAG";							FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=0
			;;
		-removeFromSwidtag|--removeFromSwidtag)
			PROCESS_ITEM="SWIDTAG";							FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-copyFile|--copyFile)
			PROCESS_ITEM="CUSTOM_FILE";						FUNCTION_NAME="copyFile";				NUMBER_OF_PARAMS_REQUIRED=2
			;;
		-listFiles|--listFiles)
			PROCESS_ITEM="CUSTOM_FILE";						FUNCTION_NAME="listFiles";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-removeFile|--removeFile)
			PROCESS_ITEM="CUSTOM_FILE";						FUNCTION_NAME="removeFile";				NUMBER_OF_PARAMS_REQUIRED=1
			;;
		-help|--help)
			displayHelp
			exit 0
			;;
		-version|--version)
			displayVersion
			exit 0
			;;
		*)	if [[ "${ARGS}" =~ ^-.* ]]; then
				printf "\nInvalid option!\n\n"
				displayHelp
				exit 1
			fi
			COUNT_OF_OPTIONS=$((COUNT_OF_OPTIONS - 1))
			if [[ "${OPTIONS_ARRAY[-1]}" = "DEPLOYMENT" ]]; then
				DEPLOYMENT="${ARGS}"
				DEPLOYMENTPARAMS+=("${ARGS[@]}")
			else
				PARAMS+=("${ARGS[@]}")
			fi
			;;
	esac

	if [[ -n "${PROCESS_ITEM}" ]]; then
		if [[ "$(optionsArrayContains "${PROCESS_ITEM}")" = "false" ]]; then
			OPTIONS_ARRAY+=("${PROCESS_ITEM}")
		fi
	fi

	if [[ "${COUNT_OF_OPTIONS}" -gt 1 ]]; then
		printf "\nOnly 1 option apart from -deploymentName option can be used with this utility. Aborting!\n\n"
		printf "Run below command to see all options and parameter details:\n\n"
		printf "./adapterUtil.sh --help\n\n"
		exit 2
	fi
done

if [[ ${#DEPLOYMENTPARAMS[@]} -ne 1 ]] && [[ "$(optionsArrayContains "DEPLOYMENT")" = "true" ]]; then
	printf "\nThe -deploymentName expects 1 parameter, found %s. Aborting!\n\n" "${#DEPLOYMENTPARAMS[@]}"
	printf "Run below command to see all options and parameter details:\n\n"
	printf "./adapterUtil.sh --help\n\n"
	exit 3
fi

if [[ -z "${PROCESS_ITEM}" ]]; then
	printf "\nNo options specified!\n\n"
	printf "Run below command to see all options and parameter details:\n\n"
	printf "./adapterUtil.sh --help\n\n"
	exit 5
fi

if [[ ${#PARAMS[@]} -ne "${NUMBER_OF_PARAMS_REQUIRED}" ]]; then
	printf "\nParameters for given option doesn't match. Expected count of parameters is %s, found %s. Aborting!\n\n" "${NUMBER_OF_PARAMS_REQUIRED}" "${#PARAMS[@]}"
	printf "Run below command to see all options and parameter details:\n\n"
	printf "./adapterUtil.sh --help\n\n"
	exit 6
fi

setup

${FUNCTION_NAME}

exit 0
