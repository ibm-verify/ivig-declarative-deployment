#!/bin/bash

# Enable debug mode
DEBUG=${DEBUG_INIT:-"false"}
DEBUG=$(echo "$DEBUG" | awk '{ print tolower($1) }')
if [[ "$DEBUG" = "true" ]]; then
	set -x
fi

OPTFILE="/work/options"
SVRCFG="/opt/ibm/wlp/usr/servers/defaultServer/server.xml"
REGFILE="/opt/ibm/wlp/usr/servers/defaultServer/config/server/metricsRegistry.xml"

if [[ ! -f $OPTFILE ]]; then
	exit 0
fi

handle_libertyMetrics() {
	# Check status
	ENABLED=$(echo "$1" | cut -d ' ' -f 1 | cut -d ':' -f 2)
	if [[ $ENABLED -eq 0 ]]; then
		sed -i '/mpMetrics/d' "$SVRCFG"
		return
	fi

	# Extract username and password
	FIELDS=$(echo "$1" | awk '{ print $2 }' | tr ',' ' ')
	for F in $FIELDS; do
		NAME=$(echo "$F" | cut -d '=' -f 1)
		VALUE=$(echo "$F" | cut -d '=' -f 2)
		case $NAME in
			userName)
				USERNAME="${VALUE:-$LIBERTYMETRICS_USERNAME}"
				;;
			password)
				PASSWORD="${VALUE:-$LIBERTYMETRICS_PASSWORD}"
				;;
			jwt)
				JWT=$VALUE
				;;
		esac
	done
	if [[ -z $USERNAME ]] || [[ -z $PASSWORD ]]; then
		echo "Unable to setup Metrics.  Username or password was empty."
		return
	fi

	# Encrypt password if not already
	if [[ ! $PASSWORD == '{aes}'* ]]; then
		PASSWORD=$(/opt/ibm/wlp/bin/securityUtility encode --encoding=aes "$PASSWORD")
	fi

	# Update the config XML to setup a user registry
	if [[ -z $JWT ]]; then
		JWT=$USERNAME
	fi
	cat << EOF > $REGFILE
<server>
    <basicRegistry id="mpMetrics" realm="MicroProfileMetrics">
        <user name="$USERNAME" password="$PASSWORD" />
    </basicRegistry>
    <reader-role>
        <user>"$JWT"</user>
    </reader-role>
</server>
EOF
echo "Enabled option: libertyMetrics"
} #handle_libertyMetrics


while IFS= read -r line; do
	optName=$(echo "$line" | cut -d ' ' -f 1 | cut -d ':' -f 1)
	handle_"$optName" "$line"
done < $OPTFILE
