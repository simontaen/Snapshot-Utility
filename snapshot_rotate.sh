#!/bin/sh

usage="
Usage:

 $0 -w working_directory -m mode
 	[-d destination_snapshot_name] [-s source_snapshot_path]

Explanation:

 working_directory:     the directory which contains all backups, it will be
                        searched to find all destination_snapshot_name Folders
 mode:                  one of {daily|weekly|monthly|yearly}, default daily
                        determens destination_snapshot and source_snapshot_path
                        automatically if not manually overwritten

 destination_snapshot:	name of the destination snapshot folder
 source_snapshot_path:	path to the source snapshot folder
                        IN RELATION to the destination folder
" ;

RUNNING_DIR=`dirname $0`;

unset PATH

source "$RUNNING_DIR"/make_snapshot_config.sh

##############################################################################
# define a function to keep the error.log if errors exist,
# assumes you put the error.log where the script is located!!
#

moveErrorLog()
{
if [ -s "$RUNNING_DIR"/error.log ] ; then
	$MV "$RUNNING_DIR"/error.log "$RUNNING_DIR"/error_rotate_`$DATE +%F_%H-%M-%S`.log
else
	$RM -f "$RUNNING_DIR"/error.log;
fi
}

##############################################################################
# make sure we're running as root
#

if [ `$ID -u` != 0 ]; then { $ECHO Sorry, must be root.  Exiting... >&2; moveErrorLog; exit 1; } fi

##############################################################################
# checking arguments and options
#

while $GETOPT w:m:d:s:h flag
do
	case $flag in
		w)	WORKING_DIR="$OPTARG";
			if [ ! -d "$WORKING_DIR" ] ; then
				$ECHO Error: "$WORKING_DIR" isn\'t a valid directory. >&2; moveErrorLog; exit 1;
			fi;;
		m)	BKP_MODE="$OPTARG"
			case $BKP_MODE in
				daily|weekly|monthly|yearly);;
				*) $ECHO Error: Unsupported mode \""$OPTARG"\". >&2; moveErrorLog; exit 1;;
			esac;;
    	d) D_SNAPSHOT="$OPTARG";;
        s) S_SNAPSHOT="$OPTARG";;
		?) $ECHO "$usage"; moveErrorLog; exit 1;;
	esac
done

if [ -z "$WORKING_DIR" ] || [ -z "$BKP_MODE" ]; then
    $ECHO Error: mandatory options not set. >&2; $ECHO "$usage"; moveErrorLog; exit 1;
fi;

##############################################################################
# setting varibles
#

case $BKP_MODE in
	daily) 
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=daily_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../hourly_snapshots; } fi;
		NEWEST_OF_SRC_SNAPSHOT=hour_`$DATE +%H`;
		OLDEST_BKP=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 86400))`; # = 3-Wednesday
		NEWEST_BKP=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 172800))`;; # = 2-Tuesday
	weekly)
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=weekly_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../daily_snapshots; } fi;
		NEWEST_OF_SRC_SNAPSHOT=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 86400))`;
		OLDEST_BKP=week_`$DATE +%V`;
		NEWEST_BKP=week_`$DATE +%V -D %s -d $(( $($DATE +%s) - 604800))`;;
    monthly)
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=monthly_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../weekly_snapshots; } fi;
		NEWEST_OF_SRC_SNAPSHOT=week_`$DATE +%V`;
		OLDEST_BKP=`$DATE +%m-%B`;
		NEWEST_BKP=`$DATE +%m-%B -D %s -d $(( $($DATE +%s) - 2419200))`;;
    yearly)
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=yearly_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../monthly_snapshots; } fi;
		NEWEST_OF_SRC_SNAPSHOT=`$DATE +%m-%B`;
		OLDEST_BKP=`$DATE +%Y`;
		NEWEST_BKP=`$DATE +%Y -D %s -d $(( $($DATE +%s) - 31449600))`;;
esac


##############################################################################
# find existing source snapshot directories
#


FIND_RESULT=`$FIND "$WORKING_DIR" -name $D_SNAPSHOT -type d -maxdepth 2`

if [ -z "$FIND_RESULT" ] ; then
    $ECHO Error: No directories named $D_SNAPSHOT in "$WORKING_DIR". >&2; moveErrorLog; exit 1;
fi

##############################################################################
# loop over source snapshots in 
#

# ends at EOF
for DESTINATION_DIR in $FIND_RESULT; do

if [ ! -d "$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT" ] ; then
    $ECHO "$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT" isn\'t a valid directory. Skipping... ;
    continue ;
fi

##############################################################################
# rotating snapshots
# delete the oldest snapshot in background, if it exists:
#

if [ -d "$DESTINATION_DIR/$OLDEST_BKP" ] ; then
	$MV "$DESTINATION_DIR/$OLDEST_BKP" \
		"$DESTINATION_DIR/$OLDEST_BKP.delete"
	$RM -rf "$DESTINATION_DIR/$OLDEST_BKP.delete" &
fi

##############################################################################
# make a hard-link-only (except for dirs) copy of
# NEWEST_OF_SRC_SNAPSHOT into OLDEST_BKP
#

$ECHO -e "\n\n############ `$DATE +%F_%H-%M-%S` - $DESTINATION_DIR #############"

$RSYNC \
	-ah --delete \
	--link-dest="$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT" \
	--stats \
	"$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT/" "$DESTINATION_DIR/$OLDEST_BKP/" ;

##############################################################################
# NOTE: do *not* update the mtime of daily.0; it will reflect
# when NEWEST_OF_SRC_SNAPSHOT was made, which should be correct.

done;

##############################################################################
# keep the error.log if errors exist
#

moveErrorLog;

wait; # on deleting oldest snapshot

#
# EOF
##############################################################################