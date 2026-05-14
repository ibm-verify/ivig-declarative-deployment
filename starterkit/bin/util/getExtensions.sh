#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: getExtensions.sh"
	echo "When to run: When first needing to access the Extensions content"
	echo "Description:"
	echo "   Identity Governance provides Extensions to help with docs and configurations."
	echo "   To access this content, run this script to copy the data from the pod to your host."
	echo "Extensions usage:"
	echo "   $ ./getExtensions.sh"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh
get_namespace || die "Unable to get namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

POD=isvgim-0
FILENAME="/tmp/extensions.tgz"
SERVERDIR="/opt/ibm/wlp/usr/servers/defaultServer"
EARDIR="$SERVERDIR/apps/EAR_STANDARD.ear"
SERVERLIBDIR="$SERVERDIR/lib"
EXTENSIONS="/work/extensions"
ISVGIM_VERSION="11.0.0"
EXAMPLES="$EXTENSIONS/$ISVGIM_VERSION/examples"
CLIENTFILES="$EXAMPLES/config/clientFiles"
BOOTSTRAPFILE="$CLIENTFILES/bootstrap.properties"
WLPDEVAPIIBMDIR="/opt/ibm/wlp/dev/api/ibm/"
WLPDEVAPITHIRDPARTYDIR="/opt/ibm/wlp/dev/api/third-party"
WLPDEVAPISPECDIR="/opt/ibm/wlp/dev/api/spec"
WLPLIBDIR="/opt/ibm/wlp/lib"
echo "Collecting files"

cat <<EOF > ../getExtensions
#!/bin/bash
FILENAME="/tmp/extensions.tgz"

cp ${EARDIR}/lib/itim_common_*.jar ${EXAMPLES}/lib
cp ${EARDIR}/lib/itim_api_*.jar ${EXAMPLES}/lib
cp ${EARDIR}/lib/itim_server_api_*.jar ${EXAMPLES}/lib
cp ${EARDIR}/lib/itim_server_*.jar ${EXAMPLES}/lib
cp ${EARDIR}/lib/itim_ws_model_*.jar ${EXAMPLES}/lib
cp ${EARDIR}/com.ibm.security.certmgr.core.rest-*.war/WEB-INF/lib/slf4j-api-*.jar ${EXAMPLES}/lib
cp ${EARDIR}/lib/com.ibm.isim.util_*.jar ${EXAMPLES}/lib

cp ${SERVERLIBDIR}/jlog-*.jar ${EXAMPLES}/lib
cp ${SERVERLIBDIR}/commons-logging-*.jar ${EXAMPLES}/lib

cp ${WLPDEVAPIIBMDIR}/com.ibm.websphere.appserver.api.security_*.jar ${EXAMPLES}/lib
cp ${WLPDEVAPIIBMDIR}/com.ibm.websphere.appserver.api.json_*.jar ${EXAMPLES}/lib
cp ${WLPDEVAPISPECDIR}/com.ibm.websphere.javaee.jaxrs.2.1_*.jar ${EXAMPLES}/lib
cp ${WLPDEVAPISPECDIR}/com.ibm.websphere.javaee.servlet.4.0_1.0.*.jar ${EXAMPLES}/lib
cp ${WLPLIBDIR}/com.ibm.ws.org.apache.httpcomponents_*.jar ${EXAMPLES}/lib
cp ${WLPLIBDIR}/com.ibm.json4j_*.jar ${EXAMPLES}/lib

sed -n '/enrole.platform.contextFactory/p' /opt/ibm/wlp/usr/servers/defaultServer/config/data/enRole.properties > $BOOTSTRAPFILE
sed -n '/enrole.appServer.url/p' /opt/ibm/wlp/usr/servers/defaultServer/config/data/enRole.properties >> $BOOTSTRAPFILE
sed -n '/enrole.appServer.realm/p' /opt/ibm/wlp/usr/servers/defaultServer/config/data/enRole.properties >> $BOOTSTRAPFILE
sed -n '/enrole.defaulttenant.id/p' /opt/ibm/wlp/usr/servers/defaultServer/config/data/enRole.properties >> $BOOTSTRAPFILE
sed -n '/enrole.ldapserver.root/p' /opt/ibm/wlp/usr/servers/defaultServer/config/data/enRole.properties >> $BOOTSTRAPFILE
echo 'itim.user="itim manager"' >> $BOOTSTRAPFILE
echo itim.pswd=secret >> $BOOTSTRAPFILE

mkdir -p ${EXAMPLES}/itim_console.war
cd ${EARDIR}/itim_console.war
tar czf ${EXAMPLES}/itim_console.war/custom.tgz css designform html jsp subforms WEB-INF/web.xml
mkdir -p ${EXAMPLES}/isim_isc_subform.war
cd ${EARDIR}/isim_isc_subform.war
tar czf ${EXAMPLES}/isim_isc_subform.war/custom.tgz subforms WEB-INF/web.xml
mkdir -p ${EXAMPLES}/ISC_UI.war
cd ${EARDIR}/ISC_UI.war
tar czf ${EXAMPLES}/ISC_UI.war/custom.tgz custom

cd /work
tar czf $FILENAME extensions
rm getExtensions
EOF

RESULT=$($kubectl -n "$NS" cp ../getExtensions "$POD":/work/getExtensions -c isvgim)
if [[ $? -ne 0 ]]; then
	echo "ERROR: Unable to upload script to the pod."
	echo "$RESULT"
	exit 1
fi


RESULT=$($kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /work/getExtensions)
if [[ $? -ne 0 ]]; then
	echo "ERROR: Unable to collect files in the pod."
	echo "$RESULT"
	exit 2
fi

echo "Downloading files"
RESULT=$($kubectl -n "$NS" cp "${POD}":"$FILENAME" ../extensions.tgz)
if [[ $? -ne 0 ]]; then
	echo "ERROR: Unable to copy files from pod."
	echo "$RESULT"
	exit 3
fi
RESULT=$($kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash -c "rm $FILENAME")
if [[ $? -ne 0 ]]; then
	echo "ERROR: Unable to clean up pod."
	echo "$RESULT"
	exit 4
fi

# Check if the file exists
ls ../extensions.tgz > /dev/null 2>&1
if [[ $? -eq 2 ]]; then
	echo "ERROR: Extensions file not found."
	exit 5
fi

cd .. > /dev/null 2>&1
echo "Unpacking extensions to $PWD/extensions"
tar zxf extensions.tgz > /dev/null 2>&1
rm extensions.tgz > /dev/null 2>&1
rm getExtensions > /dev/null 2>&1

echo "Updating custom files in $PWD/custom"
mkdir -p custom/jars > /dev/null 2>&1
DIRS="isim_isc_subform.war itim_console.war ISC_UI.war"
for DIR in $DIRS; do
	mkdir -p "custom/$DIR" > /dev/null 2>&1
	mv "extensions/$ISVGIM_VERSION/examples/$DIR/custom.tgz" "custom/$DIR/custom.tgz" > /dev/null 2>&1
	rmdir "extensions/$ISVGIM_VERSION/examples/$DIR" > /dev/null 2>&1
	cd "custom/$DIR" || die "custom/$DIR does not exist" $? > /dev/null 2>&1
	tar zxf custom.tgz > /dev/null 2>&1
	rm custom.tgz > /dev/null 2>&1
	cd ../.. > /dev/null 2>&1
done

echo "Done!"
