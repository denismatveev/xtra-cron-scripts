#!/bin/bash
set -e
#set -x

######################
##### Settings #######
DBUSER=backup-user
DBPASS=changeme
BACKUPDIR=/mnt/debian/backups
THREADS=4
NUMBEROFFULLBACKUPS=1
NUMBERINCRBACKUPS=3
LOCKFILE=/var/run/cronbackup.lock
###########################
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
NUMBEROFINCREMENTALBACKUPSINOLDESTFULL=$(ls -1 "$BACKUPDIR"/"$OLDESTBACKUP"/INC 2>/dev/null| wc -l)
NUMBEROFCURRENTINCRBACKUPS=$(ls -1 "$BACKUPDIR"/"$CURRENTFULLBACKUP"/INC 2>/dev/null | wc -l)
########################
makefull()
{
	$PWD/xb-backup-incremental.sh -r "$BACKUPDIR" -u  "$DBUSER" -p "$DBPASS" --backup-threads="$THREADS" 

	return 0
}

makeincremental()
{

	$PWD/xb-backup-incremental.sh -r "$BACKUPDIR" -u  "$DBUSER" -p "$DBPASS" --increment --backup-threads="$THREADS" 

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

