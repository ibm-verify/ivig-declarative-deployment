#!/bin/bash

# Enable debug mode
DEBUG=${DEBUG_INIT:-"false"}
DEBUG=$(echo "$DEBUG" | awk '{ print tolower($1) }')
if [[ "$DEBUG" = "true" ]]; then
	set -x
fi

SVRDIR="/opt/ibm/wlp/usr/servers/defaultServer"
BOOTSTRAP="${SVRDIR}/bootstrap.properties"
CERTDIR="${SVRDIR}/resources/security"
CONFDIR="${SVRDIR}/config/server"
TRUSTSTORE="isvgimTruststore.jks"
KEYSTORE="isvgimKeystore.jks"
KEY="/work/isvgim.key"
CERT="/work/isvgim.cert"
CACERT="/work/isvgim.cacert"
LDAPCFG="/work/ldapConfig.properties"
OIDCCFG="openidClient.xml"
SSLFILE="${CONFDIR}/sslConfig.xml"
CACERTS="/opt/ibm/java/jre/lib/security/cacerts"
CACERTSPASS="changeit"

JAVA="/opt/ibm/java/jre/bin/java"
EAR_DIR="/opt/ibm/wlp/usr/servers/defaultServer/apps/EAR_STANDARD.ear"
SVR_LIB="/opt/ibm/wlp/usr/servers/defaultServer/lib"
EXEC=com.ibm.itim.container.install.YamlConfigParser

CLASSPATH="${EAR_DIR}/lib/itim_server_1.0.0.jar"
CLASSPATH="$CLASSPATH:${SVR_LIB}/snakeyaml-2.1.jar"

"$JAVA" -cp "$CLASSPATH" $EXEC "$@"
RC=$?
if [[ $RC -ne 0 ]]; then
	exit "$RC"
fi

handle_disableTLSv12() {
	if [[ "$1" = "true" ]]; then
		sed -i 's/TLSv1.2,//' "$SSLFILE"
	fi
} #handle_disableTLSv12

handle_enableFIPS() {
	if [[ "$1" = "true" ]]; then
		/work/enableFIPS.sh
		# In case of FIPS only supported protocol is TLSv1.2. So disable TLSv1.3
		sed -i 's/\(sslProtocol="\).*\(" \/>\)/\1TLSv1.2\2/' "$SSLFILE"
	fi
} #handle_enableFIPS

handle_secureSessionCookies() {
	if [[ "$1" = "true" ]]; then
		sed -i '/<\/server>/i\
		<httpSession cookieSecure="true" cookieHttpOnly="true" />' "${CONFDIR}/endpoint.xml"
	fi
} #handle_secureSessionCookies

handle_globalHSTS() {
	if [[ "$1" = "true" ]]; then
		sed -i '/<\/server>/i\
		<webContainer addstricttransportsecurityheader="max-age=31536000;includeSubDomains" />' "${CONFDIR}/endpoint.xml"
	fi
} #handle_globalHSTS()

handle_hideServerVersion() {
	if [[ "$1" = "true" ]]; then
		sed -i '/<\/server>/i\
		<httpDispatcher enableWelcomePage="false" />\
		<httpOptions removeServerHeader="true" />\
		<webContainer disableXPoweredBy="true" />' "${CONFDIR}/endpoint.xml"
	fi
} #handle_hideServerVersion()

process_flags() {
	while IFS= read -r line; do
		flagName=$(echo "$line" | cut -d '=' -f 1)
		flagValue=$(echo "$line" | cut -d '=' -f 2-)
		handle_"$flagName" "$flagValue"
	done < /work/flags
} #process_flags


# Copy OIDC settings if they exist
if [[ -f /work/$OIDCCFG ]]; then
	cp "/work/$OIDCCFG" "${CONFDIR}/$OIDCCFG"
fi

# Handle options
if [[ -f /work/options ]]; then
	/work/processOptions.sh
fi

# Handle flags
if [[ -f /work/flags ]]; then
	process_flags
fi

# Add CA certs to truststore
PASS=$(/work/randomPassword.sh)
RESULT=$(keytool -genkeypair -keyalg RSA -alias boguscert -storepass "$PASS" -keypass secretPassword -keystore "${CERTDIR}/${TRUSTSTORE}" -storetype jks -dname "CN=IVIG" 2>&1)
RESULTCODE=$?
if [[ $RESULTCODE -ne 0 ]]; then
	echo "Failed to create the IVIG truststore"
	echo "$RESULT"
	exit "$RESULTCODE"
fi
keytool -delete -alias boguscert -storepass "$PASS" -keystore "${CERTDIR}/${TRUSTSTORE}" > /dev/null
ENCPWD=$(/opt/ibm/wlp/bin/securityUtility encode --encoding=aes "$PASS" | grep -v IBMJCEPlusFIPS)
echo "liberty.truststore.password=$ENCPWD" >> "$BOOTSTRAP"
if ls /work/cacert.* > /dev/null 2>&1; then
	for CAFILE in /work/cacert.*; do
		[[ -e "$CAFILE" ]] || continue
		csplit -z -s -f "${CAFILE}_" "$CAFILE" '/END CERTIFICATE/+1' '{*}'
	done
	for CA in /work/cacert.*_*; do
		ALIAS="$CA"
		keytool -importcert -noprompt -keystore "${CERTDIR}/${TRUSTSTORE}" -storepass "$PASS" -storetype jks -file "$CA" -alias "$ALIAS" | grep -v IBMJCEPlusFIPS
		keytool -importcert -noprompt -keystore "$CACERTS" -storepass "$CACERTSPASS" -storetype jks -file "$CA" -alias "$ALIAS" | grep -v IBMJCEPlusFIPS
	done
	rm /work/cacert.*_*

	if ls /work/oidc-*.crt > /dev/null 2>&1; then
		for CA in /work/oidc-*.crt; do
			[[ -e "$CA" ]] || continue
			if [[ $CA =~ oidc-(.*).crt ]]; then
				ALIAS=${BASH_REMATCH[1]}
			else
				ALIAS=$CA
			fi
			keytool -importcert -noprompt -keystore "${CERTDIR}/${TRUSTSTORE}" -storepass "$PASS" -storetype jks -file "$CA" -alias "$ALIAS" | grep -v IBMJCEPlusFIPS
			keytool -importcert -noprompt -keystore "$CACERTS" -storepass "$CACERTSPASS" -storetype jks -file "$CA" -alias "$ALIAS" | grep -v IBMJCEPlusFIPS
		done
	fi

	# Tell ldapConfig the pwd so it and dbConfig can access the truststore
	if [[ -f ${LDAPCFG} ]]; then
		sed -i "s;\(ldapConfigResponse\.javax\.net\.ssl\.trustStore=\).*\$;\1${CERTDIR}/${TRUSTSTORE};" "${LDAPCFG}"
		sed -i "s;\(ldapConfigResponse\.javax\.net\.ssl\.trustStorePassword=\).*\$;\1${PASS};" "${LDAPCFG}"
	fi

	PASS=$(/work/encryptionHelper.sh encrypt "$PASS")
	sed -i "s;\(javax.net.ssl.trustStorePassword=\).*\$;\1${PASS};" "${SVRDIR}/config/data/enRoleLDAPConnection.properties"
	# Tell enRoleMail the pwd so it can access the cacerts
	MAILPASS=$(/work/encryptionHelper.sh encrypt "$CACERTSPASS")
	sed -i "s;\(mail.javax.net.ssl.trustStorePassword=\).*\$;\1${MAILPASS};" "${SVRDIR}/config/data/enRoleMail.properties"
	sed -i "s;\(mail.javax.net.ssl.trustStore=\).*\$;\1${CACERTS};" "${SVRDIR}/config/data/enRoleMail.properties"
fi

# Setup SSL keystore
if [[ ! -f $KEY ]]; then
	# SSL cert not supplied, create one
	/work/certificateUtil.sh isvgim
	mv /work/isvgim.crt "$CERT"
	cp /work/isvgimRootCA.crt "$CACERT"
fi

# Create PKCS12 file to match cert and key
PKCS12PASS=$(/work/randomPassword.sh)
PASS=$(/work/randomPassword.sh)
# If keystore already exists, replace it with our new one
if [[ -f ${CERTDIR}/${KEYSTORE} ]]; then
	rm "${CERTDIR}/${KEYSTORE}"
fi
openssl pkcs12 -export -in "$CERT" -inkey "$KEY" -out /work/isvgim.p12 -name default -CAfile "$CACERT" -caname root -password pass:"$PKCS12PASS"
RESULT=$(keytool -importkeystore -deststorepass "$PASS" -destkeypass "$PASS" -destkeystore "${CERTDIR}/${KEYSTORE}" -srckeystore /work/isvgim.p12 -srcstoretype PKCS12 -srcstorepass "$PKCS12PASS" -alias default 2>&1)
RESULTCODE=$?
if [[ $RESULTCODE -ne 0 ]]; then
	echo "Failed to create the IVIG keystore"
	echo "$RESULT"
	exit "$RESULTCODE"
fi
ENCPWD=$(/opt/ibm/wlp/bin/securityUtility encode --encoding=aes "$PASS" | grep -v IBMJCEPlusFIPS)
echo "liberty.keystore.password=$ENCPWD" >> "$BOOTSTRAP"

