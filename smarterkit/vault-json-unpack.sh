#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MIT

# This script expects a flat JSON dictionary to be passed via STDIN.
# For each entry, a file with the name of key and content of value will be
# created in the current directory.
#
# Note: Directory traversal is prevented by stripping any path component off the
# key. Existing files in the current directory are overwritten if names match. 
#
# example use: cat vault-export.json | vault-json-unpack.sh

jq -ej '
  if type != "object" then
    error("Error: Input JSON must be a flat dictionary object.")
  else
    to_entries[]
    | .key, "\u0000", .value, "\u0000"
  end
' |
while
  IFS= read -r -d '' KEY &&
  IFS= read -r -d '' VALUE
do
  echo "Writing to ${KEY##*/}" >&2
  printf '%s' "$VALUE" > "${KEY##*/}"
done

