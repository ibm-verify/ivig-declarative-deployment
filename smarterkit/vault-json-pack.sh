#!/bin/bash

# This script expects a list of files provided as arguments, based on which it
# writes a flat JSON dictionary to STDOUT you can import into Vault.
# Globs/wildcards will be resolved. Entries are created of file basename as key
# and content as value. If there are duplicate basenames after resolving all
# arguments, the first one takes precedence.
#
# Note: By default, there is a size limit of 1MiB for Vault secrets. This script
# may produce larger JSON payload. Realistic usage scenarios are not affected.
# 
# example: vault-json-pack.sh mq.* isvgim*CA.crt | vault kv put certs/mqcerts -

ARGS=()

for FILE in "$@"; do
  if [[ -f "$FILE" ]]; then
    ARGS+=(--rawfile "${FILE##*/}" "$FILE")
  fi
done

jq -n "${ARGS[@]}" '$ARGS.named'

