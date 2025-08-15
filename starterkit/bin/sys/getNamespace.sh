#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: getNamespace.sh"
	echo "When to run: Never, called automatically by other scripts."
	echo "Description:"
	echo "   Wrapper for parsing the namespace value from the values.yaml file.  It never needs to be run by the user."
	echo "Example usage:"
	echo "   $ ./getNamespace.sh"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

grep "namespace: " ../helm/values.yaml | cut -d ':' -f 2 | xargs
