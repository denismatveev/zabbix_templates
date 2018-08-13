#!/bin/bash
# script checks in directory ${BACKUPDIR} if this dir contains subdirs named like MySQL/2018-08-12
# Compares if number of hosts is equal number of dirs above with creation time less 24 hours ago
# Returns 0 if everything is OK and 1 if fails(number of hosts is not equal dir MySQL/${date}

BACKUPDIR=/backups/
HOSTNUM=$(ls -1 ${BACKUPDIR} | wc -l)
BACKUPNUM=$(find ${BACKUPDIR} -type d -mtime -1 -regextype posix-egrep -regex '^.*MySQL/20[0-9]{2}-[0-9]{2}-[0-9]{2}$' | wc -l)
[[ ${HOSTNUM} -le ${BACKUPNUM} ]] && ret=0 || ret=1
echo $ret
