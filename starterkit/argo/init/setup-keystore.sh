#!/bin/bash

# Enable debug mode
DEBUG=${DEBUG_INIT:-"false"}
DEBUG=$(echo $DEBUG | awk '{ print tolower($1) }')
if [ "$DEBUG" = "true" ]; then
  set -x
fi

JAVA="/opt/ibm/java/jre/bin/java"
KERNEL_SERVICE_JAR=$(find /opt/ibm/wlp/lib/ -name 'com.ibm.ws.kernel.service_*.jar')
IM_HOME="/opt/ibm/wlp/usr/servers/defaultServer/config"
CLASSPATH="/opt/ibm/wlp/usr/servers/defaultServer/apps/EAR_STANDARD.ear/lib/itim_server_1.0.0.jar:\
${IM_HOME}/data:${KERNEL_SERVICE_JAR}:/work/init/cipherkey-injector.jar:\
/opt/ibm/wlp/usr/servers/defaultServer/lib/jlog-1.0.jar"

echo "Starting SETUP-KEYSTORE script"

KS=${IM_HOME}/data/keystore/itimKeystore.jceks
KEYPASS=$(/work/randomPassword.sh)

if [ ! -f $KS ]; then
  "$JAVA" -cp "$CLASSPATH" com.ibm.itim.container.install.KeystoreConfig $IM_HOME $KEYPASS || exit 7
  if [ "x$EXT_ITIMCIPHER_KEY"  = "x"  ]; then
    echo "No cipher key provided, cannot dynamically inject data encryption key."
    exit 11
  fi
  "$JAVA" -cp "$CLASSPATH" com.ibm.sel.itim.util.ITIMCipherKeyInjector $KS $KEYPASS $EXT_ITIMCIPHER_KEY || exit 17
fi

echo "Exiting SETUP-KEYSTORE script"
