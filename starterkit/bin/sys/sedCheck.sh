#!/bin/bash

if [ "x$1" = "x--help" ]; then
	echo "Name: sedCheck.sh"
	echo "When to run: Never, called automatically by other scripts."
	echo "Description:"
	echo "   Wrapper for checking if sed is GNU or BSD.  It never needs to be run by the user."
	echo "Example usage:"
	echo "   $ ./sedCheck.sh"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xsys" ]; then
	cd $CDIR/..
fi

# GNU (Linux) sed has a --version option.  BSD (OSX) sed does not.
# BSD sed wants an additional parameter to the -i (in place) flag

sed --version > /dev/null 2>&1
if [ $(echo $?) -eq 0 ]; then
	echo "sed -i"
else
	echo "sed -i ''"
fi
