#!/bin/bash
#set -e
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
TMP=/tmp
SERVER=flexo.navixy.com #master server
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
wait_suspend_file()
{
    while : 
    do
        ssh  "$SERVER"  ls -1 $TMP/xtrabackup_suspended_2  1>&2 2>/dev/null
        if [[ $? = 0 ]] 
            then break;
        fi
       sleep 2 # if doesn't exist
   done
   ssh -f "$SERVER" rm -f $TMP/xtrabackup_*
}
makefull()
{
    TARGET="$BACKUPDIR"/"$NOW"/"$NOW"-0
    mkdir -p "$TARGET"

### backup ibdata ###
    echo `date +%Y%m%d-%H%M:`;echo -e "Copying ibdata..\n"
    cd "$TARGET" && ssh "$SERVER" xtrabackup_55 --backup  --datadir="$MY" --target-dir=/tmp --tmpdir=/tmp --stream=xbstream --suspend-at-end | xbstream -x & # background process
    
### backup the rest files ###
    ssh "$SERVER" rm -f "$MY"/backup.list
    echo -e `date +%Y%m%d-%H%M:`;echo -e "Copying the rest mysql data..\n"
    ssh "$SERVER" "mysql -e 'FLUSH TABLES WITH READ LOCK;'"
    ssh "$SERVER" tar --create --preserve-permissions --totals --gzip  --ignore-failed-read --one-file-system --sparse\
    --wildcards --verbose \
    --listed-incremental=$MY/backup.list \
    --no-check-device  \
    --exclude=ibdata* \
    --exclude=xtrabackup_* \
    --exclude=ib_logfile* \
    --exclude-caches "$MY" > "$TARGET"/mysql-0.tar.gz
    ssh "$SERVER" "mysql -e 'UNLOCK TABLES;'"
    wait_suspend_file;
    echo `date +%Y%m%d-%H%M:`;echo -e "All done.OK\n"
    
    return 0
}

makeincremental()
{
#### make ibdata delta
    i=$(ls -1t "$BACKUPDIR"/"$CURRENTFULLBACKUP"/ 2>/dev/null | head -n1 | cut -d"-" -f3) # number of existing incremental backups
    PREVIOUSBACKUP=$(ls -1t "$BACKUPDIR"/"$CURRENTFULLBACKUP" | head -n1)
    #let "i+=1"
    (( i++ ))
    TARGET="$BACKUPDIR"/"$CURRENTFULLBACKUP"/"$NOW"-"$i"
    mkdir -p "$TARGET"

    LAST_LSN=$(grep to_lsn "$BACKUPDIR"/"$CURRENTFULLBACKUP"/"$PREVIOUSBACKUP"/xtrabackup_checkpoints | cut -f3 -d" ") # 

   cd "$TARGET" && ssh "$SERVER" xtrabackup_55 --backup --incremental-lsn="$LAST_LSN" --target-dir=/tmp --tmpdir=/tmp --datadir="$MY" --stream=xbstream --suspend-at-end | xbstream -x &
#### backup the rest files    
    ssh "$SERVER" "mysql -e 'FLUSH TABLES WITH READ LOCK;'"
    ssh "$SERVER" tar --create --preserve-permissions --totals --gzip  --ignore-failed-read --one-file-system --sparse\
    --wildcards --verbose \
    --listed-incremental="$MY"/backup.list \
    --no-check-device  \
    --exclude=ibdata* \
    --exclude=xtrabackup_* \
    --exclude=ib_logfile* \
    --exclude-caches "$MY" > "$TARGET"/mysql-incr-"$i".tar.gz
    ssh "$SERVER" "mysql -e 'UNLOCK TABLES;'"
    wait_suspend_file;
    echo `date +%Y%m%d-%H%M:`;echo -e "All done.OK\n"

    return 0
}

rmexpiredbackups()
{
	
	if [[ "$CURRENTNUMBEROFFULLBACKUPS" -ge "$NUMBEROFFULLBACKUPS" ]] && [[ "$NUMBEROFCURRENTINCRBACKUPS" -ge "$NUMBERINCRBACKUPS" ]] && [[ "$NUMBEROFINCREMENTALBACKUPSINOLDESTFULL" -ge "$NUMBERINCRBACKUPS" ]]
        	then
		echo -e "deleting old backups: "$BACKUPDIR"/"$OLDESTBACKUP"\n" 
        rm -rf "$BACKUPDIR"/"$OLDESTBACKUP"
		echo -e "old backups deleted at `date +%F-%T`\n"  
	else
		echo -e "nothing to delete of backups\n"
	fi
	return 0;

}
#######################



	if ([[ "$CURRENTNUMBEROFFULLBACKUPS" -le "$NUMBEROFFULLBACKUPS" ]] && [[ "$NUMBEROFCURRENTINCRBACKUPS" -ge "$NUMBERINCRBACKUPS" ]]) || [[ "$CURRENTNUMBEROFFULLBACKUPS" -eq 0 ]] && [[ "$NUMBEROFFULLBACKUPS" -gt 0 ]]
		then makefull
	elif [[ "$NUMBEROFCURRENTINCRBACKUPS" -lt "$NUMBERINCRBACKUPS" ]] && [[ "$CURRENTNUMBEROFFULLBACKUPS" -gt 0 ]]
		then makeincremental
	else echo -e "some error ocurred!\n" 
		exit 2
	fi	 

 
	rmexpiredbackups;

