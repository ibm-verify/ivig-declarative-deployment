#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

usage() {
  cat <<EOM
Recreate silent intstaller response files for initial data tier setup or upgrade
by extracting configuration information from 'data/erRole*.properties' files
usage: $0 [OPTION...]

Options:
   -i|--install     create dbConfig.properties and ldapConfig.properties to be
                    used for initial setup via 'dbConfig.sh' and 'ldapConfig.sh'
   -u|--upgrade     create minimal response files for '*Config.sh --upgrade'
EOM
  exit 1
}

case $1 in
  -i|--install) OP="install";;
  -u|--upgrade) OP="upgrade";;
  *) usage;;
esac

INPUT1="/opt/ibm/wlp/usr/servers/defaultServer/config/data/enRoleLDAPConnection.properties"
INPUT2="/opt/ibm/wlp/usr/servers/defaultServer/config/data/enRole.properties"
INPUT3="/opt/ibm/wlp/usr/servers/defaultServer/config/data/enRoleDatabase.properties"
OUTPUT1="/work/ldapConfig.properties"
OUTPUT2="/work/dbConfig.properties"

swap_enc_cred() {
  PATTERN=$1
  FILE=$2

  ENC=$(sed -n "s/^[a-zA-Z0-9\.]*${PATTERN}=\(.*\)$/\1/p" $FILE)

  if [ "x$ENC" = "x" ]; then
    echo "Skipping empty $PATTERN"
    return 3
  fi

  PLAIN=$(/work/encryptionHelper.sh decrypt ${ENC})
  # in property values within properties files, \, #, :, = and ! MUST be escaped
  PLAIN=$(echo $PLAIN | sed 's/\([\\#:=!]\)/\\\1/g')

  # escaping for sed in the rare case PLAIN contains ;
  sed -i "s;\(${PATTERN}\)=.*\$;\1=${PLAIN//;/\\;};" ${FILE}
}

if [ "x$OP" = "xupgrade" ]; then # only create minimal DB response for upgrade
  sed -n -e 's/^\(database\.db\.admin.*\)=\(.*\)$/dbConfigResponse.\1=\2/p' -e 's/^database\.\(tablespace.*\)=\(.*\)$/dbConfigResponse.\1=\2/p' $INPUT3 > $OUTPUT2
  swap_enc_cred adminPwd $OUTPUT2 && exit 0
fi # else, recreate full response files for both DB and LDAP

sed -n 's/^\(java\.naming\.security\.[^a].*\)=\(.*\)$/ldapConfigResponse.\1=\2/p' $INPUT1 > $OUTPUT1
sed -n 's/^java.naming.provider.url=.*\/\/\(.*\):\(.*\)/ip=\1\nport=\2/p' $INPUT1 | sed 's/^/ldapConfigResponse.enrole.ldapserver./' >> $OUTPUT1
sed -n 's/^enrole\.\(ldapserver\.root\|organization\.name\|defaulttenant\.id\)=\(.*\)$/ldapConfigResponse.enrole.\1=\2/p' $INPUT2 >> $OUTPUT1
cat <<EOM>> $OUTPUT1
ldapConfigResponse.enrole.ldapserver.hashBuckets=1
ldapConfigResponse.javax.net.ssl.trustStore=
ldapConfigResponse.javax.net.ssl.trustStorePassword=
EOM

sed -n -e 's/^\(database\.db.*\)=\(.*\)$/dbConfigResponse.\1=\2/p' -e 's/^database\.\(tablespace.*\)=\(.*\)$/dbConfigResponse.\1=\2/p' $INPUT3 > $OUTPUT2
sed -n -e 's/^database\.jdbc\.driverUrl=.*\(@\|\/\/\)\(.*\):\([^:\/]*\)[:/]\([^:?]*\).*/ip=\2\nport=\3\nname=\4/p' \
       -e 's/^database\.jdbc\.driverUrl=.*@(DESCRIPTION=.*(HOST=\([^)]*\)).*(PORT=\([^)]*\)).*(\(SID\|SERVICE_NAME\)=\([^)]*\)).*$/ip=\1\nport=\2\nname=\4/p' $INPUT3 \
    | sed 's/^/dbConfigResponse.database.db./' >> $OUTPUT2
sed -i -e 's/^dbConfigResponse\.database\.db\.type=/dbtype=/' -e 's/^dbtype=POSTGRESQL/dbtype=POSTGRES/' $OUTPUT2

swap_enc_cred credentials $OUTPUT1
swap_enc_cred password $OUTPUT2
swap_enc_cred adminPwd $OUTPUT2

