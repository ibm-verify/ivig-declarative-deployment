#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: install.sh"
	echo "When to run: When initially installing IVIG."
	echo "Description:"
	echo "   This is the main installation script.  It will call the necessary pieces to configure LDAP, DB, and the application."
	echo "   It will optionally deploy Verify Directory and Postgres pods for use with IVIG."
	echo "   You must fill in the details in config.yaml prior to running the installer."
	echo "config.yaml items:"
	echo "   1. Review the files in the license directory and set accepted to true."
	echo "   2. Specify a valid activationKey"
	echo "   3. Specify a password for the IVIG keystore."
	echo "   4. Specify LDAP information."
	echo "   5. Specify DB information."
	echo "   6. Place any SSL certificates and keys in PEM/ASCII format in the config directory. Update the truststore and keystore sections."
	echo "Options:"
	echo "   -manual: Nothing will be automatically loaded into kubernetes"
	echo "Example usage:"
	echo "   $ ./install.sh"
	echo "   $ ./install.sh -manual"
	echo ""
	exit 0
fi

if [[ "$1" = "-manual" ]]; then
	OFFLINE=1
else
	OFFLINE=0
fi
BACKUPDIR="../backup"
CFGFILE="../config/config.yaml"
PWDLENGTH=16
RUNDIR=$(dirname "${BASH_SOURCE[0]}")
cd "$RUNDIR"
source "./lib/common.sh"

trap user_abort INT

report_error() {
	echo ""
	echo "!!!!!!!!!!!!!!!!!!!!!!!"
	echo "Install failed due to:"
	case "$1" in
		"2") echo "kubectl not found in PATH"
			;;
		"3") echo "helm not found in PATH"
			;;
		"5") echo "helm failed to turn a template file into a full yaml"
			;;
		"6") echo "kubectl failed to install a yaml file into kubernetes"
			;;
		"7") echo "Unable to determine namespace from values.yaml file"
			;;
		"8") echo "Unable to schedule the ISVGIM Configuration Pod"
			;;
		"9") echo "kubectl failed to copy a properties file from the pod to the data directory"
			;;
		"10") echo "Failed to create the keystore.  Please review above messages for details"
			;;
		"11") echo "Error creating ConfigMap files.  Please review above messages for details"
			;;
		"12") echo "Failed to copy ldapConfig.properties into the pod"
			;;
		"13") echo "Failed to configure LDAP.  Please review above messages for details"
			;;
		"14") echo "Failed to copy dbConfig.properties into the pod"
			;;
		"15") echo "Failed to configure DB.  Please review above messages for details"
			;;
		"16") echo "kubectl failed to remove the ISVGIM deployment from kubernetes"
			;;
		"17") echo "keypass value missing from config.yaml"
			;;
		"18") echo "keypass value not set in config.yaml"
			;;
		"19") echo "You must specify a user for the DB in config.yaml"
			;;
		"20") echo "Application failed to start"
			;;
		"21") echo "You must specify a password for the DB in config.yaml"
			;;
		"22") echo "Error creating pgcreds secret"
			;;
		"23") echo "Invalid value specified for security.protocol in config.yaml"
			;;
		"24") echo "Unable to create certificates in config pod"
			;;
		"25") echo "Installation type was not specified in config.yaml"
			;;
		"26") echo "You must specify a password for the LDAP admin in config.yaml"
			;;
		"27") echo "You must specify a tenant id for LDAP in config.yaml"
			;;
		"28") echo "You must specify an organization name for LDAP in config.yaml"
			;;
		"29") echo "You must supply a valid ISVD license key in config.yaml"
			;;
		"30") echo "Error creating admin user.  Please review above message for details"
			;;
		"31") echo "Error adding user to admin group.  Please review above message for details"
			;;
		"32") echo "Error creating isvdcred secret"
			;;
		"33") echo "You must specify a DN for the LDAP admin in config.yaml"
			;;
		"34") echo "Failed to fully transform a YAML template.  Please review above messages for details"
			;;
		"35") echo "Error creating mqcreds secret"
			;;
		"36") echo "config.yaml file is missing!"
			;;
		"37") echo "Unable to find namespace value in config.yaml"
			;;
		"38") echo "Unable to find storageclass value in config.yaml"
			;;
		"39") echo "Invalid installation type specified in config.yaml"
			echo "Must be: cloud or local"
			;;
		"40") echo "Error creating replication agreement.  Please review above messages for details"
			;;
		"41") echo "Error loading replication agreement LDIF.  Please review above messages for details"
			;;
		"42") echo "Invalid arguments passed to waitFor script.  Please contact support."
			;;
		"43") echo "Failed to copy tablespace script into the pod"
			;;
		"44") echo "Error creating OIDC placeholder secret"
			;;
		"45") echo "Error altering the config files for MQ"
			;;
		"46") echo "Failed to replace the channel setting in MQSC files for MQ"
			;;
		"47") echo "You must supply a valid ISVDI license key in config.yaml"
			;;
		"48") echo "Failed to install the enterprise key.  See messages above"
			;;
		*) echo "Unknown error!  Please review above messages for details"
			;;
	esac
	printf "\nAfter investigating the error, you can run bin/sys/cleanup.sh to reset the environment for another install attempt.\n"
} #report_error

user_abort() {
	printf "\n!!!!! Aborted by User !!!!!\n"
	./sys/cleanup.sh install
	exit 1
} #user_abort

parseInstall() {
	TYPEFLAG=$(grep "installType:" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$TYPEFLAG" ]]; then
		report_error 25
		exit 25
	else
		if [[ ! "$TYPEFLAG" = "cloud" ]] && [[ ! "$TYPEFLAG" = "local" ]]; then
			report_error 39
			exit 39
		fi
	fi

	TIMEOUTVAL=$(grep waitTimeout "$CFGFILE" | awk '{ print $2 }' | sed 's/[^0-9]*//g')
	if [[ -z "$TIMEOUTVAL" ]]; then
		TIMEOUTVAL=120
	fi

	# Verify keypass is set
	KP=$(grep keypass "$CFGFILE")
	if [[ $? -ne 0 ]]; then
		report_error 17
		exit 17
	fi
	RESULT=$(echo "$KP" | awk '{ print $2 }')
	if [[ -z "$RESULT" ]]; then
		report_error 18
		exit 18
	fi

	# Confirm security.protocol is blank or ssl
	LINES=$(grep security.protocol "$CFGFILE")
	while IFS= read -r LINE; do
		SSLVAL=$(echo "$LINE" | awk '{ print tolower($2) }')
		if [[ -n "$SSLVAL" ]] && [[ "$SSLVAL" != "ssl" ]]; then
			report_error 23
			exit 23
		fi
	done <<< "$LINES"


	# Unless settings exist and are set to true, they will be treated as false
	DBFLAG=$(grep "deployDb:" "$CFGFILE" | awk '{ print tolower($2) }')
	if [[ "$DBFLAG" = "true" ]]; then
		DBFLAG=1
		DBHAFLAG=$(grep "deployDbHA:" "$CFGFILE" | awk '{ print tolower($2) }')
		if [[ "$DBHAFLAG" = "true" ]]; then
			DBHAFLAG=1
		else
			DBHAFLAG=0
		fi
	else
		DBFLAG=0
		DBHAFLAG=0
	fi

	LDAPFLAG=$(grep "deployLdap:" "$CFGFILE" | awk '{ print tolower($2) }')
	if [[ "$LDAPFLAG" = "true" ]]; then
		LDAPFLAG=1
		LDAPHAFLAG=$(grep "deployLdapHA:" "$CFGFILE" | awk '{ print tolower($2) }')
		if [[ "$LDAPHAFLAG" = "true" ]]; then
			LDAPHAFLAG=1
		else
			LDAPHAFLAG=0
		fi
	else
		LDAPFLAG=0
		LDAPHAFLAG=0
	fi

	ISVDIFLAG=$(grep "deployIsvdi:" "$CFGFILE" | awk '{ print tolower($2) }')
	if [[ "$ISVDIFLAG" = "true" ]]; then
		ISVDIFLAG=1
	else
		ISVDIFLAG=0
	fi

	MAILFLAG=$(grep "useSMTPMail:" "$CFGFILE" | awk '{ print tolower($2) }')
	if [[ "$MAILFLAG" = "true" ]]; then
		MAILFLAG=1
		$SED '/mail/a \ \ enabled: true' "$CFGFILE"
	else
		$SED '/mail/a \ \ enabled: false' "$CFGFILE"
		MAILFLAG=0
	fi

	REGFLAG=$(grep "useExternalRegistry:" "$CFGFILE" | awk '{ print tolower($2) }')
	if [[ "$REGFLAG" = "true" ]]; then
		REGFLAG=1
		$SED '/externalRegistry/a \ \ enabled: true' "$CFGFILE"
	else
		$SED '/externalRegistry/a \ \ enabled: false' "$CFGFILE"
		REGFLAG=0
	fi
	
	FIPSFLAG=$(grep "enableFIPS:" "$CFGFILE" | awk '{ print tolower($2) }')
	if [[ "$FIPSFLAG" != "true" ]]; then
		FIPSFLAG=false
	fi

	LICOBJC=$(grep "licenseExternalObjectclass" "$CFGFILE" | awk '{ print tolower($2) }')
	LICATTR=$(grep "licenseExternalAttribute" "$CFGFILE" | awk '{ print $2 }')

	# Check for MQ passwords.  Local is always auto-generated.
	generate_alphanumeric_password "$PWDLENGTH"
	MQLPWD=$REPLY
	MQSPWD=$(grep mqSharePwd "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$MQSPWD" ]]; then
		generate_alphanumeric_password "$PWDLENGTH"
		MQSPWD=$REPLY
	fi
	MQAPWD=$(grep mqAdminPwd "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$MQAPWD" ]]; then
		generate_alphanumeric_password "$PWDLENGTH"
		MQAPWD=$REPLY
	fi

	# Check for Postgres admin credentails
	ADMUSER=$(grep "admin:" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$ADMUSER" ]]; then
		ADMUSER="postgres"
	fi

	ADMPASS=$(grep "adminPwd:" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$ADMPASS" ]]; then
		PGUSER=$(grep "user:" "$CFGFILE" | awk '{ print $2 }')
		if [[ "$PGUSER" = "$ADMUSER" ]]; then
			PGPASS=$(grep "password:" "$CFGFILE" | awk '{ print $2 }')
			if [[ -n "$PGPASS" ]]; then
				ADMPASS=$PGPASS
			else
				report_error 21
				exit 21
			fi
		else
			generate_alphanumeric_password "$PWDLENGTH"
			ADMPASS=$REPLY
		fi
	fi

	# Check for Enterprise Analytics Key
	RISK_KEY=$(grep "riskKey:" "$CFGFILE" | awk '{ print $2 }')

	# Collect DB Info
	DBTYPE=$(grep "dbtype:" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$DBTYPE" ]]; then
		DBTYPE=postgres
	fi
	DBHOST=$(grep "  ip:" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$DBHOST" ]]; then
		DBHOST=postgres
	fi
	DBPORT=$(grep "  port:" "$CFGFILE" | awk '{ print $2 }')
	if [[ -z "$DBPORT" ]]; then
		DBPORT=5432
	fi
	DBUSER=$(grep "  user:" "$CFGFILE" | awk '{ print $2 }')
	DBPASS=$(grep "  password:" "$CFGFILE" | awk '{ print $2 }')

	CUSTOMREPO_LOGIN=0
	CUSTOMREPOUSER=$(grep customRepoUser "$CFGFILE" | awk '{ print $2 }')
	CUSTOMREPOPWD=$(grep customRepoPwd "$CFGFILE" | awk '{ print $2 }')
	CUSTOMREPOURL=$(grep customRepoUrl "$CFGFILE" | awk '{ print $2 }')
	if [[ -n "$CUSTOMREPOUSER" ]] && [[ -n "$CUSTOMREPOPWD" ]] && [[ -n "$CUSTOMREPOURL" ]]; then
		CUSTOMREPO_LOGIN=1
	fi

	JFROG_LOGIN=0
	JFROGUSER=$(grep artifactoryUser "$CFGFILE" | awk '{ print $2 }')
	JFROGPWD=$(grep artifactoryPwd "$CFGFILE" | awk '{ print $2 }')
	JFROGBLD=$(grep artifactoryBuild "$CFGFILE" | awk '{ print $2 }')
	if [[ -n "$JFROGUSER" ]] && [[ -n "$JFROGPWD" ]]; then
		JFROG_LOGIN=1
	fi

	# Remove this section
	$SED '/    installType:/d' "$CFGFILE"
	$SED '/    waitTimeout:/d' "$CFGFILE"
	$SED '/    useExternalRegistry/d' "$CFGFILE"
	$SED '/    useSMTPMail/d' "$CFGFILE"
	$SED '/    deployLdap/d' "$CFGFILE"
	$SED '/    deployDb/d' "$CFGFILE"
	$SED '/    deployIsvdi/d' "$CFGFILE"
	$SED '/    mqSharePwd/d' "$CFGFILE"
	$SED '/    mqAdminPwd/d' "$CFGFILE"
	$SED '/    artifactory/d' "$CFGFILE"
	$SED '/    customRepo/d' "$CFGFILE"
	$SED '/    license/d' "$CFGFILE"

	# Store the values
	export INSTALL_TYPE=$TYPEFLAG
	export TIMEOUT=$TIMEOUTVAL
	export INSTALL_DB=$DBFLAG
	export INSTALL_DB_HA=$DBHAFLAG
	export INSTALL_LDAP=$LDAPFLAG
	export INSTALL_LDAP_HA=$LDAPHAFLAG
	export INSTALL_ISVDI=$ISVDIFLAG
	export EXTERNAL_REG=$REGFLAG
	export DBTYPE=$DBTYPE
	export DBHOST=$DBHOST
	export DBPORT=$DBPORT
	export DBUSER=$DBUSER
	export DBPASS=$DBPASS
	export MAIL=$MAILFLAG
	export MQLOCALPWD=$MQLPWD
	export MQSHAREPWD=$MQSPWD
	export MQADMINPWD=$MQAPWD
	export ADMUSER=$ADMUSER
	export ADMPASS=$ADMPASS
	export CUSTOMREPO_LOGIN=$CUSTOMREPO_LOGIN
	export CUSTOMREPOUSER=$CUSTOMREPOUSER
	export CUSTOMREPOPWD=$CUSTOMREPOPWD
	export CUSTOMREPOURL=$CUSTOMREPOURL
	export JFROG_LOGIN=$JFROG_LOGIN
	export JFROGUSER=$JFROGUSER
	export JFROGPWD=$JFROGPWD
	export JFROGBLD=$JFROGBLD
	export ENABLE_FIPS=$FIPSFLAG
	export LICENSE_EXT_OC=$LICOBJC
	export LICENSE_EXT_ATTR=$LICATTR
	export OFFLINE=$OFFLINE
} #parseInstall


# Start of main script
echo "Installing IVIG..."

# Backup required files
cp ../config/config.yaml ../config/config.bak
cp ../helm/values.yaml ../helm/values.bak
ls ../config/certs > ../.preserveCertsOnCleanup
cp ../config/mq/ISVGContainerQMgr.mqsc ../config/mq/ISVGContainerQMgr.mqsc.bak
cp ../config/mq/ISVGContainerQMgr-shared.mqsc ../config/mq/ISVGContainerQMgr-shared.mqsc.bak
cp ../config/mq/isvgqm.ini ../config/mq/isvgqm.ini.bak

# Checking for helm and kubectl
kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

# Check for sed version
get_sed_cmd
SED=$REPLY

# Parse install settings
./sys/updateValues.sh
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi
parseInstall

# Deploying isvgimconfig
printf "\n##### Deploying configuration pod #####\n"
sleep 1
./sys/startConfigContainer.sh install
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

# Deploy LDAP if desired
if [[ "$INSTALL_LDAP" -eq 1 ]]; then
	printf "\n##### Installing Verify Directory LDAP Server #####\n"
	sleep 1
	./sys/setupLDAP.sh install
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		report_error "$RC"
		exit "$RC"
	fi
fi

if [[ "$INSTALL_DB" -eq 1 ]]; then
	printf "\n##### Installing Postgresql Database Server #####\n"
	sleep 1
	./sys/setupDB.sh install
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		report_error "$RC"
		exit "$RC"
	fi
fi

# Create the keystore
printf "\n##### Generating Keystore #####\n"
sleep 1
./sys/createKeystore.sh install
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

# Restart config pod with keystore in place
printf "\n##### Updating Configuration Settings #####\n"
sleep 1
./sys/restartConfigContainer.sh install
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

# Configure LDAP
printf "\n##### Configuring LDAP #####\n"
sleep 1
./sys/ldapConfig.sh install
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

# Configure DB
printf "\n##### Configuring DB #####\n"
sleep 1
./sys/dbConfig.sh install
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

# Configure MAIL
if [[ "$MAIL" -eq 1 ]]; then
	printf "\n##### Configuring MAIL #####\n"
	sleep 1
	./sys/mailConfig.sh install
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		report_error "$RC"
		exit "$RC"
	fi
fi

# Deploying Adapter Dispatcher
if [[ "$INSTALL_ISVDI" -eq 1 ]]; then
	printf "\n##### Deploying ISVDI Adapter Dispatcher #####\n"
	sleep 1
	./sys/setupISVDI.sh --install
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		report_error "$RC"
		exit "$RC"
	fi
fi

if [[ "$EXTERNAL_REG" -eq 1 ]]; then
printf "\n##### Configuring External Registry #####\n"
	./sys/externalRegistryConfig.sh
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		report_error "$RC"
		exit "$RC"
	fi
fi

# Deploying ISVGIM
touch ../.installed
printf "\n##### Deploying application #####\n"
sleep 1
./sys/setupISVGIM.sh install
RC=$?
if [[ "$RC" -ne 0 ]]; then
	report_error "$RC"
	exit "$RC"
fi

if [[ -n "$RISK_KEY" ]]; then
printf "\n##### Configuring Analytics Engine #####\n"
	./sys/setupAnalytics.sh "$RISK_KEY"
	RC=$?
	if [[ "$RC" -ne 0 ]]; then
		report_error "$RC"
		exit "$RC"
	fi
fi

# Restarting pods to enable MQ SSL and apply analytics changes
# To restart the queue managers for applying some configuration changes to qm.ini file
get_namespace || die "Unable to determine namespace" $?
NS=$REPLY

ISVG_POD_STATUS=$($kubectl -n "$NS" get pod isvgim-0 -o jsonpath='{.status.phase}')
MQSHARE_POD=$($kubectl -n "$NS" get pods -o name | grep "mqshare-" | head -n 1 | cut -d'/' -f2)
MQSHARE_POD_STATUS=$($kubectl -n "$NS" get pod "$MQSHARE_POD" -o jsonpath='{.status.phase}')

if [[ "$ISVG_POD_STATUS" = "Running" ]] && [[ "$MQSHARE_POD_STATUS" = "Running" ]]; then
	./sys/restartMQ.sh ISVGQMgrShared >/dev/null 2>&1
	./sys/restartMQ.sh ISVGQueueMgr >/dev/null 2>&1
	$kubectl -n "$NS" rollout restart sts isvgim
	sleep 50
else
	echo "Either isvgim-0 pod or mqshare pod is not in the Running state"
fi

# Waiting for pod to be ready for FIPS
./sys/waitFor.sh isvgim-0 application
RC=$?
if [[ "$RC" -ne 0 ]]; then
	./getLogs.sh
	exit "$RC"
fi


printf "\nInstallation complete!\n"
# Remove backup config file
rm ../config/config.bak
rm ../helm/values.bak
rm ../config/mq/ISVGContainerQMgr.mqsc.bak
rm ../config/mq/ISVGContainerQMgr-shared.mqsc.bak
rm ../config/mq/isvgqm.ini.bak
IP=$(./sys/getIP.sh)
PORT=$($kubectl -n "$NS" get svc isvgim --no-headers 2>&1)
if [[ "$PORT" == Error* ]]; then
	PORT="30943"
else
	PORT=$(echo "$PORT" | awk '{ print $5 }' | tr '/' '\n' | grep 9443 | cut -d ':' -f 2)
fi
echo "You can now login at https://${IP}:${PORT}/itim/console"

# Backup the installation
if [[ ! -d "$BACKUPDIR" ]]; then
	mkdir "$BACKUPDIR"
fi
FILE=$(date +"%Y%m%d_%H%M%S")
DIRS="data config helm yaml"
cd ..
tar czf "backup/${FILE}-installed.tgz" $DIRS
cd bin

