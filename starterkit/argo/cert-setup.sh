#!/bin/bash

cd $(dirname "${BASH_SOURCE[0]}" )

echo "Extracting input from values.yaml and values-config.yaml..."

N="$(sed -n 's/^[[:space:]]*namespace:[[:space:]]*//p' values.yaml)"
I="$(sed -n 's/^[[:space:]]*deploy\(.*\):[[:space:]]*true/\L\1/p' values-config.yaml | sed 's/db/pgsql/;s/ldap/isvd/' | paste -sd, -)"
H="$(sed -n '/^[[:space:]]*hostname:/,/^[[:space:]]*\w/{s/^[[:space:]]*-[[:space:]]*//p}' -- values-config.yaml | paste -sd, -)"

echo "Setting up certificates..."

./cert-util.sh --create ${N:+-n $N} ${H:+-f $H} ${I:+-i $I} && echo -e "Done.\n" || exit 1
./cert-util.sh --list
