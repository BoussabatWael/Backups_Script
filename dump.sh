#!/usr/bin/env bash

CONFIGFILE=/etc/mydumpadmin/settings.conf

source $CONFIGFILE

DATE_FORMAT='%d_%m_%Y'
CURRENT_DATE=$(date +"${DATE_FORMAT}")
CURRENT_TIME=$(date +"%A_%H_%M")
LOGFILENAME=$LOG_PATH/mydumpadmin-${CURRENT_DATE}-${CURRENT_TIME}.log
CREDENTIALS="--defaults-file=$CREDENTIAL_FILE"


[ ! -d $LOG_PATH ] && ${MKDIR} -p ${LOG_PATH}
echo "" > ${LOGFILENAME}
echo "<<<<<<   Backups Report :: `date +"%A_${DATE_FORMAT}"`  >>>>>>" >> ${LOGFILENAME}
echo "" >> ${LOGFILENAME}
echo "Type  :: Size   Filename" >> ${LOGFILENAME}


###### check config file 'settings.conf' ######
check_config(){
        [ ! -f $CONFIGFILE ] && close_on_error "Config file not found, make sure config file is correct"
}


### Make sure bins exists.. else close_on_error
check_cmds(){
        [ ! -x $GZIP ] && close_on_error "FILENAME $GZIP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQL ] && close_on_error "FILENAME $MYSQL does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQLDUMP ] && close_on_error "FILENAME $MYSQLDUMP does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $RM ] && close_on_error "FILENAME $RM does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MKDIR ] && close_on_error "FILENAME $MKDIR does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $MYSQLADMIN ] && close_on_error "FILENAME $MYSQLADMIN does not exists. Make sure correct path is set in $CONFIGFILE."
        [ ! -x $GREP ] && close_on_error "FILENAME $GREP does not exists. Make sure correct path is set in $CONFIGFILE."

	if [ $SFTP_ENABLE -eq 1 ]; then
		[ ! -x $SCP ] && close_on_error "FILENAME $SCP does not exists. Make sure correct path is set in $CONFIGFILE."
	fi
}


### Check if database connection is working...
check_mysql_connection(){
        ${MYSQLADMIN} ${CREDENTIALS} -h ${MYSQL_HOST} -P ${MYSQL_PORT} ping | ${GREP} 'alive'>/dev/null
        [ $? -eq 0 ] || close_on_error "Error: Cannot connect to MySQL Server. Make sure username and password setup correctly in $CONFIGFILE"
}


###### database backup ######
db_backup(){
        [ $VERBOSE -eq 1 ] && echo "*** Database backup ***"

        if [ "$DB_NAMES" == "ALL" ]; then
		DATABASES=`$MYSQL $CREDENTIALS -h $MYSQL_HOST -P $MYSQL_PORT -Bse 'show databases' | grep -Ev "^(Database|mysql|performance_schema|information_schema)"$`
        else
		DATABASES=$DB_NAMES
        fi

        db=""
        [ ! -d $BACKUPDIR ] && ${MKDIR} -p $BACKUPDIR
                [ $VERBOSE -eq 1 ] && echo "*** Dumping MySQL Database ***"
                mkdir -p ${LOCAL_BACKUP_DIR}/${CURRENT_DATE}

        for db in $DATABASES
        do
                FILE_NAME="${db}.${CURRENT_DATE}-${CURRENT_TIME}.sql.gz"
                FILE_PATH="${LOCAL_BACKUP_DIR}/${CURRENT_DATE}/"
                FILENAMEPATH="$FILE_PATH$FILE_NAME"

                [ $VERBOSE -eq 1 ] && echo -en "Database> $db... \n"
                ${MYSQLDUMP} ${CREDENTIALS} --single-transaction -h ${MYSQL_HOST} -P $MYSQL_PORT $db | ${GZIP} -9 > $FILENAMEPATH

                [ $VERBOSE -eq 1 ] && echo "*** Database backup size ***"
                echo "`du -sh ${FILENAMEPATH}`"

                [ $VERBOSE -eq 1 ] && echo "*** Saving database logs ***"
                echo "Database   :: `du -sh ${FILENAMEPATH}`"  >> ${LOGFILENAME}

                ##### ftp_backup #####
                [ $FTP_ENABLE -eq 1 ] && ftp_backup
                ##### sftp_backup #####
                [ $SFTP_ENABLE -eq 1 ] && sftp_backup

        done
        [ $VERBOSE -eq 1 ] && echo "*** Database backup completed ***"
        [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${FILE_PATH} ***"
}


###### folders - files backups ######
folder_file_backup(){
        if [ "$FOLDER_BACKUP" -eq 1 ]; then
                [ $VERBOSE -eq 1 ] && echo "*** Folder backup ***"

                [ $VERBOSE -eq 1 ] && echo "*** Copy local backup folder ***"
                cp -r $FOLDER_LOCAL_PATH ${FILE_PATH}

                [ $VERBOSE -eq 1 ] && echo "*** Folder backup size ***"
                echo "`du -sh ${FILE_PATH}${FOLDER_BACKUP_NAME}`"

                [ $VERBOSE -eq 1 ] && echo "*** Saving folder logs ***"
                echo "Folder   :: `du -sh ${FILE_PATH}${FOLDER_BACKUP_NAME}`"  >> ${LOGFILENAME}

                [ $VERBOSE -eq 1 ] && echo "*** Uploading backup folder to SFTP ***"
	        ${SCP} -r $FOLDER_LOCAL_PATH ${SFTP_USERNAME}@${SFTP_HOST}:${SFTP_UPLOAD_DIR}/
        else   
                [ $VERBOSE -eq 1 ] && echo "*** File backup ***"

        	[ $VERBOSE -eq 1 ] && echo "*** Copy local backup file ***"
                cp $FILE_LOCAL_PATH ${FILE_PATH}

                [ $VERBOSE -eq 1 ] && echo "*** File backup size ***"
                echo "`du -sh ${FILE_PATH}${FILE_BACKUP_NAME}`"

                [ $VERBOSE -eq 1 ] && echo "*** Saving file logs ***"
                echo "File   :: `du -sh ${FILE_PATH}${FILE_BACKUP_NAME}`"  >> ${LOGFILENAME}

        	[ $VERBOSE -eq 1 ] && echo "*** Uploading backup file to SFTP ***"
                ${SCP} -r $FILE_LOCAL_PATH ${SFTP_USERNAME}@${SFTP_HOST}:${SFTP_UPLOAD_DIR}/
        fi

        [ $VERBOSE -eq 1 ] && echo "*** Folder/File Backup completed ***"
        [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${FILE_PATH} ***"

}


###### the entire server backups ######
entire_server_backup(){
        if [ "$SERVER_BACKUP" -eq 1 ]; then
                [ $VERBOSE -eq 1 ] && echo "*** Entire server backup ***"

                [ $VERBOSE -eq 1 ] && echo "*** Creating archive file ***"
                day=$(date +%A_%H_%M)
                hostname=$(hostname -s)
                zip -r $hostname.$CURRENT_DATE-$day.zip $FOLDERS_LOCAL_PATH

                [ $VERBOSE -eq 1 ] && echo "*** Copy local backup archive  ***"
                cp -r "$hostname.$CURRENT_DATE-$day.zip" ${FILE_PATH}

                [ $VERBOSE -eq 1 ] && echo "*** Server backup size ***"
                echo "`du -sh "${FILE_PATH}$hostname.$CURRENT_DATE-$day.zip"`"

                [ $VERBOSE -eq 1 ] && echo "*** Saving server logs ***"
                echo "Server   :: `du -sh "${FILE_PATH}$hostname.$CURRENT_DATE-$day.zip"`"  >> ${LOGFILENAME}

                [ $VERBOSE -eq 1 ] && echo "*** Uploading backup archive to SFTP ***"
	        ${SCP} -r "$hostname.$CURRENT_DATE-$day.zip" ${SFTP_USERNAME}@${SFTP_HOST}:${SFTP_UPLOAD_DIR}/

                [ $VERBOSE -eq 1 ] && echo "*** Entire Server Backup Completed ***"
                [ $VERBOSE -eq 1 ] && echo "*** Check backup files in ${FILE_PATH} ***"

        else   
        	[ $VERBOSE -eq 1 ] && echo "*** Server backup is disabled ***"
                [ $VERBOSE -eq 1 ] && echo "*** Bye ***"

        fi
}


### close_on_error on demand with message ###
close_on_error(){
        echo "$@"
        exit 99
}


### Copy backup files to ftp server
ftp_backup(){
[ $VERBOSE -eq 1 ] && echo "*** Uploading backup file to FTP ***"
ftp -n $FTP_SERVER << EndFTP
user "$FTP_USERNAME" "$FTP_PASSWORD"
binary
hash
cd $FTP_UPLOAD_DIR
lcd $FILE_PATH
put "$FILE_NAME"
bye
EndFTP
}


### Copy backup files to sftp server
sftp_backup(){
	[ $VERBOSE -eq 1 ] && echo "*** Uploading backup file to SFTP ***"
	cd ${FILE_PATH}
	${SCP} -P ${SFTP_PORT}  "$FILE_NAME" ${SFTP_USERNAME}@${SFTP_HOST}:${SFTP_UPLOAD_DIR}/
        
#################################################################################
#	[ $VERBOSE -eq 1 ] && echo "*** Uploading backup file to SFTP ***"
#       #file_size = `du -sh ${FILENAMEPATH}`
#       #free_space = `du -sh /dev/vda1`
#       if [ $free_space > $file_size];then
#	       cd ${FILE_PATH}
#	       ${SCP} -P ${SFTP_PORT}  "$FILE_NAME" ${SFTP_USERNAME}@${SFTP_HOST}:${SFTP_UPLOAD_DIR}/
#       else    
#	       [ $VERBOSE -eq 1 ] && echo "*** Can't upload backup, file size too large ***"
#       fi
}


### Remove older backups
clean_old_backups(){
	[ $VERBOSE -eq 1 ] && echo "*** Removing old backups ***"
	DBDELDATE=`date +"${DATE_FORMAT}" --date="${BACKUP_RETAIN_DAYS} days ago"`
	if [ ! -z ${LOCAL_BACKUP_DIR} ]; then
		cd ${LOCAL_BACKUP_DIR}
		if [ ! -z ${DBDELDATE} ] && [ -d ${DBDELDATE} ]; then
			rm -rf ${DBDELDATE}
		fi
	fi
}


### Send report email
send_report(){
	if [ $SENDEMAIL -eq 1 ]; then
	        [ $VERBOSE -eq 1 ] && echo "*** Sending report ***"
	        cat ${LOGFILENAME} | mail -vs "Backups report for `date +"%A_${DATE_FORMAT}"`" ${EMAILTO}
	fi
}


### main ####
check_config
check_cmds
check_mysql_connection
db_backup
folder_file_backup
entire_server_backup
clean_old_backups
send_report
