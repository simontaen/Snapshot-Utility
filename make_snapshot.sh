#!/bin/sh

#################### VERSION 2.6 ####################

ID=`which id`;
ECHO=`which echo`;
RM=`which rm`;
MV=`which mv`;
CP=`which cp`;
TOUCH=`which touch`;
DATE=`which date`;
RSYNC=`which rsync`;
FIND=`which find`;
UNAME=`which uname`;
SSH=`which ssh`;

##############################################################################
#

usage="
Usage:

 $0 -c config_file -s source_dir -d destination_dir
 		[-f exclude_file] [-m mode] [-e]

Explanation:

 config_file:		a file that contains all config
 source_dir:		the directory to backup
 destination_dir:	the destination directory
 
 exclude_file:		a file for rsync --exclude-from, default it is unset
 e					enables SSH mode
 mode:				one of {hourly|daily|weekly|monthly|yearly}, default daily

" ;

RUNNING_DIR=`dirname $0`;
LOGS_DIR="$RUNNING_DIR"/logs

##############################################################################
# define a function to keep the error.log if errors exist,
# assumes you put the error.log where the script is located!!
#

moveErrorLog()
{
if [ -s "$LOGS_DIR"/make_error.log ] ; then
	$MV "$LOGS_DIR"/make_error.log "$LOGS_DIR"/make_error_`$DATE '+%F_%H-%M-%S'`.log
else
	$RM -f "$LOGS_DIR"/make_error.log;
fi
}

##############################################################################
# checking arguments and options
#

while getopts c:s:d:f:m:eh flag
do
	case $flag in
		c)	CONFIG_FILE="$OPTARG";
			if [ ! -f "$CONFIG_FILE" ] ; then
				$ECHO Error: "$CONFIG_FILE" isn\'t a valid file. >&2; moveErrorLog; exit 1;
        	fi;;
		s)	SOURCE_DIR="$OPTARG";
			if [ ! -d "$SOURCE_DIR" ] ; then
				$ECHO Error: "$SOURCE_DIR" isn\'t a valid directory. >&2; moveErrorLog; exit 1;
			fi;;
    	d)	DESTINATION_DIR="$OPTARG";;
        f)	EXCLUDE_FILE="$OPTARG";
        	if [ -f $EXCLUDE_FILE ] ; then
        		EXCLUDE_LINE="--exclude-from=$EXCLUDE_FILE" ;
    		else
        		$ECHO Error: $EXCLUDE_FILE isn\'t a valid file. >&2; moveErrorLog; exit 1;
    		fi;;
		m)	BKP_MODE="$OPTARG"
			case $BKP_MODE in
				daily|weekly|monthly|yearly);;
				*) $ECHO Error: Unsupported mode \""$OPTARG"\". >&2; moveErrorLog; exit 1;;
			esac;;
        e) SSH_ENABLED="yes";;
		?) $ECHO "$usage"; moveErrorLog; exit 1;;
	esac
done

if [ -z "$BKP_MODE" ] ; then
    BKP_MODE=daily;
fi

if [ -z "$SOURCE_DIR" ]; then
	$ECHO Error: mandatory option source_dir not set. >&2; $ECHO "$usage"; moveErrorLog; exit 1;
fi;
if [ -z "$DESTINATION_DIR" ]; then
	$ECHO Error: mandatory option destination_dir not set. >&2; $ECHO "$usage"; moveErrorLog; exit 1;
fi;
if [ "$SSH_ENABLED" = "yes" ] ; then
	if [ -z "$CONFIG_FILE" ]; then
		$ECHO Error: mandatory option config_file not set. >&2; $ECHO "$usage"; moveErrorLog; exit 1;
	else
		source "$CONFIG_FILE";
	fi;
fi

unset PATH


##############################################################################
# make sure we're running as root
#

if [ `$ID -u` != 0 ]; then { $ECHO Sorry, must be root. Exiting... >&2; moveErrorLog; exit 1; } fi

##############################################################################
# advanced checking of SSH arguments
# and "$DESTINATION_DIR" (which could be on the remote)
#

if [ "$SSH_ENABLED" = "yes" ] ; then
    if [ -z "$SSHPORT" ] || [ -z "$SSHKEY" ] || [ -z "$R_RSYNC" ] \
    	|| [ -z "$USER" ] || [ -z "$SERVER" ] || [ -z "$R_ECHO" ] \
		|| [ -z "$R_MV" ] || [ -z "$R_RM" ] || [ -z "$R_TOUCH" ] || [ -z "$SSH" ]; then
    	$ECHO Error: Missig Variables for SSH. >&2; exit 1;
    fi
    
    $SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
		if [ ! -d "$DESTINATION_DIR" ] ; then
    		$R_ECHO Error: "$DESTINATION_DIR" isn\'t a valid directory. >&2; exit 1;
		fi
    " ;
    
	if [ $? -ge 1 ]; then
    	moveErrorLog; exit 1;
	fi
    
else
	if [ ! -d "$DESTINATION_DIR" ] ; then
    	$ECHO Error: "$DESTINATION_DIR" isn\'t a valid directory. >&2; moveErrorLog; exit 1;
	fi
fi

##############################################################################
# setting dates
#

OS=`$UNAME`;

case $BKP_MODE in
	hourly) # assumes creation in same hour
		if [ "$OS" = "Darwin" ] ; then
			OLDEST_BKP=hour_`$DATE '+%H'`;
			NEWEST_BKP=hour_`$DATE -r $(( $($DATE '+%s') - 3600)) '+%H'`;
		else
			OLDEST_BKP=hour_`$DATE '+%H'`; # this hour
			NEWEST_BKP=hour_`$DATE '+%H' -D %s -d $(( $($DATE '+%s') - 3600))`; # last hour
		fi;;
	daily) # assumes creation on same day
		if [ "$OS" = "Darwin" ] ; then
			OLDEST_BKP=`$DATE '+%u-%A'`;
			NEWEST_BKP=`$DATE -r $(( $($DATE '+%s') - 86400)) '+%u-%A'`;
		else
			OLDEST_BKP=`$DATE +%u-%A -D %s`; # = today
			NEWEST_BKP=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 86400))`; # = yesterday
		fi;;
	weekly) # assumes creation in same week
		if [ "$OS" = "Darwin" ] ; then
			OLDEST_BKP=week_`$DATE '+%V'`;
			NEWEST_BKP=week_`$DATE -r $(( $($DATE '+%s') - 604800)) '+%V'`;
		else
			OLDEST_BKP=week_`$DATE '+%V'`; # this week
			NEWEST_BKP=week_`$DATE '+%V' -D %s -d $(( $($DATE '+%s') - 604800))`; # last week
		fi;;
    monthly) # assumes creation in SECOND HALF of same month (at least 2 digit day!)
		if [ "$OS" = "Darwin" ] ; then
			OLDEST_BKP=`$DATE '+%m-%B'`;
			NEWEST_BKP=`$DATE -r $(( $($DATE '+%s') - 3024000)) '+%m-%B'`;
		else
			OLDEST_BKP=`$DATE '+%m-%B'`; # this month
			NEWEST_BKP=`$DATE '+%m-%B' -D %s -d $(( $($DATE '+%s') - 3024000))`; # last month (-35 days)
		fi;;
    yearly) # assumes creation in same year
		if [ "$OS" = "Darwin" ] ; then
			OLDEST_BKP=`$DATE '+%Y'`;
			NEWEST_BKP=`$DATE -r $(( $($DATE '+%s') - 31968000)) '+%Y'`;
		else
			OLDEST_BKP=`$DATE '+%Y'`; # this year
			NEWEST_BKP=`$DATE '+%Y' -D %s -d $(( $($DATE '+%s') - 31968000))`; # last year (-370 days)
		fi;;
esac

##############################################################################
# rotating snapshots
# move the oldest snapshot, if it exists (don't delete yet):
#

if [ "$SSH_ENABLED" = "yes" ] ; then

    $SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
		if [ -d "$DESTINATION_DIR/$OLDEST_BKP" ] ; then
    		$R_MV "$DESTINATION_DIR/$OLDEST_BKP" \
        		"$DESTINATION_DIR/$OLDEST_BKP.delete"
		fi
    " ;
    
	if [ $? -ge 1 ]; then
    	moveErrorLog; exit 1;
	fi
		
else
	if [ -d "$DESTINATION_DIR/$OLDEST_BKP" ] ; then
    	$MV "$DESTINATION_DIR/$OLDEST_BKP" \
        	"$DESTINATION_DIR/$OLDEST_BKP.delete"
	fi
fi

##############################################################################
# rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
#

# TODO: NEWEST_BKP should be LATEST_BKP, because if NEWEST_BKP does not exists
# a whole new data set get created

$ECHO -e "\n\n############ `$DATE '+%F_%H-%M-%S'` #############"

if [ "$SSH_ENABLED" = "yes" ] ; then

	$RSYNC \
    	-ahvz --delete --delete-excluded \
		--link-dest="$DESTINATION_DIR/$NEWEST_BKP" \
    	"$EXCLUDE_LINE" \
    	--stats \
    	--rsync-path=$R_RSYNC \
    	-e "$SSH -p $SSHPORT -i $SSHKEY" \
    	"$SOURCE_DIR/" $USER@$SERVER:"$DESTINATION_DIR/$OLDEST_BKP/" ;
else
	
	$RSYNC \
    	-ahv --delete --delete-excluded \
		--link-dest="$DESTINATION_DIR/$NEWEST_BKP" \
		"$EXCLUDE_LINE" \
    	--stats \
    	"$SOURCE_DIR/" "$DESTINATION_DIR/$OLDEST_BKP/" ;
fi

##############################################################################
# update the mtime of $OLDEST_BKP to reflect the snapshot time
#

if [ "$SSH_ENABLED" = "yes" ] ; then

    $SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
    	$R_TOUCH "$DESTINATION_DIR/$OLDEST_BKP"
    " ;
    
	if [ $? -ge 1 ]; then
    	moveErrorLog; exit 1;
	fi
else
	$TOUCH "$DESTINATION_DIR/$OLDEST_BKP" ;
fi

##############################################################################
# rotating snapshots
# delete the oldest snapshot now, if it exists:
#

if [ "$SSH_ENABLED" = "yes" ] ; then

	$SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
		$R_RM -rf "$DESTINATION_DIR/$OLDEST_BKP.delete" &
	" ;

	if [ $? -ge 1 ]; then
		moveErrorLog; exit 1;
	fi

else
	$RM -rf "$DESTINATION_DIR/$OLDEST_BKP.delete" &
fi

##############################################################################
# keep the error.log if errors exist
#

moveErrorLog;

wait; # on deleting oldest snapshot and clean up of weekly backups

#
# EOF
##############################################################################