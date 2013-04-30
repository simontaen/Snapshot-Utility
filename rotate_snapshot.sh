#!/bin/sh

#################### VERSION 2.6 ####################

ID=`which id`;
ECHO=`which echo`;
RM=`which rm`;
MV=`which mv`;
CP=`which cp`;
DATE=`which date`;
RSYNC=`which rsync`;
FIND=`which find`;

##############################################################################
#

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

LOGS_DIR="$RUNNING_DIR"/logs

##############################################################################
# define a function to keep the error.log if errors exist,
# assumes you put the error.log where the script is located!!
#

moveErrorLog()
{
if [ -s "$LOGS_DIR"/rotate_error.log ] ; then
	$MV "$LOGS_DIR"/rotate_error.log "$LOGS_DIR"/rotate_error_`$DATE +%F_%H-%M-%S`.log
else
	$RM -f "$LOGS_DIR"/rotate_error.log;
fi
}

##############################################################################
# make sure we're running as root
#

if [ `$ID -u` != 0 ]; then { $ECHO Sorry, must be root.  Exiting... >&2; moveErrorLog; exit 1; } fi

##############################################################################
# checking arguments and options
#

while getopts w:m:d:s:h flag
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
		# You would need to know if the current hour has been done already
		NEWEST_OF_SRC_SNAPSHOT_1=hour_`$DATE +%H`;
		NEWEST_OF_SRC_SNAPSHOT_2=hour_`$DATE +%H -D %s -d $(( $($DATE +%s) - 3600))`;
		# Assumes rotation on same day
		OLDEST_BKP=`$DATE +%u-%A -D %s`; # = today
		NEWEST_BKP=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 86400))`;; # = yesterday
	weekly)
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=weekly_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../daily_snapshots; } fi;
		# Daily did NOT run -> date correction
		NEWEST_OF_SRC_SNAPSHOT_1=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 86400))`; # yesterday
		NEWEST_OF_SRC_SNAPSHOT_2=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 172800))`; # day before yesterday
		# Rotation in the same week, no correction
		OLDEST_BKP=week_`$DATE +%V`; # this week
		NEWEST_BKP=week_`$DATE +%V -D %s -d $(( $($DATE +%s) - 604800))`;; # last week
	monthly)
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=monthly_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../weekly_snapshots; } fi;
		# Weekly DID run, no correction
		NEWEST_OF_SRC_SNAPSHOT_1=week_`$DATE +%V`; # this week
		NEWEST_OF_SRC_SNAPSHOT_2=week_`$DATE +%V -D %s -d $(( $($DATE +%s) - 604800))`; # last week
		# Rotation on the first sunday of NEXT month -> date correction
		OLDEST_BKP=`$DATE +%m-%B -D %s -d $(( $($DATE +%s) - 691200))`; # last month ( - 8 days)
		NEWEST_BKP=`$DATE +%m-%B -D %s -d $(( $($DATE +%s) - 3456000))`;; # next to last month (- 40 days)
	yearly)
		if [ -z "$D_SNAPSHOT" ] ; then { D_SNAPSHOT=yearly_snapshots; } fi;
		if [ -z "$S_SNAPSHOT" ] ; then { S_SNAPSHOT=../monthly_snapshots; } fi;
		# Monthly DID run, no correction
		NEWEST_OF_SRC_SNAPSHOT_1=`$DATE +%m-%B -D %s -d $(( $($DATE +%s) - 2592000))`; # 12-December (-30 days)
		NEWEST_OF_SRC_SNAPSHOT_2=`$DATE +%m-%B -D %s -d $(( $($DATE +%s) - 5184000))`; # 11-November (-60 days)
		# Rotation NEXT year -> date correction
		OLDEST_BKP=`$DATE +%Y -D %s -d $(( $($DATE +%s) - 25920000))`; # last year (-300 days)
		NEWEST_BKP=`$DATE +%Y -D %s -d $(( $($DATE +%s) - 51840000))`;; # next to last year (-600 days)
esac

##############################################################################
# find destination directories for chosen mode (weekly -> weekly_snapshots)
#

ALL_FOUND_DESTINATION_DIRS=`$FIND "$WORKING_DIR" -name $D_SNAPSHOT -type d -maxdepth 2`

if [ -z "$ALL_FOUND_DESTINATION_DIRS" ] ; then
    $ECHO Error: No directories named $D_SNAPSHOT in "$WORKING_DIR". >&2; moveErrorLog; exit 1;
fi

##############################################################################
# loop over destination snapshots in ALL_FOUND_DESTINATION_DIRS
#

# ends at EOF
for DESTINATION_DIR in $ALL_FOUND_DESTINATION_DIRS; do

# here we go further back and look for the latest source snapshot,
# either NEWEST_OF_SRC_SNAPSHOT_1 or NEWEST_OF_SRC_SNAPSHOT_2 depending
# on which is available
NEWEST_OF_SRC_SNAPSHOT="$NEWEST_OF_SRC_SNAPSHOT_1"
if [ ! -d "$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT_1" ] ; then
    if [ ! -d "$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT_2" ] ; then
    		$ECHO -e "\n\n############ `$DATE +%F_%H-%M-%S` - $DESTINATION_DIR #############"
		    $ECHO "$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT_1" and "$DESTINATION_DIR/$S_SNAPSHOT/$NEWEST_OF_SRC_SNAPSHOT_2" aren\'t a valid directories. Skipping... ;
		    continue ;
	fi
	NEWEST_OF_SRC_SNAPSHOT="$NEWEST_OF_SRC_SNAPSHOT_2"
fi

##############################################################################
# clean up old weekly backups (I found that they are rarely used)
#

case $BKP_MODE in
	weekly)
		# find week_* folders older that 50 days
		OLD_WEEKLY_BACKUPS=`$FIND "$DESTINATION_DIR" -name "week_*" -type d -mtime +30 -maxdepth 1 -print`
		for WEEKLY_BACKUP in $OLD_WEEKLY_BACKUPS; do
			$RM -rf "$WEEKLY_BACKUP" &
		done;
esac

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

wait; # on deleting oldest snapshot and clean up of weekly backups

#
# EOF
##############################################################################