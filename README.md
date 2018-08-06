# MySQL zabbix template
Based on https://share.zabbix.com/databases/mysql/template-mysql-800-items</br>
But I added key mysql.ping and two triggers: mysql is alive and checking if MySQL replication is running

To import template create 
Valuemappings:
MySQL - Status
0 ⇒ No
1 ⇒ Yes</br>
It is possible in zabbix GUI `Administrtion -> General -> Value mappings -> create Value Map`


On a server that is monitored
place file `check_mysql.pl` in `/etc/zabbix/scripts`
Also place `userparameter_mysql_check.conf` in directory `/etc/zabbix/zabbix_agentd.d/`</br>
Restart the zabbix-agent:
<pre>
systemctl restart zabbix-agent
</pre>
