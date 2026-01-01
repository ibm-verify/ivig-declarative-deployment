#!/bin/bash

OUTPUT="./secrets.yaml"

rnd_b64() {
  openssl rand -base64 12 # generate random 16 characters of the base64 alphabet
}

cd $(dirname "${BASH_SOURCE[0]}" )
[ -f $OUTPUT ] && echo "Found $OUTPUT, not generating new secrets." && exit 1

echo "Generating random secrets..."

# LDAP password policy: minLength 8, minAlpha 2, minOther 2, maxRepeated 2
while true; do
    LDAPPW=$(rnd_b64)
    grep -qE -e '^[^a-zA-Z]*[a-zA-Z]?[^a-zA-Z]*$' -e '^[a-zA-Z]*[^a-zA-Z]?[a-zA-Z]*$' -e '(.)\1{2}' <<< $LDAPPW || break
done

DBPW=$(rnd_b64)

cat <<EOF >> $OUTPUT
MQLOCAL_PASSWORD: $(rnd_b64)
MQSHARE_PASSWORD: $(rnd_b64)
MQADMIN_PASSWORD: $(rnd_b64)
LDAP_PASSWORD: $LDAPPW 
DB_PASSWORD: $DBPW
DBADMIN_PASSWORD: $DBPW
APPSERVER_PASSWORD: $(rnd_b64)
ISIMSYSTEM_PASSWORD: $(rnd_b64)
MAIL_PASSWORD: $(rnd_b64)
OIDC_ISC_SECRET: $(rnd_b64)
OIDC_REST_SECRET: $(rnd_b64)
OIDC_ADMINCONSOLE_SECRET: $(rnd_b64)
ITIMCIPHER_KEY: $(openssl rand -base64 16)
EOF

echo "Done."
