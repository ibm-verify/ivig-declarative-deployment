#!/bin/bash

if [ $# -lt 2 ]
then
    echo "This script creates a JSON that you can (manually) import into vault."
    echo "usage: $0 <file>..."
    echo "sample: $0 mq.* isvgimRootCA.crt"
    exit 1
fi

JSON="{}"

for ARG in "$@"; do
	for FILEPATH in ${ARG}; do
		FILE="${FILEPATH##*/}"
		if [ -e "$FILEPATH" ]; then
			# add existing file to result JSON
			FILECONTENT=$(< "$FILEPATH")
			JSON=$(echo "$JSON" | jq --arg k "$FILE" --arg v "$FILECONTENT" '. + {($k): $v}')
		else
			echo "File not found: $FILEPATH"
		fi
	done
done

# echo JSON, ready for import to vault
echo $JSON | jq
