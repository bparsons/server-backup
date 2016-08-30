#!/bin/bash

########
##
## Server Backup Script
## Brian Parsons <brian@pmex.com>
##
## Unifed backup script to backup server directories, web sites, databases and config files to a remote server or Amazon S3
##
## CHANGELOG
## ---------
## 13-o1-o7 - bcp - initial script
## 13-o1-13 - bcp - added NICE variable and nice command to tar, bzip2 and gpg commands
## 13-o1-17 - bcp - fixed logic on keeping or removing local copies
## 13-o2-22 - bcp - change compression to xz, filenames are 0-1 based on current day being even or odd
## 13-o2-23 - bcp - addded bandwidth limit for rsync, human readable byte counts, total, and script timing
## 13-o2-25 - bcp - update total time to HH:MM:SS format
## 13-o2-26 - bcp - BINARYDPART configuration flag for Sun-Sat vs 1 or 0 backup filenames
## 14-o1-20 - bcp - convert remaining backticks to bash $() format, change strongspace references to remote server
## 14-o5-o8 - bcp - create functions for repetitive tasks EncryptFile and RsyncFile
## 14-o5-o8 - bcp - autodetect config location
## 14-o5-o8 - bcp - add support for MongoDB
## 14-o5-15 - bcp - compress mysql dumps inline instead of creating the dump file and then compressing
## 15-1o-22 - bcp - sync files to Amazon S3
## 15-11-o2 - bcp - Add flag for using Amazon S3 and SendFile function to route accordingly
## 16-o8-25 - bcp - Add postgresql support
##
#

########
##
## INITIALIZE CONFIG
##
## Config Location
##
## /etc/conf.d - Arch Linux \(^-^)/
## /etc/default - CentOS (-.-) Ubuntu/Debian (v_v)
## /etc/init.d - What planet are you from? (o.O)
##                                                                                                                                      
#                                                                                                                                       
                                                                                                                                        
## Defaults                                                                                                                             
BINARYDPART=0
DOMONGO=0
DOMYSQL=0
DOPSQL=0
DOWWW=0
ENCRYPTFILES=0
KEEPLOCALENC=0
USES3=0

CONFIGLOCATIONS="/etc/conf.d /etc/default /etc/init.d"
for conf in ${CONFIGLOCATIONS}
do
        [ -e $conf/server-backup.conf ] && { echo "Found config in $conf"; source $conf/server-backup.conf; }
done

########
##
## AUTOMATIC VARS - DO NOT ADJUST THESE
#

SERVERNAME=$(hostname)
SHORTHOSTNAME=$(hostname | awk -F. '{print$1}')
SCRIPTSTART=$(date +%s.%N)
totalbytes=0


########
##
## FUNCTIONS
#

#
# EncryptFile - encrypts given file
#
# @param string $1 - the file path/name to encrypt
#
function EncryptFile() {

        if [ "$1" ]
        then
                echo ${EPASSWD}| nice -${NICE} gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 $1
        else 
                echo "function EncryptFile requires parameter (file path/name)"
        fi
}

#
# HumanReadableBytes - converts bytes to KB, MB or GB
#
function HumanReadableBytes() {

        awk -v sum="$1" 'BEGIN {
                                                hum[1024^3]="GB";
                                                hum[1024^2]="MB";
                                                hum[1024]="KB";
                                                for (x=1024^3; x>=1024; x/=1024) {
                                                        if (sum>=x) {
                                                                printf "%.2f%s\n",sum/x,hum[x]; break;
                                                        }
                                                }
                                                if (sum<1024) print "1KB";
                                        }'

}

#
# RsyncFile - send file to remote server
#
# @param string $1 - the file path/name to sync
# @param string $2 (optional) - the subdirectory to sync to
#
function RsyncFile() {

        if [ "$1" ]
        then
                if [ "$2" ]
                then
                        rsync -a --bwlimit $BWLIMIT "$1" ${REMOTEUSER}@${REMOTESERVER}:${REMOTEROOTPATH}/$2/
                else
                        rsync -a --bwlimit $BWLIMIT "$1" ${REMOTEUSER}@${REMOTESERVER}:${REMOTEROOTPATH}/
                fi
        else
                echo "function RsyncFile requires parameter (file path/filename)"
        fi
}


#
# S3SyncFile - Send file to Amazon S3
#
# @param string $1 - the file path/name to send to Amazon S3
# @param string $2 (optional) - the subfolder / prefix
#
function S3SyncFile() {

    if [ "$1" ]
    then

        if [ "$2" ]
        then
                s3cmd --access_key=${S3ACCESSKEY} --secret_key=${S3SECRETKEY} put "$1" s3://${S3BUCKET}/$2/
        else
                s3cmd --access_key=${S3ACCESSKEY} --secret_key=${S3SECRETKEY} put "$1" s3://${S3BUCKET}/
        fi        
 
    fi
}

#
# SendFile - Determine destination and send file
#
# @param string $1 - the file/path name to send
# @param string $2 (optional) - the subdirectory to send to
#
function SendFile() {

    if [ ${USES3} -gt 0 ]
    then
        if [ "$2" ]
        then
            S3SyncFile "$1" "$2"
        else
            S3SyncFile "$1" 
        fi
    else
        if [ "$2" ]
        then
            RsyncFile "$1" "$2"
        else
            RsyncFile "$1"
        fi
    fi
}


##
## START MAIN 
##

if [ ${BINARYDPART} -gt 0 ]
then
        julianday=$(date +"%j")
        # Will be 0 or 1 based on julian day even or odd
        dpart=$(expr $julianday % 2)
else
        dpart=$(date +"%a")
fi
echo "Backup ${dpart} Started on ${SERVERNAME} $(date)"

if [ -d ${BACKUPDIR} ]
then
        echo "${BACKUPDIR} found"
else
        echo "Creating ${BACKUPDIR}..."
        mkdir ${BACKUPDIR}
        echo "Done"
fi

echo ""

##
## SERVER FILES PROCESSING
##

echo "Starting server files backup $(date)"
for dir in ${SERVERTOBACKUP}
do
        if [ -d ${dir} ]
        then
                echo -n "Packing ${dir}..."
                bfile=$(echo ${dir} | sed 's/\//_/g')
                cd ${dir}; nice -${NICE} tar --same-owner -cJpf ${BACKUPDIR}/${bfile}-${dpart}.tar.xz *
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                    echo -n "encrypting..."
                    EncryptFile ${BACKUPDIR}/${bfile}-${dpart}.tar.xz
                    filesize=$(du -b ${BACKUPDIR}/${bfile}-${dpart}.tar.xz.gpg | awk '{print$1}')
                else
                    filesize=$(du -b ${BACKUPDIR}/${bfile}-${dpart}.tar.xz | awk '{print$1}')
                fi
                totalbytes=$(expr $totalbytes + $filesize)
                humanprint=$(HumanReadableBytes $filesize)
                echo -n "syncing $humanprint to remote server..."
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                    SendFile ${BACKUPDIR}/${bfile}-${dpart}.tar.xz.gpg ${REMOTESERVERDIR}/${HOSTNAME}
                else
                    SendFile ${BACKUPDIR}/${bfile}-${dpart}.tar.xz ${REMOTESERVERDIR}/${HOSTNAME}

                fi
                if [ ${KEEPLOCALCOPY} -eq 0 ]
                then
                        echo -n "removing local copy..."
                        rm -f ${BACKUPDIR}/${bfile}-${dpart}.tar.xz
                fi
                if [ ${KEEPLOCALENC} -eq 0 ]
                then
                        echo -n "removing local encrypted copy..."
                        rm -f ${BACKUPDIR}/${bfile}-${dpart}.tar.xz.gpg
                fi
                echo "Done."
        else
                echo "Skipping ${dir} (directory not found)"
        fi
done

##
## Web Sites Processing
##

if [ $DOWWW -gt 0 ]
then
        echo "Starting WWW backup $(date)"

        if [ -d ${BACKUPDIR}/www ]
        then
                echo "${BACKUPDIR}/www found"
        else
                echo "Creating ${BACKUPDIR}/www..."
                mkdir ${BACKUPDIR}/www
        echo "Done"
        fi

        WWWDIRS=$(find ${WWWDIR}/* -maxdepth 0 -type d -print | while read inl; do echo "${inl}" | awk -F/ '{printf("%s ",$4)}'; done)

        for wdir in ${WWWDIRS}
        do
                echo -n "Packing ${wdir}..."
                bfile="$(echo ${wdir} | sed 's/\///g')"
                cd ${WWWDIR}/${wdir}; nice -${NICE} tar --same-owner -cJpf ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz *
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        echo -n "encrypting..."
                        EncryptFile ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz
                        filesize=$(du -b ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz.gpg | awk '{print$1}')
                        if [ ${KEEPLOCALENC} -gt 0 ]
                        then
                                rm -f ${BACKUPDIR}/www/${bfile}-${dpart}.tar.xz
                        fi
                else
                        filesize=$(du -b ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz  | awk '{print$1}')
                fi
                totalbytes=$(expr $totalbytes + $filesize)
                humanprint=$(HumanReadableBytes $filesize)
                echo -n "syncing $humanprint to remote server..."
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        SendFile ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz.gpg ${REMOTESITEDIR}
                else
                        SendFile ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz ${REMOTESITEDIR}
                fi
                if [ ${KEEPLOCALCOPY} -eq 0 ]
                then
                        echo -n "removing local copy..."
                        rm -f ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz
                fi
                if [ ${KEEPLOCALENC} -eq 0 ]
                then
                        echo -n "removing local encrypted copy..."
                        rm -f ${BACKUPDIR}/www/${bfile}-${dpart}-${SHORTHOSTNAME}.tar.xz.gpg
                fi
                echo "Done."

        done
fi

##
## MySQL Processing
##

if [ ${DOMYSQL} -gt 0 ]
then
        echo "Starting MySQL backup $(date)"

        if [ -d ${BACKUPDIR}/mysql ]
        then
                echo "${BACKUPDIR}/mysql found"
        else
                echo "Creating ${BACKUPDIR}/mysql..."
                mkdir ${BACKUPDIR}/mysql
                echo "Done"
        fi


        DATABASES=$(find ${MYSQLDIR}/* -type d -print | while read inl; do echo "${inl}" | awk -F/ '{printf("%s ",$5)}'; done)

        for db in ${DATABASES}
        do
                if [ -e ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2 ]
                then
                        rm -f ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2
                fi
                echo -n "Dumping and Packing ${db}..."
                /usr/bin/mysqldump ${db} | nice -${NICE} bzip2 -9 -c > ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        echo -n "encrypting..."
                        EncryptFile ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2
                        filesize=$(du -b ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2.gpg | awk '{print$1}')
                        if [ ${KEEPLOCALENC} -gt 0 ]
                        then
                                rm -f ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2
                        fi
                else
                        filesize=$(du -b ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2 | awk '{print$1}')
                fi
                totalbytes=$(expr $totalbytes + $filesize)
                humanprint=$(HumanReadableBytes $filesize)
                echo -n "syncing $humanprint to remote server..."
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        SendFile ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2.gpg ${REMOTEDBDIR}
                else
                        SendFile ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2 ${REMOTEDBDIR}
                fi
                if [ ${KEEPLOCALCOPY} -eq 0 ]
                then
                        echo -n "removing local copy..."
                        rm -f ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2
                fi
                if [ ${KEEPLOCALENC} -eq 0 ]
                then
                        echo -n "removing local encrypted copy..."
                        rm -f ${BACKUPDIR}/mysql/${db}.mysql-${dpart}-${SHORTHOSTNAME}.bz2.gpg
                fi
                echo "Done."

        done
fi

##
## MongoDB Processing
##
if [ ${DOMONGO} -gt 0 ]
then

        echo "Starting MongoDB backup $(date)"

        if [ -d ${BACKUPDIR}/mongodb ]
        then
                echo "${BACKUPDIR}/mongodb found"
        else
                echo "Creating ${BACKUPDIR}/mongodb..."
                mkdir ${BACKUPDIR}/mongodb
                echo "Done"
        fi

        cd ${BACKUPDIR}/mongodb
        echo -n "Dumping..."
        mongodump
        COLLECTIONS=$(find ${BACKUPDIR}/mongodb/dump/* -type d -print | while read inl; do echo "${inl}" | awk -F/ '{printf("%s ",$5)}'; done)
        for collection in ${COLLECTIONS}
        do
                echo -n "Packing $collection..."
                nice -${NICE} tar --same-owner -cJpf ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz ${BACKUPDIR}/mongodb/dump/$collection/*
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        echo -n "encrypting..."
                        EncryptFile ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz
                        filesize=$(du -b ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz.gpg | awk '{print$1}')
                        if [ ${KEEPLOCALENC} -gt 0 ]
                        then
                                rm -f ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz
                        fi
                else
                        filesize=$(du -b ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz | awk '{print$1}')
                fi
                totalbytes=$(expr $totalbytes + $filesize)
                echo -n "syncing $humanprint to remote server..."
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        SendFile ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz.gpg ${REMOTEMONGODIR}
                else
                        SendFile ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz ${REMOTEMONGODIR}
                fi
                if [ ${KEEPLOCALCOPY} -eq 0 ]
                then
                        echo -n "removing local copy..."
                        rm -f ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz
                fi
                if [ ${KEEPLOCALENC} -eq 0 ]
                then
                        echo -n "removing local encrypted copy..."
                        rm -f ${BACKUPDIR}/mongodb/${collection}-${dpart}.tar.xz.gpg
                fi
                echo "Done."
        done
fi

##
## Postgresql Processing
##

if [ ${DOPSQL} -gt 0 ]
then
        echo "Starting Postgresql backup $(date)"

        if [ -d ${BACKUPDIR}/psql ]
        then
                echo "${BACKUPDIR}/psql found"
                chown -R postgres ${BACKUPDIR}/psql
        else
                echo "Creating ${BACKUPDIR}/psql..."
                mkdir ${BACKUPDIR}/psql
                chown -R postgres ${BACKUPDIR}/psql
                echo "Done"
        fi

        DATABASES=$(su -c "psql -c 'SELECT datname FROM pg_database'" postgres | grep -v datname | grep -v "\-\-\-\-\-\-" | grep -v "rows)")

        for db in ${DATABASES}
        do
                if [ -e ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2 ]
                then
                        rm -f ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2
                fi
                echo -n "Dumping and Packing ${db}..."
                su -c "/usr/bin/pg_dump ${db}" postgres | nice -${NICE} bzip2 -9 -c > ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        echo -n "encrypting..."
                        EncryptFile ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2
                        filesize=$(du -b ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2.gpg | awk '{print$1}')
                        if [ ${KEEPLOCALENC} -gt 0 ]
                        then
                                rm -f ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2
                        fi
                else
                        filesize=$(du -b ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2 | awk '{print$1}')
                fi
                totalbytes=$(expr $totalbytes + $filesize)
                humanprint=$(HumanReadableBytes $filesize)
                echo -n "syncing $humanprint to remote server..."
                if [ ${ENCRYPTFILES} -gt 0 ]
                then
                        SendFile ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2.gpg ${REMOTEDBDIR}
                else
                        SendFile ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2 ${REMOTEDBDIR}
                fi
                if [ ${KEEPLOCALCOPY} -eq 0 ]
                then
                        echo -n "removing local copy..."
                        rm -f ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2
                fi
                if [ ${KEEPLOCALENC} -eq 0 ]
                then
                        echo -n "removing local encrypted copy..."
                        rm -f ${BACKUPDIR}/psql/${db}.psql-${dpart}-${SHORTHOSTNAME}.bz2.gpg
                fi
                echo "Done."

        done
fi


#
# Print Totals
#

humanprint=$(HumanReadableBytes $totalbytes)
SCRIPTEND=$(date +%s.%N)
SCRIPTEXECTIME=$(echo "$SCRIPTEND - $SCRIPTSTART" | bc)
humantime=$(echo $SCRIPTEXECTIME | awk '{printf "%.2d:%.2d:%.2d",$1/(60*60),$1%(60*60)/60,$1%60}')
echo "Backup ${dpart} Finished $(date). $humanprint synced to remote server ${REMOTESERVER}. Total Time: $humantime."
