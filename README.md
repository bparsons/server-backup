# Simple Server Backup Script 

This script will backup directories, web sites, mysql and mongodb databases, optionally encrypt them and send them to a remote server via rsync or Amazon S3

## Usage

server-backup.conf needs to be customized and placed in one of the common system configuration directories:

  - /etc/default
  - /etc/conf.d
  - /etc/init.d 

The configuration file uses 1 and 0 to toggle certain features on and off. Please see the file itself for documentation of the various flags and fields.

Due to the sensitive nature of some of the configuration fields, it is recommended that the file permissions be only readable by root for the configuration file (chmod 600).

For automated / unattended usage, ssh keys need to be in place on the remote server. I've included a basic crontab file that you can customize with the location of the backup script.

**The Amazon S3 integration requires s3cmd / s3tools to be installed**

