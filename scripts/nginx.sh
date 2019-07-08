#!/bin/bash
PREFIX='nginx'
URL='http://127.0.0.1/status'
CURL='/usr/bin/curl'
TMP='/tmp/nginx-ping.tmp'
SENDER='/usr/bin/zabbix_sender'
CONFIG='/etc/zabbix/zabbix_agentd.conf'
SERVER='cloud2.floralfrog.com'
if [ ! -x ${CURL} ]
then echo Seems, path to curl is incorrect or not installed. && exit 1
elif [ ! -x ${SENDER} ]
then echo Seems, path to zabbix_sender is incorrect or not installed. && exit 1
elif [ ! -f ${CONFIG} ]
then echo Seems, path to zabbix_agentd.conf is incorrect && exit 1
fi
read -a s <<< `(time ${CURL} --no-keepalive -s -m 9 ${URL}) 2>$TMP`
if [[ "${s[7]}" =~ ([0-9]+) ]]
then
echo "\
- ${PREFIX}.accepts ${s[7]}
- ${PREFIX}.connections.active ${s[2]}
- ${PREFIX}.connections.reading ${s[11]}
- ${PREFIX}.connections.waiting ${s[15]}
- ${PREFIX}.connections.writing ${s[13]}
- ${PREFIX}.handled ${s[8]}
- ${PREFIX}.requests ${s[9]}" | ${SENDER} -vv -c ${CONFIG} -s ${SERVER} -i - >/dev/null 2>&1
awk '/real/{split($2,a,"[ms]");print a[1]*60+a[2];}' $TMP
else
echo '-0.001'
fi
rm $TMP
exit 0
