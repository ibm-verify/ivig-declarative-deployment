#!/bin/bash

if [[ "$1" = "--help" ]]; then
	echo "Name: DBPurge.sh"
	echo "When to run: On a regular basis to remove obsolete data from the DB"
	echo "Description:"
	echo "   DBPurge deletes historical workflow audit data, non-workflow audit events, and"
	echo "   reconciliation reporting entries from the database that were completed before"
	echo "   a particular date."
	echo "Usage:"
	echo "  DBPurge -age <num_days> | -date <yyyy-mm-dd[-HH:mm]>"
	echo "           [-grouping <group_size>]"
	echo "           [-workflow <wf_flag> [-process_type <proc_type>]]"
	echo "           [-audit <audit_flag>] [-recon <recon_flag>]"
	echo ""
	echo "  where <num_days>    is a required integer indicating the age of the records"
	echo "                      to remove, which must be non-negative, where a value"
	echo "                      of 0 will remove all data, including today's"
	echo "        <date>        is an alternative way to specify the deletion date and"
	echo "                      optional time (eg. '2010-08-15-22:00')"
	echo "                      all records created this date or earlier will be deleted"
	echo "        <group_size>  is an optional integer parameter for the number of"
	echo "                      process or audit related records to be removed in a"
	echo "                      group, which must be between 1 and 100,"
	echo "                      and defaults to 50"
	echo "        <wf_flag>     is an optional boolean flag, which determines if"
	echo "                      workflow data is removed, and defaults to true"
	echo "        <proc_type>   is an optional 2 character parameter which indicates"
	echo "                      process types to delete (eg. 'AP')"
	echo "                      if unspecified, then all workflow process types are deleted"
	echo "        <audit_flag>  is an optional boolean flag, which determines if"
	echo "                      non-workflow audit data is removed, and defaults to true"
	echo "        <recon_flag>  is an optional boolean flag, which determines if"
	echo "                      historical reconciliation data is removed, and defaults"
	echo "                      to true"
	echo ""
	exit 0
fi

CDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
TDIR=$(basename "$CDIR")
if [[ "$TDIR"  = "util" ]]; then
	cd "$CDIR/.." || exit 1
fi
source ./lib/common.sh

get_namespace || die "Unable to get namespace" $?
NS=$REPLY

kubectl=$(./sys/preReqCheck.sh)
RC=$?
if [[ $RC -ne 0 ]]; then
	echo "$kubectl"
	exit "$RC"
fi

POD=isvgim-0
$kubectl -n "$NS" exec "$POD" -c isvgim -- /bin/bash /work/DBPurge.sh "$@"
if [[ $? -ne 0 ]]; then
	exit 1
fi
