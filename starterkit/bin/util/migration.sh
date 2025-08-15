#!/bin/bash


CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename $CDIR)
if [ "x$TDIR"  = "xutil" ]; then
	cd $CDIR/..
fi

NS=$(./sys/getNamespace.sh)

kubectl=$(./sys/preReqCheck.sh)
RC=$(echo $?)
if [ $RC -ne 0 ]; then
	echo $kubectl
	exit $RC
fi

POD=isvgim-0
$kubectl -n $NS exec $POD -c isvgim -- /bin/bash /work/IGIMigration/bin/migration.sh "$@"
if [ $(echo $?) -ne 0 ]; then
	exit 1
fi
