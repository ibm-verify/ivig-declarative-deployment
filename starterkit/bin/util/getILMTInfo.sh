#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: getILMTInfo.sh"
	echo "When to run: Monthly to refresh token and certificate of License Server"
	echo "Description:"
	echo "   When using the User Value Units license metric, a token an certificate are needed"
	echo "   for the application to publish this information.  They are stored in the"
	echo "   ibm-common-services namespace, but the information must be copied into the IM namespace."
	echo "Usage:"
	echo "   $ ./getILMTInfo.sh"
	echo ""
	exit 0
fi

IBMNS="ibm-common-services"

cd $(dirname ${BASH_SOURCE[0]})
NS=$(../sys/getNamespace.sh)

kubectl=$(../sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

$kubectl get ns -o name | grep -q "namespace/${IBMNS}$"
if [ $(echo $?) -ne 0 ]; then
	echo "${IBMNS} not found.  Assuming IBM License Server is not installed yet."
	exit 1
fi

if [ "x$OFFLINE" != "x1" ]; then
	echo "Importing License Server connection information"
	$kubectl -n $NS delete --ignore-not-found=true secret ibm-licensing-upload-token
	$kubectl -n $NS delete --ignore-not-found=true cm ibm-licensing-upload-config
	$kubectl get secret ibm-licensing-upload-token -n ${IBMNS} -oyaml | grep -v "namespace: ${IBMNS}" | kubectl apply -n ${NS} -f -
	$kubectl get cm ibm-licensing-upload-config -n ${IBMNS} -oyaml | grep -v "namespace: ${IBMNS}" | kubectl apply -n ${NS} -f -
else
	echo "Please run the following commands to import the IBM License Service tokens:"
	echo "$kubectl -n $NS delete --ignore-not-found=true secret ibm-licensing-upload-token"
	echo "$kubectl -n $NS delete --ignore-not-found=true cm ibm-licensing-upload-config"
	echo "$kubectl get secret ibm-licensing-upload-token -n ${IBMNS} -oyaml | grep -v \"namespace: ${IBMNS}\" | kubectl apply -n ${NS} -f -"
	echo "$kubectl get cm ibm-licensing-upload-config -n ${IBMNS} -oyaml | grep -v \"namespace: ${IBMNS}\" | kubectl apply -n ${NS} -f -"
	read -n 1 -s -r -p "Once finished, press any key to continue..."
	printf "\n\n"
fi

