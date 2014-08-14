#!/bin/bash
set -e
set -x

######################
##### Settings ######################
DBUSER=backup-user
DBPASS=changeme
BACKUPDIR=/mnt/debian/backups
THREADS=4
NUMBEROFFULLBACKUPS=3
NUMBERINCRBACKUPS=4 #+1 
LOCKFILE=/var/run/cronbackup.lock
MY=/var/lib/mysql
NOW=$(date +%Y%m%d-%H%M)
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
# lbackup dir
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
#	$PWD/xb-backup-incremental.sh -r "$BACKUPDIR" -u  "$DBUSER" -p "$DBPASS" --backup-threads="$THREADS" 
    TARGET="$BACKUPDIR"/"$NOW"/"$NOW"-0
    mkdir -p "$TARGET"
    xtrabackup --backup --target-dir="$TARGET" --datadir="$MY" --parallel="$THREADS" #make full backups
    rsync -rv --exclude=ibdata* --exclude=xtrabackup_* "$MY" "$TARGET"
    chown mysql: "$TARGET"
	return 0
}

makeincremental()
{

#	$PWD/xb-backup-incremental.sh -r "$BACKUPDIR" -u  "$DBUSER" -p "$DBPASS" --increment --backup-threads="$THREADS" 
    i=$(ls -1t "$BACKUPDIR"/"$CURRENTFULLBACKUP"/ 2>/dev/null | head -n1 | cut -d"-" -f3) # number of incremental backup
    PREVIOUSBACKUP=$(ls -1t "$BACKUPDIR"/"$CURRENTFULLBACKUP" | head -n1)
    let i=$i+1
    TARGET="$BACKUPDIR"/"$CURRENTFULLBACKUP"/"$NOW"-"$i"
    mkdir -p "$TARGET"
    xtrabackup --backup --target-dir="$TARGET" --datadir="$MY" --incremental-basedir="$BACKUPDIR"/"$CURRENTFULLBACKUP"/"$PREVIOUSBACKUP" --parallel="$THREADS"
    #tar -cf 
    rsync -rv --exclude=ibdata* --exclude=xtrabackup_* "$MY" "$TARGET"
    
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

