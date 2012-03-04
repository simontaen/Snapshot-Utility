#!/bin/sh

usage="
Usage:

 $0 -s source_dir -d destination_dir
 		[-f exclude_file] [-m mode] [-e]

Explanation:

 source_dir:		the directory to backup
 destination_dir:	the destination directory

 exclude_file:		a file for rsync --exclude-from, default it is unset
 e					enables SSH mode
 mode:				one of {hourly|daily|weekly|monthly|yearly}, default daily

Example Crontab-lines:

0 12 * * *  make_snapshot.sh /root/backup /home/ -f /root/make_snapshot_exclude;

" ; 

unset PATH

source ./make_snapshot_config.sh

##############################################################################
# make sure we're running as root
#

if [ `$ID -u` != 0 ]; then { $ECHO Sorry, must be root.  Exiting...; exit 1; } fi

##############################################################################
# checking arguments and options
#

while $GETOPT s:d:f:m:eh flag
do
	case $flag in
		s)	SOURCE_DIR="$OPTARG";
			if [ ! -d $SOURCE_DIR ] ; then
				$ECHO Error: $SOURCE_DIR isn\'t a valid directory. ; exit 1;
			fi;;
    	d) DESTINATION_DIR="$OPTARG";;
        f) 	EXCLUDE_FILE="$OPTARG";
        	if [ -f $EXCLUDE_FILE ] ; then
        		EXCLUDE_LINE="--exclude-from=\"$EXCLUDE_FILE\"" ;
    		else
        		$ECHO Error: $EXCLUDE_FILE isn\'t a valid file. ; exit 1;
    		fi;;
		m)	BKP_MODE="$OPTARG"
			case $BKP_MODE in
				daily|weekly|monthly|yearly);;
				*) $ECHO Error: Unsupported mode \""$OPTARG"\". ; exit 1;;
			esac;;
        e) SSH_ENABLED="yes";;
		?) $ECHO "$usage"; exit 1;;
	esac
done

if [ -z "$BKP_MODE" ] ; then
    BKP_MODE=daily;
fi

if [ -z "$SOURCE_DIR" ] || [ -z "$DESTINATION_DIR" ]; then
    $ECHO Error: mandatory options not set.;
    $ECHO "$usage";
    exit 1;
fi;

##############################################################################
# advanced checking of SSH arguments
# and $DESTINATION_DIR (which could be on the remote)
#

if [ "$SSH_ENABLED" = "yes" ] ; then
    if [ -z "$SSHPORT" ] || [ -z "$SSHKEY" ] || [ -z "$R_RSYNC" ] \
    	|| [ -z "$USER" ] || [ -z "$SERVER" ] || [ -z "$R_ECHO" ] \
		|| [ -z "$R_MV" ] || [ -z "$R_RM" ] || [ -z "$R_TOUCH" ] || [ -z "$SSH" ]; then
    	$ECHO Error: Missig Variables for SSH. ; exit 1;
    fi
    
    $SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
		if [ ! -d $DESTINATION_DIR ] ; then
    		$R_ECHO Error: $DESTINATION_DIR isn\'t a valid directory. ; exit 1;
		fi
    " ;
    
	if [ $? -ge 1 ]; then
    	exit 1;
	fi
    
else
	if [ ! -d $DESTINATION_DIR ] ; then
    	$ECHO Error: $DESTINATION_DIR isn\'t a valid directory. ; exit 1;
	fi
fi

##############################################################################
# setting dates
#

case $BKP_MODE in
	hourly)
		OLDEST_BKP=hour_`$DATE +%H`;
		NEWEST_BKP=hour_`$DATE +%H -D %s -d $(( $($DATE +%s) - 3600))`;;
	daily) 
		# if Today == Thursday
		OLDEST_BKP=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 86400))`; # = 3-Wednesday
		NEWEST_BKP=`$DATE +%u-%A -D %s -d $(( $($DATE +%s) - 172800))`;; # = 2-Tuesday
	weekly) 
		OLDEST_BKP=week_`$DATE +%V`;
		NEWEST_BKP=week_`$DATE +%V -D %s -d $(( $($DATE +%s) - 604800))`;;
    monthly)
		OLDEST_BKP=`$DATE +%m-%B`;
		NEWEST_BKP=`$DATE +%m-%B -D %s -d $(( $($DATE +%s) - 2419200))`;;
    yearly)
		OLDEST_BKP=`$DATE +%Y`;
		NEWEST_BKP=`$DATE +%Y -D %s -d $(( $($DATE +%s) - 31449600))`;;
esac

##############################################################################
# rotating snapshots
# delete the oldest snapshot in background, if it exists:
#

if [ "$SSH_ENABLED" = "yes" ] ; then

    $SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
		if [ -d $DESTINATION_DIR/$OLDEST_BKP ] ; then
    		$R_MV $DESTINATION_DIR/$OLDEST_BKP \
        		$DESTINATION_DIR/$OLDEST_BKP.delete
    		$R_RM -rf $DESTINATION_DIR/$OLDEST_BKP.delete &
		fi
    " ;
    
	if [ $? -ge 1 ]; then
    	exit 1;
	fi
		
else
	if [ -d $DESTINATION_DIR/$OLDEST_BKP ] ; then
    	$MV $DESTINATION_DIR/$OLDEST_BKP \
        	$DESTINATION_DIR/$OLDEST_BKP.delete
    	$RM -rf $DESTINATION_DIR/$OLDEST_BKP.delete &
	fi
fi

##############################################################################
# rsync from the system into the latest snapshot (notice that
# rsync behaves like cp --remove-destination by default, so the destination
# is unlinked first.  If it were not so, this would copy over the other
# snapshot(s) too!
#

if [ "$SSH_ENABLED" = "yes" ] ; then

	$RSYNC \
    	-ahz --delete --delete-excluded \
		--link-dest=$DESTINATION_DIR/$NEWEST_BKP \
    	$EXCLUDE_LINE \
    	--stats \
    	--rsync-path=$R_RSYNC \
    	-e "$SSH -p $SSHPORT -i $SSHKEY" \
    	$SOURCE_DIR/ $USER@$SERVER:$DESTINATION_DIR/$OLDEST_BKP ;
else
	
	$RSYNC \
    	-ah --delete --delete-excluded \
		--link-dest=$DESTINATION_DIR/$NEWEST_BKP \
    	$EXCLUDE_LINE \
    	--stats \
    	$SOURCE_DIR/ $DESTINATION_DIR/$OLDEST_BKP/ ;
fi

##############################################################################
# update the mtime of $OLDEST_BKP to reflect the snapshot time
#

if [ "$SSH_ENABLED" = "yes" ] ; then

    $SSH -p $SSHPORT -i $SSHKEY $USER@$SERVER "
    	$R_TOUCH $DESTINATION_DIR/$OLDEST_BKP
    " ;
    
	if [ $? -ge 1 ]; then
    	exit 1;
	fi
else
	$TOUCH $DESTINATION_DIR/$OLDEST_BKP ;
fi

#
# EOF
##############################################################################