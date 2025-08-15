#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: renewCerts.sh"
	echo "When to run: Annually to update auto-generated SSL certificates."
	echo "Description:"
	echo "   Certificates will expire in just over one year.  This utility will renew them."
	echo "   The updated certificates will be added to the ConfigMap, but all pods"
	echo "   must be restarted for the change to take effect."
	echo "Options:"
	echo "   -check: Will report on the current expiration date for each certificate"
	echo "Example usage:"
	echo "   $ ./renewCerts.sh"
	echo "   $ ./renewCerts.sh -check"
	echo ""
	exit 0
fi

cd $(dirname ${BASH_SOURCE[0]})
CERTFILE="../config/certs.tgz"
NS=$(./sys/getNamespace.sh)
kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

POD=$($kubectl -n $NS get pods | grep isvgim-0 | awk '{ print $1 }')
if [ "x$POD" = "x" ]; then
	echo "Unable to find name of ISVGIM pod using grep and awk"
	echo "Try manually running: kubectl -n $NS get pods | grep isvgim-0 | awk '{ print \$1 }'"
	exit 8
fi

# Collect the certs and upload them to the pod
(cd ../config; tar zcf certs.tgz certs)
$kubectl -n $NS -c isvgim cp $CERTFILE $POD:/work/certs.tgz
rm $CERTFILE
$kubectl -n $NS -c isvgim exec $POD -- /work/renewCerts.sh $1
if [ $(echo $?) -ne 0 ]; then
	echo "Unable to exec into pod."
	exit 19
fi

# Download the results and store them in ConfigMap
if [ "x$1" = "x" ]; then
	$kubectl -n $NS -c isvgim cp $POD:/work/certs.tgz $CERTFILE > /dev/null 2>&1
	$kubectl -n $NS -c isvgim exec $POD -- /bin/bash -c "rm /work/certs.tgz"
	(cd ../config; tar zxf $CERTFILE)
	rm $CERTFILE
	printf "Generating ConfigMaps..."
	for TYPE in setup ldap db isvdi mq; do
		./createConfigs.sh $TYPE > /dev/null
		RC=$(echo $?)
		if [ $RC -ne 0 ]; then
			if [ "x$1" = "x" ]; then
				echo "Errors creating ConfigMap for $TYPE"
			fi
			exit $RC
		fi
		printf "."
	done
	printf "Done!\n"
fi
