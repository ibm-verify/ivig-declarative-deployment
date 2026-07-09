#!/bin/bash

# Enable debug mode
DEBUG=${DEBUG_INIT:-"false"}
DEBUG=$(echo $DEBUG | awk '{ print tolower($1) }')
if [ "$DEBUG" = "true" ]; then
  set -x
fi

DATADIR="/opt/ibm/wlp/usr/servers/defaultServer/config/data"
DESTDIR="/tmp/export"

inject_ext_cred() {
  if [ "x${!1}" = "x" ]; then
    echo "Skipping injection of empty $1"
    return 3
  fi

  PATTERN=$2
  ENCRYPTED=$(/work/encryptionHelper.sh encrypt ${!1} | tr -d "\n")
  FILE=$3

  # PATTERN MUST be escaped upfront. ENCRYPTED will never contain ';'
  sed -i "s;\(${PATTERN}\).*\$;\1${ENCRYPTED};" ${DATADIR}/${FILE}
}

echo "Starting PRE-INIT script"

cp -rLv /tmp/isvgimks/* /tmp/isvgimdata/* ${DATADIR}/

/work/init/setup-keystore.sh || echo "exit 7"

inject_ext_cred EXT_APPSERVER_PASSWORD 'enrole\.appServer\.systemUser\.credentials=' enRole.properties
inject_ext_cred EXT_ISIMSYSTEM_PASSWORD 'enrole\.appServer\.ejbuser\.credentials=' enRole.properties
inject_ext_cred EXT_DBADMIN_PASSWORD 'database\.db\.adminPwd=' enRoleDatabase.properties
inject_ext_cred EXT_DB_PASSWORD 'database\.db\.password=' enRoleDatabase.properties
inject_ext_cred EXT_LDAP_PASSWORD 'java\.naming\.security\.credentials=' enRoleLDAPConnection.properties
inject_ext_cred EXT_MAIL_PASSWORD 'mail\.smtp\.auth\.password=' enRoleMail.properties

echo "Exporting KS and DATA"

cp -rLv ${DATADIR}/{encryptionKey.properties,keystore} /tmp/isvgimdata/* ${DESTDIR}/
cp -rLv ${DATADIR}/enRole{,Database,LDAPConnection,Mail}.properties ${DESTDIR}/

echo "Exiting PRE-INIT script"
