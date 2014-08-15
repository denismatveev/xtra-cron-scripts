#!/bin/bash
set -e
#set -x

######################
##### Settings ######################
BACKUPDIR=/mnt/backup/mysql
THREADS=4
NUMBEROFFULLBACKUPS=2
NUMBERINCRBACKUPS=15 #+1 
LOCKFILE=/var/run/cronbackup.lock
MY=/var/lib/mysql
NOW=$(date +%Y%m%d-%H%M)
SERVER=172.16.1.82 #master server
####################################
#### lockfile ####
if [ -e "$LOCKFILE" ]
	then
        echo -e "Cannot obtain lock file\n";
	exit 1;
fi
touch "$LOCKFILE";
trap 'rm -f "$LOCKFILE"; exit $?' INT TERM EXIT # signals handler(analog signal() family? )
#########################
CURRENTNUMBEROFFULLBACKUPS=$(ls -1t "$BACKUPDIR" 2>/dev/null  | wc -l)
OLDESTBACKUP=$(ls -1t "$BACKUPDIR" 2>/dev/null|  tail -n1)
CURRENTFULLBACKUP=$(ls -1t "$BACKUPDIR" 2>/dev/null|  head -n1)
NUMBEROFINCREMENTALBACKUPSINOLDESTFULL=$(ls -1 "$BACKUPDIR"/"$OLDESTBACKUP" 2>/dev/null| wc -l)
NUMBEROFCURRENTINCRBACKUPS=$(ls -1 "$BACKUPDIR"/"$CURRENTFULLBACKUP" 2>/dev/null | wc -l)
########################

# structure of backups dir
# backup dir
#    |
#    \--full backupdir 20140801-1801-0
#    |
#      \       
#       inc backupdir like 20140801-1801-1
#      \
#        20140801-1801-2
#      \
#        20140801-1801-3
#      etc...
#
#
makefull()
{
# To extract the resulting tar file, you must use the -i option, such as tar -ixvf backup.tar.
    TARGET="$BACKUPDIR"/"$NOW"/"$NOW"-0
    mkdir -p "$TARGET"
### backup ibdata ###

     cd "$TARGET" && ssh "$SERVER" xtrabackup --backup  --datadir="$MY" --stream=xbstream | xbstream -x
     ssh "$SERVER" tar zcf - "$MY"/xtrabackup_logfile | tar zxf - --strip-components=3 
### backup the rest files ###

    ssh "$SERVER" tar --create --preserve-permissions --totals --gzip  --ignore-failed-read --one-file-system --sparse\
    --wildcards --verbose \
    --listed-incremental=$MY/backup.list \
    --no-check-device  \
    --exclude=ibdata* \
    --exclude=xtrabackup_* \
    --exclude-caches "$MY" > "$TARGET"/mysql-0.tar.gz

    return 0
}

makeincremental()
{
## backup ibdata    
    i=$(ls -1t "$BACKUPDIR"/"$CURRENTFULLBACKUP"/ 2>/dev/null | head -n1 | cut -d"-" -f3) # number of existing incremental backups
    PREVIOUSBACKUP=$(ls -1t "$BACKUPDIR"/"$CURRENTFULLBACKUP" | head -n1)
    let "i+=1"
    TARGET="$BACKUPDIR"/"$CURRENTFULLBACKUP"/"$NOW"-"$i"
    mkdir -p "$TARGET"

    LAST_LSN=$(grep last_lsn "$BACKUPDIR"/"$CURRENTFULLBACKUP"/"$PREVIOUSBACKUP"/xtrabackup_checkpoints | cut -f3 -d" ")

   cd "$TARGET" && ssh "$SERVER" xtrabackup --backup --incremental-lsn="$LAST_LSN" --datadir="$MY" --stream=xbstream | xbstream -x
   ssh "$SERVER" tar zcf - "$MY"/xtrabackup_logfile | tar zxf - --strip-components=3 

## backup the rest files    
   ssh "$SERVER" tar --create --preserve-permissions --totals --gzip  --ignore-failed-read --one-file-system --sparse\
    --wildcards --verbose \
    --listed-incremental="$MY"/backup.list \
    --no-check-device  \
    --exclude=ibdata* \
    --exclude=xtrabackup_* \
    --exclude-caches "$MY" > "$TARGET"/mysql-incr-"$i".tar.gz

    return 0
}

rmexpiredbackups()
{
	
	if [[ "$CURRENTNUMBEROFFULLBACKUPS" -ge "$NUMBEROFFULLBACKUPS" ]] && [[ "$NUMBEROFCURRENTINCRBACKUPS" -ge "$NUMBERINCRBACKUPS" ]] && [[ "$NUMBEROFINCREMENTALBACKUPSINOLDESTFULL" -ge "$NUMBERINCRBACKUPS" ]]
        then
	    echo -e "deleting old backups: "$BACKUPDIR"/"$OLDESTBACKUP"\n" 
        rm -rf "$BACKUPDIR"/"$OLDESTBACKUP"
        ssh "$SERVER" 'rm -f "$MY"/backup.list'
		echo -e "old backups deleted at `date +%F-%T`\n"  
	else
		echo -e "nothing to delete of backups\n"
	fi
	return 0;

}
####### main() ##########



	if ([[ "$CURRENTNUMBEROFFULLBACKUPS" -le "$NUMBEROFFULLBACKUPS" ]] && [[ "$NUMBEROFCURRENTINCRBACKUPS" -ge "$NUMBERINCRBACKUPS" ]]) || [[ "$CURRENTNUMBEROFFULLBACKUPS" -eq 0 ]] && [[ "$NUMBEROFFULLBACKUPS" -gt 0 ]]
		then makefull
	elif [[ "$NUMBEROFCURRENTINCRBACKUPS" -lt "$NUMBERINCRBACKUPS" ]] && [[ "$CURRENTNUMBEROFFULLBACKUPS" -gt 0 ]]
		then makeincremental
	else echo -e "some error ocurred!\n" 
		exit 2
	fi	 

 
	rmexpiredbackups;

## the end
