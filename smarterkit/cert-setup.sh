#!/bin/bash

cd $(dirname "${BASH_SOURCE[0]}" )

echo "Extracting input from values.yaml and values-config.yaml..."

N="$(sed -n 's/^[[:space:]]*namespace:[[:space:]]*//p' values.yaml)"
I="$(sed -n 's/^[[:space:]]*deploy\(.*\):[[:space:]]*true/\1/p' values-config.yaml | sed 's/Db/pgsql/;s/Ldap/isvd/;s/I/i/' | paste -sd, -)"
H="$(sed -n '/^[[:space:]]*hostname:/,/^[[:space:]]*[[:alnum:]]/s/^[[:space:]]*-[[:space:]]*//p' values-config.yaml | paste -sd, -)"

echo "Setting up certificates..."

./cert-util.sh --create ${N:+-n $N} ${H:+-f $H} ${I:+-i $I} && echo -e "Done.\n" || exit 1
./cert-util.sh --list
